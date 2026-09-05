# ShauchMap Privacy Policy

Last updated: September 2026. ShauchMap has two surfaces — the Android app and ShauchMap Instant (the web version) — with different data footprints. Both are covered here.

## Android app

**Location.** ShauchMap uses your current location to find toilets near you and to derive the query bounds sent to Cloud Firestore. We do not maintain our own database of your location history. Google Maps and other OS/platform location or navigation services may separately process location under their own policies when you use features that hand off to them (for example, tapping "Navigate") — that processing is between you and that provider, not something ShauchMap controls or sees.

**Google Account.** Name and email are collected when you sign in, to attribute your contributions (ratings, check-ins, condition checks, reports, and any toilets added under the account-attribution model) to your profile.

**Diagnostic data.** Crash information is collected via Firebase Crashlytics to help fix stability problems. We describe only what we actually know about this: Crashlytics reports are associated with an installation, not deliberately linked by ShauchMap to your name or email — but we don't independently control or audit everything Crashlytics itself collects, so we avoid calling this "anonymous" as a blanket claim. ShauchMap does not use Firebase Analytics.

**What we do not do:** sell your data, show ads, or track you outside the app.

**Account deletion.** Open ShauchMap → **You** tab → scroll down → tap **Delete Account**. This removes your account, your private profile, scout points, badges, saved toilets, and your public leaderboard entry. Some sanitation-contribution records you created — toilets added, ratings, condition checks, check-ins, reports and votes — may be **retained** (some publicly visible, some stored privately) so the map stays useful for others. Your profile name and email are removed, but an internal record identifier derived from your former account may remain on those records. We do not currently claim, and you should not assume, that retained contributions are fully anonymised.

## ShauchMap Instant (web)

Instant is deliberately a smaller surface than the Android app:

- **No account.** There is no sign-in of any kind. Nothing is tied to an identity.
- **Read-only.** Instant never writes to our database — it only reads nearby toilet records to make a recommendation. There is no rating, check-in, or Add-Toilet path on Instant.
- **No analytics, no tracking.** Instant does not use Firebase Analytics, Google Analytics, or any third-party tracking or advertising script.
- **Location.** With your permission, your device reports your current coordinates to your browser. ShauchMap Instant uses that position **on your device** to work out a nearby search area, and sends that **derived query range** (not a label of "this is you") to Firestore to retrieve candidate toilets. ShauchMap does not intentionally persist an Instant location history or write your current coordinates to its application database. Infrastructure providers (Firebase Hosting, Cloud Firestore, the underlying network) may maintain their own operational logs under their own policies — see "What we don't claim" below. We do **not** claim that your location "never leaves the browser": the location-derived query range does leave the browser, because that's how the nearby-toilet lookup works.
- **Google Maps handoff.** When you choose "Navigate," Instant opens Google's own Maps site or app with your chosen destination. That handoff is between you and Google — see Google's own privacy policy for what happens there.

## What we don't claim

We don't operate the underlying cloud, network, or hosting infrastructure ourselves — Firebase Hosting, Cloud Firestore, and Google's own network sit underneath both surfaces, and those providers may keep their own standard operational/infrastructure logs (e.g. request logs for abuse prevention) at a level we don't control and don't have visibility into beyond what their own privacy documentation describes. This policy describes what **ShauchMap itself** collects, stores, and does with your data — not what every layer of the internet between you and our servers logs.

## Contact

Questions: yogendra.yoji@gmail.com

---

For compliance, procurement, or legal questions about this policy, contact yogendra.yoji@gmail.com.
