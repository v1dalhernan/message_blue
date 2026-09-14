import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:path_provider/path_provider.dart';

/// Servicio de Perfil de Usuario y Fotos de Perfil (Avatares) estilo WhatsApp.
class UserProfileService {
  UserProfileService._();
  static final UserProfileService instance = UserProfileService._();

  String? _localAvatarBase64;
  String? _localAvatarPath;
  String _statusMessage = '¡Hola! Estoy usando BlueMesh.';
  
  // Cache de fotos de perfil de los contactos/pares de la malla
  final Map<String, String> _peerAvatars = {}; // endpointId -> avatarBase64

  String? get localAvatarBase64 => _localAvatarBase64;
  String? get localAvatarPath => _localAvatarPath;
  String get statusMessage => _statusMessage;

  void setStatusMessage(String status) {
    _statusMessage = status;
  }

  /// Guarda una foto de perfil seleccionada por el usuario (desde archivo o galería)
  Future<String?> setAvatarFromFile(File imageFile) async {
    try {
      final bytes = await imageFile.readAsBytes();
      // Guardar copia local
      final dir = await getApplicationDocumentsDirectory();
      final localFile = File('${dir.path}/my_profile_avatar.jpg');
      await localFile.writeAsBytes(bytes);
      _localAvatarPath = localFile.path;

      // Generar base64 para transmitir en anuncios de la malla
      _localAvatarBase64 = base64Encode(bytes);
      return _localAvatarBase64;
    } catch (e) {
      debugPrint('Error guardando avatar de perfil: $e');
      return null;
    }
  }

  /// Asigna un avatar predefinido con emoji/icono para selección rápida
  void setPresetAvatar(String presetKey) {
    _localAvatarPath = null;
    _localAvatarBase64 = 'preset:$presetKey';
  }

  /// Registra el avatar recibido de un par
  void setPeerAvatar(String endpointId, String? avatarBase64) {
    if (avatarBase64 != null && avatarBase64.isNotEmpty) {
      _peerAvatars[endpointId] = avatarBase64;
    }
  }

  String? getPeerAvatar(String endpointId) => _peerAvatars[endpointId];

  /// Permite seleccionar una imagen desde la galería o cámara
  Future<bool> pickAvatar(ImageSource source) async {
    try {
      final picker = ImagePicker();
      final picked = await picker.pickImage(
        source: source,
        maxWidth: 256,
        maxHeight: 256,
        imageQuality: 70,
      );
      if (picked == null) return false;
      final file = File(picked.path);
      await setAvatarFromFile(file);
      return true;
    } catch (e) {
      debugPrint('Error seleccionando imagen de perfil: $e');
      return false;
    }
  }
}
