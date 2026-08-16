import 'package:milkful_app/features/catalog/data/catalog_repository.dart';
import 'package:milkful_app/features/catalog/models/category.dart';
import 'package:milkful_app/features/catalog/models/product.dart';

/// Matches CatalogRepository's real contract exactly (same "fix the fake,
/// not the assertion" discipline used throughout this repo) — configure the
/// `*Exception`/result fields to simulate failures/results instead of
/// hand-rolling ad-hoc mocks per test.
class FakeCatalogRepository implements CatalogRepository {
  FakeCatalogRepository({
    this.categoriesException,
    this.productsException,
    this.searchException,
    this.categories = const [],
    this.productsByCategory = const {},
    this.searchResults = const [],
    this.categoryFetchDelays = const {},
  });

  Object? categoriesException;
  Object? productsException;
  Object? searchException;
  List<Category> categories;
  Map<String, List<Product>> productsByCategory;
  List<Product> searchResults;

  /// Per-category artificial delay before `getProducts` resolves — lets
  /// tests simulate a slower response for an earlier request racing against
  /// a faster response for a later one.
  Map<String, Duration> categoryFetchDelays;

  final List<String> requestedCategoryIds = [];
  final List<String?> searchQueries = [];
  final List<CatalogFilters?> searchFilters = [];
  final List<CatalogSort?> searchSorts = [];

  @override
  Future<List<Category>> getCategories() async {
    if (categoriesException != null) throw categoriesException!;
    return categories;
  }

  @override
  Future<List<Product>> getProducts({required String categoryId}) async {
    requestedCategoryIds.add(categoryId);
    final delay = categoryFetchDelays[categoryId];
    if (delay != null) await Future<void>.delayed(delay);
    if (productsException != null) throw productsException!;
    return productsByCategory[categoryId] ?? [];
  }

  @override
  Future<List<Product>> search({String? query, CatalogFilters? filters, CatalogSort? sort}) async {
    searchQueries.add(query);
    searchFilters.add(filters);
    searchSorts.add(sort);
    if (searchException != null) throw searchException!;
    return searchResults;
  }
}
