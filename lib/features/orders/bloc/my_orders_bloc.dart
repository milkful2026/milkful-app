import 'package:bloc_concurrency/bloc_concurrency.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../core/utils/ist_clock.dart';
import '../../catalog/data/catalog_repository.dart';
import '../../catalog/models/product.dart';
import '../../subscriptions/data/subscription_repository.dart';
import '../../subscriptions/models/subscription_view.dart';
import '../data/order_repository.dart';
import '../models/order_summary.dart';
import '../models/orders_page.dart';
import 'my_orders_event.dart';
import 'my_orders_state.dart';

/// MA-145 — loads orders and subscriptions independently (one failing
/// never blanks the other), resolves product details through a cache, and
/// pages Past Orders on demand.
class MyOrdersBloc extends Bloc<MyOrdersEvent, MyOrdersState> {
  MyOrdersBloc({
    required OrderRepository orderRepository,
    required SubscriptionRepository subscriptionRepository,
    required CatalogRepository catalogRepository,
    Clock? clock,
  }) : _orders = orderRepository,
       _subscriptions = subscriptionRepository,
       _catalog = catalogRepository,
       _clock = clock ?? DateTime.now,
       super(MyOrdersState(today: istToday(clock ?? DateTime.now))) {
    on<MyOrdersOpened>((event, emit) => _load(emit, orders: true, subscriptions: true));
    on<MyOrdersRefreshed>(_onRefreshed);
    on<RetryFailedSources>(
      (event, emit) => _load(
        emit,
        orders: state.ordersStatus == SourceStatus.failed,
        subscriptions: state.subscriptionsStatus == SourceStatus.failed,
      ),
    );
    on<PastPageRequested>(_onPastPageRequested, transformer: droppable());
  }

  static const pageSize = 50;

  final OrderRepository _orders;
  final SubscriptionRepository _subscriptions;
  final CatalogRepository _catalog;
  final Clock _clock;

  /// Bumped by every (re)load, so a Past page that started before it is
  /// discarded when it returns (a refresh replaces the orders list).
  int _generation = 0;
  final Set<String> _requestedProducts = {};

  Future<void> _onRefreshed(MyOrdersRefreshed event, Emitter<MyOrdersState> emit) async {
    try {
      final ok = await _load(emit, orders: true, subscriptions: true, keepOnFailure: true);
      if (!ok) emit(state.copyWith(refreshFailedCount: state.refreshFailedCount + 1));
    } finally {
      if (!event.completer.isCompleted) event.completer.complete();
    }
  }

  /// Returns false if any requested source failed. With [keepOnFailure]
  /// (pull-to-refresh), a failed source keeps its previous data and status.
  Future<bool> _load(
    Emitter<MyOrdersState> emit, {
    required bool orders,
    required bool subscriptions,
    bool keepOnFailure = false,
  }) async {
    if (!orders && !subscriptions) return true;
    final generation = ++_generation;
    emit(
      state.copyWith(
        today: istToday(_clock),
        ordersStatus: orders && !keepOnFailure ? SourceStatus.loading : null,
        subscriptionsStatus: subscriptions && !keepOnFailure ? SourceStatus.loading : null,
        pagingStatus: orders ? PagingStatus.idle : null,
      ),
    );

    final results = await Future.wait([
      orders ? _attempt(() => _orders.listMine(limit: pageSize)) : Future.value(null),
      subscriptions ? _attempt(_subscriptions.list) : Future.value(null),
    ]);
    if (isClosed) return false;

    var ok = true;
    var next = state;
    if (orders) {
      final page = results[0];
      if (page is OrdersPage) {
        next = next.copyWith(
          ordersStatus: SourceStatus.loaded,
          orders: _dedupe(page.items),
          nextCursor: page.nextCursor,
          clearNextCursor: page.nextCursor == null,
        );
      } else {
        ok = false;
        if (!keepOnFailure || next.ordersStatus != SourceStatus.loaded) {
          next = next.copyWith(ordersStatus: SourceStatus.failed);
        }
      }
    }
    if (subscriptions) {
      final subs = results[1];
      if (subs is List<SubscriptionView>) {
        next = next.copyWith(subscriptionsStatus: SourceStatus.loaded, subscriptions: subs);
      } else {
        ok = false;
        if (!keepOnFailure || next.subscriptionsStatus != SourceStatus.loaded) {
          next = next.copyWith(subscriptionsStatus: SourceStatus.failed);
        }
      }
    }
    if (generation == _generation) emit(next);
    await _resolveProducts(emit);
    return ok;
  }

  Future<void> _onPastPageRequested(
    PastPageRequested event,
    Emitter<MyOrdersState> emit,
  ) async {
    final cursor = state.nextCursor;
    if (cursor == null || state.ordersStatus != SourceStatus.loaded) return;
    final generation = _generation;
    emit(state.copyWith(pagingStatus: PagingStatus.loading));
    final page = await _attempt(() => _orders.listMine(cursor: cursor, limit: pageSize));
    if (isClosed || generation != _generation) return; // a refresh replaced the list
    if (page is! OrdersPage) {
      emit(state.copyWith(pagingStatus: PagingStatus.failed));
      return;
    }
    emit(
      state.copyWith(
        orders: _dedupe([...state.orders, ...page.items]),
        nextCursor: page.nextCursor,
        clearNextCursor: page.nextCursor == null,
        pagingStatus: PagingStatus.idle,
      ),
    );
    await _resolveProducts(emit);
  }

  /// One Catalog call per distinct product for the bloc's lifetime, in
  /// parallel; a failed lookup is cached as null and never fails the screen.
  Future<void> _resolveProducts(Emitter<MyOrdersState> emit) async {
    final ids = <String>{
      for (final o in state.orders)
        for (final item in o.items) item.productId,
      for (final s in state.scheduled) s.productId,
    }.where((id) => !_requestedProducts.contains(id)).toList();
    if (ids.isEmpty) return;
    _requestedProducts.addAll(ids);
    final fetched = await Future.wait(
      ids.map((id) async {
        try {
          return MapEntry<String, Product?>(id, await _catalog.getProduct(id));
        } catch (_) {
          return MapEntry<String, Product?>(id, null);
        }
      }),
    );
    if (isClosed || emit.isDone) return;
    emit(state.copyWith(products: {...state.products, ...Map.fromEntries(fetched)}));
  }

  static Future<Object?> _attempt(Future<Object?> Function() call) async {
    try {
      return await call();
    } catch (_) {
      return null;
    }
  }

  static List<OrderSummary> _dedupe(List<OrderSummary> orders) {
    final seen = <String>{};
    return [
      for (final o in orders)
        if (seen.add(o.orderId)) o,
    ];
  }
}
