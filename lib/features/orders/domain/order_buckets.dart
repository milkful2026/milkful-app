import '../../../core/utils/ist_clock.dart';
import '../../../core/utils/money.dart';
import '../../catalog/models/product.dart';
import '../../subscriptions/models/subscription_status.dart';
import '../../subscriptions/models/subscription_view.dart';
import '../models/order_entry.dart';
import '../models/order_summary.dart';
import 'order_status_copy.dart';

/// MA-145 FR-3/FR-4/FR-8/FR-9 as pure functions (no Flutter imports), so
/// every rule is unit-testable against a fixed "today".

class OrderBuckets {
  const OrderBuckets({required this.today, required this.upcoming, required this.past});

  final List<OrderSummary> today;
  final List<OrderSummary> upcoming;
  final List<OrderSummary> past;
}

/// FR-3 — by delivery date against IST today; every status is bucketed.
OrderBuckets bucketOrders(List<OrderSummary> orders, DateTime today) {
  final t = dateOnly(today);
  final todays = <OrderSummary>[];
  final upcoming = <OrderSummary>[];
  final past = <OrderSummary>[];
  for (final order in orders) {
    final d = dateOnly(order.deliveryDate);
    if (d == t) {
      todays.add(order);
    } else if (d.isAfter(t)) {
      upcoming.add(order);
    } else {
      past.add(order);
    }
  }
  return OrderBuckets(today: todays, upcoming: upcoming, past: past);
}

/// FR-4 — each non-STOPPED subscription's next delivery after today that
/// isn't already an order. A PAUSED subscription with a future date is
/// included: a pause starting later still leaves earlier deliveries due,
/// and Subscription Service computes `nextDeliveryDate` from the pause.
List<ScheduledEntry> scheduledEntries(
  List<SubscriptionView> subscriptions,
  List<OrderSummary> orders,
  DateTime today,
) {
  final t = dateOnly(today);
  final ordered = {
    for (final o in orders)
      if (o.subscriptionId != null) '${o.subscriptionId}|${dateOnly(o.deliveryDate)}',
  };
  return [
    for (final s in subscriptions)
      if (s.status != SubscriptionStatus.stopped &&
          s.nextDeliveryDate != null &&
          dateOnly(s.nextDeliveryDate!).isAfter(t) &&
          !ordered.contains('${s.id}|${dateOnly(s.nextDeliveryDate!)}'))
        ScheduledEntry(
          subscriptionId: s.id,
          productId: s.productId,
          quantity: s.quantity,
          date: dateOnly(s.nextDeliveryDate!),
        ),
  ];
}

class DayGroup {
  const DayGroup(this.date, this.entries);

  final DateTime date;
  final List<OrderEntry> entries;
}

/// FR-9 — one group per date; within a day, orders (in input order) come
/// before scheduled entries.
List<DayGroup> groupByDate(List<OrderEntry> entries, {required bool ascending}) {
  final byDate = <DateTime, List<OrderEntry>>{};
  for (final e in entries) {
    byDate.putIfAbsent(dateOnly(e.date), () => []).add(e);
  }
  final dates = byDate.keys.toList()..sort();
  final ordered = ascending ? dates : dates.reversed.toList();
  return [
    for (final d in ordered)
      DayGroup(d, [
        ...byDate[d]!.whereType<OrderedEntry>(),
        ...byDate[d]!.whereType<ScheduledEntry>(),
      ]),
  ];
}

/// FR-8 — `round(price × 100) × quantity`, in paise; null when the product
/// (and so its price) is unknown.
int? estimatePaise(ScheduledEntry entry, Product? product) =>
    product == null ? null : rupeesToPaise(product.price) * entry.quantity;

class DayTotal {
  const DayTotal(this.paise, {required this.hasEstimate});

  final int paise;
  final bool hasEstimate;
}

/// FR-8 — sums exact order amounts and scheduled estimates. Known-not-
/// charged (and legacy FAILED) orders are left out; an unknown estimate is
/// skipped. A customer-cancelled order is left out too: its amount isn't
/// struck (it was charged), but it was refunded (MA-32, decided 2026-10-08).
DayTotal dayTotal(List<OrderEntry> entries, Map<String, Product?> products) {
  var paise = 0;
  var hasEstimate = false;
  for (final e in entries) {
    switch (e) {
      case OrderedEntry(:final order):
        if (!isAmountStruck(order) && !order.isCustomerCancelled) {
          paise += order.amountPaise;
        }
      case ScheduledEntry():
        final estimate = estimatePaise(e, products[e.productId]);
        if (estimate != null) {
          paise += estimate;
          hasEstimate = true;
        }
    }
  }
  return DayTotal(paise, hasEstimate: hasEstimate);
}
