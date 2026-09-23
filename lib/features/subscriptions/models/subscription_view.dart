import 'package:equatable/equatable.dart';

import 'schedule.dart';
import 'subscription_status.dart';

/// Mirrors subscription/src/domain/subscription_service.py's
/// `_detail_response`/`_create_response` shapes. `productName` is **not**
/// part of that response (Subscription Service only knows `productId`) —
/// it's resolved separately by `SubscriptionBloc` via `CatalogRepository`
/// and attached with [copyWithProductName], defaulting to [productId]
/// itself if that lookup fails (MA-133 §9 — a subscription still renders,
/// just without a friendly name, rather than blocking the whole list).
class SubscriptionView extends Equatable {
  const SubscriptionView({
    required this.id,
    required this.productId,
    required this.quantity,
    required this.schedule,
    required this.status,
    this.productName,
    this.nextDeliveryDate,
    this.pauseFrom,
    this.pauseUntil,
  });

  final String id;
  final String productId;
  final String? productName;
  final int quantity;
  final Schedule schedule;
  final SubscriptionStatus status;
  final DateTime? nextDeliveryDate;
  final DateTime? pauseFrom;
  final DateTime? pauseUntil;

  /// FR-3's `vacationModeOn` aggregate: `true` for a subscription that is
  /// `PAUSED` with no end date — indistinguishable, by design of the
  /// current backend data model, from one paused open-ended via its own
  /// detail sheet (MA-133 §11 Risk).
  bool get isPausedIndefinitely => status == SubscriptionStatus.paused && pauseUntil == null;

  factory SubscriptionView.fromJson(Map<String, dynamic> json) => SubscriptionView(
    id: json['subscriptionId'] as String,
    productId: json['productId'] as String,
    quantity: json['quantity'] as int,
    schedule: Schedule.fromJson(json['schedule'] as Map<String, dynamic>),
    status: SubscriptionStatus.fromWire(json['status'] as String),
    nextDeliveryDate: json['nextDeliveryDate'] == null
        ? null
        : DateTime.parse(json['nextDeliveryDate'] as String),
    pauseFrom: json['pauseFrom'] == null ? null : DateTime.parse(json['pauseFrom'] as String),
    pauseUntil: json['pauseUntil'] == null ? null : DateTime.parse(json['pauseUntil'] as String),
  );

  SubscriptionView copyWithProductName(String productName) => SubscriptionView(
    id: id,
    productId: productId,
    productName: productName,
    quantity: quantity,
    schedule: schedule,
    status: status,
    nextDeliveryDate: nextDeliveryDate,
    pauseFrom: pauseFrom,
    pauseUntil: pauseUntil,
  );

  @override
  List<Object?> get props => [
    id,
    productId,
    productName,
    quantity,
    schedule,
    status,
    nextDeliveryDate,
    pauseFrom,
    pauseUntil,
  ];
}
