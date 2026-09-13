import 'package:flutter_test/flutter_test.dart';
import 'package:message_blue/src/models/chat_message.dart';

void main() {
  test('round-trips a text message through the wire payload', () {
    final original = ChatMessage(
      id: 'message-1',
      endpointId: 'receiver-1',
      author: 'Ana',
      text: 'Mensaje local',
      sentAt: DateTime.utc(2026, 9, 13, 14, 30),
      direction: MessageDirection.outgoing,
    );

    final received = ChatMessage.fromPayload(
      endpointId: 'sender-1',
      bytes: original.toPayload(),
    );

    expect(received.id, original.id);
    expect(received.author, 'Ana');
    expect(received.text, 'Mensaje local');
    expect(received.endpointId, 'sender-1');
    expect(received.direction, MessageDirection.incoming);
    expect(received.sentAt.toUtc(), original.sentAt);
  });

  test('rejects an unsupported payload', () {
    expect(
      () => ChatMessage.fromPayload(
        endpointId: 'sender-1',
        bytes: '{"type":"file"}'.codeUnits,
      ),
      throwsFormatException,
    );
  });
}
