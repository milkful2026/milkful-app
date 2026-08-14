import 'package:equatable/equatable.dart';

/// Mirrors identity-auth's TokenBundle response shape (accessToken,
/// refreshToken, expiresIn — isNewUser only present on the registration
/// verify response, never on login's).
class TokenBundle extends Equatable {
  const TokenBundle({
    required this.accessToken,
    required this.refreshToken,
    required this.expiresIn,
    this.isNewUser,
  });

  final String accessToken;
  final String refreshToken;
  final int expiresIn;
  final bool? isNewUser;

  DateTime get expiresAt => DateTime.now().add(Duration(seconds: expiresIn));

  factory TokenBundle.fromJson(Map<String, dynamic> json) => TokenBundle(
        accessToken: json['accessToken'] as String,
        refreshToken: json['refreshToken'] as String,
        expiresIn: json['expiresIn'] as int,
        isNewUser: json['isNewUser'] as bool?,
      );

  @override
  List<Object?> get props => [accessToken, refreshToken, expiresIn, isNewUser];
}
