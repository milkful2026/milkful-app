import 'package:flutter_test/flutter_test.dart';
import 'package:milkful_app/features/auth/models/user_profile.dart';

void main() {
  group('UserProfile.fromJson', () {
    test('parses a profile with a default address', () {
      final profile = UserProfile.fromJson({
        'userId': 'user-1',
        'name': 'Priya Sharma',
        'mobile': '+919876543210',
        'accountType': 'B2C',
        'defaultAddressId': 'addr-1',
      });

      expect(profile.defaultAddressId, 'addr-1');
    });

    test(
      'parses a profile with defaultAddressId: null without throwing '
      '(a user with no saved default address)',
      () {
        final profile = UserProfile.fromJson({
          'userId': 'user-1',
          'name': 'Priya Sharma',
          'mobile': '+919876543210',
          'accountType': 'B2B',
          'defaultAddressId': null,
        });

        expect(profile.defaultAddressId, isNull);
        // The field the rest of the app actually consumes (AuthBloc's
        // accountType resolution) must still come through intact — a
        // TypeError here previously masked a successful profile fetch as
        // accountType: null (see auth_bloc.dart's _resolveAccountType).
        expect(profile.accountType, 'B2B');
      },
    );
  });
}
