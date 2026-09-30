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

String _titleCase(String wire) {
  if (wire.isEmpty) return 'Unknown';
  return wire
      .toLowerCase()
      .split('_')
      .where((w) => w.isNotEmpty)
      .map((w) => '${w[0].toUpperCase()}${w.substring(1)}')
      .join(' ');
}
