import 'dart:convert';
import 'dart:io';

import '../../models/chat_message.dart';

class ChatHistoryStore {
  ChatHistoryStore(this.file);
  final File file;
  Future<void> _writes = Future.value();

  Future<Map<String, dynamic>?> read() async {
    if (!await file.exists()) return null;
    return jsonDecode(await file.readAsString()) as Map<String, dynamic>;
  }

  static Map<String, dynamic> encode(ChatMessage message) => {
    'endpoint': message.endpointId,
    'direction': message.direction.name,
    'delivery': message.delivery.name,
    'payload': jsonDecode(utf8.decode(message.toPayload())),
  };

  static ChatMessage decode(Map<String, dynamic> json) {
    final decoded = ChatMessage.fromPayload(
      endpointId: json['endpoint'] as String,
      bytes: utf8.encode(jsonEncode(json['payload'])),
    );
    var delivery = MessageDelivery.values.byName(json['delivery'] as String);
    if (delivery == MessageDelivery.sending) {
      delivery = MessageDelivery.inMailbox;
    }
    return ChatMessage(
      id: decoded.id,
      endpointId: decoded.endpointId,
      author: decoded.author,
      text: decoded.text,
      sentAt: decoded.sentAt,
      direction: MessageDirection.values.byName(json['direction'] as String),
      delivery: delivery,
      type: decoded.type,
      mediaBase64: decoded.mediaBase64,
      durationSeconds: decoded.durationSeconds,
      isEdited: decoded.isEdited,
      editedAt: decoded.editedAt,
      isGroup: decoded.isGroup,
      hopCount: decoded.hopCount,
      authorAvatar: decoded.authorAvatar,
    );
  }

  Future<void> write(Map<String, dynamic> snapshot) {
    final contents = jsonEncode(snapshot);
    final next = _writes.then((_) async {
      await file.parent.create(recursive: true);
      final temp = File('${file.path}.tmp');
      await temp.writeAsString(contents, flush: true);
      await temp.rename(file.path);
    });
    _writes = next.catchError((Object _) {});
    return next;
  }
}
