import 'dart:convert';

import 'package:cryptography/cryptography.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:message_blue/src/nearby/secure_session.dart';

void main() {
  test('two peers derive a shared key and exchange encrypted bytes', () async {
    final alice = await SecureSession.create();
    final bob = await SecureSession.create();
    addTearDown(alice.dispose);
    addTearDown(bob.dispose);

    await Future.wait([
      alice.establish(bob.publicKeyBytes),
      bob.establish(alice.publicKeyBytes),
    ]);

    final clearText = utf8.encode('mensaje confidencial');
    final encrypted = await alice.encrypt(clearText);
    final wireText = utf8.decode(encrypted);

    expect(wireText, isNot(contains('mensaje confidencial')));
    expect(await bob.decrypt(encrypted), clearText);
  });

  test('AES-GCM rejects a modified ciphertext', () async {
    final alice = await SecureSession.create();
    final bob = await SecureSession.create();
    addTearDown(alice.dispose);
    addTearDown(bob.dispose);

    await Future.wait([
      alice.establish(bob.publicKeyBytes),
      bob.establish(alice.publicKeyBytes),
    ]);

    final encrypted = await alice.encrypt(utf8.encode('mensaje auténtico'));
    final envelope = jsonDecode(utf8.decode(encrypted)) as Map<String, dynamic>;
    final cipherText = base64Decode(envelope['ciphertext'] as String);
    cipherText[0] ^= 1;
    envelope['ciphertext'] = base64Encode(cipherText);

    expect(
      () => bob.decrypt(utf8.encode(jsonEncode(envelope))),
      throwsA(isA<SecretBoxAuthenticationError>()),
    );
  });

  test('key exchange payload contains only the ephemeral public key', () async {
    final session = await SecureSession.create();
    addTearDown(session.dispose);

    final payload = jsonDecode(
      utf8.decode(session.createKeyExchangePayload()),
    ) as Map<String, dynamic>;

    expect(payload['type'], 'key_exchange');
    expect(payload['algorithm'], 'X25519+HKDF-SHA256+AES-256-GCM');
    expect(SecureSession.keyFromPayload(payload), session.publicKeyBytes);
    expect(payload, isNot(contains('privateKey')));
  });
}
