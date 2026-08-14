# MA-001: User Registration (Flutter Mobile App)

| Field | Value |
|-------|-------|
| **Project** | MA (Milkful App) |
| **Issue Type** | Story |
| **Module** | Onboarding / Sign-Up |
| **Feature** | User Registration |
| **Platform** | Flutter (iOS & Android) |
| **Priority** | High |
| **Labels** | `flutter`, `mobile`, `onboarding`, `registration`, `wallet` |
| **Components** | Onboarding / Sign-Up |

---

## User Story

**As a** new Milkful customer,  
**I want** to register using my mobile number (with OTP), optionally via email or social login, and set up my profile, delivery address, and preferences,  
**So that** I can start ordering fresh dairy products with a verified account, serviceable delivery location, and a ready-to-use wallet.

---

## Functional Requirements

Allow new customers to create an account via **mobile number + OTP verification (primary)**, with optional **email/social (Google/Apple) sign-up**. Capture **name**, **delivery address** (with geo-pin/map picker), **pincode serviceability check**, and **preferred delivery time slot**. Support **multiple saved addresses**. Obtain **consent for T&C, privacy policy, and notifications**. **Auto-create a linked Wallet** on successful registration.

---

## Key Dependencies

| Dependency | Purpose |
|------------|---------|
| OTP/SMS API | Send and verify one-time passwords for mobile registration |
| Maps/Geocoding API | Map picker, reverse geocoding, address autocomplete |
| Serviceability (Inventory zones) | Validate pincode/location against delivery zones |
| Wallet service | Auto-provision customer wallet on registration |

---

## Acceptance Criteria

### AC-1: Mobile Number + OTP Registration (Primary Flow)

- [ ] User can enter a 10-digit Indian mobile number with country code (+91) on the sign-up screen.
- [ ] App validates mobile number format before enabling "Send OTP".
- [ ] OTP is sent via OTP/SMS API; user sees countdown timer for resend (e.g., 30s).
- [ ] User can enter 4–6 digit OTP with auto-focus between fields.
- [ ] Invalid/expired OTP shows a clear error; user can retry or request resend (with rate limiting).
- [ ] On successful OTP verification, user proceeds to profile & address setup.
- [ ] Existing registered numbers redirect to login instead of sign-up.

### AC-2: Optional Email & Social Sign-Up

- [ ] User can optionally link email during or after mobile registration.
- [ ] **Google Sign-In** available on Android and iOS (using platform SDKs).
- [ ] **Apple Sign-In** available on iOS (required if other social options exist per App Store guidelines).
- [ ] Social sign-up still requires mobile number verification OR merges with existing account policy (define with product).
- [ ] Social auth tokens are exchanged with backend; session JWT/refresh token stored securely (`flutter_secure_storage`).

### AC-3: Profile Capture — Name

- [ ] User must enter full name (min 2 chars, max 100 chars).
- [ ] Name field supports Unicode characters for regional names.
- [ ] Inline validation with error messages; cannot proceed without valid name.

### AC-4: Delivery Address with Map Picker

- [ ] User can add delivery address via:
  - **Map picker** — drag pin / tap to set geo coordinates
  - **Search/autocomplete** — address search with geocoding
  - **Manual entry** — house/flat, street, landmark, city, state, pincode
- [ ] Selected location displays on map with lat/long sent to backend.
- [ ] Reverse geocoding populates address fields from pin location.
- [ ] Location permission prompt with rationale (Android & iOS).
- [ ] Fallback to manual entry if location permission denied.

### AC-5: Pincode Serviceability Check

- [ ] On pincode entry or map selection, app calls **Serviceability (Inventory zones)** API.
- [ ] If **serviceable**: user continues registration.
- [ ] If **not serviceable**: show friendly message with option to try another pincode or join waitlist (if supported).
- [ ] Loading state shown during serviceability check; errors handled gracefully with retry.

### AC-6: Preferred Delivery Time Slot

- [ ] User selects preferred delivery time slot from API-provided slots (e.g., Morning 6–8 AM, Evening 6–8 PM).
- [ ] Slot list reflects serviceability zone and operational hours.
- [ ] Selection is saved to user profile and can be changed later in settings.

### AC-7: Multiple Saved Addresses

- [ ] User can save the first address during registration (required).
- [ ] Data model supports multiple addresses per user (backend + local cache).
- [ ] User can mark one address as **default/primary**.
- [ ] Address book accessible post-registration (manage add/edit/delete) — scaffold in registration flow for extensibility.

### AC-8: Legal & Notification Consent

- [ ] **Terms & Conditions** checkbox — required; links open in-app WebView or external browser.
- [ ] **Privacy Policy** checkbox — required; links open in-app WebView or external browser.
- [ ] **Push notification** consent — optional or required per product policy; integrates with FCM/APNs permission flow.
- [ ] User cannot complete registration without mandatory consents.
- [ ] Consent timestamps recorded and sent to backend for audit.

### AC-9: Auto-Create Linked Wallet

- [ ] On successful registration completion, backend **Wallet service** auto-creates a wallet linked to the new user ID.
- [ ] App receives wallet ID/balance in registration response or via follow-up API call.
- [ ] Registration success screen confirms wallet is ready (e.g., "Your Milkful Wallet is set up").
- [ ] Failure to create wallet does not silently succeed — show error with retry/support option.

### AC-10: Registration Completion & Session

- [ ] Successful registration returns auth tokens; user lands on home/dashboard.
- [ ] Onboarding progress persisted locally to resume if app killed mid-flow.
- [ ] Analytics events fired: `signup_started`, `otp_sent`, `otp_verified`, `address_added`, `registration_completed`.
- [ ] Deep link support for returning users mid-onboarding (optional phase 2).

---

## Flutter Implementation — Sub-Tasks

### Epic / Story Breakdown for Jira Sub-tasks

| # | Sub-task | Description |
|---|----------|-------------|
| 1 | **Project setup & routing** | Onboarding module, routes (`/signup`, `/otp`, `/profile`, `/address`, `/consent`, `/success`), dependency injection |
| 2 | **Sign-up UI — Mobile entry** | Phone input widget, country code picker, validation, Send OTP CTA |
| 3 | **OTP verification screen** | OTP input (pinput package), timer, resend, error states, API integration |
| 4 | **Social auth — Google** | `google_sign_in` integration, backend token exchange |
| 5 | **Social auth — Apple** | `sign_in_with_apple` integration (iOS), backend token exchange |
| 6 | **Profile form — Name** | Form validation, TextFormField, continue CTA |
| 7 | **Map & address picker** | `google_maps_flutter` / Mapbox, geolocator, geocoding, place autocomplete |
| 8 | **Serviceability API integration** | Pincode/zone check service, loading/error UI |
| 9 | **Delivery slot selector** | Fetch slots from API, radio/chip selection UI |
| 10 | **Address model & multi-address support** | `Address` entity, repository, default address flag |
| 11 | **Consent screens** | T&C, Privacy Policy WebView, notification permission (firebase_messaging) |
| 12 | **Registration API orchestration** | Single registration submit or step-wise APIs, error mapping |
| 13 | **Wallet provisioning hook** | Post-registration wallet fetch/create confirmation UI |
| 14 | **Secure storage & auth state** | `flutter_secure_storage`, auth bloc/provider, auto-login |
| 15 | **Onboarding state persistence** | Save/resume flow with shared_preferences or hive |
| 16 | **Unit & widget tests** | OTP validation, form validators, serviceability mock tests |
| 17 | **Integration / E2E tests** | Full happy path registration flow |

---

## Technical Notes (Flutter)

### Recommended Packages

| Area | Package |
|------|---------|
| State management | `flutter_bloc` or `riverpod` |
| HTTP | `dio` |
| Secure storage | `flutter_secure_storage` |
| Maps | `google_maps_flutter`, `geolocator`, `geocoding` |
| OTP input | `pinput` |
| Google Sign-In | `google_sign_in` |
| Apple Sign-In | `sign_in_with_apple` |
| Phone input | `intl_phone_field` or custom |
| WebView (legal) | `webview_flutter` |
| Push notifications | `firebase_messaging` |

### API Endpoints (Expected — align with backend)

```
POST /auth/otp/send          { "mobile": "+91XXXXXXXXXX" }
POST /auth/otp/verify        { "mobile", "otp", "requestId" }
POST /auth/social            { "provider": "google|apple", "idToken" }
GET  /serviceability/check   ?pincode=XXXXXX&lat=&lng=
GET  /delivery/slots         ?zoneId=
POST /users/register         { name, mobile, email?, addresses[], slot, consents[] }
POST /wallet/create          (or auto via register) 
GET  /wallet/{userId}
```

### Screen Flow

```
Welcome → Sign Up (Mobile) → OTP Verify → [Optional Social Link]
    → Name → Address (Map/Manual) → Serviceability Check
    → Delivery Slot → Consent (T&C, Privacy, Notifications)
    → Submit → Wallet Created → Home
```

---

## Definition of Done

- [ ] All acceptance criteria met on iOS and Android
- [ ] API integrations tested against staging environment
- [ ] Error and empty states implemented for all screens
- [ ] Accessibility: screen reader labels, sufficient contrast
- [ ] Code reviewed and merged to `main`
- [ ] QA sign-off on primary OTP flow and one social flow
- [ ] Product owner demo completed

---

## Out of Scope (Phase 2)

- Referral code during sign-up
- Guest checkout without registration
- Multi-language onboarding (i18n scaffold only in phase 1)

---

## Links

- Jira Board: https://milkfuldairyindia.atlassian.net/jira/software/projects/MA/boards/1
