import 'package:equatable/equatable.dart';

import '../models/token_bundle.dart';

sealed class AuthState extends Equatable {
  const AuthState();

  @override
  List<Object?> get props => [];
}

class AuthInitial extends AuthState {
  const AuthInitial();
}

class AuthOtpSending extends AuthState {
  const AuthOtpSending(this.mobile);

  final String mobile;

  @override
  List<Object?> get props => [mobile];
}

class AuthOtpSent extends AuthState {
  const AuthOtpSent({
    required this.mobile,
    required this.requestId,
    required this.expiresIn,
    required this.resendAfter,
  });

  final String mobile;
  final String requestId;
  final int expiresIn;
  final int resendAfter;

  @override
  List<Object?> get props => [mobile, requestId, expiresIn, resendAfter];
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
  });

  final String mobile;
  final String errorCode;
  final String message;

  @override
  List<Object?> get props => [mobile, errorCode, message];
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

class AuthAuthenticated extends AuthState {
  const AuthAuthenticated(this.tokens);

  final TokenBundle tokens;

  @override
  List<Object?> get props => [tokens];
}
