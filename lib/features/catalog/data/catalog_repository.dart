import 'package:equatable/equatable.dart';

import '../../../core/config/app_config.dart';
import '../../../core/network/api_client.dart';
import '../models/category.dart';
import '../models/product.dart';

/// MA-115 FR-6. Sent to MA-117's `GET /search` as repeated `filters=`
/// query params (`category:milk`, `veg:true`, `organic:true`,
/// `price:{min}-{max}`) — see [CatalogFilters.toQueryParams].
class CatalogFilters extends Equatable {
  const CatalogFilters({
    this.categoryIds = const [],
    this.minPrice,
    this.maxPrice,
    this.vegOnly = false,
    this.organicOnly = false,
  });

  final List<String> categoryIds;
  final double? minPrice;
  final double? maxPrice;
  final bool vegOnly;
  final bool organicOnly;

  bool get isEmpty =>
      categoryIds.isEmpty &&
      minPrice == null &&
      maxPrice == null &&
      !vegOnly &&
      !organicOnly;

  int get activeCount =>
      (categoryIds.isNotEmpty ? 1 : 0) +
      (minPrice != null || maxPrice != null ? 1 : 0) +
      (vegOnly ? 1 : 0) +
      (organicOnly ? 1 : 0);

  List<String> toQueryParams() => [
    for (final id in categoryIds) 'category:$id',
    if (minPrice != null || maxPrice != null)
      'price:${minPrice ?? 0}-${maxPrice ?? ''}',
    if (vegOnly) 'veg:true',
    if (organicOnly) 'organic:true',
  ];

  CatalogFilters copyWith({
    List<String>? categoryIds,
    double? minPrice,
    double? maxPrice,
    bool? vegOnly,
    bool? organicOnly,
  }) => CatalogFilters(
    categoryIds: categoryIds ?? this.categoryIds,
    minPrice: minPrice ?? this.minPrice,
    maxPrice: maxPrice ?? this.maxPrice,
    vegOnly: vegOnly ?? this.vegOnly,
    organicOnly: organicOnly ?? this.organicOnly,
  );

  @override
  List<Object?> get props => [
    categoryIds,
    minPrice,
    maxPrice,
    vegOnly,
    organicOnly,
  ];
}

enum CatalogSort { priceAsc, priceDesc, newest }

extension on CatalogSort {
  String get queryValue => switch (this) {
    CatalogSort.priceAsc => 'price_asc',
    CatalogSort.priceDesc => 'price_desc',
    CatalogSort.newest => 'newest',
  };
}

abstract class CatalogRepository {
  /// MA-116 FR-3.
  Future<List<Category>> getCategories();

  /// MA-116 FR-1.
  Future<List<Product>> getProducts({required String categoryId});

  /// MA-116 FR-2 (`GET /products/{id}`, already live server-side). MA-120
  /// §9 — used to re-fetch a product's current stock state on opening its
  /// configuration screen, since the `Product` carried via a route's
  /// `extra:` may be stale by the time the customer taps in.
  Future<Product> getProduct(String productId);

  /// MA-117 FR-1. Used for search text, filters, and sort — MA-115 FR-6
  /// routes filter/sort application through here rather than
  /// [getProducts], since `GET /products` only accepts a single
  /// `categoryId` and can't express a multi-select filter.
  Future<List<Product>> search({
    String? query,
    CatalogFilters? filters,
    CatalogSort? sort,
  });
}

class DioCatalogRepository implements CatalogRepository {
  DioCatalogRepository(this._client);

  final ApiClient _client;

  @override
  Future<List<Category>> getCategories() async {
    final list = await _client.requestList(
      'GET',
      '${AppConfig.catalogBaseUrl}/categories',
    );
    return list
        .map((c) => Category.fromJson(c as Map<String, dynamic>))
        .toList();
  }

  @override
  Future<List<Product>> getProducts({required String categoryId}) async {
    final data = await _client.request(
      'GET',
      '${AppConfig.catalogBaseUrl}/products',
      queryParameters: {'categoryId': categoryId},
    );
    return (data['products'] as List)
        .map((p) => Product.fromJson(p as Map<String, dynamic>))
        .toList();
  }

  @override
  Future<Product> getProduct(String productId) async {
    final data = await _client.request(
      'GET',
      '${AppConfig.catalogBaseUrl}/products/$productId',
    );
    return Product.fromJson(data);
  }

  @override
  Future<List<Product>> search({
    String? query,
    CatalogFilters? filters,
    CatalogSort? sort,
  }) async {
    final data = await _client.request(
      'GET',
      '${AppConfig.catalogBaseUrl}/search',
      queryParameters: {
        if (query != null && query.isNotEmpty) 'q': query,
        if (filters != null && !filters.isEmpty)
          'filters': filters.toQueryParams(),
        if (sort != null) 'sort': sort.queryValue,
      },
    );
    return (data['products'] as List)
        .map((p) => Product.fromJson(p as Map<String, dynamic>))
        .toList();
  }
}
