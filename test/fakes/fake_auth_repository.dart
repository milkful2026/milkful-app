import 'package:milkful_app/core/network/api_client.dart';
import 'package:milkful_app/features/auth/data/auth_repository.dart';
import 'package:milkful_app/features/auth/models/token_bundle.dart';

/// Matches AuthRepository's real contract exactly (same "fix the fake, not
/// the assertion" discipline used throughout the backend this app talks
/// to) — configure [sendOtpException]/[verifyOtpException] to simulate
/// failures instead of hand-rolling ad-hoc mocks per test.
class FakeAuthRepository implements AuthRepository {
  FakeAuthRepository({
    this.sendOtpException,
    this.verifyOtpException,
    this.otpSendResult,
    this.tokenBundle,
  });

  ApiException? sendOtpException;
  ApiException? verifyOtpException;
  OtpSendResult? otpSendResult;
  TokenBundle? tokenBundle;

  final List<String> sentTo = [];
  final List<String> verifiedOtps = [];

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
}
