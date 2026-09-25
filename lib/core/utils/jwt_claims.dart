import 'dart:convert';

/// Reads the signed-in user's id without a network call.
typedef CurrentUserIdReader = Future<String?> Function();

/// The `sub` claim of a Cognito JWT, decoded locally. No signature check:
/// the result only scopes on-device data (MA-137 FR-9), and every server
/// call still verifies the token itself. `null` for a missing or malformed
/// token.
String? subFromJwt(String? token) {
  if (token == null) return null;
  final parts = token.split('.');
  if (parts.length != 3) return null;
  try {
    final payload = utf8.decode(base64Url.decode(base64Url.normalize(parts[1])));
    final claims = jsonDecode(payload);
    if (claims is! Map<String, dynamic>) return null;
    final sub = claims['sub'];
    return sub is String && sub.isNotEmpty ? sub : null;
  } catch (_) {
    return null;
  }
}
