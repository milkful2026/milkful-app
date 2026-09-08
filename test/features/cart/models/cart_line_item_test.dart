import 'package:flutter_test/flutter_test.dart';
import 'package:milkful_app/features/cart/models/cart_line_item.dart';
import 'package:milkful_app/features/cart/models/frequency.dart';

void main() {
  group('CartLineItem', () {
    test('fromJson/toJson round-trips a one-time item (no startDate)', () {
      final json = {
        'id': 'li-1',
        'productId': 'cow-milk',
        'quantity': 2,
        'frequency': 'ONE_TIME',
        'startDate': null,
        'addedAt': '2026-08-31T10:00:00.000Z',
      };

      final item = CartLineItem.fromJson(json);

      expect(item.id, 'li-1');
      expect(item.productId, 'cow-milk');
      expect(item.quantity, 2);
      expect(item.frequency, Frequency.oneTime);
      expect(item.startDate, isNull);
      expect(item.toJson(), {
        'id': 'li-1',
        'productId': 'cow-milk',
        'quantity': 2,
        'frequency': 'ONE_TIME',
      });
    });

    test('fromJson/toJson round-trips a subscription item with a startDate', () {
      final json = {
        'id': 'li-2',
        'productId': 'buffalo-milk',
        'quantity': 1,
        'frequency': 'DAILY',
        'startDate': '2026-09-01',
        'addedAt': '2026-08-31T10:00:00.000Z',
      };

      final item = CartLineItem.fromJson(json);

      expect(item.frequency, Frequency.daily);
      expect(item.startDate, '2026-09-01');
      expect(item.toJson()['startDate'], '2026-09-01');
    });

    test('copyWith replaces only the quantity', () {
      final item = CartLineItem.fromJson({
        'id': 'li-1',
        'productId': 'cow-milk',
        'quantity': 1,
        'frequency': 'ONE_TIME',
        'startDate': null,
        'addedAt': '2026-08-31T10:00:00.000Z',
      });

      final updated = item.copyWith(quantity: 3);

      expect(updated.quantity, 3);
      expect(updated.id, item.id);
      expect(updated.productId, item.productId);
    });
  });
}
