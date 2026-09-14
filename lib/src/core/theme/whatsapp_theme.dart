import 'package:flutter/material.dart';

class WhatsAppTheme {
  // WhatsApp Signature Colors
  static const Color primaryTeal = Color(0xFF008069);
  static const Color darkTeal = Color(0xFF075E54);
  static const Color accentGreen = Color(0xFF25D366);
  static const Color checkBlue = Color(0xFF53BDEB);

  // Background Colors
  static const Color lightChatBg = Color(0xFFEFEAE2);
  static const Color darkChatBg = Color(0xFF0B141B);

  // Bubble Colors
  static const Color lightOutgoingBubble = Color(0xFFD9FDD3);
  static const Color darkOutgoingBubble = Color(0xFF005C4B);

  static const Color lightIncomingBubble = Color(0xFFFFFFFF);
  static const Color darkIncomingBubble = Color(0xFF202C33);

  // Text Colors
  static const Color senderAccentTeal = Color(0xFF075E54);
  static const Color senderAccentBlue = Color(0xFF1F7AC8);
  static const Color timestampLight = Color(0xFF667781);
  static const Color timestampDark = Color(0xFF8696A0);

  static ThemeData lightTheme() {
    return ThemeData(
      useMaterial3: true,
      brightness: Brightness.light,
      colorScheme: ColorScheme.fromSeed(
        seedColor: primaryTeal,
        primary: primaryTeal,
        secondary: accentGreen,
        surface: Colors.white,
        surfaceContainerLowest: lightChatBg,
      ),
      scaffoldBackgroundColor: lightChatBg,
      appBarTheme: const AppBarTheme(
        backgroundColor: primaryTeal,
        foregroundColor: Colors.white,
        elevation: 1,
        titleTextStyle: TextStyle(
          color: Colors.white,
          fontSize: 20,
          fontWeight: FontWeight.w600,
        ),
        iconTheme: IconThemeData(color: Colors.white),
      ),
      floatingActionButtonTheme: const FloatingActionButtonThemeData(
        backgroundColor: accentGreen,
        foregroundColor: Colors.white,
        elevation: 4,
      ),
    );
  }

  static ThemeData darkTheme() {
    return ThemeData(
      useMaterial3: true,
      brightness: Brightness.dark,
      colorScheme: ColorScheme.fromSeed(
        seedColor: primaryTeal,
        brightness: Brightness.dark,
        primary: primaryTeal,
        secondary: accentGreen,
        surface: const Color(0xFF121B22),
        surfaceContainerLowest: darkChatBg,
      ),
      scaffoldBackgroundColor: darkChatBg,
      appBarTheme: const AppBarTheme(
        backgroundColor: Color(0xFF1F2C34),
        foregroundColor: Colors.white,
        elevation: 1,
        titleTextStyle: TextStyle(
          color: Colors.white,
          fontSize: 20,
          fontWeight: FontWeight.w600,
        ),
        iconTheme: IconThemeData(color: Colors.white),
      ),
      floatingActionButtonTheme: const FloatingActionButtonThemeData(
        backgroundColor: accentGreen,
        foregroundColor: Colors.white,
        elevation: 4,
      ),
    );
  }
}
