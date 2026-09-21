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
    this.showBadge = true,
  });

  final String? avatarBase64;
  final String name;
  final double radius;
  final VoidCallback? onTap;
  final bool showBadge;

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
      final badgeIconSize = (radius * 0.35).clamp(11.0, 22.0);
      final badgePadding = (radius * 0.08).clamp(3.0, 6.0);
      final borderWidth = (radius * 0.05).clamp(1.5, 3.0);

      return GestureDetector(
        onTap: onTap,
        child: Stack(
          alignment: Alignment.bottomRight,
          children: [
            avatarWidget,
            if (showBadge)
              Container(
                padding: EdgeInsets.all(badgePadding),
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.primary,
                  shape: BoxShape.circle,
                  border: Border.all(
                    color: Theme.of(context).colorScheme.surface,
                    width: borderWidth,
                  ),
                ),
                child: Icon(
                  Icons.camera_alt,
                  size: badgeIconSize,
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
    final trimmed = name.trim();
    return CircleAvatar(
      radius: radius,
      backgroundColor: Theme.of(context).colorScheme.primaryContainer,
      child: Text(
        trimmed.isNotEmpty ? trimmed[0].toUpperCase() : '?',
        style: TextStyle(
          fontSize: radius * 0.9,
          fontWeight: FontWeight.bold,
          color: Theme.of(context).colorScheme.onPrimaryContainer,
        ),
      ),
    );
  }
}
