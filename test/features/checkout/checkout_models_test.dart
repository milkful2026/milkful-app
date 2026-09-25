import 'package:flutter_test/flutter_test.dart';
import 'package:milkful_app/core/network/api_client.dart';
import 'package:milkful_app/features/auth/models/user_profile.dart';
import 'package:milkful_app/features/cart/models/cart_line_item.dart';
import 'package:milkful_app/features/cart/models/cart_view.dart';
import 'package:milkful_app/features/cart/models/frequency.dart';
import 'package:milkful_app/features/checkout/models/checkout_failure.dart';
import 'package:milkful_app/features/checkout/models/checkout_result.dart';

/// MA-137 wire-shape parsing: the new fields MA-135/MA-136 added.
void main() {
  const quoteJson = {
    'basePrice': 84.0,
    'taxAmount': 4.2,
    'taxRate': 5.0,
    'deliveryFee': 20.0,
    'netPayable': 108.2,
  };

  test('CartLineItem carries slotId both ways', () {
    final line = CartLineItem.fromJson(const {
      'id': 'li-2',
      'productId': 'cow-milk',
      'quantity': 1,
      'frequency': 'DAILY',
      'startDate': '2026-09-27',
      'slotId': 'slot-am',
      'addedAt': '2026-09-25T00:00:00Z',
    });

    expect(line.slotId, 'slot-am');
    expect(line.frequency, Frequency.daily);
    expect(line.toJson()['slotId'], 'slot-am');
    expect(line.copyWith(quantity: 3).slotId, 'slot-am');
  });

  test('a one-time CartLineItem omits slotId from PUT /cart', () {
    const line = CartLineItem(
      id: 'li-1',
      productId: 'cow-milk',
      quantity: 1,
      frequency: Frequency.oneTime,
      addedAt: '2026-09-25T00:00:00Z',
    );

    expect(line.toJson().containsKey('slotId'), isFalse);
  });

  test('CartView parses the split quotes, null when absent', () {
    final view = CartView.fromJson(const {
      'items': [],
      'cartVersion': 2,
      'quote': quoteJson,
      'payNowQuote': quoteJson,
      'perDeliveryQuote': null,
    });

    expect(view.payNowQuote!.netPayable, 108.2);
    expect(view.perDeliveryQuote, isNull);
    expect(CartView.fromJson(const {'items': [], 'cartVersion': 0}).payNowQuote, isNull);
  });

  test('UserProfile parses the full defaultAddress', () {
    final profile = UserProfile.fromJson(const {
      'userId': 'user-1',
      'name': 'Priya Sharma',
      'mobile': '+919876543210',
      'accountType': 'B2C',
      'defaultAddressId': 'addr-1',
      'defaultAddress': {
        'id': 'addr-1',
        'lines': ['Flat 402, Sai Heights', 'Baner Road'],
        'landmark': null,
        'city': 'Pune',
        'state': 'Maharashtra',
        'pincode': '411045',
        'lat': 18.559,
        'lng': 73,
      },
    });

    final address = profile.defaultAddress!;
    expect(address.street, 'Flat 402, Sai Heights, Baner Road');
    expect(address.cityStatePincode, 'Pune, Maharashtra 411045');
    expect(address.landmark, isNull);
    expect(address.lng, 73.0);
  });

  test('UserProfile from an older User Service has no defaultAddress', () {
    final profile = UserProfile.fromJson(const {
      'userId': 'user-1',
      'name': 'Priya Sharma',
      'mobile': '+919876543210',
      'accountType': 'B2C',
      'defaultAddressId': 'addr-1',
    });

    expect(profile.defaultAddress, isNull);
  });

  test('CheckoutResult parses order, created and failed subscriptions', () {
    final result = CheckoutResult.fromJson(const {
      'checkoutId': 'chk_1',
      'status': 'COMPLETED',
      'order': {
        'orderId': 'ord_1',
        'status': 'CONFIRMED',
        'amountPaise': 10820,
        'deliveryDate': '2026-09-26',
        'items': [],
      },
      'subscriptions': [
        {
          'lineId': 'li-2',
          'productId': 'cow-milk',
          'status': 'CREATED',
          'subscriptionId': 'sub_1',
          'nextDeliveryDate': '2026-09-27',
        },
        {
          'lineId': 'li-3',
          'productId': 'paneer',
          'status': 'FAILED',
          'reason': 'PRODUCT_NOT_ELIGIBLE',
        },
      ],
      'walletBalanceAfterPaise': 39180,
    });

    expect(result.order!.amountPaise, 10820);
    expect(result.createdSubscriptions.single.subscriptionId, 'sub_1');
    expect(result.failedSubscriptions.single.reason, 'PRODUCT_NOT_ELIGIBLE');
  });

  test('a subscription-only CheckoutResult has no order', () {
    final result = CheckoutResult.fromJson(const {
      'checkoutId': 'chk_1',
      'order': null,
      'subscriptions': [],
      'walletBalanceAfterPaise': null,
    });

    expect(result.order, isNull);
  });

  group('CheckoutFailure.fromApiException', () {
    CheckoutFailure map(String code, {int? status, Map<String, dynamic> details = const {}}) =>
        CheckoutFailure.fromApiException(
          ApiException(errorCode: code, message: 'm', statusCode: status, details: details),
        );

    test('terminal outcomes clear the key', () {
      expect(
        map('INSUFFICIENT_BALANCE', status: 402, details: {'shortfallPaise': 100}),
        const InsufficientBalance(shortfallPaise: 100),
      );
      expect(map('WALLET_NOT_ACTIVE', status: 403), const WalletNotActive());
      expect(map('CART_CHANGED', status: 409), const CartChanged());
      expect(map('CART_EMPTY', status: 409), const CartChanged());
      expect(map('PRICE_CHANGED', status: 409), const PriceChanged());
      expect(map('DELIVERY_ADDRESS_UNKNOWN', status: 422), const AddressUnknown());
      expect(map('VALIDATION_ERROR', status: 400), const Unexpected('m'));
      expect(map('PRICE_CHANGED', status: 409).clearsKey, isTrue);
    });

    test('LINE_INVALID maps line ids to reasons', () {
      final failure = map(
        'LINE_INVALID',
        status: 422,
        details: {
          'lines': [
            {'lineId': 'li-2', 'reason': 'START_DATE_PAST'},
          ],
        },
      );

      expect(failure, const LineInvalid({'li-2': 'START_DATE_PAST'}));
    });

    test('anything that may still be finishing keeps the key', () {
      expect(map('CHECKOUT_INCOMPLETE', status: 503).clearsKey, isFalse);
      expect(map('DEPENDENCY_UNAVAILABLE', status: 503).clearsKey, isFalse);
      expect(map('NETWORK_ERROR').clearsKey, isFalse);
      expect(map('CHECKOUT_IN_PROGRESS', status: 409).clearsKey, isFalse);
    });
  });

  test('ApiException.details defaults to empty', () {
    const e = ApiException(errorCode: 'X', message: 'm');
    expect(e.details, isEmpty);
  });
}
