import 'package:equatable/equatable.dart';

sealed class AuthEvent extends Equatable {
  const AuthEvent();

  @override
  List<Object?> get props => [];
}

/// FR-1: user taps "Send OTP" on /signup.
class OtpSendRequested extends AuthEvent {
  const OtpSendRequested(this.mobile);

  final String mobile;

  @override
  List<Object?> get props => [mobile];
}

/// FR-1: resend after the countdown expires — same call, distinct event so
/// the bloc/UI can tell a fresh send apart from a resend if needed later.
class OtpResendRequested extends AuthEvent {
  const OtpResendRequested(this.mobile);

  final String mobile;

  @override
  List<Object?> get props => [mobile];
}

/// FR-2: 6th digit entered / Verify tapped.
class OtpVerifyRequested extends AuthEvent {
  const OtpVerifyRequested(this.otp);

  final String otp;

  @override
  List<Object?> get props => [otp];
}

/// Returning to /signup (e.g. from an error state) resets to a clean slate.
class AuthReset extends AuthEvent {
  const AuthReset();
}

/// MA-21 FR-1: standalone /login entry, or the signup screen's "Log in"
/// tap (which already knows the mobile — see login_otp_send_handler.py's
/// USER_EXISTS/USER_NOT_FOUND gate being the inverse of registration's).
class LoginOtpSendRequested extends AuthEvent {
  const LoginOtpSendRequested(this.mobile);

  final String mobile;

  @override
  List<Object?> get props => [mobile];
}

class LoginOtpResendRequested extends AuthEvent {
  const LoginOtpResendRequested(this.mobile);

  final String mobile;

  @override
  List<Object?> get props => [mobile];
}

/// MA-21 FR-2.
class LoginOtpVerifyRequested extends AuthEvent {
  const LoginOtpVerifyRequested(this.otp);

  final String otp;

  @override
  List<Object?> get props => [otp];
}

/// MA-21 FR-3: dispatched once at app start (see main.dart) — checks for a
/// stored session, silently refreshes an expired access token, and
/// resolves accountType via GET /users/me before the router decides
/// between landing on Home or the entry screen.
class SessionBootstrapRequested extends AuthEvent {
  const SessionBootstrapRequested();
}

/// MA-21 FR-5.
class LogoutRequested extends AuthEvent {
  const LogoutRequested();
}

/// Re-fetches GET /users/me and updates the current AuthAuthenticated
/// state's `name`/`accountType` — dispatched once registration finishes
/// (the earlier OTP-verify-during-signup path deliberately skips the
/// profile lookup, since the profile doesn't exist yet at that point), so
/// Home's "Welcome, {name}" greeting has a real name to show without a
/// second, separate profile-fetch mechanism living outside AuthBloc.
class ProfileRefreshRequested extends AuthEvent {
  const ProfileRefreshRequested();
}
