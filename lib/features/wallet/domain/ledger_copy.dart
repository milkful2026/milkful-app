import 'package:intl/intl.dart';

import '../../../core/utils/ist_clock.dart';
import '../../../core/utils/money.dart';
import '../../orders/models/order_summary.dart';
import '../models/ledger_entry.dart';

/// MA-149 FR-4/FR-5 as pure functions: titles, chips, icons, the type filter
/// and the amount/date formats.

/// FR-5 — the filter groups and the `types` each sends (MA-148).
enum TransactionFilter {
  all('All transactions', 'All transactions', null, 'No transactions yet'),
  topUps('Top-ups', 'Top-ups', ['RECHARGE'], 'No top-ups yet'),
  orderPayments('Order payments', 'Order payments', ['ORDER_DEBIT'], 'No order payments yet'),
  refundsCredits(
    'Refunds & credits',
    'Refunds & credits',
    ['REFUND', 'CASHBACK', 'REFERRAL_CREDIT', 'ADJUSTMENT'],
    'No refunds or credits yet',
  );

  const TransactionFilter(this.label, this.chipLabel, this.types, this.emptyText);

  final String label;
  final String chipLabel;
  final List<String>? types;
  final String emptyText;
}

enum LedgerIcon { cart, walletAdd, gift, people, tune, wallet, receipt }

/// FR-4 row title.
String ledgerTitle(LedgerEntry e) => switch (e.type.wire) {
  'ORDER_DEBIT' => 'Paid for Order',
  'RECHARGE' => 'Wallet Top-up',
  'REFUND' => e.orderId != null ? 'Refund for Order' : 'Refund',
  'CASHBACK' => 'Cashback',
  'REFERRAL_CREDIT' => 'Referral Credit',
  'ADJUSTMENT' => 'Adjustment',
  'OPENING' => 'Wallet Opened',
  _ => e.description.isNotEmpty ? e.description : 'Transaction',
};

/// FR-4/FR-6 chip. For an order debit, [source] is the looked-up order's
/// source (null before it resolves, or when the lookup failed → "Order").
String ledgerChipLabel(LedgerEntry e, OrderSource? source) => switch (e.type.wire) {
  'ORDER_DEBIT' => switch (source) {
    OrderSource.subscription => 'Subscription',
    OrderSource.checkout => 'One-time order',
    null => 'Order',
  },
  'RECHARGE' => 'Top-up',
  'REFUND' => 'Refund',
  'CASHBACK' => 'Cashback',
  'REFERRAL_CREDIT' => 'Referral',
  'ADJUSTMENT' => 'Adjustment',
  'OPENING' => 'Wallet',
  _ => _titleCase(e.type.wire),
};

LedgerIcon ledgerIcon(LedgerEntry e) => switch (e.type.wire) {
  'ORDER_DEBIT' || 'REFUND' => LedgerIcon.cart,
  'RECHARGE' => LedgerIcon.walletAdd,
  'CASHBACK' => LedgerIcon.gift,
  'REFERRAL_CREDIT' => LedgerIcon.people,
  'ADJUSTMENT' => LedgerIcon.tune,
  'OPENING' => LedgerIcon.wallet,
  _ => LedgerIcon.receipt,
};

/// FR-4 — `+ ₹45` / `− ₹367` (U+2212) / `₹0`. The digits are always
/// `formatPaise` of the absolute value: `formatPaise` already prefixes a
/// negative with "-", so the sign must come from here only.
String formatSignedAmount(int paise) {
  final digits = formatPaise(paise.abs());
  if (paise > 0) return '+ $digits';
  if (paise < 0) return '− $digits';
  return digits;
}

/// FR-4 — `Thu, 6th Aug 26, 07:29:15 AM`, in IST.
String formatLedgerTimestamp(DateTime instant) {
  final ist = istNow(() => instant);
  final day = '${ist.day}${ordinal(ist.day)}';
  return '${DateFormat('EEE').format(ist)}, $day ${DateFormat('MMM yy, hh:mm:ss a').format(ist)}';
}

String ordinal(int day) {
  if (day >= 11 && day <= 13) return 'th';
  return switch (day % 10) {
    1 => 'st',
    2 => 'nd',
    3 => 'rd',
    _ => 'th',
  };
}

/// IST calendar month of an entry (first day of that month).
DateTime istMonth(DateTime instant) {
  final ist = istNow(() => instant);
  return DateTime(ist.year, ist.month);
}

/// FR-4 month header — "August", or "August 2025" when it isn't the
/// current IST year.
String formatMonthHeader(DateTime month, DateTime todayIst) {
  final name = DateFormat('MMMM').format(month);
  return month.year == todayIst.year ? name : '$name ${month.year}';
}

String _titleCase(String wire) {
  if (wire.isEmpty) return 'Other';
  return wire
      .toLowerCase()
      .split('_')
      .where((w) => w.isNotEmpty)
      .map((w) => '${w[0].toUpperCase()}${w.substring(1)}')
      .join(' ');
}
