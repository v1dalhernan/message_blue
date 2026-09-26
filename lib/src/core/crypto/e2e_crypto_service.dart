import 'dart:convert';
import 'dart:math';
import 'package:cryptography/cryptography.dart';

class E2eCryptoService {
  static final X25519 _keyExchange = X25519();
  static final Hkdf _keyDerivation = Hkdf(
    hmac: Hmac.sha256(),
    outputLength: 32,
  );
  static final AesGcm _cipher = AesGcm.with256bits();
  static final Sha256 _hasher = Sha256();

  static final List<int> defaultAad = utf8.encode('bluemesh-e2ee-v2');

  /// Creates a new ephemeral or static X25519 key pair
  static Future<KeyPair> generateKeyPair() async {
    return _keyExchange.newKeyPair();
  }

  /// Extracts the 32-byte public key
  static Future<List<int>> extractPublicKey(KeyPair keyPair) async {
    final pub = await keyPair.extractPublicKey();
    return List<int>.unmodifiable((pub as SimplePublicKey).bytes);
  }

  /// Computes the ECDH shared secret and derives the AES-256 session key
  static Future<SecretKey> deriveSessionKey({
    required KeyPair localKeyPair,
    required List<int> localPublicKeyBytes,
    required List<int> remotePublicKeyBytes,
    String saltPrefix = 'BlueMesh secure session v2',
  }) async {
    if (remotePublicKeyBytes.length != 32) {
      throw const FormatException('Clave pública remota inválida (debe ser 32 bytes).');
    }

    final remotePublicKey = SimplePublicKey(
      remotePublicKeyBytes,
      type: KeyPairType.x25519,
    );

    final sharedSecret = await _keyExchange.sharedSecretKey(
      keyPair: localKeyPair,
      remotePublicKey: remotePublicKey,
    );

    final orderedKeys = _lexicographicCompare(localPublicKeyBytes, remotePublicKeyBytes) <= 0
        ? [...localPublicKeyBytes, ...remotePublicKeyBytes]
        : [...remotePublicKeyBytes, ...localPublicKeyBytes];

    final salt = (await _hasher.hash(orderedKeys)).bytes;

    try {
      return await _keyDerivation.deriveKey(
        secretKey: sharedSecret,
        nonce: salt,
        info: utf8.encode(saltPrefix),
      );
    } finally {
      sharedSecret.destroy();
    }
  }

  /// Derives an identical 6-digit PIN code on both sides for out-of-band verification
  static Future<String> deriveSixDigitPin({
    required List<int> localPublicKeyBytes,
    required List<int> remotePublicKeyBytes,
    required SecretKey sessionKey,
  }) async {
    final orderedKeys = _lexicographicCompare(localPublicKeyBytes, remotePublicKeyBytes) <= 0
        ? [...localPublicKeyBytes, ...remotePublicKeyBytes]
        : [...remotePublicKeyBytes, ...localPublicKeyBytes];

    final keyBytes = await sessionKey.extractBytes();
    final combined = [...orderedKeys, ...keyBytes, ...utf8.encode('pin-verification-v2')];
    final digest = await _hasher.hash(combined);

    // Take 4 bytes to form a stable positive integer
    final intVal = ((digest.bytes[0] & 0x7F) << 24) |
        (digest.bytes[1] << 16) |
        (digest.bytes[2] << 8) |
        digest.bytes[3];

    // Map to 6-digit range (100000..999999)
    final pin = (intVal % 900000) + 100000;
    return pin.toString().padLeft(6, '0');
  }

  /// Calculates a human-readable fingerprint (e.g. 12 hex chars) of a public key
  static Future<String> calculateFingerprint(List<int> publicKeyBytes) async {
    final digest = await _hasher.hash(publicKeyBytes);
    return digest.bytes.take(6).map((b) => b.toRadixString(16).padLeft(2, '0')).join('').toUpperCase();
  }

  /// Generates the payload to be rendered inside the QR code
  static String generateQrPayload({
    required String peerId,
    required String peerName,
    required String pin,
    required String fingerprint,
  }) {
    return jsonEncode({
      'proto': 'bluemesh-qr-v1',
      'id': peerId,
      'name': peerName,
      'pin': pin,
      'fp': fingerprint,
      'ts': DateTime.now().millisecondsSinceEpoch,
    });
  }

  /// Parses and validates a QR code payload scanned from camera
  static Map<String, dynamic>? parseQrPayload(String raw) {
    try {
      final decoded = jsonDecode(raw);
      if (decoded is Map<String, dynamic> && decoded['proto'] == 'bluemesh-qr-v1') {
        return decoded;
      }
    } catch (_) {}
    return null;
  }

  /// Generates a random 256-bit symmetric key for a group chat
  static String generateRandomGroupSecretKey() {
    final random = Random.secure();
    final bytes = List<int>.generate(32, (_) => random.nextInt(256));
    return base64Encode(bytes);
  }

  /// Imports a group key from base64
  static SecretKey importGroupSecretKey(String base64Key) {
    return SecretKey(base64Decode(base64Key));
  }

  /// Generates a new 256-bit SecretKey for a group
  static Future<SecretKey> generateGroupKey() => _cipher.newSecretKey();

  /// Decrypts group payload
  static Future<List<int>> decryptGroupPayload({
    required SecretKey groupKey,
    required String nonceBase64,
    required String ciphertextBase64,
    required String macBase64,
  }) =>
      decryptAesGcm(
        nonceBase64: nonceBase64,
        ciphertextBase64: ciphertextBase64,
        macBase64: macBase64,
        key: groupKey,
      );

  /// Encrypts bytes using AES-256-GCM
  static Future<Map<String, String>> encryptAesGcm({
    required List<int> plaintext,
    required SecretKey key,
    List<int>? aad,
  }) async {
    final box = await _cipher.encrypt(
      plaintext,
      secretKey: key,
      aad: aad ?? defaultAad,
    );
    return {
      'nonce': base64Encode(box.nonce),
      'ciphertext': base64Encode(box.cipherText),
      'mac': base64Encode(box.mac.bytes),
    };
  }

  /// Decrypts bytes using AES-256-GCM
  static Future<List<int>> decryptAesGcm({
    required String nonceBase64,
    required String ciphertextBase64,
    required String macBase64,
    required SecretKey key,
    List<int>? aad,
  }) async {
    final nonce = base64Decode(nonceBase64);
    final ciphertext = base64Decode(ciphertextBase64);
    final mac = base64Decode(macBase64);

    final box = SecretBox(ciphertext, nonce: nonce, mac: Mac(mac));
    return _cipher.decrypt(box, secretKey: key, aad: aad ?? defaultAad);
  }

  static int _lexicographicCompare(List<int> left, List<int> right) {
    for (var index = 0; index < left.length && index < right.length; index++) {
      final comparison = left[index].compareTo(right[index]);
      if (comparison != 0) return comparison;
    }
    return left.length.compareTo(right.length);
  }
}
