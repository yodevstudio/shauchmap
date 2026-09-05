# ShauchMap Instant

**Live at:** https://shauchmap.web.app

## What it is

A zero-install, read-only web surface running the same GO decision policy the Android app uses. It exists for the case where installing an app is the wrong ask — a QR code on a wall, a link shared in a message, someone who just needs an answer once and won't be back.

## What it deliberately doesn't do, and why that's a feature

- **No sign-in.** There's nothing to create an account for — Instant doesn't attribute anything to you.
- **No writes.** Instant never creates, updates, or deletes a Firestore document. It only reads nearby toilet records to make its recommendation. This is verified structurally, not just claimed: the production Instant bundle contains no Firestore write APIs (`addDoc`/`setDoc`/`updateDoc`/`deleteDoc`/`writeBatch`/`runTransaction`) at all.
- **No ratings, check-ins, or Add-Toilet path.** If you want to contribute evidence, that happens in the Android app, where it can be tied to an account and moderated the way community contributions need to be.
- **No analytics, no tracking.** See [PRIVACY.md](../PRIVACY.md).

None of this is a cut corner — a lightweight, read-only, account-free surface is a deliberately smaller and safer thing to hand to a stranger scanning a QR code than a full app account would be.

## Trying it

Open https://shauchmap.web.app, allow location when asked (Instant explains why before asking, and GO does need it — this isn't a zero-permission experience). GO then evaluates the nearby candidates under its one bounded decision policy: strong, fresh condition evidence can shape the pick, and where that evidence is absent it falls back to the nearest mapped option and says so, or says **Unknown** rather than guessing. "Navigate" hands off to Google Maps for turn-by-turn directions; Instant never implements its own.

## Installing as a PWA

Instant is an installable Progressive Web App — most mobile browsers offer an "Add to Home Screen" / "Install" prompt. Installed or not, it behaves identically; installing just gives it an icon and lets it run offline for anything already cached.

## Offline behavior

Once loaded, the app shell and static assets are cached by a service worker, so reopening Instant without a connection still loads the interface (though a fresh nearby-toilet lookup requires a live connection to Firestore, same as the Android app).

## Local development

```bash
cd instant
npm ci
npm run dev          # fixture mode — synthetic data, no Firebase project needed
```

Fixture mode is enough for almost all UI and interaction work. To run against a real Firebase project (for testing the actual read path), copy `instant/.env.example` to `instant/.env.local` and point it at your own Firebase project — never at the YoDevStudio production project. See `instant/package.json` for the full script list (typecheck, lint, test, and the guarded production build).
