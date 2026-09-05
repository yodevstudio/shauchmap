# Contributing to ShauchMap

Thanks for your interest in making public-toilet information in India more honest and useful. There are a few distinct ways to help — please use the right one for what you're reporting.

## 1. Report a stable data problem (no coding needed)

If a toilet's location is wrong, it's a duplicate, or it's permanently gone, file a [Toilet data report](https://github.com/YoDevStudio/ShauchMap/issues/new?template=toilet_data.yml). This is for **stable, identity-level problems** — GitHub Issues are public and not monitored in real time, so this is not the channel for "this toilet's condition right now."

## 2. Submit a current condition observation

Use the app's **Condition Check** action for this — it's the only path that feeds GO's current-condition authority (see [docs/truth-evidence-go.md](docs/truth-evidence-go.md)). One condition check doesn't make GO "more trustworthy" on its own: current condition works by strict majority across recent, time-bounded observations, not by volume, and it expires.

The app also has two related but different actions, worth knowing apart:
- **Ratings** are opinion only — they never carry current-condition authority.
- **Check-ins** are presence/progression bookkeeping — they don't assert or change a toilet's current condition either.

**Creating a new toilet record is currently paused** app-wide, pending a minimum-supported-version enforcement mechanism — none of the above is a way to add facilities that aren't mapped yet.

## 3. Contribute code

### Before you start
- Look through [open issues](https://github.com/YoDevStudio/ShauchMap/issues). Comment on one you'd like to take so we don't duplicate work.
- For anything larger than a small fix, open an issue first so we can align on approach.

### Local setup — Android
```bash
git clone https://github.com/YoDevStudio/ShauchMap.git
cd ShauchMap
flutter pub get
cp android/local.properties.example android/local.properties   # add your own Maps SDK key
flutter run
```
You will need **your own** Firebase project (`flutterfire configure`) and **your own** Google Maps SDK key, restricted to your own package name and signing certificate. **This repo contains no secrets and none should ever be committed.** Never point your local setup at the YoDevStudio production Firebase project or release keystore — those are production-only and not shared with contributors. Debug builds and `flutter analyze`/`flutter test` work without a real Maps key (a harmless placeholder is used); a `--release` build fails clearly if one isn't supplied — see `SECURITY.md`.

### Local setup — Instant (web)
```bash
cd instant
npm ci
npm run dev              # fixture mode — no Firebase project needed
```
Fixture mode is enough for most UI work. To run against a real Firebase project, see `docs/instant.md`.

### Local setup — Firestore rules / Cloud Functions
```bash
cd test/rules && npm ci && npm test          # rules allow/deny matrix, emulator-only
cd functions && npm ci && npm test          # unit tests
cd functions && npm run test:emulator       # emulator integration
```
All three run against the `demo-shauchmap` placeholder project via the local Firebase emulator — no real project or credentials needed. A JDK is required for the emulator (`JAVA_HOME` must point at one).

### Ground rules for the codebase
ShauchMap has a deliberate architecture. Please respect it:

- **Use the design tokens.** Never hardcode colours, type, spacing, or shadows — use `context.sm.<token>`, `SmText.*`, `SmTokens.*`, and the components in `lib/theme/sm_widgets.dart`.
- **Never** use `.withOpacity()` (use `.withValues(alpha:)`), `BackdropFilter`/blur, or custom-canvas map markers (`BitmapDescriptor` only).
- **Don't touch the data model.** The `Toilet` model and its `fromFirestore`/`toFirestore` are load-bearing across the app.
- **Keep logic and presentation separate.** UI composes tokens; business logic lives in `services/` and `logic/`.
- **Ratings and votes never gain current-condition authority.** If a change would let a rating, vote, check-in, or report count toward what GO treats as current condition, it's out of scope — see [docs/truth-evidence-go.md](docs/truth-evidence-go.md) for why that boundary is deliberate.

### Before you open a PR
```bash
flutter analyze     # must be clean — zero errors
dart format .       # must be formatted
flutter test        # if you touched anything with tests
```
Then fill out the pull-request template. Keep PRs focused — one concern per PR is easier to review and merge.

### Commit style
Conventional-ish and readable, e.g. `fix: peek card overflow on small screens`, `docs: clarify Firebase setup`, `refactor: simplify geohash bounding`.

## Code of Conduct
All participation is governed by our [Code of Conduct](CODE_OF_CONDUCT.md). Be kind; assume good faith.

Thank you.
