import 'package:equatable/equatable.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../auth/data/profile_repository.dart';
import '../../auth/models/user_profile.dart';

sealed class ProfileHeaderState extends Equatable {
  const ProfileHeaderState();

  @override
  List<Object?> get props => [];
}

class ProfileHeaderLoading extends ProfileHeaderState {
  const ProfileHeaderLoading();
}

class ProfileHeaderLoaded extends ProfileHeaderState {
  const ProfileHeaderLoaded(this.profile);

  final UserProfile profile;

  @override
  List<Object?> get props => [profile];
}

class ProfileHeaderError extends ProfileHeaderState {
  const ProfileHeaderError();
}

/// MA-147 FR-4 — only the Profile header depends on `GET /users/me`; the
/// rows below it never wait for, or fail with, this call.
class ProfileHeaderCubit extends Cubit<ProfileHeaderState> {
  ProfileHeaderCubit(this._profiles) : super(const ProfileHeaderLoading());

  final ProfileRepository _profiles;

  Future<void> load() async {
    emit(const ProfileHeaderLoading());
    try {
      final profile = await _profiles.getMe();
      if (!isClosed) emit(ProfileHeaderLoaded(profile));
    } catch (_) {
      if (!isClosed) emit(const ProfileHeaderError());
    }
  }
}
