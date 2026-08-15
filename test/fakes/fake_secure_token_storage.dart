import 'package:milkful_app/core/storage/secure_token_storage.dart';

/// In-memory stand-in — real SecureTokenStorage wraps
/// flutter_secure_storage, which has no platform channel available under
/// `flutter test`'s headless environment.
class FakeSecureTokenStorage implements SecureTokenStorage {
  String? accessToken;
  String? refreshToken;
  DateTime? accessTokenExpiresAt;

  /// Simulates a real, documented flutter_secure_storage failure mode
  /// (e.g. a PlatformException on some Android OEMs/Keystore states) —
  /// deliberately not an ApiException, to exercise the non-API error path.
  Object? saveTokensException;
  Object? readAccessTokenExpiresAtException;

  @override
  Future<void> saveTokens({
    required String accessToken,
    required String refreshToken,
    required DateTime accessTokenExpiresAt,
  }) async {
    if (saveTokensException != null) throw saveTokensException!;
    this.accessToken = accessToken;
    this.refreshToken = refreshToken;
    this.accessTokenExpiresAt = accessTokenExpiresAt;
  }

  @override
  Future<String?> readAccessToken() async => accessToken;

  @override
  Future<String?> readRefreshToken() async => refreshToken;

  @override
  Future<DateTime?> readAccessTokenExpiresAt() async {
    if (readAccessTokenExpiresAtException != null) throw readAccessTokenExpiresAtException!;
    return accessTokenExpiresAt;
  }

  @override
  Future<void> clear() async {
    accessToken = null;
    refreshToken = null;
    accessTokenExpiresAt = null;
  }
}
