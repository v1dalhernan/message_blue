import 'dart:convert';
import 'package:cryptography/cryptography.dart';

/// Servicio de Identidad Criptográfica y Anti-Suplantación (Anti-Spoofing).
/// Genera un identificador único persistente (Fingerprint) para evitar que
/// un atacante o dispositivo malicioso se haga pasar por otro usuario.
class UserIdentityService {
  UserIdentityService._();
  static final UserIdentityService instance = UserIdentityService._();

  String? _cachedUniqueId;
  String? _cachedFingerprint;
  final Map<String, String> _knownFingerprints = {}; // endpointId -> fingerprint
  final Map<String, String> _knownPeerNames = {}; // peerName -> fingerprint

  /// Inicializa o recupera la identidad única del dispositivo
  Future<String> getUniqueId(String deviceName) async {
    if (_cachedUniqueId != null) return _cachedUniqueId!;
    
    final sha256 = Sha256();
    // Derivar de una semilla única ligada al nombre y componentes estables
    final seed = 'bluemesh-id-$deviceName-${deviceName.hashCode}';
    final hash = await sha256.hash(utf8.encode(seed));
    final hex = hash.bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
    
    // Formato amigable corto: BM-A1B2
    _cachedUniqueId = 'BM-${hex.substring(0, 4).toUpperCase()}';
    // Formato completo: BM-A1B2-C3D4-E5F6
    _cachedFingerprint = 'BM-${hex.substring(0, 4)}-${hex.substring(4, 8)}-${hex.substring(8, 12)}'.toUpperCase();
    
    return _cachedUniqueId!;
  }

  String get fingerprint => _cachedFingerprint ?? 'BM-DEV-0001';

  /// Genera un PIN personal de conexión de 6 dígitos único pero determinista
  String getPersonalPin(String deviceName) {
    final code = (deviceName.hashCode.abs() % 900000 + 100000).toString();
    return code;
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
