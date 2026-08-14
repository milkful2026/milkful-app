# milkful-app

Flutter mobile app for [MA-1](https://milkfuldairyindia.atlassian.net/browse/MA-1) (registration)
and [MA-21](https://milkfuldairyindia.atlassian.net/browse/MA-21) (login). This PR implements
**MA-1's primary mobile+OTP registration flow only** — see [Scope](#scope) below. MA-21 (login,
session persistence, role-aware home, logout) is an immediate follow-up PR, since its own spec
depends on the `AuthBloc` foundation this one builds.

Spec: `specs/mobile-app/tasks/MA/MA-1/flutter-registration-onboarding.md` in `milkful2026/specs`.
Backend this app talks to: `milkful2026/services` — see that repo's `services/local-dev/README.md`
for how to run it locally.

## Prerequisites

- Flutter 3.47+ (`flutter doctor` should show Flutter itself as OK; Android's `cmdline-tools`
  component is a separate, known gap — see [Known gaps](#known-gaps))
- The backend running locally — follow `services/local-dev/README.md` in the `services` repo
  (`docker compose up -d`, `bootstrap.py`, `apply_migrations.py`, `seed_inventory_zones.py`,
  `seed_user_zone_slots.py`, then `run_local.py` for identity-auth and user)

## Running

```bash
flutter pub get
flutter run -d chrome     # or -d windows — Android needs the cmdline-tools gap closed first
```

Defaults to `http://localhost:8001` (identity-auth), `:8002` (user), `:8000` (inventory) —
matching `services/local-dev/README.md`'s documented ports exactly, so no flags are needed against
a locally running backend. Override for a different backend via `--dart-define`:

```bash
flutter run -d chrome \
  --dart-define=IDENTITY_AUTH_BASE_URL=https://... \
  --dart-define=USER_BASE_URL=https://... \
  --dart-define=INVENTORY_BASE_URL=https://...
```

## Testing

```bash
flutter analyze
flutter test
```

Fully offline — every bloc/widget test runs against hand-written fakes (`test/fakes/`) that match
each repository's real interface exactly, the same "fix the fake, not the assertion" discipline
used throughout the backend this app talks to. No real backend, no network.

**Live sanity check** (optional, needs the real backend running — see Prerequisites):

```bash
dart run tool/live_check.dart +919876500001   # any fresh mobile number
```

Exercises the real `DioAuthRepository` (not a fake) against a real running identity-auth backend:
send OTP → read it back via `services/local-dev/peek_otp.py` (no SMS provider exists locally) →
verify → confirm a real access token comes back. This is how the send/verify OTP flow was actually
verified working end-to-end while building this PR — there's no browser-automation tooling
available to click through the UI directly, so this drives the same repository code the UI calls,
directly, against the real wire contract.

## Architecture

Feature-first, mirroring the backend's own hexagonal discipline (port interface + real adapter +
fake-for-tests) rather than introducing a new pattern:

```
lib/
├── core/
│   ├── config/app_config.dart       # backend base URLs (--dart-define overridable)
│   ├── network/api_client.dart      # shared Dio wrapper: JWT + X-Request-Id interceptor,
│   │                                # envelope unwrapping, ApiException error mapping
│   ├── storage/                     # secure_token_storage.dart (tokens), draft_storage.dart
│   │                                # (onboarding-in-progress state, shared_preferences)
│   ├── router/app_router.dart       # go_router
│   └── theme/app_theme.dart
└── features/
    ├── auth/                        # AuthBloc + AuthRepository — MA-1's OTP send/verify only;
    │                                # MA-21 extends this exact interface, not a new one
    └── onboarding/                  # RegistrationBloc + RegistrationRepository + the 8 screens
```

State: `flutter_bloc`. HTTP: `dio`. Tokens: `flutter_secure_storage`. Onboarding draft resume:
`shared_preferences`. All named explicitly in the spec's technical design, not new choices.

## Scope

**Built:** Welcome (placeholder) → Sign up (mobile+OTP) → OTP verify → Name → Address (manual
entry) → Serviceability result → Delivery slot → Consent → Submit → Success → Home (placeholder).

**Deliberately deferred — each needs a real credential/asset this pass doesn't have, not just
time:**

1. **Google Maps map picker + Places autocomplete** (spec FR-5) — needs a real Google Maps API
   key. Address screen is manual-entry only (one of the spec's three explicitly valid methods).
   As a consequence, this screen also asks for latitude/longitude directly as plain number fields
   — a deliberate deviation from the spec's literal manual-entry field list, since both the
   serviceability check and registration require real lat/lng and there's no geocoding available
   to derive them from an address.
2. **Google/Apple social sign-in** (FR-3) — needs real OAuth app registrations.
3. **The full branded 3-slide welcome carousel** (`docs/jira/MA-XXX-welcome-screen-story.md`) —
   needs real hero images/icons and a confirmed design-system color token (that story doc itself
   says "confirm against design system"); it's also not yet a created Jira issue. This PR ships a
   minimal single-screen entry point instead.
4. **Legal doc WebView** (FR-8) — simplified to plain-text consent copy; no real legal-doc URLs
   exist to link to yet either.
5. **Analytics events** (AC-10) — not detailed enough in the spec to implement meaningfully.

## Known gaps

- **Android `cmdline-tools` are missing** on the machine this was built on (`flutter doctor`
  flags it) — `flutter build apk` / running on a real Android emulator or device wasn't possible
  this session. Everything was verified via `flutter analyze`, `flutter test`, and the live-check
  script against `-d chrome`/`-d windows` targets instead. A real Android run is a genuine gap,
  not silently worked around.
- **`GET /delivery/slots` needs User Service's own `zone_slots` table seeded** (see
  `services/local-dev/seed_user_zone_slots.py`, added alongside this PR) — that table isn't
  synced from Inventory's real zone config in any environment (flagged in `user/README.md`'s own
  decision #1), so local testing of the slot screen depends on that seed script having run.
  Neither seed script was exercised against a live Postgres container in this sandbox — same
  Docker-availability limitation documented in `services/local-dev/README.md`.
- **No Home screen content** — MA-1's own spec puts a real Home (catalog, cart, subscriptions)
  out of scope; this PR's `HomeScreen` is a bare placeholder that MA-21 (role indicator, logout)
  and later stories build on.
