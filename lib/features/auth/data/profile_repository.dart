import '../../../core/config/app_config.dart';
import '../../../core/network/api_client.dart';
import '../models/user_profile.dart';

/// Separate from RegistrationRepository even though both call User
/// Service — AuthBloc needs this immediately after both login and
/// registration (MA-21 FR-4), so it belongs alongside auth, not pulled in
/// through the registration wizard feature.
abstract class ProfileRepository {
  Future<UserProfile> getMe();
}

class DioProfileRepository implements ProfileRepository {
  DioProfileRepository(this._client);

  final ApiClient _client;

  @override
  Future<UserProfile> getMe() async {
    final data = await _client.request('GET', '${AppConfig.userBaseUrl}/users/me');
    return UserProfile.fromJson(data);
  }
}
