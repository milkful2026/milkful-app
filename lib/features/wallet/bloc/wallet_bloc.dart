import 'dart:async';

import 'package:bloc_concurrency/bloc_concurrency.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../core/network/api_client.dart';
import '../../../core/utils/id_generator.dart';
import '../data/pending_recharge_store.dart';
import '../data/razorpay_checkout.dart';
import '../data/wallet_repository.dart';
import '../models/payment_method.dart';
import '../models/payment_status.dart';
import '../models/payment_view.dart';
import '../models/pending_recharge.dart';
import 'wallet_event.dart';
import 'wallet_state.dart';

/// MA-24's Wallet & Recharge screen bloc — owns the balance load, the
/// amount/method selection, and the full recharge attempt lifecycle
/// (create order → Razorpay sheet → confirm → poll to a terminal
/// [PaymentStatus]), including resuming or abandoning a [PendingRecharge]
/// left over from a killed app (MA-125 FR-6a).
///
/// Success is decided **only** by `getPayment().status == confirmed`
/// (PR #16 round-2 finding #10) — never by a wallet balance delta, since
/// the credit is webhook-driven and may lag the poll.
class WalletBloc extends Bloc<WalletEvent, WalletState> {
  WalletBloc({
    required this._walletRepository,
    required this._razorpayCheckout,
    required this._pendingRechargeStore,
    required this._paymentMethodStore,
    Duration pollInterval = const Duration(seconds: 2),
    int maxPollAttemptsPerSession = 10,
  }) : _pollInterval = pollInterval,
       _maxPollAttemptsPerSession = maxPollAttemptsPerSession,
       super(const WalletState()) {
    on<WalletStarted>(_onStarted);
    on<WalletRefreshRequested>(_onRefreshRequested);
    on<QuickAmountSelected>(_onQuickAmountSelected);
    on<CustomAmountEntered>(_onCustomAmountEntered);
    on<AmountCleared>(_onAmountCleared);
    on<PaymentMethodSelected>(_onPaymentMethodSelected);
    // droppable(): a second tap while an attempt is already in flight must
    // never mint a second idempotency key / open a second sheet.
    on<RechargeRequested>(_onRechargeRequested, transformer: droppable());
    on<RechargeGatewaySucceeded>(_onRechargeGatewaySucceeded, transformer: droppable());
    on<RechargeGatewayFailed>(_onRechargeGatewayFailed);
    on<RechargeGatewayDismissed>(_onRechargeGatewayDismissed);
    // restartable(): a manual refresh/resume can race the timer-driven
    // tick it itself scheduled — only the newest one should finish.
    on<RechargePollTick>(_onRechargePollTick, transformer: restartable());
    on<WalletProvisionRetryRequested>(_onProvisionRetryRequested, transformer: droppable());
    on<PendingRechargeAbandoned>(_onPendingRechargeAbandoned);
  }

  final WalletRepository _walletRepository;
  final RazorpayCheckout _razorpayCheckout;
  final PendingRechargeStore _pendingRechargeStore;
  final PaymentMethodStore _paymentMethodStore;
  final Duration _pollInterval;

  /// MA-125 FR-6: the in-session poll runs every [_pollInterval] up to
  /// this many attempts (2s × 10 = 20s) before it stops on its own,
  /// leaving the persisted record + pending banner in place for the next
  /// manual refresh or app reopen to resume (FR-6a).
  final int _maxPollAttemptsPerSession;
  int _pollAttemptsThisSession = 0;

  Future<void> _onStarted(WalletStarted event, Emitter<WalletState> emit) async {
    final lastMethodWire = await _paymentMethodStore.read();
    final pending = await _pendingRechargeStore.read();

    emit(
      state.copyWith(
        walletLoadStatus: WalletLoadStatus.loading,
        selectedMethod: lastMethodWire != null ? PaymentMethod.fromWire(lastMethodWire) : null,
        idempotencyKey: pending?.idempotencyKey,
        pendingRecharge: pending,
        rechargeStatus: pending != null ? RechargeStatus.pending : state.rechargeStatus,
      ),
    );

    await _loadWallet(emit);

    if (pending == null || isClosed) return;
    _startPollSession();
    add(const RechargePollTick());
  }

  Future<void> _onRefreshRequested(WalletRefreshRequested event, Emitter<WalletState> emit) async {
    await _loadWallet(emit);
    if (isClosed || state.pendingRecharge == null) return;
    _startPollSession();
    add(const RechargePollTick());
  }

  void _startPollSession() => _pollAttemptsThisSession = 0;

  Future<void> _loadWallet(Emitter<WalletState> emit) async {
    try {
      final wallet = await _walletRepository.getWallet();
      if (isClosed) return;
      emit(
        state.copyWith(
          walletLoadStatus: WalletLoadStatus.loaded,
          wallet: wallet,
          clearWalletErrorMessage: true,
        ),
      );
    } on ApiException catch (e) {
      if (isClosed) return;
      emit(state.copyWith(walletLoadStatus: WalletLoadStatus.failed, walletErrorMessage: e.message));
    } catch (_) {
      if (isClosed) return;
      emit(state.copyWith(walletLoadStatus: WalletLoadStatus.failed));
    }
  }

  /// FR-6/§6: rejected outright while a prior attempt is unresolved (the
  /// CTA is disabled then anyway); otherwise a new amount is a new
  /// attempt, so any idempotency key held from a pre-confirm failure of a
  /// *different* amount must not be reused.
  void _onQuickAmountSelected(QuickAmountSelected event, Emitter<WalletState> emit) {
    if (state.pendingRecharge != null) return;
    emit(_selectAmount(event.amountPaise));
  }

  void _onCustomAmountEntered(CustomAmountEntered event, Emitter<WalletState> emit) {
    if (state.pendingRecharge != null) return;
    emit(_selectAmount(event.amountPaise));
  }

  WalletState _selectAmount(int amountPaise) => state.copyWith(
    selectedAmountPaise: amountPaise,
    clearIdempotencyKey: true,
    clearRechargeErrorMessage: true,
    rechargeStatus: state.rechargeStatus == RechargeStatus.failed ? RechargeStatus.idle : state.rechargeStatus,
  );

  void _onAmountCleared(AmountCleared event, Emitter<WalletState> emit) {
    if (state.pendingRecharge != null) return;
    emit(state.copyWith(clearSelectedAmountPaise: true, clearIdempotencyKey: true));
  }

  Future<void> _onPaymentMethodSelected(
    PaymentMethodSelected event,
    Emitter<WalletState> emit,
  ) async {
    emit(state.copyWith(selectedMethod: event.method));
    await _paymentMethodStore.write(event.method.wireValue);
  }

  Future<void> _onRechargeRequested(RechargeRequested event, Emitter<WalletState> emit) async {
    if (!state.canStartRecharge) return;

    final amountPaise = state.selectedAmountPaise!;
    final method = state.selectedMethod;
    // Reused verbatim across a retry of a pre-confirm failure (FR-8) —
    // only minted fresh the first time this attempt is made.
    final idempotencyKey = state.idempotencyKey ?? newHexId();

    emit(
      state.copyWith(
        rechargeStatus: RechargeStatus.creatingOrder,
        idempotencyKey: idempotencyKey,
        clearRechargeErrorMessage: true,
      ),
    );

    try {
      final order = await _walletRepository.createRecharge(
        amountPaise: amountPaise,
        method: method,
        idempotencyKey: idempotencyKey,
      );
      if (isClosed) return;

      final pending = PendingRecharge(
        idempotencyKey: idempotencyKey,
        paymentId: order.paymentId,
        amountPaise: amountPaise,
        method: method,
        createdAtIso: DateTime.now().toIso8601String(),
      );
      await _pendingRechargeStore.write(pending);
      if (isClosed) return;

      emit(
        state.copyWith(
          rechargeStatus: RechargeStatus.awaitingGateway,
          activeOrder: order,
          pendingRecharge: pending,
        ),
      );

      unawaited(_launchGateway(order.razorpayOrderId, amountPaise, method));
    } on ApiException catch (e) {
      // Pre-confirm failure — idempotencyKey is deliberately left set so
      // a Retry (FR-8) reuses it rather than minting a second one.
      if (isClosed) return;
      emit(state.copyWith(rechargeStatus: RechargeStatus.failed, rechargeErrorMessage: e.message));
    } catch (_) {
      if (isClosed) return;
      emit(state.copyWith(rechargeStatus: RechargeStatus.failed));
    }
  }

  Future<void> _launchGateway(String razorpayOrderId, int amountPaise, PaymentMethod method) async {
    final result = await _razorpayCheckout.open(
      RazorpayOptions(razorpayOrderId: razorpayOrderId, amountPaise: amountPaise, method: method),
    );
    if (isClosed) return;
    switch (result) {
      case RazorpaySuccess(:final razorpayPaymentId, :final razorpayOrderId, :final razorpaySignature):
        add(
          RechargeGatewaySucceeded(
            razorpayPaymentId: razorpayPaymentId,
            razorpayOrderId: razorpayOrderId,
            razorpaySignature: razorpaySignature,
          ),
        );
      case RazorpayFailure(:final code, :final description):
        add(RechargeGatewayFailed(code: code, description: description));
      case RazorpayDismissed():
        add(const RechargeGatewayDismissed());
    }
  }

  Future<void> _onRechargeGatewaySucceeded(
    RechargeGatewaySucceeded event,
    Emitter<WalletState> emit,
  ) async {
    final pending = state.pendingRecharge;
    if (pending == null) return;

    emit(state.copyWith(rechargeStatus: RechargeStatus.confirming));

    try {
      await _walletRepository.confirmRecharge(
        paymentId: pending.paymentId,
        razorpayPaymentId: event.razorpayPaymentId,
        razorpayOrderId: event.razorpayOrderId,
        razorpaySignature: event.razorpaySignature,
      );
    } on ApiException catch (_) {
      // Whether or not the confirm call itself succeeded, the payment
      // resource is the sole source of truth (round-2 finding #10) — a
      // lost response here must not be reported as a failed recharge
      // while money may already be moving server-side. Fall through to
      // polling and let getPayment() decide.
    } catch (_) {
      // Same rationale as above.
    }

    if (isClosed) return;
    emit(state.copyWith(rechargeStatus: RechargeStatus.pending));
    _startPollSession();
    add(const RechargePollTick());
  }

  /// No confirm call was ever made, so nothing was charged — the
  /// persisted record is dropped (nothing to resume), but
  /// [WalletState.idempotencyKey] is deliberately left set so a Retry
  /// reuses it: `createRecharge` becomes an idempotent replay on the
  /// same key (MA-126 FR-1) rather than a second, separately-chargeable
  /// order.
  Future<void> _onRechargeGatewayFailed(
    RechargeGatewayFailed event,
    Emitter<WalletState> emit,
  ) async {
    await _pendingRechargeStore.clear();
    if (isClosed) return;
    emit(
      state.copyWith(
        rechargeStatus: RechargeStatus.failed,
        rechargeErrorMessage: event.description,
        clearActiveOrder: true,
        clearPendingRecharge: true,
      ),
    );
  }

  Future<void> _onRechargeGatewayDismissed(
    RechargeGatewayDismissed event,
    Emitter<WalletState> emit,
  ) async {
    await _pendingRechargeStore.clear();
    if (isClosed) return;
    emit(
      state.copyWith(
        rechargeStatus: RechargeStatus.idle,
        clearActiveOrder: true,
        clearPendingRecharge: true,
      ),
    );
  }

  Future<void> _onRechargePollTick(RechargePollTick event, Emitter<WalletState> emit) async {
    final pending = state.pendingRecharge;
    if (pending == null || isClosed) return;

    PaymentView? payment;
    try {
      payment = await _walletRepository.getPayment(pending.paymentId);
    } catch (_) {
      // Transient network hiccup — fall through to the still-pending
      // branch below rather than reporting a failure that isn't one.
    }

    if (isClosed || state.pendingRecharge != pending) return;

    switch (payment?.status) {
      case PaymentStatus.confirmed:
        await _pendingRechargeStore.clear();
        // FR-7: the method that actually completed this recharge becomes
        // the new "last used" default — not written eagerly on every
        // PaymentMethodSelected-free default, only on a real success.
        await _paymentMethodStore.write(pending.method.wireValue);
        if (isClosed) return;
        emit(
          state.copyWith(
            rechargeStatus: RechargeStatus.success,
            clearActiveOrder: true,
            clearPendingRecharge: true,
            clearSelectedAmountPaise: true,
            clearIdempotencyKey: true,
            lastConfirmedAmountPaise: pending.amountPaise,
          ),
        );
        add(const WalletRefreshRequested());
      case PaymentStatus.failed:
        // Terminal, server-authoritative — unlike a pre-confirm failure,
        // this clears idempotencyKey too: no Retry is offered for it
        // (FR-8), a fresh attempt needs a fresh key.
        await _pendingRechargeStore.clear();
        if (isClosed) return;
        emit(
          state.copyWith(
            rechargeStatus: RechargeStatus.failed,
            rechargeErrorMessage: payment!.failureReason ?? 'The payment could not be completed',
            clearActiveOrder: true,
            clearPendingRecharge: true,
            clearIdempotencyKey: true,
          ),
        );
      case PaymentStatus.created:
      case PaymentStatus.confirming:
      case null:
        final age = DateTime.now().difference(DateTime.parse(pending.createdAtIso));
        if (age > WalletState.staleAfter) {
          emit(state.copyWith(isPendingStale: true));
          return;
        }
        _pollAttemptsThisSession++;
        if (_pollAttemptsThisSession >= _maxPollAttemptsPerSession) {
          // In-session cutoff reached (FR-6): stop auto-polling, keep the
          // persisted record + pending banner for the next refresh/reopen.
          return;
        }
        await Future<void>.delayed(_pollInterval);
        if (!isClosed && state.pendingRecharge == pending) add(const RechargePollTick());
    }
  }

  Future<void> _onProvisionRetryRequested(
    WalletProvisionRetryRequested event,
    Emitter<WalletState> emit,
  ) async {
    emit(state.copyWith(provisionRetryStatus: ProvisionRetryStatus.loading));
    try {
      await _walletRepository.retryProvision();
      if (isClosed) return;
      emit(state.copyWith(provisionRetryStatus: ProvisionRetryStatus.idle));
      add(const WalletRefreshRequested());
    } on ApiException catch (_) {
      if (isClosed) return;
      emit(state.copyWith(provisionRetryStatus: ProvisionRetryStatus.failed));
    } catch (_) {
      if (isClosed) return;
      emit(state.copyWith(provisionRetryStatus: ProvisionRetryStatus.failed));
    }
  }

  Future<void> _onPendingRechargeAbandoned(
    PendingRechargeAbandoned event,
    Emitter<WalletState> emit,
  ) async {
    await _pendingRechargeStore.clear();
    if (isClosed) return;
    emit(
      state.copyWith(
        rechargeStatus: RechargeStatus.idle,
        clearActiveOrder: true,
        clearPendingRecharge: true,
        clearIdempotencyKey: true,
      ),
    );
  }

  @override
  Future<void> close() {
    _razorpayCheckout.dispose();
    return super.close();
  }
}
