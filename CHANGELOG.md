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

[Unreleased]: https://github.com/YoDevStudio/ShauchMap/compare/v1.0.0...HEAD
[1.0.0]: https://github.com/YoDevStudio/ShauchMap/releases/tag/v1.0.0
