import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:milkful_app/core/network/api_client.dart';
import 'package:milkful_app/features/onboarding/bloc/registration_bloc.dart';
import 'package:milkful_app/features/wallet/data/pending_recharge_store.dart';
import 'package:milkful_app/features/wallet/data/razorpay_checkout.dart';
import 'package:milkful_app/features/wallet/data/wallet_repository.dart';
import 'package:milkful_app/features/wallet/models/payment_status.dart';
import 'package:milkful_app/features/wallet/models/payment_view.dart';
import 'package:milkful_app/features/wallet/models/recharge_order.dart';
import 'package:milkful_app/features/wallet/models/wallet_status.dart';
import 'package:milkful_app/features/wallet/models/wallet_view.dart';
import 'package:milkful_app/features/wallet/presentation/wallet_screen.dart';

import '../../../fakes/fake_draft_storage.dart';
import '../../../fakes/fake_pending_recharge_store.dart';
import '../../../fakes/fake_razorpay_checkout.dart';
import '../../../fakes/fake_registration_repository.dart';
import '../../../fakes/fake_wallet_repository.dart';

const _wallet = WalletView(
  walletId: 'wallet-1',
  status: WalletStatus.active,
  balancePaise: 45000,
  currency: 'INR',
  rechargeMinPaise: 10000,
  rechargeMaxPaise: 10000000,
);

const _order = RechargeOrder(
  paymentId: 'pay-1',
  razorpayOrderId: 'order_1',
  razorpayKeyId: 'rzp_test_1',
  amountPaise: 50000,
  currency: 'INR',
);

void main() {
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

  Future<void> pumpWallet(WidgetTester tester) async {
    final router = GoRouter(
      initialLocation: '/wallet',
      routes: [
        GoRoute(path: '/wallet', builder: (context, state) => const WalletScreen()),
        GoRoute(path: '/wallet/transactions', builder: (context, state) => const Placeholder()),
        GoRoute(path: '/home', builder: (context, state) => const Placeholder()),
      ],
    );
    await tester.pumpWidget(
      MultiRepositoryProvider(
        providers: [
          RepositoryProvider<WalletRepository>.value(value: walletRepository),
          RepositoryProvider<RazorpayCheckout>.value(value: razorpayCheckout),
          RepositoryProvider<PendingRechargeStore>.value(value: pendingRechargeStore),
          RepositoryProvider<PaymentMethodStore>.value(value: paymentMethodStore),
        ],
        child: BlocProvider(
          create: (_) => RegistrationBloc(
            repository: FakeRegistrationRepository(),
            draftStorage: FakeDraftStorage(),
          ),
          child: MaterialApp.router(routerConfig: router),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('Wallet screen renders the mocked layout', (tester) async {
    await pumpWallet(tester);

    expect(find.byKey(const Key('wallet-balance-amount')), findsOneWidget);
    expect(find.text('₹450.00'), findsOneWidget);
    expect(find.byKey(const Key('wallet-quick-topup-500')), findsOneWidget);
    expect(find.byKey(const Key('wallet-quick-topup-1000')), findsOneWidget);
    expect(find.byKey(const Key('wallet-quick-topup-2000')), findsOneWidget);
    expect(find.byKey(const Key('wallet-method-upi')), findsOneWidget);
    expect(find.byKey(const Key('wallet-method-card')), findsOneWidget);

    final proceedButton = tester.widget<FilledButton>(
      find.byKey(const Key('wallet-proceed-to-payment')),
    );
    expect(proceedButton.onPressed, isNull);
  });

  testWidgets('Choosing a quick amount enables the CTA', (tester) async {
    await pumpWallet(tester);

    await tester.tap(find.byKey(const Key('wallet-quick-topup-1000')));
    await tester.pumpAndSettle();

    final proceedButton = tester.widget<FilledButton>(
      find.byKey(const Key('wallet-proceed-to-payment')),
    );
    expect(proceedButton.onPressed, isNotNull);
    expect(find.textContaining('1,000'), findsOneWidget);
  });

  testWidgets('Custom amount below minimum is rejected', (tester) async {
    await pumpWallet(tester);

    await tester.tap(find.byKey(const Key('wallet-topup-button')));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('wallet-topup-amount-field')), '50');
    await tester.tap(find.text('Continue'));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('wallet-topup-amount-error')), findsOneWidget);
    expect(find.text('Minimum top-up is ₹100.00'), findsOneWidget);
    expect(find.byKey(const Key('wallet-topup-sheet')), findsOneWidget);
  });

  testWidgets('Successful recharge credits and shows confirmation', (tester) async {
    walletRepository.createRechargeResult = _order;
    razorpayCheckout.result = const RazorpaySuccess(
      razorpayPaymentId: 'rzp_pay_1',
      razorpayOrderId: 'order_1',
      razorpaySignature: 'sig_1',
    );
    // Resolved on the very first poll tick — no delay needed in the test.
    walletRepository.getPaymentResult = const PaymentView(
      paymentId: 'pay-1',
      status: PaymentStatus.confirmed,
      amountPaise: 50000,
    );

    await pumpWallet(tester);
    await tester.tap(find.byKey(const Key('wallet-quick-topup-500')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('wallet-proceed-to-payment')));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('wallet-recharge-success')), findsOneWidget);
    expect(paymentMethodStore.value, 'CARD');
    expect(pendingRechargeStore.value, isNull);
  });

  testWidgets(
    'Gateway failure is surfaced and retry reuses the idempotency key',
    (tester) async {
      walletRepository.createRechargeResult = _order;
      razorpayCheckout.result = const RazorpayFailure(code: '2', description: 'Bank declined');

      await pumpWallet(tester);
      await tester.tap(find.byKey(const Key('wallet-quick-topup-500')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('wallet-proceed-to-payment')));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('wallet-recharge-error')), findsOneWidget);
      expect(find.text('Bank declined'), findsOneWidget);

      await tester.tap(find.byKey(const Key('wallet-recharge-retry')));
      await tester.pumpAndSettle();

      expect(walletRepository.createRechargeCalls, hasLength(2));
      final keys = walletRepository.createRechargeCalls.map((c) => c.idempotencyKey).toSet();
      expect(keys, hasLength(1));
    },
  );

  testWidgets('Wallet not yet provisioned disables the CTA', (tester) async {
    walletRepository.getWalletResult = const WalletView(
      walletId: 'wallet-1',
      status: WalletStatus.creating,
      balancePaise: 0,
      currency: 'INR',
      rechargeMinPaise: 10000,
      rechargeMaxPaise: 10000000,
    );

    await pumpWallet(tester);

    expect(find.byKey(const Key('wallet-not-provisioned')), findsOneWidget);
    expect(find.text('Wallet setup in progress'), findsOneWidget);
    final proceedButton = tester.widget<FilledButton>(
      find.byKey(const Key('wallet-proceed-to-payment')),
    );
    expect(proceedButton.onPressed, isNull);
  });

  testWidgets(
    'Quick Top Up chips outside the wallet\'s current recharge bounds are not shown',
    (tester) async {
      // Excludes ₹500 (below min) and ₹2000 (above max) — only ₹1000 is
      // within bounds; a hidden/disabled-without-explanation chip must
      // never be tappable (MA-125 §6, rechargeMinPaise/rechargeMaxPaise
      // are server-configured, not hard-coded).
      walletRepository.getWalletResult = const WalletView(
        walletId: 'wallet-1',
        status: WalletStatus.active,
        balancePaise: 45000,
        currency: 'INR',
        rechargeMinPaise: 60000,
        rechargeMaxPaise: 150000,
      );

      await pumpWallet(tester);

      expect(find.byKey(const Key('wallet-quick-topup-500')), findsNothing);
      expect(find.byKey(const Key('wallet-quick-topup-1000')), findsOneWidget);
      expect(find.byKey(const Key('wallet-quick-topup-2000')), findsNothing);
    },
  );

  testWidgets('A load failure shows the retry state, never a fake ₹0', (tester) async {
    walletRepository.getWalletResult = null;
    walletRepository.getWalletException = const ApiException(
      errorCode: 'NETWORK_ERROR',
      message: 'Could not reach the server',
    );

    await pumpWallet(tester);

    expect(find.byKey(const Key('wallet-load-error')), findsOneWidget);
    expect(find.byKey(const Key('wallet-load-retry')), findsOneWidget);
    expect(find.byKey(const Key('wallet-balance-amount')), findsNothing);
  });
}
