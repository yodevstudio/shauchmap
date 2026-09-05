// public_profiles mirror robustness.
//
// If only the INTERACTIVE Google sign-in path ever wrote `name` / `photo_url`
// to `public_profiles/{uid}`, a silently-resumed auth session that then
// earned scout points would create a permanently BARE
// `{scout_points, updated_at}` row — an anonymous leaderboard entry for
// every other viewer. This file locks down the fix.
//
// The fix centralises the projection + sanitisation in
// `lib/logic/public_profile_mirror.dart` and adds
// `FirestoreService.ensurePublicProfileMirror`, called from EVERY auth path.
//
// `FirestoreService` needs a live Firestore, so — exactly as
// `rollout_gate_test.dart` does for the Add-Toilet guard — the Firestore
// round-trips (merge / FieldValue.increment / create-vs-update) are proven in
// the emulator suite (`test/rules/pp_mirror_emulator.mjs`), while
// this file locks down the pure projection/sanitisation logic and the
// once-per-uid auth guard that all three write paths compose.

import 'package:flutter_test/flutter_test.dart';
import 'package:shauchmap_app/logic/public_profile_mirror.dart';

void main() {
  group('sanitizePublicName — CASE 8 (schema/rule constraints)', () {
    test('null / empty / whitespace-only -> product fallback persona', () {
      expect(sanitizePublicName(null), kPublicProfileFallbackName);
      expect(sanitizePublicName(''), kPublicProfileFallbackName);
      expect(sanitizePublicName('    '), kPublicProfileFallbackName);
      expect(sanitizePublicName('\n\t '), kPublicProfileFallbackName);
    });

    test('a real name is trimmed but otherwise preserved', () {
      expect(sanitizePublicName('  Yogendra Singh  '), 'Yogendra Singh');
    });

    test('a name longer than the rule limit is hard-truncated to 80, no '
        'ellipsis', () {
      final long = 'x' * 200;
      final out = sanitizePublicName(long);
      expect(out.length, kPublicProfileNameMaxLen);
      expect(out.length, 80);
      expect(out, 'x' * 80);
      expect(out.endsWith('…'), isFalse);
    });

    test('a name exactly at the limit is untouched', () {
      final exact = 'y' * 80;
      expect(sanitizePublicName(exact), exact);
    });

    test('never returns empty (the row is never left nameless)', () {
      for (final raw in <String?>[null, '', '   ', 'A', 'z' * 999]) {
        expect(sanitizePublicName(raw).isNotEmpty, isTrue);
      }
    });
  });

  group('sanitizePublicPhotoUrl — CASE 8 (schema/rule constraints)', () {
    test('null / empty / whitespace-only -> null (field is omitted)', () {
      expect(sanitizePublicPhotoUrl(null), isNull);
      expect(sanitizePublicPhotoUrl(''), isNull);
      expect(sanitizePublicPhotoUrl('   '), isNull);
    });

    test('a normal URL is trimmed and kept', () {
      expect(
        sanitizePublicPhotoUrl('  https://lh3.googleusercontent.com/a/x=s96  '),
        'https://lh3.googleusercontent.com/a/x=s96',
      );
    });

    test('a URL longer than the rule limit -> null (omit, never write an '
        'out-of-range string)', () {
      final long = 'https://example.com/${'p' * 600}';
      expect(long.length > kPublicProfilePhotoUrlMaxLen, isTrue);
      expect(sanitizePublicPhotoUrl(long), isNull);
    });

    test('a URL exactly at the limit is kept', () {
      final exact = 'h' * kPublicProfilePhotoUrlMaxLen;
      expect(sanitizePublicPhotoUrl(exact), exact);
    });
  });

  group('publicProfileIdentityFields — shared composition for all 3 write '
      'paths', () {
    test('CASE 1 — silent resume with a real auth name + photo -> full '
        'identity, no score key, no private key', () {
      final f = publicProfileIdentityFields(
        name: 'Yogendra Singh',
        photoUrl: 'https://lh3.googleusercontent.com/a/x=s96',
      );
      expect(f['name'], 'Yogendra Singh');
      expect(f['photo_url'], 'https://lh3.googleusercontent.com/a/x=s96');
      // The mirror NEVER carries scout_points — so a mirror refresh can never
      // reset a score (merge:true keeps whatever is already stored).
      expect(f.containsKey('scout_points'), isFalse);
      // CASE 7 — only ever projection keys, never a private field.
      expect(isPublicProfileKeySetValid(f.keys), isTrue);
      for (final forbidden in const [
        'email',
        'uid',
        'badges',
        'saved_toilets',
        'toilets_added',
        'provider',
        'phone',
        'streak_count',
      ]) {
        expect(f.containsKey(forbidden), isFalse);
      }
    });

    test('CASE 3 — silent resume when only a bare {scout_points, updated_at} '
        'row exists: payload backfills name/photo and omits scout_points so '
        'the stored 30 is preserved by merge', () {
      final f = publicProfileIdentityFields(
        name: 'Yogendra Singh',
        photoUrl: 'https://photo/x',
      );
      expect(f['name'], 'Yogendra Singh');
      expect(f['photo_url'], 'https://photo/x');
      expect(f.containsKey('scout_points'), isFalse);
    });

    test('CASE 5 — full doc already exists: identical inputs -> identical, '
        'in-range payload (idempotent, non-destructive)', () {
      final a = publicProfileIdentityFields(
        name: 'Yogendra Singh',
        photoUrl: 'https://photo/x',
      );
      final b = publicProfileIdentityFields(
        name: 'Yogendra Singh',
        photoUrl: 'https://photo/x',
      );
      expect(a, b);
      expect(isPublicProfileKeySetValid(a.keys), isTrue);
    });

    test('CASE 2 / CASE 4 — points path: identity fields are supplied for '
        'addScoutPoints to merge ALONGSIDE its own scout_points increment '
        '(so a first-write points award still creates name+photo, and a '
        'later award never drops them)', () {
      // addScoutPoints spreads exactly these keys next to
      // {scout_points: FieldValue.increment(n), updated_at: serverTimestamp()}.
      final f = publicProfileIdentityFields(
        name: 'Yogendra Singh',
        photoUrl: 'https://photo/x',
      );
      expect(f['name'], 'Yogendra Singh');
      expect(f['photo_url'], 'https://photo/x');
      // The union {name, photo_url} ∪ {scout_points, updated_at} is still a
      // subset of the frozen projection.
      final union = {...f.keys, 'scout_points', 'updated_at'};
      expect(isPublicProfileKeySetValid(union), isTrue);
    });

    test('no photo available -> photo_url key omitted (rule allows absent), '
        'name still present via fallback', () {
      final f = publicProfileIdentityFields(name: null, photoUrl: null);
      expect(f['name'], kPublicProfileFallbackName);
      expect(f.containsKey('photo_url'), isFalse);
      expect(isPublicProfileKeySetValid(f.keys), isTrue);
    });

    test('CASE 8 — an overlong auth name is clamped before it can reach the '
        'write (rule would otherwise reject it)', () {
      final f = publicProfileIdentityFields(name: 'q' * 500, photoUrl: null);
      expect((f['name'] as String).length, 80);
    });
  });

  // CASE 6 — repeated auth-state callbacks must not cause a write storm.
  // Reproduces the exact once-per-uid guard from
  // `_NavigationShellState._ensurePublicProfileFor` (main.dart), the same way
  // rollout_gate_test.dart reproduces the shipped Add-Toilet guard.
  group('CASE 6 — auth-state mirror guard (once per uid per session)', () {
    test('many callbacks for the same uid -> exactly one mirror write; '
        'sign-out then sign-in re-arms it', () {
      String? ensuredUid;
      var mirrorWrites = 0;

      void onAuthUser(String? uid) {
        if (uid == null) {
          ensuredUid = null; // signed out — re-arm
          return;
        }
        if (ensuredUid == uid) return; // guard
        ensuredUid = uid;
        mirrorWrites++;
      }

      // 5 rapid callbacks for the same user (cold start + token refreshes).
      for (var i = 0; i < 5; i++) {
        onAuthUser('uidA');
      }
      expect(mirrorWrites, 1);

      // Sign out, then a different user signs in.
      onAuthUser(null);
      onAuthUser('uidB');
      onAuthUser('uidB');
      expect(mirrorWrites, 2);

      // Original user returns -> one more ensure.
      onAuthUser(null);
      onAuthUser('uidA');
      expect(mirrorWrites, 3);
    });

    test(
      'a mirror failure clears the guard so the next auth event retries',
      () {
        String? ensuredUid;
        var attempts = 0;

        void onAuthUser(String uid, {required bool willFail}) {
          if (ensuredUid == uid) return;
          ensuredUid = uid;
          attempts++;
          if (willFail && ensuredUid == uid) {
            ensuredUid = null; // catchError path in _ensurePublicProfileFor
          }
        }

        onAuthUser('uidA', willFail: true);
        expect(attempts, 1);
        onAuthUser('uidA', willFail: false); // retry succeeds
        expect(attempts, 2);
        onAuthUser('uidA', willFail: false); // now guarded
        expect(attempts, 2);
      },
    );
  });
}
