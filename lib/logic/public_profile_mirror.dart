// Pure helpers for the world-readable `public_profiles/{uid}`
// leaderboard mirror.
//
// WHY THIS FILE EXISTS
// -------------------
// The mirror is written from several client paths (interactive Google sign-in,
// silent Firebase-Auth resume, and every scout-points award). If only the
// interactive sign-in path ever wrote `name` / `photo_url`, a session that
// resumed auth silently and then earned points could CREATE a permanently
// bare `{scout_points, updated_at}` row — an anonymous leaderboard entry for
// every OTHER viewer. Centralising the projection + sanitisation here,
// UI- and Firestore-free, lets every writer compose an identical, rule-valid
// payload and lets the exact rules be unit-tested.
//
// FROZEN SCHEMA (the deployed rule for `/public_profiles/{userId}`):
//   keys  : ONLY {name, photo_url, scout_points, updated_at}   (hasOnly)
//   name  : absent OR string, length <= 80
//   photo_url : absent OR null OR string, length <= 500
//   scout_points : absent OR (int|float) >= 0
//   updated_at   : server timestamp
// A change to the constants below MUST be matched in `firestore.rules` and the
// 153-case rules matrix.

library;

/// Max stored length of `public_profiles.name` (mirrors the deployed rule).
const int kPublicProfileNameMaxLen = 80;

/// Max stored length of `public_profiles.photo_url` (mirrors the deployed rule).
const int kPublicProfilePhotoUrlMaxLen = 500;

/// Every key the public projection may ever contain. Any writer composing a
/// `/public_profiles` payload asserts its key set is a subset of this — a
/// structural guarantee that no private field (email, provider metadata,
/// badges, saved toilets, …) can leak into the world-readable doc.
const Set<String> kPublicProfileAllowedKeys = <String>{
  'name',
  'photo_url',
  'scout_points',
  'updated_at',
};

/// Product fallback display name. This is the SAME value the interactive
/// sign-in path already persists (`user.displayName ?? 'Explorer'`), so it is
/// not invented identity — it is the app's existing default persona, used only
/// so a leaderboard row is never blank when no real name is available.
const String kPublicProfileFallbackName = 'Explorer';

/// Sanitise a raw display name to the frozen public schema.
///
/// * `null` / empty / whitespace-only  → [kPublicProfileFallbackName]
/// * longer than [kPublicProfileNameMaxLen] → hard-truncated (no ellipsis)
///
/// Always returns a non-empty, in-range name.
String sanitizePublicName(String? raw) {
  final String trimmed = (raw ?? '').trim();
  final String base = trimmed.isEmpty ? kPublicProfileFallbackName : trimmed;
  return base.length > kPublicProfileNameMaxLen
      ? base.substring(0, kPublicProfileNameMaxLen)
      : base;
}

/// Sanitise a raw photo URL to the frozen public schema.
///
/// Returns `null` (→ caller OMITS the field; the rule permits absent/null) when
/// the value is `null` / empty / whitespace-only / longer than
/// [kPublicProfilePhotoUrlMaxLen]. Never returns an out-of-range string.
String? sanitizePublicPhotoUrl(String? raw) {
  final String trimmed = (raw ?? '').trim();
  if (trimmed.isEmpty) return null;
  if (trimmed.length > kPublicProfilePhotoUrlMaxLen) return null;
  return trimmed;
}

/// The sanitised IDENTITY fields for a `/public_profiles` merge write:
/// `name` always (fallback persona if needed), `photo_url` only when a valid
/// value survives sanitisation.
///
/// Callers merge this with `updated_at` (server timestamp) and — on the
/// points path only — `scout_points` (`FieldValue.increment`). Both extra keys
/// are in [kPublicProfileAllowedKeys]. The returned map never contains a
/// private field and never a `scout_points` key (so a mirror refresh can never
/// reset a score).
Map<String, Object> publicProfileIdentityFields({
  String? name,
  String? photoUrl,
}) {
  final Map<String, Object> out = <String, Object>{
    'name': sanitizePublicName(name),
  };
  final String? photo = sanitizePublicPhotoUrl(photoUrl);
  if (photo != null) out['photo_url'] = photo;
  return out;
}

/// True when [keys] is a subset of the frozen public projection — used in
/// `assert`s at every `/public_profiles` write site.
bool isPublicProfileKeySetValid(Iterable<String> keys) =>
    keys.every(kPublicProfileAllowedKeys.contains);
