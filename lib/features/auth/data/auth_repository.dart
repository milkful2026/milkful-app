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

abstract class AuthRepository {
  Future<OtpSendResult> sendOtp(String mobile);

  Future<TokenBundle> verifyOtp({
    required String mobile,
    required String otp,
    required String requestId,
  });

  /// MA-21 FR-1.
  Future<OtpSendResult> sendLoginOtp(String mobile);

  /// MA-21 FR-2. Response has no `isNewUser` (identity-auth's
  /// login_otp_verify_handler.py omits it entirely, not just sets it
  /// false) — TokenBundle.fromJson's already-nullable field handles this
  /// with no change needed.
  Future<TokenBundle> verifyLoginOtp({
    required String mobile,
    required String otp,
    required String requestId,
  });

  /// MA-21 FR-3 (silent refresh).
  Future<TokenBundle> refreshToken(String refreshToken);

  /// MA-21 FR-5. The route is Cognito-JWT-authorized; ApiClient's shared
  /// token interceptor attaches the Bearer access token automatically —
  /// nothing special needed here.
  Future<void> logout(String refreshToken);
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

  @override
  Future<OtpSendResult> sendLoginOtp(String mobile) async {
    final data = await _client.request(
      'POST',
      '${AppConfig.identityAuthBaseUrl}/v1/auth/login/otp/send',
      body: {'mobile': mobile},
    );
    return OtpSendResult.fromJson(data);
  }

  @override
  Future<TokenBundle> verifyLoginOtp({
    required String mobile,
    required String otp,
    required String requestId,
  }) async {
    final data = await _client.request(
      'POST',
      '${AppConfig.identityAuthBaseUrl}/v1/auth/login/otp/verify',
      body: {'mobile': mobile, 'otp': otp, 'requestId': requestId},
    );
    return TokenBundle.fromJson(data);
  }

  @override
  Future<TokenBundle> refreshToken(String refreshToken) async {
    final data = await _client.request(
      'POST',
      '${AppConfig.identityAuthBaseUrl}/v1/auth/token/refresh',
      body: {'refreshToken': refreshToken},
    );
    return TokenBundle.fromJson(data);
  }

  @override
  Future<void> logout(String refreshToken) async {
    await _client.request(
      'POST',
      '${AppConfig.identityAuthBaseUrl}/v1/auth/logout',
      body: {'refreshToken': refreshToken},
    );
  }
}
