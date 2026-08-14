import '../../../core/config/app_config.dart';
import '../../../core/network/api_client.dart';
import '../models/token_bundle.dart';

class OtpSendResult {
  const OtpSendResult({
    required this.requestId,
    required this.expiresIn,
    required this.resendAfter,
  });

  final String requestId;
  final int expiresIn;
  final int resendAfter;

  factory OtpSendResult.fromJson(Map<String, dynamic> json) => OtpSendResult(
        requestId: json['requestId'] as String,
        expiresIn: json['expiresIn'] as int,
        resendAfter: json['resendAfter'] as int,
      );
}

/// Registration-flow auth calls only (MA-1 scope) — the port MA-21's login
/// flow extends with sendLoginOtp/verifyLoginOtp/refresh/logout, in its own
/// PR. Kept in `features/auth/` (not `onboarding/`) precisely because that
/// extension reuses this exact interface, per both specs' technical design.
abstract class AuthRepository {
  Future<OtpSendResult> sendOtp(String mobile);

  Future<TokenBundle> verifyOtp({
    required String mobile,
    required String otp,
    required String requestId,
  });
}

class DioAuthRepository implements AuthRepository {
  DioAuthRepository(this._client);

  final ApiClient _client;

  @override
  Future<OtpSendResult> sendOtp(String mobile) async {
    final data = await _client.request(
      'POST',
      '${AppConfig.identityAuthBaseUrl}/v1/auth/otp/send',
      body: {'mobile': mobile},
    );
    return OtpSendResult.fromJson(data);
  }

  @override
  Future<TokenBundle> verifyOtp({
    required String mobile,
    required String otp,
    required String requestId,
  }) async {
    final data = await _client.request(
      'POST',
      '${AppConfig.identityAuthBaseUrl}/v1/auth/otp/verify',
      body: {'mobile': mobile, 'otp': otp, 'requestId': requestId},
    );
    return TokenBundle.fromJson(data);
  }
}
