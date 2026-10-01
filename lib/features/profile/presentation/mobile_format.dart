/// MA-147 FR-4 — `+91 98765 43210` for a 10-digit Indian number, with or
/// without a `+91`/`91` prefix; anything else as stored; null when empty
/// (the row is hidden).
String? formatIndianMobile(String? mobile) {
  final raw = mobile?.trim() ?? '';
  if (raw.isEmpty) return null;
  final digits = raw.replaceAll(RegExp(r'[\s-]'), '');
  final match = RegExp(r'^(?:\+?91)?([6-9]\d{9})$').firstMatch(digits);
  if (match == null) return raw;
  final n = match.group(1)!;
  return '+91 ${n.substring(0, 5)} ${n.substring(5)}';
}

/// Up to two initials from a name; empty when the name is blank.
String initialsOf(String name) {
  final parts = name
      .trim()
      .split(RegExp(r'\s+'))
      .where((p) => p.isNotEmpty)
      .toList();
  return parts.take(2).map((p) => p[0].toUpperCase()).join();
}
