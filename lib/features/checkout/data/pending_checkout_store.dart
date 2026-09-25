import 'dart:convert';

import 'package:equatable/equatable.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// MA-137 FR-9 — a Confirm Order that hasn't reached a final outcome: its
/// Idempotency-Key plus the exact body it was sent with. A resume resends
/// both, so the server finishes what the customer confirmed (MA-136 FR-2a
/// ignores a changed body once a checkout may have been charged).
class PendingCheckout extends Equatable {
  const PendingCheckout({
    required this.key,
    required this.cartVersion,
    required this.expectedPayNowPaise,
  });

  final String key;
  final int cartVersion;
  final int expectedPayNowPaise;

  Map<String, dynamic> toJson() => {
    'key': key,
    'cartVersion': cartVersion,
    'expectedPayNowPaise': expectedPayNowPaise,
  };

  /// `null` for anything that isn't a complete record — a corrupt entry is
  /// treated as absent rather than resumed with a guessed body.
  static PendingCheckout? tryParse(String raw) {
    try {
      final json = jsonDecode(raw);
      if (json is! Map<String, dynamic>) return null;
      final key = json['key'];
      final cartVersion = json['cartVersion'];
      final expected = json['expectedPayNowPaise'];
      if (key is! String || cartVersion is! int || expected is! int) return null;
      return PendingCheckout(key: key, cartVersion: cartVersion, expectedPayNowPaise: expected);
    } catch (_) {
      return null;
    }
  }

  @override
  List<Object?> get props => [key, cartVersion, expectedPayNowPaise];
}

/// Kept per user (the Cognito `sub`, FR-9) so it survives an app kill and a
/// logout. Same injectable shape as `PendingRechargeStore`.
abstract class PendingCheckoutStore {
  Future<PendingCheckout?> read(String userId);

  /// `false` when the record couldn't be saved — the caller must not send
  /// the checkout then, or a retry could no longer resume it.
  Future<bool> write(String userId, PendingCheckout pending);

  Future<void> clear(String userId);
}

class SharedPreferencesPendingCheckoutStore implements PendingCheckoutStore {
  static String _key(String userId) => 'checkout.pendingKey.$userId';

  @override
  Future<PendingCheckout?> read(String userId) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_key(userId));
      return raw == null ? null : PendingCheckout.tryParse(raw);
    } catch (_) {
      return null;
    }
  }

  @override
  Future<bool> write(String userId, PendingCheckout pending) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      return await prefs.setString(_key(userId), jsonEncode(pending.toJson()));
    } catch (_) {
      return false;
    }
  }

  @override
  Future<void> clear(String userId) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(_key(userId));
    } catch (_) {}
  }
}
