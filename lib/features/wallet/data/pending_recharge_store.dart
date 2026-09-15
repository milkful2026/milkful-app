import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../models/pending_recharge.dart';

/// Thin `shared_preferences` wrapper around the `wallet.pendingRecharge`
/// record (MA-125 §7, PR #16 round-2 finding #6) — injected into
/// [WalletBloc] so its persistence behaviour is unit-testable without a
/// real plugin channel (tests inject a fake implementing this interface).
abstract class PendingRechargeStore {
  Future<PendingRecharge?> read();
  Future<void> write(PendingRecharge value);
  Future<void> clear();
}

class SharedPreferencesPendingRechargeStore implements PendingRechargeStore {
  static const _key = 'wallet.pendingRecharge';

  @override
  Future<PendingRecharge?> read() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_key);
    if (raw == null) return null;
    try {
      return PendingRecharge.fromJson(jsonDecode(raw) as Map<String, dynamic>);
    } catch (_) {
      // A malformed/stale record must never crash the Wallet screen —
      // treat it as absent, same as "no pending attempt".
      await clear();
      return null;
    }
  }

  @override
  Future<void> write(PendingRecharge value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_key, jsonEncode(value.toJson()));
  }

  @override
  Future<void> clear() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_key);
  }
}

/// The `wallet.lastPaymentMethod` record (MA-125 §4/§7) — remembers the
/// last-used payment method per device; defaults to Card (the mock's
/// default) when absent.
abstract class PaymentMethodStore {
  Future<String?> read();
  Future<void> write(String wireValue);
}

class SharedPreferencesPaymentMethodStore implements PaymentMethodStore {
  static const _key = 'wallet.lastPaymentMethod';

  @override
  Future<String?> read() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_key);
  }

  @override
  Future<void> write(String wireValue) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_key, wireValue);
  }
}
