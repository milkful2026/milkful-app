import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../core/network/api_client.dart';
import '../../catalog/data/catalog_repository.dart';
import '../data/subscription_repository.dart';
import '../models/subscription_status.dart';
import '../models/subscription_view.dart';
import 'subscription_event.dart';
import 'subscription_state.dart';

/// MA-133 §6. Mirrors `WalletBloc`'s shape (one bloc owning a list screen
/// with several async lifecycle actions).
class SubscriptionBloc extends Bloc<SubscriptionEvent, SubscriptionsState> {
  SubscriptionBloc({required this._repository, required this._catalogRepository})
    : super(const SubscriptionsState()) {
    on<SubscriptionsStarted>(_onStarted);
    on<SubscriptionsRefreshRequested>(_onStarted);
    on<VacationModeToggled>(_onVacationModeToggled);
    on<PauseRequested>(_onPauseRequested);
    on<ResumeRequested>(_onResumeRequested);
    on<StopRequested>(_onStopRequested);
    on<SkipRequested>(_onSkipRequested);
    on<EditRequested>(_onEditRequested);
  }

  final SubscriptionRepository _repository;

  /// Subscription Service's own response only ever carries `productId`
  /// (see subscription_repository.dart) — this resolves each one's
  /// display name via Catalog, same "fail gracefully, keep going" posture
  /// as `ProductConfigBloc._refreshStaleStock`: a lookup failure leaves
  /// that one subscription showing its bare `productId` rather than
  /// blocking the whole list.
  final CatalogRepository _catalogRepository;

  Future<List<SubscriptionView>> _withProductNames(List<SubscriptionView> subscriptions) async {
    final results = await Future.wait(
      subscriptions.map((s) async {
        try {
          final product = await _catalogRepository.getProduct(s.productId);
          return s.copyWithProductName(product.name);
        } catch (_) {
          return s;
        }
      }),
    );
    return results;
  }

  /// Feeds [SubscriptionActionMessage.attempt] — see that class's doc
  /// comment on why a monotonic counter, not just id+text, is needed.
  int _messageAttempt = 0;

  Future<void> _onStarted(SubscriptionEvent event, Emitter<SubscriptionsState> emit) async {
    emit(state.copyWith(loadStatus: SubscriptionsLoadStatus.loading));
    try {
      final subscriptions = await _withProductNames(await _repository.list());
      if (isClosed) return;
      emit(
        state.copyWith(
          loadStatus: SubscriptionsLoadStatus.loaded,
          subscriptions: subscriptions,
          clearLoadErrorMessage: true,
        ),
      );
    } on ApiException catch (e) {
      emit(state.copyWith(loadStatus: SubscriptionsLoadStatus.failed, loadErrorMessage: e.message));
    } catch (_) {
      emit(
        state.copyWith(
          loadStatus: SubscriptionsLoadStatus.failed,
          loadErrorMessage: 'Something went wrong. Please try again.',
        ),
      );
    }
  }

  /// Re-fetches the full list from the server rather than patching
  /// individual entries — Subscription Service's own pause/resume/stop
  /// endpoints do return an updated detail response, but `skip`/`edit`
  /// don't (see subscription_repository.dart's own doc comments), so a
  /// single, uniform "always refetch after a write" rule keeps every
  /// action's post-state identically correct rather than three field-
  /// patching code paths and two full-refetch ones.
  Future<List<SubscriptionView>> _refreshList() async =>
      _withProductNames(await _repository.list());

  String _friendlyMessage(Object error) =>
      error is ApiException ? error.message : 'Something went wrong. Please try again.';

  Future<void> _onVacationModeToggled(
    VacationModeToggled event,
    Emitter<SubscriptionsState> emit,
  ) async {
    final targetIds = event.on
        ? state.subscriptions
              .where((s) => s.status == SubscriptionStatus.active)
              .map((s) => s.id)
              .toList()
        : state.subscriptions.where((s) => s.isPausedIndefinitely).map((s) => s.id).toList();
    if (targetIds.isEmpty) return; // MA-133 §9 — nothing to pause/resume.

    emit(
      state.copyWith(
        actionStatus: {
          ...state.actionStatus,
          for (final id in targetIds) id: ActionStatus.loading,
        },
      ),
    );

    String? failureMessage;
    await Future.wait(
      targetIds.map((id) async {
        try {
          if (event.on) {
            await _repository.pause(id);
          } else {
            await _repository.resume(id);
          }
        } catch (e) {
          failureMessage ??= _friendlyMessage(e);
        }
      }),
    );

    if (isClosed) return;
    List<SubscriptionView> refreshed = state.subscriptions;
    try {
      refreshed = await _refreshList();
    } catch (_) {
      // Keep the pre-toggle list — a refetch failure here must not also
      // wipe out what's currently on screen.
    }
    if (isClosed) return;
    emit(
      state.copyWith(
        subscriptions: refreshed,
        actionStatus: {for (final entry in state.actionStatus.entries) entry.key: ActionStatus.idle},
        lastActionMessage: failureMessage == null
            ? null
            : SubscriptionActionMessage(
                subscriptionId: '',
                message: failureMessage!,
                isError: true,
                attempt: ++_messageAttempt,
              ),
      ),
    );
  }

  Future<void> _runAction(
    String id,
    Emitter<SubscriptionsState> emit,
    Future<void> Function() action, {
    String Function(Object error)? errorMessage,
  }) async {
    emit(state.copyWith(actionStatus: state.actionStatusWith(id, ActionStatus.loading)));
    try {
      await action();
      final refreshed = await _refreshList();
      if (isClosed) return;
      emit(
        state.copyWith(
          subscriptions: refreshed,
          actionStatus: state.actionStatusWith(id, ActionStatus.idle),
        ),
      );
    } catch (e) {
      if (isClosed) return;
      emit(
        state.copyWith(
          actionStatus: state.actionStatusWith(id, ActionStatus.idle),
          lastActionMessage: SubscriptionActionMessage(
            subscriptionId: id,
            message: (errorMessage ?? _friendlyMessage)(e),
            isError: true,
            attempt: ++_messageAttempt,
          ),
        ),
      );
    }
  }

  Future<void> _onPauseRequested(PauseRequested event, Emitter<SubscriptionsState> emit) =>
      _runAction(event.id, emit, () => _repository.pause(event.id, from: event.from, until: event.until));

  Future<void> _onResumeRequested(ResumeRequested event, Emitter<SubscriptionsState> emit) =>
      _runAction(event.id, emit, () => _repository.resume(event.id));

  Future<void> _onStopRequested(StopRequested event, Emitter<SubscriptionsState> emit) =>
      _runAction(event.id, emit, () => _repository.stop(event.id));

  Future<void> _onSkipRequested(SkipRequested event, Emitter<SubscriptionsState> emit) => _runAction(
    event.id,
    emit,
    () => _repository.skip(event.id, event.date),
    // MA-133 §9 — a stale client-side cut-off guess racing the server's
    // authoritative one surfaces as this specific errorCode.
    errorMessage: (error) => error is ApiException && error.errorCode == 'CUTOFF_PASSED'
        ? 'Too late to skip this delivery'
        : _friendlyMessage(error),
  );

  Future<void> _onEditRequested(EditRequested event, Emitter<SubscriptionsState> emit) async {
    SubscriptionView? before;
    for (final s in state.subscriptions) {
      if (s.id == event.id) {
        before = s;
        break;
      }
    }
    emit(state.copyWith(actionStatus: state.actionStatusWith(event.id, ActionStatus.loading)));
    try {
      final effectiveFrom = await _repository.edit(
        event.id,
        quantity: event.quantity,
        schedule: event.schedule,
      );
      final refreshed = await _refreshList();
      if (isClosed) return;
      // MA-133 FR-5 — a deferred edit (effectiveFrom later than what was
      // already the next delivery) gets a one-line notice rather than
      // silently applying; an immediate edit (effectiveFrom null, or no
      // later than the prior next-delivery date) needs no notice.
      final deferred =
          effectiveFrom != null &&
          (before?.nextDeliveryDate == null || effectiveFrom.isAfter(before!.nextDeliveryDate!));
      emit(
        state.copyWith(
          subscriptions: refreshed,
          actionStatus: state.actionStatusWith(event.id, ActionStatus.idle),
          lastActionMessage: deferred
              ? SubscriptionActionMessage(
                  subscriptionId: event.id,
                  message: 'Changes apply from ${effectiveFrom.toIso8601String().split('T').first}',
                  isError: false,
                  attempt: ++_messageAttempt,
                )
              : null,
        ),
      );
    } catch (e) {
      if (isClosed) return;
      emit(
        state.copyWith(
          actionStatus: state.actionStatusWith(event.id, ActionStatus.idle),
          lastActionMessage: SubscriptionActionMessage(
            subscriptionId: event.id,
            message: _friendlyMessage(e),
            isError: true,
            attempt: ++_messageAttempt,
          ),
        ),
      );
    }
  }
}
