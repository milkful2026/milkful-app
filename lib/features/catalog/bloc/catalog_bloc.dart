import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../core/network/api_client.dart';
import '../data/catalog_repository.dart';
import '../models/product.dart';
import 'catalog_event.dart';
import 'catalog_state.dart';

class CatalogBloc extends Bloc<CatalogEvent, CatalogState> {
  CatalogBloc({required CatalogRepository repository})
      : _repository = repository,
        super(const CatalogState()) {
    on<CatalogStarted>(_onStarted);
    on<CategorySelected>(_onCategorySelected);
    on<SearchQueryChanged>(_onSearchQueryChanged);
    on<FiltersApplied>(_onFiltersApplied);
    on<SortChanged>(_onSortChanged);
    on<CatalogRetryRequested>(_onRetry);
  }

  final CatalogRepository _repository;

  Future<void> _onStarted(CatalogStarted event, Emitter<CatalogState> emit) async {
    emit(state.copyWith(status: CatalogStatus.loading));
    try {
      final categories = await _repository.getCategories();
      if (categories.isEmpty) {
        emit(state.copyWith(status: CatalogStatus.empty, categories: categories));
        return;
      }
      // FR-1: default selection is the first category returned.
      emit(state.copyWith(categories: categories, selectedCategoryId: categories.first.id));
      await _fetch(emit);
    } catch (e) {
      emit(state.copyWith(status: CatalogStatus.error, errorMessage: _errorMessage(e)));
    }
  }

  Future<void> _onCategorySelected(CategorySelected event, Emitter<CatalogState> emit) async {
    // FR-1: switching the rail always drops back to a plain single-category
    // browse — clears search/filters so the rail stays predictable. Sort
    // persists across category switches per FR-7.
    emit(
      state.copyWith(
        selectedCategoryId: event.categoryId,
        searchActive: false,
        searchQuery: '',
        filters: const CatalogFilters(),
      ),
    );
    await _fetch(emit);
  }

  Future<void> _onSearchQueryChanged(SearchQueryChanged event, Emitter<CatalogState> emit) async {
    emit(state.copyWith(searchActive: true, searchQuery: event.query));
    await _fetch(emit);
  }

  Future<void> _onFiltersApplied(FiltersApplied event, Emitter<CatalogState> emit) async {
    emit(state.copyWith(filters: event.filters));
    await _fetch(emit);
  }

  Future<void> _onSortChanged(SortChanged event, Emitter<CatalogState> emit) async {
    emit(state.copyWith(sort: event.sort));
    await _fetch(emit);
  }

  Future<void> _onRetry(CatalogRetryRequested event, Emitter<CatalogState> emit) async {
    if (state.categories.isEmpty) {
      await _onStarted(const CatalogStarted(), emit);
      return;
    }
    await _fetch(emit);
  }

  /// Central fetch: plain category browse (`GET /products`) when no
  /// search/filter/sort is active, otherwise `GET /search` — mirrors FR-6's
  /// own reasoning that `/products` can't express a multi-select filter or
  /// a sort, so any of those three route through search instead. When
  /// searching/sorting without an explicit filter, the currently-selected
  /// rail category is carried along as an implicit filter so the result set
  /// still narrows to it.
  Future<void> _fetch(Emitter<CatalogState> emit) async {
    emit(state.copyWith(status: CatalogStatus.loading));
    try {
      final usesSearchPath =
          state.searchQuery.isNotEmpty || !state.filters.isEmpty || state.sort != null;
      final products = usesSearchPath
          ? await _repository.search(
              query: state.searchQuery.isEmpty ? null : state.searchQuery,
              filters: state.filters.categoryIds.isEmpty && state.selectedCategoryId != null
                  ? state.filters.copyWith(categoryIds: [state.selectedCategoryId!])
                  : state.filters,
              sort: state.sort,
            )
          : state.selectedCategoryId == null
              ? <Product>[]
              : await _repository.getProducts(categoryId: state.selectedCategoryId!);
      emit(
        state.copyWith(
          status: products.isEmpty ? CatalogStatus.empty : CatalogStatus.loaded,
          products: products,
        ),
      );
    } catch (e) {
      emit(state.copyWith(status: CatalogStatus.error, errorMessage: _errorMessage(e)));
    }
  }

  String _errorMessage(Object error) =>
      error is ApiException ? error.message : 'Something went wrong. Please try again.';
}
