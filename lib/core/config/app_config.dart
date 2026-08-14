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
}
