import 'package:equatable/equatable.dart';

/// MA-136 FR-9 — `POST /orders/checkout`'s success body.
class CheckoutResult extends Equatable {
  const CheckoutResult({
    required this.checkoutId,
    required this.subscriptions,
    this.order,
    this.walletBalanceAfterPaise,
  });

  final String checkoutId;

  /// Null for a subscription-only cart (nothing is charged at checkout).
  final CheckoutOrder? order;
  final List<CheckoutSubscription> subscriptions;
  final int? walletBalanceAfterPaise;

  List<CheckoutSubscription> get createdSubscriptions =>
      subscriptions.where((s) => s.created).toList();

  List<CheckoutSubscription> get failedSubscriptions =>
      subscriptions.where((s) => !s.created).toList();

  factory CheckoutResult.fromJson(Map<String, dynamic> json) {
    final orderJson = json['order'] as Map<String, dynamic>?;
    return CheckoutResult(
      checkoutId: json['checkoutId'] as String,
      order: orderJson != null ? CheckoutOrder.fromJson(orderJson) : null,
      subscriptions: (json['subscriptions'] as List<dynamic>? ?? const [])
          .map((s) => CheckoutSubscription.fromJson(s as Map<String, dynamic>))
          .toList(),
      walletBalanceAfterPaise: json['walletBalanceAfterPaise'] as int?,
    );
  }

  @override
  List<Object?> get props => [checkoutId, order, subscriptions, walletBalanceAfterPaise];
}

class CheckoutOrder extends Equatable {
  const CheckoutOrder({
    required this.orderId,
    required this.amountPaise,
    required this.deliveryDate,
  });

  final String orderId;
  final int amountPaise;

  /// `yyyy-MM-dd`, the server's own delivery date (MA-136 FR-8).
  final String deliveryDate;

  factory CheckoutOrder.fromJson(Map<String, dynamic> json) => CheckoutOrder(
    orderId: json['orderId'] as String,
    amountPaise: json['amountPaise'] as int,
    deliveryDate: json['deliveryDate'] as String,
  );

  @override
  List<Object?> get props => [orderId, amountPaise, deliveryDate];
}

class CheckoutSubscription extends Equatable {
  const CheckoutSubscription({
    required this.lineId,
    required this.productId,
    required this.created,
    this.subscriptionId,
    this.nextDeliveryDate,
    this.reason,
  });

  final String lineId;
  final String productId;
  final bool created;
  final String? subscriptionId;
  final String? nextDeliveryDate;

  /// Why a line couldn't be subscribed (e.g. `PRODUCT_NOT_ELIGIBLE`) —
  /// that line stays in the cart.
  final String? reason;

  factory CheckoutSubscription.fromJson(Map<String, dynamic> json) => CheckoutSubscription(
    lineId: json['lineId'] as String,
    productId: json['productId'] as String,
    created: json['status'] == 'CREATED',
    subscriptionId: json['subscriptionId'] as String?,
    nextDeliveryDate: json['nextDeliveryDate'] as String?,
    reason: json['reason'] as String?,
  );

  @override
  List<Object?> get props => [
    lineId,
    productId,
    created,
    subscriptionId,
    nextDeliveryDate,
    reason,
  ];
}
