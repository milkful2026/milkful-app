import 'package:flutter/material.dart';

/// MA-125 FR-9. Reached from the balance card's `Passbook` button and the
/// `View All Transactions` link — both route here until MA-27 (Transaction
/// History) ships and replaces this builder.
class WalletTransactionsPlaceholder extends StatelessWidget {
  const WalletTransactionsPlaceholder({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(leading: const BackButton(), title: const Text('Transactions')),
      body: const Center(
        key: Key('wallet-transactions-placeholder'),
        child: Text('Transaction history coming soon'),
      ),
    );
  }
}
