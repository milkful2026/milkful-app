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

  /// Cart Service (MA-96) and Pricing & Offer Service (MA-101) — both
  /// specced and reviewed, but not yet implemented (no `services/cart` or
  /// `services/pricing-offer` directory exists). Ports are provisional
  /// (next free slots after 8000-8003); confirm against
  /// services/local-dev/README.md once those services are scaffolded.
  static const cartBaseUrl = String.fromEnvironment(
    'CART_BASE_URL',
    defaultValue: 'http://localhost:8004',
  );

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
