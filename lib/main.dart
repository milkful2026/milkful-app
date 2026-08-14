import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import 'core/network/api_client.dart';
import 'core/router/app_router.dart';
import 'core/storage/draft_storage.dart';
import 'core/storage/secure_token_storage.dart';
import 'core/theme/app_theme.dart';
import 'features/auth/bloc/auth_bloc.dart';
import 'features/auth/data/auth_repository.dart';
import 'features/onboarding/bloc/registration_bloc.dart';
import 'features/onboarding/data/registration_repository.dart';

void main() {
  runApp(const MilkfulApp());
}

class MilkfulApp extends StatelessWidget {
  const MilkfulApp({super.key});

  @override
  Widget build(BuildContext context) {
    final tokenStorage = SecureTokenStorage();
    final draftStorage = DraftStorage();
    // A single shared ApiClient (and therefore Dio instance) for the whole
    // app — its interceptor attaches whatever access token is currently in
    // secure storage to every request, so individual repositories never
    // handle tokens themselves. Before login this just means no
    // Authorization header is added; that's correct, not an error case.
    final apiClient = ApiClient(accessTokenProvider: tokenStorage.readAccessToken);
    final authRepository = DioAuthRepository(apiClient);
    final registrationRepository = DioRegistrationRepository(apiClient);

    return MultiRepositoryProvider(
      providers: [
        RepositoryProvider<SecureTokenStorage>.value(value: tokenStorage),
        RepositoryProvider<DraftStorage>.value(value: draftStorage),
      ],
      child: MultiBlocProvider(
        providers: [
          BlocProvider(
            create: (_) => AuthBloc(authRepository: authRepository, tokenStorage: tokenStorage),
          ),
          BlocProvider(
            create: (_) => RegistrationBloc(
              repository: registrationRepository,
              draftStorage: draftStorage,
            ),
          ),
        ],
        child: MaterialApp.router(
          title: 'Milkful',
          theme: AppTheme.light,
          routerConfig: appRouter,
        ),
      ),
    );
  }
}
