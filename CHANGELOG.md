# Changelog

All notable changes to ShauchMap are documented here.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Planned
- Photo contributions on toilets
- Hindi & regional localization
- Dedicated area/landmark search screen
- "People helped" impact metric on the profile
- iOS build
- Re-enable in-app Add Toilet once a minimum-supported-version mechanism exists

## [1.0.3] — 2026-09

A rebuild of how ShauchMap decides what to show you, plus a second, independent surface.

### Added
- **Truth / Evidence / GO** — toilet status is now evidence-graded rather than a binary open/closed flag. Where the evidence is thin or contradictory, ShauchMap says **Unknown** instead of guessing, and GO's recommendation always comes with a stated reason.
- **Shared decision core** (`packages/shauchmap_core`) — the Truth/Evidence/GO logic is now a single, independently-tested Dart package consumed by both clients, instead of being duplicated inside the Android app.
- **ShauchMap Instant** — a read-only, install-free web companion at [shauchmap.web.app](https://shauchmap.web.app). No account, no writes, no analytics; built for a QR-code, "I need one right now" use case.
- **OpenStreetMap attribution** — both the Android map screen and Instant now visibly credit OpenStreetMap contributors for the seeded toilet-location data, with a link to the OSM copyright page.
- **Google Maps SDK key** is no longer a literal in `AndroidManifest.xml` — it's resolved at build time from a local, git-ignored config value, with a fail-closed release build if none is supplied.

### Changed
- Location-quality handling was hardened based on real-device testing: a browser location fix with unusably large uncertainty is no longer treated as good, and a timed-out location request now recovers into the same acquisition window instead of surfacing an avoidable "took too long" error.
- `PRIVACY.md` and `SECURITY.md` now cover both surfaces and describe the actual security model (client-visible restricted keys secured by platform/certificate restrictions, not by secrecy of the string) rather than an inaccurate blanket "never hardcoded" claim.

### Known limitations
- Most of the ~7,741 seeded toilet locations still have no community evidence attached yet — this is expected and disclosed, not a bug.
- Add-Toilet remains paused in this release, pending a minimum-supported-version enforcement mechanism (see `lib/config/rollout_config.dart`).
- iOS is unbuilt.

## [1.0.0] — 2026-07-04

The first public release. 🎉

### Added
- **GO** — a single button, reachable from any tab, that finds the nearest usable toilet, previews it on a mini-map with walk time, and hands off to Google Maps.
- **Map-first home** — full-bleed map with live clustering over 7,741 OpenStreetMap-seeded toilets, floating search, quick filters, and a "nearest open toilet" peek card.
- **Filters** — Open now, Free, Has water, Western, Women-safe.
- **Trust signals** — community check-ins, star ratings, freshness ("checked Xh ago"), Bayesian/Wilson scoring, and spam hiding.
- **Colour-blind-safe status** — open/closed shown as dot + word + icon, never colour alone.
- **Scout system** — XP for adding (+50), quick-checking (+15), and rating (+10); ranks from Loo Scout to Swachh Legend; weekly leaderboard; Warden verification.
- **Add a toilet** — a premium, one-minute contribution flow (long-press GO or the You tab).
- **Home-screen widget** — nearest open toilet, refreshed in the background.
- **Deep links** — `shauchmap://emergency` and `shauchmap://navigate`.
- **Offline support** — Firestore caching and graceful empty/offline states.
- Google Sign-In, Crashlytics, custom haptics, and a full design-token system with light (default) and dark themes.

[Unreleased]: https://github.com/YoDevStudio/ShauchMap/compare/v1.0.3...HEAD
[1.0.3]: https://github.com/YoDevStudio/ShauchMap/compare/v1.0.0...v1.0.3
[1.0.0]: https://github.com/YoDevStudio/ShauchMap/releases/tag/v1.0.0
