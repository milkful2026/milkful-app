/// IST (UTC+05:30, no DST) date helpers. Delivery dates on the wire are
/// IST calendar dates, so "today" must be computed in IST from UTC — never
/// from the device's own time zone.
library;

typedef Clock = DateTime Function();

const _istOffset = Duration(hours: 5, minutes: 30);

/// The current IST wall-clock time, as a UTC-flagged [DateTime] whose
/// fields read as IST (only its date/time fields are meaningful).
DateTime istNow(Clock clock) => clock().toUtc().add(_istOffset);

/// Today's IST calendar date, as a date-only local [DateTime].
DateTime istToday(Clock clock) => dateOnly(istNow(clock));

/// Strips the time part, keeping the calendar date as written.
DateTime dateOnly(DateTime d) => DateTime(d.year, d.month, d.day);

bool isSameDate(DateTime a, DateTime b) =>
    a.year == b.year && a.month == b.month && a.day == b.day;

/// MA-155 — the instant a delivery stops being cancellable: [cutoffHourIst]
/// IST on the day before [deliveryDate]. The hour must match Order and
/// Subscription Service's `checkout_cutoff_hour_ist`; the server stays
/// authoritative, so this only decides what the app shows.
DateTime deliveryCutoff(DateTime deliveryDate, {int cutoffHourIst = 20}) => DateTime.utc(
  deliveryDate.year,
  deliveryDate.month,
  deliveryDate.day - 1,
  cutoffHourIst,
).subtract(_istOffset);

/// Parses the leading `YYYY-MM-DD` of an API date string as a calendar
/// date, ignoring any time or offset suffix.
DateTime parseApiDate(String value) => dateOnly(DateTime.parse(value.substring(0, 10)));
