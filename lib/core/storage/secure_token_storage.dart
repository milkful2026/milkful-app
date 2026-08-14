import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// Session tokens live only in secure storage, never in shared_preferences
/// or app memory persisted to disk — per both specs' NFR "Security: Tokens
/// only in secure storage; no PII in logs".
class SecureTokenStorage {
  SecureTokenStorage({FlutterSecureStorage? storage})
      : _storage = storage ?? const FlutterSecureStorage();

  final FlutterSecureStorage _storage;

  static const _accessTokenKey = 'milkful_access_token';
  static const _refreshTokenKey = 'milkful_refresh_token';
  static const _accessTokenExpiresAtKey = 'milkful_access_token_expires_at';

  Future<void> saveTokens({
    required String accessToken,
    required String refreshToken,
    required DateTime accessTokenExpiresAt,
  }) async {
    await Future.wait([
      _storage.write(key: _accessTokenKey, value: accessToken),
      _storage.write(key: _refreshTokenKey, value: refreshToken),
      _storage.write(
        key: _accessTokenExpiresAtKey,
        value: accessTokenExpiresAt.toIso8601String(),
      ),
    ]);
  }

  Future<String?> readAccessToken() => _storage.read(key: _accessTokenKey);

  Future<String?> readRefreshToken() => _storage.read(key: _refreshTokenKey);

  Future<DateTime?> readAccessTokenExpiresAt() async {
    final raw = await _storage.read(key: _accessTokenExpiresAtKey);
    if (raw == null) return null;
    return DateTime.tryParse(raw);
  }

  /// Clears local storage unconditionally — logout must never leave a
  /// stale session behind even if the server-side revoke call fails, per
  /// MA-21 FR-5.
  Future<void> clear() async {
    await Future.wait([
      _storage.delete(key: _accessTokenKey),
      _storage.delete(key: _refreshTokenKey),
      _storage.delete(key: _accessTokenExpiresAtKey),
    ]);
  }
}
