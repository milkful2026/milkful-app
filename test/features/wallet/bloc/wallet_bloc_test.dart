import 'package:bloc_test/bloc_test.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:milkful_app/core/network/api_client.dart';
import 'package:milkful_app/features/wallet/bloc/wallet_bloc.dart';
import 'package:milkful_app/features/wallet/bloc/wallet_event.dart';
import 'package:milkful_app/features/wallet/bloc/wallet_state.dart';
import 'package:milkful_app/features/wallet/data/razorpay_checkout.dart';
import 'package:milkful_app/features/wallet/models/payment_method.dart';
import 'package:milkful_app/features/wallet/models/payment_status.dart';
import 'package:milkful_app/features/wallet/models/payment_view.dart';
import 'package:milkful_app/features/wallet/models/pending_recharge.dart';
import 'package:milkful_app/features/wallet/models/recharge_order.dart';
import 'package:milkful_app/features/wallet/models/wallet_status.dart';
import 'package:milkful_app/features/wallet/models/wallet_view.dart';

import '../../../fakes/fake_pending_recharge_store.dart';
import '../../../fakes/fake_razorpay_checkout.dart';
import '../../../fakes/fake_wallet_repository.dart';

const _wallet = WalletView(
  walletId: 'wallet-1',
  status: WalletStatus.active,
  balancePaise: 10000,
  currency: 'INR',
  rechargeMinPaise: 10000,
  rechargeMaxPaise: 5000000,
);

const _order = RechargeOrder(
  paymentId: 'pay-1',
  razorpayOrderId: 'order_1',
  razorpayKeyId: 'rzp_test_1',
  amountPaise: 50000,
  currency: 'INR',
);

void main() {
  group('WalletBloc', () {
    late FakeWalletRepository walletRepository;
    late FakeRazorpayCheckout razorpayCheckout;
    late FakePendingRechargeStore pendingRechargeStore;
    late FakePaymentMethodStore paymentMethodStore;

    setUp(() {
      walletRepository = FakeWalletRepository(getWalletResult: _wallet);
      razorpayCheckout = FakeRazorpayCheckout();
      pendingRechargeStore = FakePendingRechargeStore();
      paymentMethodStore = FakePaymentMethodStore();
    });

    WalletBloc build() => WalletBloc(
      walletRepository: walletRepository,
      razorpayCheckout: razorpayCheckout,
      pendingRechargeStore: pendingRechargeStore,
      paymentMethodStore: paymentMethodStore,
      pollInterval: const Duration(milliseconds: 5),
    );

    blocTest<WalletBloc, WalletState>(
      'WalletStarted loads the wallet',
      build: build,
      act: (bloc) => bloc.add(const WalletStarted()),
      expect: () => [
        predicate<WalletState>((s) => s.walletLoadStatus == WalletLoadStatus.loading),
        predicate<WalletState>(
          (s) => s.walletLoadStatus == WalletLoadStatus.loaded && s.wallet == _wallet,
        ),
      ],
    );

    blocTest<WalletBloc, WalletState>(
      'WalletStarted surfaces a load failure',
      setUp: () {
        walletRepository.getWalletResult = null;
        walletRepository.getWalletException = const ApiException(
          errorCode: 'NETWORK_ERROR',
          message: 'Could not reach the server',
        );
      },
      build: build,
      act: (bloc) => bloc.add(const WalletStarted()),
      expect: () => [
        predicate<WalletState>((s) => s.walletLoadStatus == WalletLoadStatus.loading),
        predicate<WalletState>(
          (s) =>
              s.walletLoadStatus == WalletLoadStatus.failed &&
              s.walletErrorMessage == 'Could not reach the server',
        ),
      ],
    );

    blocTest<WalletBloc, WalletState>(
      'a fresh pending recharge resumes polling and reports on WalletStarted',
      setUp: () {
        pendingRechargeStore.value = PendingRecharge(
          idempotencyKey: 'idem-1',
          paymentId: 'pay-1',
          amountPaise: 50000,
          method: PaymentMethod.upi,
          createdAtIso: DateTime.now().toIso8601String(),
        );
        walletRepository.getPaymentResult = const PaymentView(
          paymentId: 'pay-1',
          status: PaymentStatus.confirming,
          amountPaise: 50000,
        );
      },
      build: build,
      act: (bloc) => bloc.add(const WalletStarted()),
      wait: const Duration(milliseconds: 20),
      verify: (bloc) {
        expect(bloc.state.rechargeStatus, RechargeStatus.pending);
        expect(bloc.state.isPendingStale, isFalse);
        expect(walletRepository.getPaymentCallCount, greaterThan(0));
      },
    );

    blocTest<WalletBloc, WalletState>(
      'a stale pending recharge is still checked once, then flagged rather than auto-polled',
      setUp: () {
        pendingRechargeStore.value = PendingRecharge(
          idempotencyKey: 'idem-1',
          paymentId: 'pay-1',
          amountPaise: 50000,
          method: PaymentMethod.upi,
          createdAtIso: DateTime.now().subtract(const Duration(hours: 1)).toIso8601String(),
        );
        walletRepository.getPaymentResult = const PaymentView(
          paymentId: 'pay-1',
          status: PaymentStatus.confirming,
          amountPaise: 50000,
        );
      },
      build: build,
      act: (bloc) => bloc.add(const WalletStarted()),
      wait: const Duration(milliseconds: 20),
      verify: (bloc) {
        expect(bloc.state.rechargeStatus, RechargeStatus.pending);
        expect(bloc.state.isPendingStale, isTrue);
        // Checked once on resume (FR-6a resolves the status before
        // deciding staleness) — then it stops, no continuous auto-poll.
        expect(walletRepository.getPaymentCallCount, 1);
      },
    );

    blocTest<WalletBloc, WalletState>(
      'PendingRechargeAbandoned clears the persisted record and resets state',
      seed: () => WalletState(
        wallet: _wallet,
        walletLoadStatus: WalletLoadStatus.loaded,
        rechargeStatus: RechargeStatus.pending,
        isPendingStale: true,
        pendingRecharge: PendingRecharge(
          idempotencyKey: 'idem-1',
          paymentId: 'pay-1',
          amountPaise: 50000,
          method: PaymentMethod.upi,
          createdAtIso: DateTime.now().toIso8601String(),
        ),
      ),
      build: build,
      act: (bloc) => bloc.add(const PendingRechargeAbandoned()),
      expect: () => [
        predicate<WalletState>(
          (s) =>
              s.pendingRecharge == null &&
              s.isPendingStale == false &&
              s.rechargeStatus == RechargeStatus.idle,
        ),
      ],
      verify: (_) => expect(pendingRechargeStore.clearCallCount, 1),
    );

    blocTest<WalletBloc, WalletState>(
      'full happy path: create order -> gateway success -> confirm -> poll -> success',
      setUp: () {
        walletRepository.createRechargeResult = _order;
        razorpayCheckout.result = const RazorpaySuccess(
          razorpayPaymentId: 'rzp_pay_1',
          razorpayOrderId: 'order_1',
          razorpaySignature: 'sig_1',
        );
        walletRepository.getPaymentResults.addAll([
          const PaymentView(paymentId: 'pay-1', status: PaymentStatus.confirming, amountPaise: 50000),
          const PaymentView(paymentId: 'pay-1', status: PaymentStatus.confirmed, amountPaise: 50000),
        ]);
      },
      seed: () => WalletState(
        wallet: _wallet,
        walletLoadStatus: WalletLoadStatus.loaded,
        selectedAmountPaise: 50000,
        selectedMethod: PaymentMethod.upi,
      ),
      build: build,
      act: (bloc) => bloc.add(const RechargeRequested()),
      wait: const Duration(milliseconds: 50),
      verify: (bloc) {
        expect(bloc.state.rechargeStatus, RechargeStatus.success);
        expect(bloc.state.pendingRecharge, isNull);
        expect(bloc.state.selectedAmountPaise, isNull);
        expect(walletRepository.createRechargeCalls, hasLength(1));
        expect(walletRepository.createRechargeCalls.single.amountPaise, 50000);
        expect(walletRepository.confirmRechargePaymentIds, ['pay-1']);
        expect(pendingRechargeStore.clearCallCount, 1);
        // The recharge success path re-fetches the wallet (its balance
        // only ever moves via the webhook-driven credit, so this is the
        // only way the screen picks up the new number).
        expect(walletRepository.getWalletCallCount, greaterThanOrEqualTo(1));
      },
    );

    blocTest<WalletBloc, WalletState>(
      'a real payment.failed from the poll surfaces as a failure and clears the pending record',
      setUp: () {
        walletRepository.createRechargeResult = _order;
        razorpayCheckout.result = const RazorpaySuccess(
          razorpayPaymentId: 'rzp_pay_1',
          razorpayOrderId: 'order_1',
          razorpaySignature: 'sig_1',
        );
        walletRepository.getPaymentResult = const PaymentView(
          paymentId: 'pay-1',
          status: PaymentStatus.failed,
          amountPaise: 50000,
          failureReason: 'Card declined',
        );
      },
      seed: () => WalletState(
        wallet: _wallet,
        walletLoadStatus: WalletLoadStatus.loaded,
        selectedAmountPaise: 50000,
        selectedMethod: PaymentMethod.card,
      ),
      build: build,
      act: (bloc) => bloc.add(const RechargeRequested()),
      wait: const Duration(milliseconds: 30),
      verify: (bloc) {
        expect(bloc.state.rechargeStatus, RechargeStatus.failed);
        expect(bloc.state.rechargeErrorMessage, 'Card declined');
        expect(bloc.state.pendingRecharge, isNull);
        // Post-confirm, server-authoritative failure — no Retry offered;
        // a fresh attempt needs a fresh idempotency key (FR-8).
        expect(bloc.state.canRetryRecharge, isFalse);
        expect(bloc.state.idempotencyKey, isNull);
      },
    );

    blocTest<WalletBloc, WalletState>(
      'a dismissed gateway sheet is a benign cancel, not a failure',
      setUp: () {
        walletRepository.createRechargeResult = _order;
        razorpayCheckout.result = const RazorpayDismissed();
      },
      seed: () => WalletState(
        wallet: _wallet,
        walletLoadStatus: WalletLoadStatus.loaded,
        selectedAmountPaise: 50000,
        selectedMethod: PaymentMethod.card,
      ),
      build: build,
      act: (bloc) => bloc.add(const RechargeRequested()),
      wait: const Duration(milliseconds: 20),
      verify: (bloc) {
        expect(bloc.state.rechargeStatus, RechargeStatus.idle);
        expect(bloc.state.rechargeErrorMessage, isNull);
        expect(bloc.state.pendingRecharge, isNull);
        expect(pendingRechargeStore.clearCallCount, 1);
        // Never confirmed — no charge was ever made against this order.
        expect(walletRepository.confirmRechargePaymentIds, isEmpty);
      },
    );

    blocTest<WalletBloc, WalletState>(
      'a gateway error is reported and the abandoned order is not confirmed',
      setUp: () {
        walletRepository.createRechargeResult = _order;
        razorpayCheckout.result = const RazorpayFailure(code: '1', description: 'Payment failed');
      },
      seed: () => WalletState(
        wallet: _wallet,
        walletLoadStatus: WalletLoadStatus.loaded,
        selectedAmountPaise: 50000,
        selectedMethod: PaymentMethod.card,
      ),
      build: build,
      act: (bloc) => bloc.add(const RechargeRequested()),
      wait: const Duration(milliseconds: 20),
      verify: (bloc) {
        expect(bloc.state.rechargeStatus, RechargeStatus.failed);
        expect(bloc.state.rechargeErrorMessage, 'Payment failed');
        expect(bloc.state.pendingRecharge, isNull);
        expect(walletRepository.confirmRechargePaymentIds, isEmpty);
        // Pre-confirm failure — Retry is offered and must reuse this key.
        expect(bloc.state.canRetryRecharge, isTrue);
        expect(bloc.state.idempotencyKey, isNotNull);
      },
    );

    blocTest<WalletBloc, WalletState>(
      'Retry after a gateway error reuses the same idempotency key and resumes the same order',
      setUp: () {
        walletRepository.createRechargeResult = _order;
        razorpayCheckout.result = const RazorpayFailure(code: '1', description: 'Payment failed');
      },
      seed: () => WalletState(
        wallet: _wallet,
        walletLoadStatus: WalletLoadStatus.loaded,
        selectedAmountPaise: 50000,
        selectedMethod: PaymentMethod.card,
      ),
      build: build,
      act: (bloc) async {
        bloc.add(const RechargeRequested());
        await Future<void>.delayed(const Duration(milliseconds: 20));
        bloc.add(const RechargeRequested());
      },
      wait: const Duration(milliseconds: 20),
      verify: (bloc) {
        expect(walletRepository.createRechargeCalls, hasLength(2));
        final keys = walletRepository.createRechargeCalls.map((c) => c.idempotencyKey).toSet();
        expect(keys, hasLength(1), reason: 'both attempts must carry the same idempotency key');
      },
    );

    blocTest<WalletBloc, WalletState>(
      'Retry after a createRecharge API failure reuses the same idempotency key',
      setUp: () => walletRepository.createRechargeException = const ApiException(
        errorCode: 'NETWORK_ERROR',
        message: 'Could not reach the server',
      ),
      seed: () => WalletState(
        wallet: _wallet,
        walletLoadStatus: WalletLoadStatus.loaded,
        selectedAmountPaise: 50000,
        selectedMethod: PaymentMethod.card,
      ),
      build: build,
      act: (bloc) async {
        bloc.add(const RechargeRequested());
        await Future<void>.delayed(const Duration(milliseconds: 10));
        bloc.add(const RechargeRequested());
      },
      wait: const Duration(milliseconds: 10),
      verify: (bloc) {
        expect(bloc.state.canRetryRecharge, isTrue);
        expect(walletRepository.createRechargeCalls, hasLength(2));
        final keys = walletRepository.createRechargeCalls.map((c) => c.idempotencyKey).toSet();
        expect(keys, hasLength(1));
      },
    );

    blocTest<WalletBloc, WalletState>(
      'changing the amount after a pre-confirm failure discards the stale idempotency key',
      setUp: () => walletRepository.createRechargeException = const ApiException(
        errorCode: 'NETWORK_ERROR',
        message: 'Could not reach the server',
      ),
      seed: () => WalletState(
        wallet: _wallet,
        walletLoadStatus: WalletLoadStatus.loaded,
        selectedAmountPaise: 50000,
        selectedMethod: PaymentMethod.card,
      ),
      build: build,
      act: (bloc) async {
        bloc.add(const RechargeRequested());
        await Future<void>.delayed(const Duration(milliseconds: 10));
        bloc.add(const QuickAmountSelected(100000));
      },
      wait: const Duration(milliseconds: 10),
      verify: (bloc) {
        expect(bloc.state.idempotencyKey, isNull);
        expect(bloc.state.canRetryRecharge, isFalse);
        expect(bloc.state.selectedAmountPaise, 100000);
      },
    );

    blocTest<WalletBloc, WalletState>(
      'the in-session poll stops after its attempt budget, keeping the pending record',
      setUp: () {
        walletRepository.createRechargeResult = _order;
        razorpayCheckout.result = const RazorpaySuccess(
          razorpayPaymentId: 'rzp_pay_1',
          razorpayOrderId: 'order_1',
          razorpaySignature: 'sig_1',
        );
        walletRepository.getPaymentResult = const PaymentView(
          paymentId: 'pay-1',
          status: PaymentStatus.confirming,
          amountPaise: 50000,
        );
      },
      seed: () => WalletState(
        wallet: _wallet,
        walletLoadStatus: WalletLoadStatus.loaded,
        selectedAmountPaise: 50000,
        selectedMethod: PaymentMethod.card,
      ),
      build: () => WalletBloc(
        walletRepository: walletRepository,
        razorpayCheckout: razorpayCheckout,
        pendingRechargeStore: pendingRechargeStore,
        paymentMethodStore: paymentMethodStore,
        pollInterval: const Duration(milliseconds: 5),
        maxPollAttemptsPerSession: 3,
      ),
      act: (bloc) => bloc.add(const RechargeRequested()),
      wait: const Duration(milliseconds: 60),
      verify: (bloc) {
        // Exactly the 3-attempt budget, then the in-session poll stops.
        expect(walletRepository.getPaymentCallCount, 3);
        expect(bloc.state.rechargeStatus, RechargeStatus.pending);
        expect(bloc.state.pendingRecharge, isNotNull);
      },
    );

    blocTest<WalletBloc, WalletState>(
      'RechargeRequested is a no-op when the wallet is not active',
      seed: () => WalletState(
        wallet: const WalletView(
          walletId: 'wallet-1',
          status: WalletStatus.creating,
          balancePaise: 0,
          currency: 'INR',
          rechargeMinPaise: 10000,
          rechargeMaxPaise: 5000000,
        ),
        walletLoadStatus: WalletLoadStatus.loaded,
        selectedAmountPaise: 50000,
      ),
      build: build,
      act: (bloc) => bloc.add(const RechargeRequested()),
      expect: () => [],
      verify: (_) => expect(walletRepository.createRechargeCalls, isEmpty),
    );

    blocTest<WalletBloc, WalletState>(
      'a second RechargeRequested is dropped while one is already in flight',
      setUp: () => walletRepository.createRechargeResult = _order,
      seed: () => WalletState(
        wallet: _wallet,
        walletLoadStatus: WalletLoadStatus.loaded,
        selectedAmountPaise: 50000,
      ),
      build: build,
      act: (bloc) {
        bloc.add(const RechargeRequested());
        bloc.add(const RechargeRequested());
      },
      wait: const Duration(milliseconds: 20),
      verify: (_) => expect(walletRepository.createRechargeCalls, hasLength(1)),
    );

    blocTest<WalletBloc, WalletState>(
      'PaymentMethodSelected persists the choice',
      build: build,
      act: (bloc) => bloc.add(const PaymentMethodSelected(PaymentMethod.upi)),
      verify: (bloc) {
        expect(bloc.state.selectedMethod, PaymentMethod.upi);
        expect(paymentMethodStore.value, 'UPI');
      },
    );

    blocTest<WalletBloc, WalletState>(
      'WalletProvisionRetryRequested refreshes the wallet on success',
      build: build,
      act: (bloc) => bloc.add(const WalletProvisionRetryRequested()),
      wait: const Duration(milliseconds: 10),
      verify: (bloc) {
        expect(bloc.state.provisionRetryStatus, ProvisionRetryStatus.idle);
        expect(walletRepository.retryProvisionCallCount, 1);
        expect(walletRepository.getWalletCallCount, 1);
      },
    );

    blocTest<WalletBloc, WalletState>(
      'WalletProvisionRetryRequested surfaces a failure',
      setUp: () => walletRepository.retryProvisionException = const ApiException(
        errorCode: 'PROVISION_FAILED',
        message: 'Could not set up your wallet',
      ),
      build: build,
      act: (bloc) => bloc.add(const WalletProvisionRetryRequested()),
      expect: () => [
        predicate<WalletState>((s) => s.provisionRetryStatus == ProvisionRetryStatus.loading),
        predicate<WalletState>((s) => s.provisionRetryStatus == ProvisionRetryStatus.failed),
      ],
    );
  });
}
