import 'package:equatable/equatable.dart';

import 'order_summary.dart';

/// One row on My Orders: a real order, or a subscription's next delivery
/// that isn't an order yet (MA-145 FR-4).
sealed class OrderEntry extends Equatable {
  const OrderEntry();

  /// IST delivery date (date-only).
  DateTime get date;
}

class OrderedEntry extends OrderEntry {
  const OrderedEntry(this.order);

  final OrderSummary order;

  @override
  DateTime get date => order.deliveryDate;

  @override
  List<Object?> get props => [order];
}

/// Also passed as `extra` to `/orders/scheduled/:subscriptionId` (MA-146).
class ScheduledEntry extends OrderEntry {
  const ScheduledEntry({
    required this.subscriptionId,
    required this.productId,
    required this.quantity,
    required this.date,
  });

  final String subscriptionId;
  final String productId;
  final int quantity;

  @override
  final DateTime date;

  @override
  List<Object?> get props => [subscriptionId, productId, quantity, date];
}
