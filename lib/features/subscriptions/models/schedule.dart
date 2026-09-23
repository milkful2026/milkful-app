import 'package:equatable/equatable.dart';

/// MA-131 §6. Wire values match Subscription Service's `ScheduleType`
/// StrEnum exactly.
enum ScheduleType {
  daily,
  alternateDays,
  weekly,
  customDays;

  String get wireValue => switch (this) {
    ScheduleType.daily => 'DAILY',
    ScheduleType.alternateDays => 'ALTERNATE_DAYS',
    ScheduleType.weekly => 'WEEKLY',
    ScheduleType.customDays => 'CUSTOM_DAYS',
  };

  static ScheduleType fromWire(String value) => switch (value) {
    'DAILY' => ScheduleType.daily,
    'ALTERNATE_DAYS' => ScheduleType.alternateDays,
    'WEEKLY' => ScheduleType.weekly,
    'CUSTOM_DAYS' => ScheduleType.customDays,
    _ => throw ArgumentError('Unknown schedule type: $value'),
  };
}

/// Mirrors subscription/src/domain/models.py's `Schedule` dataclass and
/// its `to_dict()`/`ScheduleDto` wire shape. [daysOfWeek] is only ever
/// non-null for [ScheduleType.weekly]/[ScheduleType.customDays] — ISO
/// weekday numbers (1=Monday..7=Sunday), matching the backend's own
/// `days_of_week` field.
class Schedule extends Equatable {
  const Schedule({required this.type, this.daysOfWeek});

  final ScheduleType type;
  final List<int>? daysOfWeek;

  factory Schedule.fromJson(Map<String, dynamic> json) => Schedule(
    type: ScheduleType.fromWire(json['type'] as String),
    daysOfWeek: (json['daysOfWeek'] as List?)?.cast<int>(),
  );

  Map<String, dynamic> toJson() => {
    'type': type.wireValue,
    if (daysOfWeek != null) 'daysOfWeek': daysOfWeek,
  };

  /// FR-4's human-readable frequency label. `{Day}`/`{Day, Day, ...}`
  /// short weekday names, matching `intl`'s own `DateFormat.EEEE()`
  /// abbreviation convention used elsewhere in this app.
  String label() {
    switch (type) {
      case ScheduleType.daily:
        return 'Delivers Daily';
      case ScheduleType.alternateDays:
        return 'Delivers Every Other Day';
      case ScheduleType.weekly:
        return 'Delivers Weekly on ${_dayNames()}';
      case ScheduleType.customDays:
        return 'Delivers on ${_dayNames()}';
    }
  }

  String _dayNames() {
    const names = {1: 'Mon', 2: 'Tue', 3: 'Wed', 4: 'Thu', 5: 'Fri', 6: 'Sat', 7: 'Sun'};
    final days = daysOfWeek ?? const [];
    return days.map((d) => names[d] ?? '?').join(', ');
  }

  @override
  List<Object?> get props => [type, daysOfWeek];
}
