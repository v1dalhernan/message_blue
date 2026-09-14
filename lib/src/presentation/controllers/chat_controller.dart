import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';

import '../../domain/entities/chat_group_entity.dart';
import '../../domain/entities/chat_message_entity.dart';
import '../../domain/entities/pairing_session_entity.dart';
import '../../domain/entities/peer_entity.dart';
import '../../domain/repositories/chat_repository.dart';
import '../../domain/usecases/manage_groups_usecase.dart';
import '../../domain/usecases/pair_peer_usecase.dart';
import '../../domain/usecases/send_message_usecase.dart';

class ChatController extends ChangeNotifier {
  ChatController({
    required this.repository,
  })  : _sendMessageUseCase = SendMessageUseCase(repository),
        _pairPeerUseCase = PairPeerUseCase(repository),
        _manageGroupsUseCase = ManageGroupsUseCase(repository);

  final ChatRepository repository;
  final SendMessageUseCase _sendMessageUseCase;
  final PairPeerUseCase _pairPeerUseCase;
  final ManageGroupsUseCase _manageGroupsUseCase;

  List<PeerEntity> _peers = [];
  List<ChatMessageEntity> _messages = [];
  List<ChatGroupEntity> _groups = [];
  PairingSessionEntity? _currentPairingSession;

  List<PeerEntity> get peers => _peers;
  List<ChatMessageEntity> get messages => _messages;
  List<ChatGroupEntity> get groups => _groups;
  PairingSessionEntity? get currentPairingSession => _currentPairingSession;

  String get localEndpointId => repository.localEndpointId;
  String get localDeviceName => repository.localDeviceName;

  StreamSubscription? _peersSub;
  StreamSubscription? _messagesSub;
  StreamSubscription? _groupsSub;
  StreamSubscription? _pairingSub;

  Future<void> init({String deviceName = 'Android cercano'}) async {
    _peersSub = repository.peersStream.listen((peersList) {
      _peers = peersList;
      notifyListeners();
    });

    _messagesSub = repository.messagesStream.listen((messagesList) {
      _messages = messagesList;
      notifyListeners();
    });

    _groupsSub = repository.groupsStream.listen((groupsList) {
      _groups = groupsList;
      notifyListeners();
    });

    _pairingSub = repository.pairingSessionStream.listen((session) {
      _currentPairingSession = session;
      notifyListeners();
    });

    await repository.start(deviceName: deviceName);
  }

  @override
  void dispose() {
    _peersSub?.cancel();
    _messagesSub?.cancel();
    _groupsSub?.cancel();
    _pairingSub?.cancel();
    super.dispose();
  }

  // -------------------------------------------------------------
  // PAIRING FLOW
  // -------------------------------------------------------------
  Future<void> connectToPeer(String peerId) async {
    await _pairPeerUseCase.connect(peerId);
  }

  Future<void> acceptIncomingConnection(String peerId) async {
    await _pairPeerUseCase.accept(peerId);
  }

  Future<void> rejectIncomingConnection(String peerId) async {
    await _pairPeerUseCase.reject(peerId);
  }

  Future<bool> verifyPairingPin(String peerId, String pin) async {
    return _pairPeerUseCase.verifyPin(peerId, pin);
  }

  Future<bool> verifyPairingQr(String rawQr) async {
    return _pairPeerUseCase.verifyQr(rawQr);
  }

  Future<void> disconnectPeer(String peerId) async {
    await _pairPeerUseCase.disconnect(peerId);
  }

  // -------------------------------------------------------------
  // DIRECT 1-ON-1 MESSAGING (TRUE E2EE)
  // -------------------------------------------------------------
  Future<bool> sendDirectText(String peerId, String text) async {
    return _sendMessageUseCase.sendDirectText(peerId, text);
  }

  Future<bool> editDirectMessage(String peerId, String messageId, String newText) async {
    return _sendMessageUseCase.editDirectMessage(peerId, messageId, newText);
  }

  Future<bool> sendDirectImage(String peerId, File file) async {
    return _sendMessageUseCase.sendDirectImage(peerId, file);
  }

  Future<bool> sendDirectAudio(String peerId, File file, int duration) async {
    return _sendMessageUseCase.sendDirectAudio(peerId, file, duration);
  }

  // -------------------------------------------------------------
  // CHAT GROUPS (WHATSAPP STYLE)
  // -------------------------------------------------------------
  Future<ChatGroupEntity> createGroup({
    required String name,
    String description = '',
    required List<String> memberIds,
  }) async {
    return _manageGroupsUseCase.createGroup(
      name: name,
      description: description,
      memberIds: memberIds,
    );
  }

  Future<bool> sendGroupText(String groupId, String text) async {
    return _sendMessageUseCase.sendGroupText(groupId, text);
  }

  Future<bool> editGroupMessage(String groupId, String messageId, String newText) async {
    return _sendMessageUseCase.editGroupMessage(groupId, messageId, newText);
  }

  Future<bool> sendGroupImage(String groupId, File file) async {
    return _sendMessageUseCase.sendGroupImage(groupId, file);
  }

  Future<bool> sendGroupAudio(String groupId, File file, int duration) async {
    return _sendMessageUseCase.sendGroupAudio(groupId, file, duration);
  }

  // -------------------------------------------------------------
  // MESH BROADCAST
  // -------------------------------------------------------------
  Future<bool> sendMeshBroadcastText(String text) async {
    return _sendMessageUseCase.sendMeshBroadcastText(text);
  }

  Future<bool> sendMeshBroadcastImage(File file) async {
    return _sendMessageUseCase.sendMeshBroadcastImage(file);
  }

  Future<bool> sendMeshBroadcastAudio(File file, int duration) async {
    return _sendMessageUseCase.sendMeshBroadcastAudio(file, duration);
  }

  // Backwards compatibility helper methods for screens/tests
  Future<void> requestConnection(String endpointId) => connectToPeer(endpointId);
  Future<void> accept(String endpointId) => acceptIncomingConnection(endpointId);
  Future<void> reject(String endpointId) => rejectIncomingConnection(endpointId);
  Future<void> send(String endpointId, String text) => sendDirectText(endpointId, text);
  Future<bool> sendImage(String endpointId, File file) => sendDirectImage(endpointId, file);
  Future<bool> sendAudio(String endpointId, File file, int duration) => sendDirectAudio(endpointId, file, duration);
  Future<bool> editMessage(String endpointId, String messageId, String newText) => editDirectMessage(endpointId, messageId, newText);
}
