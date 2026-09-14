import 'dart:convert';

import 'package:cryptography/cryptography.dart';

class SecureSession {
  SecureSession._(this._keyPair, this.publicKeyBytes);

  static final X25519 _keyExchange = X25519();
  static final Hkdf _keyDerivation = Hkdf(
    hmac: Hmac.sha256(),
    outputLength: 32,
  );
  static final AesGcm _cipher = AesGcm.with256bits();
  static final List<int> _associatedData = utf8.encode(
    'bluemesh-e2ee-message-v1',
  );

  final KeyPair _keyPair;
  final List<int> publicKeyBytes;
  SecretKey? _sessionKey;
  bool _disposed = false;
  bool hasSentKey = false;

  bool get isReady => _sessionKey != null && !_disposed;

  static Future<SecureSession> create() async {
    final keyPair = await _keyExchange.newKeyPair();
    final publicKey = await keyPair.extractPublicKey();
    return SecureSession._(keyPair, List.unmodifiable(publicKey.bytes));
  }

  Future<void> establish(List<int> remotePublicKeyBytes) async {
    _ensureActive();
    if (remotePublicKeyBytes.length != 32) {
      throw const FormatException('La clave pública remota no es válida.');
    }

    final remotePublicKey = SimplePublicKey(
      remotePublicKeyBytes,
      type: KeyPairType.x25519,
    );
    final sharedSecret = await _keyExchange.sharedSecretKey(
      keyPair: _keyPair,
      remotePublicKey: remotePublicKey,
    );
    final orderedKeys =
        _lexicographicCompare(publicKeyBytes, remotePublicKeyBytes) <= 0
        ? [...publicKeyBytes, ...remotePublicKeyBytes]
        : [...remotePublicKeyBytes, ...publicKeyBytes];
    final salt = (await Sha256().hash(orderedKeys)).bytes;
    try {
      final nextSessionKey = await _keyDerivation.deriveKey(
        secretKey: sharedSecret,
        nonce: salt,
        info: utf8.encode('BlueMesh secure session v1'),
      );
      _sessionKey?.destroy();
      _sessionKey = nextSessionKey;
    } finally {
      sharedSecret.destroy();
    }
  }

  Future<List<int>> encrypt(List<int> clearText) async {
    final key = _requireSessionKey();
    final box = await _cipher.encrypt(
      clearText,
      secretKey: key,
      aad: _associatedData,
    );
    return utf8.encode(
      jsonEncode({
        'version': 1,
        'type': 'encrypted_message',
        'nonce': base64Encode(box.nonce),
        'ciphertext': base64Encode(box.cipherText),
        'mac': base64Encode(box.mac.bytes),
      }),
    );
  }

  Future<List<int>> decrypt(List<int> payload) async {
    final key = _requireSessionKey();
    final decoded = jsonDecode(utf8.decode(payload));
    if (decoded is! Map<String, dynamic> ||
        decoded['version'] != 1 ||
        decoded['type'] != 'encrypted_message') {
      throw const FormatException('El sobre cifrado no es compatible.');
    }

    final nonce = _decodeField(decoded, 'nonce');
    final cipherText = _decodeField(decoded, 'ciphertext');
    final mac = _decodeField(decoded, 'mac');
    final box = SecretBox(cipherText, nonce: nonce, mac: Mac(mac));
    return _cipher.decrypt(box, secretKey: key, aad: _associatedData);
  }

  Future<Map<String, String>> encryptRaw(List<int> clearText) async {
    final key = _requireSessionKey();
    final box = await _cipher.encrypt(
      clearText,
      secretKey: key,
      aad: _associatedData,
    );
    return {
      'nonce': base64Encode(box.nonce),
      'ciphertext': base64Encode(box.cipherText),
      'mac': base64Encode(box.mac.bytes),
    };
  }

  Future<List<int>> decryptRaw({
    required String nonceBase64,
    required String ciphertextBase64,
    required String macBase64,
  }) async {
    final key = _requireSessionKey();
    final nonce = base64Decode(nonceBase64);
    final cipherText = base64Decode(ciphertextBase64);
    final mac = base64Decode(macBase64);
    final box = SecretBox(cipherText, nonce: nonce, mac: Mac(mac));
    return _cipher.decrypt(box, secretKey: key, aad: _associatedData);
  }

  Future<String> deriveSixDigitPin(List<int> remotePublicKeyBytes) async {
    final key = _requireSessionKey();
    final orderedKeys = _lexicographicCompare(publicKeyBytes, remotePublicKeyBytes) <= 0
        ? [...publicKeyBytes, ...remotePublicKeyBytes]
        : [...remotePublicKeyBytes, ...publicKeyBytes];

    final keyBytes = await key.extractBytes();
    final combined = [...orderedKeys, ...keyBytes, ...utf8.encode('pin-verification-v2')];
    final digest = await Sha256().hash(combined);

    final intVal = ((digest.bytes[0] & 0x7F) << 24) |
        (digest.bytes[1] << 16) |
        (digest.bytes[2] << 8) |
        digest.bytes[3];

    final pin = (intVal % 900000) + 100000;
    return pin.toString().padLeft(6, '0');
  }

  static bool isKeyExchangePayload(Map<String, dynamic> payload) {
    return payload['version'] == 1 && payload['type'] == 'key_exchange';
  }

  static List<int> keyFromPayload(Map<String, dynamic> payload) {
    if (!isKeyExchangePayload(payload)) {
      throw const FormatException('Intercambio de claves no reconocido.');
    }
    return _decodeField(payload, 'publicKey');
  }

  List<int> createKeyExchangePayload() {
    _ensureActive();
    return utf8.encode(
      jsonEncode({
        'version': 1,
        'type': 'key_exchange',
        'algorithm': 'X25519+HKDF-SHA256+AES-256-GCM',
        'publicKey': base64Encode(publicKeyBytes),
      }),
    );
  }

  static List<int> _decodeField(Map<String, dynamic> payload, String field) {
    final value = payload[field];
    if (value is! String) {
      throw FormatException('Falta el campo cifrado $field.');
    }
    try {
      return base64Decode(value);
    } on FormatException {
      throw FormatException('El campo cifrado $field no es Base64 válido.');
    }
  }

  static int _lexicographicCompare(List<int> left, List<int> right) {
    for (var index = 0; index < left.length && index < right.length; index++) {
      final comparison = left[index].compareTo(right[index]);
      if (comparison != 0) return comparison;
    }
    return left.length.compareTo(right.length);
  }

  SecretKey _requireSessionKey() {
    _ensureActive();
    final key = _sessionKey;
    if (key == null) {
      throw StateError('El canal cifrado todavía no está listo.');
    }
    return key;
  }

  void _ensureActive() {
    if (_disposed) throw StateError('La sesión cifrada ya fue destruida.');
  }

  void dispose() {
    if (_disposed) return;
    _disposed = true;
    _sessionKey?.destroy();
    _sessionKey = null;
    _keyPair.destroy();
  }
}
