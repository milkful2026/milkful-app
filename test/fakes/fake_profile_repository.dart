import 'package:milkful_app/features/auth/data/profile_repository.dart';
import 'package:milkful_app/features/auth/models/user_profile.dart';

class FakeProfileRepository implements ProfileRepository {
  FakeProfileRepository({this.profile, this.getMeException});

  UserProfile? profile;
  Object? getMeException;

  int getMeCallCount = 0;

  @override
  Future<UserProfile> getMe() async {
    getMeCallCount++;
    if (getMeException != null) throw getMeException!;
    return profile ??
        const UserProfile(
          userId: 'user-1',
          name: 'Priya Sharma',
          mobile: '+919876543210',
          accountType: 'B2C',
          defaultAddressId: 'addr-1',
        );
  }
}
