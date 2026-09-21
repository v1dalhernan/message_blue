import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:message_blue/src/core/storage/chat_history_store.dart';
import 'package:message_blue/src/core/identity/user_identity_service.dart';
import 'package:message_blue/src/models/chat_message.dart';

void main() {
  test('history preserves media and resumes interrupted outgoing messages', () async {
    final directory = await Directory.systemTemp.createTemp('trama-history-test-');
    addTearDown(() => directory.delete(recursive: true));
    final store = ChatHistoryStore(File('${directory.path}/history.json'));
    final message = ChatMessage(id: 'one', endpointId: 'stable-peer', author: 'Alice',
      text: 'foto', sentAt: DateTime.utc(2026), direction: MessageDirection.outgoing,
      delivery: MessageDelivery.sending, type: ChatMessageType.image, mediaBase64: 'AQID');
    final first = store.write({'messages': []});
    final last = store.write({'messages': [ChatHistoryStore.encode(message)]});
    await Future.wait([first, last]);
    final data = await ChatHistoryStore(store.file).read();
    final restored = ChatHistoryStore.decode((data!['messages'] as List).single as Map<String, dynamic>);
    expect(restored.endpointId, 'stable-peer');
    expect(restored.direction, MessageDirection.outgoing);
    expect(restored.delivery, MessageDelivery.inMailbox);
    expect(restored.mediaBase64, 'AQID');
  });

  test('PIN matches RFC 6238 and validates receiver clock at rotation boundaries', () {
    final identity = UserIdentityService.instance;
    identity.setDeviceSecret('12345678901234567890');
    final instant = DateTime.fromMillisecondsSinceEpoch(59000, isUtc: true);
    expect(identity.getCurrentPin(instant), '287082');
    expect(identity.isValidPin('287082', instant.add(const Duration(seconds: 1))), isTrue);
    expect(identity.isValidPin('287082', instant.add(const Duration(seconds: 61))), isFalse);
    expect(identity.isValidPin('abcdef', instant), isFalse);
  });
}
