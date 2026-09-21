import 'dart:io';

import 'package:flutter/material.dart';

import 'src/nearby/demo_nearby_transport.dart';
import 'src/nearby/lan_socket_transport.dart';
import 'src/nearby/nearby_connections_transport.dart';
import 'src/nearby/nearby_transport.dart';
import 'src/nearby/mesh_transport.dart';
import 'src/screens/home_page.dart';
import 'src/screens/widgets/chat_visibility.dart';

void main() {
  runApp(const BlueMeshApp());
}

class BlueMeshApp extends StatelessWidget {
  const BlueMeshApp({
    super.key,
    this.transport,
    this.enablePlatformServices = true,
  });

  final NearbyTransport? transport;
  final bool enablePlatformServices;

  @override
  Widget build(BuildContext context) {
    const seedColor = Color(0xFF176B87);

    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'Trama',
      navigatorObservers: [chatRouteObserver],
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: seedColor,
          brightness: Brightness.light,
        ),
        scaffoldBackgroundColor: const Color(0xFFF5F8FA),
        appBarTheme: const AppBarTheme(
          backgroundColor: Color(0xFFF5F8FA),
          surfaceTintColor: Colors.transparent,
        ),
        cardTheme: const CardThemeData(elevation: 0, margin: EdgeInsets.zero),
        inputDecorationTheme: const InputDecorationTheme(
          border: OutlineInputBorder(),
        ),
        useMaterial3: true,
      ),
      home: HomePage(
        transport: transport ?? _defaultTransport(),
        enablePlatformServices: enablePlatformServices,
      ),
    );
  }

  NearbyTransport _defaultTransport() {
    const demoMode = bool.fromEnvironment('DEMO_MODE');
    if (demoMode) return DemoNearbyTransport();

    const lanMode = bool.fromEnvironment('LAN_MODE', defaultValue: false);
    if (lanMode || !Platform.isAndroid) {
      return MeshTransport(LanSocketTransport());
    }

    return MeshTransport(NearbyConnectionsTransport());
  }
}
