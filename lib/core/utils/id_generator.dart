import 'dart:math';

final _secureRandom = Random.secure();

/// Random hex string, e.g. for a request ID or an Idempotency-Key. Same
/// approach [ApiClient] already hand-rolls for `X-Request-Id` — shared here
/// rather than pulling in the `uuid` package for a second caller.
String newHexId({int bytes = 16}) {
  final values = List<int>.generate(bytes, (_) => _secureRandom.nextInt(256));
  return values.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
}
