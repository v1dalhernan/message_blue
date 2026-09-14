import 'dart:io';
import '../entities/peer_entity.dart';
import '../entities/chat_message_entity.dart';
import '../entities/chat_group_entity.dart';
import '../entities/pairing_session_entity.dart';

abstract class ChatRepository {
  Stream<List<PeerEntity>> get peersStream;
  Stream<List<ChatMessageEntity>> get messagesStream;
  Stream<List<ChatGroupEntity>> get groupsStream;
  Stream<PairingSessionEntity?> get pairingSessionStream;

  String get localEndpointId;
  String get localDeviceName;

  Future<void> start({required String deviceName});
  Future<void> stop();

  Future<void> connectToPeer(String peerId);
  Future<void> acceptIncomingConnection(String peerId);
  Future<void> rejectIncomingConnection(String peerId);
  Future<bool> verifyPairingPin(String peerId, String pin);
  Future<bool> verifyPairingQr(String rawQr);
  Future<void> disconnectPeer(String peerId);

  Future<bool> sendDirectText(String peerId, String text);
  Future<bool> editDirectMessage(String peerId, String messageId, String newText);
  Future<bool> sendDirectImage(String peerId, File imageFile);
  Future<bool> sendDirectAudio(String peerId, File audioFile, int durationSeconds);

  Future<ChatGroupEntity> createGroup({
    required String name,
    String description = '',
    required List<String> memberIds,
  });
  Future<bool> sendGroupText(String groupId, String text);
  Future<bool> editGroupMessage(String groupId, String messageId, String newText);
  Future<bool> sendGroupImage(String groupId, File imageFile);
  Future<bool> sendGroupAudio(String groupId, File audioFile, int durationSeconds);

  Future<bool> sendMeshBroadcastText(String text);
  Future<bool> sendMeshBroadcastImage(File imageFile);
  Future<bool> sendMeshBroadcastAudio(File audioFile, int durationSeconds);
}
