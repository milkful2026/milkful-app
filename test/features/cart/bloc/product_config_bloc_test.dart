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
import 'package:milkful_app/features/onboarding/data/registration_repository.dart';

import '../../../fakes/fake_cart_repository.dart';
import '../../../fakes/fake_catalog_repository.dart';
import '../../../fakes/fake_pricing_repository.dart';
import '../../../fakes/fake_profile_repository.dart';
import '../../../fakes/fake_registration_repository.dart';
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
    late FakeRegistrationRepository registrationRepository;

    setUp(() {
      catalogRepository = FakeCatalogRepository(
        productsById: {'cow-milk': _product},
      );
      pricingRepository = FakePricingRepository(result: _quote);
      cartRepository = FakeCartRepository();
      walletBalanceRepository = FakeWalletBalanceRepository(balance: 600);
      // MA-25 Step 6 — defaultAddressZoneId is what the slot picker reads
      // (not RegistrationBloc's ephemeral draft.zoneId); most tests below
      // want it populated so the slot-fetch path actually runs.
      profileRepository = FakeProfileRepository(
        profile: const UserProfile(
          userId: 'user-1',
          name: 'Priya Sharma',
          mobile: '+919876543210',
          accountType: 'B2C',
          defaultAddressId: 'addr-1',
          defaultAddressState: 'Karnataka',
          defaultAddressZoneId: 'zone-1',
        ),
      );
      registrationRepository = FakeRegistrationRepository(
        slots: const [
          DeliverySlot(id: 'morning-6-8', label: 'Morning 6-8 AM'),
          DeliverySlot(id: 'evening-6-8', label: 'Evening 6-8 PM'),
        ],
      );
    });

    ProductConfigBloc build() => ProductConfigBloc(
      product: _product,
      catalogRepository: catalogRepository,
      pricingRepository: pricingRepository,
      cartRepository: cartRepository,
      walletBalanceRepository: walletBalanceRepository,
      profileRepository: profileRepository,
      registrationRepository: registrationRepository,
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

    blocTest<ProductConfigBloc, ProductConfigState>(
      'switching to a subscription frequency fetches delivery slots and '
      'defaults to the first available one',
      build: build,
      act: (bloc) async {
        bloc.add(const ProductConfigStarted(_product));
        await Future<void>.delayed(const Duration(milliseconds: 10));
        bloc.add(const FrequencyChanged(Frequency.daily));
      },
      wait: const Duration(milliseconds: 10),
      verify: (bloc) {
        expect(bloc.state.slotsStatus, SlotsStatus.loaded);
        expect(bloc.state.slots, hasLength(2));
        expect(bloc.state.slotId, 'morning-6-8');
      },
    );

    blocTest<ProductConfigBloc, ProductConfigState>(
      // Regression for the review-fixed RegistrationBloc-sourced gap: a
      // returning user with no in-session registration draft must still
      // reach a working (if empty) state, not a crash — see
      // product_config_bloc.dart's own comment on why this reads
      // defaultAddressZoneId, never RegistrationBloc.state.draft.zoneId.
      'a null defaultAddressZoneId never calls getDeliverySlots and the '
      'slot row stays empty',
      build: () {
        profileRepository.profile = const UserProfile(
          userId: 'user-1',
          name: 'Priya Sharma',
          mobile: '+919876543210',
          accountType: 'B2C',
          defaultAddressId: 'addr-1',
          defaultAddressState: 'Karnataka',
        );
        return build();
      },
      act: (bloc) async {
        bloc.add(const ProductConfigStarted(_product));
        await Future<void>.delayed(const Duration(milliseconds: 10));
        bloc.add(const FrequencyChanged(Frequency.daily));
      },
      wait: const Duration(milliseconds: 10),
      verify: (bloc) {
        expect(bloc.state.slotsStatus, SlotsStatus.notApplicable);
        expect(bloc.state.slots, isEmpty);
        expect(bloc.state.slotId, isNull);
      },
    );

    blocTest<ProductConfigBloc, ProductConfigState>(
      'SlotSelected updates the selected slot',
      build: build,
      act: (bloc) async {
        bloc.add(const ProductConfigStarted(_product));
        await Future<void>.delayed(const Duration(milliseconds: 10));
        bloc.add(const FrequencyChanged(Frequency.daily));
        await Future<void>.delayed(const Duration(milliseconds: 10));
        bloc.add(const SlotSelected('evening-6-8'));
      },
      wait: const Duration(milliseconds: 10),
      verify: (bloc) => expect(bloc.state.slotId, 'evening-6-8'),
    );

    blocTest<ProductConfigBloc, ProductConfigState>(
      'canConfirm is false for a subscription frequency with no slot selected',
      build: () {
        registrationRepository.slots = const [];
        return build();
      },
      act: (bloc) async {
        bloc.add(const ProductConfigStarted(_product));
        await Future<void>.delayed(const Duration(milliseconds: 10));
        bloc.add(const FrequencyChanged(Frequency.daily));
      },
      wait: const Duration(milliseconds: 10),
      verify: (bloc) {
        expect(bloc.state.slotId, isNull);
        expect(bloc.state.slotGateBlocks, isTrue);
        expect(bloc.state.canConfirm, isFalse);
      },
    );

    blocTest<ProductConfigBloc, ProductConfigState>(
      'AddToCartRequested for a subscription frequency adds a cart line '
      'carrying its start date and the selected slot (MA-137 FR-3 — the '
      'subscription itself starts at Confirm Order)',
      build: build,
      act: (bloc) async {
        bloc.add(const ProductConfigStarted(_product));
        await Future<void>.delayed(const Duration(milliseconds: 10));
        bloc.add(const FrequencyChanged(Frequency.daily));
        await Future<void>.delayed(const Duration(milliseconds: 10));
        bloc.add(const AddToCartRequested());
      },
      wait: const Duration(milliseconds: 10),
      verify: (bloc) {
        expect(bloc.state.addStatus, AddStatus.success);
        final request = cartRepository.requests.single;
        expect(request.productId, 'cow-milk');
        expect(request.frequency, Frequency.daily);
        expect(request.slotId, 'morning-6-8');
        expect(request.startDate, isNotNull);
      },
    );

    blocTest<ProductConfigBloc, ProductConfigState>(
      'a one-time confirm adds a cart line with no slot or start date',
      build: build,
      act: (bloc) async {
        bloc.add(const ProductConfigStarted(_product));
        await Future<void>.delayed(const Duration(milliseconds: 10));
        bloc.add(const AddToCartRequested());
      },
      wait: const Duration(milliseconds: 10),
      verify: (bloc) {
        expect(bloc.state.addStatus, AddStatus.success);
        final request = cartRepository.requests.single;
        expect(request.frequency, Frequency.oneTime);
        expect(request.slotId, isNull);
        expect(request.startDate, isNull);
      },
    );
  });
}
