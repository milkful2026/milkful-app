import 'package:equatable/equatable.dart';

/// MA-27 — one Wallet ledger entry as returned by
/// `GET /wallet/me/transactions` (MA-24). Every entry is a completed money
/// movement; `amountPaise` is signed (+credit / −debit).
class LedgerEntry extends Equatable {
  const LedgerEntry({
    required this.id,
    required this.type,
    required this.amountPaise,
    required this.balanceAfterPaise,
    required this.ref,
    required this.description,
    required this.createdAt,
  });

  final String id;
  final LedgerType type;
  final int amountPaise;
  final int balanceAfterPaise;
  final String ref;
  final String description;
  final DateTime createdAt;

  factory LedgerEntry.fromJson(Map<String, dynamic> json) => LedgerEntry(
    id: json['id'] as String,
    type: LedgerType(json['type'] as String? ?? ''),
    amountPaise: (json['amountPaise'] as num).toInt(),
    balanceAfterPaise: (json['balanceAfterPaise'] as num).toInt(),
    ref: json['ref'] as String? ?? '',
    description: json['description'] as String? ?? '',
    createdAt: DateTime.parse(json['createdAt'] as String),
  );

  /// MA-148 FR-3 ref conventions: `order:{orderId}` (an order debit) or
  /// `refund:{orderId}[:{refundId}]` (an order refund). Null otherwise.
  String? get orderId {
    final String rest;
    if (ref.startsWith('order:')) {
      rest = ref.substring('order:'.length);
    } else if (ref.startsWith('refund:')) {
      rest = ref.substring('refund:'.length).split(':').first;
    } else {
      return null;
    }
    return rest.isEmpty ? null : rest;
  }

  @override
  List<Object?> get props => [id, type, amountPaise, balanceAfterPaise, ref, description, createdAt];
}

/// Wallet's `LedgerType`, kept as its wire string so a type a newer backend
/// adds still parses (and renders with a fallback).
class LedgerType extends Equatable {
  const LedgerType(this.wire);

  final String wire;

  static const opening = LedgerType('OPENING');
  static const recharge = LedgerType('RECHARGE');
  static const orderDebit = LedgerType('ORDER_DEBIT');
  static const refund = LedgerType('REFUND');
  static const cashback = LedgerType('CASHBACK');
  static const referralCredit = LedgerType('REFERRAL_CREDIT');
  static const adjustment = LedgerType('ADJUSTMENT');

  @override
  List<Object?> get props => [wire];
}

class LedgerPage {
  const LedgerPage({required this.items, this.nextCursor});

  final List<LedgerEntry> items;
  final String? nextCursor;

  factory LedgerPage.fromJson(Map<String, dynamic> json) => LedgerPage(
    items: [
      for (final item in (json['items'] as List? ?? const []))
        LedgerEntry.fromJson(item as Map<String, dynamic>),
    ],
    nextCursor: json['nextCursor'] as String?,
  );
}
