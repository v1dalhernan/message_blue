import 'package:flutter/widgets.dart';

import '../../chat_controller.dart';

final chatRouteObserver = RouteObserver<ModalRoute<void>>();

mixin ChatVisibility<T extends StatefulWidget> on State<T>
    implements RouteAware {
  ChatController get chatController;
  String get visibleChatId;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final route = ModalRoute.of(context);
    if (route != null) chatRouteObserver.subscribe(this, route);
  }

  @override
  void didPush() => chatController.openChat(visibleChatId);
  @override
  void didPopNext() => chatController.openChat(visibleChatId);
  @override
  void didPushNext() => chatController.closeChat(visibleChatId);
  @override
  void didPop() => chatController.closeChat(visibleChatId);

  @override
  void dispose() {
    chatRouteObserver.unsubscribe(this);
    chatController.closeChat(visibleChatId);
    super.dispose();
  }
}
