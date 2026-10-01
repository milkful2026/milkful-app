import 'package:intl/intl.dart';

import '../../../core/utils/ist_clock.dart';

/// MA-145 FR-9 group headers: "Tomorrow, 24 Oct" / "Yesterday, 22 Oct" /
/// "Sat, 26 Oct", with the year appended when it isn't today's IST year.
String formatGroupDate(DateTime date, DateTime today, {required bool upcoming}) {
  final d = dateOnly(date);
  final t = dateOnly(today);
  final dayMonth = DateFormat('d MMM').format(d);
  final year = d.year == t.year ? '' : ' ${d.year}';
  if (upcoming && d == t.add(const Duration(days: 1))) return 'Tomorrow, $dayMonth$year';
  if (!upcoming && d == t.subtract(const Duration(days: 1))) {
    return 'Yesterday, $dayMonth$year';
  }
  return '${DateFormat('EEE').format(d)}, $dayMonth$year';
}

/// MA-146 FR-6 — "Sat, 26 Oct 2026".
String formatLongDate(DateTime date) => DateFormat('EEE, d MMM y').format(dateOnly(date));

/// MA-146 FR-3 "Placed On" — "24 Oct 2026", from an instant, in IST.
String formatPlacedOn(DateTime instant) =>
    DateFormat('d MMM y').format(istNow(() => instant));
