/// MA-120 FR-7 / MA-137 FR-5 — the wallet balance a customer must hold to
/// start a subscription. One constant shared by the product screen's gate
/// and the Review Cart shortfall hint, and mirrored server-side by Cart's
/// `wallet_minimum_balance` and Order's `subscription_min_balance_paise`.
const kSubscriptionMinWalletBalanceRupees = 500;

const kSubscriptionMinWalletBalancePaise = kSubscriptionMinWalletBalanceRupees * 100;
