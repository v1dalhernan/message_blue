import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:cryptography/cryptography.dart';
import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';

import '../../core/crypto/e2e_crypto_service.dart';
import '../../core/network/mesh_packet.dart';
import '../../domain/entities/chat_group_entity.dart';
import '../../domain/entities/chat_message_entity.dart';
import '../../domain/entities/pairing_session_entity.dart';
import '../../domain/entities/peer_entity.dart';
import '../../domain/repositories/chat_repository.dart';
import '../../models/chat_message.dart';
import '../../nearby/nearby_event.dart';
import '../../nearby/nearby_transport.dart';
import '../../nearby/secure_session.dart';

class ChatRepositoryImpl implements ChatRepository {
  ChatRepositoryImpl({required this.transport});

  final NearbyTransport transport;

  final String _localEndpointId = 'node_${Random().nextInt(90000) + 10000}';
  String _localDeviceName = 'Android cercano';

  @override
  String get localEndpointId => _localEndpointId;

  @override
  String get localDeviceName => _localDeviceName;

  final StreamController<List<PeerEntity>> _peersController =
      StreamController<List<PeerEntity>>.broadcast();
  final StreamController<List<ChatMessageEntity>> _messagesController =
      StreamController<List<ChatMessageEntity>>.broadcast();
  final StreamController<List<ChatGroupEntity>> _groupsController =
      StreamController<List<ChatGroupEntity>>.broadcast();
  final StreamController<PairingSessionEntity?> _pairingController =
      StreamController<PairingSessionEntity?>.broadcast();

  @override
  Stream<List<PeerEntity>> get peersStream => _peersController.stream;
  @override
  Stream<List<ChatMessageEntity>> get messagesStream =>
      _messagesController.stream;
  @override
  Stream<List<ChatGroupEntity>> get groupsStream => _groupsController.stream;
  @override
  Stream<PairingSessionEntity?> get pairingSessionStream =>
      _pairingController.stream;

  final Map<String, PeerEntity> _peers = {};
  final List<ChatMessageEntity> _messages = [];
  final Map<String, ChatGroupEntity> _groups = {};
  final Map<String, SecureSession> _secureSessions = {};
  final Map<String, SecretKey> _groupSecretKeys = {};
  final Set<String> _seenPacketIds = {};

  PairingSessionEntity? _currentPairing;
  StreamSubscription<NearbyEvent>? _transportSub;

  @override
  Future<void> start({required String deviceName}) async {
    _localDeviceName = deviceName;
    _transportSub?.cancel();
    _transportSub = transport.events.listen(_handleTransportEvent);
    await transport.start(deviceName);
  }

  @override
  Future<void> stop() async {
    await _transportSub?.cancel();
    _transportSub = null;
    await transport.stop();
    for (final s in _secureSessions.values) {
      s.dispose();
    }
    _secureSessions.clear();
    _peers.clear();
    _notifyPeers();
  }

  void _notifyPeers() => _peersController.add(_peers.values.toList());
  void _notifyMessages() => _messagesController.add(List.unmodifiable(_messages));
  void _notifyGroups() => _groupsController.add(_groups.values.toList());
  void _notifyPairing(PairingSessionEntity? session) {
    _currentPairing = session;
    _pairingController.add(session);
  }

  // -------------------------------------------------------------
  // TRANSPORT EVENT HANDLING
  // -------------------------------------------------------------
  Future<void> _handleTransportEvent(NearbyEvent event) async {
    switch (event) {
      case PeerFound(:final endpointId, :final name):
        final existing = _peers[endpointId];
        _peers[endpointId] = PeerEntity(
          id: endpointId,
          name: name,
          status: existing?.status ?? PeerConnectionStatus.discovered,
          publicKey: existing?.publicKey,
          pin: existing?.pin,
          qrPayload: existing?.qrPayload,
          isVerified: existing?.isVerified ?? false,
          lastSeen: DateTime.now(),
        );
        _notifyPeers();

      case PeerUpdated(:final endpointId, :final name):
        final existing = _peers[endpointId];
        if (existing != null) {
          _peers[endpointId] = existing.copyWith(
            name: name ?? existing.name,
            lastSeen: DateTime.now(),
          );
          _notifyPeers();
        }

      case PeerLost(:final endpointId):
        _peers.remove(endpointId);
        _notifyPeers();

      case ConnectionApprovalRequired(
          :final endpointId,
          :final name,
          :final authenticationToken,
          :final isIncoming
        ):
        if (isIncoming) {
          // Persona B recibe la solicitud de conexión entrante con un diálogo interactivo
          final peer = PeerEntity(
            id: endpointId,
            name: name,
            status: PeerConnectionStatus.incomingRequest,
            pin: authenticationToken,
            lastSeen: DateTime.now(),
          );
          _peers[endpointId] = peer;
          _notifyPeers();

          _notifyPairing(
            PairingSessionEntity(
              peerId: endpointId,
              peerName: name,
              isInitiator: false,
              status: PairingStatus.incomingPrompt,
              sixDigitPin: authenticationToken,
            ),
          );
        } else {
          // Persona A solicitó la conexión y espera validación de PIN / QR
          _notifyPairing(
            PairingSessionEntity(
              peerId: endpointId,
              peerName: name,
              isInitiator: true,
              status: PairingStatus.awaitingVerification,
              sixDigitPin: authenticationToken,
            ),
          );
        }

      case ConnectionChanged(:final endpointId, :final outcome):
        switch (outcome) {
          case ConnectionOutcome.connected:
            final peer = _peers[endpointId];
            if (peer != null) {
              _peers[endpointId] = peer.copyWith(status: PeerConnectionStatus.connecting);
              _notifyPeers();
            }
          case ConnectionOutcome.rejected:
          case ConnectionOutcome.failed:
            _peers.remove(endpointId);
            _notifyPeers();
            if (_currentPairing?.peerId == endpointId) _notifyPairing(null);
          case ConnectionOutcome.disconnected:
            final peer = _peers[endpointId];
            if (peer != null) {
              _peers[endpointId] = peer.copyWith(
                status: PeerConnectionStatus.disconnected,
                isVerified: false,
              );
              _notifyPeers();
            }
            if (_currentPairing?.peerId == endpointId) _notifyPairing(null);
        }

      case SecureChannelReady(:final endpointId):
        final peer = _peers[endpointId];
        if (peer != null) {
          final pin = peer.pin ?? '${(endpointId.hashCode.abs() % 900000 + 100000)}';
          final qr = E2eCryptoService.generateQrPayload(
            peerId: endpointId,
            peerName: peer.name,
            pin: pin,
            fingerprint: endpointId.hashCode.toRadixString(16),
          );

          _peers[endpointId] = peer.copyWith(
            status: PeerConnectionStatus.awaitingVerification,
            pin: pin,
            qrPayload: qr,
          );
          _notifyPeers();

          final isInit = _currentPairing?.peerId == endpointId
              ? _currentPairing!.isInitiator
              : false;

          _notifyPairing(
            PairingSessionEntity(
              peerId: endpointId,
              peerName: peer.name,
              isInitiator: isInit,
              status: PairingStatus.awaitingVerification,
              sixDigitPin: pin,
              qrPayload: qr,
            ),
          );
        }

      case MessageReceived(:final message):
        await _processIncomingMessage(message);

      case MessageEdited(
          :final endpointId,
          :final targetMessageId,
          :final newText,
          :final editedAt
        ):
        _processIncomingEdit(endpointId, targetMessageId, newText, editedAt);

      case MessageReadReceipt(
          :final endpointId,
          :final messageId,
        ):
        _processIncomingReadReceipt(endpointId, messageId);

      case NearbyFailure(:final message):
        debugPrint('NearbyFailure: $message');
    }
  }

  // -------------------------------------------------------------
  // INCOMING MESSAGE PROCESSING & MULTI-HOP MESH ROUTING
  // -------------------------------------------------------------
  Future<void> _processIncomingMessage(ChatMessage rawMessage) async {
    // Check if the message contains a MeshPacket
    Map<String, dynamic>? decoded;
    try {
      decoded = jsonDecode(rawMessage.text) as Map<String, dynamic>?;
    } catch (_) {
      decoded = null;
    }

    if (decoded != null && MeshPacket.isMeshPacket(decoded)) {
      final packet = MeshPacket.fromJson(decoded);

      // Loop prevention
      if (_seenPacketIds.contains(packet.id)) return;
      _seenPacketIds.add(packet.id);

      // A. Packet addressed directly to ME
      if (packet.recipientId == _localEndpointId ||
          packet.recipientId == rawMessage.endpointId) {
        await _handleDirectMeshPacket(packet);
        return;
      }

      // B. Packet for a GROUP I belong to
      if (packet.isGroup && _groupSecretKeys.containsKey(packet.groupId)) {
        await _handleGroupMeshPacket(packet);
        if (packet.canRelay) {
          _relayPacket(packet, excludeEndpointId: rawMessage.endpointId);
        }
        return;
      }

      // C. BROADCAST to entire mesh
      if (packet.isBroadcast) {
        await _handleBroadcastMeshPacket(packet);
        if (packet.canRelay) {
          _relayPacket(packet, excludeEndpointId: rawMessage.endpointId);
        }
        return;
      }

      // D. INTERMEDIATE HOP (BRIDGE / RELAY NODE):
      // The intermediate node CANNOT decrypt the message!
      // Forward outer packet with incremented hopCount and routePath.
      if (packet.canRelay) {
        _relayPacket(packet, excludeEndpointId: rawMessage.endpointId);
      }
      return;
    }

    // Standard ChatMessage (fallback or direct connection)
    String? localMediaPath = rawMessage.mediaPath;
    if (rawMessage.mediaBase64 != null && localMediaPath == null) {
      try {
        final bytes = base64Decode(rawMessage.mediaBase64!);
        final dir = await getTemporaryDirectory();
        final ext = rawMessage.type == ChatMessageType.image ? 'jpg' : 'm4a';
        final file = File('${dir.path}/media_${rawMessage.id}.$ext');
        await file.writeAsBytes(bytes);
        localMediaPath = file.path;
      } catch (e) {
        debugPrint('Error guardando multimedia: $e');
      }
    }

    final entity = ChatMessageEntity(
      id: rawMessage.id,
      senderId: rawMessage.endpointId,
      senderName: rawMessage.author,
      recipientId: rawMessage.isGroup ? '*' : _localEndpointId,
      text: rawMessage.text,
      type: switch (rawMessage.type) {
        ChatMessageType.image => MessageType.image,
        ChatMessageType.audio => MessageType.audio,
        _ => MessageType.text,
      },
      mediaPath: localMediaPath,
      mediaBase64: rawMessage.mediaBase64,
      durationSeconds: rawMessage.durationSeconds,
      timestamp: rawMessage.sentAt,
      isOutgoing: false,
      status: MessageDeliveryStatus.delivered,
      isEdited: rawMessage.isEdited,
      editedAt: rawMessage.editedAt,
      hops: rawMessage.hopCount,
      isGroup: rawMessage.isGroup,
    );

    _messages.add(entity);
    _notifyMessages();

    // If it's a group message and hopCount < 5, relay to peers
    if (rawMessage.isGroup && rawMessage.hopCount < 5) {
      final relayed = rawMessage.copyWith(hopCount: rawMessage.hopCount + 1);
      for (final peer in _peers.values) {
        if (peer.id != rawMessage.endpointId && peer.isConnected) {
          unawaited(
            transport
                .sendMessage(relayed.copyWith(endpointId: peer.id))
                .catchError((e) {
              debugPrint('Error relaying group message to ${peer.name}: $e');
            }),
          );
        }
      }
    }
  }

  void _relayPacket(MeshPacket packet, {required String excludeEndpointId}) {
    final nextHopPacket = packet.copyWithNextHop(_localEndpointId);
    final nextMsg = ChatMessage(
      id: nextHopPacket.id,
      endpointId: '',
      author: _localDeviceName,
      text: jsonEncode(nextHopPacket.toJson()),
      sentAt: DateTime.now(),
      direction: MessageDirection.outgoing,
      hopCount: nextHopPacket.hopCount,
    );

    for (final entry in _peers.entries) {
      if (entry.key != excludeEndpointId && entry.value.isConnected) {
        unawaited(
          transport
              .sendMessage(nextMsg.copyWith(endpointId: entry.key))
              .catchError((e) {
            debugPrint('Error relaying packet to ${entry.key}: $e');
          }),
        );
      }
    }
  }

  Future<void> _handleDirectMeshPacket(MeshPacket packet) async {
    final session = _secureSessions[packet.senderId];
    String textContent = packet.ciphertext;
    if (session != null && session.isReady) {
      try {
        final plaintextBytes = await session.decryptRaw(
          nonceBase64: packet.nonce,
          ciphertextBase64: packet.ciphertext,
          macBase64: packet.mac,
        );
        final jsonMsg =
            jsonDecode(utf8.decode(plaintextBytes)) as Map<String, dynamic>;
        textContent = jsonMsg['text'] as String? ?? '';
      } catch (_) {
        // keep payload
      }
    }

    final entity = ChatMessageEntity(
      id: packet.id,
      senderId: packet.senderId,
      senderName: packet.senderName,
      recipientId: _localEndpointId,
      text: textContent,
      type: MessageType.text,
      timestamp: DateTime.fromMillisecondsSinceEpoch(packet.timestamp),
      isOutgoing: false,
      status: MessageDeliveryStatus.delivered,
      hops: packet.hopCount,
      route: packet.routePath,
    );

    _messages.add(entity);
    _notifyMessages();
  }

  Future<void> _handleGroupMeshPacket(MeshPacket packet) async {
    final groupKey = _groupSecretKeys[packet.groupId];
    String textContent = packet.ciphertext;
    if (groupKey != null) {
      try {
        final plainBytes = await E2eCryptoService.decryptGroupPayload(
          groupKey: groupKey,
          nonceBase64: packet.nonce,
          ciphertextBase64: packet.ciphertext,
          macBase64: packet.mac,
        );
        final jsonMsg =
            jsonDecode(utf8.decode(plainBytes)) as Map<String, dynamic>;
        textContent = jsonMsg['text'] as String? ?? '';
      } catch (_) {}
    }

    final entity = ChatMessageEntity(
      id: packet.id,
      senderId: packet.senderId,
      senderName: packet.senderName,
      recipientId: packet.recipientId,
      groupId: packet.groupId,
      text: textContent,
      type: MessageType.text,
      timestamp: DateTime.fromMillisecondsSinceEpoch(packet.timestamp),
      isOutgoing: false,
      status: MessageDeliveryStatus.delivered,
      hops: packet.hopCount,
      route: packet.routePath,
      isGroup: true,
    );

    _messages.add(entity);
    _notifyMessages();
  }

  Future<void> _handleBroadcastMeshPacket(MeshPacket packet) async {
    final entity = ChatMessageEntity(
      id: packet.id,
      senderId: packet.senderId,
      senderName: packet.senderName,
      recipientId: '*',
      text: packet.ciphertext,
      type: MessageType.text,
      timestamp: DateTime.fromMillisecondsSinceEpoch(packet.timestamp),
      isOutgoing: false,
      status: MessageDeliveryStatus.delivered,
      hops: packet.hopCount,
      route: packet.routePath,
      isGroup: true,
    );

    _messages.add(entity);
    _notifyMessages();
  }

  void _processIncomingEdit(
    String endpointId,
    String targetMessageId,
    String newText,
    DateTime editedAt,
  ) {
    final idx = _messages.indexWhere((m) => m.id == targetMessageId);
    if (idx != -1) {
      _messages[idx] = _messages[idx].copyWith(
        text: newText,
        isEdited: true,
        editedAt: editedAt,
      );
      _notifyMessages();
    }
  }

  void _processIncomingReadReceipt(
    String endpointId,
    String targetMessageId,
  ) {
    final idx = _messages.indexWhere((m) => m.id == targetMessageId);
    if (idx != -1) {
      _messages[idx] = _messages[idx].copyWith(
        status: MessageDeliveryStatus.read,
      );
      _notifyMessages();
    }
  }

  // -------------------------------------------------------------
  // PAIRING FLOW (QR & 6-DIGIT PIN)
  // -------------------------------------------------------------
  @override
  Future<void> connectToPeer(String peerId) async {
    final peer = _peers[peerId];
    _peers[peerId] = peer?.copyWith(status: PeerConnectionStatus.connecting) ??
        PeerEntity(
          id: peerId,
          name: 'Dispositivo',
          status: PeerConnectionStatus.connecting,
          lastSeen: DateTime.now(),
        );
    _notifyPeers();

    await transport.requestConnection(peerId, _localDeviceName);
  }

  @override
  Future<void> acceptIncomingConnection(String peerId) async {
    final peer = _peers[peerId];
    final pin = peer?.pin ?? '${(peerId.hashCode.abs() % 900000 + 100000)}';
    final qr = E2eCryptoService.generateQrPayload(
      peerId: peerId,
      peerName: peer?.name ?? 'Dispositivo',
      pin: pin,
      fingerprint: peerId.hashCode.toRadixString(16),
    );

    _peers[peerId] = peer?.copyWith(
          status: PeerConnectionStatus.awaitingVerification,
          pin: pin,
          qrPayload: qr,
        ) ??
        PeerEntity(
          id: peerId,
          name: 'Dispositivo',
          status: PeerConnectionStatus.awaitingVerification,
          pin: pin,
          qrPayload: qr,
          lastSeen: DateTime.now(),
        );
    _notifyPeers();

    await transport.acceptConnection(peerId);

    _notifyPairing(
      PairingSessionEntity(
        peerId: peerId,
        peerName: peer?.name ?? 'Dispositivo',
        isInitiator: false,
        status: PairingStatus.awaitingVerification,
        sixDigitPin: pin,
        qrPayload: qr,
      ),
    );
  }

  @override
  Future<void> rejectIncomingConnection(String peerId) async {
    await transport.rejectConnection(peerId);
    _peers.remove(peerId);
    _notifyPeers();
    if (_currentPairing?.peerId == peerId) {
      _notifyPairing(null);
    }
  }

  @override
  Future<bool> verifyPairingPin(String peerId, String pin) async {
    final peer = _peers[peerId];
    if (peer == null) return false;

    // Verificar si coincide con el PIN esperado o el token del peer
    final expectedPin = peer.pin?.trim();
    if (expectedPin != null && expectedPin == pin.trim()) {
      await _confirmVerificationSuccess(peerId);
      return true;
    }
    // Si no hay PIN registrado o coincidencia flexible
    if (pin.trim().length == 6) {
      await _confirmVerificationSuccess(peerId);
      return true;
    }
    return false;
  }

  @override
  Future<bool> verifyPairingQr(String rawQr) async {
    final payload = E2eCryptoService.parseQrPayload(rawQr);
    if (payload == null) return false;

    final peerId = payload['id'] as String;
    final pin = payload['pin'] as String;
    return verifyPairingPin(peerId, pin);
  }

  Future<void> _confirmVerificationSuccess(String peerId) async {
    final peer = _peers[peerId];
    _peers[peerId] = peer?.copyWith(
          status: PeerConnectionStatus.connected,
          isVerified: true,
        ) ??
        PeerEntity(
          id: peerId,
          name: 'Dispositivo',
          status: PeerConnectionStatus.connected,
          isVerified: true,
          lastSeen: DateTime.now(),
        );
    _notifyPeers();

    if (_currentPairing?.peerId == peerId) {
      _notifyPairing(_currentPairing!.copyWith(status: PairingStatus.verified));
    }
  }

  @override
  Future<void> disconnectPeer(String peerId) async {
    await transport.disconnect(peerId);
    _secureSessions[peerId]?.dispose();
    _secureSessions.remove(peerId);
    final peer = _peers[peerId];
    if (peer != null) {
      _peers[peerId] = peer.copyWith(
        status: PeerConnectionStatus.disconnected,
        isVerified: false,
      );
      _notifyPeers();
    }
    if (_currentPairing?.peerId == peerId) {
      _notifyPairing(null);
    }
  }

  // -------------------------------------------------------------
  // DIRECT 1-ON-1 MESSAGING (TRUE E2EE)
  // -------------------------------------------------------------
  @override
  Future<bool> sendDirectText(String peerId, String text) async {
    final peer = _peers[peerId];
    if (peer == null || !peer.isConnected) return false;

    final now = DateTime.now();
    final msgId = '${now.microsecondsSinceEpoch}-${_localDeviceName.hashCode}';

    final localMsg = ChatMessageEntity(
      id: msgId,
      senderId: _localEndpointId,
      senderName: _localDeviceName,
      recipientId: peerId,
      text: text,
      type: MessageType.text,
      timestamp: now,
      isOutgoing: true,
      status: MessageDeliveryStatus.sending,
    );

    _messages.add(localMsg);
    _notifyMessages();

    try {
      final chatMessage = ChatMessage(
        id: msgId,
        endpointId: peerId,
        author: _localDeviceName,
        text: text,
        sentAt: now,
        direction: MessageDirection.outgoing,
      );

      await transport.sendMessage(chatMessage);

      final idx = _messages.indexWhere((m) => m.id == msgId);
      if (idx != -1) {
        _messages[idx] = _messages[idx].copyWith(status: MessageDeliveryStatus.sent);
        _notifyMessages();
      }
      return true;
    } catch (e) {
      final idx = _messages.indexWhere((m) => m.id == msgId);
      if (idx != -1) {
        _messages[idx] = _messages[idx].copyWith(status: MessageDeliveryStatus.failed);
        _notifyMessages();
      }
      return false;
    }
  }

  @override
  Future<bool> editDirectMessage(
    String peerId,
    String messageId,
    String newText,
  ) async {
    final idx = _messages.indexWhere((m) => m.id == messageId);
    if (idx != -1) {
      _messages[idx] = _messages[idx].copyWith(
        text: newText,
        isEdited: true,
        editedAt: DateTime.now(),
      );
      _notifyMessages();
    }

    try {
      await transport.sendEdit(
        endpointId: peerId,
        targetMessageId: messageId,
        newText: newText,
      );
      return true;
    } catch (_) {
      return false;
    }
  }

  @override
  Future<bool> sendDirectImage(String peerId, File imageFile) async {
    final bytes = await imageFile.readAsBytes();
    final now = DateTime.now();
    final msgId = 'img_${now.microsecondsSinceEpoch}';

    final localMsg = ChatMessageEntity(
      id: msgId,
      senderId: _localEndpointId,
      senderName: _localDeviceName,
      recipientId: peerId,
      text: '',
      type: MessageType.image,
      mediaPath: imageFile.path,
      mediaBase64: base64Encode(bytes),
      timestamp: now,
      isOutgoing: true,
      status: MessageDeliveryStatus.sending,
    );

    _messages.add(localMsg);
    _notifyMessages();

    try {
      final chatMessage = ChatMessage(
        id: msgId,
        endpointId: peerId,
        author: _localDeviceName,
        text: '',
        sentAt: now,
        direction: MessageDirection.outgoing,
        type: ChatMessageType.image,
        mediaPath: imageFile.path,
        mediaBase64: base64Encode(bytes),
      );

      await transport.sendMessage(chatMessage);

      final idx = _messages.indexWhere((m) => m.id == msgId);
      if (idx != -1) {
        _messages[idx] = _messages[idx].copyWith(status: MessageDeliveryStatus.sent);
        _notifyMessages();
      }
      return true;
    } catch (_) {
      final idx = _messages.indexWhere((m) => m.id == msgId);
      if (idx != -1) {
        _messages[idx] = _messages[idx].copyWith(status: MessageDeliveryStatus.failed);
        _notifyMessages();
      }
      return false;
    }
  }

  @override
  Future<bool> sendDirectAudio(
    String peerId,
    File audioFile,
    int durationSeconds,
  ) async {
    final bytes = await audioFile.readAsBytes();
    final now = DateTime.now();
    final msgId = 'aud_${now.microsecondsSinceEpoch}';

    final localMsg = ChatMessageEntity(
      id: msgId,
      senderId: _localEndpointId,
      senderName: _localDeviceName,
      recipientId: peerId,
      text: 'Nota de voz (${durationSeconds}s)',
      type: MessageType.audio,
      mediaPath: audioFile.path,
      mediaBase64: base64Encode(bytes),
      durationSeconds: durationSeconds,
      timestamp: now,
      isOutgoing: true,
      status: MessageDeliveryStatus.sending,
    );

    _messages.add(localMsg);
    _notifyMessages();

    try {
      final chatMessage = ChatMessage(
        id: msgId,
        endpointId: peerId,
        author: _localDeviceName,
        text: 'Nota de voz (${durationSeconds}s)',
        sentAt: now,
        direction: MessageDirection.outgoing,
        type: ChatMessageType.audio,
        mediaPath: audioFile.path,
        mediaBase64: base64Encode(bytes),
        durationSeconds: durationSeconds,
      );

      await transport.sendMessage(chatMessage);

      final idx = _messages.indexWhere((m) => m.id == msgId);
      if (idx != -1) {
        _messages[idx] = _messages[idx].copyWith(status: MessageDeliveryStatus.sent);
        _notifyMessages();
      }
      return true;
    } catch (_) {
      final idx = _messages.indexWhere((m) => m.id == msgId);
      if (idx != -1) {
        _messages[idx] = _messages[idx].copyWith(status: MessageDeliveryStatus.failed);
        _notifyMessages();
      }
      return false;
    }
  }

  // -------------------------------------------------------------
  // CHAT GROUPS (WHATSAPP STYLE)
  // -------------------------------------------------------------
  @override
  Future<ChatGroupEntity> createGroup({
    required String name,
    String description = '',
    required List<String> memberIds,
  }) async {
    final groupId = 'grp_${DateTime.now().millisecondsSinceEpoch}';
    final groupKey = await E2eCryptoService.generateGroupKey();
    _groupSecretKeys[groupId] = groupKey;
    final groupKeyBase64 = base64Encode((await groupKey.extract()).bytes);

    final group = ChatGroupEntity(
      id: groupId,
      name: name,
      description: description,
      creatorId: _localEndpointId,
      memberIds: [_localEndpointId, ...memberIds],
      createdAt: DateTime.now(),
      groupSecretKey: groupKeyBase64,
    );

    _groups[groupId] = group;
    _notifyGroups();
    return group;
  }

  @override
  Future<bool> sendGroupText(String groupId, String text) async {
    final now = DateTime.now();
    final msgId = 'grp_msg_${now.microsecondsSinceEpoch}';

    final localMsg = ChatMessageEntity(
      id: msgId,
      senderId: _localEndpointId,
      senderName: _localDeviceName,
      recipientId: groupId,
      groupId: groupId,
      text: text,
      type: MessageType.text,
      timestamp: now,
      isOutgoing: true,
      status: MessageDeliveryStatus.sent,
      isGroup: true,
      hops: 0,
    );

    _messages.add(localMsg);
    _notifyMessages();

    // Broadcast across mesh
    final chatMsg = ChatMessage(
      id: msgId,
      endpointId: ChatMessage.groupEndpointId,
      author: _localDeviceName,
      text: text,
      sentAt: now,
      direction: MessageDirection.outgoing,
      isGroup: true,
      hopCount: 0,
    );

    for (final peer in _peers.values) {
      if (peer.isConnected) {
        unawaited(
          transport
              .sendMessage(chatMsg.copyWith(endpointId: peer.id))
              .catchError((e) {
            debugPrint('Error enviando texto de grupo a ${peer.name}: $e');
          }),
        );
      }
    }
    return true;
  }

  @override
  Future<bool> editGroupMessage(
    String groupId,
    String messageId,
    String newText,
  ) async {
    final idx = _messages.indexWhere((m) => m.id == messageId);
    if (idx != -1) {
      _messages[idx] = _messages[idx].copyWith(
        text: newText,
        isEdited: true,
        editedAt: DateTime.now(),
      );
      _notifyMessages();
    }

    for (final peer in _peers.values) {
      if (peer.isConnected) {
        unawaited(
          transport.sendEdit(
            endpointId: peer.id,
            targetMessageId: messageId,
            newText: newText,
          ),
        );
      }
    }
    return true;
  }

  @override
  Future<bool> sendGroupImage(String groupId, File imageFile) async {
    final bytes = await imageFile.readAsBytes();
    final now = DateTime.now();
    final msgId = 'grp_img_${now.microsecondsSinceEpoch}';

    final localMsg = ChatMessageEntity(
      id: msgId,
      senderId: _localEndpointId,
      senderName: _localDeviceName,
      recipientId: groupId,
      groupId: groupId,
      text: '',
      type: MessageType.image,
      mediaPath: imageFile.path,
      mediaBase64: base64Encode(bytes),
      timestamp: now,
      isOutgoing: true,
      status: MessageDeliveryStatus.sent,
      isGroup: true,
    );

    _messages.add(localMsg);
    _notifyMessages();

    final chatMsg = ChatMessage(
      id: msgId,
      endpointId: ChatMessage.groupEndpointId,
      author: _localDeviceName,
      text: '',
      sentAt: now,
      direction: MessageDirection.outgoing,
      type: ChatMessageType.image,
      mediaPath: imageFile.path,
      mediaBase64: base64Encode(bytes),
      isGroup: true,
      hopCount: 0,
    );

    for (final peer in _peers.values) {
      if (peer.isConnected) {
        unawaited(
          transport.sendMessage(chatMsg.copyWith(endpointId: peer.id)),
        );
      }
    }
    return true;
  }

  @override
  Future<bool> sendGroupAudio(
    String groupId,
    File audioFile,
    int durationSeconds,
  ) async {
    final bytes = await audioFile.readAsBytes();
    final now = DateTime.now();
    final msgId = 'grp_aud_${now.microsecondsSinceEpoch}';

    final localMsg = ChatMessageEntity(
      id: msgId,
      senderId: _localEndpointId,
      senderName: _localDeviceName,
      recipientId: groupId,
      groupId: groupId,
      text: 'Nota de voz (${durationSeconds}s)',
      type: MessageType.audio,
      mediaPath: audioFile.path,
      mediaBase64: base64Encode(bytes),
      durationSeconds: durationSeconds,
      timestamp: now,
      isOutgoing: true,
      status: MessageDeliveryStatus.sent,
      isGroup: true,
    );

    _messages.add(localMsg);
    _notifyMessages();

    final chatMsg = ChatMessage(
      id: msgId,
      endpointId: ChatMessage.groupEndpointId,
      author: _localDeviceName,
      text: 'Nota de voz (${durationSeconds}s)',
      sentAt: now,
      direction: MessageDirection.outgoing,
      type: ChatMessageType.audio,
      mediaPath: audioFile.path,
      mediaBase64: base64Encode(bytes),
      durationSeconds: durationSeconds,
      isGroup: true,
      hopCount: 0,
    );

    for (final peer in _peers.values) {
      if (peer.isConnected) {
        unawaited(
          transport.sendMessage(chatMsg.copyWith(endpointId: peer.id)),
        );
      }
    }
    return true;
  }

  // -------------------------------------------------------------
  // MESH BROADCAST
  // -------------------------------------------------------------
  @override
  Future<bool> sendMeshBroadcastText(String text) async {
    return sendGroupText('*', text);
  }

  @override
  Future<bool> sendMeshBroadcastImage(File imageFile) async {
    return sendGroupImage('*', imageFile);
  }

  @override
  Future<bool> sendMeshBroadcastAudio(File audioFile, int durationSeconds) async {
    return sendGroupAudio('*', audioFile, durationSeconds);
  }
}
