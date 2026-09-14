import 'dart:async';

import 'package:flutter/foundation.dart';

import 'models/chat_message.dart';
import 'models/nearby_peer.dart';
import 'nearby/nearby_event.dart';
import 'nearby/nearby_transport.dart';

class ChatController extends ChangeNotifier {
  ChatController(this._transport) {
    _subscription = _transport.events.listen(_handleEvent);
  }

  final NearbyTransport _transport;
  late final StreamSubscription<NearbyEvent> _subscription;
  final Map<String, NearbyPeer> _peers = {};
  final Map<String, List<ChatMessage>> _messages = {};

  bool _isRunning = false;
  bool _isBusy = false;
  String _displayName = '';
  String? _errorMessage;

  bool get isSupported => _transport.isSupported;
  bool get isDemo => _transport.isDemo;
  bool get isRunning => _isRunning;
  bool get isBusy => _isBusy;
  String get displayName => _displayName;
  String? get errorMessage => _errorMessage;

  List<NearbyPeer> get peers {
    final result = _peers.values.toList();
    result.sort((a, b) {
      if (a.isConnected != b.isConnected) return a.isConnected ? -1 : 1;
      return a.name.toLowerCase().compareTo(b.name.toLowerCase());
    });
    return result;
  }

  NearbyPeer? peerById(String endpointId) => _peers[endpointId];

  List<ChatMessage> messagesFor(String endpointId) =>
      List.unmodifiable(_messages[endpointId] ?? const []);

  Future<bool> start(String rawDisplayName) async {
    final name = rawDisplayName.trim();
    if (name.isEmpty) {
      _setError('Escribe un nombre para identificar este dispositivo.');
      return false;
    }

    _isBusy = true;
    _errorMessage = null;
    notifyListeners();
    try {
      await _transport.start(name);
      _displayName = name;
      _isRunning = true;
      return true;
    } catch (error) {
      _setError(error.toString());
      return false;
    } finally {
      _isBusy = false;
      notifyListeners();
    }
  }

  Future<void> stop() async {
    _isBusy = true;
    _errorMessage = null;
    notifyListeners();
    try {
      await _transport.stop();
      _isRunning = false;
      _peers.clear();
      _messages.clear();
    } catch (error) {
      _setError(error.toString());
    } finally {
      _isBusy = false;
      notifyListeners();
    }
  }

  Future<void> connect(String endpointId) async {
    final peer = _peers[endpointId];
    if (peer == null) return;

    _peers[endpointId] = peer.copyWith(status: PeerConnectionStatus.connecting);
    _errorMessage = null;
    notifyListeners();
    try {
      await _transport.requestConnection(endpointId, _displayName);
    } catch (error) {
      _peers[endpointId] = peer.copyWith(status: PeerConnectionStatus.failed);
      _setError(error.toString());
    }
  }

  Future<void> approve(String endpointId) async {
    try {
      await _transport.acceptConnection(endpointId);
      final peer = _peers[endpointId];
      if (peer != null) {
        _peers[endpointId] = peer.copyWith(
          status: PeerConnectionStatus.connecting,
        );
      }
      notifyListeners();
    } catch (error) {
      _setError(error.toString());
    }
  }

  Future<void> reject(String endpointId) async {
    try {
      await _transport.rejectConnection(endpointId);
      _updatePeerStatus(endpointId, PeerConnectionStatus.rejected);
    } catch (error) {
      _setError(error.toString());
    }
  }

  Future<void> disconnect(String endpointId) async {
    try {
      await _transport.disconnect(endpointId);
    } catch (error) {
      _setError(error.toString());
    }
  }

  Future<bool> send(String endpointId, String rawText) async {
    final text = rawText.trim();
    final peer = _peers[endpointId];
    if (text.isEmpty || peer == null || !peer.isConnected) return false;

    final now = DateTime.now();
    var message = ChatMessage(
      id: '${now.microsecondsSinceEpoch}-${_displayName.hashCode}',
      endpointId: endpointId,
      author: _displayName,
      text: text,
      sentAt: now,
      direction: MessageDirection.outgoing,
      delivery: MessageDelivery.sending,
    );
    final messages = _messages.putIfAbsent(endpointId, () => []);
    messages.add(message);
    notifyListeners();

    try {
      await _transport.sendMessage(message);
      message = message.copyWith(delivery: MessageDelivery.sent);
      _replaceMessage(endpointId, message);
      return true;
    } catch (error) {
      message = message.copyWith(delivery: MessageDelivery.failed);
      _replaceMessage(endpointId, message);
      _setError('No se pudo enviar el mensaje: $error');
      return false;
    }
  }

  void clearError() {
    if (_errorMessage == null) return;
    _errorMessage = null;
    notifyListeners();
  }

  void _handleEvent(NearbyEvent event) {
    switch (event) {
      case PeerFound():
        final existing = _peers[event.endpointId];
        _peers[event.endpointId] = NearbyPeer(
          id: event.endpointId,
          name: event.name,
          status: existing?.status ?? PeerConnectionStatus.discovered,
          authenticationToken: existing?.authenticationToken,
          isIncoming: existing?.isIncoming ?? false,
        );
      case PeerLost():
        final peer = _peers[event.endpointId];
        if (peer != null && !peer.isConnected) {
          _peers.remove(event.endpointId);
        }
      case ConnectionApprovalRequired():
        final existing = _peers[event.endpointId];
        _peers[event.endpointId] = NearbyPeer(
          id: event.endpointId,
          name: existing?.name ?? event.name,
          status: PeerConnectionStatus.awaitingApproval,
          authenticationToken: event.authenticationToken,
          isIncoming: event.isIncoming,
        );
      case ConnectionChanged():
        final status = switch (event.outcome) {
          ConnectionOutcome.connected => PeerConnectionStatus.securing,
          ConnectionOutcome.rejected => PeerConnectionStatus.rejected,
          ConnectionOutcome.failed => PeerConnectionStatus.failed,
          ConnectionOutcome.disconnected => PeerConnectionStatus.disconnected,
        };
        _updatePeerStatus(event.endpointId, status, shouldNotify: false);
      case SecureChannelReady():
        _updatePeerStatus(
          event.endpointId,
          PeerConnectionStatus.connected,
          shouldNotify: false,
        );
      case MessageReceived():
        _messages
            .putIfAbsent(event.message.endpointId, () => [])
            .add(event.message);
      case NearbyFailure():
        _errorMessage = event.message;
    }
    notifyListeners();
  }

  void _updatePeerStatus(
    String endpointId,
    PeerConnectionStatus status, {
    bool shouldNotify = true,
  }) {
    final peer = _peers[endpointId];
    if (peer == null) return;
    _peers[endpointId] = peer.copyWith(
      status: status,
      clearAuthenticationToken: status != PeerConnectionStatus.awaitingApproval,
    );
    if (shouldNotify) notifyListeners();
  }

  void _replaceMessage(String endpointId, ChatMessage replacement) {
    final messages = _messages[endpointId];
    if (messages == null) return;
    final index = messages.indexWhere(
      (message) => message.id == replacement.id,
    );
    if (index >= 0) messages[index] = replacement;
    notifyListeners();
  }

  void _setError(String message) {
    _errorMessage = message.replaceFirst('NearbySetupException: ', '');
    notifyListeners();
  }

  @override
  void dispose() {
    unawaited(_subscription.cancel());
    unawaited(_transport.dispose());
    super.dispose();
  }
}
