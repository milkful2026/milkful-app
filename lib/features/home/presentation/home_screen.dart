import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../auth/bloc/auth_bloc.dart';
import '../../auth/bloc/auth_event.dart';
import '../../auth/bloc/auth_state.dart';
import '../../catalog/bloc/catalog_bloc.dart';
import '../../catalog/bloc/catalog_event.dart';
import '../../catalog/presentation/catalog_screen.dart';
import '../../onboarding/bloc/registration_bloc.dart';
import '../../onboarding/bloc/registration_event.dart';
import '../../onboarding/bloc/registration_state.dart';

/// MA-1's spec explicitly puts a real Home (catalog, cart, subscriptions)
/// out of scope; MA-21 adds the role-aware indicator (FR-4) and a logout
/// entry point (FR-5) on top of the placeholder MA-1 left here; MA-115
/// added the real catalog.
///
/// This screen has since absorbed what used to be three separate
/// onboarding steps:
/// - **Name**: no longer collected from the user at all — the old dedicated
///   screen, and later the inline Home-screen prompt that replaced it, are
///   both gone. Registration now submits automatically as soon as
///   serviceability is confirmed (see registration_bloc.dart's
///   `_submitRegistration`), with a placeholder name the UI never shows.
/// - **Consent**: no longer a gated step at all — Terms & Privacy
///   acceptance is implicit (Welcome screen's own "by continuing you
///   agree..." footer), so registration always submits with both marked
///   accepted.
/// - **Delivery slot**: [_DeliverySlotPicker] below replaces the old
///   dedicated slot-selection screen with a calendar-style strip, usable
///   any time (not just mid-registration) — see its own doc comment for
///   the real gap this has relative to the reference mockup (no backend
///   endpoint exists yet to persist a slot preference outside of
///   registration's own optional, one-time `preferredSlotId`).
class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  final _searchController = TextEditingController();
  Timer? _searchDebounce;

  @override
  void dispose() {
    _searchDebounce?.cancel();
    _searchController.dispose();
    super.dispose();
  }

  // FR-5: debounced 300ms, matching the address search field's own pattern.
  void _onSearchChanged(String query) {
    _searchDebounce?.cancel();
    _searchDebounce = Timer(const Duration(milliseconds: 300), () {
      context.read<CatalogBloc>().add(SearchQueryChanged(query));
    });
  }

  void _onSearchCleared() {
    _searchDebounce?.cancel();
    _searchController.clear();
    context.read<CatalogBloc>().add(const SearchCleared());
  }

  Future<void> _confirmLogout(BuildContext context) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Log out?'),
        content: const Text("You'll need to verify your number again to sign back in."),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Log out'),
          ),
        ],
      ),
    );
    if (confirmed == true && context.mounted) {
      context.read<AuthBloc>().add(const LogoutRequested());
    }
  }

  @override
  Widget build(BuildContext context) {
    return BlocProvider(
      // CatalogRepository itself is provided app-wide from main.dart
      // (alongside PlacesRepository) — only the bloc is scoped here, since
      // its loading/search/filter state shouldn't outlive this screen the
      // way the repository/HTTP client should. Scoped around the whole
      // Scaffold (not just the body) so the header's own search field —
      // now living here, not inside CatalogScreen — can reach it too.
      create: (context) => CatalogBloc(repository: context.read()),
      child: BlocListener<RegistrationBloc, RegistrationState>(
        listenWhen: (previous, current) => previous.phase != current.phase,
        listener: (context, state) {
          if (state.phase == RegistrationPhase.submitFailed) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text(state.errorMessage ?? 'Something went wrong. Please try again.'),
                action: SnackBarAction(
                  label: 'Retry',
                  onPressed: () =>
                      context.read<RegistrationBloc>().add(const RegistrationRetryRequested()),
                ),
              ),
            );
            return;
          }
          if (state.phase != RegistrationPhase.success) return;
          // AuthBloc's own profile lookup was skipped at OTP-verify time
          // (the profile didn't exist yet) — refresh it now so the rest of
          // Home picks up the real accountType.
          context.read<AuthBloc>().add(const ProfileRefreshRequested());
          final zoneId = state.draft.zoneId;
          if (zoneId != null) {
            context.read<RegistrationBloc>().add(DeliverySlotsRequested(zoneId));
          }
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(_walletMessage(state.result?.walletStatus))),
          );
        },
        child: Scaffold(
          appBar: AppBar(
            automaticallyImplyLeading: false,
            titleSpacing: 8,
            title: Row(
              children: [
                IconButton(
                  key: const Key('profile-action'),
                  icon: const Icon(Icons.account_circle_outlined),
                  tooltip: 'Profile',
                  // No Profile screen exists yet — present per the
                  // reference mockup, not yet wired, same as the bottom
                  // nav's own non-Home items below.
                  onPressed: null,
                ),
                Expanded(
                  child: Semantics(
                    label: 'Search products',
                    child: TextField(
                      key: const Key('home-search-field'),
                      controller: _searchController,
                      onChanged: _onSearchChanged,
                      decoration: InputDecoration(
                        isDense: true,
                        hintText: 'Search for "Milk"',
                        prefixIcon: const Icon(Icons.search, size: 20),
                        suffixIcon: _searchController.text.isEmpty
                            ? null
                            : IconButton(
                                icon: const Icon(Icons.close, size: 18),
                                onPressed: () => setState(_onSearchCleared),
                              ),
                        filled: true,
                        fillColor: Colors.white,
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(24),
                          borderSide: BorderSide.none,
                        ),
                      ),
                      onSubmitted: (_) {},
                    ),
                  ),
                ),
                IconButton(
                  key: const Key('wallet-action'),
                  icon: const Icon(Icons.account_balance_wallet_outlined),
                  tooltip: 'Wallet',
                  // Registration does provision a real wallet
                  // (walletId/walletStatus) but no endpoint exists yet to
                  // read its balance or top it up ("Recharge") — present,
                  // not yet wired, same as Profile above.
                  onPressed: null,
                ),
                IconButton(
                  key: const Key('logout-action'),
                  icon: const Icon(Icons.logout),
                  tooltip: 'Log out',
                  onPressed: () => _confirmLogout(context),
                ),
              ],
            ),
          ),
          bottomNavigationBar: const _HomeBottomNav(),
          body: Column(
            children: [
              BlocBuilder<AuthBloc, AuthState>(
                builder: (context, state) {
                  final accountType = state is AuthAuthenticated ? state.accountType : null;
                  if (accountType != 'B2B') return const SizedBox.shrink();
                  return const Padding(
                    padding: EdgeInsets.only(top: 8),
                    child: Chip(label: Text('B2B account')),
                  );
                },
              ),
              const _GreetingBar(),
              const _DeliverySlotPicker(),
              const Expanded(child: CatalogScreen()),
            ],
          ),
        ),
      ),
    );
  }

  String _walletMessage(String? walletStatus) => switch (walletStatus) {
        'PENDING' => 'Welcome to Freshoza! Your wallet is being set up.',
        'FAILED' => 'Welcome to Freshoza! Wallet setup incomplete — contact support if this persists.',
        _ => 'Welcome to Freshoza! Your wallet is ready.',
      };
}

/// A plain, non-personalized greeting — no name is collected from the user
/// anywhere in the app anymore, so this never varies per-user.
class _GreetingBar extends StatelessWidget {
  const _GreetingBar();

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
      child: Text(
        'Welcome!',
        style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold),
      ),
    );
  }
}

/// Calendar-style delivery-slot picker, replacing the old dedicated Slot
/// screen. The date strip itself is presentational (this app has no
/// subscription/recurring-order concept to attach real per-day state to —
/// unlike the reference mockup, which is from a subscription-delivery
/// app); the slot chips below it are real, backed by the same
/// `GET /delivery/slots` data the old wizard step used.
///
/// Known gap: there's no backend endpoint to persist a slot preference
/// outside of registration's own one-time, optional `preferredSlotId`, so
/// picking a chip here is local-only for now (flagged, not hidden) —
/// selecting a different date/slot after registration has nothing to save
/// it to yet.
class _DeliverySlotPicker extends StatefulWidget {
  const _DeliverySlotPicker();

  @override
  State<_DeliverySlotPicker> createState() => _DeliverySlotPickerState();
}

class _DeliverySlotPickerState extends State<_DeliverySlotPicker> {
  int _selectedDayOffset = 0;
  String? _selectedSlotId;

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<RegistrationBloc, RegistrationState>(
      builder: (context, state) {
        if (state.draft.zoneId == null && state.availableSlots.isEmpty) {
          return const SizedBox.shrink();
        }
        final theme = Theme.of(context);
        final today = DateTime.now();
        return Padding(
          padding: const EdgeInsets.symmetric(vertical: 8),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Text('Delivery schedule', style: theme.textTheme.labelLarge),
              ),
              const SizedBox(height: 8),
              SizedBox(
                key: const Key('delivery-date-strip'),
                height: 64,
                child: ListView.builder(
                  scrollDirection: Axis.horizontal,
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  itemCount: 7,
                  itemBuilder: (context, index) {
                    final date = today.add(Duration(days: index));
                    final selected = index == _selectedDayOffset;
                    return Padding(
                      key: Key('delivery-date-$index'),
                      padding: const EdgeInsets.symmetric(horizontal: 4),
                      child: InkWell(
                        borderRadius: BorderRadius.circular(12),
                        onTap: () => setState(() => _selectedDayOffset = index),
                        child: Container(
                          width: 48,
                          decoration: BoxDecoration(
                            color: selected ? theme.colorScheme.primary : Colors.white,
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(
                              color: selected ? theme.colorScheme.primary : Colors.grey.shade300,
                            ),
                          ),
                          alignment: Alignment.center,
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Text(
                                _weekdayShort(date.weekday),
                                style: TextStyle(
                                  fontSize: 11,
                                  color: selected ? Colors.white : Colors.grey.shade600,
                                ),
                              ),
                              Text(
                                '${date.day}',
                                style: TextStyle(
                                  fontWeight: FontWeight.bold,
                                  color: selected ? Colors.white : Colors.black87,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    );
                  },
                ),
              ),
              if (state.availableSlots.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
                  child: Wrap(
                    spacing: 8,
                    children: [
                      for (final slot in state.availableSlots.where((s) => s.available))
                        ChoiceChip(
                          key: Key('delivery-slot-${slot.id}'),
                          label: Text(slot.label),
                          selected: _selectedSlotId == slot.id,
                          onSelected: (_) => setState(() => _selectedSlotId = slot.id),
                        ),
                    ],
                  ),
                ),
            ],
          ),
        );
      },
    );
  }

  String _weekdayShort(int weekday) => const [
        'Mon',
        'Tue',
        'Wed',
        'Thu',
        'Fri',
        'Sat',
        'Sun',
      ][weekday - 1];
}

/// Matches the reference mockup's bottom nav bar. Only Home is real —
/// Products/Refer/Favourites have no screens or specs behind them yet, so
/// they're visually present but disabled (`onTap: null`), same "present
/// per mockup, not yet wired" treatment used elsewhere on this screen.
class _HomeBottomNav extends StatelessWidget {
  const _HomeBottomNav();

  @override
  Widget build(BuildContext context) {
    final primary = Theme.of(context).colorScheme.primary;
    return BottomNavigationBar(
      currentIndex: 0,
      onTap: null,
      selectedItemColor: primary,
      unselectedItemColor: Colors.grey.shade400,
      items: const [
        BottomNavigationBarItem(icon: Icon(Icons.home), label: 'Home'),
        BottomNavigationBarItem(icon: Icon(Icons.grid_view_outlined), label: 'Products'),
        BottomNavigationBarItem(icon: Icon(Icons.card_giftcard_outlined), label: 'Refer'),
        BottomNavigationBarItem(icon: Icon(Icons.favorite_border), label: 'Favourites'),
      ],
    );
  }
}
