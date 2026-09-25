import 'package:equatable/equatable.dart';

import '../../../core/network/api_client.dart';

/// MA-137 FR-7 — every non-success outcome of Confirm Order, mapped from
/// the backend's error code. [clearsKey] says whether the attempt is over
/// (a fresh Confirm must use a new Idempotency-Key) or may still be
/// finishing server-side (the same key must be reused to resume it).
sealed class CheckoutFailure extends Equatable {
  const CheckoutFailure();

  bool get clearsKey => true;

  factory CheckoutFailure.fromApiException(ApiException e) {
    final details = e.details;
    switch (e.errorCode) {
      case 'INSUFFICIENT_BALANCE':
        return InsufficientBalance(shortfallPaise: (details['shortfallPaise'] as num?)?.toInt());
      case 'WALLET_NOT_ACTIVE':
        return const WalletNotActive();
      case 'CART_CHANGED':
      case 'CART_EMPTY':
        return const CartChanged();
      case 'PRICE_CHANGED':
        return const PriceChanged();
      case 'CHECKOUT_IN_PROGRESS':
        return const CheckoutInProgress();
      case 'LINE_INVALID':
        final lines = (details['lines'] as List<dynamic>? ?? const [])
            .whereType<Map<String, dynamic>>();
        return LineInvalid({
          for (final line in lines) line['lineId'] as String: line['reason'] as String,
        });
      case 'DELIVERY_ADDRESS_UNKNOWN':
        return const AddressUnknown();
    }
    // CHECKOUT_INCOMPLETE, DEPENDENCY_UNAVAILABLE, any other 5xx, and
    // transport failures: the checkout may be mid-way server-side, so the
    // same key must be kept and reused (MA-136 FR-2 resumes it).
    final status = e.statusCode;
    if (status == null || status >= 500 || e.errorCode == 'NETWORK_ERROR') {
      return const Incomplete();
    }
    return Unexpected(e.message);
  }
}

class InsufficientBalance extends CheckoutFailure {
  const InsufficientBalance({this.shortfallPaise});

  final int? shortfallPaise;

  @override
  List<Object?> get props => [shortfallPaise];
}

class WalletNotActive extends CheckoutFailure {
  const WalletNotActive();

  @override
  List<Object?> get props => [];
}

class CartChanged extends CheckoutFailure {
  const CartChanged();

  @override
  List<Object?> get props => [];
}

class PriceChanged extends CheckoutFailure {
  const PriceChanged();

  @override
  List<Object?> get props => [];
}

class CheckoutInProgress extends CheckoutFailure {
  const CheckoutInProgress();

  @override
  bool get clearsKey => false;

  @override
  List<Object?> get props => [];
}

class LineInvalid extends CheckoutFailure {
  const LineInvalid(this.reasonsByLineId);

  /// lineId -> SLOT_MISSING | START_DATE_PAST | PRODUCT_UNAVAILABLE
  final Map<String, String> reasonsByLineId;

  @override
  List<Object?> get props => [reasonsByLineId];
}

class AddressUnknown extends CheckoutFailure {
  const AddressUnknown();

  @override
  List<Object?> get props => [];
}

class Incomplete extends CheckoutFailure {
  const Incomplete();

  @override
  bool get clearsKey => false;

  @override
  List<Object?> get props => [];
}

class Unexpected extends CheckoutFailure {
  const Unexpected(this.message);

  final String message;

  @override
  List<Object?> get props => [message];
}
