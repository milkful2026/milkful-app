import 'package:equatable/equatable.dart';

import '../models/payment_method.dart';

sealed class WalletEvent extends Equatable {
  const WalletEvent();

  @override
  List<Object?> get props => [];
}

/// Initial load; also resumes a persisted pending-attempt record if one
/// exists (FR-6a).
class WalletStarted extends WalletEvent {
  const WalletStarted();
}

/// Pull-to-refresh / on-resume — re-fetches the displayed balance/status
/// only; never touches an in-flight recharge attempt.
class WalletRefreshRequested extends WalletEvent {
  const WalletRefreshRequested();
}

class QuickAmountSelected extends WalletEvent {
  const QuickAmountSelected(this.amountPaise);

  final int amountPaise;

  @override
  List<Object?> get props => [amountPaise];
}

class CustomAmountEntered extends WalletEvent {
  const CustomAmountEntered(this.amountPaise);

  final int amountPaise;

  @override
  List<Object?> get props => [amountPaise];
}

class AmountCleared extends WalletEvent {
  const AmountCleared();
}

class PaymentMethodSelected extends WalletEvent {
  const PaymentMethodSelected(this.method);

  final PaymentMethod method;

  @override
  List<Object?> get props => [method];
}

/// Build/keep the idempotency key, write the `wallet.pendingRecharge`
/// record, call `createRecharge`.
class RechargeRequested extends WalletEvent {
  const RechargeRequested();
}

/// The Razorpay sheet reported success — call `confirmRecharge` (all
/// three ids required; MA-126 FR-2), enter pending.
class RechargeGatewaySucceeded extends WalletEvent {
  const RechargeGatewaySucceeded({
    required this.razorpayPaymentId,
    required this.razorpayOrderId,
    required this.razorpaySignature,
  });

  final String razorpayPaymentId;
  final String razorpayOrderId;
  final String razorpaySignature;

  @override
  List<Object?> get props => [razorpayPaymentId, razorpayOrderId, razorpaySignature];
}

class RechargeGatewayFailed extends WalletEvent {
  const RechargeGatewayFailed({required this.code, required this.description});

  final String code;
  final String description;

  @override
  List<Object?> get props => [code, description];
}

/// Benign cancel — the sheet closed before a Razorpay success.
class RechargeGatewayDismissed extends WalletEvent {
  const RechargeGatewayDismissed();
}

/// Internal (timer-driven) poll of the pending payment's authoritative
/// state — never inferred from a wallet balance delta (round-2 finding #10).
class RechargePollTick extends WalletEvent {
  const RechargePollTick();
}

class WalletProvisionRetryRequested extends WalletEvent {
  const WalletProvisionRetryRequested();
}

/// User confirmed "Start over" on a stale (>30 min) pending attempt
/// (FR-6a): clears the persisted record, re-enables the CTA.
class PendingRechargeAbandoned extends WalletEvent {
  const PendingRechargeAbandoned();
}
