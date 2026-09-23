import 'package:equatable/equatable.dart';

import '../../catalog/models/product.dart';
import '../../onboarding/data/registration_repository.dart';
import '../models/frequency.dart';
import '../models/quote.dart';

enum QuoteStatus { idle, loading, loaded, failed }

/// MA-133 FR-6 — only meaningful for a subscription-eligible product with
/// a subscription frequency selected; [notApplicable] for a one-time
/// confirm, which never needs a slot.
enum SlotsStatus { notApplicable, loading, loaded, failed }

/// Only meaningful for a subscription frequency (MA-120 FR-7) — stays
/// [notApplicable] for One Time, which is never gated on wallet balance.
enum WalletCheckStatus {
  notApplicable,
  loading,
  sufficient,
  insufficient,
  failed,
}

enum AddStatus { idle, loading, success, failed }

class ProductConfigState extends Equatable {
  const ProductConfigState({
    required this.product,
    required this.frequency,
    required this.quantity,
    this.startDate,
    this.quoteStatus = QuoteStatus.idle,
    this.quote,
    this.quoteErrorMessage,
    this.walletCheckStatus = WalletCheckStatus.notApplicable,
    this.walletBalance,
    this.walletErrorMessage,
    this.addStatus = AddStatus.idle,
    this.addErrorMessage,
    this.addIdempotencyKey,
    this.slotsStatus = SlotsStatus.notApplicable,
    this.slots = const [],
    this.slotId,
  });

  /// FR-2: One Time is the default selection on screen open.
  factory ProductConfigState.initial(Product product) => ProductConfigState(
    product: product,
    frequency: Frequency.oneTime,
    quantity: 1,
  );

  final Product product;
  final Frequency frequency;
  final int quantity;
  final DateTime? startDate;

  final QuoteStatus quoteStatus;
  final Quote? quote;
  final String? quoteErrorMessage;

  final WalletCheckStatus walletCheckStatus;
  final int? walletBalance;
  final String? walletErrorMessage;

  final AddStatus addStatus;
  final String? addErrorMessage;

  /// Generated once when `AddToCartRequested` first fires for a given
  /// confirm attempt, reused across any retry of that same attempt (MA-121
  /// FR-2/FR-8) — cleared back to `null` only on a fresh, successful add or
  /// when the customer changes the selection (a materially different
  /// request deserves its own key, not a stale one from an earlier attempt).
  final String? addIdempotencyKey;

  /// MA-133 FR-6. [slots] is populated once [slotsStatus] is
  /// [SlotsStatus.loaded] — empty means the zone had none, not that the
  /// fetch is still pending. [slotId] defaults to the first `available`
  /// slot but is customer-changeable before confirming.
  final SlotsStatus slotsStatus;
  final List<DeliverySlot> slots;
  final String? slotId;

  /// FR-7 — Subscribe Now is gated only for a subscription frequency with
  /// a confirmed-insufficient balance; One Time is never gated, and an
  /// in-flight/unknown wallet check fails closed (not gateable yet, but
  /// not blocked either — the screen shows its own loading/error state).
  bool get walletGateBlocks =>
      frequency.isSubscription &&
      walletCheckStatus == WalletCheckStatus.insufficient;

  /// MA-133 FR-6 — the Subscribe Now CTA additionally requires a selected
  /// slot for a subscription frequency; a one-time confirm is unaffected
  /// (mirrors [walletGateBlocks]'s existing gating pattern).
  bool get slotGateBlocks => frequency.isSubscription && slotId == null;

  bool get canConfirm =>
      quoteStatus == QuoteStatus.loaded &&
      !walletGateBlocks &&
      !slotGateBlocks &&
      addStatus != AddStatus.loading;

  ProductConfigState copyWith({
    Product? product,
    Frequency? frequency,
    int? quantity,
    DateTime? startDate,
    bool clearStartDate = false,
    QuoteStatus? quoteStatus,
    Quote? quote,
    String? quoteErrorMessage,
    WalletCheckStatus? walletCheckStatus,
    int? walletBalance,
    String? walletErrorMessage,
    AddStatus? addStatus,
    String? addErrorMessage,
    String? addIdempotencyKey,
    bool clearAddIdempotencyKey = false,
    SlotsStatus? slotsStatus,
    List<DeliverySlot>? slots,
    String? slotId,
    bool clearSlotId = false,
  }) => ProductConfigState(
    product: product ?? this.product,
    frequency: frequency ?? this.frequency,
    quantity: quantity ?? this.quantity,
    startDate: clearStartDate ? null : (startDate ?? this.startDate),
    quoteStatus: quoteStatus ?? this.quoteStatus,
    quote: quote ?? this.quote,
    quoteErrorMessage: quoteErrorMessage,
    walletCheckStatus: walletCheckStatus ?? this.walletCheckStatus,
    walletBalance: walletBalance ?? this.walletBalance,
    walletErrorMessage: walletErrorMessage,
    addStatus: addStatus ?? this.addStatus,
    addErrorMessage: addErrorMessage,
    addIdempotencyKey: clearAddIdempotencyKey
        ? null
        : (addIdempotencyKey ?? this.addIdempotencyKey),
    slotsStatus: slotsStatus ?? this.slotsStatus,
    slots: slots ?? this.slots,
    slotId: clearSlotId ? null : (slotId ?? this.slotId),
  );

  @override
  List<Object?> get props => [
    product,
    frequency,
    quantity,
    startDate,
    quoteStatus,
    quote,
    quoteErrorMessage,
    walletCheckStatus,
    walletBalance,
    walletErrorMessage,
    addStatus,
    addErrorMessage,
    addIdempotencyKey,
    slotsStatus,
    slots,
    slotId,
  ];
}
