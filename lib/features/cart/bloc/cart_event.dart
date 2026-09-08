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
