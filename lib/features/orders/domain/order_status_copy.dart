import '../models/order_summary.dart';

/// Status labels, tones and the "known not charged" rule — shared by My
/// Orders (MA-145 FR-6/FR-8) and Order Detail (MA-146 FR-3/FR-5). Pure
/// Dart: widgets map [ChipTone] onto theme tokens.
enum ChipTone { neutral, error, warning, primary }

enum ChipIcon { checkCircle, schedule, errorOutline, cancel, info, calendar }

class StatusChipSpec {
  const StatusChipSpec(this.label, this.tone, [this.icon]);

  final String label;
  final ChipTone tone;
  final ChipIcon? icon;
}

/// MA-145 FR-6. No "Delivered" state exists until delivery tracking
/// (MA-102) records one.
StatusChipSpec statusChip(OrderStatus status) => switch (status.wire) {
  'CONFIRMED' => const StatusChipSpec('Order Placed', ChipTone.neutral, ChipIcon.checkCircle),
  'CREATED' => const StatusChipSpec('Processing', ChipTone.neutral, ChipIcon.schedule),
  'PAYMENT_FAILED' => const StatusChipSpec(
    'Payment Failed',
    ChipTone.error,
    ChipIcon.errorOutline,
  ),
  'CANCELLED' => const StatusChipSpec('Cancelled', ChipTone.error, ChipIcon.cancel),
  'NEEDS_ATTENTION' => const StatusChipSpec('Under Review', ChipTone.warning, ChipIcon.info),
  'FAILED' => const StatusChipSpec('Failed', ChipTone.error, ChipIcon.errorOutline),
  _ => StatusChipSpec(_titleCase(status.wire), ChipTone.neutral),
};

const scheduledChip = StatusChipSpec('Scheduled', ChipTone.primary, ChipIcon.calendar);

/// True only where the backend has *proven* no debit landed: a declined
/// charge, a checkout cancelled through the Wallet void (MA-144 PD-1), or a
/// subscription order closed past its charge deadline after a void
/// (MA-143, `NEEDS_ATTENTION` + `CUTOFF_PASSED`). Any other
/// `NEEDS_ATTENTION` (e.g. `SWEEP_EXHAUSTED`) may have been charged.
bool isKnownNotCharged(OrderSummary order) => switch (order.status.wire) {
  'CANCELLED' || 'PAYMENT_FAILED' => true,
  'NEEDS_ATTENTION' => order.failureReason == 'CUTOFF_PASSED',
  _ => false,
};

/// Amount shown struck through: known not charged, or a legacy `FAILED`
/// order (nothing sets it today; its charge isn't known).
bool isAmountStruck(OrderSummary order) =>
    isKnownNotCharged(order) || order.status == OrderStatus.failed;

// --- MA-146 Order Detail ---------------------------------------------------

/// FR-3 — the banner uses the same labels and tones as the list chip.
StatusChipSpec bannerSpec(OrderStatus status) => statusChip(status);

/// FR-3 — shown under the banner for statuses that didn't go through.
bool showsReason(OrderStatus status) => const {
  'PAYMENT_FAILED',
  'CANCELLED',
  'NEEDS_ATTENTION',
  'FAILED',
}.contains(status.wire);

/// FR-3 reason copy. "You weren't charged" appears only for
/// `CUTOFF_PASSED`, where a Wallet void proved it (MA-142/143/144); for
/// `SWEEP_EXHAUSTED` the charge may be unknown, so the copy only promises
/// no double charge (matching MA-144's CHECKOUT_NEEDS_ATTENTION).
String reasonText(String? failureReason) => switch (failureReason) {
  'INSUFFICIENT_BALANCE' => "Your wallet didn't have enough balance for this order.",
  'WALLET_NOT_ACTIVE' => "Your wallet wasn't active when this order was placed.",
  'DELIVERY_ADDRESS_UNKNOWN' => "We couldn't find a delivery address on your account.",
  'PRODUCT_UNAVAILABLE' => 'This product is no longer available.',
  'CUTOFF_PASSED' =>
    "This order couldn't be completed before the delivery cut-off. You weren't charged.",
  'SWEEP_EXHAUSTED' =>
    "We couldn't finish this order automatically. Our team has been alerted, "
        "and you won't be charged twice.",
  _ => 'Something went wrong with this order.',
};

/// FR-5 caption under Grand Total.
String? billCaption(OrderSummary order) {
  if (isKnownNotCharged(order)) return 'Not charged';
  if (order.status == OrderStatus.needsAttention) return 'Charge under review';
  return null;
}

/// FR-3 — `ord_3f9a2c1b…` → `#3F9A2C1B` (first 8 characters after the
/// `ord_` prefix, uppercased).
String displayOrderId(String orderId) {
  final raw = orderId.startsWith('ord_') ? orderId.substring(4) : orderId;
  final short = raw.length > 8 ? raw.substring(0, 8) : raw;
  return '#${short.toUpperCase()}';
}

String _titleCase(String wire) {
  if (wire.isEmpty) return 'Unknown';
  return wire
      .toLowerCase()
      .split('_')
      .where((w) => w.isNotEmpty)
      .map((w) => '${w[0].toUpperCase()}${w.substring(1)}')
      .join(' ');
}
