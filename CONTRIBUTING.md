# Contributing to ShauchMap

Thanks for helping make clean public toilets findable across India. There are two kinds of contribution and both matter.

## 1. Contribute toilet data (no coding needed)

The single most valuable thing you can do is **use the app and add or verify toilets** in your area. Every check-in, rating, and new pin makes the next person's answer more trustworthy. If you spot bad or missing data, file a [Toilet data report](https://github.com/YoDevStudio/ShauchMap/issues/new?template=toilet_data.yml).

## 2. Contribute code

### Before you start
- Look through [open issues](https://github.com/YoDevStudio/ShauchMap/issues). Comment on one you'd like to take so we don't duplicate work.
- For anything larger than a small fix, open an issue or a [discussion](https://github.com/YoDevStudio/ShauchMap/discussions) first so we can align on approach.

### Local setup
```bash
git clone https://github.com/YoDevStudio/ShauchMap.git
cd ShauchMap
flutter pub get
cp .env.example .env      # add your own keys
flutter run --dart-define=PLACES_API_KEY=your_key_here
```
You will need your own Firebase project (`flutterfire configure`) and a Google Maps/Places key. **This repo contains no secrets and none should ever be committed.**

### Ground rules for the codebase
ShauchMap has a deliberate architecture. Please respect it:

- **Use the design tokens.** Never hardcode colours, type, spacing, or shadows — use `context.sm.<token>`, `SmText.*`, `SmTokens.*`, and the components in `lib/theme/sm_widgets.dart`.
- **Never** use `.withOpacity()` (use `.withValues(alpha:)`), `BackdropFilter`/blur, or custom-canvas map markers (`BitmapDescriptor` only).
- **Don't touch the data model.** The `Toilet` model and its `fromFirestore`/`toFirestore` are load-bearing across the app.
- **Keep logic and presentation separate.** UI composes tokens; business logic lives in `services/` and `logic/`.

### Before you open a PR
```bash
flutter analyze     # must be clean — zero errors
dart format .       # must be formatted
flutter test        # if you touched anything with tests
```
Then fill out the pull-request template. Keep PRs focused — one concern per PR is easier to review and merge.

### Commit style
Conventional-ish and readable, e.g. `feat: add women-safe filter chip`, `fix: peek card overflow on small screens`, `docs: clarify Firebase setup`.

## Code of Conduct
All participation is governed by our [Code of Conduct](CODE_OF_CONDUCT.md). Be kind; assume good faith.

Thank you 💚
