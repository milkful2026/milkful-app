import 'package:flutter_test/flutter_test.dart';
import 'package:milkful_app/features/orders/models/order_summary.dart';
import 'package:milkful_app/features/wallet/domain/ledger_copy.dart';
import 'package:milkful_app/features/wallet/models/ledger_entry.dart';

LedgerEntry _e(String type, {String ref = '', int amount = -100, String description = ''}) =>
    LedgerEntry(
      id: 'led_1',
      type: LedgerType(type),
      amountPaise: amount,
      balanceAfterPaise: 0,
      ref: ref,
      description: description,
      createdAt: DateTime.utc(2026, 8, 6, 1, 59, 15),
    );

void main() {
  group('LedgerEntry', () {
    test('fromJson keeps signed amounts and unknown types', () {
      final e = LedgerEntry.fromJson({
        'id': 'led_7',
        'type': 'SOMETHING_NEW',
        'amountPaise': -36700,
        'balanceAfterPaise': 662146,
        'ref': 'order:ord_1',
        'description': 'New thing',
        'createdAt': '2026-08-06T01:59:15+00:00',
      });
      expect(e.amountPaise, -36700);
      expect(e.type.wire, 'SOMETHING_NEW');
      expect(e.orderId, 'ord_1');
    });

    test('orderId follows the MA-148 ref conventions', () {
      String? id(String ref) => _e('REFUND', ref: ref).orderId;
      expect(id('order:ord_1'), 'ord_1');
      expect(id('refund:ord_1:rf_1'), 'ord_1');
      expect(id('refund:ord_1'), 'ord_1');
      for (final none in ['refund::rf_1', 'razorpay_payment:pay_1', 'opening:wal_1', 'manual-credit', 'order:']) {
        expect(id(none), isNull, reason: none);
      }
    });
  });

  group('titles, chips, icons', () {
    test('every ledger type', () {
      final table = {
        'ORDER_DEBIT': ('Paid for Order', 'Order', LedgerIcon.cart),
        'RECHARGE': ('Wallet Top-up', 'Top-up', LedgerIcon.walletAdd),
        'CASHBACK': ('Cashback', 'Cashback', LedgerIcon.gift),
        'REFERRAL_CREDIT': ('Referral Credit', 'Referral', LedgerIcon.people),
        'ADJUSTMENT': ('Adjustment', 'Adjustment', LedgerIcon.tune),
        'OPENING': ('Wallet Opened', 'Wallet', LedgerIcon.wallet),
      };
      table.forEach((type, expected) {
        final e = _e(type);
        expect((ledgerTitle(e), ledgerChipLabel(e, null), ledgerIcon(e)), expected, reason: type);
      });
    });

    test('order debit chip comes from the order source', () {
      final e = _e('ORDER_DEBIT', ref: 'order:ord_1');
      expect(ledgerChipLabel(e, OrderSource.subscription), 'Subscription');
      expect(ledgerChipLabel(e, OrderSource.checkout), 'One-time order');
      expect(ledgerChipLabel(e, null), 'Order');
    });

    test('refund title depends on an order ref', () {
      expect(ledgerTitle(_e('REFUND', ref: 'refund:ord_1:rf_1')), 'Refund for Order');
      expect(ledgerTitle(_e('REFUND', ref: 'manual-credit')), 'Refund');
      expect(ledgerChipLabel(_e('REFUND'), null), 'Refund');
    });

    test('unknown type falls back to the description and a title-cased chip', () {
      final e = _e('FOO_BAR', description: 'Something new');
      expect(ledgerTitle(e), 'Something new');
      expect(ledgerChipLabel(e, null), 'Foo Bar');
      expect(ledgerIcon(e), LedgerIcon.receipt);
      expect(ledgerTitle(_e('FOO_BAR')), 'Transaction');
    });
  });

  group('formats', () {
    test('signed amount has exactly one sign', () {
      expect(formatSignedAmount(-36700), '− ₹367');
      expect(formatSignedAmount(4500), '+ ₹45');
      expect(formatSignedAmount(4550), '+ ₹45.50');
      expect(formatSignedAmount(0), '₹0');
      expect(formatSignedAmount(-36700), isNot(contains('-₹')));
    });

    test('ordinals', () {
      final expected = {1: 'st', 2: 'nd', 3: 'rd', 4: 'th', 11: 'th', 12: 'th', 13: 'th', 21: 'st', 22: 'nd', 23: 'rd', 31: 'st'};
      expected.forEach((day, suffix) => expect(ordinal(day), suffix, reason: '$day'));
    });

    test('timestamp is IST, mock format', () {
      expect(formatLedgerTimestamp(DateTime.utc(2026, 8, 6, 1, 59, 15)), 'Thu, 6th Aug 26, 07:29:15 AM');
      // 20:00 UTC is 01:30 the next day in IST.
      expect(formatLedgerTimestamp(DateTime.utc(2026, 7, 31, 20)), 'Sat, 1st Aug 26, 01:30:00 AM');
    });

    test('month header omits the current year only', () {
      final today = DateTime(2026, 10, 2);
      expect(formatMonthHeader(DateTime(2026, 8), today), 'August');
      expect(formatMonthHeader(DateTime(2025, 12), today), 'December 2025');
    });

    test('filter types per group (MA-148 §8)', () {
      expect(TransactionFilter.all.types, isNull);
      expect(TransactionFilter.topUps.types, ['RECHARGE']);
      expect(TransactionFilter.orderPayments.types, ['ORDER_DEBIT']);
      expect(TransactionFilter.refundsCredits.types, ['REFUND', 'CASHBACK', 'REFERRAL_CREDIT', 'ADJUSTMENT']);
    });
  });
}
