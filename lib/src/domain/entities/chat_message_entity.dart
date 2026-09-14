enum MessageType {
  text,
  image,
  audio,
  system,
}

enum MessageDeliveryStatus {
  pending,
  sending,
  sent,
  delivered,
  read,
  failed,
}

class ChatMessageEntity {
  const ChatMessageEntity({
    required this.id,
    required this.senderId,
    required this.senderName,
    required this.recipientId,
    this.groupId,
    this.text = '',
    this.type = MessageType.text,
    this.mediaPath,
    this.mediaBase64,
    this.durationSeconds,
    required this.timestamp,
    required this.isOutgoing,
    this.status = MessageDeliveryStatus.sent,
    this.isEdited = false,
    this.editedAt,
    this.hops = 0,
    this.route = const [],
    this.isGroup = false,
  });

  final String id;
  final String senderId;
  final String senderName;
  final String recipientId;
  final String? groupId;
  final String text;
  final MessageType type;
  final String? mediaPath;
  final String? mediaBase64;
  final int? durationSeconds;
  final DateTime timestamp;
  final bool isOutgoing;
  final MessageDeliveryStatus status;
  final bool isEdited;
  final DateTime? editedAt;
  final int hops;
  final List<String> route;
  final bool isGroup;

  bool get isBroadcast => recipientId == '*';

  ChatMessageEntity copyWith({
    String? id,
    String? senderId,
    String? senderName,
    String? recipientId,
    String? groupId,
    String? text,
    MessageType? type,
    String? mediaPath,
    String? mediaBase64,
    int? durationSeconds,
    DateTime? timestamp,
    bool? isOutgoing,
    MessageDeliveryStatus? status,
    bool? isEdited,
    DateTime? editedAt,
    int? hops,
    List<String>? route,
    bool? isGroup,
  }) {
    return ChatMessageEntity(
      id: id ?? this.id,
      senderId: senderId ?? this.senderId,
      senderName: senderName ?? this.senderName,
      recipientId: recipientId ?? this.recipientId,
      groupId: groupId ?? this.groupId,
      text: text ?? this.text,
      type: type ?? this.type,
      mediaPath: mediaPath ?? this.mediaPath,
      mediaBase64: mediaBase64 ?? this.mediaBase64,
      durationSeconds: durationSeconds ?? this.durationSeconds,
      timestamp: timestamp ?? this.timestamp,
      isOutgoing: isOutgoing ?? this.isOutgoing,
      status: status ?? this.status,
      isEdited: isEdited ?? this.isEdited,
      editedAt: editedAt ?? this.editedAt,
      hops: hops ?? this.hops,
      route: route ?? this.route,
      isGroup: isGroup ?? this.isGroup,
    );
  }
}
