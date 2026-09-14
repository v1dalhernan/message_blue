import 'dart:async';

import '../models/chat_message.dart';
import 'nearby_event.dart';
import 'nearby_transport.dart';
import 'secure_session.dart';

class DemoNearbyTransport implements NearbyTransport {
  final StreamController<NearbyEvent> _events =
      StreamController<NearbyEvent>.broadcast();
  final Map<String, _DemoSecureChannel> _channels = {};
  final Map<String, String> _peerNames = const {
    'demo-ana': 'Ana · Demo',
    'demo-taller': 'Nodo Taller · Demo',
  };

  bool _running = false;
  String _displayName = '';
  List<int>? lastWirePayload;

  @override
  bool get isSupported => true;

  @override
  bool get isDemo => true;

  @override
  Stream<NearbyEvent> get events => _events.stream;

  @override
  Future<void> start(String displayName) async {
    _running = true;
    _displayName = displayName;
    await Future<void>.delayed(const Duration(milliseconds: 250));
    if (!_running) return;
    for (final peer in _peerNames.entries) {
      _events.add(PeerFound(endpointId: peer.key, name: peer.value));
    }
  }

  @override
  Future<void> requestConnection(String endpointId, String displayName) async {
    final name = _peerNames[endpointId];
    if (name == null) throw StateError('El par de demostración no existe.');
    await Future<void>.delayed(const Duration(milliseconds: 250));
    if (!_running) return;
    _events.add(
      ConnectionApprovalRequired(
        endpointId: endpointId,
        name: name,
        authenticationToken: endpointId == 'demo-ana' ? '4821' : '7319',
        isIncoming: false,
      ),
    );
  }

  @override
  Future<void> acceptConnection(String endpointId) async {
    final channel = await _DemoSecureChannel.create();
    _channels[endpointId]?.dispose();
    _channels[endpointId] = channel;
    _events.add(
      ConnectionChanged(
        endpointId: endpointId,
        outcome: ConnectionOutcome.connected,
      ),
    );
    await Future<void>.delayed(const Duration(milliseconds: 300));
    if (_running) _events.add(SecureChannelReady(endpointId));
  }

  @override
  Future<void> rejectConnection(String endpointId) async {
    _events.add(
      ConnectionChanged(
        endpointId: endpointId,
        outcome: ConnectionOutcome.rejected,
      ),
    );
  }

  @override
  Future<void> disconnect(String endpointId) async {
    _channels.remove(endpointId)?.dispose();
    _events.add(
      ConnectionChanged(
        endpointId: endpointId,
        outcome: ConnectionOutcome.disconnected,
      ),
    );
  }

  @override
  Future<void> sendMessage(ChatMessage message) async {
    final channel = _channels[message.endpointId];
    if (channel == null) throw StateError('El canal cifrado no está listo.');

    final encrypted = await channel.encryptFromLocal(message.toPayload());
    lastWirePayload = encrypted;
    final remoteClearText = await channel.decryptAtRemote(encrypted);
    ChatMessage.fromPayload(endpointId: _displayName, bytes: remoteClearText);

    await Future<void>.delayed(const Duration(milliseconds: 450));
    if (!_running) return;
    final now = DateTime.now();
    final reply = ChatMessage(
      id: 'demo-${now.microsecondsSinceEpoch}',
      endpointId: message.endpointId,
      author: _peerNames[message.endpointId] ?? 'Par demo',
      text: 'Mensaje recibido y descifrado correctamente.',
      sentAt: now,
      direction: MessageDirection.outgoing,
    );
    final encryptedReply = await channel.encryptFromRemote(reply.toPayload());
    final localClearText = await channel.decryptAtLocal(encryptedReply);
    _events.add(
      MessageReceived(
        ChatMessage.fromPayload(
          endpointId: message.endpointId,
          bytes: localClearText,
        ),
      ),
    );
  }

  @override
  Future<void> stop() async {
    _running = false;
    for (final channel in _channels.values) {
      channel.dispose();
    }
    _channels.clear();
  }

  @override
  Future<void> dispose() async {
    await stop();
    await _events.close();
  }
}

class _DemoSecureChannel {
  _DemoSecureChannel(this.local, this.remote);

  final SecureSession local;
  final SecureSession remote;

  static Future<_DemoSecureChannel> create() async {
    final local = await SecureSession.create();
    final remote = await SecureSession.create();
    await Future.wait([
      local.establish(remote.publicKeyBytes),
      remote.establish(local.publicKeyBytes),
    ]);
    return _DemoSecureChannel(local, remote);
  }

  Future<List<int>> encryptFromLocal(List<int> bytes) => local.encrypt(bytes);

  Future<List<int>> decryptAtRemote(List<int> bytes) => remote.decrypt(bytes);

  Future<List<int>> encryptFromRemote(List<int> bytes) => remote.encrypt(bytes);

  Future<List<int>> decryptAtLocal(List<int> bytes) => local.decrypt(bytes);

  void dispose() {
    local.dispose();
    remote.dispose();
  }
}
