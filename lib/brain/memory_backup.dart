import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';

/// Passphrase-encrypted memory backup with an integrity check.
///
/// Key derivation: PBKDF2-HMAC-SHA256 (configurable iterations, 64-byte output
/// split into an encryption key and a MAC key). Encryption: HMAC-SHA256 in
/// counter mode as a keystream (XOR). Integrity: HMAC-SHA256 over
/// version|salt|iterations|ciphertext (encrypt-then-MAC). Wrong passphrase or
/// any modified byte → [BackupException] before anything is imported.
class BackupException implements Exception {
  final String message;
  const BackupException(this.message);
  @override
  String toString() => message;
}

Uint8List _pbkdf2(List<int> pass, List<int> salt, int iterations, int length) {
  final mac = Hmac(sha256, pass);
  final out = BytesBuilder();
  for (var block = 1; out.length < length; block++) {
    var u = mac.convert([...salt, (block >> 24) & 255, (block >> 16) & 255, (block >> 8) & 255, block & 255]).bytes;
    final t = List<int>.from(u);
    for (var i = 1; i < iterations; i++) {
      u = mac.convert(u).bytes;
      for (var j = 0; j < t.length; j++) {
        t[j] ^= u[j];
      }
    }
    out.add(t);
  }
  return Uint8List.fromList(out.toBytes().sublist(0, length));
}

Uint8List _keystreamXor(List<int> key, List<int> nonce, List<int> data) {
  final mac = Hmac(sha256, key);
  final out = Uint8List(data.length);
  for (var off = 0, ctr = 0; off < data.length; ctr++) {
    final ks = mac.convert([...nonce, (ctr >> 24) & 255, (ctr >> 16) & 255, (ctr >> 8) & 255, ctr & 255]).bytes;
    for (var i = 0; i < ks.length && off < data.length; i++, off++) {
      out[off] = data[off] ^ ks[i];
    }
  }
  return out;
}

bool _constEq(List<int> a, List<int> b) {
  if (a.length != b.length) return false;
  var d = 0;
  for (var i = 0; i < a.length; i++) {
    d |= a[i] ^ b[i];
  }
  return d == 0;
}

String encryptBackup(String plaintext, String passphrase, {int iterations = 60000, Random? random}) {
  if (passphrase.length < 6) throw const BackupException('Use a passphrase of at least 6 characters.');
  final rnd = random ?? Random.secure();
  final salt = List<int>.generate(16, (_) => rnd.nextInt(256));
  final keys = _pbkdf2(utf8.encode(passphrase), salt, iterations, 64);
  final ct = _keystreamXor(keys.sublist(0, 32), salt, utf8.encode(plaintext));
  final tag = Hmac(sha256, keys.sublist(32)).convert([...utf8.encode('jarvis-mem-v1'), ...salt, ...utf8.encode('$iterations'), ...ct]).bytes;
  return jsonEncode({'format': 'jarvis-memory-backup', 'v': 1, 'iter': iterations,
    'salt': base64Encode(salt), 'data': base64Encode(ct), 'mac': base64Encode(tag)});
}

String decryptBackup(String backup, String passphrase) {
  Map<String, dynamic> j;
  try {
    j = jsonDecode(backup) as Map<String, dynamic>;
  } catch (_) {
    throw const BackupException('This is not a JARVIS memory backup.');
  }
  if (j['format'] != 'jarvis-memory-backup' || j['v'] != 1) throw const BackupException('Unsupported backup format.');
  final iterations = j['iter'] as int;
  final salt = base64Decode(j['salt'] as String);
  final ct = base64Decode(j['data'] as String);
  final keys = _pbkdf2(utf8.encode(passphrase), salt, iterations, 64);
  final tag = Hmac(sha256, keys.sublist(32)).convert([...utf8.encode('jarvis-mem-v1'), ...salt, ...utf8.encode('$iterations'), ...ct]).bytes;
  if (!_constEq(tag, base64Decode(j['mac'] as String))) {
    throw const BackupException('Wrong passphrase or the backup was modified. Nothing was imported.');
  }
  return utf8.decode(_keystreamXor(keys.sublist(0, 32), salt, ct));
}

/// Simple relevance score: shared word stems + small recency bonus.
double relevance(String query, String fact, DateTime createdAt, {DateTime? now}) {
  Set<String> words(String s) => s.toLowerCase().split(RegExp(r'[^\p{L}\p{N}]+', unicode: true))
      .where((w) => w.length > 2).map((w) => w.length > 5 ? w.substring(0, 5) : w).toSet();
  final q = words(query), f = words(fact);
  if (q.isEmpty || f.isEmpty) return 0;
  final overlap = q.intersection(f).length / q.length;
  final ageDays = (now ?? DateTime.now()).difference(createdAt).inHours / 24.0;
  return overlap + 0.05 / (1 + ageDays / 30);
}
