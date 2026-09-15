import 'package:flutter/material.dart';

/// MA-125 FR-1: shown at `/wallet` in place of [WalletScreen] while
/// `AppConfig.walletEnabled` is `false` — the nav item stays visible, but
/// tapping it doesn't yet reach the real screen (dark-shipped until
/// MA-126/MA-127 are deployed somewhere this build can reach).
class WalletComingSoon extends StatelessWidget {
  const WalletComingSoon({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        key: const Key('wallet-coming-soon'),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.account_balance_wallet_outlined, size: 48, color: Colors.grey.shade400),
            const SizedBox(height: 12),
            const Text('Wallet is coming soon'),
          ],
        ),
      ),
    );
  }
}
