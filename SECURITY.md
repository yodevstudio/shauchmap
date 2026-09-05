# Security Policy

## Reporting a vulnerability

If you discover a security issue, **please do not open a public issue.** Instead, report it privately through GitHub's [security advisories](https://github.com/YoDevStudio/ShauchMap/security/advisories/new) or by contacting the maintainer directly. We'll acknowledge your report as quickly as we can and keep you updated on the fix.

## What's actually private, and what isn't

Not everything that looks like a "key" is a secret in the same sense. Here's the honest breakdown:

| Item | Classification | How it's handled |
| :-- | :-- | :-- |
| Release signing keystore (`*.jks`, `android/key.properties`) | **Secret** | Local only, git-ignored, never committed |
| Firebase admin / service-account credentials | **Secret** | Never present in this repository |
| Google Maps SDK key (Android native map rendering) | **Restricted-by-design, client-visible API key** | Resolved at build time from `android/local.properties` (git-ignored) or a `MAPS_API_KEY` environment variable, and injected into `AndroidManifest.xml` as a manifest placeholder (`${MAPS_API_KEY}`) — **never a literal in tracked source**. A `--release` build fails closed if no key is configured (see `android/app/build.gradle.kts`); debug builds and CI checks compile with a harmless placeholder that doesn't render real maps. The intended model is that this key is restricted in Google Cloud Console (Android package name + release-signing certificate SHA-1 + API allowlist) rather than kept secret as a string — Android Maps SDK keys are inherently visible to anyone who decompiles an installed APK, on every app that uses one, not just this one. **This document does not assert that the currently deployed production key's Cloud Console restrictions have been independently verified** — that check requires Google Cloud Console access this repository's own tooling doesn't have |
| Firebase client configuration (`google-services.json`, `firebase_options.dart`, the Firebase Web `apiKey`) | **Not a secret / not an authorization boundary** | Firebase's own security model puts real enforcement in **Firestore Security Rules**, not in hiding this value — a client config value only identifies which project to talk to. This repo still keeps these files git-ignored, but for a different reason: clean fork separation, so a contributor's build talks to *their own* Firebase project (via `flutterfire configure`) rather than accidentally pointing at production |
| Firestore Security Rules (`firestore.rules`) | **Intentionally public** | This is the actual access-control boundary, and it's committed to this repo on purpose — a reviewer should be able to see exactly what's enforced, not have to trust an opaque backend |

There is no separate Places/Geocoding Web Service key in this app — an earlier direct-HTTP integration with that API was removed because production builds never provisioned a key for it; searching by name or address now works entirely over the toilets already loaded into the app (see the README).

## If you fork this project

- Create and restrict **your own** Google Maps SDK key (restricted by package name and your own release-signing certificate's SHA-1).
- Set up **your own** Firebase project via `flutterfire configure` — never point a fork at the YoDevStudio production Firebase project.
- Generate **your own** release keystore — never reuse another project's signing key, and never use the YoDevStudio release keystore.
- Double-check `git status` before your first push; if a secret ever lands in history, rotate it immediately.

## Supported versions

The latest release on the `main` branch receives security updates.
