import 'package:equatable/equatable.dart';

import '../data/catalog_repository.dart';
import '../models/category.dart';
import '../models/product.dart';

enum CatalogStatus {
  /// Nothing fetched yet.
  initial,

  /// First load, or a category/search/filter/sort change re-fetching.
  loading,

  loaded,

  /// FR-8: the current category/search/filter combination has zero results.
  empty,

  /// FR-8.
  error,
}

class CatalogState extends Equatable {
  const CatalogState({
    this.status = CatalogStatus.initial,
    this.categories = const [],
    this.selectedCategoryId,
    this.products = const [],
    this.searchActive = false,
    this.searchQuery = '',
    this.filters = const CatalogFilters(),
    this.sort,
    this.errorMessage,
  });

  final CatalogStatus status;
  final List<Category> categories;
  final String? selectedCategoryId;
  final List<Product> products;

  /// FR-5: whether the search field is currently shown (tapped the search
  /// icon) — independent of whether [searchQuery] is non-empty.
  final bool searchActive;
  final String searchQuery;
  final CatalogFilters filters;
  final CatalogSort? sort;
  final String? errorMessage;

  Category? get selectedCategory {
    if (selectedCategoryId == null) return null;
    for (final category in categories) {
      if (category.id == selectedCategoryId) return category;
    }
    return null;
  }

  CatalogState copyWith({
    CatalogStatus? status,
    List<Category>? categories,
    String? selectedCategoryId,
    List<Product>? products,
    bool? searchActive,
    String? searchQuery,
    CatalogFilters? filters,
    CatalogSort? sort,
    String? errorMessage,
  }) =>
      CatalogState(
        status: status ?? this.status,
        categories: categories ?? this.categories,
        selectedCategoryId: selectedCategoryId ?? this.selectedCategoryId,
        products: products ?? this.products,
        searchActive: searchActive ?? this.searchActive,
        searchQuery: searchQuery ?? this.searchQuery,
        filters: filters ?? this.filters,
        sort: sort ?? this.sort,
        errorMessage: errorMessage,
      );

  @override
  List<Object?> get props => [
        status,
        categories,
        selectedCategoryId,
        products,
        searchActive,
        searchQuery,
        filters,
        sort,
        errorMessage,
      ];
}
