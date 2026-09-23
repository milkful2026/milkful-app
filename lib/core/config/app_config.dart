/// Backend base URLs. Default to the ports documented in
/// services/local-dev/README.md for zero-config local development;
/// override via --dart-define for staging/prod builds.
class AppConfig {
  static const identityAuthBaseUrl = String.fromEnvironment(
    'IDENTITY_AUTH_BASE_URL',
    defaultValue: 'http://localhost:8001',
  );

  static const userBaseUrl = String.fromEnvironment(
    'USER_BASE_URL',
    defaultValue: 'http://localhost:8002',
  );

  static const inventoryBaseUrl = String.fromEnvironment(
    'INVENTORY_BASE_URL',
    defaultValue: 'http://localhost:8000',
  );

  static const catalogBaseUrl = String.fromEnvironment(
    'CATALOG_BASE_URL',
    defaultValue: 'http://localhost:8003',
  );

  /// Cart Service (MA-96, `services/cart`) — real, DynamoDB-backed.
  static const cartBaseUrl = String.fromEnvironment(
    'CART_BASE_URL',
    defaultValue: 'http://localhost:8004',
  );

  /// Pricing Service (MA-101, `services/pricing-offer`) — a deliberately
  /// scoped-down build of the full merged MA-122 spec (no Offers, no
  /// per-product HSN/GST tax rate, no Redis — see that service's own
  /// README "Scope" section), enough to make `POST /pricing/quote` real
  /// for MA-23's mobile screen, its only caller today.
  static const pricingBaseUrl = String.fromEnvironment(
    'PRICING_BASE_URL',
    defaultValue: 'http://localhost:8005',
  );

  /// Used by [PlacesRepository] for Places Autocomplete/Geocoding HTTP calls
  /// — separate from the native map-tile key in android/local.properties'
  /// MAPS_API_KEY (Android) / ios/Runner/ApiKeys.xcconfig (iOS). No safe
  /// default — pass via --dart-define=GOOGLE_MAPS_API_KEY=... at run/build
  /// time; never hardcode the real key here (this file is committed).
  static const googleMapsApiKey = String.fromEnvironment('GOOGLE_MAPS_API_KEY');

  /// Wallet Service (MA-100, `services/wallet`) — real, Aurora-backed.
  static const walletBaseUrl = String.fromEnvironment(
    'WALLET_BASE_URL',
    defaultValue: 'http://localhost:8006',
  );

  /// Payment Service (MA-99, `services/payment`) — real, Aurora-backed;
  /// scoped to Razorpay wallet-recharge (MA-126).
  static const paymentBaseUrl = String.fromEnvironment(
    'PAYMENT_BASE_URL',
    defaultValue: 'http://localhost:8007',
  );

  /// Razorpay **publishable** key id only — never the key secret or the
  /// webhook secret, which never leave Payment Service. Empty in a build
  /// that hasn't set it; [RazorpayCheckout] guards against that rather
  /// than letting the SDK fail with a confusing error (MA-125 §9).
  static const razorpayKeyId = String.fromEnvironment('RAZORPAY_KEY_ID');

  /// Dark-ships the Wallet tab (MA-24) until Payment/Wallet Service are
  /// deployed somewhere this build can reach — see MA-125 §11.
  static const walletEnabled = bool.fromEnvironment('WALLET_ENABLED');

  /// Subscription Service (MA-131, `services/subscription`) — real,
  /// Aurora-backed. No feature flag (unlike [walletEnabled]) — ships live
  /// once merged, per MA-133 §4 FR-1's own decision (no external gateway
  /// dependency blocking it the way Razorpay credentials blocked Wallet).
  static const subscriptionBaseUrl = String.fromEnvironment(
    'SUBSCRIPTION_BASE_URL',
    defaultValue: 'http://localhost:8008',
  );

  /// Order Service (MA-132, `services/order`) — not called directly by any
  /// screen yet (MA-133 §8); added now since a future order-status
  /// affordance will need it.
  static const orderBaseUrl = String.fromEnvironment(
    'ORDER_BASE_URL',
    defaultValue: 'http://localhost:8009',
  );
}
