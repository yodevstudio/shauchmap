# Architecture

## Overview

ShauchMap ships two client surfaces over one shared decision core:

```
                 packages/shauchmap_core
                 (Truth / Evidence / GO logic,
                  pure Dart, independently tested)
                        /            \
                       /              \
              lib/ (Android)          instant/ (web)
              Flutter + Firebase      Preact + TypeScript + Vite
              scoped contributions    read-only, no account
```

Both clients read from the same Cloud Firestore project. Android additionally writes — but only to tightly scoped, individually-owned nested contributions (a rating, a check-in, a condition check, a report), each structurally tied to the authoring account. Creating, updating, or deleting a top-level toilet record is denied to every client, old or new, by the current public Firestore rules — this is a server-enforced boundary, not a client-side courtesy. Neither client re-implements the decision logic locally — see [Truth / Evidence / GO](truth-evidence-go.md) for what that logic actually does.

## Shared core (`packages/shauchmap_core`)

A pure-Dart package (`lib/shauchmap_core.dart` as the public entrypoint, `lib/src/` for the implementation, `lib/interop/` for the JS-interop boundary used by Instant, `test/` for its own test suite, `oracle/` for a native-Dart-vs-compiled-JS conformance check). It owns:

- Parsing a raw Firestore toilet document into a Truth record.
- Evaluating Evidence freshness, strength, and contradiction.
- The GO selection algorithm and its reason strings.

Instant consumes this package by compiling it to JavaScript and calling it through a small, versioned interop contract (a handful of pure functions — no shared mutable state, no direct Firestore access baked into the compiled core itself). This means a change to how GO decides something is written and tested once, and both clients get it identically, rather than risking the two surfaces silently drifting apart.

## Android (`lib/`)

Flutter + Firebase (Auth, Firestore, Crashlytics). Notable structure:

```
lib/
├── screens/     # Map, GO, Detail, Browse, Add wizard, You, Onboarding
├── theme/       # Design tokens + reusable widgets
├── services/    # Firestore, haptics, notifications, orientation
├── logic/       # Trust/rating math, now backed by packages/shauchmap_core for Truth/Evidence/GO
├── widgets/     # Shared UI (states, OSM attribution, …)
├── adapters/    # Bridges legacy/community data fields into the shared-core model
├── field_audit/ # Local-only structured ground-inspection tool (see field-audit-method.md)
└── utils/       # Map launcher (hands off to native Google Maps — this app never
                 # implements its own turn-by-turn navigation), helpers
```

Toilets are indexed by geohash and fetched bounded to a radius around the user, so the app never pulls the full toilet corpus at once.

## Instant (`instant/`)

A Preact + TypeScript app built with Vite, deployed as static files to Firebase Hosting. See [instant.md](instant.md) for what it is and isn't. Source layout:

```
instant/src/
├── core/       # Compiled shauchmap_core output + the interop wrapper
├── data/       # Firestore read client (Firebase mode) and a fixture data source (no-Firebase mode)
├── domain/     # Instant-specific view logic over the shared core's decisions
├── location/   # Browser geolocation acquisition, staged for accuracy and timeout recovery
├── routes/     # Page-level components
├── ui/         # Shared UI (Shell, states, components — including the OSM attribution footer)
└── styles/     # Global CSS
```

## Cloud Functions (`functions/`)

A small TypeScript Cloud Functions codebase (`derive.ts`, `index.ts`) that performs server-side derivation work over contributed evidence. No Function in this codebase runs on a schedule that touches production data outside of what a real user action triggers.

## Firestore rules (`firestore.rules`)

Committed and public on purpose — this is the actual access-control enforcement, not the client code. See [SECURITY.md](../SECURITY.md).

## Testing strategy

Each layer has its own test suite: `packages/shauchmap_core` (`dart test`), the Android app (`flutter test`), Instant (`vitest`), Cloud Functions (unit + emulator), and Firestore rules (emulator-based rules tests). See the CI workflow (`.github/workflows/ci.yml`) for exactly which of these currently run on every pull request without needing production credentials — that list is kept accurate there rather than duplicated (and risking drift) here.
