import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

import '../../models/chat_message.dart';

class ChatNotifications {
  final FlutterLocalNotificationsPlugin _plugin =
      FlutterLocalNotificationsPlugin();
  Future<void>? _initialization;
  void Function(String)? onOpenChat;

  Future<void> initialize() => _initialization ??= _initialize();

  Future<void> _initialize() async {
    if (!Platform.isAndroid && !Platform.isIOS && !Platform.isMacOS) return;
    const darwin = DarwinInitializationSettings(
      requestAlertPermission: false,
      requestBadgePermission: false,
      requestSoundPermission: false,
    );
    await _plugin.initialize(
      const InitializationSettings(
        android: AndroidInitializationSettings('ic_notification'),
        iOS: darwin,
        macOS: darwin,
      ),
      onDidReceiveNotificationResponse: (response) {
        final chat = response.payload;
        if (chat != null) onOpenChat?.call(chat);
      },
    );
    final launch = await _plugin.getNotificationAppLaunchDetails();
    final chat = launch?.notificationResponse?.payload;
    if (launch?.didNotificationLaunchApp == true && chat != null) {
      onOpenChat?.call(chat);
    }
  }

  Future<void> requestPermission() async {
    await initialize();
    await _plugin
        .resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin
        >()
        ?.requestNotificationsPermission();
    await _plugin
        .resolvePlatformSpecificImplementation<
          IOSFlutterLocalNotificationsPlugin
        >()
        ?.requestPermissions(alert: true, badge: true, sound: true);
    await _plugin
        .resolvePlatformSpecificImplementation<
          MacOSFlutterLocalNotificationsPlugin
        >()
        ?.requestPermissions(alert: true, badge: true, sound: true);
  }

  static String chatId(ChatMessage message) =>
      message.isGroup ? ChatMessage.groupEndpointId : message.endpointId;

  // Stable across launches, unlike a platform dependent String.hashCode.
  static int notificationId(String chat) {
    var hash = 2166136261;
    for (final byte in chat.codeUnits) {
      hash = ((hash ^ byte) * 16777619) & 0x7fffffff;
    }
    return hash;
  }

  Future<void> show(
    ChatMessage message, {
    required bool Function() shouldShow,
  }) async {
    await initialize();
    if (!shouldShow()) return;
    final chat = chatId(message);
    await _plugin.show(
      notificationId(chat),
      message.isGroup ? 'Sala de la malla · ${message.author}' : message.author,
      switch (message.type) {
        ChatMessageType.text => message.text,
        ChatMessageType.image => 'Foto',
        ChatMessageType.audio => 'Nota de voz',
      },
      const NotificationDetails(
        android: AndroidNotificationDetails(
          'trama_messages',
          'Mensajes',
          channelDescription: 'Mensajes de conversaciones que no estás viendo',
          importance: Importance.high,
          priority: Priority.high,
          category: AndroidNotificationCategory.message,
          visibility: NotificationVisibility.private,
        ),
        iOS: DarwinNotificationDetails(presentAlert: true, presentSound: true),
        macOS: DarwinNotificationDetails(
          presentAlert: true,
          presentSound: true,
        ),
      ),
      payload: chat,
    );
    if (!shouldShow()) await cancel(chat);
  }

  Future<void> cancel(String chat) async {
    await initialize();
    await _plugin.cancel(notificationId(chat));
  }

  static const _network = MethodChannel('trama/network');
  static Future<void> setNetworkActive(bool active) async {
    if (!Platform.isAndroid) return;
    try {
      await _network.invokeMethod<void>(active ? 'start' : 'stop');
    } on MissingPluginException {
      // Tests and desktop previews do not have the Android service.
    } on PlatformException catch (error) {
      debugPrint('No se pudo cambiar el servicio de red: ${error.message}');
      rethrow;
    }
  }
}
