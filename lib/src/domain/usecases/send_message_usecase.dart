import 'dart:io';
import '../repositories/chat_repository.dart';

class SendMessageUseCase {
  const SendMessageUseCase(this._repository);

  final ChatRepository _repository;

  Future<bool> sendDirectText(String peerId, String text) =>
      _repository.sendDirectText(peerId, text);

  Future<bool> editDirectMessage(String peerId, String messageId, String newText) =>
      _repository.editDirectMessage(peerId, messageId, newText);

  Future<bool> sendDirectImage(String peerId, File image) =>
      _repository.sendDirectImage(peerId, image);

  Future<bool> sendDirectAudio(String peerId, File audio, int duration) =>
      _repository.sendDirectAudio(peerId, audio, duration);

  Future<bool> sendGroupText(String groupId, String text) =>
      _repository.sendGroupText(groupId, text);

  Future<bool> editGroupMessage(String groupId, String messageId, String newText) =>
      _repository.editGroupMessage(groupId, messageId, newText);

  Future<bool> sendGroupImage(String groupId, File image) =>
      _repository.sendGroupImage(groupId, image);

  Future<bool> sendGroupAudio(String groupId, File audio, int duration) =>
      _repository.sendGroupAudio(groupId, audio, duration);

  Future<bool> sendMeshBroadcastText(String text) =>
      _repository.sendMeshBroadcastText(text);

  Future<bool> sendMeshBroadcastImage(File image) =>
      _repository.sendMeshBroadcastImage(image);

  Future<bool> sendMeshBroadcastAudio(File audio, int duration) =>
      _repository.sendMeshBroadcastAudio(audio, duration);
}
