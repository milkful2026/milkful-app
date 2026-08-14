# MA-113: Rider Route & Delivery Confirmation (Delivery Partner App — MVP)

> **Confirmed:** created in Jira as [MA-113](https://milkfuldairyindia.atlassian.net/browse/MA-113).
> This file is the local record of that story for SDD workflow purposes — the User Story input
> `/spec-driven-designer MA-113` will read from Jira, not from this file, but keeping this in
> sync avoids drift between the two.
>
> **Scope note:** this covers the minimal rider-facing app referenced in the architecture docs
> (`docs/design/milkful-deployment-roadmap-cost.md`, `milkful-hld.drawio`) as "Delivery Partner
> App" but never spec'd in `docs/jira/attachments/nsmb-app-feature-spec.txt`. It is new scope,
> not part of the original 31-feature backlog.

| Field | Value |
|-------|-------|
| **Key** | [MA-113](https://milkfuldairyindia.atlassian.net/browse/MA-113) |
| **Project** | MA (Milkful App) |
| **Issue Type** | Story |
| **Module** | Delivery Partner App |
| **Feature** | Rider Route & Delivery Confirmation |
| **Platform** | Flutter (iOS & Android) — separate app target from the customer app |
| **Priority** | Must-Have (blocks features #17 Order Status and #25 Delivery & Route Management from being functionally complete) |
| **Labels** | `flutter`, `rider`, `delivery-partner`, `logistics` |
| **Components** | Delivery Partner App *(new component — doesn't exist yet, see Notes)* |

---

## User Story

**As a** delivery rider assigned to a daily route,
**I want** to see today's delivery stops in order, mark each one delivered (with proof) or failed (with a reason), and have that update the customer's order status in real time,
**So that** customers get accurate delivery tracking and the business has a reliable record of what was actually delivered.

---

## Functional Requirements

Allow a **staff-provisioned rider account** to log in and view their **assigned stops for the current day**, sourced from the admin's Delivery & Route Management assignment. For each stop, the rider can open **customer, address, and order details**, then either **mark it delivered** (capturing an OTP the customer provides or a photo as proof) or **mark it failed/skipped** (with a reason code). Each action must **update order status in real time** so it's reflected in the customer app's Order Status screen. Given delivery runs happen early morning with unreliable connectivity, actions taken **offline must queue locally and sync** once connectivity returns, without blocking the rider's ability to keep working through their route.

---

## Key Dependencies

| Dependency | Purpose |
|------------|---------|
| Auth server (Cognito) | Staff/rider role — provisioned by admin, not self-registration like the customer app |
| Order service | Status transitions (`Out for Delivery` → `Delivered`/`Failed`), reads order + address per stop |
| Delivery/Logistics service | Source of today's route assignment (built as part of admin feature #25) |
| Notifications | Pushes delivery status change to the customer app in real time |
| Location Service / Maps | Stop ordering, navigation link-out to Google/Apple Maps per stop |
| Local storage (offline queue) | Persists delivery actions taken without connectivity until sync |

---

## Acceptance Criteria

### AC-1: Rider Login

- [ ] Rider logs in with mobile number + OTP, same auth mechanism as the customer app but scoped to a `rider` role.
- [ ] Rider accounts are **provisioned by admin** (via RBAC/admin console, feature #28) — no self-service sign-up.
- [ ] A mobile number with no rider role gets a clear "not authorized" message, not a generic login error.
- [ ] Session persists across app restarts (secure token storage); auto-refresh on app start.

### AC-2: Today's Route View

- [ ] On login, rider sees an ordered list of today's assigned stops (address, customer name, order summary, delivery slot).
- [ ] List reflects the route assignment made in admin's Delivery & Route Management screen — no separate rider-side route creation.
- [ ] Each stop shows status: `Pending`, `Delivered`, `Failed`.
- [ ] Pull-to-refresh re-syncs the route (covers admin reassigning mid-run).
- [ ] Empty state if no stops assigned for the day.

### AC-3: Stop Detail

- [ ] Tapping a stop shows full address, customer contact (call/message shortcut), order items, and any delivery notes.
- [ ] "Navigate" action opens the address in the device's default maps app.
- [ ] Actions available: **Mark Delivered**, **Mark Failed/Skipped**.

### AC-4: Mark Delivered — OTP Proof

- [ ] Rider can enter a delivery OTP provided verbally by the customer.
- [ ] Invalid OTP shows an inline error without losing the rest of the delivery form.
- [ ] On valid OTP, stop status updates to `Delivered` immediately in the local list.

### AC-5: Mark Delivered — Photo Proof (Fallback)

- [ ] If OTP isn't available (customer not present, doorstep drop), rider can capture a photo as proof instead.
- [ ] Photo is compressed client-side before upload to keep sync fast on mobile data.
- [ ] Delivered-via-photo stops are visually distinguishable from OTP-confirmed ones (useful for later dispute resolution).

### AC-6: Mark Failed / Skipped

- [ ] Rider selects a reason code (e.g., customer unavailable, address issue, non-serviceable today, customer refused).
- [ ] Optional free-text note.
- [ ] Failed stops remain visible in the day's list (not removed), clearly flagged.

### AC-7: Real-Time Status Sync

- [ ] Marking a stop delivered/failed calls the Order service to transition status, which the customer sees in Order Status (feature #17) without needing to refresh.
- [ ] Push notification fires to the customer on status change (reuses the Notifications pipeline).

### AC-8: Offline Queue & Sync

- [ ] All delivery actions (deliver/fail) are written to a local queue immediately, independent of network state.
- [ ] Queued actions show a "pending sync" indicator on the stop.
- [ ] Queue auto-flushes when connectivity returns; rider is not blocked from continuing to the next stop while offline.
- [ ] Sync conflicts (e.g., admin reassigned the stop while rider was offline) surface a clear resolution prompt, not a silent overwrite.

### AC-9: End-of-Run Summary

- [ ] Once all stops are actioned, rider sees a summary: delivered count, failed count, total stops.
- [ ] Summary is what feeds the admin's Delivery Performance report (feature #22).

---

## Sub-Task Breakdown

| # | Sub-task | Description |
|---|----------|-------------|
| 1 | **Rider app project setup** | New Flutter app target (or flavor) — decide: standalone app vs. role-based flavor of the existing customer app, see Notes |
| 2 | **Rider login screen** | Mobile + OTP entry, role check against rider table |
| 3 | **Today's route list screen** | Fetch + display ordered stops, pull-to-refresh, status badges |
| 4 | **Stop detail screen** | Address, contact, order summary, navigate-out action |
| 5 | **OTP delivery confirmation widget** | OTP entry, inline validation, submit |
| 6 | **Photo capture flow** | Camera/gallery picker, client-side compression, upload |
| 7 | **Mark failed/skipped flow** | Reason code picker, optional note |
| 8 | **Offline queue (local DB)** | `sqflite`/`hive`-backed action queue, connectivity listener, auto-flush |
| 9 | **Sync conflict handling** | Detect stale local state vs. server, resolution prompt |
| 10 | **Push notification wiring** | Confirm order-status push fires to customer app on rider action |
| 11 | **End-of-run summary screen** | Aggregate today's actioned stops |
| 12 | **Unit & widget tests** | OTP validation, offline queue behavior, reason-code form |
| 13 | **Integration tests** | Full happy path: login → route → deliver (OTP) → deliver (photo) → fail → summary |

---

## Technical Notes

### Open decision: standalone app vs. flavor of the customer app

The architecture docs (`milkful-deployment.drawio`) draw this as a separate client hitting the same API Gateway. Two viable paths:

- **Standalone Flutter app** — separate `pubspec.yaml`, own release cycle, cleanest separation of a staff tool from a consumer app.
- **Role-based flavor/build variant** of the existing customer app codebase — faster to bootstrap since it can reuse `AuthBloc`, `secure_token_storage`, and networking layer once MA-1 builds them, at the cost of shipping delivery-staff code inside a consumer app bundle.

This decision should be made and recorded before specs are drafted — it changes the SDD `Component`/area mapping (see below).

### Recommended Packages

| Area | Package |
|------|---------|
| State management | `flutter_bloc` (match customer app for consistency) |
| HTTP | `dio` |
| Secure storage | `flutter_secure_storage` |
| Offline queue | `sqflite` or `hive` |
| Connectivity | `connectivity_plus` |
| Camera/photo | `image_picker`, `flutter_image_compress` |
| Maps hand-off | `url_launcher` (deep link to native maps) |
| Push notifications | `firebase_messaging` |

### API Endpoints (Expected — align with backend, none of these exist yet)

```
POST /auth/rider/login          { "mobile": "+91XXXXXXXXXX" }
GET  /rider/routes/today
GET  /rider/stops/{stopId}
POST /rider/stops/{stopId}/deliver   { "proofType": "otp"|"photo", "otp"?, "photoUrl"? }
POST /rider/stops/{stopId}/fail      { "reasonCode", "note"? }
POST /rider/sync/queue               [ { action, stopId, payload, clientTimestamp } ]
```

### Screen Flow

```
Login (OTP) → Today's Route List → Stop Detail
    → [Mark Delivered: OTP | Photo] → back to list
    → [Mark Failed: reason code] → back to list
  → End-of-Run Summary
```

---

## Definition of Done

- [ ] All acceptance criteria met on iOS and Android
- [ ] Offline queue verified by physically testing airplane-mode delivery actions and confirming sync on reconnect
- [ ] API integrations tested against staging environment
- [ ] Order status change is confirmed visible on the customer app's Order Status screen within the same test session
- [ ] Code reviewed and merged to `main`
- [ ] QA sign-off on OTP proof, photo proof, and failed-stop flows
- [ ] Product owner demo completed with a real rider walkthrough, not just simulator taps

---

## Out of Scope (Phase 2)

- Route optimization or in-app reassignment (stays admin-side, feature #25)
- Rider earnings/payout tracking
- Multi-day route history or performance dashboard *within the rider app* (aggregate reporting stays admin-side, feature #22)
- In-app chat/support for riders
- Live GPS breadcrumb tracking for the customer-facing "live map" experience (flagged as optional in feature #17 — treat as a later addition, not MVP)

---

## Notes for the SDD Workflow

- **No Component exists yet** for this area in Jira, and no `{area}/README.md` exists in `specs/` (`specs/mobile-app`, `specs/services`, `specs/portal-ui` are the only three areas currently configured). Per `specs/README.md`'s "Configure a new area" step, this needs a new area (e.g., `specs/rider-app/README.md`) plus a matching Jira Component before `/spec-driven-designer` can run against it.
- **Hard dependency on MA-1 and the admin's Delivery & Route Management story (#25)** — this story reads route assignments that #25 has to produce first, and (if built as a flavor of the customer app) reuses MA-1's auth scaffolding. Sequence this after both.
- Story is filed as **MA-113**. Running `/spec-driven-designer MA-113` is the next step once the Component/area setup below is in place — the agent works from the Jira ticket's own description, not this file.

---

## Links

- Story: https://milkfuldairyindia.atlassian.net/browse/MA-113
- Jira Board: https://milkfuldairyindia.atlassian.net/jira/software/projects/MA/boards/1
