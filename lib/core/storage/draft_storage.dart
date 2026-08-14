import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../../features/onboarding/models/registration_draft.dart';

/// Onboarding-in-progress state only (spec §7/FR-10) — never tokens (those
/// live in SecureTokenStorage). Safe for shared_preferences: no secrets, no
/// verified PII beyond what the user already typed into this same device.
class DraftStorage {
  static const _key = 'milkful_registration_draft';

  Future<void> save(RegistrationDraft draft) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_key, jsonEncode(draft.toJson()));
  }

  Future<RegistrationDraft?> load() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_key);
    if (raw == null) return null;
    try {
      return RegistrationDraft.fromJson(jsonDecode(raw) as Map<String, dynamic>);
    } catch (_) {
      // Corrupt/incompatible draft (e.g. after a schema change) must never
      // crash app start — treat it as if no draft existed.
      return null;
    }
  }

  Future<void> clear() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_key);
  }
}
