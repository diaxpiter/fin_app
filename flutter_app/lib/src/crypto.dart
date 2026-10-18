// End-to-end encryption for synced data. The server only ever sees:
//   - an auth secret derived from the password (never the password itself)
//   - the data key, wrapped (AES-256-GCM) by the password and by the recovery key
//   - the data, encrypted with the data key
// Nobody with database access can read a user's finances.
//
//   password ──PBKDF2(600k, salt=email)──► master ──HKDF "auth"──► Supabase password
//                                                └─HKDF "enc"───► key that wraps the data key
//   recovery key (160 random bits) ──HKDF "recovery"──► key that wraps the data key
//   data key (256 random bits) ──AES-256-GCM──► encrypted AppState JSON

import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:cryptography/cryptography.dart';

const kdfIterations = 600000; // OWASP 2023 minimum for PBKDF2-HMAC-SHA256

final _aes = AesGcm.with256bits();
final _hkdf = Hkdf(hmac: Hmac.sha256(), outputLength: 32);
final _rand = Random.secure();

List<int> randomBytes(int n) => List<int>.generate(n, (_) => _rand.nextInt(256));

class PasswordKeys {
  const PasswordKeys(this.authSecret, this.wrappingKey);

  /// Sent to Supabase as the account password. One-way: it reveals nothing
  /// about [wrappingKey].
  final String authSecret;
  final SecretKey wrappingKey;
}

String _salt(String email) => 'fin_app/v1/${email.trim().toLowerCase()}';

Future<PasswordKeys> derivePasswordKeys(String email, String password, {int iterations = kdfIterations}) async {
  final master = await Pbkdf2.hmacSha256(iterations: iterations, bits: 256)
      .deriveKeyFromPassword(password: password, nonce: utf8.encode(_salt(email)));
  final auth = await _hkdf.deriveKey(secretKey: master, info: utf8.encode('auth'));
  final enc = await _hkdf.deriveKey(secretKey: master, info: utf8.encode('enc'));
  return PasswordKeys(base64Url.encode(await auth.extractBytes()).replaceAll('=', ''), enc);
}

Future<SecretKey> recoveryWrappingKey(String recoveryKey) =>
    _hkdf.deriveKey(secretKey: SecretKey(parseRecoveryKey(recoveryKey)), info: utf8.encode('recovery'));

Future<SecretKey> newDataKey() => _aes.newSecretKey();

Future<String> seal(SecretKey key, List<int> clear) async {
  final box = await _aes.encrypt(clear, secretKey: key);
  return base64.encode(box.concatenation());
}

/// Throws [SecretBoxAuthenticationError] when the key is wrong or data was tampered with.
Future<List<int>> open(SecretKey key, String sealed) => _aes.decrypt(
      SecretBox.fromConcatenation(base64.decode(sealed), nonceLength: _aes.nonceLength, macLength: 16),
      secretKey: key,
    );

Future<String> wrapKey(SecretKey wrappingKey, SecretKey dataKey) async =>
    seal(wrappingKey, await dataKey.extractBytes());

Future<SecretKey> unwrapKey(SecretKey wrappingKey, String wrapped) async =>
    SecretKey(await open(wrappingKey, wrapped));

Future<String> encryptJson(SecretKey dataKey, Object? json) => seal(dataKey, utf8.encode(jsonEncode(json)));

Future<Object?> decryptJson(SecretKey dataKey, String sealed) async => jsonDecode(utf8.decode(await open(dataKey, sealed)));

// ---- Recovery key: 20 random bytes as base32, e.g. "ABCD-EFGH-…" (8 groups of 4) ----

const _b32 = 'ABCDEFGHIJKLMNOPQRSTUVWXYZ234567';

String newRecoveryKey() {
  final bytes = randomBytes(20);
  final buf = StringBuffer();
  var bits = 0, value = 0;
  for (final b in bytes) {
    value = ((value << 8) | b) & 0xFFFF;
    bits += 8;
    while (bits >= 5) {
      buf.write(_b32[(value >> (bits - 5)) & 31]);
      bits -= 5;
    }
  }
  final s = buf.toString(); // 32 chars
  return [for (var i = 0; i < s.length; i += 4) s.substring(i, i + 4)].join('-');
}

/// Accepts any case, spaces or dashes. Throws [FormatException] if malformed.
Uint8List parseRecoveryKey(String key) {
  final s = key.toUpperCase().replaceAll(RegExp(r'[^A-Z2-7]'), '');
  if (s.length != 32) throw const FormatException('Chave de recuperação inválida.');
  final out = <int>[];
  var bits = 0, value = 0;
  for (final ch in s.split('')) {
    value = ((value << 5) | _b32.indexOf(ch)) & 0xFFFF;
    bits += 5;
    if (bits >= 8) {
      out.add((value >> (bits - 8)) & 0xFF);
      bits -= 8;
    }
  }
  return Uint8List.fromList(out);
}
