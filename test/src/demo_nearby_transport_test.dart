import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:message_blue/src/models/chat_message.dart';
import 'package:message_blue/src/nearby/demo_nearby_transport.dart';
import 'package:message_blue/src/nearby/nearby_event.dart';

void main() {
  test('demo transport exercises an encrypted round trip', () async {
    final transport = DemoNearbyTransport();
    addTearDown(transport.dispose);
    final events = <NearbyEvent>[];
    final subscription = transport.events.listen(events.add);
    addTearDown(subscription.cancel);

    await transport.start('Emulador');
    await transport.requestConnection('demo-ana', 'Emulador');
    await transport.acceptConnection('demo-ana');

    final message = ChatMessage(
      id: 'demo-message',
      endpointId: 'demo-ana',
      author: 'Emulador',
      text: 'texto que no debe viajar visible',
      sentAt: DateTime.utc(2026, 9, 13),
      direction: MessageDirection.outgoing,
    );
    await transport.sendMessage(message);
    await Future<void>.delayed(Duration.zero);

    expect(
      utf8.decode(transport.lastWirePayload!),
      isNot(contains(message.text)),
    );
    expect(events.whereType<SecureChannelReady>(), hasLength(1));
    expect(events.whereType<MessageReceived>(), hasLength(1));
  });
}
