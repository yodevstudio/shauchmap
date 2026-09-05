# ShauchMap Instant

Open a link or scan a QR → share your location → GO evaluates the nearby
candidates: strong fresh evidence can shape the pick, and when it's absent GO
falls back to the nearest mapped option and says so — **Unknown** stays
Unknown, never a guess → a Google Maps route. No install, no sign-in, no map
to pan. Live at https://shauchmap.web.app — see
[../docs/instant.md](../docs/instant.md) for what it is and isn't.

A Preact + TypeScript shell over **one authoritative pure-Dart core**
(`../packages/shauchmap_core`) compiled to JS — the web shell never
reimplements Truth / Evidence / GO / revalidation / location freshness /
distance; every one of those calls the compiled core.

## Run

```bash
npm install
npm run dev        # predev compiles the Dart core -> generated/shauchmap_core.js
```

Dev: http://127.0.0.1:5174 · Preview a production build: `npm run build && npm run preview` (4174).

Requires a Dart SDK for `build:core` — it looks for `$DART`, `dart` on PATH, then
`$FLUTTER_ROOT/bin/cache/dart-sdk/bin/dart`.

## Scripts

| script | what |
|---|---|
| `npm run build:core` | `dart compile js -O2` the real core → `generated/shauchmap_core.js` (+ `.meta.json`) |
| `npm run dev` / `build` | Vite dev / production build (core built first) |
| `npm run typecheck` / `lint` / `test` | `tsc --noEmit` / ESLint / Vitest |
| `npm run oracle` | run the shared-core oracle vectors through the compiled JS in headless Chrome; asserts NATIVE == CHROMIUM |
| `node scripts/measure.mjs` | production-build size + mobile-throttled FCP / time-to-usable (needs `npm run preview` running) |
| `node scripts/browser-smoke.mjs <engine>` | lightweight per-engine smoke: loads the canonical routes, asserts no horizontal scroll and the expected key element is present |
| `node scripts/responsive-matrix.mjs` | full responsive/visual matrix across viewports |

## Data modes (`VITE_DATA_MODE`)

* **`fixture`** (default) — deterministic demo data, persistent "DEMO DATA"
  banner. No Firebase.
* **`firebase`** — real Firestore *Lite* adapter, the mode the live deployment
  runs in. Requires **all** of `VITE_FIREBASE_{API_KEY,PROJECT_ID,APP_ID,DATABASE_ID}`
  in `.env.local` (see `.env.example`). A production build that asks for
  `firebase` with any missing **fails the build** — it never silently falls
  back to fixtures.

## Fixture-mode demo query hooks (inert in a Firebase / production build)

| param | effect |
|---|---|
| `?demo=default\|unknown\|confirm\|none\|empty` | pick a demo "world" |
| `?loc=<lat>,<lng>` | pin a location without the sensor |
| `?locage=<seconds>` | age the pinned fix (`> 10` → stale) |
| `?locerr=denied\|timeout\|unavailable\|future` | simulate a location failure |
| `?fail=offline\|timeout\|partial` | simulate a data-layer failure |
| `?reval=launch\|refreshSuggestion\|refreshOption\|confirmThenLaunch` | force a revalidation outcome |
| `?perm=prompt` | force the permission-explainer |

## Layout

```
scripts/build-core.mjs      real Dart core -> generated/shauchmap_core.js
generated/                  build output (git-ignored)
src/core/                   typed interop wrapper + version guard + loader
src/data/                   mode, normalize, fixtures, source seam, fixture + firestore sources, geohash
src/domain/                 geo-pool (15km), resolve-go, revalidate, travel-mode
src/location/               browser geolocation adapter (freshness via the core)
src/routes/  src/ui/        preact-iso routes + components + failure states
test/                       Vitest (interop, normalize, geo-pool, location, revalidate, firestore, travel, mode, render/routing)
```
