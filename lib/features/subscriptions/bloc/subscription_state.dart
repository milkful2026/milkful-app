import 'package:equatable/equatable.dart';

import '../models/subscription_view.dart';

enum SubscriptionsLoadStatus { idle, loading, loaded, failed }

/// Per-subscription action lifecycle — keyed by subscription id in
/// [SubscriptionsState.actionStatus] so one card's pause-in-flight
/// spinner doesn't disable unrelated cards (MA-133 §6/§10).
enum ActionStatus { idle, loading }

/// One-shot notice surfaced by a `BlocListener` (snackbar) — [attempt] is
/// a monotonic per-bloc counter so two consecutive messages with
/// identical text/id still register as distinct values for `listenWhen`
/// to key off, and are never re-shown on an unrelated rebuild.
class SubscriptionActionMessage extends Equatable {
  const SubscriptionActionMessage({
    required this.subscriptionId,
    required this.message,
    required this.isError,
    required this.attempt,
  });

  final String subscriptionId;
  final String message;
  final bool isError;
  final int attempt;

  @override
  List<Object?> get props => [subscriptionId, message, isError, attempt];
}

class SubscriptionsState extends Equatable {
  const SubscriptionsState({
    this.loadStatus = SubscriptionsLoadStatus.idle,
    this.subscriptions = const [],
    this.loadErrorMessage,
    this.actionStatus = const {},
    this.lastActionMessage,
  });

  final SubscriptionsLoadStatus loadStatus;
  final List<SubscriptionView> subscriptions;
  final String? loadErrorMessage;

  /// Absent (not `idle`) for a subscription with nothing in flight —
  /// callers use `actionStatus[id] ?? ActionStatus.idle`.
  final Map<String, ActionStatus> actionStatus;

  final SubscriptionActionMessage? lastActionMessage;

  /// FR-3 — computed, never a client-tracked flag (the exact gap this
  /// spec's own regression tests fix): `true` iff there is at least one
  /// subscription and every one of them is `PAUSED` with no `pauseUntil`.
  /// Guarded on non-empty so a fresh account with zero subscriptions
  /// doesn't vacuously read as "already on" (`Iterable.every` is `true`
  /// on an empty list) — MA-133 §9's "zero subscriptions" edge case
  /// expects the toggle to start OFF.
  bool get vacationModeOn =>
      subscriptions.isNotEmpty && subscriptions.every((s) => s.isPausedIndefinitely);

  ActionStatus statusFor(String id) => actionStatus[id] ?? ActionStatus.idle;

  SubscriptionsState copyWith({
    SubscriptionsLoadStatus? loadStatus,
    List<SubscriptionView>? subscriptions,
    String? loadErrorMessage,
    bool clearLoadErrorMessage = false,
    Map<String, ActionStatus>? actionStatus,
    SubscriptionActionMessage? lastActionMessage,
  }) => SubscriptionsState(
    loadStatus: loadStatus ?? this.loadStatus,
    subscriptions: subscriptions ?? this.subscriptions,
    loadErrorMessage: clearLoadErrorMessage ? null : (loadErrorMessage ?? this.loadErrorMessage),
    actionStatus: actionStatus ?? this.actionStatus,
    lastActionMessage: lastActionMessage ?? this.lastActionMessage,
  );

  /// Returns a new `actionStatus` map with just [id] updated — every other
  /// entry untouched, so concurrent per-subscription actions never clobber
  /// each other's status.
  Map<String, ActionStatus> actionStatusWith(String id, ActionStatus status) => {
    ...actionStatus,
    id: status,
  };

  @override
  List<Object?> get props => [
    loadStatus,
    subscriptions,
    loadErrorMessage,
    actionStatus,
    lastActionMessage,
  ];
}
