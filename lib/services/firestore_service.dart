import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import 'package:geoflutterfire_plus/geoflutterfire_plus.dart';
import 'package:shauchmap_core/shauchmap_core.dart';

import '../adapters/firestore_domain_adapter.dart';
import '../config/rollout_config.dart';
import '../logic/public_profile_mirror.dart';
import 'notification_service.dart';

// the domain read model + Truth V2 + Evidence V2 + GO V2 now live in
// `package:shauchmap_core`. Re-exported here so every existing
// `import '.../services/firestore_service.dart'` site keeps seeing `Toilet`,
// `ToiletTruth`, `ToiletEvidence`, `decideGo`, … unchanged.
export 'package:shauchmap_core/shauchmap_core.dart';
export '../adapters/firestore_domain_adapter.dart'
    show
        toiletFromFirestore,
        truthV2SubmissionMap,
        normalizeFirestoreTimestamps,
        GeolocatorPositionToGeoPos;

class FirestoreService {
  final FirebaseFirestore _db = FirebaseFirestore.instance;

  Stream<List<Toilet>> getToiletsNearby({
    required double latitude,
    required double longitude,
    double radiusKm = 10.0,
  }) {
    final center = GeoFirePoint(GeoPoint(latitude, longitude));
    final collectionRef = _db.collection('toilets');
    return GeoCollectionReference<Map<String, dynamic>>(collectionRef)
        .subscribeWithin(
          center: center,
          radiusInKm: radiusKm,
          field: 'position',
          geopointFrom: (data) => (data['position']['geopoint'] as GeoPoint),
          strictMode: true,
        )
        .map(
          (list) => list
              .map((doc) => toiletFromFirestore(doc))
              .where((t) => t.latitude != 0.0 && t.longitude != 0.0)
              .toList(),
        );
  }

  /// ONE-SHOT bounded candidate pool for GO V2.
  ///
  /// Uses `fetchWithinWithDistance` so the COMPLETE strict [radiusKm]-bounded
  /// result is fetched and carries a per-record distance from
  /// [latitude]/[longitude]. Structurally-invalid records (0,0 coordinates) are
  /// dropped; the survivors are ordered `(distanceKm asc, toilet.id asc)` for
  /// DETERMINISTIC / stable behaviour, and **every** one is returned.
  ///
  /// There is NO decision cap. `RecommendationAuthority` is part of the frozen
  /// GO policy, so a pre-engine "nearest N" truncation could hide the only
  /// source-mapped primary (or the only unflagged record) behind N nearer
  /// candidate / flagged records and manufacture a false no-primary /
  /// flagged-only result. `decideGo` owns authority — it must see the whole
  /// 15-km bounded universe. (The cap also saved zero Firestore reads:
  /// `fetchWithinWithDistance` already fetched every covered document.)
  Future<List<Toilet>> getGoPool({
    required double latitude,
    required double longitude,
    double radiusKm = 15.0,
  }) async {
    final center = GeoFirePoint(GeoPoint(latitude, longitude));
    final collectionRef = _db.collection('toilets');

    final geoDocs =
        await GeoCollectionReference<Map<String, dynamic>>(
          collectionRef,
        ).fetchWithinWithDistance(
          center: center,
          radiusInKm: radiusKm,
          field: 'position',
          geopointFrom: (data) => (data['position']['geopoint'] as GeoPoint),
          strictMode: true,
        );

    final ranked = <Ranked<Toilet>>[];
    for (final g in geoDocs) {
      final t = toiletFromFirestore(g.documentSnapshot);
      if (t.latitude != 0.0 && t.longitude != 0.0) {
        ranked.add((item: t, distanceKm: g.distanceFromCenterInKm));
      }
    }
    // limit: 0 => deterministic ordering, NO truncation of the decision universe.
    return orderNearest(ranked, (t) => t.id, limit: 0);
  }

  // Add a new toilet — writes geopoint+geohash so geo queries can find it.
  // FAIL-CLOSED consumer write boundary. A native V2 create can
  // never be reached from consumer code while the Add-Toilet gate is off, even
  // if a UI entry point is missed. (Not a security boundary — the deployed rules
  // are — but it stops the shipped/accidental client path centrally.)
  Future<void> addToilet(Map<String, dynamic> data) async {
    RolloutConfig.assertConsumerAddToiletAllowed();
    final double lat = data['latitude'] as double;
    final double lng = data['longitude'] as double;
    final geoPoint = GeoPoint(lat, lng);
    data['position'] = {
      'geopoint': geoPoint,
      'geohash': GeoFirePoint(geoPoint).geohash,
    };
    await _db.collection('toilets').add(data);

    final String? userId = data['added_by'];
    if (userId != null && userId.isNotEmpty) {
      await _db.collection('users').doc(userId).set({
        'toilets_added_count': FieldValue.increment(1),
      }, SetOptions(merge: true));
      await checkAndAwardBadges(userId);
    }
  }

  // Submit or update the signed-in user's rating for a toilet.
  //
  // TRUST MODEL (2026-09-02 integrity pass):
  //   - The rating DOCUMENT ID IS the author's uid: toilets/{t}/ratings/{uid}.
  //     One rating per account, enforced structurally by the rules — a modified
  //     client cannot mint extra rows under random ids. No pre-query needed.
  //   - Payload is {stars(int 1..5), tags, note, timestamp}. NO user_id /
  //     user_name — the review renders as "Community review". (The doc id is
  //     still account-derived; this is not full anonymisation.)
  //   - `timestamp` is always the server time (rules require == request.time).
  //   - Does NOT touch the parent toilet. star_rating / total_ratings are
  //     derived at read time by getRatingSummary(). No last_verified write.
  Future<void> addRating(
    String toiletId,
    Map<String, dynamic> ratingData,
  ) async {
    final String? userId = ratingData['user_id'];
    if (userId == null || userId.isEmpty) return;

    final ratingRef = _db
        .collection('toilets')
        .doc(toiletId)
        .collection('ratings')
        .doc(userId);
    final bool isUpdate = (await ratingRef.get()).exists;

    await ratingRef.set({
      'stars': (ratingData['stars'] as num).toInt(),
      'tags': ratingData['tags'] ?? <String>[],
      'note': ratingData['note'] ?? '',
      'timestamp': FieldValue.serverTimestamp(),
    });

    if (!isUpdate) {
      await _db.collection('users').doc(userId).set({
        'ratings_given': FieldValue.increment(1),
      }, SetOptions(merge: true));
      await addScoutPoints(userId, 10);
      await checkAndAwardBadges(userId);
    }
  }

  // Read-time rating aggregate for the one-toilet DetailSheet. Un-forgeable:
  // computed by Firestore from the owner-scoped rating docs (one per account).
  // `ok == false` means the aggregation QUERY FAILED — the caller must show
  // "Unavailable", NOT a fabricated "0 ratings".
  Future<({int count, double average, bool ok})> getRatingSummary(
    String toiletId,
  ) async {
    try {
      final col = _db.collection('toilets').doc(toiletId).collection('ratings');
      final agg = await col.aggregate(count(), average('stars')).get();
      final int c = agg.count ?? 0;
      final double a = c == 0 ? 0.0 : (agg.getAverage('stars') ?? 0.0);
      return (count: c, average: a, ok: true);
    } catch (_) {
      return (count: 0, average: 0.0, ok: false);
    }
  }

  // Stream of recent reviews for a toilet (limit 10)
  Stream<List<Map<String, dynamic>>> getRecentRatingsStream(String toiletId) {
    return _db
        .collection('toilets')
        .doc(toiletId)
        .collection('ratings')
        .orderBy('timestamp', descending: true)
        .limit(10)
        .snapshots()
        .map((snapshot) {
          return snapshot.docs.map((doc) => doc.data()).toList();
        });
  }

  // Bookmark a toilet
  Future<void> saveToilet(String userId, String toiletId) async {
    await _db.collection('users').doc(userId).update({
      'saved_toilets': FieldValue.arrayUnion([toiletId]),
    });
  }

  // Remove bookmark
  Future<void> unsaveToilet(String userId, String toiletId) async {
    await _db.collection('users').doc(userId).update({
      'saved_toilets': FieldValue.arrayRemove([toiletId]),
    });
  }

  // Fetch single user document stream
  Stream<DocumentSnapshot> getUserStream(String userId) {
    return _db.collection('users').doc(userId).snapshots();
  }

  // Create/Update the PRIVATE user doc, and mirror the small public leaderboard
  // row (public_profiles/{uid} — world-readable, only {name, photo_url,
  // scout_points, updated_at}). email / provider data / saved_toilets stay
  // private in /users and are never copied to /public_profiles.
  Future<void> createOrUpdateUser(
    String userId,
    String name,
    String email,
    String? photoUrl,
  ) async {
    final userRef = _db.collection('users').doc(userId);
    final docSnap = await userRef.get();

    if (!docSnap.exists) {
      await userRef.set({
        'name': name,
        'email': email,
        'photo_url': photoUrl,
        'scout_points': 0,
        'saved_toilets': [],
        'badges': [],
        'toilets_added': [],
      }, SetOptions(merge: true));
    } else {
      await userRef.set({
        'name': name,
        'email': email,
        'photo_url': photoUrl,
      }, SetOptions(merge: true));
    }

    final int points = (docSnap.data()?['scout_points'] as num?)?.toInt() ?? 0;
    final Map<String, dynamic> pub = {
      ...publicProfileIdentityFields(name: name, photoUrl: photoUrl),
      'scout_points': points < 0 ? 0 : points,
      'updated_at': FieldValue.serverTimestamp(),
    };
    assert(isPublicProfileKeySetValid(pub.keys));
    await _db
        .collection('public_profiles')
        .doc(userId)
        .set(pub, SetOptions(merge: true));
  }

  /// Idempotent public-leaderboard mirror. Safe to call any number of times,
  /// from ANY auth path — interactive Google sign-in, a silently-resumed
  /// Firebase Auth session, or an app restart.
  ///
  /// Writes ONLY the sanitised public projection with `SetOptions(merge: true)`:
  ///   * `name` (real value, else the product fallback persona) and, when a
  ///     valid value survives sanitisation, `photo_url`;
  ///   * `updated_at` = server timestamp;
  ///   * NEVER `scout_points` here — the score is owned by
  ///     [createOrUpdateUser]'s initial mirror and [addScoutPoints]'s atomic
  ///     increment, so a mirror refresh can never reset it;
  ///   * NEVER a private field (email / provider / badges / saved toilets).
  ///
  /// `merge: true` means this only ADDS/REFRESHES `name` + `photo_url` +
  /// `updated_at`; it never destroys an existing document. A bare
  /// `{scout_points, updated_at}` row (the historical anonymous-mirror defect)
  /// is repaired to the full projection on the first call.
  ///
  /// [name] / [photoUrl] should be passed from `FirebaseAuth.currentUser`
  /// (the authoritative upstream identity). When [name] is missing this falls
  /// back to the private `/users/{uid}` mirror before sanitising. A write
  /// failure is logged and swallowed — it must never break the auth session.
  Future<void> ensurePublicProfileMirror(
    String userId, {
    String? name,
    String? photoUrl,
  }) async {
    if (userId.isEmpty) return;

    String? resolvedName = name;
    String? resolvedPhoto = photoUrl;
    if (resolvedName == null || resolvedName.trim().isEmpty) {
      try {
        final data = (await _db.collection('users').doc(userId).get()).data();
        resolvedName ??= data?['name'] as String?;
        resolvedPhoto ??= data?['photo_url'] as String?;
      } catch (_) {
        // Keep whatever the caller supplied; sanitiser handles null.
      }
    }

    final Map<String, dynamic> payload = {
      ...publicProfileIdentityFields(
        name: resolvedName,
        photoUrl: resolvedPhoto,
      ),
      'updated_at': FieldValue.serverTimestamp(),
    };
    assert(isPublicProfileKeySetValid(payload.keys));

    try {
      await _db
          .collection('public_profiles')
          .doc(userId)
          .set(payload, SetOptions(merge: true));
    } catch (e) {
      debugPrint('ensurePublicProfileMirror write failed (non-fatal): $e');
    }
  }

  // Unlock badge
  Future<void> unlockBadge(String userId, String badgeId) async {
    await _db.collection('users').doc(userId).set({
      'badges': FieldValue.arrayUnion([badgeId]),
    }, SetOptions(merge: true));
  }

  // Check and award milestone badges based on counters
  Future<void> checkAndAwardBadges(String userId) async {
    try {
      final userRef = _db.collection('users').doc(userId);
      final userSnap = await userRef.get();
      if (!userSnap.exists) return;
      final data = userSnap.data() ?? {};

      final int scoutPoints = (data['scout_points'] as num?)?.toInt() ?? 0;
      final int toiletsAdded =
          (data['toilets_added_count'] as num?)?.toInt() ?? 0;
      final int ratingsGiven = (data['ratings_given'] as num?)?.toInt() ?? 0;
      final int womenSafeVerifies =
          (data['women_safe_verifies'] as num?)?.toInt() ?? 0;
      final List<dynamic> currentBadges =
          data['badges'] as List<dynamic>? ?? [];

      final List<String> newBadges = [];

      if (toiletsAdded >= 1 && !currentBadges.contains('first_scout')) {
        newBadges.add('first_scout');
      }
      if (toiletsAdded >= 5 && !currentBadges.contains('mapper')) {
        newBadges.add('mapper');
      }
      if (toiletsAdded >= 25 && !currentBadges.contains('cartographer')) {
        newBadges.add('cartographer');
      }
      if (ratingsGiven >= 1 && !currentBadges.contains('reviewer')) {
        newBadges.add('reviewer');
      }
      if (womenSafeVerifies >= 1 && !currentBadges.contains('guardian')) {
        newBadges.add('guardian');
      }
      if (scoutPoints >= 1000 && !currentBadges.contains('legend')) {
        newBadges.add('legend');
      }

      if (newBadges.isNotEmpty) {
        await userRef.set({
          'badges': FieldValue.arrayUnion(newBadges),
        }, SetOptions(merge: true));
      }

      // Request notification permissions after first contribution
      await NotificationService().requestPermissionIfNeeded();
    } catch (e) {
      debugPrint('checkAndAwardBadges error: \$e');
    }
  }

  // Increment scout points on the private user doc AND mirror onto the public
  // leaderboard row. NOTE (documented limitation): scout_points is authored by
  // the client here, so it is self-reportable / cosmetic. Server-side accrual
  // (a Cloud Function) is the deferred fix — until then the leaderboard is an
  // honest-effort cosmetic score, not a trusted ranking.
  Future<void> addScoutPoints(String userId, int points) async {
    await _db.collection('users').doc(userId).set({
      'scout_points': FieldValue.increment(points),
    }, SetOptions(merge: true));

    // Public leaderboard mirror. The score stays ATOMIC (FieldValue.increment)
    // and `merge: true` removes nothing. We ALSO carry the sanitised
    // name/photo_url (from the private /users mirror) so that if this points
    // award is the very first /public_profiles write for the account — e.g. a
    // silently-resumed auth session that earned points before the auth-state
    // mirror ran — it CREATES the full projection, never a permanently bare
    // {scout_points, updated_at} row (the defect).
    final Map<String, dynamic> pub = {
      'scout_points': FieldValue.increment(points),
      'updated_at': FieldValue.serverTimestamp(),
    };
    try {
      final data = (await _db.collection('users').doc(userId).get()).data();
      pub.addAll(
        publicProfileIdentityFields(
          name: data?['name'] as String?,
          photoUrl: data?['photo_url'] as String?,
        ),
      );
    } catch (_) {
      // Read failed — still mirror the score; the auth-state mirror backfills
      // name/photo on the next app start.
    }
    assert(isPublicProfileKeySetValid(pub.keys));
    await _db
        .collection('public_profiles')
        .doc(userId)
        .set(pub, SetOptions(merge: true));
  }

  // Check in to a toilet.
  //
  // TRUST MODEL (2026-09-02 integrity pass): a check-in means only "this account
  // was physically here". It does NOT imply open / usable / water / safe /
  // verified, and it does NOT write last_verified.
  //
  //   - The check-in DOCUMENT ID IS the author's uid:
  //     toilets/{t}/check_ins/{uid} — the account's LATEST check-in at that
  //     toilet. Read is the user's own deterministic doc, not a query.
  //   - The 4-hour cool-down is enforced BY THE RULES on `update`
  //     (request.time >= previous.timestamp + 4h). The client pre-check below
  //     is only a nicer "already checked in" message; the rule is the guard.
  //   - `timestamp` is always the server time.
  Future<bool> checkIn(String toiletId, String userId) async {
    final ref = _db
        .collection('toilets')
        .doc(toiletId)
        .collection('check_ins')
        .doc(userId);
    final snap = await ref.get();
    if (snap.exists) {
      final ts = snap.data()?['timestamp'] as Timestamp?;
      if (ts != null && DateTime.now().difference(ts.toDate()).inHours < 4) {
        return false;
      }
    }

    // create (first time) or update (rules enforce the >= 4h gap).
    await ref.set({'timestamp': FieldValue.serverTimestamp()});

    await addScoutPoints(userId, 20);
    await checkAndAwardBadges(userId);
    return true;
  }

  // Submit a CONDITION CHECK: a tri-state observation of the facility right now.
  //
  // TRUST MODEL (2026-09-02 integrity pass):
  //  - The DOCUMENT ID IS the author's uid: toilets/{t}/condition_checks/{uid}.
  //    This is the account's LATEST observation for that toilet — NOT immutable
  //    history. `.set()` overwrites the account's previous row, so one account
  //    can never occupy more than one row in the last-N majority. Longitudinal
  //    history is a future server-side concern, not something to fake with an
  //    abuseable client collection.
  //  - No `user_id` field: ownership is the doc id.
  //  - There is NO women-safety question; nothing writes a women-safety flag.
  //  - `open` / `water` / `usable` (and optional `lock`) are 'yes' | 'no' |
  //    'unknown'. UNKNOWN is first-class and is stored, not coerced.
  //  - `timestamp` is always the server time (rules require == request.time).
  //  - Does NOT touch the parent toilet. Freshness / status derived at read.
  Future<void> submitConditionCheck(
    String toiletId,
    String userId, {
    required String open,
    required String water,
    required String usable,
    String? lock,
  }) async {
    String tri(String v) =>
        (v == 'yes' || v == 'no' || v == 'unknown') ? v : 'unknown';

    final Map<String, dynamic> payload = {
      'open': tri(open),
      'water': tri(water),
      'usable': tri(usable),
      'timestamp': FieldValue.serverTimestamp(),
    };
    if (lock != null) payload['lock'] = tri(lock);

    await _db
        .collection('toilets')
        .doc(toiletId)
        .collection('condition_checks')
        .doc(userId)
        .set(payload);

    await addScoutPoints(userId, 15);
    await checkAndAwardBadges(userId);

    // Private, cosmetic per-user counter. Nothing authoritative reads it.
    await _db
        .collection('users')
        .doc(userId)
        .collection('toilet_wardens')
        .doc(toiletId)
        .set({
          'verify_count': FieldValue.increment(1),
        }, SetOptions(merge: true));
  }

  // Stream of the 3 most recent condition checks for a toilet.
  Stream<List<Map<String, dynamic>>> getRecentConditionChecks(String toiletId) {
    return _db
        .collection('toilets')
        .doc(toiletId)
        .collection('condition_checks')
        .orderBy('timestamp', descending: true)
        .limit(3)
        .snapshots()
        .map((snapshot) => snapshot.docs.map((doc) => doc.data()).toList());
  }

  // DETAIL screen's high-fidelity live condition read. Matches the AUTHORITATIVE
  // server derivation (functions/src/derive.ts): it reads the FULL
  // one-doc-per-account condition_checks collection for this one toilet (NO
  // limit — bounded by active accounts, acceptable at current usage scale) and applies
  // the 60-minute window locally.
  //
  //   - Distinct account per row (doc id == uid). Strict majority of non-
  //     'unknown' observations per dimension; tie / none -> 'unknown'. UNKNOWN
  //     abstains. A structurally malformed observation is dropped and does not
  //     count. `lock` is derived too, so client + server dimensions align.
  //   - `validUntilMs` = the EARLIEST (observationTime + 60min) among the
  //     counted observations — the same conservative expiry as Evidence V2, so
  //     the caller can drop to UNKNOWN once wall-clock passes it, with no
  //     Firestore write needed. `null` when nothing was counted.
  //   - No probabilistic "confidence".
  Stream<Map<String, dynamic>> getConditionSummary(String toiletId) {
    return _db
        .collection('toilets')
        .doc(toiletId)
        .collection('condition_checks')
        .orderBy('timestamp', descending: true)
        .snapshots()
        .map((snapshot) {
          final now = DateTime.now();
          const windowMs = 60 * 60 * 1000;
          int count = 0;
          DateTime? mostRecent;
          int? earliestExpiryMs;
          final tally = <String, Map<String, int>>{
            'open': {'yes': 0, 'no': 0, 'unknown': 0},
            'water': {'yes': 0, 'no': 0, 'unknown': 0},
            'usable': {'yes': 0, 'no': 0, 'unknown': 0},
            'lock': {'yes': 0, 'no': 0, 'unknown': 0},
          };

          bool strictTri(Object? v) =>
              v == 'yes' || v == 'no' || v == 'unknown';

          for (final doc in snapshot.docs) {
            final data = doc.data();
            final ts = data['timestamp'];
            if (ts is! Timestamp) continue;
            // Defensive: every required dimension must be an exact tri-state;
            // `lock` may be absent (=> 'unknown') but not a bad value.
            if (!strictTri(data['open']) ||
                !strictTri(data['water']) ||
                !strictTri(data['usable']) ||
                (data['lock'] != null && !strictTri(data['lock']))) {
              continue;
            }
            final date = ts.toDate();
            final ageMs =
                now.millisecondsSinceEpoch - date.millisecondsSinceEpoch;
            if (ageMs < 0 || ageMs > windowMs) continue;

            if (mostRecent == null || date.isAfter(mostRecent)) {
              mostRecent = date;
            }
            final expiry = date.millisecondsSinceEpoch + windowMs;
            if (earliestExpiryMs == null || expiry < earliestExpiryMs) {
              earliestExpiryMs = expiry;
            }
            count++;

            for (final dim in tally.keys) {
              final v = dim == 'lock' && data['lock'] == null
                  ? 'unknown'
                  : data[dim];
              if (v == 'yes') tally[dim]!['yes'] = tally[dim]!['yes']! + 1;
              if (v == 'no') tally[dim]!['no'] = tally[dim]!['no']! + 1;
              if (v == 'unknown') {
                tally[dim]!['unknown'] = tally[dim]!['unknown']! + 1;
              }
            }
          }

          String verdict(String dim) {
            final y = tally[dim]!['yes']!;
            final n = tally[dim]!['no']!;
            if (y > n) return 'yes';
            if (n > y) return 'no';
            return 'unknown';
          }

          Map<String, int> support(String dim) => {
            'yes': tally[dim]!['yes']!,
            'no': tally[dim]!['no']!,
            'unknown': tally[dim]!['unknown']!,
          };

          return {
            'open': verdict('open'),
            'water': verdict('water'),
            'usable': verdict('usable'),
            'lock': verdict('lock'),
            'support': {
              'open': support('open'),
              'water': support('water'),
              'usable': support('usable'),
              'lock': support('lock'),
            },
            'count': count,
            'minutesAgo': mostRecent != null
                ? now.difference(mostRecent).inMinutes
                : 0,
            'validUntilMs': earliestExpiryMs,
          };
        });
  }

  // Cast a community upvote or downvote, or remove the vote.
  //
  // TRUST MODEL (2026-09-02): the vote doc id IS the voter uid, so there is
  // structurally one logical vote per user per toilet. This writes ONLY the
  // user's own votes/{uid} doc. It does NOT write upvote_count / downvote_count
  // on the parent toilet — those are derived at read time by getVoteSummary().
  Future<void> voteToilet(
    String toiletId,
    String userId,
    bool? isUpvote,
  ) async {
    final voteRef = _db
        .collection('toilets')
        .doc(toiletId)
        .collection('votes')
        .doc(userId);
    if (isUpvote == null) {
      await voteRef.delete();
    } else {
      await voteRef.set({
        'is_upvote': isUpvote,
        'timestamp': FieldValue.serverTimestamp(),
      });
    }
  }

  // Read-time vote aggregate for the one-toilet DetailSheet. Un-forgeable:
  // one vote doc per account (doc id == uid), counted by Firestore.
  // `ok == false` means the count QUERY FAILED — the caller must show
  // "Unavailable", NOT a fabricated "0 votes".
  Future<({int up, int down, bool ok})> getVoteSummary(String toiletId) async {
    try {
      final col = _db.collection('toilets').doc(toiletId).collection('votes');
      final upAgg = await col.where('is_upvote', isEqualTo: true).count().get();
      final downAgg = await col
          .where('is_upvote', isEqualTo: false)
          .count()
          .get();
      return (up: upAgg.count ?? 0, down: downAgg.count ?? 0, ok: true);
    } catch (_) {
      return (up: 0, down: 0, ok: false);
    }
  }

  // Returns the user's current vote (true=upvote, false=downvote, null=no vote)
  Future<bool?> getUserVote(String toiletId, String userId) async {
    final doc = await _db
        .collection('toilets')
        .doc(toiletId)
        .collection('votes')
        .doc(userId)
        .get();
    if (!doc.exists) return null;
    return doc.data()?['is_upvote'] as bool?;
  }

  // Atomic daily streak update — runs inside a transaction to prevent race conditions.
  // Returns the new streak count (or the unchanged count if already updated today).
  Future<int> updateStreak(String userId) async {
    final userRef = _db.collection('users').doc(userId);
    int newStreak = 1;
    try {
      await _db.runTransaction((transaction) async {
        final snap = await transaction.get(userRef);
        if (!snap.exists) return;
        final data = snap.data() ?? {};
        final int current = (data['streak_count'] as num?)?.toInt() ?? 0;
        final Timestamp? lastTs = data['last_active_date'] as Timestamp?;
        final DateTime now = DateTime.now();
        final DateTime today = DateTime(now.year, now.month, now.day);
        if (lastTs != null) {
          final DateTime last = lastTs.toDate();
          final DateTime lastDay = DateTime(last.year, last.month, last.day);
          final int diff = today.difference(lastDay).inDays;
          if (diff == 0) {
            newStreak = current;
            return;
          }
          if (diff == 1) {
            newStreak = current + 1;
          }
          // diff > 1: streak broken, newStreak stays 1
        }
        transaction.update(userRef, {
          'streak_count': newStreak,
          'last_active_date': Timestamp.fromDate(today),
        });
      });
    } catch (e) {
      debugPrint('updateStreak error: $e');
    }
    return newStreak;
  }

  Future<int> getStreak(String userId) async {
    try {
      final snap = await _db.collection('users').doc(userId).get();
      final data = snap.data() ?? {};
      return (data['streak_count'] as num?)?.toInt() ?? 0;
    } catch (_) {
      return 0;
    }
  }

  // File (or correct) this account's report for a toilet.
  //
  // TRUST MODEL (2026-09-02 integrity pass):
  //   - The report DOCUMENT ID IS the author's uid: toilets/{t}/reports/{uid}.
  //     One report per account per toilet — a single account cannot spam a
  //     toilet with many report docs. `.set()` lets the owner correct their
  //     own report's reason (Option B).
  //   - No `reported_by` field: ownership is the doc id. Owner-read only.
  //   - `created_at` is always the server time (rules require == request.time).
  //   - Automatic community flagging is REMOVED — a client cannot touch the
  //     toilet's flagged/closed state. Reports are moderation records only;
  //     they do not feed current-condition authority.
  Future<void> reportToilet(
    String toiletId,
    String userId,
    String reason,
  ) async {
    await _db
        .collection('toilets')
        .doc(toiletId)
        .collection('reports')
        .doc(userId)
        .set({'reason': reason, 'created_at': FieldValue.serverTimestamp()});
  }

  Future<List<bool>> getLast7DaysActivity(String userId) async {
    try {
      final now = DateTime.now();
      final startOfToday = DateTime(now.year, now.month, now.day);
      final List<bool> activity = List.filled(7, false);

      final snap = await _db
          .collection('toilets')
          .where('added_by', isEqualTo: userId)
          .get();

      for (var doc in snap.docs) {
        final data = doc.data();
        if (data['created_at'] != null) {
          final DateTime createdAt = (data['created_at'] as Timestamp).toDate();
          final startOfCreated = DateTime(
            createdAt.year,
            createdAt.month,
            createdAt.day,
          );
          final difference = startOfToday.difference(startOfCreated).inDays;
          if (difference >= 0 && difference < 7) {
            activity[6 - difference] = true;
          }
        }
      }
      return activity;
    } catch (_) {
      return List.filled(7, false);
    }
  }
}
