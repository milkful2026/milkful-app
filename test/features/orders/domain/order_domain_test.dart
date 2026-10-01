import 'package:flutter_test/flutter_test.dart';
import 'package:milkful_app/features/catalog/models/product.dart';
import 'package:milkful_app/features/orders/domain/order_buckets.dart';
import 'package:milkful_app/features/orders/domain/order_status_copy.dart';
import 'package:milkful_app/features/orders/models/order_entry.dart';
import 'package:milkful_app/features/orders/models/order_summary.dart';
import 'package:milkful_app/features/subscriptions/models/schedule.dart';
import 'package:milkful_app/features/subscriptions/models/subscription_status.dart';
import 'package:milkful_app/features/subscriptions/models/subscription_view.dart';

import '../../../fakes/fake_order_repository.dart';

final _today = DateTime(2026, 10, 1);
DateTime _d(int offset) => _today.add(Duration(days: offset));

SubscriptionView _sub(String id, {SubscriptionStatus status = SubscriptionStatus.active, DateTime? next}) =>
    SubscriptionView(
      id: id,
      productId: 'cow-milk',
      quantity: 2,
      schedule: const Schedule(type: ScheduleType.daily),
      status: status,
      nextDeliveryDate: next,
    );

Product _product(double price) => Product(
  id: 'cow-milk',
  categoryId: 'milk',
  name: 'Cow Milk',
  description: '',
  unit: '1L',
  price: price,
  stockState: StockState.inStock,
);

void main() {
  group('bucketOrders', () {
    test('splits by delivery date against today, for every status', () {
      final orders = [
        testOrder('t', deliveryDate: _d(0), status: OrderStatus.cancelled),
        testOrder('u', deliveryDate: _d(1), status: OrderStatus.needsAttention),
        testOrder('p', deliveryDate: _d(-1), status: OrderStatus.paymentFailed),
      ];
      final b = bucketOrders(orders, _today);
      expect(b.today.map((o) => o.orderId), ['t']);
      expect(b.upcoming.map((o) => o.orderId), ['u']);
      expect(b.past.map((o) => o.orderId), ['p']);
    });
  });

  group('scheduledEntries', () {
    test('ACTIVE with a future date → entry', () {
      expect(scheduledEntries([_sub('s', next: _d(2))], const [], _today), [
        ScheduledEntry(subscriptionId: 's', productId: 'cow-milk', quantity: 2, date: _d(2)),
      ]);
    });

    test('PAUSED with a future date (pause starts later) → entry', () {
      final subs = [_sub('s', status: SubscriptionStatus.paused, next: _d(2))];
      expect(scheduledEntries(subs, const [], _today), hasLength(1));
    });

    test('STOPPED, null date, or date == today → none', () {
      final subs = [
        _sub('stopped', status: SubscriptionStatus.stopped, next: _d(2)),
        _sub('none'),
        _sub('today', next: _d(0)),
      ];
      expect(scheduledEntries(subs, const [], _today), isEmpty);
    });

    test('an order already for (subscription, date) → none', () {
      final orders = [testOrder('o', deliveryDate: _d(2), subscriptionId: 's')];
      expect(scheduledEntries([_sub('s', next: _d(2))], orders, _today), isEmpty);
    });
  });

  group('groupByDate', () {
    test('orders before scheduled within a day; ascending vs descending', () {
      final entries = <OrderEntry>[
        ScheduledEntry(subscriptionId: 's', productId: 'p', quantity: 1, date: _d(1)),
        OrderedEntry(testOrder('a', deliveryDate: _d(1))),
        OrderedEntry(testOrder('b', deliveryDate: _d(3))),
      ];
      final asc = groupByDate(entries, ascending: true);
      expect(asc.map((g) => g.date), [_d(1), _d(3)]);
      expect(asc.first.entries.first, isA<OrderedEntry>());
      expect(groupByDate(entries, ascending: false).first.date, _d(3));
    });
  });

  group('dayTotal', () {
    test('excludes known-not-charged, includes charge-unknown NEEDS_ATTENTION', () {
      final entries = <OrderEntry>[
        OrderedEntry(testOrder('ok', deliveryDate: _d(1), amountPaise: 1000)),
        OrderedEntry(testOrder('c', deliveryDate: _d(1), status: OrderStatus.cancelled, amountPaise: 1)),
        OrderedEntry(testOrder('f', deliveryDate: _d(1), status: OrderStatus.failed, amountPaise: 8)),
        OrderedEntry(testOrder('pf', deliveryDate: _d(1), status: OrderStatus.paymentFailed, amountPaise: 2)),
        OrderedEntry(
          testOrder('cut', deliveryDate: _d(1), status: OrderStatus.needsAttention,
              failureReason: 'CUTOFF_PASSED', amountPaise: 4),
        ),
        OrderedEntry(
          testOrder('rev', deliveryDate: _d(1), status: OrderStatus.needsAttention,
              failureReason: 'SWEEP_EXHAUSTED', amountPaise: 500),
        ),
      ];
      final total = dayTotal(entries, const {});
      expect(total.paise, 1500);
      expect(total.hasEstimate, isFalse);
    });

    test('scheduled estimate is paise: unit price rounded, then × quantity', () {
      final s = ScheduledEntry(subscriptionId: 's', productId: 'cow-milk', quantity: 2, date: _d(1));
      expect(estimatePaise(s, _product(37.485)), 7498); // 3749 × 2
      expect(estimatePaise(s, _product(32.5)), 6500);
      final total = dayTotal([OrderedEntry(testOrder('o', deliveryDate: _d(1))), s],
          {'cow-milk': _product(32.5)});
      expect(total.paise, 6500 + 6500);
      expect(total.hasEstimate, isTrue);
    });

    test('unknown price is skipped', () {
      final s = ScheduledEntry(subscriptionId: 's', productId: 'cow-milk', quantity: 1, date: _d(1));
      final total = dayTotal([s], const {'cow-milk': null});
      expect((total.paise, total.hasEstimate), (0, false));
    });
  });

  group('status copy', () {
    test('chip labels, with no Delivered state', () {
      expect(statusChip(OrderStatus.confirmed).label, 'Order Placed');
      expect(statusChip(OrderStatus.created).label, 'Processing');
      expect(statusChip(OrderStatus.paymentFailed).label, 'Payment Failed');
      expect(statusChip(OrderStatus.cancelled).label, 'Cancelled');
      expect(statusChip(OrderStatus.needsAttention).label, 'Under Review');
      expect(statusChip(OrderStatus.failed).label, 'Failed');
      final unknown = statusChip(const OrderStatus('OUT_FOR_DELIVERY'));
      expect((unknown.label, unknown.tone, unknown.icon), ('Out For Delivery', ChipTone.neutral, null));
    });

    test('isAmountStruck: known-not-charged plus legacy FAILED', () {
      OrderSummary o(OrderStatus s, [String? r]) =>
          testOrder('x', deliveryDate: _today, status: s, failureReason: r);
      expect(isAmountStruck(o(OrderStatus.cancelled)), isTrue);
      expect(isAmountStruck(o(OrderStatus.paymentFailed)), isTrue);
      expect(isAmountStruck(o(OrderStatus.needsAttention, 'CUTOFF_PASSED')), isTrue);
      expect(isAmountStruck(o(OrderStatus.failed)), isTrue);
      expect(isAmountStruck(o(OrderStatus.needsAttention, 'SWEEP_EXHAUSTED')), isFalse);
      expect(isAmountStruck(o(OrderStatus.confirmed)), isFalse);
      expect(isAmountStruck(o(OrderStatus.created)), isFalse);
    });

    test('isKnownNotCharged truth table', () {
      OrderSummary o(OrderStatus s, [String? r]) => testOrder('x', deliveryDate: _today, status: s, failureReason: r);
      expect(isKnownNotCharged(o(OrderStatus.cancelled)), isTrue);
      expect(isKnownNotCharged(o(OrderStatus.paymentFailed)), isTrue);
      expect(isKnownNotCharged(o(OrderStatus.needsAttention, 'CUTOFF_PASSED')), isTrue);
      expect(isKnownNotCharged(o(OrderStatus.needsAttention, 'SWEEP_EXHAUSTED')), isFalse);
      expect(isKnownNotCharged(o(OrderStatus.needsAttention)), isFalse);
      expect(isKnownNotCharged(o(OrderStatus.confirmed)), isFalse);
      expect(isKnownNotCharged(o(OrderStatus.failed)), isFalse);
    });
  });

  group('OrderSummary.fromJson', () {
    test('parses fields and tolerates unknown status/source and missing items', () {
      final o = OrderSummary.fromJson({
        'orderId': 'ord_1',
        'source': 'SOMETHING_NEW',
        'amountPaise': 6500,
        'deliveryDate': '2026-10-03',
        'status': 'OUT_FOR_DELIVERY',
        'createdAt': '2026-10-01T10:00:00+00:00',
      });
      expect(o.source, OrderSource.checkout);
      expect(o.items, isEmpty);
      expect(o.status.isUnknown, isTrue);
      expect(o.deliveryDate, DateTime(2026, 10, 3));
      expect(o.createdAt, isNotNull);
    });
  });

  group('MA-146 detail copy', () {
    OrderSummary o(OrderStatus s, [String? r]) =>
        testOrder('x', deliveryDate: _today, status: s, failureReason: r);

    test('reason text for every known reason, generic otherwise', () {
      expect(reasonText('INSUFFICIENT_BALANCE'), contains("didn't have enough balance"));
      expect(reasonText('WALLET_NOT_ACTIVE'), contains("wasn't active"));
      expect(reasonText('DELIVERY_ADDRESS_UNKNOWN'), contains('delivery address'));
      expect(reasonText('PRODUCT_UNAVAILABLE'), contains('no longer available'));
      expect(reasonText('SOMETHING_NEW'), 'Something went wrong with this order.');
      expect(reasonText(null), 'Something went wrong with this order.');
    });

    test('the not-charged copy appears only for CUTOFF_PASSED', () {
      expect(reasonText('CUTOFF_PASSED'), contains("You weren't charged"));
      for (final r in ['SWEEP_EXHAUSTED', 'INSUFFICIENT_BALANCE', null]) {
        expect(reasonText(r), isNot(contains("You weren't charged")));
      }
      expect(reasonText('SWEEP_EXHAUSTED'), contains("won't be charged twice"));
    });

    test('bill caption truth table', () {
      expect(billCaption(o(OrderStatus.cancelled)), 'Not charged');
      expect(billCaption(o(OrderStatus.paymentFailed)), 'Not charged');
      expect(billCaption(o(OrderStatus.needsAttention, 'CUTOFF_PASSED')), 'Not charged');
      expect(billCaption(o(OrderStatus.needsAttention, 'SWEEP_EXHAUSTED')), 'Charge under review');
      expect(billCaption(o(OrderStatus.needsAttention)), 'Charge under review');
      expect(billCaption(o(OrderStatus.failed)), isNull);
      expect(billCaption(o(OrderStatus.confirmed)), isNull);
    });

    test('displayOrderId', () {
      expect(displayOrderId('ord_3f9a2c1b77e04d'), '#3F9A2C1B');
      expect(displayOrderId('abcdef1234'), '#ABCDEF12');
      expect(displayOrderId('ord_ab'), '#AB');
    });
  });
}
