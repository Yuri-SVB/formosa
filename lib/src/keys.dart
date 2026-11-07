import 'dart:convert';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';

/// PBKDF2 rounds of the seed, as BIP39 sets them.
const int kPbkdf2Rounds = 2048;

/// Bytes of a seed: one SHA-512 block.
const int kSeedBytes = 64;

/// Bytes of a private key, and of a chain code.
const int _kKeyBytes = 32;

/// PBKDF2-HMAC-SHA512 of [password] and [salt], [rounds] rounds, one block
/// ([kSeedBytes] bytes).
Uint8List pbkdf2HmacSha512(List<int> password, List<int> salt, int rounds) {
  final Hmac hmac = Hmac(sha512, password);
  const List<int> firstBlock = <int>[0, 0, 0, 1];
  List<int> u = hmac.convert(<int>[...salt, ...firstBlock]).bytes;
  final Uint8List out = Uint8List.fromList(u);
  for (int r = 1; r < rounds; r++) {
    u = hmac.convert(u).bytes;
    for (int i = 0; i < out.length; i++) {
      out[i] ^= u[i];
    }
  }
  return out;
}

const String _kBase58Alphabet =
    '123456789ABCDEFGHJKLMNPQRSTUVWXYZabcdefghijkmnopqrstuvwxyz';

/// Base58 of [bytes], as the reference implementation writes it (no leading
/// `1` for leading zero bytes: an extended key starts with none).
String base58Encode(List<int> bytes) {
  BigInt acc = BigInt.zero;
  for (final int b in bytes) {
    acc = (acc << 8) | BigInt.from(b);
  }
  final BigInt radix = BigInt.from(_kBase58Alphabet.length);
  final StringBuffer out = StringBuffer();
  while (acc > BigInt.zero) {
    out.write(_kBase58Alphabet[(acc % radix).toInt()]);
    acc ~/= radix;
  }
  return out.toString().split('').reversed.join();
}

/// BIP32's version bytes of a private extended key.
const List<int> _kMainnetPrivate = <int>[0x04, 0x88, 0xad, 0xe4];
const List<int> _kTestnetPrivate = <int>[0x04, 0x35, 0x83, 0x94];

/// Depth, parent fingerprint and child number of a master key: all zero.
const int _kMasterHeaderZeros = 9;

/// Bytes of the checksum appended to an extended key.
const int _kChecksumBytes = 4;

/// The BIP32 master private key of [seed], serialised (`xprv…`, or `tprv…` on
/// [testnet]).
String hdMasterKey(List<int> seed, {bool testnet = false}) {
  if (seed.length != kSeedBytes) {
    throw ArgumentError('Provided seed should have length of $kSeedBytes');
  }
  final List<int> i =
      Hmac(sha512, utf8.encode('Bitcoin seed')).convert(seed).bytes;
  final List<int> xprv = <int>[
    ...(testnet ? _kTestnetPrivate : _kMainnetPrivate),
    ...List<int>.filled(_kMasterHeaderZeros, 0),
    ...i.sublist(_kKeyBytes), // chain code
    0, ...i.sublist(0, _kKeyBytes), // master key
  ];
  final List<int> check = sha256.convert(sha256.convert(xprv).bytes).bytes;
  return base58Encode(<int>[...xprv, ...check.sublist(0, _kChecksumBytes)]);
}
