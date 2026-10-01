import 'package:equatable/equatable.dart';

import '../../catalog/models/product.dart';
import '../../subscriptions/models/subscription_view.dart';
import '../domain/order_buckets.dart';
import '../models/order_entry.dart';
import '../models/order_summary.dart';

enum SourceStatus { loading, loaded, failed }

enum PagingStatus { idle, loading, failed }

class MyOrdersState extends Equatable {
  const MyOrdersState({
    required this.today,
    this.ordersStatus = SourceStatus.loading,
    this.subscriptionsStatus = SourceStatus.loading,
    this.orders = const [],
    this.nextCursor,
    this.subscriptions = const [],
    this.products = const {},
    this.pagingStatus = PagingStatus.idle,
    this.refreshFailedCount = 0,
  });

  /// IST today, fixed when the state is built (from the bloc's clock).
  final DateTime today;
  final SourceStatus ordersStatus;
  final SourceStatus subscriptionsStatus;

  /// Every loaded page, deduplicated by `orderId`, in API order.
  final List<OrderSummary> orders;
  final String? nextCursor;
  final List<SubscriptionView> subscriptions;

  /// Product lookups by id. A key mapped to `null` means the lookup failed
  /// (render "Item"); a missing key means not resolved yet.
  final Map<String, Product?> products;
  final PagingStatus pagingStatus;

  /// Bumped each time a pull-to-refresh fails, so the screen can show a
  /// SnackBar once per failure.
  final int refreshFailedCount;

  bool get isInitialLoading =>
      ordersStatus == SourceStatus.loading &&
      subscriptionsStatus == SourceStatus.loading &&
      orders.isEmpty &&
      subscriptions.isEmpty;

  bool get bothFailed =>
      ordersStatus == SourceStatus.failed && subscriptionsStatus == SourceStatus.failed;

  bool get hasMorePast => nextCursor != null;

  OrderBuckets get buckets => bucketOrders(orders, today);

  List<ScheduledEntry> get scheduled => subscriptionsStatus == SourceStatus.loaded
      ? scheduledEntries(subscriptions, orders, today)
      : const [];

  List<DayGroup> get upcomingGroups => groupByDate([
    ...buckets.upcoming.map(OrderedEntry.new),
    ...scheduled,
  ], ascending: true);

  List<DayGroup> get pastGroups =>
      groupByDate(buckets.past.map(OrderedEntry.new).toList(), ascending: false);

  MyOrdersState copyWith({
    DateTime? today,
    SourceStatus? ordersStatus,
    SourceStatus? subscriptionsStatus,
    List<OrderSummary>? orders,
    String? nextCursor,
    bool clearNextCursor = false,
    List<SubscriptionView>? subscriptions,
    Map<String, Product?>? products,
    PagingStatus? pagingStatus,
    int? refreshFailedCount,
  }) => MyOrdersState(
    today: today ?? this.today,
    ordersStatus: ordersStatus ?? this.ordersStatus,
    subscriptionsStatus: subscriptionsStatus ?? this.subscriptionsStatus,
    orders: orders ?? this.orders,
    nextCursor: clearNextCursor ? null : (nextCursor ?? this.nextCursor),
    subscriptions: subscriptions ?? this.subscriptions,
    products: products ?? this.products,
    pagingStatus: pagingStatus ?? this.pagingStatus,
    refreshFailedCount: refreshFailedCount ?? this.refreshFailedCount,
  );

  @override
  List<Object?> get props => [
    today,
    ordersStatus,
    subscriptionsStatus,
    orders,
    nextCursor,
    subscriptions,
    products,
    pagingStatus,
    refreshFailedCount,
  ];
}
