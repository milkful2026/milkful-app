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
}
