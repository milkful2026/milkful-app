import 'package:equatable/equatable.dart';

import 'delivery_address.dart';

/// Mirrors user/src/handlers/dto.py's serialize_user_profile output.
class UserProfile extends Equatable {
  const UserProfile({
    required this.userId,
    required this.name,
    required this.mobile,
    required this.accountType,
    required this.defaultAddressId,
    this.defaultAddressState,
    this.defaultAddressZoneId,
    this.defaultAddress,
  });

  final String userId;
  final String name;
  final String mobile;
  final String accountType; // "B2C" | "B2B"
  final String? defaultAddressId;

  /// MA-23 impl plan §2.1/§4A — null when no default address is set, or
  /// when this app instance predates the field's addition on the backend.
  final String? defaultAddressState;

  /// MA-25 Step 6 backend companion — null when no default address is set,
  /// the address predates this field, or this app instance predates it.
  /// Used by ProductConfigBloc to resolve delivery slots for the
  /// subscription slot picker, in place of RegistrationBloc's ephemeral
  /// draft (see product_config_bloc.dart's own comment on why).
  final String? defaultAddressZoneId;

  /// MA-135 FR-6 — the full default address (null when none is set, or
  /// from a User Service that predates the field). The Review Cart
  /// screen's delivery card reads this (MA-137 FR-6).
  final DeliveryAddress? defaultAddress;

  factory UserProfile.fromJson(Map<String, dynamic> json) => UserProfile(
    userId: json['userId'] as String,
    name: json['name'] as String,
    mobile: json['mobile'] as String,
    accountType: json['accountType'] as String,
    defaultAddressId: json['defaultAddressId'] as String?,
    defaultAddressState: json['defaultAddressState'] as String?,
    defaultAddressZoneId: json['defaultAddressZoneId'] as String?,
    defaultAddress: json['defaultAddress'] is Map<String, dynamic>
        ? DeliveryAddress.fromJson(json['defaultAddress'] as Map<String, dynamic>)
        : null,
  );

  @override
  List<Object?> get props => [
    userId,
    name,
    mobile,
    accountType,
    defaultAddressId,
    defaultAddressState,
    defaultAddressZoneId,
    defaultAddress,
  ];
}
