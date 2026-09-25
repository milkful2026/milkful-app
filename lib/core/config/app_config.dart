import 'package:flutter/foundation.dart' show TargetPlatform, defaultTargetPlatform, kIsWeb;

/// Backend base URLs. Default to the ports documented in
/// services/local-dev/README.md for zero-config local development;
/// override via --dart-define for staging/prod builds (an explicit
/// --dart-define always wins over the platform-aware default below,
/// on every platform).
class AppConfig {
  /// `localhost` inside an Android emulator resolves to the emulator
  /// itself, not the host machine — `10.0.2.2` is the emulator's own
  /// alias for the host. Every *_BASE_URL default below routes through
  /// this so a bare `flutter run -d <android-emulator>` with zero
  /// --dart-define flags reaches a locally running backend correctly,
  /// instead of silently defaulting to an unreachable `localhost` and
  /// failing with a generic "Connection refused" on whichever service's
  /// --dart-define a human/agent happened to forget (this has bitten
  /// cart specifically, twice, before this fallback existed).
  static String get _localBackendHost =>
      (!kIsWeb && defaultTargetPlatform == TargetPlatform.android)
          ? '10.0.2.2'
          : 'localhost';

  static String _localDefault(int port) => 'http://$_localBackendHost:$port';

  static const _identityAuthBaseUrlOverride =
      String.fromEnvironment('IDENTITY_AUTH_BASE_URL');
  static String get identityAuthBaseUrl => _identityAuthBaseUrlOverride.isNotEmpty
      ? _identityAuthBaseUrlOverride
      : _localDefault(8001);

  static const _userBaseUrlOverride = String.fromEnvironment('USER_BASE_URL');
  static String get userBaseUrl =>
      _userBaseUrlOverride.isNotEmpty ? _userBaseUrlOverride : _localDefault(8002);

  static const _inventoryBaseUrlOverride =
      String.fromEnvironment('INVENTORY_BASE_URL');
  static String get inventoryBaseUrl => _inventoryBaseUrlOverride.isNotEmpty
      ? _inventoryBaseUrlOverride
      : _localDefault(8000);

  static const _catalogBaseUrlOverride = String.fromEnvironment('CATALOG_BASE_URL');
  static String get catalogBaseUrl =>
      _catalogBaseUrlOverride.isNotEmpty ? _catalogBaseUrlOverride : _localDefault(8003);

  /// Cart Service (MA-96, `services/cart`) — real, DynamoDB-backed.
  static const _cartBaseUrlOverride = String.fromEnvironment('CART_BASE_URL');
  static String get cartBaseUrl =>
      _cartBaseUrlOverride.isNotEmpty ? _cartBaseUrlOverride : _localDefault(8004);

  /// Pricing Service (MA-101, `services/pricing-offer`) — a deliberately
  /// scoped-down build of the full merged MA-122 spec (no Offers, no
  /// per-product HSN/GST tax rate, no Redis — see that service's own
  /// README "Scope" section), enough to make `POST /pricing/quote` real
  /// for MA-23's mobile screen, its only caller today.
  static const _pricingBaseUrlOverride = String.fromEnvironment('PRICING_BASE_URL');
  static String get pricingBaseUrl =>
      _pricingBaseUrlOverride.isNotEmpty ? _pricingBaseUrlOverride : _localDefault(8005);

  /// Used by [PlacesRepository] for Places Autocomplete/Geocoding HTTP calls
  /// — separate from the native map-tile key in android/local.properties'
  /// MAPS_API_KEY (Android) / ios/Runner/ApiKeys.xcconfig (iOS). No safe
  /// default — pass via --dart-define=GOOGLE_MAPS_API_KEY=... at run/build
  /// time; never hardcode the real key here (this file is committed).
  static const googleMapsApiKey = String.fromEnvironment('GOOGLE_MAPS_API_KEY');

  /// Wallet Service (MA-100, `services/wallet`) — real, Aurora-backed.
  static const _walletBaseUrlOverride = String.fromEnvironment('WALLET_BASE_URL');
  static String get walletBaseUrl =>
      _walletBaseUrlOverride.isNotEmpty ? _walletBaseUrlOverride : _localDefault(8006);

  /// Payment Service (MA-99, `services/payment`) — real, Aurora-backed;
  /// scoped to Razorpay wallet-recharge (MA-126).
  static const _paymentBaseUrlOverride = String.fromEnvironment('PAYMENT_BASE_URL');
  static String get paymentBaseUrl =>
      _paymentBaseUrlOverride.isNotEmpty ? _paymentBaseUrlOverride : _localDefault(8007);

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
  static const _subscriptionBaseUrlOverride =
      String.fromEnvironment('SUBSCRIPTION_BASE_URL');
  static String get subscriptionBaseUrl => _subscriptionBaseUrlOverride.isNotEmpty
      ? _subscriptionBaseUrlOverride
      : _localDefault(8008);

  /// Order Service (MA-132, `services/order`) — not called directly by any
  /// screen yet (MA-133 §8); added now since a future order-status
  /// affordance will need it.
  static const _orderBaseUrlOverride = String.fromEnvironment('ORDER_BASE_URL');
  static String get orderBaseUrl =>
      _orderBaseUrlOverride.isNotEmpty ? _orderBaseUrlOverride : _localDefault(8009);
}
