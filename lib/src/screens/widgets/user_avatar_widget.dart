import 'dart:convert';
import 'package:flutter/material.dart';

/// Widget unificado para mostrar avatares de perfil (fotos o emojis predefinidos)
/// con diseño consistente estilo WhatsApp en toda la aplicación.
class UserAvatarWidget extends StatelessWidget {
  const UserAvatarWidget({
    super.key,
    this.avatarBase64,
    required this.name,
    this.radius = 22,
    this.onTap,
  });

  final String? avatarBase64;
  final String name;
  final double radius;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    Widget avatarWidget;
    if (avatarBase64 != null && avatarBase64!.startsWith('preset:')) {
      final emoji = avatarBase64!.replaceFirst('preset:', '');
      avatarWidget = CircleAvatar(
        radius: radius,
        backgroundColor: Theme.of(context).colorScheme.primaryContainer,
        child: Text(emoji, style: TextStyle(fontSize: radius * 1.1)),
      );
    } else if (avatarBase64 != null && avatarBase64!.isNotEmpty) {
      try {
        final bytes = base64Decode(avatarBase64!);
        avatarWidget = CircleAvatar(
          radius: radius,
          backgroundImage: MemoryImage(bytes),
        );
      } catch (_) {
        avatarWidget = _fallbackAvatar(context);
      }
    } else {
      avatarWidget = _fallbackAvatar(context);
    }

    if (onTap != null) {
      return GestureDetector(
        onTap: onTap,
        child: Stack(
          alignment: Alignment.bottomRight,
          children: [
            avatarWidget,
            Container(
              padding: const EdgeInsets.all(3),
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.primary,
                shape: BoxShape.circle,
              ),
              child: const Icon(
                Icons.camera_alt,
                size: 11,
                color: Colors.white,
              ),
            ),
          ],
        ),
      );
    }
    return avatarWidget;
  }

  Widget _fallbackAvatar(BuildContext context) {
    return CircleAvatar(
      radius: radius,
      backgroundColor: Theme.of(context).colorScheme.primaryContainer,
      child: Text(
        name.isNotEmpty ? name[0].toUpperCase() : '?',
        style: TextStyle(
          fontSize: radius * 0.9,
          fontWeight: FontWeight.bold,
          color: Theme.of(context).colorScheme.onPrimaryContainer,
        ),
      ),
    );
  }
}
