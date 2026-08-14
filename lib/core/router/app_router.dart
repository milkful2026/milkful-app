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
import '../../features/onboarding/presentation/signup_screen.dart';
import '../../features/onboarding/presentation/slot_screen.dart';
import '../../features/onboarding/presentation/success_screen.dart';
import '../../features/onboarding/presentation/welcome_screen.dart';

const _entryPoints = {'/', '/login'};

/// Route list covers both specs' screen flows:
/// Welcome → Sign Up → OTP Verify → Name → Address → Slot → Consent →
/// Success (MA-1), and Login → Login OTP Verify (MA-21) — both landing on
/// Home.
///
/// Redirect guard is deliberately narrow: it only governs the three
/// boundary routes (`/`, `/login`, `/home`), not the registration
/// wizard's internal steps. AuthAuthenticated is the bloc's state for the
/// *entire* post-verify lifetime of a registering user too (they stay
/// authenticated all the way through /profile → /address → … → /success),
/// so a blanket "AuthAuthenticated → force /home" rule would incorrectly
/// yank a mid-registration user off their current wizard step. Only the
/// entry points and Home itself need guarding:
/// - `/` or `/login` while authenticated → already signed in, go to Home
///   (covers session-bootstrap landing on `/`, and a signed-in user
///   navigating back to either entry point)
/// - `/home` while not authenticated (and not still bootstrapping) →
///   no session, back to the entry screen
/// Every other route (including /otp and /login/otp, mid-verify) is left
/// alone — those screens navigate themselves via their own BlocListeners.
GoRouter buildAppRouter(AuthBloc authBloc) {
  return GoRouter(
    initialLocation: '/',
    refreshListenable: GoRouterRefreshStream(authBloc.stream),
    redirect: (context, state) {
      final authState = authBloc.state;
      final path = state.matchedLocation;

      if (authState is AuthAuthenticated && _entryPoints.contains(path)) {
        return '/home';
      }
      if (path == '/home' && authState is! AuthAuthenticated && authState is! AuthBootstrapping) {
        return '/';
      }
      return null;
    },
    routes: [
      GoRoute(path: '/', builder: (context, state) => const WelcomeScreen()),
      GoRoute(path: '/signup', builder: (context, state) => const SignupScreen()),
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
