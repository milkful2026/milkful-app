import 'package:equatable/equatable.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../core/network/api_client.dart';
import '../../../core/utils/ist_clock.dart';
import '../../catalog/data/catalog_repository.dart';
import '../../catalog/models/product.dart';
import '../../subscriptions/data/subscription_repository.dart';
import '../data/order_repository.dart';
import '../domain/order_buckets.dart';
import '../models/order_entry.dart';
import 'order_detail_cubit.dart';

/// Why a refresh moved the scheduled date (MA-146 FR-8).
sealed class ScheduleChange extends Equatable {
  const ScheduleChange();

  @override
  List<Object?> get props => [];
}

class NoChange extends ScheduleChange {
  const NoChange();
}

/// The date moved but no order exists for the old date — skipped,
/// edited or paused elsewhere (or the order lookup failed).
class DateChanged extends ScheduleChange {
  const DateChanged();
}

/// Order Service has an order for the date that was on screen.
class BecameOrder extends ScheduleChange {
  const BecameOrder(this.orderId);

  final String orderId;

  @override
  List<Object?> get props => [orderId];
}

sealed class ScheduledDeliveryState extends Equatable {
  const ScheduledDeliveryState();

  @override
  List<Object?> get props => [];
}

class ScheduledDeliveryLoading extends ScheduledDeliveryState {
  const ScheduledDeliveryLoading();
}

class ScheduledDeliveryLoaded extends ScheduledDeliveryState {
  const ScheduledDeliveryLoaded(
    this.entry,
    this.product, {
    this.change = const NoChange(),
    this.quiet = false,
  });

  final ScheduledEntry entry;

  /// Null when the Catalog lookup failed (no estimate).
  final Product? product;
  final ScheduleChange change;

  /// MA-155 — the refresh after a refused Cancel delivery: its outcome
  /// SnackBar explains [change], so the screen's own notice stays quiet.
  final bool quiet;

  @override
  List<Object?> get props => [entry, product, change, quiet];
}

/// STOPPED, or no next delivery after today.
class ScheduledDeliveryGone extends ScheduledDeliveryState {
  const ScheduledDeliveryGone();
}

class ScheduledDeliveryError extends ScheduledDeliveryState {
  const ScheduledDeliveryError();
}

/// MA-155 FR-5 — how a Cancel delivery (Skip) ended. [alreadyOrder]: Skip
/// said CUTOFF_PASSED before the cut-off, meaning the delivery was already
/// created as an order, which can still be cancelled from Order Detail.
enum SkipOutcome { cancelled, cutoffPassed, alreadyOrder, failed }

/// MA-146 FR-8 — a subscription's next delivery that isn't an order yet.
class ScheduledDeliveryCubit extends Cubit<ScheduledDeliveryState> {
  ScheduledDeliveryCubit({
    required SubscriptionRepository subscriptionRepository,
    required OrderRepository orderRepository,
    required CatalogRepository catalogRepository,
    required this.subscriptionId,
    this._initial,
    Clock? clock,
  }) : _subscriptions = subscriptionRepository,
       _orders = orderRepository,
       _catalog = catalogRepository,
       _clock = clock ?? DateTime.now,
       super(const ScheduledDeliveryLoading());

  final SubscriptionRepository _subscriptions;
  final OrderRepository _orders;
  final CatalogRepository _catalog;
  final ScheduledEntry? _initial;
  final Clock _clock;
  final String subscriptionId;

  /// The entry from My Orders is used for the first load only. After that
  /// (e.g. Retry after a failed refresh) it may be stale, so always fetch.
  bool _initialUsed = false;

  /// The delivery date last shown to the customer, so a fetch after an error
  /// can still tell them it moved. Null until something has been shown.
  DateTime? _shownDate;

  /// First load: with an entry from My Orders, no subscription call;
  /// otherwise (deep link, app restart) fetch by id, with no change notice.
  /// Retry: always fetches, compared against the last date shown.
  Future<void> load() async {
    emit(const ScheduledDeliveryLoading());
    final initial = _initial;
    if (!_initialUsed && initial != null && initial.subscriptionId == subscriptionId) {
      _initialUsed = true;
      await _emitLoaded(initial, const NoChange());
      return;
    }
    _initialUsed = true;
    await _fetch(shownDate: _shownDate);
  }

  Future<void> refresh({bool quiet = false}) => _fetch(shownDate: _shownDate, quiet: quiet);

  bool _cancelling = false;

  /// MA-155 FR-5 — cancels the shown delivery through Subscription Service's
  /// Skip. Null (and no call) unless loaded, or while one is in flight. A
  /// CUTOFF_PASSED answer refreshes, which flags a delivery that became an
  /// order (`BecameOrder`).
  Future<SkipOutcome?> cancelDelivery() async {
    final current = state;
    if (current is! ScheduledDeliveryLoaded || _cancelling) return null;
    _cancelling = true;
    final date = current.entry.date;
    try {
      await _subscriptions.skip(subscriptionId, date);
      return SkipOutcome.cancelled;
    } on ApiException catch (e) {
      if (e.errorCode != 'CUTOFF_PASSED') return SkipOutcome.failed;
      final outcome = _clock().isBefore(deliveryCutoff(date))
          ? SkipOutcome.alreadyOrder
          : SkipOutcome.cutoffPassed;
      await refresh(quiet: true);
      return outcome;
    } catch (_) {
      return SkipOutcome.failed;
    } finally {
      _cancelling = false;
    }
  }

  Future<void> _fetch({required DateTime? shownDate, bool quiet = false}) async {
    try {
      final sub = await _subscriptions.get(subscriptionId);
      final entries = scheduledEntries([sub], const [], istToday(_clock));
      if (entries.isEmpty) {
        if (!isClosed) emit(const ScheduledDeliveryGone());
        return;
      }
      final entry = entries.single;
      final ScheduleChange change = (shownDate == null || isSameDate(shownDate, entry.date))
          ? const NoChange()
          : await _whyMoved(shownDate);
      await _emitLoaded(entry, change, quiet: quiet);
    } catch (_) {
      if (!isClosed) emit(const ScheduledDeliveryError());
    }
  }

  /// Only an order for the shown date means "it became an order"; skips,
  /// edits and pauses move the date too. A failed lookup is "not found".
  Future<ScheduleChange> _whyMoved(DateTime shownDate) async {
    try {
      final page = await _orders.listMine();
      for (final o in page.items) {
        if (o.subscriptionId == subscriptionId && isSameDate(o.deliveryDate, shownDate)) {
          return BecameOrder(o.orderId);
        }
      }
    } catch (_) {
      // fall through
    }
    return const DateChanged();
  }

  Future<void> _emitLoaded(
    ScheduledEntry entry,
    ScheduleChange change, {
    bool quiet = false,
  }) async {
    final products = await resolveProducts(_catalog, [entry.productId]);
    if (isClosed) return;
    _shownDate = entry.date;
    emit(ScheduledDeliveryLoaded(entry, products[entry.productId], change: change, quiet: quiet));
  }
}
