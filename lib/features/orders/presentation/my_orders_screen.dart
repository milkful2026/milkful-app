import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';

import '../../../core/utils/ist_clock.dart';
import '../../catalog/data/catalog_repository.dart';
import '../../subscriptions/data/subscription_repository.dart';
import '../bloc/my_orders_bloc.dart';
import '../bloc/my_orders_event.dart';
import '../bloc/my_orders_state.dart';
import '../data/order_repository.dart';
import '../domain/order_buckets.dart';
import 'widgets/day_group_card.dart';
import 'widgets/today_section.dart';

/// MA-145 — `/orders`, pushed from Profile (MA-147). One scroll view:
/// failure banners, Today's Delivery, then an Upcoming / Past Orders tab
/// bar whose selection picks the list below it — so pull-to-refresh and
/// Past pagination work on a single scrollable.
class MyOrdersScreen extends StatelessWidget {
  const MyOrdersScreen({super.key, this.clock});

  /// Tests pin "today"; production uses the wall clock.
  final Clock? clock;

  @override
  Widget build(BuildContext context) {
    return BlocProvider(
      create: (context) => MyOrdersBloc(
        orderRepository: context.read<OrderRepository>(),
        subscriptionRepository: context.read<SubscriptionRepository>(),
        catalogRepository: context.read<CatalogRepository>(),
        clock: clock,
      )..add(const MyOrdersOpened()),
      child: const _MyOrdersView(),
    );
  }
}

class _MyOrdersView extends StatefulWidget {
  const _MyOrdersView();

  @override
  State<_MyOrdersView> createState() => _MyOrdersViewState();
}

class _MyOrdersViewState extends State<_MyOrdersView> with SingleTickerProviderStateMixin {
  late final TabController _tabs = TabController(length: 2, vsync: this)
    ..addListener(_onTabChanged);

  /// A short Past list never scrolls, so opening the tab also asks for the
  /// next page when there are only a few past days loaded.
  void _onTabChanged() {
    setState(() {});
    if (!_onPast || _tabs.indexIsChanging) return;
    final state = context.read<MyOrdersBloc>().state;
    if (state.hasMorePast &&
        state.pagingStatus == PagingStatus.idle &&
        state.pastGroups.length < 5) {
      context.read<MyOrdersBloc>().add(const PastPageRequested());
    }
  }

  bool get _onPast => _tabs.index == 1;

  @override
  void dispose() {
    _tabs.dispose();
    super.dispose();
  }

  Future<void> _refresh(BuildContext context) {
    final event = MyOrdersRefreshed();
    context.read<MyOrdersBloc>().add(event);
    return event.completer.future;
  }

  bool _onScroll(ScrollNotification n, MyOrdersState state) {
    if (_onPast &&
        state.hasMorePast &&
        state.pagingStatus == PagingStatus.idle &&
        n.metrics.extentAfter < 300) {
      context.read<MyOrdersBloc>().add(const PastPageRequested());
    }
    return false;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('My Orders')),
      body: BlocConsumer<MyOrdersBloc, MyOrdersState>(
        listenWhen: (a, b) => b.refreshFailedCount > a.refreshFailedCount,
        listener: (context, state) => ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("Couldn't refresh. Try again.")),
        ),
        builder: (context, state) {
          if (state.isInitialLoading) return const _Skeleton();
          if (state.bothFailed) {
            return _FullError(
              onRetry: () => context.read<MyOrdersBloc>().add(const RetryFailedSources()),
            );
          }
          return RefreshIndicator(
            onRefresh: () => _refresh(context),
            child: NotificationListener<ScrollNotification>(
              onNotification: (n) => _onScroll(n, state),
              child: CustomScrollView(
                physics: const AlwaysScrollableScrollPhysics(),
                slivers: [
                  ..._banners(context, state),
                  SliverToBoxAdapter(
                    child: TodaySection(
                      orders: state.buckets.today,
                      products: state.products,
                      ordersFailed: state.ordersStatus == SourceStatus.failed,
                    ),
                  ),
                  SliverPersistentHeader(pinned: true, delegate: _TabBarHeader(_tabs)),
                  const SliverToBoxAdapter(child: SizedBox(height: 12)),
                  ...(_onPast ? _pastSlivers(context, state) : _upcomingSlivers(context, state)),
                  const SliverToBoxAdapter(child: SizedBox(height: 24)),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  List<Widget> _banners(BuildContext context, MyOrdersState state) {
    void retry() => context.read<MyOrdersBloc>().add(const RetryFailedSources());
    return [
      if (state.ordersStatus == SourceStatus.failed)
        SliverToBoxAdapter(
          child: _Banner(text: "Some orders couldn't be loaded.", onRetry: retry),
        ),
      if (state.subscriptionsStatus == SourceStatus.failed)
        SliverToBoxAdapter(
          child: _Banner(
            text: "Upcoming subscription deliveries couldn't be loaded.",
            onRetry: retry,
          ),
        ),
    ];
  }

  List<Widget> _upcomingSlivers(BuildContext context, MyOrdersState state) {
    final groups = state.upcomingGroups;
    if (groups.isEmpty) {
      // Empty only when every feeding source loaded (MA-145 empty-state rule).
      final allLoaded =
          state.ordersStatus == SourceStatus.loaded &&
          state.subscriptionsStatus == SourceStatus.loaded;
      return [
        SliverToBoxAdapter(
          child: allLoaded
              ? _EmptyMessage(
                  text: 'No upcoming deliveries',
                  action: TextButton(
                    onPressed: () => context.go('/catalog'),
                    child: const Text('Browse products'),
                  ),
                )
              : const _EmptyMessage(text: "Couldn't load upcoming orders."),
        ),
      ];
    }
    return [_groupList(groups, state, upcoming: true)];
  }

  List<Widget> _pastSlivers(BuildContext context, MyOrdersState state) {
    final groups = state.pastGroups;
    if (state.ordersStatus == SourceStatus.failed) {
      return [const SliverToBoxAdapter(child: _EmptyMessage(text: "Couldn't load past orders."))];
    }
    if (groups.isEmpty && !state.hasMorePast) {
      return [const SliverToBoxAdapter(child: _EmptyMessage(text: 'No past orders yet'))];
    }
    return [
      _groupList(groups, state, upcoming: false),
      SliverToBoxAdapter(child: _pagingFooter(context, state)),
    ];
  }

  Widget _groupList(List<DayGroup> groups, MyOrdersState state, {required bool upcoming}) =>
      SliverList.builder(
        itemCount: groups.length,
        itemBuilder: (context, i) => DayGroupCard(
          group: groups[i],
          today: state.today,
          products: state.products,
          upcoming: upcoming,
        ),
      );

  Widget _pagingFooter(BuildContext context, MyOrdersState state) {
    switch (state.pagingStatus) {
      case PagingStatus.loading:
        return const Padding(
          padding: EdgeInsets.all(16),
          child: Center(child: CircularProgressIndicator()),
        );
      case PagingStatus.failed:
        return Center(
          child: TextButton(
            key: const Key('orders.past.loadMoreRetry'),
            onPressed: () => context.read<MyOrdersBloc>().add(const PastPageRequested()),
            child: const Text("Couldn't load more. Retry"),
          ),
        );
      case PagingStatus.idle:
        return const SizedBox.shrink();
    }
  }
}

class _TabBarHeader extends SliverPersistentHeaderDelegate {
  _TabBarHeader(this.controller);

  final TabController controller;

  @override
  double get minExtent => 48;

  @override
  double get maxExtent => 48;

  @override
  Widget build(BuildContext context, double shrinkOffset, bool overlapsContent) => ColoredBox(
    color: Theme.of(context).scaffoldBackgroundColor,
    child: TabBar(
      controller: controller,
      tabs: const [
        Tab(text: 'Upcoming'),
        Tab(text: 'Past Orders'),
      ],
    ),
  );

  @override
  bool shouldRebuild(_TabBarHeader old) => old.controller != controller;
}

class _Banner extends StatelessWidget {
  const _Banner({required this.text, required this.onRetry});

  final String text;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 8, 16, 0),
      padding: const EdgeInsets.only(left: 14),
      decoration: BoxDecoration(
        color: scheme.errorContainer,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          Expanded(
            child: Text(text, style: TextStyle(color: scheme.onErrorContainer)),
          ),
          TextButton(onPressed: onRetry, child: const Text('Retry')),
        ],
      ),
    );
  }
}

class _EmptyMessage extends StatelessWidget {
  const _EmptyMessage({required this.text, this.action});

  final String text;
  final Widget? action;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
    child: Column(
      children: [
        Text(text, textAlign: TextAlign.center, style: Theme.of(context).textTheme.bodyMedium),
        ?action,
      ],
    ),
  );
}

class _FullError extends StatelessWidget {
  const _FullError({required this.onRetry});

  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) => Center(
    child: Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Text("Couldn't load your orders."),
          const SizedBox(height: 12),
          FilledButton(onPressed: onRetry, child: const Text('Retry')),
        ],
      ),
    ),
  );
}

class _Skeleton extends StatelessWidget {
  const _Skeleton();

  @override
  Widget build(BuildContext context) {
    final color = Theme.of(context).colorScheme.surfaceContainerHigh;
    Widget block(double h) => Container(
      height: h,
      margin: const EdgeInsets.fromLTRB(16, 0, 16, 12),
      decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(24)),
    );
    return Semantics(
      label: 'Loading orders',
      child: ListView(
        padding: const EdgeInsets.only(top: 16),
        children: [block(88), block(88), block(48), block(96), block(96)],
      ),
    );
  }
}
