import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';

import 'core/identity/user_identity_service.dart';
import 'core/profile/user_profile_service.dart';
import 'core/storage/offline_mailbox_service.dart';
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
  final Set<String> _seenMessageIds = {};
  final StreamController<ChatMessage> _incomingMessageNotifications =
      StreamController<ChatMessage>.broadcast();
  final StreamController<String> _peerConnectionNotifications =
      StreamController<String>.broadcast();

  bool _isRunning = false;
  bool _isBusy = false;
  String _displayName = '';
  String? _errorMessage;

  bool get isSupported => _transport.isSupported;
  bool get isDemo => _transport.isDemo;
  bool get isRunning => _isRunning;
  bool get isBusy => _isBusy;
  String get displayName => _displayName.isNotEmpty ? _displayName : UserProfileService.instance.displayName;
  String get statusMessage => UserProfileService.instance.statusMessage;
  String? get errorMessage => _errorMessage;

  Stream<ChatMessage> get incomingMessageNotifications =>
      _incomingMessageNotifications.stream;
  Stream<String> get peerConnectionNotifications =>
      _peerConnectionNotifications.stream;

  String get localUniqueId => UserIdentityService.instance.fingerprint;
  String get personalPin => UserIdentityService.instance.getPersonalPin(displayName);
  String? get localAvatar => UserProfileService.instance.localAvatarBase64;
  int get offlineMailboxCount => OfflineMailboxService.instance.pendingCount;

  int get connectedCount => _peers.values.where((p) => p.isConnected).length;

  List<NearbyPeer> get connectedPeers =>
      _peers.values.where((p) => p.isConnected).toList();

  List<ChatMessage> get groupMessages =>
      List.unmodifiable(_messages[ChatMessage.groupEndpointId] ?? const []);

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

  int getUnreadCount(String endpointId) {
    final list = _messages[endpointId];
    if (list == null) return 0;
    return list
        .where((m) =>
            m.direction == MessageDirection.incoming &&
            m.delivery != MessageDelivery.read)
        .length;
  }

  UserProfileService get userProfileService => UserProfileService.instance;

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
      await UserIdentityService.instance.getUniqueId(name);
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

  Future<void> updateProfileAvatar(File imageFile) async {
    await UserProfileService.instance.setAvatarFromFile(imageFile);
    await _transport.sendProfileUpdate(
      avatar: UserProfileService.instance.localAvatarBase64,
    );
    notifyListeners();
  }

  void setPresetAvatar(String preset) {
    UserProfileService.instance.setPresetAvatar(preset);
    unawaited(_transport.sendProfileUpdate(
      avatar: UserProfileService.instance.localAvatarBase64,
    ));
    notifyListeners();
  }

  void updateDisplayName(String newName) {
    final trimmed = newName.trim();
    if (trimmed.isNotEmpty) {
      _displayName = trimmed;
      UserProfileService.instance.setDisplayName(trimmed);
      unawaited(_transport.sendProfileUpdate(
        name: trimmed,
      ));
      notifyListeners();
    }
  }

  void updateStatusMessage(String newStatus) {
    final trimmed = newStatus.trim();
    if (trimmed.isNotEmpty) {
      UserProfileService.instance.setStatusMessage(trimmed);
      notifyListeners();
    }
  }

  Future<void> markChatAsRead(String peerEndpointId) async {
    final list = _messages[peerEndpointId];
    if (list == null || list.isEmpty) return;

    bool updated = false;
    for (int i = 0; i < list.length; i++) {
      final msg = list[i];
      if (msg.direction == MessageDirection.incoming &&
          msg.delivery != MessageDelivery.read) {
        list[i] = msg.copyWith(delivery: MessageDelivery.read);
        updated = true;
        unawaited(
          _transport.sendReadReceipt(peerEndpointId, msg.id).catchError((e) {
            debugPrint('Error enviando confirmacion de lectura: $e');
          }),
        );
      }
    }
    if (updated) {
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
      _seenMessageIds.clear();
    } catch (error) {
      _setError(error.toString());
    } finally {
      _isBusy = false;
      notifyListeners();
    }
  }

  Future<void> connect(String endpointId, {String? enteredCode}) async {
    final peer = _peers[endpointId];
    if (peer == null) return;

    _peers[endpointId] = peer.copyWith(status: PeerConnectionStatus.connecting);
    _errorMessage = null;
    notifyListeners();
    try {
      await _transport.requestConnection(
        endpointId,
        _displayName,
        enteredCode: enteredCode,
      );
    } catch (error) {
      _peers[endpointId] = peer.copyWith(status: PeerConnectionStatus.failed);
      _setError(error.toString());
    }
  }

  Future<void> approve(String endpointId) async {
    final peer = _peers[endpointId];
    if (peer != null && !peer.isConnected) {
      _peers[endpointId] = peer.copyWith(
        status: PeerConnectionStatus.connecting,
      );
      notifyListeners();
    }
    try {
      await _transport.acceptConnection(endpointId);
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
    if (text.isEmpty) return false;

    final peer = _peers[endpointId];
    final isConnected = peer?.isConnected ?? false;
    final now = DateTime.now();

    var message = ChatMessage(
      id: '${now.microsecondsSinceEpoch}-${_displayName.hashCode}',
      endpointId: endpointId,
      author: _displayName,
      authorAvatar: UserProfileService.instance.localAvatarBase64,
      text: text,
      sentAt: now,
      direction: MessageDirection.outgoing,
      delivery: isConnected ? MessageDelivery.sending : MessageDelivery.inMailbox,
    );
    final messages = _messages.putIfAbsent(endpointId, () => []);
    messages.add(message);
    notifyListeners();

    if (!isConnected) {
      // Si el destinatario no está conectado, encolar en el buzón offline
      OfflineMailboxService.instance.queueMessage(message, endpointId);
      try {
        await _transport.sendMessage(message);
      } catch (_) {}
      return true;
    }

    try {
      await _transport.sendMessage(message);
      message = message.copyWith(delivery: MessageDelivery.sent);
      _replaceMessage(endpointId, message);
      return true;
    } catch (error) {
      message = message.copyWith(delivery: MessageDelivery.inMailbox);
      _replaceMessage(endpointId, message);
      OfflineMailboxService.instance.queueMessage(message, endpointId);
      return true;
    }
  }

  Future<bool> sendGroupText(String rawText) async {
    final text = rawText.trim();
    if (text.isEmpty || connectedCount == 0) return false;

    final now = DateTime.now();
    final messageId =
        'group-${now.microsecondsSinceEpoch}-${_displayName.hashCode}';
    _seenMessageIds.add(messageId);

    final localMsg = ChatMessage(
      id: messageId,
      endpointId: ChatMessage.groupEndpointId,
      author: _displayName,
      authorAvatar: UserProfileService.instance.localAvatarBase64,
      text: text,
      sentAt: now,
      direction: MessageDirection.outgoing,
      delivery: MessageDelivery.sent,
      isGroup: true,
      hopCount: 0,
    );

    final groupList =
        _messages.putIfAbsent(ChatMessage.groupEndpointId, () => []);
    groupList.add(localMsg);
    notifyListeners();

    for (final peer in connectedPeers) {
      unawaited(
        _transport.sendMessage(
          localMsg.copyWith(endpointId: peer.id),
        ).catchError((e) {
          debugPrint('Error enviando a ${peer.name}: $e');
        }),
      );
    }
    return true;
  }

  Future<bool> sendImage(
    String endpointId,
    File imageFile, {
    String caption = '',
  }) async {
    final peer = _peers[endpointId];
    if (peer == null || !peer.isConnected) return false;

    final bytes = await imageFile.readAsBytes();
    final now = DateTime.now();
    var message = ChatMessage(
      id: '${now.microsecondsSinceEpoch}-${_displayName.hashCode}',
      endpointId: endpointId,
      author: _displayName,
      authorAvatar: UserProfileService.instance.localAvatarBase64,
      text: caption,
      sentAt: now,
      direction: MessageDirection.outgoing,
      delivery: MessageDelivery.sending,
      type: ChatMessageType.image,
      mediaPath: imageFile.path,
      mediaBase64: base64Encode(bytes),
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
      _setError('No se pudo enviar la imagen: $error');
      return false;
    }
  }

  Future<bool> sendGroupImage(File imageFile, {String caption = ''}) async {
    if (connectedCount == 0) return false;

    final bytes = await imageFile.readAsBytes();
    final now = DateTime.now();
    final messageId =
        'group-img-${now.microsecondsSinceEpoch}-${_displayName.hashCode}';
    _seenMessageIds.add(messageId);

    final localMsg = ChatMessage(
      id: messageId,
      endpointId: ChatMessage.groupEndpointId,
      author: _displayName,
      authorAvatar: UserProfileService.instance.localAvatarBase64,
      text: caption,
      sentAt: now,
      direction: MessageDirection.outgoing,
      delivery: MessageDelivery.sent,
      type: ChatMessageType.image,
      mediaPath: imageFile.path,
      mediaBase64: base64Encode(bytes),
      isGroup: true,
      hopCount: 0,
    );

    final groupList =
        _messages.putIfAbsent(ChatMessage.groupEndpointId, () => []);
    groupList.add(localMsg);
    notifyListeners();

    for (final peer in connectedPeers) {
      unawaited(
        _transport.sendMessage(
          localMsg.copyWith(endpointId: peer.id),
        ).catchError((e) {
          debugPrint('Error enviando imagen grupal a ${peer.name}: $e');
        }),
      );
    }
    return true;
  }

  Future<bool> sendAudio(
    String endpointId,
    File audioFile,
    int durationSeconds,
  ) async {
    final peer = _peers[endpointId];
    if (peer == null || !peer.isConnected) return false;

    final bytes = await audioFile.readAsBytes();
    final now = DateTime.now();
    var message = ChatMessage(
      id: '${now.microsecondsSinceEpoch}-${_displayName.hashCode}',
      endpointId: endpointId,
      author: _displayName,
      authorAvatar: UserProfileService.instance.localAvatarBase64,
      text: 'Nota de voz (${durationSeconds}s)',
      sentAt: now,
      direction: MessageDirection.outgoing,
      delivery: MessageDelivery.sending,
      type: ChatMessageType.audio,
      mediaPath: audioFile.path,
      mediaBase64: base64Encode(bytes),
      durationSeconds: durationSeconds,
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
      _setError('No se pudo enviar la nota de voz: $error');
      return false;
    }
  }

  Future<bool> sendGroupAudio(File audioFile, int durationSeconds) async {
    if (connectedCount == 0) return false;

    final bytes = await audioFile.readAsBytes();
    final now = DateTime.now();
    final messageId =
        'group-audio-${now.microsecondsSinceEpoch}-${_displayName.hashCode}';
    _seenMessageIds.add(messageId);

    final localMsg = ChatMessage(
      id: messageId,
      endpointId: ChatMessage.groupEndpointId,
      author: _displayName,
      authorAvatar: UserProfileService.instance.localAvatarBase64,
      text: 'Nota de voz (${durationSeconds}s)',
      sentAt: now,
      direction: MessageDirection.outgoing,
      delivery: MessageDelivery.sent,
      type: ChatMessageType.audio,
      mediaPath: audioFile.path,
      mediaBase64: base64Encode(bytes),
      durationSeconds: durationSeconds,
      isGroup: true,
      hopCount: 0,
    );

    final groupList =
        _messages.putIfAbsent(ChatMessage.groupEndpointId, () => []);
    groupList.add(localMsg);
    notifyListeners();

    for (final peer in connectedPeers) {
      unawaited(
        _transport.sendMessage(
          localMsg.copyWith(endpointId: peer.id),
        ).catchError((e) {
          debugPrint('Error enviando audio grupal a ${peer.name}: $e');
        }),
      );
    }
    return true;
  }

  Future<bool> editMessage(
    String endpointId,
    String messageId,
    String newText,
  ) async {
    final text = newText.trim();
    if (text.isEmpty) return false;
    final list = _messages[endpointId];
    if (list == null) return false;
    final index = list.indexWhere((m) => m.id == messageId);
    if (index < 0) return false;

    final original = list[index];
    final now = DateTime.now();
    final updated = original.copyWith(
      text: text,
      isEdited: true,
      editedAt: now,
    );
    list[index] = updated;
    notifyListeners();

    try {
      await _transport.sendEdit(
        endpointId: endpointId,
        targetMessageId: messageId,
        newText: text,
      );
      return true;
    } catch (e) {
      _setError('No se pudo editar el mensaje: $e');
      return false;
    }
  }

  Future<bool> editGroupMessage(String messageId, String newText) async {
    final text = newText.trim();
    if (text.isEmpty) return false;
    final list = _messages[ChatMessage.groupEndpointId];
    if (list == null) return false;
    final index = list.indexWhere((m) => m.id == messageId);
    if (index < 0) return false;

    final original = list[index];
    final now = DateTime.now();
    final updated = original.copyWith(
      text: text,
      isEdited: true,
      editedAt: now,
    );
    list[index] = updated;
    notifyListeners();

    for (final peer in connectedPeers) {
      unawaited(
        _transport.sendEdit(
          endpointId: peer.id,
          targetMessageId: messageId,
          newText: text,
        ).catchError((e) {
          debugPrint('Error enviando edición grupal a ${peer.name}: $e');
        }),
      );
    }
    return true;
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
        final isSpoofed = event.uniqueId != null
            ? !UserIdentityService.instance.verifyOrRegisterPeer(
                endpointId: event.endpointId,
                peerName: event.name,
                fingerprint: event.uniqueId!,
              )
            : false;
        if (event.avatarBase64 != null) {
          UserProfileService.instance.setPeerAvatar(
            event.endpointId,
            event.avatarBase64,
          );
        }
        _peers[event.endpointId] = NearbyPeer(
          id: event.endpointId,
          name: event.name,
          status: existing?.status ?? PeerConnectionStatus.discovered,
          authenticationToken: existing?.authenticationToken,
          isIncoming: existing?.isIncoming ?? false,
          uniqueId: event.uniqueId ?? existing?.uniqueId,
          avatarBase64: event.avatarBase64 ?? existing?.avatarBase64,
          personalPin: event.personalPin ?? existing?.personalPin,
          isSpoofed: isSpoofed,
        );
      case PeerUpdated():
        final existing = _peers[event.endpointId];
        if (existing != null) {
          if (event.avatar != null) {
            UserProfileService.instance.setPeerAvatar(
              event.endpointId,
              event.avatar,
            );
          }
          _peers[event.endpointId] = existing.copyWith(
            name: event.name ?? existing.name,
            avatarBase64: event.avatar ?? existing.avatarBase64,
            uniqueId: event.uniqueId ?? existing.uniqueId,
          );
        }
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
          uniqueId: existing?.uniqueId,
          avatarBase64: existing?.avatarBase64,
          personalPin: existing?.personalPin,
          isSpoofed: existing?.isSpoofed ?? false,
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
        _flushMailboxForPeer(event.endpointId);
        final p = _peers[event.endpointId];
        if (p != null) {
          _peerConnectionNotifications.add(p.name);
        }
      case MessageReceived():
        unawaited(_processIncomingMessage(event.message));
      case MessageEdited():
        _processIncomingEdit(event);
      case MessageReadReceipt():
        _processIncomingReadReceipt(event);
      case NearbyFailure():
        _errorMessage = event.message;
    }
    notifyListeners();
  }

  void _flushMailboxForPeer(String endpointId) {
    unawaited(
      OfflineMailboxService.instance.flushPendingForPeer(
        endpointId,
        (message) async {
          try {
            await _transport.sendMessage(message);
            final updated = message.copyWith(delivery: MessageDelivery.sent);
            _replaceMessage(endpointId, updated);
            return true;
          } catch (e) {
            debugPrint('Error enviando mensaje pendiente del buzón: $e');
            return false;
          }
        },
      ).then((sent) {
        if (sent.isNotEmpty) {
          notifyListeners();
        }
      }),
    );
  }

  Future<void> _processIncomingMessage(ChatMessage raw) async {
    var message = raw;
    if (message.authorAvatar != null) {
      UserProfileService.instance.setPeerAvatar(message.endpointId, message.authorAvatar);
      final existing = _peers[message.endpointId];
      if (existing != null && existing.avatarBase64 != message.authorAvatar) {
        _peers[message.endpointId] = existing.copyWith(avatarBase64: message.authorAvatar);
      }
    }
    if (message.mediaBase64 != null && message.mediaPath == null) {
      try {
        final bytes = base64Decode(message.mediaBase64!);
        final dir = await getTemporaryDirectory();
        final ext = message.type == ChatMessageType.image ? 'jpg' : 'm4a';
        final file = File('${dir.path}/media_${message.id}.$ext');
        await file.writeAsBytes(bytes);
        message = message.copyWith(mediaPath: file.path);
      } catch (e) {
        debugPrint('Error guardando archivo multimedia recibido: $e');
      }
    }

    if (message.isGroup) {
      // Loop prevention / deduplicación
      if (!_seenMessageIds.add(message.id)) return;

      final targetList =
          _messages.putIfAbsent(ChatMessage.groupEndpointId, () => []);
      targetList.add(message);
      notifyListeners();

      // Mesh Relay: Si no excede 5 saltos, retransmitir a los demás pares conectados
      if (message.hopCount < 5) {
        final relayed = message.copyWith(hopCount: message.hopCount + 1);
        for (final peer in connectedPeers) {
          if (peer.id != raw.endpointId) {
            unawaited(
              _transport
                  .sendMessage(relayed.copyWith(endpointId: peer.id))
                  .catchError((e) {
                debugPrint(
                    'Error retransmitiendo salto mesh a ${peer.name}: $e');
              }),
            );
          }
        }
      }
      return;
    }

    _messages.putIfAbsent(message.endpointId, () => []).add(message);
    _incomingMessageNotifications.add(message);
    notifyListeners();
  }

  void _processIncomingReadReceipt(MessageReadReceipt event) {
    final list = _messages[event.endpointId];
    if (list != null) {
      final index = list.indexWhere((m) => m.id == event.messageId);
      if (index >= 0) {
        list[index] = list[index].copyWith(delivery: MessageDelivery.read);
        notifyListeners();
      }
    }
  }

  void _processIncomingEdit(MessageEdited event) {
    // Buscar en chat 1 a 1
    final list = _messages[event.endpointId];
    if (list != null) {
      final index = list.indexWhere((m) => m.id == event.targetMessageId);
      if (index >= 0) {
        list[index] = list[index].copyWith(
          text: event.newText,
          isEdited: true,
          editedAt: event.editedAt,
        );
        notifyListeners();
        return;
      }
    }

    // Buscar en sala grupal
    final groupList = _messages[ChatMessage.groupEndpointId];
    if (groupList != null) {
      final index = groupList.indexWhere((m) => m.id == event.targetMessageId);
      if (index >= 0) {
        groupList[index] = groupList[index].copyWith(
          text: event.newText,
          isEdited: true,
          editedAt: event.editedAt,
        );
        notifyListeners();
      }
    }
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
    unawaited(_incomingMessageNotifications.close());
    unawaited(_peerConnectionNotifications.close());
    super.dispose();
  }
}
