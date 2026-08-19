import 'package:equatable/equatable.dart';

/// Which OTP flow a send/sent/failure state belongs to — registration's
/// `OtpSendRequested` or the login screen's/signup's-"Log in"-link's
/// `LoginOtpSendRequested`. Both dispatch onto the same AuthBloc and land
/// in the same AuthOtpSending/AuthOtpSent/AuthOtpSendFailure state types,
/// so without this a listener has no way to tell which flow a given state
/// belongs to other than re-deriving it from local UI flags.
enum OtpFlow { registration, login }

sealed class AuthState extends Equatable {
  const AuthState();

  @override
  List<Object?> get props => [];
}

class AuthInitial extends AuthState {
  const AuthInitial();
}

/// MA-21 FR-3: shown briefly at app start while a stored session is being
/// checked/silently refreshed — the router treats this as "not yet
/// decided" rather than redirecting to the entry screen, avoiding a flash
/// of Welcome before the check resolves.
class AuthBootstrapping extends AuthState {
  const AuthBootstrapping();
}

class AuthOtpSending extends AuthState {
  const AuthOtpSending(this.mobile, {required this.flow});

  final String mobile;
  final OtpFlow flow;

  @override
  List<Object?> get props => [mobile, flow];
}

class AuthOtpSent extends AuthState {
  const AuthOtpSent({
    required this.mobile,
    required this.requestId,
    required this.expiresIn,
    required this.resendAfter,
    required this.flow,
  });

  final String mobile;
  final String requestId;
  final int expiresIn;
  final int resendAfter;
  final OtpFlow flow;

  @override
  List<Object?> get props => [mobile, requestId, expiresIn, resendAfter, flow];
}

/// FR-1: `POST /auth/otp/send` returned USER_EXISTS — the number already
/// has a verified account. UI shows "Already registered? Log in" inline.
class AuthUserAlreadyExists extends AuthState {
  const AuthUserAlreadyExists(this.mobile);

  final String mobile;

  @override
  List<Object?> get props => [mobile];
}

class AuthOtpSendFailure extends AuthState {
  const AuthOtpSendFailure({
    required this.mobile,
    required this.errorCode,
    required this.message,
    required this.flow,
  });

  final String mobile;
  final String errorCode;
  final String message;
  final OtpFlow flow;

  @override
  List<Object?> get props => [mobile, errorCode, message, flow];
}

class AuthOtpVerifying extends AuthState {
  const AuthOtpVerifying({required this.mobile, required this.requestId});

  final String mobile;
  final String requestId;

  @override
  List<Object?> get props => [mobile, requestId];
}

/// FR-2: invalid / expired / lockout — errorCode drives which of the
/// spec's three distinct copy strings the OTP screen shows.
class AuthOtpVerifyFailure extends AuthState {
  const AuthOtpVerifyFailure({
    required this.mobile,
    required this.requestId,
    required this.errorCode,
    required this.message,
  });

  final String mobile;
  final String requestId;
  final String errorCode;
  final String message;

  @override
  List<Object?> get props => [mobile, requestId, errorCode, message];
}

/// Tokens themselves live only in SecureTokenStorage (never repeated
/// here) — nothing in the UI needs the raw token value again once
/// ApiClient's interceptor can read it from storage on each request.
/// `accountType`/`name` are populated from GET /users/me where possible
/// (MA-21 FR-4) but are optional: a failed profile lookup after a
/// successful login/registration must never block reaching Home, so this
/// state can legitimately carry both as `null` — and, on the fresh
/// registration path specifically, `name` starts `null` because the
/// profile doesn't exist yet at OTP-verify time (see
/// `ProfileRefreshRequested`, dispatched once registration completes).
class AuthAuthenticated extends AuthState {
  const AuthAuthenticated({this.accountType, this.name});

  final String? accountType;
  final String? name;

  @override
  List<Object?> get props => [accountType, name];
}

/// MA-21 FR-1's inverse of AuthUserAlreadyExists — the standalone /login
/// entry's mobile number has no matching account.
class AuthUserNotFound extends AuthState {
  const AuthUserNotFound(this.mobile);

  final String mobile;

  @override
  List<Object?> get props => [mobile];
}
