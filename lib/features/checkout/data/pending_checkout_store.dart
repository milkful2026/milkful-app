import 'package:shared_preferences/shared_preferences.dart';

/// MA-137 FR-9 — the Idempotency-Key of a Confirm Order that hasn't reached
/// a final outcome yet, kept per user so it survives an app kill. Reusing
/// it makes the server resume (never repeat) that checkout. Same injectable
/// shape as `PendingRechargeStore`.
abstract class PendingCheckoutStore {
  Future<String?> read(String userId);
  Future<void> write(String userId, String key);
  Future<void> clear(String userId);
}

class SharedPreferencesPendingCheckoutStore implements PendingCheckoutStore {
  static String _key(String userId) => 'checkout.pendingKey.$userId';

  @override
  Future<String?> read(String userId) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      return prefs.getString(_key(userId));
    } catch (_) {
      // A per-device convenience: without it a retry just mints a new key,
      // which the server's own guards (cart version, one live checkout)
      // still keep from double-ordering.
      return null;
    }
  }

  @override
  Future<void> write(String userId, String key) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_key(userId), key);
    } catch (_) {}
  }

  @override
  Future<void> clear(String userId) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(_key(userId));
    } catch (_) {}
  }
}
