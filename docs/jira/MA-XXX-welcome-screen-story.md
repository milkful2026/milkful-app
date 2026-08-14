# MA-XXX: Welcome / Splash Screen (Flutter Mobile App)

> **Issue Key:** To be assigned — Atlassian Rovo connector is not yet authorized in this environment, so this issue has not been created in Jira. Authorize the connector (claude.ai connector settings, or `/mcp` in an interactive session), then create the issue in the MA project using the content below.

| Field | Value |
|-------|-------|
| **Project** | MA (Milkful App) |
| **Issue Type** | Story |
| **Module** | Onboarding / Welcome |
| **Feature** | Welcome / Splash Carousel Screen |
| **Platform** | Flutter (iOS & Android) |
| **Priority** | High |
| **Labels** | `flutter`, `mobile`, `onboarding`, `welcome`, `splash` |
| **Components** | Onboarding / Sign-Up |

---

## User Story

**As a** first-time app visitor,
**I want** to see a welcoming splash/carousel screen that communicates Milkful's core value proposition,
**So that** I understand what the app offers before I proceed to sign up.

---

## Design Reference

Welcome screen (slide 1 of an onboarding carousel):

- Full-bleed hero image: glass of fresh milk on a table, warm home/kitchen setting with greenery
- Brand logo mark, top-left, over the hero image
- Headline (two lines): "Purity You" (regular weight) / "Can Trust." (bold, brand green)
- Subtext: "Farm-fresh milk and groceries delivered to your doorstep by 7 AM."
- Two info badges/chips below subtext:
  - ✓ **100% Pure** (green chip)
  - 🕐 **Before 7AM** (peach/pink chip)
- Carousel page indicator: 3 dots — first shown as an active pill, remaining two as inactive dots
- Primary CTA: full-width button, "Get Started →", dark green background, white text

---

## Functional Requirements

Build a **3-slide onboarding carousel** with the Welcome screen as slide 1. Slide content (hero image, headline, subtext, badges) is swappable per slide via a config/model so slides 2 and 3 can be added without UI rework. Bottom pagination dots reflect current slide and are swipe- and tap-driven. "Get Started" CTA is present on every slide and navigates to the sign-up flow ([MA-001](MA-001-user-registration-story.md)) regardless of which slide is active; skip-to-end behavior on swipe is standard carousel UX.

---

## Acceptance Criteria

### AC-1: Hero Layout

- [ ] Full-bleed hero image fills the top ~60% of the screen with a subtle bottom gradient/fade so overlaid text remains legible.
- [ ] Brand logo mark renders top-left over the hero image on a light circular/rounded backing.
- [ ] Image assets are provided at standard mobile resolutions (1x/2x/3x) and lazy/eagerly cached appropriately for a splash screen.

### AC-2: Headline & Subtext

- [ ] Headline renders as two lines: "Purity You" in regular weight, "Can Trust." in bold, brand green (`#0B6B3A`-equivalent token — confirm against design system).
- [ ] Subtext "Farm-fresh milk and groceries delivered to your doorstep by 7 AM." renders below the headline in body/secondary text style.
- [ ] Text scales correctly under device font-size accessibility settings without truncation or overlap (test at largest supported text size).

### AC-3: Info Badges

- [ ] Two chip components render side-by-side below the subtext.
- [ ] First chip: check icon + **"100% Pure"** label, green background/text. *(Copy updated from "100% Organic" → "100% Pure" per latest design.)*
- [ ] Second chip: clock icon + **"Before 7AM"** label, peach/pink background/text.
- [ ] Chip copy and icons are driven by the slide config (not hardcoded), so future slides can reuse the component with different copy.

### AC-4: Carousel & Pagination

- [ ] Screen supports horizontal swipe between 3 slides (`PageView` or equivalent).
- [ ] Pagination dots show 3 indicators; active slide renders as an elongated pill in brand green, inactive slides as small gray dots.
- [ ] Swiping updates the active dot in sync with the visible slide (no lag/flicker).

### AC-5: Primary CTA

- [ ] "Get Started →" button is full-width, fixed near the bottom of the screen, dark green background, white text and trailing arrow icon.
- [ ] Tapping the CTA navigates to the sign-up entry point (mobile number screen from [MA-001](MA-001-user-registration-story.md)).
- [ ] Button remains visible/reachable on all 3 slides and across supported screen sizes (no overlap with pagination dots or system nav bars).
- [ ] Button has a minimum 44x44pt touch target and visible pressed/disabled states.

### AC-6: First-Run Behavior

- [ ] Welcome carousel is shown only on first app launch (or until dismissed via "Get Started"), tracked via local persistence (e.g., `shared_preferences` flag).
- [ ] Returning users who have already completed onboarding skip directly to login/home on subsequent launches.

---

## Flutter Implementation — Sub-Tasks

| # | Sub-task | Description |
|---|----------|--------------|
| 1 | **Onboarding route & scaffold** | `/welcome` route, `PageView` scaffold, slide data model |
| 2 | **Slide content model** | `OnboardingSlide { image, headlineLines, subtext, badges[] }`, seed 3 slides |
| 3 | **Hero image component** | Full-bleed image with gradient overlay, responsive sizing |
| 4 | **Badge/chip component** | Reusable chip widget (icon + label + color variant) |
| 5 | **Pagination dots component** | Animated active/inactive indicator synced to `PageController` |
| 6 | **CTA button & navigation** | Persistent "Get Started" button wired to sign-up route |
| 7 | **First-run persistence** | `shared_preferences` flag to skip onboarding on repeat launches |
| 8 | **Accessibility pass** | Font scaling, screen reader labels for image/badges/CTA |
| 9 | **Widget tests** | Slide swipe, dot sync, CTA navigation, first-run skip logic |

---

## Definition of Done

- [ ] All acceptance criteria met on iOS and Android
- [ ] Copy matches latest design ("100% Pure", not "100% Organic")
- [ ] Accessibility: screen reader labels, font scaling, sufficient contrast on chips/CTA
- [ ] Code reviewed and merged to `main`
- [ ] Product owner/design sign-off against reference image

---

## Links

- Jira Board: https://milkfuldairyindia.atlassian.net/jira/software/projects/MA/boards/1
- Related: [MA-001 — User Registration](MA-001-user-registration-story.md)
