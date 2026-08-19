import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:milkful_app/features/catalog/bloc/catalog_bloc.dart';
import 'package:milkful_app/features/catalog/bloc/catalog_event.dart';
import 'package:milkful_app/features/catalog/models/category.dart';
import 'package:milkful_app/features/catalog/models/product.dart';
import 'package:milkful_app/features/catalog/presentation/catalog_screen.dart';

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

const _outOfStockCurd = Product(
  id: 'curd-500g',
  categoryId: 'curd',
  name: 'Fresh Curd',
  description: 'Set curd',
  unit: '500g Cup',
  price: 45,
  stockState: StockState.outOfStock,
);

final _availableFromMilk = Product(
  id: 'buffalo-milk',
  categoryId: 'milk',
  name: 'Buffalo Milk',
  description: 'Rich buffalo milk',
  unit: '1L Pouch',
  price: 84,
  stockState: StockState.availableFrom,
  availableFrom: DateTime(2026, 9, 1),
);

const _subscriptionMilk = Product(
  id: 'sub-milk',
  categoryId: 'milk',
  name: 'Daily Milk Pack',
  description: 'Subscribe and save',
  unit: '1L Bottle',
  price: 65,
  stockState: StockState.inStock,
  subscriptionEligible: true,
);

void main() {
  late FakeCatalogRepository repository;

  Future<void> pumpCatalog(WidgetTester tester) async {
    repository = FakeCatalogRepository(
      categories: const [_milkCategory, _curdCategory],
      productsByCategory: {
        'milk': [_cowMilk],
        'curd': [_outOfStockCurd],
      },
    );
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: BlocProvider(
            create: (_) => CatalogBloc(repository: repository),
            child: const CatalogScreen(),
          ),
        ),
      ),
    );
    await tester.pump();
  }

  testWidgets('category bar renders (with All) and defaults to the first category (FR-1)', (
    tester,
  ) async {
    await pumpCatalog(tester);

    expect(find.byKey(const Key('category-bar')), findsOneWidget);
    expect(find.byKey(const Key('category-all')), findsOneWidget);
    expect(find.byKey(const Key('category-milk')), findsOneWidget);
    expect(find.byKey(const Key('category-curd')), findsOneWidget);
    expect(find.byKey(const Key('product-card-cow-milk')), findsOneWidget);
  });

  testWidgets('tapping All browses every category at once (FR-1)', (tester) async {
    repository = FakeCatalogRepository(
      categories: const [_milkCategory, _curdCategory],
      productsByCategory: {
        'milk': [_cowMilk],
        'curd': [_outOfStockCurd],
      },
      searchResults: const [_cowMilk, _outOfStockCurd],
    );
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: BlocProvider(
            create: (_) => CatalogBloc(repository: repository),
            child: const CatalogScreen(),
          ),
        ),
      ),
    );
    await tester.pump();

    await tester.tap(find.byKey(const Key('category-all')));
    await tester.pump();

    expect(find.byKey(const Key('product-card-cow-milk')), findsOneWidget);
    expect(find.byKey(const Key('product-card-curd-500g')), findsOneWidget);
  });

  testWidgets('tapping a category switches the product list (FR-1)', (tester) async {
    await pumpCatalog(tester);

    await tester.tap(find.byKey(const Key('category-curd')));
    await tester.pump();

    expect(find.byKey(const Key('product-card-curd-500g')), findsOneWidget);
    expect(find.byKey(const Key('product-card-cow-milk')), findsNothing);
  });

  testWidgets('product card renders name, unit, and price (FR-2)', (tester) async {
    await pumpCatalog(tester);

    expect(find.text('Cow Milk'), findsOneWidget);
    expect(find.text('1L Bottle'), findsOneWidget);
    expect(find.text('₹68'), findsOneWidget);
  });

  testWidgets('out-of-stock product shows the Out of Stock label, not an Add button (FR-3)', (
    tester,
  ) async {
    repository = FakeCatalogRepository(
      categories: const [_milkCategory],
      productsByCategory: {
        'milk': [_outOfStockCurd.copyWithCategory('milk')],
      },
    );
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: BlocProvider(
            create: (_) => CatalogBloc(repository: repository),
            child: const CatalogScreen(),
          ),
        ),
      ),
    );
    await tester.pump();

    expect(find.byKey(const Key('out-of-stock-curd-500g')), findsOneWidget);
    expect(find.widgetWithText(FilledButton, 'Add'), findsNothing);
  });

  testWidgets('available-from product shows the formatted date, not an Add button (FR-3)', (
    tester,
  ) async {
    repository = FakeCatalogRepository(
      categories: const [_milkCategory],
      productsByCategory: {
        'milk': [_availableFromMilk],
      },
    );
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: BlocProvider(
            create: (_) => CatalogBloc(repository: repository),
            child: const CatalogScreen(),
          ),
        ),
      ),
    );
    await tester.pump();

    expect(find.byKey(const Key('available-from-buffalo-milk')), findsOneWidget);
    expect(find.textContaining('Sep'), findsOneWidget);
  });

  testWidgets('subscription-eligible product shows the badge; a plain one does not (FR-4)', (
    tester,
  ) async {
    repository = FakeCatalogRepository(
      categories: const [_milkCategory],
      productsByCategory: {
        'milk': [_cowMilk, _subscriptionMilk],
      },
    );
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: BlocProvider(
            create: (_) => CatalogBloc(repository: repository),
            child: const CatalogScreen(),
          ),
        ),
      ),
    );
    await tester.pump();

    expect(find.byKey(const Key('subscription-badge-sub-milk')), findsOneWidget);
    expect(find.byKey(const Key('subscription-badge-cow-milk')), findsNothing);
  });

  // Search itself is now a Home-screen concern (a persistent header field
  // dispatching straight to this same CatalogBloc — see home_screen.dart
  // and catalog_bloc_test.dart's own SearchQueryChanged/SearchCleared
  // coverage) — CatalogScreen no longer owns a search field to drive
  // through the UI, so these exercise the same events a step lower, still
  // asserting on this screen's own rendering of the results.
  testWidgets('a typed search query is reflected in the product list (FR-5)', (tester) async {
    repository = FakeCatalogRepository(
      categories: const [_milkCategory],
      productsByCategory: {
        'milk': [_cowMilk],
      },
      searchResults: const [_cowMilk],
    );
    late CatalogBloc bloc;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: BlocProvider(
            create: (_) => bloc = CatalogBloc(repository: repository),
            child: const CatalogScreen(),
          ),
        ),
      ),
    );
    await tester.pump();

    bloc.add(const SearchQueryChanged('cow'));
    await tester.pump();

    expect(repository.searchQueries, contains('cow'));
    expect(find.byKey(const Key('product-card-cow-milk')), findsOneWidget);

    bloc.add(const SearchCleared());
    await tester.pump();

    expect(find.byKey(const Key('product-card-cow-milk')), findsOneWidget);
  });

  testWidgets('search with no matches shows the empty-search state (FR-5)', (tester) async {
    repository = FakeCatalogRepository(
      categories: const [_milkCategory],
      productsByCategory: {
        'milk': [_cowMilk],
      },
      searchResults: const [],
    );
    late CatalogBloc bloc;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: BlocProvider(
            create: (_) => bloc = CatalogBloc(repository: repository),
            child: const CatalogScreen(),
          ),
        ),
      ),
    );
    await tester.pump();

    bloc.add(const SearchQueryChanged('nonsense'));
    await tester.pump();

    expect(find.byKey(const Key('search-empty-state')), findsOneWidget);
  });

  testWidgets('a Catalog Service failure shows the error state; Retry re-triggers the fetch (FR-8)', (
    tester,
  ) async {
    repository = FakeCatalogRepository(categoriesException: Exception('down'));
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: BlocProvider(
            create: (_) => CatalogBloc(repository: repository),
            child: const CatalogScreen(),
          ),
        ),
      ),
    );
    await tester.pump();

    expect(find.byKey(const Key('catalog-retry-button')), findsOneWidget);

    repository.categoriesException = null;
    repository.categories = const [_milkCategory];
    repository.productsByCategory = {
      'milk': [_cowMilk],
    };
    await tester.tap(find.byKey(const Key('catalog-retry-button')));
    await tester.pump();

    expect(find.byKey(const Key('product-card-cow-milk')), findsOneWidget);
  });

  testWidgets('an empty category shows the category-empty state (FR-8)', (tester) async {
    repository = FakeCatalogRepository(
      categories: const [_milkCategory],
      productsByCategory: const {},
    );
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: BlocProvider(
            create: (_) => CatalogBloc(repository: repository),
            child: const CatalogScreen(),
          ),
        ),
      ),
    );
    await tester.pump();

    expect(find.byKey(const Key('category-empty-state')), findsOneWidget);
  });
}

extension on Product {
  // Convenience for reusing the shared `_outOfStockCurd` fixture under a
  // different categoryId in a single-category test setup.
  Product copyWithCategory(String categoryId) => Product(
        id: id,
        categoryId: categoryId,
        name: name,
        description: description,
        unit: unit,
        price: price,
        stockState: stockState,
        imageUrl: imageUrl,
        tag: tag,
        subscriptionEligible: subscriptionEligible,
        availableFrom: availableFrom,
      );
}
