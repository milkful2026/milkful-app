import 'package:equatable/equatable.dart';

import '../models/schedule.dart';

sealed class SubscriptionEvent extends Equatable {
  const SubscriptionEvent();

  @override
  List<Object?> get props => [];
}

/// Fired once on screen open — `GET /subscriptions/me`.
class SubscriptionsStarted extends SubscriptionEvent {
  const SubscriptionsStarted();
}

/// Pull-to-refresh (MA-133 §9's "two devices diverge" case).
class SubscriptionsRefreshRequested extends SubscriptionEvent {
  const SubscriptionsRefreshRequested();
}

/// `true`: pause every currently-`ACTIVE` subscription (open-ended).
/// `false`: resume every subscription currently `PAUSED` with no
/// `pauseUntil` — the same aggregate `vacationModeOn` is computed from,
/// never a client-side-tracked subset (MA-133 FR-3's own regression fix).
class VacationModeToggled extends SubscriptionEvent {
  const VacationModeToggled(this.on);

  final bool on;

  @override
  List<Object?> get props => [on];
}

class PauseRequested extends SubscriptionEvent {
  const PauseRequested(this.id, {this.from, this.until});

  final String id;
  final DateTime? from;
  final DateTime? until;

  @override
  List<Object?> get props => [id, from, until];
}

class ResumeRequested extends SubscriptionEvent {
  const ResumeRequested(this.id);

  final String id;

  @override
  List<Object?> get props => [id];
}

class StopRequested extends SubscriptionEvent {
  const StopRequested(this.id);

  final String id;

  @override
  List<Object?> get props => [id];
}

class SkipRequested extends SubscriptionEvent {
  const SkipRequested(this.id, this.date);

  final String id;
  final DateTime date;

  @override
  List<Object?> get props => [id, date];
}

class EditRequested extends SubscriptionEvent {
  const EditRequested(this.id, {this.quantity, this.schedule});

  final String id;
  final int? quantity;
  final Schedule? schedule;

  @override
  List<Object?> get props => [id, quantity, schedule];
}
