import 'package:bloc_test/bloc_test.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:milkful_app/core/network/api_client.dart';
import 'package:milkful_app/features/cart/bloc/cart_bloc.dart';
import 'package:milkful_app/features/cart/bloc/cart_event.dart';
import 'package:milkful_app/features/cart/bloc/cart_state.dart';
import 'package:milkful_app/features/cart/models/cart_line_item.dart';
import 'package:milkful_app/features/cart/models/cart_view.dart';
import 'package:milkful_app/features/cart/models/frequency.dart';
import 'package:milkful_app/features/cart/models/quote.dart';
import 'package:milkful_app/features/catalog/models/product.dart';

import '../../../fakes/fake_cart_repository.dart';
import '../../../fakes/fake_catalog_repository.dart';

const _cowMilk = Product(
  id: 'cow-milk',
  categoryId: 'milk',
  name: 'Cow Milk',
  description: 'Farm-fresh cow milk',
  unit: '1L Bottle',
  price: 68,
  stockState: StockState.inStock,
);

const _buffaloMilk = Product(
  id: 'buffalo-milk',
  categoryId: 'milk',
  name: 'Buffalo Milk',
  description: 'Rich buffalo milk',
  unit: '1L Bottle',
  price: 90,
  stockState: StockState.inStock,
  subscriptionEligible: true,
);

const _lineItem1 = CartLineItem(
  id: 'li-1',
  productId: 'cow-milk',
  quantity: 1,
  frequency: Frequency.oneTime,
  addedAt: '2026-08-31T10:00:00.000Z',
);

const _lineItem2 = CartLineItem(
  id: 'li-2',
  productId: 'buffalo-milk',
  quantity: 1,
  frequency: Frequency.daily,
  startDate: '2026-09-01',
  addedAt: '2026-08-31T10:00:00.000Z',
);

const _quote = Quote(basePrice: 158, taxAmount: 7.9, taxRate: 5, deliveryFee: 20, netPayable: 185.9);

void main() {
  group('CartBloc', () {
    late FakeCartRepository cartRepository;
    late FakeCatalogRepository catalogRepository;

    setUp(() {
      cartRepository = FakeCartRepository(
        getCartResult: const CartView(
          items: [_lineItem1, _lineItem2],
          cartVersion: 1,
          quote: _quote,
        ),
      );
      catalogRepository = FakeCatalogRepository(
        productsById: {'cow-milk': _cowMilk, 'buffalo-milk': _buffaloMilk},
      );
    });

    CartBloc build() =>
        CartBloc(cartRepository: cartRepository, catalogRepository: catalogRepository);

    blocTest<CartBloc, CartState>(
      'CartStarted resolves items and products, and loads the quote',
      build: build,
      act: (bloc) => bloc.add(const CartStarted()),
      verify: (bloc) {
        expect(bloc.state.loadStatus, CartLoadStatus.loaded);
        expect(bloc.state.items, hasLength(2));
        expect(bloc.state.items[0].product, _cowMilk);
        expect(bloc.state.items[1].product, _buffaloMilk);
        expect(bloc.state.cartVersion, 1);
        expect(bloc.state.quote, _quote);
      },
    );

    blocTest<CartBloc, CartState>(
      'a per-item getProduct failure degrades only that row, not the whole load',
      build: () {
        catalogRepository.productsById = {'cow-milk': _cowMilk};
        return build();
      },
      act: (bloc) => bloc.add(const CartStarted()),
      verify: (bloc) {
        expect(bloc.state.loadStatus, CartLoadStatus.loaded);
        final buffaloRow = bloc.state.items.firstWhere((v) => v.lineItem.id == 'li-2');
        expect(buffaloRow.product, isNull);
      },
    );

    blocTest<CartBloc, CartState>(
      'a getCart failure resolves to a failed load state',
      build: () {
        cartRepository.getCartException = const ApiException(
          errorCode: 'NETWORK_ERROR',
          message: 'offline',
        );
        return build();
      },
      act: (bloc) => bloc.add(const CartStarted()),
      verify: (bloc) {
        expect(bloc.state.loadStatus, CartLoadStatus.failed);
        expect(bloc.state.loadErrorMessage, 'offline');
      },
    );

    blocTest<CartBloc, CartState>(
      'an empty cart (no items) loads with an empty list and no quote',
      build: () {
        cartRepository.getCartResult = const CartView(items: [], cartVersion: 0);
        return build();
      },
      act: (bloc) => bloc.add(const CartStarted()),
      verify: (bloc) {
        expect(bloc.state.isEmpty, isTrue);
        expect(bloc.state.quote, isNull);
      },
    );

    blocTest<CartBloc, CartState>(
      'QuantityWriteRequested calls updateItem with the full item list and current cartVersion',
      build: build,
      act: (bloc) async {
        bloc.add(const CartStarted());
        await Future<void>.delayed(const Duration(milliseconds: 5));
        bloc.add(const QuantityWriteRequested(lineItemId: 'li-1', quantity: 3));
      },
      wait: const Duration(milliseconds: 20),
      verify: (bloc) {
        expect(cartRepository.updateItemRequests, hasLength(1));
        final request = cartRepository.updateItemRequests.single;
        expect(request.ifVersion, 1);
        expect(request.items, hasLength(2));
        expect(request.items.firstWhere((i) => i.id == 'li-1').quantity, 3);
      },
    );

    blocTest<CartBloc, CartState>(
      'a 409 on updateItem silently refetches and reapplies the target quantity, with no error',
      build: () {
        cartRepository = FakeCartRepository(
          getCartResult: const CartView(items: [_lineItem1, _lineItem2], cartVersion: 1, quote: _quote),
          updateItemException: const ApiException(
            errorCode: 'CART_VERSION_CONFLICT',
            message: 'stale version',
            statusCode: 409,
          ),
        )..updateItemFailuresRemaining = 1;
        return CartBloc(cartRepository: cartRepository, catalogRepository: catalogRepository);
      },
      act: (bloc) async {
        bloc.add(const CartStarted());
        await Future<void>.delayed(const Duration(milliseconds: 5));
        bloc.add(const QuantityWriteRequested(lineItemId: 'li-1', quantity: 5));
      },
      wait: const Duration(milliseconds: 20),
      verify: (bloc) {
        expect(bloc.state.writeErrorMessage, isNull);
        expect(cartRepository.updateItemRequests, hasLength(2));
        expect(cartRepository.updateItemRequests.last.items.firstWhere((i) => i.id == 'li-1').quantity, 5);
      },
    );

    blocTest<CartBloc, CartState>(
      'removing the last item transitions straight to the empty state without an extra getCart call',
      build: () {
        cartRepository = FakeCartRepository(
          getCartResult: const CartView(items: [_lineItem1], cartVersion: 1, quote: _quote),
        );
        return CartBloc(cartRepository: cartRepository, catalogRepository: catalogRepository);
      },
      act: (bloc) async {
        bloc.add(const CartStarted());
        await Future<void>.delayed(const Duration(milliseconds: 5));
        bloc.add(const ItemRemoveConfirmed(lineItemId: 'li-1'));
      },
      wait: const Duration(milliseconds: 20),
      verify: (bloc) {
        expect(bloc.state.isEmpty, isTrue);
        expect(bloc.state.quote, isNull);
        // Exactly one getCart call: the initial CartStarted load. Removing
        // the last item must not trigger a second one (MA-123 FR-5).
        expect(cartRepository.getCartCallCount, 1);
      },
    );

    blocTest<CartBloc, CartState>(
      'ItemRemoveRequested sets pendingRemovalId without removing anything',
      build: build,
      act: (bloc) async {
        bloc.add(const CartStarted());
        await Future<void>.delayed(const Duration(milliseconds: 5));
        bloc.add(const ItemRemoveRequested(lineItemId: 'li-1'));
      },
      wait: const Duration(milliseconds: 10),
      verify: (bloc) {
        expect(bloc.state.pendingRemovalId, 'li-1');
        expect(bloc.state.items, hasLength(2));
      },
    );

    blocTest<CartBloc, CartState>(
      'a non-conflict write failure reverts the optimistic change and surfaces the message',
      build: () {
        cartRepository.updateItemException = const ApiException(
          errorCode: 'STOCK_EXCEEDED',
          message: 'Only 2 left in stock',
        );
        return build();
      },
      act: (bloc) async {
        bloc.add(const CartStarted());
        await Future<void>.delayed(const Duration(milliseconds: 5));
        bloc.add(const QuantityWriteRequested(lineItemId: 'li-1', quantity: 10));
      },
      wait: const Duration(milliseconds: 20),
      verify: (bloc) {
        expect(bloc.state.writeErrorMessage, 'Only 2 left in stock');
        expect(bloc.state.items.firstWhere((v) => v.lineItem.id == 'li-1').lineItem.quantity, 1);
      },
    );
  });
}
