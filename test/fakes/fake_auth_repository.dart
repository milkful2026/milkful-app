import 'dart:async';

import 'package:milkful_app/core/network/api_client.dart';
import 'package:milkful_app/features/auth/data/auth_repository.dart';
import 'package:milkful_app/features/auth/models/token_bundle.dart';

/// Matches AuthRepository's real contract exactly (same "fix the fake, not
/// the assertion" discipline used throughout the backend this app talks
/// to) — configure the `*Exception` fields to simulate failures instead of
/// hand-rolling ad-hoc mocks per test.
class FakeAuthRepository implements AuthRepository {
  FakeAuthRepository({
    this.sendOtpException,
    this.verifyOtpException,
    this.sendLoginOtpException,
    this.verifyLoginOtpException,
    this.refreshTokenException,
    this.logoutException,
    this.otpSendResult,
    this.tokenBundle,
  });

  ApiException? sendOtpException;
  ApiException? verifyOtpException;
  ApiException? sendLoginOtpException;
  ApiException? verifyLoginOtpException;
  Object? refreshTokenException;
  Object? logoutException;
  OtpSendResult? otpSendResult;
  TokenBundle? tokenBundle;

  /// When set, `sendLoginOtp` waits on this before resolving/throwing —
  /// lets a test hold a login send "in flight" to exercise races against
  /// it (e.g. a concurrent registration send).
  Completer<void>? sendLoginOtpGate;

  final List<String> sentTo = [];
  final List<String> verifiedOtps = [];
  final List<String> loginSentTo = [];
  final List<String> loginVerifiedOtps = [];
  final List<String> refreshedWith = [];
  final List<String> loggedOutWith = [];

  @override
  Future<OtpSendResult> sendOtp(String mobile) async {
    sentTo.add(mobile);
    if (sendOtpException != null) throw sendOtpException!;
    return otpSendResult ??
        const OtpSendResult(requestId: 'req-1', expiresIn: 300, resendAfter: 30);
  }

  @override
  Future<TokenBundle> verifyOtp({
    required String mobile,
    required String otp,
    required String requestId,
  }) async {
    verifiedOtps.add(otp);
    if (verifyOtpException != null) throw verifyOtpException!;
    return tokenBundle ??
        const TokenBundle(
          accessToken: 'access-token',
          refreshToken: 'refresh-token',
          expiresIn: 3600,
          isNewUser: true,
        );
  }

  @override
  Future<OtpSendResult> sendLoginOtp(String mobile) async {
    loginSentTo.add(mobile);
    if (sendLoginOtpGate != null) await sendLoginOtpGate!.future;
    if (sendLoginOtpException != null) throw sendLoginOtpException!;
    return otpSendResult ??
        const OtpSendResult(requestId: 'login-req-1', expiresIn: 300, resendAfter: 30);
  }

  @override
  Future<TokenBundle> verifyLoginOtp({
    required String mobile,
    required String otp,
    required String requestId,
  }) async {
    loginVerifiedOtps.add(otp);
    if (verifyLoginOtpException != null) throw verifyLoginOtpException!;
    return tokenBundle ??
        const TokenBundle(
          accessToken: 'login-access-token',
          refreshToken: 'login-refresh-token',
          expiresIn: 3600,
        );
  }

  @override
  Future<TokenBundle> refreshToken(String refreshToken) async {
    refreshedWith.add(refreshToken);
    if (refreshTokenException != null) throw refreshTokenException!;
    return tokenBundle ??
        const TokenBundle(
          accessToken: 'refreshed-access-token',
          refreshToken: 'refreshed-refresh-token',
          expiresIn: 3600,
        );
  }

  @override
  Future<void> logout(String refreshToken) async {
    loggedOutWith.add(refreshToken);
    if (logoutException != null) throw logoutException!;
  }
}
