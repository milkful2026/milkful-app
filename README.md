# milkful-app

Flutter mobile app for [MA-1](https://milkfuldairyindia.atlassian.net/browse/MA-1) (registration)
and [MA-21](https://milkfuldairyindia.atlassian.net/browse/MA-21) (login) — both now implemented.

Specs: `specs/mobile-app/tasks/MA/MA-1/flutter-registration-onboarding.md` and
`specs/mobile-app/tasks/MA/MA-21/flutter-login-flow.md` in `milkful2026/specs`.
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
dart run tool/live_check.dart +919876500001          # MA-1: register → verify
dart run tool/live_check_login.dart +919876500002    # MA-21: register → login → logout
```

Both drive the real `DioAuthRepository` (not a fake) against a real running identity-auth
backend — no browser-automation tooling is available to click through the UI directly, so these
exercise the same repository code the UI calls, directly, against the real wire contract. This is
how a real, previously-undetected bug was actually found while building MA-21: logging in
immediately after registering failed with `USER_NOT_FOUND` due to a `moto[server]==5.0.21` bug in
`list_users` filtering (fixed by upgrading to `5.2.2` — see `services/local-dev/README.md`'s Known
Gaps). Neither test-suite-level fakes nor the earlier MA-1 live check could have caught this — it
only showed up once two real backend calls (register, then login) ran back-to-back against the
same real Cognito-emulating backend.

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
│   ├── router/app_router.dart       # go_router — redirect guard is narrow, see its own
│   │                                # docstring for why it doesn't gate every route
│   └── theme/app_theme.dart
└── features/
    ├── auth/                        # AuthBloc + AuthRepository + ProfileRepository — OTP
    │                                # send/verify (both flows), session bootstrap, logout;
    │                                # login_screen.dart, login_otp_screen.dart
    ├── onboarding/                  # RegistrationBloc + RegistrationRepository + MA-1's 8
    │                                # wizard screens
    └── home/                        # role-aware placeholder Home + logout entry point
```

State: `flutter_bloc`. HTTP: `dio`. Tokens: `flutter_secure_storage`. Onboarding draft resume:
`shared_preferences`. All named explicitly in both specs' technical design, not new choices.

**One `AuthBloc`, not two.** MA-21's spec explicitly extends MA-1's `AuthBloc` rather than
introducing a separate one, and registration's and login's OTP send/verify share identical
states (`AuthOtpSending`/`AuthOtpSent`/`AuthOtpVerifying`/`AuthOtpVerifyFailure`) since they're
structurally identical flows. The one place this needs care: both flows can produce the same
`AuthOtpSent` state, so `SignupScreen`'s "Log in" link tracks a local flag to route the resulting
navigation to `/login/otp` instead of `/otp` — see that screen's own comments for the full
reasoning (a `BlocBuilder` narrowed to a single state type loses track of which flow is active
the moment the bloc moves on to a shared transient state like `AuthOtpSending`).

## Scope

**Built (MA-1):** Welcome (placeholder) → Sign up (mobile+OTP) → OTP verify → Name → Address
(manual entry) → Serviceability result → Delivery slot → Consent → Submit → Success → Home.

**Built (MA-21):** Standalone `/login` (mobile entry) → OTP verify → Home; MA-1's "Already
registered? Log in" link → OTP verify directly (mobile already known) → Home; session bootstrap
on app start (silent refresh if the access token is expired, `GET /users/me` to resolve role);
role-aware Home (B2B indicator only, no B2B-specific screens — spec's own explicit limit);
logout with confirmation, best-effort server-side revoke, always-succeeds local clear.

**Deliberately deferred (MA-1 only) — each needs a real credential/asset this pass doesn't have,
not just time:**

1. **Google Maps map picker + Places autocomplete** (spec FR-5) — needs a real Google Maps API
   key. Address screen is manual-entry only (one of the spec's three explicitly valid methods).
   As a consequence, this screen also asks for latitude/longitude directly as plain number fields
   — a deliberate deviation from the spec's literal manual-entry field list, since both the
   serviceability check and registration require real lat/lng and there's no geocoding available
   to derive them from an address.
2. **Google/Apple social sign-in** (FR-3) — needs real OAuth app registrations.
3. **The full branded 3-slide welcome carousel** (`docs/jira/MA-XXX-welcome-screen-story.md`) —
   needs real hero images/icons and a confirmed design-system color token (that story doc itself
   says "confirm against design system"); it's also not yet a created Jira issue. This app ships
   a minimal single-screen entry point instead.
4. **Legal doc WebView** (FR-8) — simplified to plain-text consent copy; no real legal-doc URLs
   exist to link to yet either.
5. **Analytics events** (AC-10) — not detailed enough in the spec to implement meaningfully.

**Deliberately simplified (MA-21):** the spec's routing note about redirecting to `/login` vs
`/signup` based on "a last known mobile number hint... otherwise a first-time device" needs a
persisted "has this device ever had a session" flag that nothing in either spec actually defines.
Since MA-1's `/` (Welcome) already correctly serves both first-time and returning users (returning
users reach `/login` via the existing "Log in" link during signup), this app uses one simpler
rule instead: authenticated → always land on `/home`; unauthenticated → always land on `/`
(Welcome). See `app_router.dart`'s own docstring for the full reasoning, including why the
redirect guard deliberately does *not* govern every route (a blanket rule would incorrectly yank
a mid-registration user off their current wizard step, since `AuthAuthenticated` is also the
bloc's state throughout the whole post-verify registration journey, not just after login).

## Known gaps

- **Android `cmdline-tools` are missing** on the machine this was built on (`flutter doctor`
  flags it) — `flutter build apk` / running on a real Android emulator or device wasn't possible
  this session. Everything was verified via `flutter analyze`, `flutter test`, and the live-check
  scripts against `-d chrome`/`-d windows` targets instead. A real Android run is a genuine gap,
  not silently worked around.
- **`GET /delivery/slots` needs User Service's own `zone_slots` table seeded** (see
  `services/local-dev/seed_user_zone_slots.py`) — that table isn't synced from Inventory's real
  zone config in any environment (flagged in `user/README.md`'s own decision #1), so local testing
  of the slot screen depends on that seed script having run. Neither seed script was exercised
  against a live Postgres container in this sandbox — same Docker-availability limitation
  documented in `services/local-dev/README.md`.
- **Logout placement is provisional** (an `AppBar` icon action) — the spec itself says the exact
  location is flexible pending a future Account/Settings screen; the underlying logout mechanism
  is fixed regardless of where the button eventually lives.
- **No B2B-specific Home content** — MA-21's own spec limits this to reading and displaying the
  role flag, not gating any actual functionality differently. A real B2B experience is a separate,
  future story.
