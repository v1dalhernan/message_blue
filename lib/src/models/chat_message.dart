import 'dart:convert';

enum MessageDirection { incoming, outgoing }

enum MessageDelivery { sending, sent, failed }

enum ChatMessageType { text, image, audio }

class ChatMessage {
  const ChatMessage({
    required this.id,
    required this.endpointId,
    required this.author,
    required this.text,
    required this.sentAt,
    required this.direction,
    this.delivery = MessageDelivery.sent,
    this.type = ChatMessageType.text,
    this.mediaBase64,
    this.mediaPath,
    this.durationSeconds,
    this.isEdited = false,
    this.editedAt,
    this.isGroup = false,
    this.hopCount = 0,
  });

  static const String groupEndpointId = 'group-mesh-all';

  final String id;
  final String endpointId;
  final String author;
  final String text;
  final DateTime sentAt;
  final MessageDirection direction;
  final MessageDelivery delivery;
  final ChatMessageType type;
  final String? mediaBase64;
  final String? mediaPath;
  final int? durationSeconds;
  final bool isEdited;
  final DateTime? editedAt;
  final bool isGroup;
  final int hopCount;

  ChatMessage copyWith({
    String? endpointId,
    MessageDelivery? delivery,
    String? text,
    String? mediaPath,
    String? mediaBase64,
    bool? isEdited,
    DateTime? editedAt,
    bool? isGroup,
    int? hopCount,
  }) {
    return ChatMessage(
      id: id,
      endpointId: endpointId ?? this.endpointId,
      author: author,
      text: text ?? this.text,
      sentAt: sentAt,
      direction: direction,
      delivery: delivery ?? this.delivery,
      type: type,
      mediaBase64: mediaBase64 ?? this.mediaBase64,
      mediaPath: mediaPath ?? this.mediaPath,
      durationSeconds: durationSeconds,
      isEdited: isEdited ?? this.isEdited,
      editedAt: editedAt ?? this.editedAt,
      isGroup: isGroup ?? this.isGroup,
      hopCount: hopCount ?? this.hopCount,
    );
  }

  List<int> toPayload() {
    return utf8.encode(
      jsonEncode({
        'version': 2,
        'type': 'message',
        'id': id,
        'author': author,
        'text': text,
        'sentAt': sentAt.toUtc().toIso8601String(),
        'msgType': type.name,
        if (mediaBase64 != null) 'media': mediaBase64,
        if (durationSeconds != null) 'duration': durationSeconds,
        if (isEdited) 'isEdited': true,
        if (editedAt != null) 'editedAt': editedAt!.toUtc().toIso8601String(),
        if (isGroup) 'isGroup': true,
        if (hopCount > 0) 'hops': hopCount,
      }),
    );
  }

  static ChatMessage fromPayload({
    required String endpointId,
    required List<int> bytes,
  }) {
    final decoded = jsonDecode(utf8.decode(bytes));
    if (decoded is! Map<String, dynamic> || decoded['type'] != 'message') {
      throw const FormatException('Payload de mensaje no reconocido.');
    }

    final id = decoded['id'];
    final author = decoded['author'];
    final text = decoded['text'];
    final sentAt = decoded['sentAt'];
    if (id is! String ||
        author is! String ||
        text is! String ||
        sentAt is! String) {
      throw const FormatException('El mensaje recibido está incompleto.');
    }

    final msgTypeStr = decoded['msgType'] as String?;
    final msgType = switch (msgTypeStr) {
      'image' => ChatMessageType.image,
      'audio' => ChatMessageType.audio,
      _ => ChatMessageType.text,
    };

    final media = decoded['media'] as String?;
    if (msgType == ChatMessageType.text && text.trim().isEmpty) {
      throw const FormatException('El mensaje de texto no puede estar vacío.');
    }

    return ChatMessage(
      id: id,
      endpointId: endpointId,
      author: author,
      text: text,
      sentAt: DateTime.parse(sentAt).toLocal(),
      direction: MessageDirection.incoming,
      type: msgType,
      mediaBase64: media,
      durationSeconds: decoded['duration'] as int?,
      isEdited: decoded['isEdited'] == true,
      editedAt: decoded['editedAt'] != null
          ? DateTime.parse(decoded['editedAt'] as String).toLocal()
          : null,
      isGroup: decoded['isGroup'] == true,
      hopCount: (decoded['hops'] as int?) ?? 0,
    );
  }
}

class ChatMessageEdit {
  const ChatMessageEdit({
    required this.id,
    required this.targetId,
    required this.text,
    required this.editedAt,
    this.isGroup = false,
  });

  final String id;
  final String targetId;
  final String text;
  final DateTime editedAt;
  final bool isGroup;

  List<int> toPayload() {
    return utf8.encode(
      jsonEncode({
        'version': 2,
        'type': 'edit',
        'id': id,
        'targetId': targetId,
        'text': text,
        'editedAt': editedAt.toUtc().toIso8601String(),
        if (isGroup) 'isGroup': true,
      }),
    );
  }

  static ChatMessageEdit fromJson(Map<String, dynamic> decoded) {
    final id = decoded['id'];
    final targetId = decoded['targetId'];
    final text = decoded['text'];
    final editedAt = decoded['editedAt'];

    if (id is! String ||
        targetId is! String ||
        text is! String ||
        editedAt is! String ||
        text.trim().isEmpty) {
      throw const FormatException('Payload de edición inválido.');
    }

    return ChatMessageEdit(
      id: id,
      targetId: targetId,
      text: text,
      editedAt: DateTime.parse(editedAt).toLocal(),
      isGroup: decoded['isGroup'] == true,
    );
  }
}
