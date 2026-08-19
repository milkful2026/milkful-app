import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:intl/intl.dart';

import '../bloc/catalog_bloc.dart';
import '../bloc/catalog_event.dart';
import '../bloc/catalog_state.dart';
import '../data/catalog_repository.dart';
import '../models/category.dart';
import '../models/product.dart';

/// Matches the reference mockup's price color — amber, not the brand
/// green, so price stands out from the rest of a product card's text.
const _priceAmber = Color(0xFFB07A1E);

/// MA-115. Replaces `HomeScreen`'s placeholder body — see that screen for
/// the surrounding AppBar/logout chrome, which this widget doesn't own.
/// Built against the spec's functional requirements (FR-1–FR-8); the
/// reference mockup only shows the plain-browse state, so error/empty/
/// search/filter chrome is this widget's own extrapolation in the same
/// visual language (see MA-115 §11 Risk #3), not something the mockup
/// itself depicts.
class CatalogScreen extends StatefulWidget {
  const CatalogScreen({super.key});

  @override
  State<CatalogScreen> createState() => _CatalogScreenState();
}

class _CatalogScreenState extends State<CatalogScreen> {
  @override
  void initState() {
    super.initState();
    context.read<CatalogBloc>().add(const CatalogStarted());
  }

  Future<void> _openFilterSheet(BuildContext context, CatalogState state) async {
    final result = await showModalBottomSheet<CatalogFilters>(
      context: context,
      isScrollControlled: true,
      builder: (sheetContext) => _FilterSheet(
        initial: state.filters,
        categories: state.categories,
      ),
    );
    if (result != null && context.mounted) {
      context.read<CatalogBloc>().add(FiltersApplied(result));
    }
  }

  Future<void> _openSortMenu(BuildContext context) async {
    final selected = await showModalBottomSheet<CatalogSort>(
      context: context,
      builder: (sheetContext) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              title: const Text('Price: Low to High'),
              onTap: () => Navigator.of(sheetContext).pop(CatalogSort.priceAsc),
            ),
            ListTile(
              title: const Text('Price: High to Low'),
              onTap: () => Navigator.of(sheetContext).pop(CatalogSort.priceDesc),
            ),
            ListTile(
              title: const Text('Newest'),
              onTap: () => Navigator.of(sheetContext).pop(CatalogSort.newest),
            ),
          ],
        ),
      ),
    );
    if (selected != null && context.mounted) {
      context.read<CatalogBloc>().add(SortChanged(selected));
    }
  }

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<CatalogBloc, CatalogState>(
      builder: (context, state) {
        return Column(
          children: [
            _CategoryBar(
              state: state,
              onFilterTap: () => _openFilterSheet(context, state),
              onSortTap: () => _openSortMenu(context),
            ),
            Expanded(child: _CatalogBody(state: state)),
          ],
        );
      },
    );
  }
}

/// Horizontal category bar — "All" first, then every real category, plus
/// the filter/sort icons trailing the row. Search itself lives in Home's
/// own header now (a single persistent field, not a toggled-in one), since
/// it dispatches to this same [CatalogBloc] instance regardless of which
/// widget renders the field.
class _CategoryBar extends StatelessWidget {
  const _CategoryBar({required this.state, required this.onFilterTap, required this.onSortTap});

  final CatalogState state;
  final VoidCallback onFilterTap;
  final VoidCallback onSortTap;

  IconData _iconFor(String? iconName) => switch (iconName) {
        'milk' => Icons.local_drink,
        'curd' => Icons.icecream_outlined,
        'paneer' => Icons.layers,
        'ghee' => Icons.opacity,
        'veggies' => Icons.eco,
        _ => Icons.storefront,
      };

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        children: [
          Expanded(
            child: SizedBox(
              key: const Key('category-bar'),
              height: 96,
              child: ListView(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(horizontal: 12),
                children: [
                  _CategoryPill(
                    categoryKey: 'category-all',
                    label: 'All',
                    icon: Icons.apps,
                    selected: state.showingAll,
                    onTap: () => context.read<CatalogBloc>().add(const AllProductsSelected()),
                  ),
                  for (final category in state.categories)
                    _CategoryPill(
                      categoryKey: 'category-${category.id}',
                      label: category.name,
                      icon: _iconFor(category.iconName),
                      selected: !state.showingAll && category.id == state.selectedCategoryId,
                      onTap: () =>
                          context.read<CatalogBloc>().add(CategorySelected(category.id)),
                    ),
                ],
              ),
            ),
          ),
          IconButton(
            key: const Key('catalog-filter-toggle'),
            icon: Badge(
              isLabelVisible: state.filters.activeCount > 0,
              label: Text('${state.filters.activeCount}'),
              child: const Icon(Icons.filter_list),
            ),
            tooltip: 'Filters (${state.filters.activeCount})',
            onPressed: onFilterTap,
          ),
          IconButton(
            key: const Key('catalog-sort-toggle'),
            icon: const Icon(Icons.sort),
            tooltip: 'Sort',
            onPressed: onSortTap,
          ),
        ],
      ),
    );
  }
}

class _CategoryPill extends StatelessWidget {
  const _CategoryPill({
    required this.categoryKey,
    required this.label,
    required this.icon,
    required this.selected,
    required this.onTap,
  });

  final String categoryKey;
  final String label;
  final IconData icon;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Padding(
      key: Key(categoryKey),
      padding: const EdgeInsets.symmetric(horizontal: 6),
      child: InkWell(
        borderRadius: BorderRadius.circular(40),
        onTap: onTap,
        child: SizedBox(
          width: 68,
          child: Column(
            children: [
              CircleAvatar(
                radius: 28,
                backgroundColor: selected
                    ? Theme.of(context).colorScheme.primary
                    : Theme.of(context).colorScheme.primaryContainer,
                child: Icon(
                  icon,
                  color: selected ? Colors.white : Theme.of(context).colorScheme.primary,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                label,
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.labelSmall,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _CatalogBody extends StatelessWidget {
  const _CatalogBody({required this.state});

  final CatalogState state;

  @override
  Widget build(BuildContext context) {
    switch (state.status) {
      case CatalogStatus.initial:
      case CatalogStatus.loading:
        return const _LoadingSkeleton();
      case CatalogStatus.error:
        return _ErrorState(message: state.errorMessage);
      case CatalogStatus.empty:
        return state.searchQuery.isNotEmpty
            ? _SearchEmptyState(query: state.searchQuery)
            : const _CategoryEmptyState();
      case CatalogStatus.loaded:
        return _ProductGrid(products: state.products);
    }
  }
}

class _LoadingSkeleton extends StatelessWidget {
  const _LoadingSkeleton();

  @override
  Widget build(BuildContext context) {
    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: 3,
      itemBuilder: (context, index) => Container(
        height: 96,
        margin: const EdgeInsets.only(bottom: 12),
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(16),
        ),
      ),
    );
  }
}

class _ErrorState extends StatelessWidget {
  const _ErrorState({this.message});

  final String? message;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              message ?? 'Something went wrong.',
              textAlign: TextAlign.center,
              style: TextStyle(color: Theme.of(context).colorScheme.error),
            ),
            const SizedBox(height: 12),
            FilledButton(
              key: const Key('catalog-retry-button'),
              onPressed: () => context.read<CatalogBloc>().add(const CatalogRetryRequested()),
              child: const Text('Retry'),
            ),
          ],
        ),
      ),
    );
  }
}

class _CategoryEmptyState extends StatelessWidget {
  const _CategoryEmptyState();

  @override
  Widget build(BuildContext context) {
    return const Center(
      key: Key('category-empty-state'),
      child: Text('No products in this category yet'),
    );
  }
}

class _SearchEmptyState extends StatelessWidget {
  const _SearchEmptyState({required this.query});

  final String query;

  @override
  Widget build(BuildContext context) {
    return Center(
      key: const Key('search-empty-state'),
      child: Text("No products found for '$query'"),
    );
  }
}

class _ProductGrid extends StatelessWidget {
  const _ProductGrid({required this.products});

  final List<Product> products;

  @override
  Widget build(BuildContext context) {
    // MA-115 §6 responsive table: single column under 600dp, 2-column grid
    // at/above it.
    final isTablet = MediaQuery.sizeOf(context).width >= 600;
    return GridView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: products.length,
      gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: isTablet ? 2 : 1,
        mainAxisExtent: 112,
        crossAxisSpacing: 12,
        mainAxisSpacing: 12,
      ),
      itemBuilder: (context, index) => _ProductCard(product: products[index]),
    );
  }
}

class _ProductCard extends StatelessWidget {
  const _ProductCard({required this.product});

  final Product product;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final deemphasized = product.stockState == StockState.outOfStock;
    return Opacity(
      opacity: deemphasized ? 0.6 : 1,
      child: Container(
        key: Key('product-card-${product.id}'),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.06),
              blurRadius: 12,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Row(
          children: [
            Stack(
              children: [
                ClipRRect(
                  borderRadius: BorderRadius.circular(12),
                  child: SizedBox(
                    width: 72,
                    height: 72,
                    child: product.imageUrl == null
                        ? Container(
                            color: theme.colorScheme.primaryContainer,
                            child: Icon(Icons.image_outlined, color: theme.colorScheme.primary),
                          )
                        : Image.network(
                            product.imageUrl!,
                            fit: BoxFit.cover,
                            errorBuilder: (context, error, stackTrace) => Container(
                              color: theme.colorScheme.primaryContainer,
                              child:
                                  Icon(Icons.image_outlined, color: theme.colorScheme.primary),
                            ),
                          ),
                  ),
                ),
                if (product.tag != null)
                  Positioned(
                    top: 4,
                    left: 4,
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                      decoration: BoxDecoration(
                        color: Colors.black.withValues(alpha: 0.55),
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: Text(
                        product.tag!,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 9,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ),
                if (product.subscriptionEligible)
                  Positioned(
                    bottom: 2,
                    right: 2,
                    child: Container(
                      key: Key('subscription-badge-${product.id}'),
                      padding: const EdgeInsets.all(2),
                      decoration: const BoxDecoration(
                        color: Colors.white,
                        shape: BoxShape.circle,
                      ),
                      child: Icon(Icons.autorenew, size: 14, color: theme.colorScheme.primary),
                    ),
                  ),
              ],
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(
                    product.name,
                    style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  Text(product.unit, style: theme.textTheme.bodySmall),
                  const SizedBox(height: 4),
                  Text(
                    '₹${product.price.toStringAsFixed(0)}',
                    style: theme.textTheme.titleMedium
                        ?.copyWith(color: _priceAmber, fontWeight: FontWeight.bold),
                  ),
                ],
              ),
            ),
            SizedBox(width: 84, child: _ProductAction(product: product)),
          ],
        ),
      ),
    );
  }
}

class _ProductAction extends StatelessWidget {
  const _ProductAction({required this.product});

  final Product product;

  @override
  Widget build(BuildContext context) {
    switch (product.stockState) {
      case StockState.outOfStock:
        return Text(
          'Out of Stock',
          key: Key('out-of-stock-${product.id}'),
          style: TextStyle(color: Theme.of(context).colorScheme.error, fontSize: 12),
        );
      case StockState.availableFrom:
        final date = product.availableFrom;
        return Text(
          date == null ? 'Available soon' : 'Available from ${DateFormat.yMMMd().format(date)}',
          key: Key('available-from-${product.id}'),
          textAlign: TextAlign.end,
          style: Theme.of(context).textTheme.bodySmall,
        );
      case StockState.inStock:
        return FilledButton(
          onPressed: () {}, // MA-23's concern — this spec only requires Add be present/enabled.
          style: FilledButton.styleFrom(minimumSize: const Size(64, 36)),
          child: const Text('Add'),
        );
    }
  }
}

class _FilterSheet extends StatefulWidget {
  const _FilterSheet({required this.initial, required this.categories});

  final CatalogFilters initial;
  final List<Category> categories;

  @override
  State<_FilterSheet> createState() => _FilterSheetState();
}

class _FilterSheetState extends State<_FilterSheet> {
  late Set<String> _categoryIds;
  late bool _vegOnly;
  late bool _organicOnly;
  late RangeValues _priceRange;

  static const _maxPrice = 500.0;

  @override
  void initState() {
    super.initState();
    _categoryIds = widget.initial.categoryIds.toSet();
    _vegOnly = widget.initial.vegOnly;
    _organicOnly = widget.initial.organicOnly;
    _priceRange = RangeValues(
      widget.initial.minPrice ?? 0,
      widget.initial.maxPrice ?? _maxPrice,
    );
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Filters', style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 16),
            Text('Category', style: Theme.of(context).textTheme.labelLarge),
            Wrap(
              spacing: 8,
              children: [
                for (final category in widget.categories)
                  FilterChip(
                    label: Text(category.name),
                    selected: _categoryIds.contains(category.id),
                    onSelected: (selected) => setState(() {
                      if (selected) {
                        _categoryIds.add(category.id);
                      } else {
                        _categoryIds.remove(category.id);
                      }
                    }),
                  ),
              ],
            ),
            const SizedBox(height: 16),
            Text('Price', style: Theme.of(context).textTheme.labelLarge),
            RangeSlider(
              min: 0,
              max: _maxPrice,
              values: _priceRange,
              labels: RangeLabels(
                '₹${_priceRange.start.round()}',
                '₹${_priceRange.end.round()}',
              ),
              onChanged: (values) => setState(() => _priceRange = values),
            ),
            SwitchListTile(
              title: const Text('Veg only'),
              value: _vegOnly,
              onChanged: (value) => setState(() => _vegOnly = value),
            ),
            SwitchListTile(
              title: const Text('Organic only'),
              value: _organicOnly,
              onChanged: (value) => setState(() => _organicOnly = value),
            ),
            const SizedBox(height: 8),
            SizedBox(
              width: double.infinity,
              child: FilledButton(
                onPressed: () => Navigator.of(context).pop(
                  CatalogFilters(
                    categoryIds: _categoryIds.toList(),
                    minPrice: _priceRange.start > 0 ? _priceRange.start : null,
                    maxPrice: _priceRange.end < _maxPrice ? _priceRange.end : null,
                    vegOnly: _vegOnly,
                    organicOnly: _organicOnly,
                  ),
                ),
                child: const Text('Apply'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
