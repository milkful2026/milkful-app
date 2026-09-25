import 'package:milkful_app/features/checkout/data/checkout_repository.dart';
import 'package:milkful_app/features/checkout/models/checkout_result.dart';

class FakeCheckoutCall {
  FakeCheckoutCall({
    required this.cartVersion,
    required this.expectedPayNowPaise,
    required this.idempotencyKey,
  });

  final int cartVersion;
  final int expectedPayNowPaise;
  final String idempotencyKey;
}

/// Scriptable Order Service checkout: [outcomes] is consumed one entry per
/// call (a [CheckoutResult] to return, or anything else to throw); once
/// empty, [result] is returned.
class FakeCheckoutRepository implements CheckoutRepository {
  FakeCheckoutRepository({this.result, List<Object>? outcomes}) : outcomes = outcomes ?? [];

  CheckoutResult? result;
  final List<Object> outcomes;
  final List<FakeCheckoutCall> calls = [];

  static const defaultResult = CheckoutResult(
    checkoutId: 'chk_1',
    order: CheckoutOrder(orderId: 'ord_1', amountPaise: 10820, deliveryDate: '2026-09-26'),
    subscriptions: [],
    walletBalanceAfterPaise: 39180,
  );

  @override
  Future<CheckoutResult> checkout({
    required int cartVersion,
    required int expectedPayNowPaise,
    required String idempotencyKey,
  }) async {
    calls.add(
      FakeCheckoutCall(
        cartVersion: cartVersion,
        expectedPayNowPaise: expectedPayNowPaise,
        idempotencyKey: idempotencyKey,
      ),
    );
    if (outcomes.isNotEmpty) {
      final next = outcomes.removeAt(0);
      if (next is CheckoutResult) return next;
      throw next;
    }
    return result ?? defaultResult;
  }
}
