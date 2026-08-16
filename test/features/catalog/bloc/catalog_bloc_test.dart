import 'package:bloc_test/bloc_test.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:milkful_app/features/catalog/bloc/catalog_bloc.dart';
import 'package:milkful_app/features/catalog/bloc/catalog_event.dart';
import 'package:milkful_app/features/catalog/bloc/catalog_state.dart';
import 'package:milkful_app/features/catalog/data/catalog_repository.dart';
import 'package:milkful_app/features/catalog/models/category.dart';
import 'package:milkful_app/features/catalog/models/product.dart';

import '../../../fakes/fake_catalog_repository.dart';

const _milkCategory = Category(id: 'milk', name: 'Fresh Milk');
const _curdCategory = Category(id: 'curd', name: 'Yogurt & Curd');

const _cowMilk = Product(
  id: 'cow-milk',
  categoryId: 'milk',
  name: 'Cow Milk',
  description: 'Farm-fresh cow milk',
  unit: '1L Bottle',
  price: 68,
  stockState: StockState.inStock,
);

void main() {
  group('CatalogBloc', () {
    late FakeCatalogRepository repository;

    setUp(() => repository = FakeCatalogRepository());

    CatalogBloc build() => CatalogBloc(repository: repository);

    blocTest<CatalogBloc, CatalogState>(
      'CatalogStarted loads categories and defaults to the first one (FR-1)',
      build: () {
        repository
          ..categories = const [_milkCategory, _curdCategory]
          ..productsByCategory = {
            'milk': [_cowMilk],
          };
        return build();
      },
      act: (bloc) => bloc.add(const CatalogStarted()),
      // Bloc dedupes consecutive equal states — the loading emission inside
      // _fetch() is equal to the loading+categories state right before it
      // (same status, same fields), so only 3 distinct states actually
      // reach the stream, not 4.
      expect: () => [
        isA<CatalogState>().having((s) => s.status, 'status', CatalogStatus.loading),
        isA<CatalogState>()
            .having((s) => s.categories.length, 'categories', 2)
            .having((s) => s.selectedCategoryId, 'selectedCategoryId', 'milk')
            .having((s) => s.status, 'status', CatalogStatus.loading),
        isA<CatalogState>()
            .having((s) => s.status, 'status', CatalogStatus.loaded)
            .having((s) => s.products, 'products', [_cowMilk]),
      ],
      verify: (_) => expect(repository.requestedCategoryIds, ['milk']),
    );

    blocTest<CatalogBloc, CatalogState>(
      'a category with zero products lands on the empty state (FR-8)',
      build: () {
        repository.categories = const [_milkCategory];
        return build();
      },
      act: (bloc) => bloc.add(const CatalogStarted()),
      skip: 2,
      expect: () => [
        isA<CatalogState>().having((s) => s.status, 'status', CatalogStatus.empty),
      ],
    );

    blocTest<CatalogBloc, CatalogState>(
      'a Catalog Service failure surfaces the error state with Retry available (FR-8)',
      build: () {
        repository.categoriesException = Exception('network down');
        return build();
      },
      act: (bloc) => bloc.add(const CatalogStarted()),
      skip: 1,
      expect: () => [
        isA<CatalogState>().having((s) => s.status, 'status', CatalogStatus.error),
      ],
    );

    blocTest<CatalogBloc, CatalogState>(
      'CategorySelected re-fetches for the new category and clears search/filters (FR-1)',
      build: () {
        repository
          ..categories = const [_milkCategory, _curdCategory]
          ..productsByCategory = {
            'milk': [_cowMilk],
            'curd': [],
          };
        return build();
      },
      act: (bloc) async {
        bloc.add(const CatalogStarted());
        await Future<void>.delayed(Duration.zero);
        bloc.add(const CategorySelected('curd'));
      },
      wait: const Duration(milliseconds: 10),
      verify: (_) => expect(repository.requestedCategoryIds, ['milk', 'curd']),
    );

    blocTest<CatalogBloc, CatalogState>(
      'SearchQueryChanged with a non-empty query routes through search, not products (FR-5)',
      build: () {
        repository
          ..categories = const [_milkCategory]
          ..productsByCategory = {
            'milk': [_cowMilk],
          }
          ..searchResults = const [_cowMilk];
        return build();
      },
      act: (bloc) async {
        bloc.add(const CatalogStarted());
        await Future<void>.delayed(Duration.zero);
        bloc.add(const SearchQueryChanged('cow'));
      },
      wait: const Duration(milliseconds: 10),
      verify: (_) {
        expect(repository.searchQueries, contains('cow'));
      },
    );

    blocTest<CatalogBloc, CatalogState>(
      'an empty search query reverts to the category-filtered view (FR-5)',
      build: () {
        repository
          ..categories = const [_milkCategory]
          ..productsByCategory = {
            'milk': [_cowMilk],
          };
        return build();
      },
      act: (bloc) async {
        bloc.add(const CatalogStarted());
        await Future<void>.delayed(Duration.zero);
        bloc.add(const SearchQueryChanged(''));
      },
      wait: const Duration(milliseconds: 10),
      verify: (_) {
        // getProducts (category path), not search, is used once the query
        // is empty again — searchQueries only records calls actually made
        // to search().
        expect(repository.searchQueries, isEmpty);
        expect(repository.requestedCategoryIds, ['milk', 'milk']);
      },
    );

    blocTest<CatalogBloc, CatalogState>(
      'FiltersApplied with no explicit category carries the selected rail category along (FR-6)',
      build: () {
        repository
          ..categories = const [_milkCategory]
          ..productsByCategory = {
            'milk': [_cowMilk],
          }
          ..searchResults = const [_cowMilk];
        return build();
      },
      act: (bloc) async {
        bloc.add(const CatalogStarted());
        await Future<void>.delayed(Duration.zero);
        bloc.add(const FiltersApplied(CatalogFilters(vegOnly: true)));
      },
      wait: const Duration(milliseconds: 10),
      verify: (_) {
        expect(repository.searchFilters.last?.vegOnly, isTrue);
        expect(repository.searchFilters.last?.categoryIds, ['milk']);
      },
    );

    blocTest<CatalogBloc, CatalogState>(
      'CatalogRetryRequested after an error re-issues the same fetch (FR-8)',
      build: () {
        repository
          ..categories = const [_milkCategory]
          ..productsException = Exception('boom');
        return build();
      },
      act: (bloc) async {
        bloc.add(const CatalogStarted());
        await Future<void>.delayed(Duration.zero);
        repository.productsException = null;
        repository.productsByCategory = {
          'milk': [_cowMilk],
        };
        bloc.add(const CatalogRetryRequested());
      },
      wait: const Duration(milliseconds: 10),
      expect: () => [
        isA<CatalogState>().having((s) => s.status, 'status', CatalogStatus.loading),
        isA<CatalogState>()
            .having((s) => s.categories.length, 'categories', 1)
            .having((s) => s.selectedCategoryId, 'selectedCategoryId', 'milk')
            .having((s) => s.status, 'status', CatalogStatus.loading),
        isA<CatalogState>().having((s) => s.status, 'status', CatalogStatus.error),
        isA<CatalogState>().having((s) => s.status, 'status', CatalogStatus.loading),
        isA<CatalogState>()
            .having((s) => s.status, 'status', CatalogStatus.loaded)
            .having((s) => s.products, 'products', [_cowMilk]),
      ],
    );
  });
}
