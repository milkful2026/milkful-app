import 'package:equatable/equatable.dart';

import 'payment_status.dart';

/// `GET /payments/{id}`'s response shape (MA-126 FR-4) — what the pending-
/// recharge poll (MA-125 FR-6) reads. `status` is the sole source of truth
/// for whether a recharge succeeded; the app never infers it from a wallet
/// balance delta (PR #16 round-2 finding #10).
class PaymentView extends Equatable {
  const PaymentView({
    required this.paymentId,
    required this.status,
    required this.amountPaise,
    this.failureReason,
  });

  final String paymentId;
  final PaymentStatus status;
  final int amountPaise;
  final String? failureReason;

  factory PaymentView.fromJson(Map<String, dynamic> json) => PaymentView(
    paymentId: json['paymentId'] as String,
    status: PaymentStatus.fromWire(json['status'] as String),
    amountPaise: json['amountPaise'] as int,
    failureReason: json['failureReason'] as String?,
  );

  @override
  List<Object?> get props => [paymentId, status, amountPaise, failureReason];
}
