import 'package:equatable/equatable.dart';

import '../models/payment_method.dart';
import '../models/pending_recharge.dart';
import '../models/recharge_order.dart';
import '../models/wallet_view.dart';

enum WalletLoadStatus { idle, loading, loaded, failed }

/// The recharge attempt's own lifecycle, independent of [WalletLoadStatus]
/// — `creatingOrder` through `confirming` are each a single API round-trip;
/// `pending` covers the poll loop started after a successful `confirm`
/// call (MA-125 FR-6) and after a resumed attempt (FR-6a).
enum RechargeStatus {
  idle,
  creatingOrder,
  awaitingGateway,
  confirming,
  pending,
  success,
  failed,
}

enum ProvisionRetryStatus { idle, loading, failed }

class WalletState extends Equatable {
  const WalletState({
    this.walletLoadStatus = WalletLoadStatus.idle,
    this.wallet,
    this.walletErrorMessage,
    this.selectedAmountPaise,
    this.selectedMethod = PaymentMethod.card,
    this.rechargeStatus = RechargeStatus.idle,
    this.rechargeErrorMessage,
    this.idempotencyKey,
    this.activeOrder,
    this.lastConfirmedAmountPaise,
    this.pendingRecharge,
    this.isPendingStale = false,
    this.provisionRetryStatus = ProvisionRetryStatus.idle,
  });

  final WalletLoadStatus walletLoadStatus;
  final WalletView? wallet;
  final String? walletErrorMessage;

  final int? selectedAmountPaise;
  final PaymentMethod selectedMethod;

  final RechargeStatus rechargeStatus;
  final String? rechargeErrorMessage;

  /// Set for this recharge attempt and reused verbatim across a retry of
  /// a *pre-confirm* failure (MA-125 FR-8) — cleared only on a terminal
  /// outcome (success, a post-confirm `getPayment()` FAILED, or a
  /// user-confirmed abandon), never on the pre-confirm failures
  /// themselves. [canRetryRecharge] uses its presence to tell those two
  /// kinds of failure apart without a dedicated state field.
  final String? idempotencyKey;

  /// The order just returned by `createRecharge` — carries the ids the
  /// gateway sheet and the subsequent `confirmRecharge` call both need.
  final RechargeOrder? activeOrder;

  /// The amount of the most recently *successful* recharge — the success
  /// sheet's copy ("₹{amount} added") needs this after [selectedAmountPaise]
  /// has already been cleared.
  final int? lastConfirmedAmountPaise;

  /// The persisted `wallet.pendingRecharge` record (MA-125 §7). Non-null
  /// from the moment `RechargeRequested` writes it until a terminal
  /// outcome (success or a real failure) clears it — surviving an app
  /// kill in between (FR-6a).
  final PendingRecharge? pendingRecharge;

  /// FR-6a: a resumed [pendingRecharge] older than [staleAfter] is shown
  /// with a "Start over" choice rather than silently resumed forever.
  final bool isPendingStale;

  final ProvisionRetryStatus provisionRetryStatus;

  static const staleAfter = Duration(minutes: 30);

  bool get isRechargeInFlight => switch (rechargeStatus) {
    RechargeStatus.creatingOrder ||
    RechargeStatus.awaitingGateway ||
    RechargeStatus.confirming ||
    RechargeStatus.pending => true,
    _ => false,
  };

  /// FR-2/FR-3 — the CTA needs a wallet in good standing, a valid amount
  /// selection, and no attempt already in flight or awaiting a decision.
  bool get canStartRecharge =>
      walletLoadStatus == WalletLoadStatus.loaded &&
      wallet != null &&
      wallet!.status.name == 'active' &&
      !isRechargeInFlight &&
      pendingRecharge == null &&
      selectedAmountPaise != null &&
      selectedAmountPaise! >= wallet!.rechargeMinPaise &&
      selectedAmountPaise! <= wallet!.rechargeMaxPaise;

  bool get showPendingBanner => pendingRecharge != null && rechargeStatus == RechargeStatus.pending;

  /// FR-8: a Retry button only ever appears for a *pre-confirm* failure
  /// (a `createRecharge` API error or a Razorpay gateway error) — never
  /// for a post-confirm, server-authoritative `getPayment()` FAILED. Both
  /// share [RechargeStatus.failed]; [idempotencyKey] survives only the
  /// former, so its presence is what tells the two apart.
  bool get canRetryRecharge => rechargeStatus == RechargeStatus.failed && idempotencyKey != null;

  WalletState copyWith({
    WalletLoadStatus? walletLoadStatus,
    WalletView? wallet,
    String? walletErrorMessage,
    bool clearWalletErrorMessage = false,
    int? selectedAmountPaise,
    bool clearSelectedAmountPaise = false,
    PaymentMethod? selectedMethod,
    RechargeStatus? rechargeStatus,
    String? rechargeErrorMessage,
    bool clearRechargeErrorMessage = false,
    String? idempotencyKey,
    bool clearIdempotencyKey = false,
    RechargeOrder? activeOrder,
    bool clearActiveOrder = false,
    int? lastConfirmedAmountPaise,
    PendingRecharge? pendingRecharge,
    bool clearPendingRecharge = false,
    bool? isPendingStale,
    ProvisionRetryStatus? provisionRetryStatus,
  }) => WalletState(
    walletLoadStatus: walletLoadStatus ?? this.walletLoadStatus,
    wallet: wallet ?? this.wallet,
    walletErrorMessage: clearWalletErrorMessage ? null : (walletErrorMessage ?? this.walletErrorMessage),
    selectedAmountPaise: clearSelectedAmountPaise ? null : (selectedAmountPaise ?? this.selectedAmountPaise),
    selectedMethod: selectedMethod ?? this.selectedMethod,
    rechargeStatus: rechargeStatus ?? this.rechargeStatus,
    rechargeErrorMessage: clearRechargeErrorMessage
        ? null
        : (rechargeErrorMessage ?? this.rechargeErrorMessage),
    idempotencyKey: clearIdempotencyKey ? null : (idempotencyKey ?? this.idempotencyKey),
    activeOrder: clearActiveOrder ? null : (activeOrder ?? this.activeOrder),
    lastConfirmedAmountPaise: lastConfirmedAmountPaise ?? this.lastConfirmedAmountPaise,
    pendingRecharge: clearPendingRecharge ? null : (pendingRecharge ?? this.pendingRecharge),
    isPendingStale: clearPendingRecharge ? false : (isPendingStale ?? this.isPendingStale),
    provisionRetryStatus: provisionRetryStatus ?? this.provisionRetryStatus,
  );

  @override
  List<Object?> get props => [
    walletLoadStatus,
    wallet,
    walletErrorMessage,
    selectedAmountPaise,
    selectedMethod,
    rechargeStatus,
    rechargeErrorMessage,
    idempotencyKey,
    activeOrder,
    lastConfirmedAmountPaise,
    pendingRecharge,
    isPendingStale,
    provisionRetryStatus,
  ];
}
