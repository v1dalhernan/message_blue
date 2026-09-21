
import 'package:flutter_test/flutter_test.dart';
import 'package:message_blue/src/chat_controller.dart';
import 'package:message_blue/src/models/chat_message.dart';
import 'package:message_blue/src/nearby/nearby_event.dart';

import '../widget_test.dart' show FakeNearbyTransport;

void main() {
  test('system alerts exclude visible chat, include other chats, groups and background', () async {
    final transport = FakeNearbyTransport();
    final controller = ChatController(transport);
    final notifications = <ChatMessage>[];
    controller.incomingMessageNotifications.listen(notifications.add);
    addTearDown(controller.dispose);
    controller.openChat('alice');
    var id = 0;
    Future<void> receive(String endpoint, {bool group = false}) async {
      transport.add(
        MessageReceived(
          ChatMessage(
            id: '${id++}',
            endpointId: endpoint,
            author: endpoint,
            text: 'Hola',
            sentAt: DateTime.now(),
            direction: MessageDirection.incoming,
            isGroup: group,
          ),
        ),
      );
      await Future<void>.delayed(Duration.zero);
    }

    await receive('alice');
    expect(notifications, isEmpty);
    expect(controller.getUnreadCount('alice'), 0);
    await receive('bob');
    expect(notifications.length, 1);
    expect(controller.getUnreadCount('bob'), 1);
    controller.setForeground(false);
    await receive('alice');
    expect(notifications.length, 2);
    expect(controller.getUnreadCount('alice'), 1);
    controller.setForeground(true);
    await Future<void>.delayed(Duration.zero);
    expect(controller.getUnreadCount('alice'), 0);
    controller.closeChat('alice');
    await receive('alice', group: true);
    expect(notifications.length, 3);
    controller.openChat(ChatMessage.groupEndpointId);
    await receive('alice', group: true);
    expect(notifications.length, 3);
    expect(controller.getUnreadCount(ChatMessage.groupEndpointId), 0);
  });
}
