import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:message_blue/src/models/chat_message.dart';

void main() {
  group('Multimedia & Edit Payloads', () {
    test('serializes and deserializes image message', () {
      final message = ChatMessage(
        id: 'msg-img-1',
        endpointId: 'peer-2',
        author: 'Jhonathan',
        text: 'Mira esta foto',
        sentAt: DateTime.utc(2026, 9, 13, 19, 0),
        direction: MessageDirection.outgoing,
        type: ChatMessageType.image,
        mediaBase64: 'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mNk+M9QDwADhgGAWjR9awAAAABJRU5ErkJggg==',
      );

      final payload = message.toPayload();
      final restored = ChatMessage.fromPayload(
        endpointId: 'peer-1',
        bytes: payload,
      );

      expect(restored.type, ChatMessageType.image);
      expect(restored.text, 'Mira esta foto');
      expect(restored.mediaBase64, isNotNull);
      expect(restored.direction, MessageDirection.incoming);
    });

    test('serializes and deserializes voice note message', () {
      final message = ChatMessage(
        id: 'msg-audio-1',
        endpointId: 'peer-2',
        author: 'Jhonathan',
        text: 'Nota de voz (5s)',
        sentAt: DateTime.utc(2026, 9, 13, 19, 5),
        direction: MessageDirection.outgoing,
        type: ChatMessageType.audio,
        mediaBase64: 'AAAAHGZ0eXBNNEEgAAAAAE00QSBtcDQyaXNvbQ==',
        durationSeconds: 5,
      );

      final payload = message.toPayload();
      final restored = ChatMessage.fromPayload(
        endpointId: 'peer-1',
        bytes: payload,
      );

      expect(restored.type, ChatMessageType.audio);
      expect(restored.durationSeconds, 5);
      expect(restored.mediaBase64, isNotNull);
    });

    test('serializes and deserializes message edit payload', () {
      final edit = ChatMessageEdit(
        id: 'edit-1',
        targetId: 'msg-text-1',
        text: 'Texto corregido y editado',
        editedAt: DateTime.utc(2026, 9, 13, 19, 10),
      );

      final payload = edit.toPayload();
      final decoded = jsonDecode(utf8.decode(payload)) as Map<String, dynamic>;
      final restored = ChatMessageEdit.fromJson(decoded);

      expect(restored.targetId, 'msg-text-1');
      expect(restored.text, 'Texto corregido y editado');
      expect(restored.editedAt.toUtc(), edit.editedAt);
    });
  });
}
