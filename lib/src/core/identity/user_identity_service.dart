import 'dart:convert';
import 'dart:math';
import 'package:cryptography/cryptography.dart';

/// Servicio de Identidad Criptográfica, Anti-Suplantación y Códigos 2FA Dinámicos (TOTP).
/// Genera un identificador único persistente (Fingerprint) para evitar que
/// un atacante o dispositivo malicioso se haga pasar por otro usuario,
/// y códigos de enlace temporales de 6 dígitos que rotan cada 30 segundos.
class UserIdentityService {
  UserIdentityService._();
  static final UserIdentityService instance = UserIdentityService._();

  String? _cachedUniqueId;
  String? _cachedFingerprint;
  String _deviceSecret = '';
  final Map<String, String> _knownFingerprints = {}; // endpointId -> fingerprint
  final Map<String, String> _knownPeerNames = {}; // peerName -> fingerprint

  static const int pinIntervalSeconds = 30;

  /// Clave secreta única de este dispositivo/instalación
  String get deviceSecret {
    if (_deviceSecret.isEmpty) {
      final rand = Random.secure();
      final bytes = List<int>.generate(20, (_) => rand.nextInt(256));
      _deviceSecret = bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
    }
    return _deviceSecret;
  }

  void setDeviceSecret(String secret) {
    if (secret.isNotEmpty && _deviceSecret != secret) {
      _deviceSecret = secret;
      _cachedUniqueId = null;
      _cachedFingerprint = null;
    }
  }

  /// Inicializa o recupera la identidad única del dispositivo
  Future<String> getUniqueId(String deviceName) async {
    if (_cachedUniqueId != null) return _cachedUniqueId!;
    
    final sha256 = Sha256();
    // Derivar de la clave secreta única del dispositivo y el nombre
    final seed = 'bluemesh-id-$deviceSecret-$deviceName';
    final hash = await sha256.hash(utf8.encode(seed));
    final hex = hash.bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
    
    // Formato amigable corto: BM-A1B2
    _cachedUniqueId = 'BM-${hex.substring(0, 4).toUpperCase()}';
    // Formato completo: BM-A1B2-C3D4-E5F6
    _cachedFingerprint = 'BM-${hex.substring(0, 4)}-${hex.substring(4, 8)}-${hex.substring(8, 12)}'.toUpperCase();
    
    return _cachedUniqueId!;
  }

  String get fingerprint => _cachedFingerprint ?? 'BM-DEV-0001';

  int getCurrentStep([DateTime? time]) {
    final now = time ?? DateTime.now();
    return now.millisecondsSinceEpoch ~/ (pinIntervalSeconds * 1000);
  }

  int getSecondsRemaining([DateTime? time]) {
    final now = time ?? DateTime.now();
    final seconds = (now.millisecondsSinceEpoch ~/ 1000) % pinIntervalSeconds;
    return pinIntervalSeconds - seconds;
  }

  double getProgress([DateTime? time]) {
    return getSecondsRemaining(time) / pinIntervalSeconds;
  }

  String _computePinForStep(int step) {
    int hash = 0x811c9dc5;
    final input = '$deviceSecret:$step';
    for (int i = 0; i < input.length; i++) {
      hash ^= input.codeUnitAt(i);
      hash = (hash * 0x01000193) & 0xFFFFFFFF;
    }
    hash = (hash ^ (step & 0xFFFFFFFF)) & 0xFFFFFFFF;
    hash = ((hash ^ (hash >> 16)) * 0x45d9f3b) & 0xFFFFFFFF;
    hash = ((hash ^ (hash >> 16)) * 0x45d9f3b) & 0xFFFFFFFF;
    hash = (hash ^ (hash >> 16)) & 0x7FFFFFFF;
    return (hash % 900000 + 100000).toString();
  }

  /// Retorna el código PIN de 6 dígitos actual tipo 2FA (válido durante 30s)
  String getCurrentPin([DateTime? time]) {
    return _computePinForStep(getCurrentStep(time));
  }

  /// Genera o devuelve el PIN de conexión (compatibilidad hacia atrás)
  String getPersonalPin([String? deviceName]) => getCurrentPin();

  /// Valida si el código ingresado coincide con el intervalo actual o el anterior/siguiente (tolerancia de 2FA)
  bool isValidPin(String enteredPin) {
    final clean = enteredPin.replaceAll(' ', '').trim();
    if (clean.length != 6) return false;
    final currentStep = getCurrentStep();
    for (int offset = -1; offset <= 1; offset++) {
      if (_computePinForStep(currentStep + offset) == clean) {
        return true;
      }
    }
    return false;
  }

  /// Registra o valida un par para detectar intentos de suplantación (TOFU)
  /// Retorna true si la identidad es legítima, o false si se detectó suplantación.
  bool verifyOrRegisterPeer({
    required String endpointId,
    required String peerName,
    required String fingerprint,
  }) {
    // Si ya conocíamos este nombre con otro fingerprint diferente
    final knownFpForName = _knownPeerNames[peerName];
    if (knownFpForName != null && knownFpForName != fingerprint) {
      // Posible suplantación: alguien está usando el mismo nombre con otra clave
      return false;
    }

    _knownFingerprints[endpointId] = fingerprint;
    _knownPeerNames[peerName] = fingerprint;
    return true;
  }

  String? getKnownFingerprint(String endpointId) => _knownFingerprints[endpointId];

  void reset() {
    _knownFingerprints.clear();
    _knownPeerNames.clear();
    _cachedUniqueId = null;
    _cachedFingerprint = null;
  }
}
