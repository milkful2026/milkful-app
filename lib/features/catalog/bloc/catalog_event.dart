import 'package:equatable/equatable.dart';

import '../data/catalog_repository.dart';

sealed class CatalogEvent extends Equatable {
  const CatalogEvent();

  @override
  List<Object?> get props => [];
}

/// Fetches categories, then the first category's products (FR-1).
class CatalogStarted extends CatalogEvent {
  const CatalogStarted();
}

/// FR-1: rail tap. Clears any active search/filter so the rail always shows
/// a plain, predictable single-category browse.
class CategorySelected extends CatalogEvent {
  const CategorySelected(this.categoryId);

  final String categoryId;

  @override
  List<Object?> get props => [categoryId];
}

/// FR-5. The screen debounces (300ms) before dispatching this — the bloc
/// itself doesn't own the debounce timer, matching how this app's other
/// screens (e.g. `OtpVerificationView`) keep timers in the widget, not the
/// bloc.
class SearchQueryChanged extends CatalogEvent {
  const SearchQueryChanged(this.query);

  final String query;

  @override
  List<Object?> get props => [query];
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
