import 'package:equatable/equatable.dart';

import '../../catalog/models/product.dart';
import '../models/cart_line_item.dart';
import '../models/quote.dart';

enum CartLoadStatus { loading, loaded, failed }

/// Pairs a cart line item with its resolved [Product] — `null` product
/// means that item's own `getProduct` lookup failed (MA-123 FR-2's per-row
/// degradation), not that the whole screen failed to load.
class CartLineItemView extends Equatable {
  const CartLineItemView({required this.lineItem, this.product});

  final CartLineItem lineItem;
  final Product? product;

  CartLineItemView copyWith({CartLineItem? lineItem}) =>
      CartLineItemView(lineItem: lineItem ?? this.lineItem, product: product);

  @override
  List<Object?> get props => [lineItem, product];
}

class CartState extends Equatable {
  const CartState({
    this.loadStatus = CartLoadStatus.loading,
    this.loadErrorMessage,
    this.items = const [],
    this.cartVersion = 0,
    this.quote,
    this.pendingRemovalId,
    this.writeErrorMessage,
  });

  final CartLoadStatus loadStatus;
  final String? loadErrorMessage;
  final List<CartLineItemView> items;
  final int cartVersion;
  final Quote? quote;

  /// MA-123 FR-5 — set while the removal confirmation dialog is open; the
  /// screen reads this to decide whether to show it, not a separate
  /// bool flag per item.
  final String? pendingRemovalId;

  /// Transient — surfaced once as a SnackBar by the screen, then cleared;
  /// never a permanent part of a "failed" load state (MA-123 FR-6, an
  /// already-loaded cart stays usable after a write failure).
  final String? writeErrorMessage;

  bool get isEmpty => loadStatus == CartLoadStatus.loaded && items.isEmpty;

  CartState copyWith({
    CartLoadStatus? loadStatus,
    String? loadErrorMessage,
    List<CartLineItemView>? items,
    int? cartVersion,
    Quote? quote,
    bool clearQuote = false,
    String? pendingRemovalId,
    bool clearPendingRemovalId = false,
    String? writeErrorMessage,
    bool clearWriteErrorMessage = false,
  }) => CartState(
    loadStatus: loadStatus ?? this.loadStatus,
    loadErrorMessage: loadErrorMessage,
    items: items ?? this.items,
    cartVersion: cartVersion ?? this.cartVersion,
    quote: clearQuote ? null : (quote ?? this.quote),
    pendingRemovalId: clearPendingRemovalId ? null : (pendingRemovalId ?? this.pendingRemovalId),
    writeErrorMessage: clearWriteErrorMessage ? null : (writeErrorMessage ?? this.writeErrorMessage),
  );

  @override
  List<Object?> get props => [
    loadStatus,
    loadErrorMessage,
    items,
    cartVersion,
    quote,
    pendingRemovalId,
    writeErrorMessage,
  ];
}
