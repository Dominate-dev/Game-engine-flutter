import 'dart:convert';

import 'package:coreapp/coreapp.dart';
import 'package:flutter_test/flutter_test.dart';

// T-COV — SecurityGenerator produces the RSA request token and had no tests.
//
// What can honestly be asserted here is structural, not semantic:
//   - the repository ships only the PUBLIC key, so there is no round trip and
//     no way to prove the ciphertext decrypts to `data;millis`;
//   - the timestamp comes from DateTime.now() with no injection point, so the
//     plaintext differs on every call and cannot be pinned;
//   - PKCS#1 v1.5 padding is randomised, so ciphertext is never repeatable.
//
// Every constant below (172, 128, the oversize throw) was measured against
// this implementation, not derived from the RSA spec on paper.

/// 1024-bit key → a 128-byte cipher block → 172 base64 characters.
const _blockBytes = 128;
const _base64Length = 172;

void main() {
  void expectValidToken(String token) {
    expect(token, isNotEmpty);
    expect(token.length, _base64Length);
    expect(base64.decode(token).length, _blockBytes);
    // Base64.NO_WRAP equivalent — the implementation comment calls this out.
    expect(token, isNot(contains('\n')));
    expect(token, isNot(contains('\r')));
    expect(token.trim(), token);
  }

  group('encryptDataRSA', () {
    test('produces a decodable, fixed-size base64 block', () {
      expectValidToken(SecurityGenerator.encryptDataRSA('47'));
    });

    test('encrypts an empty payload rather than short-circuiting', () {
      // The plaintext is still ';<millis>', so there is always something.
      expectValidToken(SecurityGenerator.encryptDataRSA(''));
    });

    test('handles non-ASCII payloads through utf8', () {
      expectValidToken(SecurityGenerator.encryptDataRSA('مرحبا'));
      expectValidToken(SecurityGenerator.encryptDataRSA('héllo — ok'));
    });

    test('handles a payload at the top of the usable range', () {
      expectValidToken(SecurityGenerator.encryptDataRSA('x' * 103));
    });

    test('never repeats a token for the same input', () {
      final first = SecurityGenerator.encryptDataRSA('47');
      final second = SecurityGenerator.encryptDataRSA('47');
      final third = SecurityGenerator.encryptDataRSA('47');

      // PKCS#1 v1.5 pads with random bytes; a repeated token would mean the
      // padding stopped being randomised.
      expect(first, isNot(second));
      expect(second, isNot(third));
      expect(first, isNot(third));
    });

    test('rejects a payload larger than one RSA block', () {
      expect(
        () => SecurityGenerator.encryptDataRSA('x' * 200),
        throwsArgumentError,
      );
    });
  });

  group('encryptDataRSAs', () {
    test('produces a decodable, fixed-size base64 block', () {
      expectValidToken(SecurityGenerator.encryptDataRSAs('47'));
    });

    test('encrypts an empty payload', () {
      expectValidToken(SecurityGenerator.encryptDataRSAs(''));
    });

    test('handles non-ASCII payloads', () {
      expectValidToken(SecurityGenerator.encryptDataRSAs('مرحبا'));
    });

    test('never repeats a token for the same input', () {
      final first = SecurityGenerator.encryptDataRSAs('47');
      final second = SecurityGenerator.encryptDataRSAs('47');
      expect(first, isNot(second));
    });

    test('rejects a payload larger than one RSA block', () {
      expect(
        () => SecurityGenerator.encryptDataRSAs('x' * 200),
        throwsArgumentError,
      );
    });
  });

  group('the two entry points agree structurally', () {
    test('both yield the same token shape for the same input', () {
      final a = SecurityGenerator.encryptDataRSA('47');
      final b = SecurityGenerator.encryptDataRSAs('47');

      expect(a.length, b.length);
      expect(base64.decode(a).length, base64.decode(b).length);
    });

    test('both accept the same range of inputs', () {
      for (final input in <String>['', '47', 'a b c', 'مرحبا', 'x' * 103]) {
        expectValidToken(SecurityGenerator.encryptDataRSA(input));
        expectValidToken(SecurityGenerator.encryptDataRSAs(input));
      }
    });
  });
}
