import 'package:equatable/equatable.dart';

/// Mirrors user/src/handlers/dto.py's serialize_user_profile output.
class UserProfile extends Equatable {
  const UserProfile({
    required this.userId,
    required this.name,
    required this.mobile,
    required this.accountType,
    required this.defaultAddressId,
  });

  final String userId;
  final String name;
  final String mobile;
  final String accountType; // "B2C" | "B2B"
  final String defaultAddressId;

  factory UserProfile.fromJson(Map<String, dynamic> json) => UserProfile(
        userId: json['userId'] as String,
        name: json['name'] as String,
        mobile: json['mobile'] as String,
        accountType: json['accountType'] as String,
        defaultAddressId: json['defaultAddressId'] as String,
      );

  @override
  List<Object?> get props => [userId, name, mobile, accountType, defaultAddressId];
}
