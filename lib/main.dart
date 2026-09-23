import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import 'core/network/api_client.dart';
import 'core/router/app_router.dart';
import 'core/storage/draft_storage.dart';
import 'core/storage/secure_token_storage.dart';
import 'core/theme/app_theme.dart';
import 'features/auth/bloc/auth_bloc.dart';
import 'features/auth/bloc/auth_event.dart';
import 'features/auth/data/auth_repository.dart';
import 'features/auth/data/profile_repository.dart';
import 'features/cart/data/cart_repository.dart';
import 'features/cart/data/pricing_repository.dart';
import 'features/catalog/data/catalog_repository.dart';
import 'features/onboarding/bloc/registration_bloc.dart';
import 'features/onboarding/data/places_repository.dart';
import 'features/onboarding/data/registration_repository.dart';
import 'features/subscriptions/data/subscription_repository.dart';
import 'features/wallet/data/dio_wallet_balance_repository.dart';
import 'features/wallet/data/pending_recharge_store.dart';
import 'features/wallet/data/razorpay_checkout.dart';
import 'features/wallet/data/wallet_balance_repository.dart';
import 'features/wallet/data/wallet_repository.dart';

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
    final profileRepository = DioProfileRepository(apiClient);
    final registrationRepository = DioRegistrationRepository(apiClient);
    final catalogRepository = DioCatalogRepository(apiClient);
    // MA-96 (Cart, DynamoDB-backed) and MA-101 (Pricing, scoped-down —
    // see that service's own README) both now exist as real, runnable
    // services at services/cart and services/pricing-offer.
    final pricingRepository = DioPricingRepository(apiClient);
    final cartRepository = DioCartRepository(apiClient);
    // MA-24/MA-127 (Wallet Service) is now real — see
    // dio_wallet_balance_repository.dart's own doc comment for how this
    // preserves MA-120's whole-rupee `getBalance()` contract on top of it.
    final walletRepository = DioWalletRepository(apiClient);
    final walletBalanceRepository = DioWalletBalanceRepository(walletRepository);
    // MA-25/MA-131 (Subscription Service) is now real — see
    // subscription_repository.dart's own doc comments for the two places
    // its wire contract diverges from a full detail response
    // (create/edit).
    final subscriptionRepository = DioSubscriptionRepository(apiClient);
    final pendingRechargeStore = SharedPreferencesPendingRechargeStore();
    final paymentMethodStore = SharedPreferencesPaymentMethodStore();
    // A fresh SDK instance shared across every Wallet screen visit for the
    // app's lifetime — `WalletBloc.close()` calls `.dispose()` (Razorpay's
    // `clear()`) on it each time the screen is left, and the next visit's
    // bloc simply re-registers its listeners via `.on(...)` on the same
    // instance, matching how `SecureTokenStorage`/`DraftStorage` are
    // shared, long-lived singletons rather than screen-scoped.
    final razorpayCheckout = RealRazorpayCheckout();
    // A separate, plain Dio — Google's Places/Geocoding APIs use their own
    // response envelope, not this app's backend's, so they don't go through
    // ApiClient (which would try to unwrap {requestId,status,data}) or carry
    // this app's own Authorization header.
    final placesRepository = GooglePlacesRepository(Dio());

    final authBloc = AuthBloc(
      authRepository: authRepository,
      tokenStorage: tokenStorage,
      profileRepository: profileRepository,
      // MA-21 FR-3: checks for a stored session once at startup, before
      // the router makes its first routing decision.
    )..add(const SessionBootstrapRequested());

    return MultiRepositoryProvider(
      providers: [
        RepositoryProvider<SecureTokenStorage>.value(value: tokenStorage),
        RepositoryProvider<DraftStorage>.value(value: draftStorage),
        RepositoryProvider<PlacesRepository>.value(value: placesRepository),
        RepositoryProvider<CatalogRepository>.value(value: catalogRepository),
        RepositoryProvider<ProfileRepository>.value(value: profileRepository),
        RepositoryProvider<PricingRepository>.value(value: pricingRepository),
        RepositoryProvider<CartRepository>.value(value: cartRepository),
        RepositoryProvider<RegistrationRepository>.value(value: registrationRepository),
        RepositoryProvider<SubscriptionRepository>.value(value: subscriptionRepository),
        RepositoryProvider<WalletRepository>.value(value: walletRepository),
        RepositoryProvider<WalletBalanceRepository>.value(value: walletBalanceRepository),
        RepositoryProvider<PendingRechargeStore>.value(value: pendingRechargeStore),
        RepositoryProvider<PaymentMethodStore>.value(value: paymentMethodStore),
        RepositoryProvider<RazorpayCheckout>.value(value: razorpayCheckout),
      ],
      child: MultiBlocProvider(
        providers: [
          BlocProvider<AuthBloc>.value(value: authBloc),
          BlocProvider(
            create: (_) => RegistrationBloc(
              repository: registrationRepository,
              draftStorage: draftStorage,
            ),
          ),
        ],
        child: MaterialApp.router(
          title: 'Freshoza',
          theme: AppTheme.light,
          routerConfig: buildAppRouter(authBloc),
        ),
      ),
    );
  }
}
