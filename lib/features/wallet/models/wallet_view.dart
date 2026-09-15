import 'package:equatable/equatable.dart';

import 'wallet_status.dart';

/// `GET /wallet/me`'s response shape (MA-127 FR-1) — balance in **paise**,
/// plus the recharge bounds the app reads rather than hard-coding (MA-125
/// §6). Distinct from MA-1's `GET /wallet/me/status`, which stays on its
/// original whole-rupee body and is not consumed by this screen.
class WalletView extends Equatable {
  const WalletView({
    required this.walletId,
    required this.status,
    required this.balancePaise,
    required this.currency,
    required this.rechargeMinPaise,
    required this.rechargeMaxPaise,
  });

  final String? walletId;
  final WalletStatus status;
  final int balancePaise;
  final String currency;
  final int rechargeMinPaise;
  final int rechargeMaxPaise;

  factory WalletView.fromJson(Map<String, dynamic> json) => WalletView(
    walletId: json['walletId'] as String?,
    status: WalletStatus.fromWire(json['status'] as String),
    balancePaise: json['balancePaise'] as int,
    currency: json['currency'] as String,
    rechargeMinPaise: json['rechargeMinPaise'] as int,
    rechargeMaxPaise: json['rechargeMaxPaise'] as int,
  );

  @override
  List<Object?> get props => [
    walletId,
    status,
    balancePaise,
    currency,
    rechargeMinPaise,
    rechargeMaxPaise,
  ];
}
