import 'package:flutter/gestures.dart' show PointerDeviceKind;
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';

import '../../auth/bloc/auth_bloc.dart';
import '../../auth/bloc/auth_event.dart';
import '../../auth/bloc/auth_state.dart';
import '../../catalog/bloc/catalog_bloc.dart';
import '../../catalog/bloc/catalog_event.dart';
import '../../catalog/bloc/catalog_state.dart';
import '../../catalog/data/catalog_repository.dart';
import '../../catalog/models/category.dart';
import '../../catalog/models/product.dart';
import '../../catalog/presentation/widgets/promo_banner.dart';
import '../../onboarding/bloc/registration_bloc.dart';
import '../../onboarding/bloc/registration_event.dart';
import '../../onboarding/bloc/registration_state.dart';

/// MA-1's spec explicitly puts a real Home (catalog, cart, subscriptions)
/// out of scope; MA-21 adds the role-aware indicator (FR-4) and a logout
/// entry point (FR-5) on top of the placeholder MA-1 left here; MA-115
/// added the real catalog.
///
/// This screen has since absorbed what used to be three separate
/// onboarding steps:
/// - **Name**: no longer collected from the user at all — the old dedicated
///   screen, and later the inline Home-screen prompt that replaced it, are
///   both gone. Registration now submits automatically as soon as
///   serviceability is confirmed (see registration_bloc.dart's
///   `_submitRegistration`), with a placeholder name the UI never shows.
/// - **Consent**: no longer a gated step at all — Terms & Privacy
///   acceptance is implicit (Welcome screen's own "by continuing you
///   agree..." footer), so registration always submits with both marked
///   accepted.
/// - **Delivery slot**: [_DeliverySlotPicker] below replaces the old
///   dedicated slot-selection screen with a calendar-style strip, usable
///   any time (not just mid-registration) — see its own doc comment for
///   the real gap this has relative to the reference mockup (no backend
///   endpoint exists yet to persist a slot preference outside of
///   registration's own optional, one-time `preferredSlotId`).
///
/// Body layout now follows the Freshoza landing-page reference mockup
/// (location header, search entry, promo banner, categories, bestsellers,
/// bento deals grid) rather than embedding [CatalogScreen] directly — the
/// full browse/search/filter/sort experience [CatalogScreen] already
/// provides now lives one tap away, at `/catalog` (see [CatalogPage]),
/// reached via "View All", a category tile, or the search bar.
class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  Future<void> _confirmLogout(BuildContext context) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Log out?'),
        content: const Text("You'll need to verify your number again to sign back in."),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Log out'),
          ),
        ],
      ),
    );
    if (confirmed == true && context.mounted) {
      context.read<AuthBloc>().add(const LogoutRequested());
    }
  }

  @override
  Widget build(BuildContext context) {
    return BlocProvider(
      // CatalogRepository itself is provided app-wide from main.dart
      // (alongside PlacesRepository) — only the bloc is scoped here, since
      // its loading/search/filter state shouldn't outlive this screen the
      // way the repository/HTTP client should. Started eagerly (rather than
      // from a child's initState, the way CatalogScreen does it for its own
      // standalone instance at `/catalog`) since nothing embedded here owns
      // an initState of its own to hang the dispatch off of.
      create: (context) => CatalogBloc(repository: context.read())..add(const CatalogStarted()),
      child: BlocListener<RegistrationBloc, RegistrationState>(
        listenWhen: (previous, current) => previous.phase != current.phase,
        listener: (context, state) {
          if (state.phase == RegistrationPhase.submitFailed) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text(state.errorMessage ?? 'Something went wrong. Please try again.'),
                action: SnackBarAction(
                  label: 'Retry',
                  onPressed: () =>
                      context.read<RegistrationBloc>().add(const RegistrationRetryRequested()),
                ),
              ),
            );
            return;
          }
          if (state.phase != RegistrationPhase.success) return;
          // AuthBloc's own profile lookup was skipped at OTP-verify time
          // (the profile didn't exist yet) — refresh it now so the rest of
          // Home picks up the real accountType.
          context.read<AuthBloc>().add(const ProfileRefreshRequested());
          final zoneId = state.draft.zoneId;
          if (zoneId != null) {
            context.read<RegistrationBloc>().add(DeliverySlotsRequested(zoneId));
          }
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(_walletMessage(state.result?.walletStatus))),
          );
        },
        child: Scaffold(
          body: SafeArea(
            child: Column(
              children: [
                _LandingHeader(onLogout: () => _confirmLogout(context)),
                Expanded(
                  child: BlocBuilder<CatalogBloc, CatalogState>(
                    builder: (context, catalogState) {
                      return SingleChildScrollView(
                        padding: const EdgeInsets.only(bottom: 96),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            BlocBuilder<AuthBloc, AuthState>(
                              builder: (context, state) {
                                final accountType =
                                    state is AuthAuthenticated ? state.accountType : null;
                                if (accountType != 'B2B') return const SizedBox.shrink();
                                return const Padding(
                                  padding: EdgeInsets.fromLTRB(16, 12, 16, 0),
                                  child: Align(
                                    alignment: Alignment.centerLeft,
                                    child: Chip(label: Text('B2B account')),
                                  ),
                                );
                              },
                            ),
                            _SearchEntry(onTap: () => context.push('/catalog')),
                            PromoBanner(onShopNow: () => context.push('/catalog')),
                            const _DeliverySlotPicker(),
                            _CategoriesSection(
                              categories: catalogState.categories,
                              onViewAll: () => context.push('/catalog'),
                            ),
                            _BestsellersSection(products: catalogState.products),
                            _PureMilkSection(categories: catalogState.categories),
                            const _MorningFreshnessSection(),
                          ],
                        ),
                      );
                    },
                  ),
                ),
              ],
            ),
          ),
          bottomNavigationBar: const _HomeBottomNav(),
          floatingActionButton: FloatingActionButton(
            key: const Key('cart-fab'),
            onPressed: () => context.push('/cart'),
            child: const Icon(Icons.shopping_basket_outlined),
          ),
        ),
      ),
    );
  }

  String _walletMessage(String? walletStatus) => switch (walletStatus) {
        'PENDING' => 'Welcome to Freshoza! Your wallet is being set up.',
        'FAILED' => 'Welcome to Freshoza! Wallet setup incomplete — contact support if this persists.',
        _ => 'Welcome to Freshoza! Your wallet is ready.',
      };
}

/// Fixed (non-scrolling) top bar: current delivery city — sourced from the
/// in-progress/most-recent registration draft's address, the only place
/// this app tracks one — plus notifications (present per mockup, not
/// wired — no such feature/backend exists) and logout.
class _LandingHeader extends StatelessWidget {
  const _LandingHeader({required this.onLogout});

  final VoidCallback onLogout;

  @override
  Widget build(BuildContext context) {
    final primary = Theme.of(context).colorScheme.primary;
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 12, 8, 12),
      decoration: BoxDecoration(
        color: Colors.white,
        boxShadow: [
          BoxShadow(color: Colors.black.withValues(alpha: 0.06), blurRadius: 16, offset: const Offset(0, 4)),
        ],
      ),
      child: Row(
        children: [
          Icon(Icons.location_on, color: primary),
          const SizedBox(width: 4),
          Expanded(
            child: BlocBuilder<RegistrationBloc, RegistrationState>(
              builder: (context, state) {
                final city = state.draft.address?.city;
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text('Delivering to', style: TextStyle(fontSize: 11, color: Colors.grey.shade600)),
                    Text(
                      city == null || city.isEmpty ? 'Set your location' : city,
                      style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: primary),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                );
              },
            ),
          ),
          IconButton(
            key: const Key('notification-action'),
            icon: const Icon(Icons.notifications_outlined),
            tooltip: 'Notifications',
            onPressed: null,
          ),
          IconButton(
            key: const Key('logout-action'),
            icon: const Icon(Icons.logout),
            tooltip: 'Log out',
            onPressed: onLogout,
          ),
        ],
      ),
    );
  }
}

/// Tapping in opens the full search/browse experience at `/catalog`
/// ([CatalogPage]) instead of filtering in place — Home's landing sections
/// (bestsellers, bento deals) aren't a search results surface, and
/// [CatalogScreen] already owns the real category rail/filter/sort chrome
/// that a results view needs.
class _SearchEntry extends StatelessWidget {
  const _SearchEntry({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
      child: Material(
        color: Colors.white,
        borderRadius: BorderRadius.circular(999),
        elevation: 1,
        child: InkWell(
          key: const Key('home-search-entry'),
          borderRadius: BorderRadius.circular(999),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
            child: Row(
              children: [
                Icon(Icons.search, color: Colors.grey.shade500),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Search fresh organic milk, ghee...',
                    style: TextStyle(color: Colors.grey.shade500),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Calendar-style delivery-slot picker, replacing the old dedicated Slot
/// screen. The date strip itself is presentational (this app has no
/// subscription/recurring-order concept to attach real per-day state to —
/// unlike the reference mockup, which is from a subscription-delivery
/// app); the slot chips below it are real, backed by the same
/// `GET /delivery/slots` data the old wizard step used.
///
/// Known gap: there's no backend endpoint to persist a slot preference
/// outside of registration's own one-time, optional `preferredSlotId`, so
/// picking a chip here is local-only for now (flagged, not hidden) —
/// selecting a different date/slot after registration has nothing to save
/// it to yet.
class _DeliverySlotPicker extends StatefulWidget {
  const _DeliverySlotPicker();

  @override
  State<_DeliverySlotPicker> createState() => _DeliverySlotPickerState();
}

class _DeliverySlotPickerState extends State<_DeliverySlotPicker> {
  int _selectedDayOffset = 0;
  String? _selectedSlotId;

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<RegistrationBloc, RegistrationState>(
      builder: (context, state) {
        if (state.draft.zoneId == null && state.availableSlots.isEmpty) {
          return const SizedBox.shrink();
        }
        final theme = Theme.of(context);
        final today = DateTime.now();
        return Padding(
          padding: const EdgeInsets.symmetric(vertical: 8),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Text('Delivery schedule', style: theme.textTheme.labelLarge),
              ),
              const SizedBox(height: 8),
              SizedBox(
                key: const Key('delivery-date-strip'),
                height: 64,
                child: ListView.builder(
                  scrollDirection: Axis.horizontal,
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  itemCount: 7,
                  itemBuilder: (context, index) {
                    final date = today.add(Duration(days: index));
                    final selected = index == _selectedDayOffset;
                    return Padding(
                      key: Key('delivery-date-$index'),
                      padding: const EdgeInsets.symmetric(horizontal: 4),
                      child: InkWell(
                        borderRadius: BorderRadius.circular(12),
                        onTap: () => setState(() => _selectedDayOffset = index),
                        child: Container(
                          width: 48,
                          decoration: BoxDecoration(
                            color: selected ? theme.colorScheme.primary : Colors.white,
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(
                              color: selected ? theme.colorScheme.primary : Colors.grey.shade300,
                            ),
                          ),
                          alignment: Alignment.center,
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Text(
                                _weekdayShort(date.weekday),
                                style: TextStyle(
                                  fontSize: 11,
                                  color: selected ? Colors.white : Colors.grey.shade600,
                                ),
                              ),
                              Text(
                                '${date.day}',
                                style: TextStyle(
                                  fontWeight: FontWeight.bold,
                                  color: selected ? Colors.white : Colors.black87,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    );
                  },
                ),
              ),
              if (state.availableSlots.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
                  child: Wrap(
                    spacing: 8,
                    children: [
                      for (final slot in state.availableSlots.where((s) => s.available))
                        ChoiceChip(
                          key: Key('delivery-slot-${slot.id}'),
                          label: Text(slot.label),
                          selected: _selectedSlotId == slot.id,
                          onSelected: (_) => setState(() => _selectedSlotId = slot.id),
                        ),
                    ],
                  ),
                ),
            ],
          ),
        );
      },
    );
  }

  String _weekdayShort(int weekday) => const [
        'Mon',
        'Tue',
        'Wed',
        'Thu',
        'Fri',
        'Sat',
        'Sun',
      ][weekday - 1];
}

/// First 4 real categories, mirroring the mockup's fixed 4-across grid —
/// "View All" (and every tile, for a one-tap shortcut) opens the full
/// category rail at `/catalog` rather than reproducing it here.
class _CategoriesSection extends StatelessWidget {
  const _CategoriesSection({required this.categories, required this.onViewAll});

  final List<Category> categories;
  final VoidCallback onViewAll;

  @override
  Widget build(BuildContext context) {
    final shown = categories.take(4).toList();
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 24, 16, 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'Categories',
                style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold),
              ),
              TextButton(
                key: const Key('categories-view-all'),
                onPressed: onViewAll,
                child: const Text('View All'),
              ),
            ],
          ),
          if (shown.isNotEmpty)
            Row(
              children: [
                for (final category in shown) _CategoryTile(category: category, onTap: onViewAll),
              ],
            ),
        ],
      ),
    );
  }
}

/// Mirrors `CatalogScreen`'s own icon-name → [IconData] mapping — kept as a
/// separate copy rather than a shared export since the two live in
/// different features and this is the full extent of the duplication.
IconData _categoryIcon(String? iconName) => switch (iconName) {
      'milk' => Icons.local_drink,
      'curd' => Icons.icecream_outlined,
      'paneer' => Icons.layers,
      'ghee' => Icons.opacity,
      'veggies' => Icons.eco,
      _ => Icons.storefront,
    };

class _CategoryTile extends StatelessWidget {
  const _CategoryTile({required this.category, required this.onTap});

  final Category category;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final primary = Theme.of(context).colorScheme.primary;
    return Expanded(
      child: InkWell(
        key: Key('category-tile-${category.id}'),
        borderRadius: BorderRadius.circular(40),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 8),
          child: Column(
            children: [
              CircleAvatar(
                radius: 28,
                backgroundColor: primary.withValues(alpha: 0.1),
                child: Icon(_categoryIcon(category.iconName), color: primary),
              ),
              const SizedBox(height: 6),
              Text(
                category.name,
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.labelSmall,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Real product data (whatever's currently loaded for the default
/// category) presented as "Bestsellers" — this backend has no dedicated
/// bestseller/merchandising concept of its own, so this is a reasonable
/// stand-in rather than a fabricated one, in the same spirit as
/// [_DeliverySlotPicker]'s own documented gaps.
class _BestsellersSection extends StatelessWidget {
  const _BestsellersSection({required this.products});

  final List<Product> products;

  @override
  Widget build(BuildContext context) {
    if (products.isEmpty) return const SizedBox.shrink();
    return _ProductRail(
      title: 'Bestsellers',
      badgeLabel: 'Most Loved',
      products: products.take(6).toList(),
      keyPrefix: 'bestseller',
    );
  }
}

/// The one real category whose name/icon identifies it as milk — shown as
/// its own curated rail below Bestsellers, the same "pick a category and
/// front it" idea as Bestsellers itself, just narrowed to a single
/// category instead of whatever's currently loaded. Renders nothing if no
/// category matches (e.g. this deployment's catalog has no milk category
/// at all) rather than showing an empty/misleading section.
class _PureMilkSection extends StatelessWidget {
  const _PureMilkSection({required this.categories});

  final List<Category> categories;

  @override
  Widget build(BuildContext context) {
    Category? milk;
    for (final category in categories) {
      if (category.iconName == 'milk' || category.name.toLowerCase().contains('milk')) {
        milk = category;
        break;
      }
    }
    if (milk == null) return const SizedBox.shrink();
    return _CategoryProductRail(
      key: ValueKey('pure-milk-rail-${milk.id}'),
      categoryId: milk.id,
      title: 'Pure Milk',
      badgeLabel: '100% Natural',
      keyPrefix: 'milk',
    );
  }
}

/// Fetches one category's products directly from [CatalogRepository] —
/// deliberately not routed through the shared [CatalogBloc] instance this
/// screen already has, since that bloc's `selectedCategoryId` drives the
/// Categories rail state elsewhere on this same screen; switching it just
/// to populate this rail would fight that. A plain one-shot repository
/// call, cached for this widget's lifetime, is simpler and matches how
/// this app already makes one-off calls outside a bloc (e.g.
/// AddressScreen's own PlacesRepository calls).
class _CategoryProductRail extends StatefulWidget {
  const _CategoryProductRail({
    super.key,
    required this.categoryId,
    required this.title,
    required this.badgeLabel,
    required this.keyPrefix,
  });

  final String categoryId;
  final String title;
  final String badgeLabel;
  final String keyPrefix;

  @override
  State<_CategoryProductRail> createState() => _CategoryProductRailState();
}

class _CategoryProductRailState extends State<_CategoryProductRail> {
  late Future<List<Product>> _future;

  @override
  void initState() {
    super.initState();
    _future = context.read<CatalogRepository>().getProducts(categoryId: widget.categoryId);
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<List<Product>>(
      future: _future,
      builder: (context, snapshot) {
        final products = snapshot.data ?? const <Product>[];
        if (products.isEmpty) return const SizedBox.shrink();
        return _ProductRail(
          title: widget.title,
          badgeLabel: widget.badgeLabel,
          products: products.take(6).toList(),
          keyPrefix: widget.keyPrefix,
        );
      },
    );
  }
}

/// Shared horizontal-scroll rail — title + badge pill above a row of
/// [_ProductCard]s. [ScrollConfiguration] opts into mouse/trackpad drag
/// (not just touch), matching this app's other horizontal strips
/// ([_DeliverySlotPicker]'s date strip, the category rail) so scrolling
/// works the same way on a desktop/web build as it does on a phone.
class _ProductRail extends StatelessWidget {
  const _ProductRail({
    required this.title,
    required this.badgeLabel,
    required this.products,
    required this.keyPrefix,
  });

  final String title;
  final String badgeLabel;
  final List<Product> products;
  final String keyPrefix;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 24, 0, 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(right: 16),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  title,
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold),
                ),
                Chip(
                  label: Text(badgeLabel),
                  backgroundColor: Theme.of(context).colorScheme.primary.withValues(alpha: 0.1),
                  labelStyle: TextStyle(
                    color: Theme.of(context).colorScheme.primary,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          SizedBox(
            key: Key('$keyPrefix-rail'),
            height: 284,
            child: ScrollConfiguration(
              behavior: _DragScrollBehavior(),
              child: ListView.builder(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.only(right: 16),
                itemCount: products.length,
                itemBuilder: (context, index) =>
                    _ProductCard(product: products[index], keyPrefix: keyPrefix),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _DragScrollBehavior extends MaterialScrollBehavior {
  @override
  Set<PointerDeviceKind> get dragDevices => {
        PointerDeviceKind.touch,
        PointerDeviceKind.mouse,
        PointerDeviceKind.trackpad,
      };
}

class _ProductCard extends StatefulWidget {
  const _ProductCard({required this.product, required this.keyPrefix});

  final Product product;
  final String keyPrefix;

  @override
  State<_ProductCard> createState() => _ProductCardState();
}

class _ProductCardState extends State<_ProductCard> {
  // Same local-only caveat as _DeliverySlotPickerState's slot chips — no
  // backend concept of a per-product subscription toggle exists yet.
  bool _subscribed = false;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final product = widget.product;
    return Container(
      key: Key('${widget.keyPrefix}-card-${product.id}'),
      width: 200,
      margin: const EdgeInsets.only(right: 12),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(color: Colors.black.withValues(alpha: 0.06), blurRadius: 16, offset: const Offset(0, 6)),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Stack(
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(14),
                child: SizedBox(
                  height: 100,
                  width: double.infinity,
                  child: product.imageUrl != null
                      ? Image.network(
                          product.imageUrl!,
                          fit: BoxFit.cover,
                          errorBuilder: (context, error, stackTrace) => _imageFallback(theme),
                        )
                      : Image.asset(
                          'assets/images/products/${product.id}.jpg',
                          fit: BoxFit.cover,
                          errorBuilder: (context, error, stackTrace) => _imageFallback(theme),
                        ),
                ),
              ),
              if (product.tag != null)
                Positioned(
                  top: 6,
                  left: 6,
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(
                      color: theme.colorScheme.secondaryContainer,
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Text(
                      product.tag!.toUpperCase(),
                      style: TextStyle(
                        fontSize: 9,
                        fontWeight: FontWeight.w700,
                        color: theme.colorScheme.onSecondaryContainer,
                      ),
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 10),
          Text(
            product.name,
            style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.bold),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          Text(product.description, style: theme.textTheme.bodySmall, maxLines: 1, overflow: TextOverflow.ellipsis),
          const SizedBox(height: 8),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Flexible(
                child: Text(
                  '₹${product.price.toStringAsFixed(0)}',
                  style: theme.textTheme.titleMedium
                      ?.copyWith(color: theme.colorScheme.primary, fontWeight: FontWeight.bold),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              FilledButton(
                // MA-23: opens the same product-configuration screen
                // CatalogScreen's own Add button does — see that screen's
                // _ProductAction.
                onPressed: () => context.push('/product/${product.id}', extra: product),
                style: FilledButton.styleFrom(minimumSize: const Size(64, 32), padding: const EdgeInsets.symmetric(horizontal: 12)),
                child: const Text('Add', style: TextStyle(fontSize: 13)),
              ),
            ],
          ),
          if (product.subscriptionEligible) ...[
            const Divider(height: 16),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Expanded(
                  child: Text(
                    'Daily Subscription',
                    style: theme.textTheme.bodySmall,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                Switch(
                  key: Key('${widget.keyPrefix}-subscription-toggle-${product.id}'),
                  value: _subscribed,
                  materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  onChanged: (value) => setState(() => _subscribed = value),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  Widget _imageFallback(ThemeData theme) => Container(
        color: theme.colorScheme.primaryContainer,
        child: Icon(Icons.image_outlined, color: theme.colorScheme.primary),
      );
}

/// Static bento-style deals grid — purely decorative, matching the mockup;
/// none of Combo Packs/Farm News/Quick Buy correspond to a real feature or
/// backend endpoint, so unlike every other section on this screen, nothing
/// here is wired to data (same "present per mockup" treatment as the
/// bottom nav's own non-Home items, just with no tap target at all rather
/// than a disabled one, since there's nowhere for a tap to go).
class _MorningFreshnessSection extends StatelessWidget {
  const _MorningFreshnessSection();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 24, 16, 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Morning Freshness', style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold)),
          const SizedBox(height: 12),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Container(
                  height: 184,
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: theme.colorScheme.secondaryContainer.withValues(alpha: 0.35),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Combo Packs',
                        style: theme.textTheme.labelLarge
                            ?.copyWith(fontWeight: FontWeight.bold, color: theme.colorScheme.secondary),
                      ),
                      const SizedBox(height: 4),
                      Text('Milk + Eggs at 15% off', style: theme.textTheme.bodySmall),
                      const Spacer(),
                      Icon(Icons.egg_outlined, color: theme.colorScheme.secondary, size: 32),
                    ],
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  children: [
                    _BentoTile(
                      title: 'Farm News',
                      subtitle: "Today's harvest story",
                      icon: Icons.article_outlined,
                      color: theme.colorScheme.primary,
                    ),
                    const SizedBox(height: 12),
                    _BentoTile(
                      title: 'Quick Buy',
                      subtitle: '1-Tap Orders',
                      icon: Icons.bolt,
                      color: theme.colorScheme.tertiary,
                    ),
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _BentoTile extends StatelessWidget {
  const _BentoTile({required this.title, required this.subtitle, required this.icon, required this.color});

  final String title;
  final String subtitle;
  final IconData icon;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 86,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(color: color.withValues(alpha: 0.08), borderRadius: BorderRadius.circular(16)),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(title, style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12, color: color)),
                Text(subtitle, style: const TextStyle(fontSize: 10)),
              ],
            ),
          ),
          Icon(icon, color: color, size: 20),
        ],
      ),
    );
  }
}

/// Matches the reference mockup's bottom nav bar. Only Home is real —
/// Schedule/Wallet/Profile have no screens or specs behind them yet, so
/// they're visually present but disabled (`onTap: null`), same "present
/// per mockup, not yet wired" treatment used elsewhere on this screen.
class _HomeBottomNav extends StatelessWidget {
  const _HomeBottomNav();

  @override
  Widget build(BuildContext context) {
    final primary = Theme.of(context).colorScheme.primary;
    return BottomNavigationBar(
      currentIndex: 0,
      onTap: null,
      selectedItemColor: primary,
      unselectedItemColor: Colors.grey.shade400,
      items: const [
        BottomNavigationBarItem(icon: Icon(Icons.home), label: 'Home'),
        BottomNavigationBarItem(icon: Icon(Icons.calendar_today_outlined), label: 'Schedule'),
        BottomNavigationBarItem(icon: Icon(Icons.account_balance_wallet_outlined), label: 'Wallet'),
        BottomNavigationBarItem(icon: Icon(Icons.person_outline), label: 'Profile'),
      ],
    );
  }
}
