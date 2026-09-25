import 'package:equatable/equatable.dart';

sealed class CartEvent extends Equatable {
  const CartEvent();

  @override
  List<Object?> get props => [];
}

class CartStarted extends CartEvent {
  const CartStarted();
}

/// Dispatched by [CartScreen]'s own debounce `Timer` (MA-123 FR-4, same
/// screen-owns-the-`Timer` pattern as `catalog_page.dart`'s search field) —
/// not fired on every stepper tap directly.
class QuantityWriteRequested extends CartEvent {
  const QuantityWriteRequested({required this.lineItemId, required this.quantity});

  final String lineItemId;
  final int quantity;

  @override
  List<Object?> get props => [lineItemId, quantity];
}

/// Sets [CartState.pendingRemovalId] so the screen can show the
/// confirmation dialog (MA-123 FR-5) — does not itself remove anything.
class ItemRemoveRequested extends CartEvent {
  const ItemRemoveRequested({required this.lineItemId});

  final String lineItemId;

  @override
  List<Object?> get props => [lineItemId];
}

class ItemRemoveCancelled extends CartEvent {
  const ItemRemoveCancelled();
}

class ItemRemoveConfirmed extends CartEvent {
  const ItemRemoveConfirmed({required this.lineItemId});

  final String lineItemId;

  @override
  List<Object?> get props => [lineItemId];
}

/// MA-137 FR-2/FR-5 — re-fetch the cart (and wallet balance) after coming
/// back from Catalog or Wallet, keeping the current list on screen rather
/// than flashing the loading skeleton.
class CartRefreshRequested extends CartEvent {
  const CartRefreshRequested();
}

/// MA-137 FR-7 — the Confirm Order button.
class CheckoutRequested extends CartEvent {
  const CheckoutRequested();
}

/// The screen has shown [CartState.checkoutFailure]; clear it so it's
/// shown exactly once.
class CheckoutFeedbackConsumed extends CartEvent {
  const CheckoutFeedbackConsumed();
}
