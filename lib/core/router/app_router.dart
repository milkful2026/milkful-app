import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:go_router/go_router.dart';

import '../../features/auth/bloc/auth_bloc.dart';
import '../../features/auth/bloc/auth_state.dart';
import '../../features/auth/presentation/login_otp_screen.dart';
import '../../features/auth/presentation/login_screen.dart';
import '../../features/cart/presentation/cart_screen.dart';
import '../../features/cart/presentation/product_config_screen.dart';
import '../../features/catalog/models/product.dart';
import '../../features/catalog/presentation/catalog_page.dart';
import '../../features/home/presentation/home_screen.dart';
import '../../features/onboarding/presentation/address_screen.dart';
import '../../features/onboarding/presentation/otp_screen.dart';
import '../../features/onboarding/presentation/welcome_screen.dart';
import '../../features/orders/models/order_entry.dart';
import '../../features/orders/presentation/my_orders_screen.dart';
import '../../features/orders/presentation/order_detail_screen.dart';
import '../../features/orders/presentation/scheduled_delivery_screen.dart';
import '../../features/profile/presentation/profile_screen.dart';
import '../../features/subscriptions/presentation/subscriptions_screen.dart';
import '../../features/wallet/presentation/wallet_coming_soon.dart';
import '../../features/wallet/presentation/transaction_history_screen.dart';
import '../../features/wallet/presentation/wallet_screen.dart';
import '../../features/checkout/presentation/order_success_screen.dart';
import '../config/app_config.dart';

/// Route list covers both specs' screen flows:
/// Welcome → Sign Up → OTP Verify → Address → Home (MA-1) — Name, delivery
/// slot, and consent no longer have their own wizard steps: Home's own
/// inline prompt collects the name (implicitly consenting via Welcome's
/// "by continuing..." footer) and finishes registration, and delivery
/// slot selection lives in Home's own calendar picker, choosable any
/// time — and Login → Login OTP Verify (MA-21) — both landing on Home.
///
/// Redirect guard is deliberately narrow: it only governs `/`, `/home`,
/// not the registration wizard's internal steps nor `/login`.
/// AuthAuthenticated is the bloc's state for the *entire* post-verify
/// lifetime of a registering user too (they stay authenticated all the way
/// through /profile → /address → … → /success), so a blanket
/// "AuthAuthenticated → force /home" rule would incorrectly yank a
/// mid-registration user off their current wizard step. `/login` is
/// deliberately excluded from that rule for the same reason: on web, a
/// mid-registration user can land back on `/login` via the browser's back
/// button (or a deep link) — force-redirecting them to Home would abandon
/// their in-progress wizard with no way back into it, for no real benefit
/// (an already-authenticated user simply seeing the login screen again is
/// harmless). Only three things are guarded:
/// - `/` while authenticated → already signed in, go to Home (covers
///   session-bootstrap landing on `/`, and a signed-in user navigating
///   back to Welcome)
/// - `/` or `/home` while `AuthNeedsRegistration` → valid tokens but no
///   Postgres profile (session bootstrap or login both surface this, not
///   just the registration OTP-verify path — see AuthNeedsRegistration's
///   doc comment) → send back into the wizard at /address instead of
///   stranding them on a Home screen where every address-dependent screen
///   will fail closed with no explanation.
/// - `/home` while not authenticated (and not still bootstrapping) →
///   no session, back to the entry screen
/// Every other route (including /login, /otp and /login/otp, mid-verify)
/// is left alone — those screens navigate themselves via their own
/// BlocListeners.
GoRouter buildAppRouter(AuthBloc authBloc) {
  return GoRouter(
    initialLocation: '/',
    refreshListenable: GoRouterRefreshStream(authBloc.stream),
    redirect: (context, state) {
      final authState = authBloc.state;
      final path = state.matchedLocation;

      if (authState is AuthAuthenticated && path == '/') {
        return '/home';
      }
      if (authState is AuthNeedsRegistration && (path == '/' || path == '/home')) {
        return '/address';
      }
      if (path == '/home' && authState is! AuthAuthenticated && authState is! AuthBootstrapping) {
        return '/';
      }
      return null;
    },
    routes: [
      GoRoute(path: '/', builder: (context, state) => const WelcomeScreen()),
      // LoginScreen's "Sign up" link still targets /signup — kept as a
      // second route to the same merged Welcome+Signup screen (see
      // welcome_screen.dart's own doc comment) rather than touching
      // login_screen.dart/login_screen_test.dart.
      GoRoute(path: '/signup', builder: (context, state) => const WelcomeScreen()),
      GoRoute(path: '/otp', builder: (context, state) => const OtpScreen()),
      GoRoute(path: '/address', builder: (context, state) => const AddressScreen()),
      GoRoute(path: '/login', builder: (context, state) => const LoginScreen()),
      GoRoute(path: '/login/otp', builder: (context, state) => const LoginOtpScreen()),
      GoRoute(path: '/home', builder: (context, state) => const HomeScreen()),
      // Reached from Home's landing page — "View All" on Categories, tapping
      // a category icon, or the search bar — never a first-load destination
      // of its own, so it's pushed (not routed to directly) rather than
      // wired into the auth redirect guard above.
      GoRoute(path: '/catalog', builder: (context, state) => const CatalogPage()),
      // MA-123. Reached from Home's cart FAB — no `extra:` payload, since
      // the screen always fetches its own state fresh from Cart Service
      // rather than trusting anything passed in.
      GoRoute(path: '/cart', builder: (context, state) => const CartScreen()),
      // MA-23/MA-120 §6. The tapped `Product` is passed via `extra:` (the
      // catalog card already holds it, avoiding a redundant fetch) — this
      // is the first route in this app to actually consume `state.extra`
      // (no existing builder does; see the PR #7 review's correction of
      // the original spec's routing citation), so it's null-checked rather
      // than assumed present: a deep link or a restored route with no
      // `Product` attached falls back to Home instead of crashing.
      GoRoute(
        path: '/product/:productId',
        builder: (context, state) {
          final product = state.extra;
          if (product is! Product) return const HomeScreen();
          return ProductConfigScreen(product: product);
        },
      ),
      // MA-125 FR-1. A top-level `go` destination off the bottom nav, like
      // `/home` — dark-shipped behind `WALLET_ENABLED` until MA-126/MA-127
      // are reachable from this build.
      GoRoute(
        path: '/wallet',
        builder: (context, state) =>
            AppConfig.walletEnabled ? const WalletScreen() : const WalletComingSoon(),
      ),
      // MA-149. Reached from the Wallet screen's Passbook button and "View All
      // Transactions" link, and Profile's Transactions row; behind the same
      // `WALLET_ENABLED` gate as `/wallet`.
      GoRoute(
        path: '/wallet/transactions',
        builder: (context, state) =>
            AppConfig.walletEnabled ? const TransactionHistoryScreen() : const WalletComingSoon(),
      ),
      // MA-133 FR-1. A top-level `go` destination off the bottom nav, like
      // `/wallet` — no feature flag (unlike `/wallet`'s `walletEnabled`),
      // ships live once merged per MA-133 §4 FR-1's own decision.
      GoRoute(path: '/subscriptions', builder: (context, state) => const SubscriptionsScreen()),
      // MA-147. The Profile tab's destination (was a stub on every bar).
      GoRoute(path: '/profile', builder: (context, state) => const ProfileScreen()),
      // MA-137 FR-10. Reached with `go` from Review Cart once a checkout
      // completes; a deep link or restored route has no `extra` to show,
      // so it falls back to Home rather than crashing.
      GoRoute(
        path: '/order-success',
        builder: (context, state) {
          final args = state.extra;
          if (args is! OrderSuccessArgs) return const HomeScreen();
          return OrderSuccessScreen(args: args);
        },
      ),
      // MA-145. Pushed from Profile's My Orders row (MA-147).
      GoRoute(path: '/orders', builder: (context, state) => const MyOrdersScreen()),
      // MA-146. Declared before `/orders/:orderId` so "scheduled" is never
      // read as an order id. `extra` is the list's ScheduledEntry; a deep
      // link or restart has none, and the screen fetches by id instead.
      GoRoute(
        path: '/orders/scheduled/:subscriptionId',
        builder: (context, state) => ScheduledDeliveryScreen(
          subscriptionId: state.pathParameters['subscriptionId']!,
          entry: state.extra is ScheduledEntry ? state.extra as ScheduledEntry : null,
        ),
      ),
      GoRoute(
        path: '/orders/:orderId',
        builder: (context, state) =>
            OrderDetailScreen(orderId: state.pathParameters['orderId']!),
      ),
    ],
  );
}

/// go_router's own docs show this exact pattern for driving
/// `refreshListenable` from a Stream (here, AuthBloc's state stream) — not
/// a class the package exports itself, so it's hand-rolled here.
class GoRouterRefreshStream extends ChangeNotifier {
  GoRouterRefreshStream(Stream<dynamic> stream) {
    notifyListeners();
    _subscription = stream.asBroadcastStream().listen((_) => notifyListeners());
  }

  late final StreamSubscription<dynamic> _subscription;

  @override
  void dispose() {
    _subscription.cancel();
    super.dispose();
  }
}
