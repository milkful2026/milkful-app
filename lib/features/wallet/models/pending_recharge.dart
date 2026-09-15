import 'package:equatable/equatable.dart';

import 'payment_method.dart';

/// The `wallet.pendingRecharge` `shared_preferences` record (MA-125 §7,
/// PR #16 round-2 finding #6) — the one recharge attempt currently in
/// flight or awaiting confirmation. Written before the Razorpay sheet
/// opens; read on `WalletStarted` to resume polling after an app kill or
/// a pending-timeout; cleared only on a terminal outcome. This is what
/// makes a relaunch resume the *same* payment instead of allowing a
/// second, separately-chargeable recharge for the same top-up.
class PendingRecharge extends Equatable {
  const PendingRecharge({
    required this.idempotencyKey,
    required this.paymentId,
    required this.amountPaise,
    required this.method,
    required this.createdAtIso,
  });

  final String idempotencyKey;
  final String paymentId;
  final int amountPaise;
  final PaymentMethod method;
  final String createdAtIso;

  Map<String, dynamic> toJson() => {
    'idempotencyKey': idempotencyKey,
    'paymentId': paymentId,
    'amountPaise': amountPaise,
    'method': method.wireValue,
    'createdAtIso': createdAtIso,
  };

  factory PendingRecharge.fromJson(Map<String, dynamic> json) => PendingRecharge(
    idempotencyKey: json['idempotencyKey'] as String,
    paymentId: json['paymentId'] as String,
    amountPaise: json['amountPaise'] as int,
    method: PaymentMethod.fromWire(json['method'] as String),
    createdAtIso: json['createdAtIso'] as String,
  );

  @override
  List<Object?> get props => [idempotencyKey, paymentId, amountPaise, method, createdAtIso];
}
