// Manual visual preview — NOT part of `flutter test`. Boots straight into
// the real ProductConfigScreen (MA-23/MA-120) against inline fakes, so it
// can be reviewed without going through the full auth/registration flow or
// a live backend (none of Cart/Pricing/Wallet Service exist yet — see the
// MA-23 impl plan §2). Same widget tree main.dart would build, just seeded
// with fakes. Fakes are duplicated inline (not imported from test/) because
// Flutter web's build root can't reach outside lib/.
//
//   flutter run -t tool/preview_product_config.dart -d chrome
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';
import 'package:milkful_app/core/theme/app_theme.dart';
import 'package:milkful_app/features/auth/data/profile_repository.dart';
import 'package:milkful_app/features/auth/models/user_profile.dart';
import 'package:milkful_app/features/cart/data/cart_repository.dart';
import 'package:milkful_app/features/cart/data/pricing_repository.dart';
import 'package:milkful_app/features/cart/data/wallet_balance_repository.dart';
import 'package:milkful_app/features/cart/models/cart_line_item.dart';
import 'package:milkful_app/features/cart/models/cart_view.dart';
import 'package:milkful_app/features/cart/models/frequency.dart';
import 'package:milkful_app/features/cart/models/quote.dart';
import 'package:milkful_app/features/cart/presentation/product_config_screen.dart';
import 'package:milkful_app/features/catalog/data/catalog_repository.dart';
import 'package:milkful_app/features/catalog/models/category.dart';
import 'package:milkful_app/features/catalog/models/product.dart';

class _FakeCatalogRepository implements CatalogRepository {
  _FakeCatalogRepository(this.product);
  final Product product;

  @override
  Future<Product> getProduct(String productId) async => product;

  @override
  Future<List<Category>> getCategories() async => [];

  @override
  Future<List<Product>> getProducts({required String categoryId}) async => [product];

  @override
  Future<List<Product>> search({String? query, CatalogFilters? filters, CatalogSort? sort}) async =>
      [product];
}

class _FakePricingRepository implements PricingRepository {
  static const _fixedQuote = Quote(
    basePrice: 65,
    taxAmount: 3.25,
    taxRate: 5,
    deliveryFee: 10,
    netPayable: 78.25,
    monthlyEstimate: 2347.5,
  );

  @override
  Future<Quote> quote({
    required String productId,
    required int quantity,
    required Frequency frequency,
    required String? deliveryState,
    String? offerCode,
  }) async => _fixedQuote;
}

class _FakeCartRepository implements CartRepository {
  @override
  Future<void> addItem({
    required String productId,
    required int quantity,
    required Frequency frequency,
    required String idempotencyKey,
    DateTime? startDate,
  }) async {}

  @override
  Future<CartView> getCart() async => const CartView(items: [], cartVersion: 0);

  @override
  Future<CartView> updateItem({
    required List<CartLineItem> items,
    required int ifVersion,
  }) async => CartView(items: items, cartVersion: ifVersion + 1);

  @override
  Future<void> removeItem({required String id}) async {}
}

class _FakeWalletBalanceRepository implements WalletBalanceRepository {
  @override
  Future<int> getBalance() async => 600;
}

class _FakeProfileRepository implements ProfileRepository {
  @override
  Future<UserProfile> getMe() async => const UserProfile(
    userId: 'user-1',
    name: 'Priya Sharma',
    mobile: '+919876543210',
    accountType: 'B2C',
    defaultAddressId: 'addr-1',
    defaultAddressState: 'Karnataka',
  );
}

const _cowMilk = Product(
  id: 'cow-milk',
  categoryId: 'milk',
  name: 'Farm Fresh Cow Milk',
  description: 'Farm-fresh cow milk, delivered daily.',
  unit: '1L Bottle',
  price: 65,
  stockState: StockState.inStock,
  subscriptionEligible: true,
  tag: 'Premium Selection',
  availableQuantity: 12,
);

void main() {
  final router = GoRouter(
    initialLocation: '/product/cow-milk',
    routes: [
      GoRoute(
        path: '/product/:productId',
        builder: (context, state) => const ProductConfigScreen(product: _cowMilk),
      ),
    ],
  );

  runApp(
    MultiRepositoryProvider(
      providers: [
        RepositoryProvider<CatalogRepository>.value(value: _FakeCatalogRepository(_cowMilk)),
        RepositoryProvider<PricingRepository>.value(value: _FakePricingRepository()),
        RepositoryProvider<CartRepository>.value(value: _FakeCartRepository()),
        RepositoryProvider<WalletBalanceRepository>.value(value: _FakeWalletBalanceRepository()),
        RepositoryProvider<ProfileRepository>.value(value: _FakeProfileRepository()),
      ],
      child: MaterialApp.router(theme: AppTheme.light, routerConfig: router),
    ),
  );
}
