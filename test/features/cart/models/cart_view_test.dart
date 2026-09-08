import 'package:flutter_test/flutter_test.dart';
import 'package:milkful_app/features/cart/models/cart_view.dart';

void main() {
  group('CartView', () {
    test('fromJson parses a non-empty cart with a quote', () {
      final json = {
        'items': [
          {
            'id': 'li-1',
            'productId': 'cow-milk',
            'quantity': 2,
            'frequency': 'ONE_TIME',
            'startDate': null,
            'addedAt': '2026-08-31T10:00:00.000Z',
          },
        ],
        'cartVersion': 3,
        'quote': {
          'basePrice': 68.0,
          'taxAmount': 3.4,
          'taxRate': 5.0,
          'deliveryFee': 20.0,
          'netPayable': 91.4,
          'monthlyEstimate': null,
          'discountAmount': null,
          'appliedOfferId': null,
        },
      };

      final view = CartView.fromJson(json);

      expect(view.items, hasLength(1));
      expect(view.cartVersion, 3);
      expect(view.quote, isNotNull);
      expect(view.quote!.netPayable, 91.4);
    });

    test('fromJson parses an empty cart (items: [], quote: null)', () {
      final view = CartView.fromJson({'items': [], 'cartVersion': 0, 'quote': null});

      expect(view.items, isEmpty);
      expect(view.cartVersion, 0);
      expect(view.quote, isNull);
    });

    test('fromJson treats a missing quote key the same as null (PUT /cart response)', () {
      final view = CartView.fromJson({
        'items': [
          {
            'id': 'li-1',
            'productId': 'cow-milk',
            'quantity': 1,
            'frequency': 'ONE_TIME',
            'startDate': null,
            'addedAt': '2026-08-31T10:00:00.000Z',
          },
        ],
        'cartVersion': 1,
      });

      expect(view.quote, isNull);
    });
  });
}
