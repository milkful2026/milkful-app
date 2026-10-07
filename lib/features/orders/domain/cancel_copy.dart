import 'package:intl/intl.dart';

import '../../../core/utils/ist_clock.dart';
import '../../../core/utils/money.dart';
import '../models/order_summary.dart';

/// MA-155 — the cancel flow's copy (Order Detail sheet, results, Scheduled
/// Delivery dialog), kept out of the widgets. Pure Dart.

String reasonLabel(CancelReason reason) => switch (reason) {
  CancelReason.orderedByMistake => 'Ordered by mistake',
  CancelReason.notHome => "Won't be home",
  CancelReason.changedMind => 'Changed my mind',
  CancelReason.other => 'Other',
};

/// FR-1 — "Free cancellation until 8:00 PM, Wed 7 Oct", in IST.
String cancelPolicyLine(DateTime cancellableUntil) {
  final ist = istNow(() => cancellableUntil);
  return 'Free cancellation until ${DateFormat('h:mm a').format(ist)}, '
      '${DateFormat('EEE d MMM').format(ist)}';
}

/// FR-5 — the same line for a scheduled delivery, from its date.
String deliveryPolicyLine(DateTime deliveryDate) => cancelPolicyLine(deliveryCutoff(deliveryDate));

/// FR-2 — what the sheet promises before the customer confirms.
String sheetPolicy(OrderSummary order) => order.amountPaise > 0
    ? "You'll get a full refund of ${_amount(order)} to your Milkful Wallet."
    : 'Nothing was charged for this order.';

/// FR-3 — the SnackBar after a successful cancel. Never says "refunded"
/// while the refund is still pending (MA-155 §5).
String cancelResultMessage(OrderSummary order) => switch (order.refundState) {
  RefundState.refunded => 'Order cancelled. ${_amount(order)} refunded to your Wallet.',
  RefundState.pending => 'Order cancelled. Your refund is on its way.',
  _ => 'Order cancelled.',
};

const cancelCutoffPassedMessage =
    "It's past the 8 PM cut-off, so this order can't be cancelled now.";
const cancelNotCancellableMessage = "This order can't be cancelled anymore.";
const cancelFailedMessage = "Couldn't cancel. Try again.";

/// FR-6 — shown instead of the Cancel action once the cut-off has passed.
const cancellationClosedLine = 'Cancellation closed at 8 PM the day before delivery.';

const shopForTomorrowLabel = 'Shop for tomorrow';

// --- FR-5: Scheduled Delivery ------------------------------------------------

String cancelDeliveryBody(String productName, DateTime date) =>
    "Your $productName delivery on ${_shortDate(date)} won't be sent and you won't be "
    'charged. Your subscription continues as usual.';

String deliveryCancelledMessage(DateTime date) => 'Delivery on ${_shortDate(date)} cancelled.';

const deliveryCutoffPassedMessage =
    "It's past the 8 PM cut-off, so this delivery can't be cancelled now.";

/// The delivery was already created as an order (MA-154's same-day path):
/// Skip refuses it, but the order itself can still be cancelled.
const deliveryAlreadyOrderMessage =
    'This delivery is already an order. Cancel it from the order instead.';

String _amount(OrderSummary order) => formatPaise(order.amountPaise, alwaysDecimals: true);

String _shortDate(DateTime date) => DateFormat('EEE d MMM').format(date);
