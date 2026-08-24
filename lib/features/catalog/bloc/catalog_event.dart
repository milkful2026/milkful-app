import 'package:equatable/equatable.dart';

import '../data/catalog_repository.dart';

sealed class CatalogEvent extends Equatable {
  const CatalogEvent();

  @override
  List<Object?> get props => [];
}

/// Fetches categories, then either the first category's products (FR-1) or,
/// when [showAllByDefault] is set, every product across all categories —
/// used by the full catalog page (`/catalog`), reached via Home's "View
/// All", which should land already showing everything rather than one
/// arbitrary category.
class CatalogStarted extends CatalogEvent {
  const CatalogStarted({this.showAllByDefault = false});

  final bool showAllByDefault;

  @override
  List<Object?> get props => [showAllByDefault];
}

/// FR-1: rail tap. Clears any active search/filter so the rail always shows
/// a plain, predictable single-category browse.
class CategorySelected extends CatalogEvent {
  const CategorySelected(this.categoryId);

  final String categoryId;

  @override
  List<Object?> get props => [categoryId];
}

/// The header bar's "All" pill — browses every category at once instead of
/// one. Also clears any active search/filter, matching [CategorySelected].
class AllProductsSelected extends CatalogEvent {
  const AllProductsSelected();
}

/// FR-5. Home's header owns the search field and its debounce timer (not
/// the bloc), same as this app's other screens (e.g. `OtpVerificationView`
/// keeps its countdown timer in the widget too).
class SearchQueryChanged extends CatalogEvent {
  const SearchQueryChanged(this.query);

  final String query;

  @override
  List<Object?> get props => [query];
}

/// The search field's own clear ("X") button: drops the query, reverting
/// to the plain category browse (FR-5).
class SearchCleared extends CatalogEvent {
  const SearchCleared();
}

/// FR-6.
class FiltersApplied extends CatalogEvent {
  const FiltersApplied(this.filters);

  final CatalogFilters filters;

  @override
  List<Object?> get props => [filters];
}

/// FR-7.
class SortChanged extends CatalogEvent {
  const SortChanged(this.sort);

  final CatalogSort sort;

  @override
  List<Object?> get props => [sort];
}

/// FR-8 error-state retry.
class CatalogRetryRequested extends CatalogEvent {
  const CatalogRetryRequested();
}
