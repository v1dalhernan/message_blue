import 'dart:convert';

enum MessageDirection { incoming, outgoing }

enum MessageDelivery { sending, sent, failed }

class ChatMessage {
  const ChatMessage({
    required this.id,
    required this.endpointId,
    required this.author,
    required this.text,
    required this.sentAt,
    required this.direction,
    this.delivery = MessageDelivery.sent,
  });

  final String id;
  final String endpointId;
  final String author;
  final String text;
  final DateTime sentAt;
  final MessageDirection direction;
  final MessageDelivery delivery;

  ChatMessage copyWith({MessageDelivery? delivery}) {
    return ChatMessage(
      id: id,
      endpointId: endpointId,
      author: author,
      text: text,
      sentAt: sentAt,
      direction: direction,
      delivery: delivery ?? this.delivery,
    );
  }

  List<int> toPayload() {
    return utf8.encode(
      jsonEncode({
        'version': 1,
        'type': 'message',
        'id': id,
        'author': author,
        'text': text,
        'sentAt': sentAt.toUtc().toIso8601String(),
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
        sentAt is! String ||
        text.trim().isEmpty) {
      throw const FormatException('El mensaje recibido está incompleto.');
    }

    return ChatMessage(
      id: id,
      endpointId: endpointId,
      author: author,
      text: text,
      sentAt: DateTime.parse(sentAt).toLocal(),
      direction: MessageDirection.incoming,
    );
  }
}
