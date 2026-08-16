import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:go_router/go_router.dart';

import '../../features/auth/bloc/auth_bloc.dart';
import '../../features/auth/bloc/auth_state.dart';
import '../../features/auth/presentation/login_otp_screen.dart';
import '../../features/auth/presentation/login_screen.dart';
import '../../features/home/presentation/home_screen.dart';
import '../../features/onboarding/presentation/address_screen.dart';
import '../../features/onboarding/presentation/consent_screen.dart';
import '../../features/onboarding/presentation/otp_screen.dart';
import '../../features/onboarding/presentation/profile_screen.dart';
import '../../features/onboarding/presentation/slot_screen.dart';
import '../../features/onboarding/presentation/success_screen.dart';
import '../../features/onboarding/presentation/welcome_screen.dart';

/// Route list covers both specs' screen flows:
/// Welcome → Sign Up → OTP Verify → Name → Address → Slot → Consent →
/// Success (MA-1), and Login → Login OTP Verify (MA-21) — both landing on
/// Home.
///
/// Redirect guard is deliberately narrow: it only governs `/` and `/home`,
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
/// harmless). Only two things are guarded:
/// - `/` while authenticated → already signed in, go to Home (covers
///   session-bootstrap landing on `/`, and a signed-in user navigating
///   back to Welcome)
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
      GoRoute(path: '/profile', builder: (context, state) => const ProfileScreen()),
      GoRoute(path: '/address', builder: (context, state) => const AddressScreen()),
      GoRoute(path: '/slot', builder: (context, state) => const SlotScreen()),
      GoRoute(path: '/consent', builder: (context, state) => const ConsentScreen()),
      GoRoute(path: '/success', builder: (context, state) => const SuccessScreen()),
      GoRoute(path: '/login', builder: (context, state) => const LoginScreen()),
      GoRoute(path: '/login/otp', builder: (context, state) => const LoginOtpScreen()),
      GoRoute(path: '/home', builder: (context, state) => const HomeScreen()),
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
