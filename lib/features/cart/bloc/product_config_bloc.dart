import 'dart:async';

import 'package:bloc_concurrency/bloc_concurrency.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../core/network/api_client.dart';
import '../../../core/utils/id_generator.dart';
import '../../auth/data/profile_repository.dart';
import '../../catalog/data/catalog_repository.dart';
import '../../catalog/models/product.dart';
import '../../onboarding/data/registration_repository.dart';
import '../../subscriptions/data/subscription_repository.dart';
import '../../subscriptions/models/schedule.dart';
import '../data/cart_repository.dart';
import '../data/pricing_repository.dart';
import '../models/frequency.dart';
import '../../wallet/data/wallet_balance_repository.dart';
import 'product_config_event.dart';
import 'product_config_state.dart';

/// MA-120's `ProductConfigBloc`. Mirrors `RegistrationBloc`'s shape (one
/// bloc owning a multi-step, single-screen flow) more than `CatalogBloc`'s
/// (list/filter) — but borrows `CatalogBloc`'s `restartable()` convention
/// for the quote-refetch-on-change handler (see [QuoteRequested] below).
class ProductConfigBloc extends Bloc<ProductConfigEvent, ProductConfigState> {
  ProductConfigBloc({
    required Product product,
    required this._catalogRepository,
    required this._pricingRepository,
    required this._cartRepository,
    required this._walletBalanceRepository,
    required this._profileRepository,
    required this._registrationRepository,
    required this._subscriptionRepository,
  }) : super(ProductConfigState.initial(product)) {
    on<ProductConfigStarted>(_onStarted);
    on<FrequencyChanged>(_onFrequencyChanged);
    on<StartDateChanged>(_onStartDateChanged);
    on<QuantityChanged>(_onQuantityChanged);
    on<SlotSelected>(_onSlotSelected);
    on<AddToCartRequested>(_onAddToCartRequested);
    // restartable(): a frequency change racing a quantity change (or two
    // rapid quantity changes) must only ever apply the latest quote result
    // — see the MA-120 PR #7 review finding this resolves. One shared
    // event type (rather than per-event-type restartable() registrations,
    // which only supersede same-type events) covers cross-type races too.
    on<QuoteRequested>(_onQuoteRequested, transformer: restartable());
  }

  final CatalogRepository _catalogRepository;
  final PricingRepository _pricingRepository;
  final CartRepository _cartRepository;
  final WalletBalanceRepository _walletBalanceRepository;
  final ProfileRepository _profileRepository;
  final RegistrationRepository _registrationRepository;
  final SubscriptionRepository _subscriptionRepository;

  /// MA-133 FR-6 — resolved alongside [_deliveryState] in
  /// [_resolveDeliveryState] (same `getMe()` call, no extra round-trip).
  /// `null` if the profile lookup fails or the customer's default address
  /// predates this field — the slot picker simply doesn't render then
  /// (see [_onStarted]), never falling back to
  /// `RegistrationBloc.state.draft.zoneId` (that source is `null` outside
  /// an active registration session — MA-25 Step 6's review-fixed gap).
  String? _zoneId;

  /// Resolved once in [_onStarted] (MA-23 impl plan §2.1/§4A) — `null` if
  /// the profile lookup fails or the customer has no default address; a
  /// `null` here makes every subsequent quote fail fast with
  /// [PricingRepository.deliveryStateUnknownErrorCode] rather than quoting
  /// against a guessed state.
  String? _deliveryState;

  Future<void> _onStarted(
    ProductConfigStarted event,
    Emitter<ProductConfigState> emit,
  ) async {
    emit(ProductConfigState.initial(event.product));

    // Both run concurrently and are awaited here — the delivery state must
    // be settled (resolved or confirmed unresolvable) before the first
    // QuoteRequested fires below, otherwise whether that first quote sees
    // a real state or `null` would depend on unpredictable microtask
    // ordering rather than being deterministic.
    await Future.wait([_resolveDeliveryState(), _refreshStaleStock(event.product, emit)]);

    add(const QuoteRequested());
    if (state.frequency.isSubscription) {
      unawaited(_checkWalletBalance(emit));
    }
  }

  /// MA-120 §9 — the `Product` from route `extra:` seeds the initial
  /// render only. A failure here is non-fatal: the screen simply keeps
  /// showing the seeded product rather than blocking.
  Future<void> _refreshStaleStock(Product seeded, Emitter<ProductConfigState> emit) async {
    try {
      final fresh = await _catalogRepository.getProduct(seeded.id);
      if (isClosed) return;
      emit(state.copyWith(product: fresh));
    } catch (_) {
      // Keep the seeded product — see comment above.
    }
  }

  Future<void> _resolveDeliveryState() async {
    try {
      final profile = await _profileRepository.getMe();
      _deliveryState = profile.defaultAddressState;
      _zoneId = profile.defaultAddressZoneId;
    } catch (_) {
      _deliveryState = null;
      _zoneId = null;
    }
  }

  /// MA-133 FR-6. No zone (lookup failed, or the customer's default
  /// address predates `defaultAddressZoneId`) → no slots fetched, no
  /// default selection — the chip row simply doesn't render and Subscribe
  /// Now stays disabled via [ProductConfigState.slotGateBlocks], the same
  /// fail-closed posture MA-133 §11 specifies for an empty response too.
  Future<void> _fetchSlots(Emitter<ProductConfigState> emit) async {
    final zoneId = _zoneId;
    if (zoneId == null) {
      emit(state.copyWith(slotsStatus: SlotsStatus.notApplicable, slots: const [], clearSlotId: true));
      return;
    }
    emit(state.copyWith(slotsStatus: SlotsStatus.loading));
    try {
      final slots = await _registrationRepository.getDeliverySlots(zoneId);
      if (isClosed) return;
      String? firstAvailable;
      for (final slot in slots) {
        if (slot.available) {
          firstAvailable = slot.id;
          break;
        }
      }
      emit(
        state.copyWith(
          slotsStatus: SlotsStatus.loaded,
          slots: slots,
          slotId: firstAvailable,
          clearSlotId: firstAvailable == null,
        ),
      );
    } catch (_) {
      if (isClosed) return;
      emit(state.copyWith(slotsStatus: SlotsStatus.failed, slots: const [], clearSlotId: true));
    }
  }

  Future<void> _onSlotSelected(SlotSelected event, Emitter<ProductConfigState> emit) async {
    emit(state.copyWith(slotId: event.slotId));
  }

  Future<void> _onFrequencyChanged(
    FrequencyChanged event,
    Emitter<ProductConfigState> emit,
  ) async {
    emit(
      state.copyWith(
        frequency: event.frequency,
        clearStartDate: !event.frequency.isSubscription,
        walletCheckStatus: event.frequency.isSubscription
            ? WalletCheckStatus.loading
            : WalletCheckStatus.notApplicable,
        slotsStatus: event.frequency.isSubscription
            ? SlotsStatus.loading
            : SlotsStatus.notApplicable,
        slots: event.frequency.isSubscription ? state.slots : const [],
        clearSlotId: !event.frequency.isSubscription,
      ),
    );
    add(const QuoteRequested());
    if (event.frequency.isSubscription) {
      unawaited(_checkWalletBalance(emit));
      unawaited(_fetchSlots(emit));
    }
  }

  Future<void> _onStartDateChanged(
    StartDateChanged event,
    Emitter<ProductConfigState> emit,
  ) async {
    emit(state.copyWith(startDate: event.date));
  }

  Future<void> _onQuantityChanged(
    QuantityChanged event,
    Emitter<ProductConfigState> emit,
  ) async {
    emit(state.copyWith(quantity: event.quantity));
    add(const QuoteRequested());
  }

  Future<void> _onQuoteRequested(
    QuoteRequested event,
    Emitter<ProductConfigState> emit,
  ) async {
    emit(state.copyWith(quoteStatus: QuoteStatus.loading));
    if (_deliveryState == null) {
      // A UI-flow correctness rule, not an HTTP-client concern — see
      // PricingRepository's own doc comment on why this check lives here
      // rather than in DioPricingRepository (or duplicated into every
      // implementation, including fakes).
      emit(
        state.copyWith(
          quoteStatus: QuoteStatus.failed,
          quoteErrorMessage: "We couldn't determine your delivery address yet — pull to retry.",
        ),
      );
      return;
    }
    try {
      final quote = await _pricingRepository.quote(
        productId: state.product.id,
        quantity: state.quantity,
        frequency: state.frequency,
        deliveryState: _deliveryState,
      );
      emit(state.copyWith(quoteStatus: QuoteStatus.loaded, quote: quote));
    } on ApiException catch (e) {
      emit(
        state.copyWith(
          quoteStatus: QuoteStatus.failed,
          quoteErrorMessage: e.message,
        ),
      );
    } catch (_) {
      emit(state.copyWith(quoteStatus: QuoteStatus.failed));
    }
  }

  Future<void> _checkWalletBalance(Emitter<ProductConfigState> emit) async {
    try {
      final balance = await _walletBalanceRepository.getBalance();
      if (isClosed) return;
      emit(
        state.copyWith(
          walletCheckStatus: balance >= 500
              ? WalletCheckStatus.sufficient
              : WalletCheckStatus.insufficient,
          walletBalance: balance,
        ),
      );
    } on ApiException catch (e) {
      if (isClosed) return;
      emit(
        state.copyWith(
          walletCheckStatus: WalletCheckStatus.failed,
          walletErrorMessage: e.message,
        ),
      );
    } catch (_) {
      if (isClosed) return;
      emit(state.copyWith(walletCheckStatus: WalletCheckStatus.failed));
    }
  }

  Future<void> _onAddToCartRequested(
    AddToCartRequested event,
    Emitter<ProductConfigState> emit,
  ) async {
    if (!state.canConfirm) return;
    final key = state.addIdempotencyKey ?? newHexId();
    emit(state.copyWith(addStatus: AddStatus.loading, addIdempotencyKey: key));
    try {
      if (state.frequency.isSubscription) {
        // MA-133 FR-6 — a subscription-frequency confirm creates a real,
        // standing subscription (MA-131 FR-1) instead of a cart line item.
        // A one-time confirm below is completely unchanged.
        await _subscriptionRepository.create(
          productId: state.product.id,
          quantity: state.quantity,
          schedule: Schedule(type: _scheduleTypeFor(state.frequency)),
          startDate: state.startDate ?? DateTime.now(),
          slotId: state.slotId!, // guaranteed by canConfirm's slotGateBlocks check above
          idempotencyKey: key,
        );
      } else {
        await _cartRepository.addItem(
          productId: state.product.id,
          quantity: state.quantity,
          frequency: state.frequency,
          startDate: state.startDate,
          idempotencyKey: key,
        );
      }
      emit(
        state.copyWith(
          addStatus: AddStatus.success,
          clearAddIdempotencyKey: true,
        ),
      );
    } on ApiException catch (e) {
      emit(
        state.copyWith(addStatus: AddStatus.failed, addErrorMessage: e.message),
      );
    } catch (_) {
      emit(state.copyWith(addStatus: AddStatus.failed));
    }
  }

  /// MA-133 FR-6 — `Frequency` itself is deliberately not extended with
  /// `WEEKLY`/`CUSTOM_DAYS` (MA-131 §6's decision that Cart's `Frequency`
  /// stays narrow); those schedule types are only reachable from the My
  /// Subscriptions screen's own create flow, not here.
  ScheduleType _scheduleTypeFor(Frequency frequency) => switch (frequency) {
    Frequency.daily => ScheduleType.daily,
    Frequency.alternateDays => ScheduleType.alternateDays,
    Frequency.oneTime => throw StateError('One Time is never a subscription frequency'),
  };
}
