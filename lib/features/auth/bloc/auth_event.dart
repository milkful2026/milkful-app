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
