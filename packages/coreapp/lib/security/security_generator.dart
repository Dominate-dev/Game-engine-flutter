import 'dart:convert';
import 'dart:typed_data';

import 'package:asn1lib/asn1lib.dart';
import 'package:pointycastle/export.dart';

// Port of native [SecurityGenerator] — RSA/ECB/PKCS1Padding request token.
abstract final class SecurityGenerator {
  static const _publicKeyString = '''
MIGfMA0GCSqGSIb3DQEBAQUAA4GNADCBiQKBgQDf+nhCSmP9PkPQbuATvuFBwNaH
PdgHrTwjuRX/NsHXQqC3FYH6OkndnwhANFunHyRXn+QcFYd/aTIOHReQsDfEycIq
EYuD4Ns49QtHz2VRRN7Vuw15JvlZa4JJ21gzclIz5cohlBmleVA1g8tkQkfLRIFA
iKkfJWezorDPvGzIOwIDAQAB''';

  // Matches native [encryptDataRSA] — encrypts `$data;$utcTimeMilliseconds`.
  static String encryptDataRSA(String data) {
    final utcTimeMilliseconds = _currentUtcTimeMilliseconds();
    return _encrypt('$data;$utcTimeMilliseconds');
  }

  // Matches native [encryptDataRSAs] — uses [DateTime.now] UTC millis.
  static String encryptDataRSAs(String data) {
    final utcTimeMilliseconds = DateTime.now().toUtc().millisecondsSinceEpoch;
    return _encrypt('$data;$utcTimeMilliseconds');
  }

  static int _currentUtcTimeMilliseconds() =>
      DateTime.now().toUtc().millisecondsSinceEpoch;

  static String _encrypt(String plainText) {
    final publicKey = _parsePublicKey(_publicKeyString);
    final cipher = PKCS1Encoding(RSAEngine())
      ..init(true, PublicKeyParameter<RSAPublicKey>(publicKey));

    final input = Uint8List.fromList(utf8.encode(plainText));
    final encrypted = cipher.process(input);

    // Base64.NO_WRAP equivalent — dart encode has no line breaks by default.
    return base64.encode(encrypted);
  }

  static RSAPublicKey _parsePublicKey(String base64Key) {
    final normalized = base64Key
        .replaceAll('-----BEGIN PUBLIC KEY-----', '')
        .replaceAll('-----END PUBLIC KEY-----', '')
        .replaceAll('\n', '')
        .trim();

    final keyBytes = base64.decode(normalized);
    final topLevelSeq = ASN1Parser(keyBytes).nextObject() as ASN1Sequence;
    final publicKeyBitString = topLevelSeq.elements[1] as ASN1BitString;

    final publicKeySeq = ASN1Parser(
      Uint8List.fromList(publicKeyBitString.stringValue),
    ).nextObject() as ASN1Sequence;

    final modulus =
        (publicKeySeq.elements[0] as ASN1Integer).valueAsBigInteger;
    final exponent =
        (publicKeySeq.elements[1] as ASN1Integer).valueAsBigInteger;

    return RSAPublicKey(modulus, exponent);
  }
}
