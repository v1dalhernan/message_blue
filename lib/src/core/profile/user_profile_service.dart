import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:path_provider/path_provider.dart';

import '../identity/user_identity_service.dart';

/// Servicio de Perfil de Usuario y Fotos de Perfil (avatares).
class UserProfileService {
  UserProfileService._();
  static final UserProfileService instance = UserProfileService._();

  String _displayName = 'Android cercano';
  String? _localAvatarBase64;
  String? _localAvatarPath;
  String _statusMessage = '¡Hola! Estoy usando Trama.';
  Future<void>? _loading;
  Future<void> _saving = Future.value();

  // Cache de fotos de perfil de los contactos/pares de la malla
  final Map<String, String> _peerAvatars = {}; // endpointId -> avatarBase64

  String get displayName => _displayName;
  String? get localAvatarBase64 => _localAvatarBase64;
  String? get localAvatarPath => _localAvatarPath;
  String get statusMessage => _statusMessage;

  Future<void> loadProfile() => _loading ??= _loadProfile();

  Future<void> _loadProfile() async {
    try {
      final dir = await getApplicationDocumentsDirectory();
      final file = File('${dir.path}/user_profile.json');
      if (await file.exists()) {
        final data =
            jsonDecode(await file.readAsString()) as Map<String, dynamic>;
        if (data['displayName'] is String &&
            (data['displayName'] as String).isNotEmpty) {
          _displayName = data['displayName'] as String;
        }
        if (data['statusMessage'] is String &&
            (data['statusMessage'] as String).isNotEmpty) {
          _statusMessage = data['statusMessage'] as String;
        }
        if (data['avatarBase64'] is String &&
            (data['avatarBase64'] as String).isNotEmpty) {
          _localAvatarBase64 = data['avatarBase64'] as String;
        }
        if (data['deviceSecret'] is String &&
            (data['deviceSecret'] as String).isNotEmpty) {
          UserIdentityService.instance.setDeviceSecret(
            data['deviceSecret'] as String,
          );
        } else {
          await _saveProfile();
        }
      } else {
        await _saveProfile();
      }
    } catch (_) {}
  }

  Future<void> _saveProfile() {
    final snapshot = jsonEncode({
      'displayName': _displayName,
      'statusMessage': _statusMessage,
      'avatarBase64': _localAvatarBase64,
      'deviceSecret': UserIdentityService.instance.deviceSecret,
    });
    return _saving = _saving.then((_) async {
      try {
        final dir = await getApplicationDocumentsDirectory();
        final file = File('${dir.path}/user_profile.json');
        final temp = File('${file.path}.tmp');
        await temp.writeAsString(snapshot, flush: true);
        await temp.rename(file.path);
      } catch (_) {}
    });
  }

  void setDisplayName(String name) {
    if (name.trim().isNotEmpty) {
      _displayName = name.trim();
      _saveProfile();
    }
  }

  void setStatusMessage(String status) {
    _statusMessage = status.trim();
    _saveProfile();
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
      await _saveProfile();
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
    _saveProfile();
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
