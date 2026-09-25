import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:milkful_app/core/utils/jwt_claims.dart';
import 'package:milkful_app/features/checkout/data/pending_checkout_store.dart';

String _part(Object json) => base64Url.encode(utf8.encode(jsonEncode(json))).replaceAll('=', '');

void main() {
  group('subFromJwt', () {
    test('reads the sub claim from an unpadded base64url payload', () {
      final token = '${_part({'alg': 'RS256'})}.${_part({'sub': 'abc-123', 'x': 'y?'})}.sig';
      expect(subFromJwt(token), 'abc-123');
    });

    test('is null for a missing, malformed or sub-less token', () {
      expect(subFromJwt(null), isNull);
      expect(subFromJwt('not-a-jwt'), isNull);
      expect(subFromJwt('a.%%%.c'), isNull);
      expect(subFromJwt('${_part({'alg': 'none'})}.${_part({'aud': 'x'})}.sig'), isNull);
      expect(subFromJwt('${_part({'alg': 'none'})}.${_part({'sub': ''})}.sig'), isNull);
    });
  });

  group('PendingCheckout', () {
    const pending = PendingCheckout(key: 'k1', cartVersion: 7, expectedPayNowPaise: 10820);

    test('round-trips through JSON', () {
      expect(PendingCheckout.tryParse(jsonEncode(pending.toJson())), pending);
    });

    test('a bare key or incomplete record is treated as absent', () {
      expect(PendingCheckout.tryParse('k1'), isNull);
      expect(PendingCheckout.tryParse(jsonEncode({'key': 'k1', 'cartVersion': 7})), isNull);
    });
  });
}
