import 'chat_message_entity.dart';

class ChatGroupEntity {
  const ChatGroupEntity({
    required this.id,
    required this.name,
    this.description = '',
    required this.creatorId,
    required this.memberIds,
    required this.createdAt,
    required this.groupSecretKey,
    this.lastMessage,
    this.unreadCount = 0,
  });

  final String id;
  final String name;
  final String description;
  final String creatorId;
  final List<String> memberIds;
  final DateTime createdAt;
  final String groupSecretKey;
  final ChatMessageEntity? lastMessage;
  final int unreadCount;

  bool isMember(String endpointId) => memberIds.contains(endpointId);

  ChatGroupEntity copyWith({
    String? id,
    String? name,
    String? description,
    String? creatorId,
    List<String>? memberIds,
    DateTime? createdAt,
    String? groupSecretKey,
    ChatMessageEntity? lastMessage,
    int? unreadCount,
  }) {
    return ChatGroupEntity(
      id: id ?? this.id,
      name: name ?? this.name,
      description: description ?? this.description,
      creatorId: creatorId ?? this.creatorId,
      memberIds: memberIds ?? this.memberIds,
      createdAt: createdAt ?? this.createdAt,
      groupSecretKey: groupSecretKey ?? this.groupSecretKey,
      lastMessage: lastMessage ?? this.lastMessage,
      unreadCount: unreadCount ?? this.unreadCount,
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'description': description,
        'creatorId': creatorId,
        'memberIds': memberIds,
        'createdAt': createdAt.millisecondsSinceEpoch,
        'key': groupSecretKey,
      };

  factory ChatGroupEntity.fromJson(Map<String, dynamic> json) => ChatGroupEntity(
        id: json['id'] as String,
        name: json['name'] as String,
        description: json['description'] as String? ?? '',
        creatorId: json['creatorId'] as String,
        memberIds: (json['memberIds'] as List<dynamic>).cast<String>(),
        createdAt: DateTime.fromMillisecondsSinceEpoch(json['createdAt'] as int),
        groupSecretKey: json['key'] as String,
      );
}
