import 'package:bloc_test/bloc_test.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:milkful_app/core/network/api_client.dart';
import 'package:milkful_app/features/auth/models/user_profile.dart';
import 'package:milkful_app/features/cart/bloc/product_config_bloc.dart';
import 'package:milkful_app/features/cart/bloc/product_config_event.dart';
import 'package:milkful_app/features/cart/bloc/product_config_state.dart';
import 'package:milkful_app/features/cart/models/frequency.dart';
import 'package:milkful_app/features/cart/models/quote.dart';
import 'package:milkful_app/features/catalog/models/product.dart';

import '../../../fakes/fake_cart_repository.dart';
import '../../../fakes/fake_catalog_repository.dart';
import '../../../fakes/fake_pricing_repository.dart';
import '../../../fakes/fake_profile_repository.dart';
import '../../../fakes/fake_wallet_balance_repository.dart';

const _product = Product(
  id: 'cow-milk',
  categoryId: 'milk',
  name: 'Cow Milk',
  description: 'Farm-fresh cow milk',
  unit: '1L Bottle',
  price: 68,
  stockState: StockState.inStock,
  subscriptionEligible: true,
);

const _quote = Quote(
  basePrice: 68,
  taxAmount: 3.4,
  taxRate: 5,
  deliveryFee: 10,
  netPayable: 81.4,
);

void main() {
  group('ProductConfigBloc', () {
    late FakeCatalogRepository catalogRepository;
    late FakePricingRepository pricingRepository;
    late FakeCartRepository cartRepository;
    late FakeWalletBalanceRepository walletBalanceRepository;
    late FakeProfileRepository profileRepository;

    setUp(() {
      catalogRepository = FakeCatalogRepository(
        productsById: {'cow-milk': _product},
      );
      pricingRepository = FakePricingRepository(result: _quote);
      cartRepository = FakeCartRepository();
      walletBalanceRepository = FakeWalletBalanceRepository(balance: 600);
      profileRepository = FakeProfileRepository(
        profile: const UserProfile(
          userId: 'user-1',
          name: 'Priya Sharma',
          mobile: '+919876543210',
          accountType: 'B2C',
          defaultAddressId: 'addr-1',
          defaultAddressState: 'Karnataka',
        ),
      );
    });

    ProductConfigBloc build() => ProductConfigBloc(
      product: _product,
      catalogRepository: catalogRepository,
      pricingRepository: pricingRepository,
      cartRepository: cartRepository,
      walletBalanceRepository: walletBalanceRepository,
      profileRepository: profileRepository,
    );

    blocTest<ProductConfigBloc, ProductConfigState>(
      'ProductConfigStarted re-fetches the product and loads a quote',
      build: build,
      act: (bloc) => bloc.add(const ProductConfigStarted(_product)),
      wait: const Duration(milliseconds: 10),
      verify: (bloc) {
        expect(bloc.state.quoteStatus, QuoteStatus.loaded);
        expect(bloc.state.quote, _quote);
        expect(catalogRepository.requestedProductIds, ['cow-milk']);
        expect(pricingRepository.requests, hasLength(1));
        expect(pricingRepository.requests.single.deliveryState, 'Karnataka');
      },
    );

    blocTest<ProductConfigBloc, ProductConfigState>(
      'a stale-stock re-fetch failure keeps the seeded product rather than failing the screen',
      build: () {
        catalogRepository.getProductException = const ApiException(
          errorCode: 'NETWORK_ERROR',
          message: 'offline',
        );
        return build();
      },
      act: (bloc) => bloc.add(const ProductConfigStarted(_product)),
      wait: const Duration(milliseconds: 10),
      verify: (bloc) => expect(bloc.state.product, _product),
    );

    blocTest<ProductConfigBloc, ProductConfigState>(
      'a null delivery state fails the quote closed with DELIVERY_STATE_UNKNOWN',
      build: () {
        profileRepository.profile = const UserProfile(
          userId: 'user-1',
          name: 'Priya Sharma',
          mobile: '+919876543210',
          accountType: 'B2C',
          defaultAddressId: '',
        );
        return build();
      },
      act: (bloc) => bloc.add(const ProductConfigStarted(_product)),
      wait: const Duration(milliseconds: 10),
      verify: (bloc) {
        expect(bloc.state.quoteStatus, QuoteStatus.failed);
        expect(bloc.state.quoteErrorMessage, contains("couldn't determine"));
      },
    );

    blocTest<ProductConfigBloc, ProductConfigState>(
      'only the latest of two rapid QuantityChanged events lands in state (restartable)',
      build: () {
        pricingRepository.delay = const Duration(milliseconds: 50);
        return build();
      },
      act: (bloc) async {
        bloc.add(const ProductConfigStarted(_product));
        await Future<void>.delayed(const Duration(milliseconds: 5));
        bloc.add(const QuantityChanged(2));
        bloc.add(const QuantityChanged(3));
      },
      wait: const Duration(milliseconds: 120),
      verify: (bloc) {
        expect(bloc.state.quantity, 3);
        // Only one quote request should have resolved into state — the
        // restartable() transformer cancels the superseded QuantityChanged
        // handler (and, transitively, its QuoteRequested) before it can
        // apply a stale result.
        expect(bloc.state.quoteStatus, QuoteStatus.loaded);
      },
    );

    blocTest<ProductConfigBloc, ProductConfigState>(
      'Subscribe Now is blocked when the wallet balance is below ₹500',
      build: () {
        walletBalanceRepository.balance = 300;
        return build();
      },
      act: (bloc) async {
        bloc.add(const ProductConfigStarted(_product));
        await Future<void>.delayed(const Duration(milliseconds: 10));
        bloc.add(const FrequencyChanged(Frequency.daily));
        await Future<void>.delayed(const Duration(milliseconds: 10));
        bloc.add(const AddToCartRequested());
      },
      wait: const Duration(milliseconds: 20),
      verify: (bloc) {
        expect(bloc.state.walletCheckStatus, WalletCheckStatus.insufficient);
        expect(bloc.state.walletGateBlocks, isTrue);
        expect(
          bloc.state.addStatus,
          AddStatus.idle,
          reason: 'the gate must block the add call',
        );
        expect(cartRepository.requests, isEmpty);
      },
    );

    blocTest<ProductConfigBloc, ProductConfigState>(
      'One Time confirms are never gated by wallet balance',
      build: () {
        walletBalanceRepository.balance = 0;
        return build();
      },
      act: (bloc) async {
        bloc.add(const ProductConfigStarted(_product));
        await Future<void>.delayed(const Duration(milliseconds: 10));
        bloc.add(const AddToCartRequested());
      },
      wait: const Duration(milliseconds: 10),
      verify: (bloc) {
        expect(bloc.state.addStatus, AddStatus.success);
        expect(cartRepository.requests, hasLength(1));
      },
    );

    blocTest<ProductConfigBloc, ProductConfigState>(
      'a successful add clears the idempotency key; a retry after failure reuses it',
      build: () {
        cartRepository.addItemException = const ApiException(
          errorCode: 'NETWORK_ERROR',
          message: 'timeout',
        );
        return build();
      },
      act: (bloc) async {
        bloc.add(const ProductConfigStarted(_product));
        await Future<void>.delayed(const Duration(milliseconds: 10));
        bloc.add(const AddToCartRequested());
        await Future<void>.delayed(const Duration(milliseconds: 5));
        cartRepository.addItemException = null;
        bloc.add(const AddToCartRequested());
      },
      wait: const Duration(milliseconds: 10),
      verify: (bloc) {
        expect(cartRepository.requests, hasLength(2));
        expect(
          cartRepository.requests[0].idempotencyKey,
          cartRepository.requests[1].idempotencyKey,
          reason: 'a retry of the same attempt must reuse the original Idempotency-Key',
        );
        expect(bloc.state.addStatus, AddStatus.success);
        expect(bloc.state.addIdempotencyKey, isNull);
      },
    );
  });
}
