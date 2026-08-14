import 'package:go_router/go_router.dart';

import '../../features/home/presentation/home_screen.dart';
import '../../features/onboarding/presentation/address_screen.dart';
import '../../features/onboarding/presentation/consent_screen.dart';
import '../../features/onboarding/presentation/otp_screen.dart';
import '../../features/onboarding/presentation/profile_screen.dart';
import '../../features/onboarding/presentation/signup_screen.dart';
import '../../features/onboarding/presentation/slot_screen.dart';
import '../../features/onboarding/presentation/success_screen.dart';
import '../../features/onboarding/presentation/welcome_screen.dart';

/// Route list matches the spec's screen flow exactly:
/// Welcome → Sign Up → OTP Verify → Name → Address → Slot → Consent →
/// Success → Home. No auth-state redirect guards yet — those matter once
/// MA-21 adds session persistence/silent refresh; this PR's flow is a
/// single linear pass with no "already signed in" case to guard against.
final appRouter = GoRouter(
  initialLocation: '/',
  routes: [
    GoRoute(path: '/', builder: (context, state) => const WelcomeScreen()),
    GoRoute(path: '/signup', builder: (context, state) => const SignupScreen()),
    GoRoute(path: '/otp', builder: (context, state) => const OtpScreen()),
    GoRoute(path: '/profile', builder: (context, state) => const ProfileScreen()),
    GoRoute(path: '/address', builder: (context, state) => const AddressScreen()),
    GoRoute(path: '/slot', builder: (context, state) => const SlotScreen()),
    GoRoute(path: '/consent', builder: (context, state) => const ConsentScreen()),
    GoRoute(path: '/success', builder: (context, state) => const SuccessScreen()),
    GoRoute(path: '/home', builder: (context, state) => const HomeScreen()),
  ],
);
