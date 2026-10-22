import 'package:flutter_test/flutter_test.dart';
import 'package:milkful_app/core/utils/ist_clock.dart';
import 'package:milkful_app/features/orders/domain/cancel_copy.dart';
import 'package:milkful_app/features/orders/domain/order_buckets.dart';
import 'package:milkful_app/features/orders/domain/order_status_copy.dart';
import 'package:milkful_app/features/orders/models/order_entry.dart';
import 'package:milkful_app/features/orders/models/order_summary.dart';

import '../../../fakes/fake_order_repository.dart';

final _today = DateTime(2026, 10, 1);

OrderSummary _customerCancelled({RefundState? refund, int amountPaise = 15500}) => testOrder(
  'ord_1',
  deliveryDate: _today,
  status: OrderStatus.cancelled,
  failureReason: 'CUSTOMER_CANCELLED',
  amountPaise: amountPaise,
  refundState: refund,
);

void main() {
  group('MA-155 FR-7 OrderSummary.fromJson', () {
    Map<String, dynamic> json(Map<String, dynamic> extra) => {
      'orderId': 'ord_1',
      'source': 'CHECKOUT',
      'amountPaise': 15500,
      'deliveryDate': '2026-10-08',
      'status': 'CANCELLED',
      ...extra,
    };

    test('parses the cancel fields', () {
      final o = OrderSummary.fromJson(json({
        'failureReason': 'CUSTOMER_CANCELLED',
        'cancellableUntil': '2026-10-07T20:00:00+05:30',
        'cancelReason': 'NOT_HOME',
        'cancelledAt': '2026-10-07T09:12:03+00:00',
        'refundState': 'PENDING',
      }));
      expect(o.cancellableUntil, DateTime.utc(2026, 10, 7, 14, 30));
      expect(o.cancelReason, CancelReason.notHome);
      expect(o.cancelledAt, DateTime.utc(2026, 10, 7, 9, 12, 3));
      expect(o.refundState, RefundState.pending);
      expect(o.isCustomerCancelled, isTrue);
    });

    test('unknown or missing values become null', () {
      final unknown = OrderSummary.fromJson(json({
        'cancellableUntil': 'not-a-date',
        'cancelReason': 'BORED',
        'refundState': 'MAYBE',
      }));
      expect(unknown.cancellableUntil, isNull);
      expect(unknown.cancelReason, isNull);
      expect(unknown.refundState, isNull);
      final missing = OrderSummary.fromJson(json({}));
      expect(
        [missing.cancellableUntil, missing.cancelReason, missing.cancelledAt, missing.refundState],
        everyElement(isNull),
      );
    });
  });

  group('MA-155 FR-4 status copy', () {
    test('a customer cancel is not "not charged"; a sweep cancel still is', () {
      expect(isKnownNotCharged(_customerCancelled()), isFalse);
      expect(isAmountStruck(_customerCancelled()), isFalse);
      final sweepCancelled = testOrder(
        'x',
        deliveryDate: _today,
        status: OrderStatus.cancelled,
        failureReason: 'CUTOFF_PASSED',
      );
      expect(isKnownNotCharged(sweepCancelled), isTrue);
    });

    test('reason text by refund state', () {
      String text(RefundState? s) => reasonText('CUSTOMER_CANCELLED', _customerCancelled(refund: s));
      expect(text(RefundState.refunded), 'You cancelled this order. ₹155.00 was refunded to your Wallet.');
      expect(text(RefundState.pending), 'You cancelled this order. Your refund is in progress.');
      expect(text(RefundState.notRequired), 'You cancelled this order.');
      expect(text(null), 'You cancelled this order.');
      expect(reasonText('CUSTOMER_CANCELLED'), 'You cancelled this order.');
    });

    test('bill caption never implies a refund that did not happen', () {
      expect(billCaption(_customerCancelled(refund: RefundState.refunded)), 'Refunded to Wallet');
      expect(billCaption(_customerCancelled(refund: RefundState.pending)), 'Refund in progress');
      expect(billCaption(_customerCancelled(refund: RefundState.notRequired)), isNull);
      expect(billCaption(_customerCancelled()), isNull);
    });

    test('day total leaves out a customer-cancelled order but counts a confirmed one', () {
      final total = dayTotal([
        OrderedEntry(_customerCancelled(refund: RefundState.refunded)),
        OrderedEntry(testOrder('ord_2', deliveryDate: _today, amountPaise: 6500)),
      ], const {});
      expect(total.paise, 6500);
    });
  });

  group('MA-155 cut-off and copy', () {
    test('deliveryCutoff is 20:00 IST the day before (14:30 UTC)', () {
      expect(deliveryCutoff(DateTime(2026, 10, 8)), DateTime.utc(2026, 10, 7, 14, 30));
      // Across a month boundary.
      expect(deliveryCutoff(DateTime(2026, 11, 1)), DateTime.utc(2026, 10, 31, 14, 30));
    });

    test('policy lines are in IST', () {
      expect(
        cancelPolicyLine(DateTime.utc(2026, 10, 7, 14, 30)),
        'Free cancellation until 8:00 PM, Wed 7 Oct',
      );
      expect(deliveryPolicyLine(DateTime(2026, 10, 8)), 'Free cancellation until 8:00 PM, Wed 7 Oct');
    });

    test('reason labels', () {
      expect(CancelReason.values.map(reasonLabel), [
        'Ordered by mistake',
        "Won't be home",
        'Changed my mind',
        'Other',
      ]);
    });

    test('sheet policy and result messages', () {
      expect(sheetPolicy(_customerCancelled()), "You'll get a full refund of ₹155.00 to your Milkful Wallet.");
      expect(sheetPolicy(_customerCancelled(amountPaise: 0)), 'Nothing was charged for this order.');
      expect(
        cancelResultMessage(_customerCancelled(refund: RefundState.refunded)),
        'Order cancelled. ₹155.00 refunded to your Wallet.',
      );
      expect(
        cancelResultMessage(_customerCancelled(refund: RefundState.pending)),
        'Order cancelled. Your refund is on its way.',
      );
      expect(cancelResultMessage(_customerCancelled(refund: RefundState.notRequired)), 'Order cancelled.');
    });
  });
}
