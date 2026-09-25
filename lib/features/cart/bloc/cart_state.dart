import 'dart:math' as math;

import 'package:equatable/equatable.dart';

import '../../auth/models/delivery_address.dart';
import '../../catalog/models/product.dart';
import '../../checkout/data/pending_checkout_store.dart';
import '../../checkout/models/checkout_failure.dart';
import '../../checkout/models/checkout_result.dart';
import '../models/cart_line_item.dart';
import '../models/quote.dart';
import '../models/wallet_rules.dart';

enum CartLoadStatus { loading, loaded, failed }

/// MA-137 FR-5/FR-6 — the wallet balance and delivery address are loaded
/// alongside the cart but never block it: a failure hides that row only.
enum SideLoadStatus { loading, loaded, failed }

/// MA-137 FR-7/FR-8. `incomplete` means a Confirm may still be finishing
/// server-side — the persisted checkout is kept and the next Confirm
/// resumes it.
enum CheckoutStatus { idle, submitting, incomplete }

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
    this.payNowQuote,
    this.perDeliveryQuote,
    this.pendingRemovalId,
    this.writeErrorMessage,
    this.writesInFlight = 0,
    this.unsentQuantityEdits = const {},
    this.walletStatus = SideLoadStatus.loading,
    this.walletBalancePaise,
    this.addressStatus = SideLoadStatus.loading,
    this.deliveryAddress,
    this.userId,
    this.checkoutStatus = CheckoutStatus.idle,
    this.pendingCheckout,
    this.checkoutFailure,
    this.lineErrors = const {},
    this.checkoutResult,
  });

  final CartLoadStatus loadStatus;
  final String? loadErrorMessage;
  final List<CartLineItemView> items;
  final int cartVersion;
  final Quote? quote;

  /// MA-135 FR-2 — see `CartView.payNowQuote`/`CartView.perDeliveryQuote`.
  final Quote? payNowQuote;
  final Quote? perDeliveryQuote;

  /// MA-123 FR-5 — set while the removal confirmation dialog is open; the
  /// screen reads this to decide whether to show it, not a separate
  /// bool flag per item.
  final String? pendingRemovalId;

  /// Transient — surfaced once as a SnackBar by the screen, then cleared;
  /// never a permanent part of a "failed" load state (MA-123 FR-6, an
  /// already-loaded cart stays usable after a write failure).
  final String? writeErrorMessage;

  /// Quantity writes/removals not yet settled — Confirm Order waits for
  /// them so it always checks out the cartVersion the customer sees.
  final int writesInFlight;

  /// Line ids whose quantity the customer changed but whose write the
  /// screen hasn't sent yet (it waits 500 ms, MA-123 FR-4). Confirm waits
  /// for them too, or it would charge the old quantity the screen no
  /// longer shows.
  final Set<String> unsentQuantityEdits;

  final SideLoadStatus walletStatus;
  final int? walletBalancePaise;

  /// `loaded` with a null [deliveryAddress] means the profile has no
  /// default address (MA-137 FR-6's "No delivery address on file").
  final SideLoadStatus addressStatus;
  final DeliveryAddress? deliveryAddress;

  /// The Cognito `sub` from the stored access token — scopes the persisted
  /// checkout (MA-137 FR-9). Read locally, never from `GET /users/me`, so a
  /// failed profile load can't lose a pending checkout. `null` until read,
  /// or when signed out; Confirm stays disabled while it's `null`.
  final String? userId;

  final CheckoutStatus checkoutStatus;

  /// The Confirm in flight or left incomplete (key + the body it was sent
  /// with). While set, the cart is locked (FR-9).
  final PendingCheckout? pendingCheckout;

  /// Transient — shown once (dialog/SnackBar/banner) and then consumed.
  final CheckoutFailure? checkoutFailure;

  /// lineId -> LINE_INVALID reason, shown inline on that line's card.
  final Map<String, String> lineErrors;

  /// Set once when a checkout completes — the screen navigates on it.
  final CheckoutResult? checkoutResult;

  bool get isEmpty => loadStatus == CartLoadStatus.loaded && items.isEmpty;

  bool get hasSubscriptionLines => items.any((v) => v.lineItem.frequency.isSubscription);

  bool get hasOneTimeLines => items.any((v) => !v.lineItem.frequency.isSubscription);

  /// The "Pay now" breakdown. Falls back to the all-lines [quote] for an
  /// all-one-time cart when Cart Service predates the split (MA-137 §7),
  /// so a stale backend never shows an empty summary.
  Quote? get effectivePayNowQuote =>
      payNowQuote ?? (!hasSubscriptionLines && perDeliveryQuote == null ? quote : null);

  /// What Confirm Order charges now, in paise — the same half-up rounding
  /// Order Service applies (MA-136 FR-3.5), sent as `expectedPayNowPaise`.
  int get payNowPaise {
    final quote = effectivePayNowQuote;
    return quote == null ? 0 : (quote.netPayable * 100).round();
  }

  /// MA-137 FR-5 — pay-now plus the subscription minimum when any
  /// subscription line is in the cart (mirrors MA-136 FR-3.7).
  int get requiredPaise =>
      payNowPaise + (hasSubscriptionLines ? kSubscriptionMinWalletBalancePaise : 0);

  /// Null when the balance couldn't be read.
  int? get shortfallPaise => walletBalancePaise == null
      ? null
      : math.max(0, requiredPaise - walletBalancePaise!);

  /// MA-137 FR-9 — no edits while a checkout is pending: the next Confirm
  /// resends the saved key and body, and the server finishes that checkout
  /// whatever the cart looks like now.
  bool get isCartLocked =>
      pendingCheckout != null || checkoutStatus == CheckoutStatus.submitting;

  bool get canConfirm =>
      loadStatus == CartLoadStatus.loaded &&
      items.isNotEmpty &&
      userId != null &&
      writesInFlight == 0 &&
      unsentQuantityEdits.isEmpty &&
      checkoutStatus != CheckoutStatus.submitting;

  CartState copyWith({
    CartLoadStatus? loadStatus,
    String? loadErrorMessage,
    bool clearLoadErrorMessage = false,
    List<CartLineItemView>? items,
    int? cartVersion,
    Quote? quote,
    bool clearQuote = false,
    Quote? payNowQuote,
    bool clearPayNowQuote = false,
    Quote? perDeliveryQuote,
    bool clearPerDeliveryQuote = false,
    String? pendingRemovalId,
    bool clearPendingRemovalId = false,
    String? writeErrorMessage,
    bool clearWriteErrorMessage = false,
    int? writesInFlight,
    Set<String>? unsentQuantityEdits,
    SideLoadStatus? walletStatus,
    int? walletBalancePaise,
    SideLoadStatus? addressStatus,
    DeliveryAddress? deliveryAddress,
    bool clearDeliveryAddress = false,
    String? userId,
    CheckoutStatus? checkoutStatus,
    PendingCheckout? pendingCheckout,
    bool clearPendingCheckout = false,
    CheckoutFailure? checkoutFailure,
    bool clearCheckoutFailure = false,
    Map<String, String>? lineErrors,
    CheckoutResult? checkoutResult,
  }) => CartState(
    loadStatus: loadStatus ?? this.loadStatus,
    loadErrorMessage: clearLoadErrorMessage ? null : (loadErrorMessage ?? this.loadErrorMessage),
    items: items ?? this.items,
    cartVersion: cartVersion ?? this.cartVersion,
    quote: clearQuote ? null : (quote ?? this.quote),
    payNowQuote: clearPayNowQuote ? null : (payNowQuote ?? this.payNowQuote),
    perDeliveryQuote: clearPerDeliveryQuote ? null : (perDeliveryQuote ?? this.perDeliveryQuote),
    pendingRemovalId: clearPendingRemovalId ? null : (pendingRemovalId ?? this.pendingRemovalId),
    writeErrorMessage: clearWriteErrorMessage ? null : (writeErrorMessage ?? this.writeErrorMessage),
    writesInFlight: writesInFlight ?? this.writesInFlight,
    unsentQuantityEdits: unsentQuantityEdits ?? this.unsentQuantityEdits,
    walletStatus: walletStatus ?? this.walletStatus,
    walletBalancePaise: walletBalancePaise ?? this.walletBalancePaise,
    addressStatus: addressStatus ?? this.addressStatus,
    deliveryAddress: clearDeliveryAddress ? null : (deliveryAddress ?? this.deliveryAddress),
    userId: userId ?? this.userId,
    checkoutStatus: checkoutStatus ?? this.checkoutStatus,
    pendingCheckout: clearPendingCheckout ? null : (pendingCheckout ?? this.pendingCheckout),
    checkoutFailure: clearCheckoutFailure ? null : (checkoutFailure ?? this.checkoutFailure),
    lineErrors: lineErrors ?? this.lineErrors,
    checkoutResult: checkoutResult ?? this.checkoutResult,
  );

  @override
  List<Object?> get props => [
    loadStatus,
    loadErrorMessage,
    items,
    cartVersion,
    quote,
    payNowQuote,
    perDeliveryQuote,
    pendingRemovalId,
    writeErrorMessage,
    writesInFlight,
    unsentQuantityEdits,
    walletStatus,
    walletBalancePaise,
    addressStatus,
    deliveryAddress,
    userId,
    checkoutStatus,
    pendingCheckout,
    checkoutFailure,
    lineErrors,
    checkoutResult,
  ];
}
