import 'package:equatable/equatable.dart';

import '../../../core/utils/ist_clock.dart';

/// MA-132 FR-3 / MA-136 FR-10 — one order as returned by Order Service's
/// `GET /orders/me` and `GET /orders/{id}`. Parsed defensively: an unknown
/// status or source never throws (MA-145 §7).
class OrderSummary extends Equatable {
  const OrderSummary({
    required this.orderId,
    required this.source,
    required this.items,
    required this.amountPaise,
    required this.deliveryDate,
    required this.status,
    this.checkoutId,
    this.subscriptionId,
    this.failureReason,
    this.createdAt,
    this.confirmedAt,
    this.cancellableUntil,
    this.cancelReason,
    this.cancelledAt,
    this.refundState,
  });

  final String orderId;
  final OrderSource source;
  final String? checkoutId;
  final String? subscriptionId;
  final List<OrderItem> items;
  final int amountPaise;

  /// IST calendar date (date-only).
  final DateTime deliveryDate;
  final OrderStatus status;
  final String? failureReason;
  final DateTime? createdAt;
  final DateTime? confirmedAt;

  /// MA-154 FR-7 — set only while a CONFIRMED order can still be cancelled.
  final DateTime? cancellableUntil;
  final CancelReason? cancelReason;
  final DateTime? cancelledAt;
  final RefundState? refundState;

  /// Cancelled by the customer (charged, then refunded) — unlike a
  /// CANCELLED order the backend closed without charging (MA-144).
  bool get isCustomerCancelled =>
      status == OrderStatus.cancelled && failureReason == 'CUSTOMER_CANCELLED';

  factory OrderSummary.fromJson(Map<String, dynamic> json) => OrderSummary(
    orderId: json['orderId'] as String,
    source: OrderSource.fromWire(json['source'] as String?),
    checkoutId: json['checkoutId'] as String?,
    subscriptionId: json['subscriptionId'] as String?,
    items: [
      for (final item in (json['items'] as List? ?? const []))
        OrderItem.fromJson(item as Map<String, dynamic>),
    ],
    amountPaise: (json['amountPaise'] as num?)?.toInt() ?? 0,
    deliveryDate: parseApiDate(json['deliveryDate'] as String),
    status: OrderStatus(json['status'] as String? ?? ''),
    failureReason: json['failureReason'] as String?,
    createdAt: _parseInstant(json['createdAt']),
    confirmedAt: _parseInstant(json['confirmedAt']),
    cancellableUntil: _parseInstant(json['cancellableUntil']),
    cancelReason: CancelReason.fromWire(json['cancelReason']),
    cancelledAt: _parseInstant(json['cancelledAt']),
    refundState: RefundState.fromWire(json['refundState']),
  );

  @override
  List<Object?> get props => [
    orderId,
    source,
    checkoutId,
    subscriptionId,
    items,
    amountPaise,
    deliveryDate,
    status,
    failureReason,
    createdAt,
    confirmedAt,
    cancellableUntil,
    cancelReason,
    cancelledAt,
    refundState,
  ];
}

DateTime? _parseInstant(Object? value) =>
    value is String && value.isNotEmpty ? DateTime.tryParse(value) : null;

class OrderItem extends Equatable {
  const OrderItem({required this.productId, required this.quantity});

  final String productId;
  final int quantity;

  factory OrderItem.fromJson(Map<String, dynamic> json) => OrderItem(
    productId: json['productId'] as String,
    quantity: (json['quantity'] as num?)?.toInt() ?? 0,
  );

  @override
  List<Object?> get props => [productId, quantity];
}

/// MA-154 FR-1 — the optional reason a customer gives for cancelling.
enum CancelReason {
  orderedByMistake('ORDERED_BY_MISTAKE'),
  notHome('NOT_HOME'),
  changedMind('CHANGED_MIND'),
  other('OTHER');

  const CancelReason(this.wire);

  final String wire;

  /// Unknown or missing → null (MA-155 FR-7).
  static CancelReason? fromWire(Object? value) {
    for (final r in values) {
      if (r.wire == value) return r;
    }
    return null;
  }
}

/// MA-154 — where a customer cancel's refund to the Wallet stands.
enum RefundState {
  pending('PENDING'),
  refunded('REFUNDED'),
  notRequired('NOT_REQUIRED');

  const RefundState(this.wire);

  final String wire;

  /// Unknown or missing → null (MA-155 FR-7).
  static RefundState? fromWire(Object? value) {
    for (final s in values) {
      if (s.wire == value) return s;
    }
    return null;
  }
}

enum OrderSource {
  subscription,
  checkout;

  /// Anything other than `SUBSCRIPTION` displays as a checkout order.
  static OrderSource fromWire(String? value) =>
      value == 'SUBSCRIPTION' ? OrderSource.subscription : OrderSource.checkout;
}

/// Order Service's status, kept as its wire string so an unknown value a
/// newer backend adds still round-trips (and renders as-is) instead of
/// failing to parse.
class OrderStatus extends Equatable {
  const OrderStatus(this.wire);

  final String wire;

  static const created = OrderStatus('CREATED');
  static const confirmed = OrderStatus('CONFIRMED');
  static const paymentFailed = OrderStatus('PAYMENT_FAILED');
  static const failed = OrderStatus('FAILED');
  static const needsAttention = OrderStatus('NEEDS_ATTENTION');
  static const cancelled = OrderStatus('CANCELLED');

  static const _knownWire = {
    'CREATED',
    'CONFIRMED',
    'PAYMENT_FAILED',
    'FAILED',
    'NEEDS_ATTENTION',
    'CANCELLED',
  };

  bool get isUnknown => !_knownWire.contains(wire);

  @override
  List<Object?> get props => [wire];
}
