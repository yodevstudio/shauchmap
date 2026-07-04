import 'package:cloud_firestore/cloud_firestore.dart';
import 'dart:math' as math;
import 'package:flutter/foundation.dart';
import 'package:geoflutterfire_plus/geoflutterfire_plus.dart';

import 'notification_service.dart';

class Toilet {
  final String id;
  final String name;
  final String address;
  final double latitude;
  final double longitude;
  final String category;
  double starRating;
  int totalRatings;
  bool isOpen;
  bool isFree;
  String genderType; // men, women, unisex
  bool hasWater;
  bool hasSoap;
  bool hasLock;
  bool isWheelchair;
  bool hasBabyChange;
  bool hasSanitaryDisposal;
  bool isWestern;
  bool womenSafeFlag;
  final DateTime? womenSafeUntil;
  bool flaggedRaw;
  final DateTime? flaggedUntil;
  String landmark;
  String? wardenName;
  final String addedBy;
  final DateTime? createdAt;
  final DateTime? lastVerified;
  int upvoteCount;
  int downvoteCount;
  final bool needsConfirm;

  bool get isWomenSafe =>
      womenSafeFlag && (womenSafeUntil?.isAfter(DateTime.now()) == true);
  bool get isFlagged =>
      flaggedRaw && (flaggedUntil?.isAfter(DateTime.now()) == true);
  double get communityScore => upvoteCount == 0 && downvoteCount == 0
      ? 0.5
      : upvoteCount / (upvoteCount + downvoteCount).toDouble();

  Toilet({
    required this.id,
    required this.name,
    required this.address,
    required this.latitude,
    required this.longitude,
    required this.category,
    required this.starRating,
    required this.totalRatings,
    required this.isOpen,
    required this.isFree,
    required this.genderType,
    required this.hasWater,
    required this.hasSoap,
    required this.hasLock,
    required this.isWheelchair,
    required this.hasBabyChange,
    required this.hasSanitaryDisposal,
    required this.isWestern,
    required this.womenSafeFlag,
    this.womenSafeUntil,
    required this.flaggedRaw,
    this.flaggedUntil,
    this.landmark = '',
    this.wardenName,
    required this.addedBy,
    this.createdAt,
    this.lastVerified,
    this.upvoteCount = 0,
    this.downvoteCount = 0,
    this.needsConfirm = false,
  });

  factory Toilet.fromFirestore(DocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>? ?? {};
    return Toilet(
      id: doc.id,
      name: data['name'] ?? '',
      address: data['address'] ?? '',
      latitude: (data['latitude'] as num?)?.toDouble() ?? 0.0,
      longitude: (data['longitude'] as num?)?.toDouble() ?? 0.0,
      category: data['category'] ?? 'govt',
      starRating: (data['star_rating'] as num?)?.toDouble() ?? 0.0,
      totalRatings: (data['total_ratings'] as num?)?.toInt() ?? 0,
      isOpen: data['is_open'] ?? true,
      isFree: data['is_free'] ?? true,
      genderType: data['gender_type'] ?? 'unisex',
      hasWater: data['has_water'] ?? false,
      hasSoap: data['has_soap'] ?? false,
      hasLock: data['has_lock'] ?? false,
      isWheelchair: data['is_wheelchair'] ?? false,
      hasBabyChange: data['has_baby_change'] ?? false,
      hasSanitaryDisposal: data['has_sanitary_disposal'] ?? false,
      isWestern: data['is_western'] ?? false,
      womenSafeFlag: data['is_women_safe'] ?? false,
      womenSafeUntil: (data['women_safe_until'] as Timestamp?)?.toDate(),
      flaggedRaw: data['is_flagged'] ?? false,
      flaggedUntil: (data['flagged_until'] as Timestamp?)?.toDate(),
      landmark: data['landmark'] ?? '',
      wardenName: data['warden_name'] as String?,
      addedBy: data['added_by'] ?? '',
      createdAt: (data['created_at'] as Timestamp?)?.toDate(),
      lastVerified: (data['last_verified'] as Timestamp?)?.toDate(),
      upvoteCount: (data['upvote_count'] as num?)?.toInt() ?? 0,
      downvoteCount: (data['downvote_count'] as num?)?.toInt() ?? 0,
      needsConfirm: data['needs_confirm'] ?? false,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'name': name,
      'address': address,
      'latitude': latitude,
      'longitude': longitude,
      'category': category,
      'star_rating': starRating,
      'total_ratings': totalRatings,
      'is_open': isOpen,
      'is_free': isFree,
      'gender_type': genderType,
      'has_water': hasWater,
      'has_soap': hasSoap,
      'has_lock': hasLock,
      'is_wheelchair': isWheelchair,
      'has_baby_change': hasBabyChange,
      'has_sanitary_disposal': hasSanitaryDisposal,
      'landmark': landmark,
      'added_by': addedBy,
      'needs_confirm': needsConfirm,
      'created_at': createdAt != null
          ? Timestamp.fromDate(createdAt!)
          : FieldValue.serverTimestamp(),
    };
  }
}

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
              .map((doc) => Toilet.fromFirestore(doc))
              .where((t) => t.latitude != 0.0 && t.longitude != 0.0)
              .toList(),
        );
  }

  // Future list of toilets bounded by geo-hash and limited by count
  Future<List<Toilet>> getToilets({
    double? latitude,
    double? longitude,
    double radiusKm = 10.0,
    int limit = 50,
  }) async {
    if (latitude == null || longitude == null) {
      // Safety bound if no coordinates are provided
      final querySnapshot = await _db.collection('toilets').limit(limit).get();
      return querySnapshot.docs
          .map((doc) => Toilet.fromFirestore(doc))
          .toList();
    }

    final center = GeoFirePoint(GeoPoint(latitude, longitude));
    final collectionRef = _db.collection('toilets');

    final stream = GeoCollectionReference<Map<String, dynamic>>(collectionRef)
        .subscribeWithin(
          center: center,
          radiusInKm: radiusKm,
          field: 'position',
          geopointFrom: (data) => (data['position']['geopoint'] as GeoPoint),
          strictMode: true,
        )
        .map(
          (list) => list
              .map((doc) => Toilet.fromFirestore(doc))
              .where((t) => t.latitude != 0.0 && t.longitude != 0.0)
              .take(limit)
              .toList(),
        );

    return await stream.first;
  }

  // Add a new toilet — writes geopoint+geohash so geo queries can find it
  Future<void> addToilet(Map<String, dynamic> data) async {
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

  // Submit or update a rating atomically. Queries for an existing doc outside the
  // transaction (Firestore transactions do not support queries), then reads the same
  // ref inside the transaction for a consistent old-stars value.
  Future<void> addRating(
    String toiletId,
    Map<String, dynamic> ratingData,
  ) async {
    final String? userId = ratingData['user_id'];
    final toiletRef = _db.collection('toilets').doc(toiletId);
    final userRef = (userId != null && userId.isNotEmpty)
        ? _db.collection('users').doc(userId)
        : null;

    // Find existing rating doc before the transaction (queries can't run inside one)
    DocumentSnapshot? existingRatingSnap;
    if (userId != null && userId.isNotEmpty) {
      final query = await _db
          .collection('toilets')
          .doc(toiletId)
          .collection('ratings')
          .where('user_id', isEqualTo: userId)
          .limit(1)
          .get();
      if (query.docs.isNotEmpty) existingRatingSnap = query.docs.first;
    }
    final bool isUpdate = existingRatingSnap != null;
    final DocumentReference ratingRef =
        existingRatingSnap?.reference ?? toiletRef.collection('ratings').doc();

    await _db.runTransaction((transaction) async {
      // 1. Perform ALL Reads first
      final toiletSnap = await transaction.get(toiletRef);
      DocumentSnapshot? userSnap;
      if (userRef != null) userSnap = await transaction.get(userRef);
      final DocumentSnapshot? existingTxSnap = isUpdate
          ? await transaction.get(ratingRef)
          : null;

      int currentCount = 0;
      double currentRating = 0.0;
      if (toiletSnap.exists) {
        final data = toiletSnap.data() ?? {};
        currentCount = (data['total_ratings'] as num?)?.toInt() ?? 0;
        currentRating = (data['star_rating'] as num?)?.toDouble() ?? 0.0;
      }

      final double newStars = (ratingData['stars'] as num).toDouble();
      double newRating;
      int newCount;

      if (isUpdate && existingTxSnap != null && existingTxSnap.exists) {
        final oldData = existingTxSnap.data() as Map<String, dynamic>? ?? {};
        final double oldStars =
            (oldData['stars'] as num?)?.toDouble() ?? newStars;
        newCount = currentCount;
        newRating = currentCount > 0
            ? ((currentRating * currentCount) - oldStars + newStars) /
                  currentCount
            : newStars;
      } else {
        newCount = currentCount + 1;
        newRating = ((currentRating * currentCount) + newStars) / newCount;
      }

      int currentPoints = 0;
      if (!isUpdate && userSnap != null && userSnap.exists) {
        final userData = userSnap.data() as Map<String, dynamic>?;
        currentPoints = (userData?['scout_points'] as num?)?.toInt() ?? 0;
      }

      // 2. Perform ALL Writes after
      transaction.set(ratingRef, ratingData);
      transaction.update(toiletRef, {
        'star_rating': newRating,
        'total_ratings': newCount,
        'last_verified': FieldValue.serverTimestamp(),
      });
      if (!isUpdate && userRef != null && userSnap != null && userSnap.exists) {
        transaction.update(userRef, {
          'scout_points': currentPoints + 10,
          'ratings_given': FieldValue.increment(1),
        });
      }
    });

    if (!isUpdate && userId != null && userId.isNotEmpty) {
      await checkAndAwardBadges(userId);
    }
  }

  // Fetch the user's existing rating for a toilet (null if none)
  Future<Map<String, dynamic>?> getUserRating(
    String toiletId,
    String userId,
  ) async {
    final query = await _db
        .collection('toilets')
        .doc(toiletId)
        .collection('ratings')
        .where('user_id', isEqualTo: userId)
        .limit(1)
        .get();
    return query.docs.isEmpty ? null : query.docs.first.data();
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

  // Create/Update user doc safely
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

  // Increment points
  Future<void> addScoutPoints(String userId, int points) async {
    await _db.collection('users').doc(userId).update({
      'scout_points': FieldValue.increment(points),
    });
  }

  // Check in to a toilet
  Future<bool> checkIn(String toiletId, String userId) async {
    final recentCheckIns = await _db
        .collection('toilets')
        .doc(toiletId)
        .collection('check_ins')
        .where('user_id', isEqualTo: userId)
        .orderBy('timestamp', descending: true)
        .limit(1)
        .get();

    if (recentCheckIns.docs.isNotEmpty) {
      final ts = recentCheckIns.docs.first['timestamp'] as Timestamp?;
      if (ts != null) {
        final ageHours = DateTime.now().difference(ts.toDate()).inHours;
        if (ageHours < 4) return false;
      }
    }

    await _db.collection('toilets').doc(toiletId).collection('check_ins').add({
      'user_id': userId,
      'timestamp': FieldValue.serverTimestamp(),
    });

    await _db.collection('toilets').doc(toiletId).update({
      'last_verified': FieldValue.serverTimestamp(),
    });

    await addScoutPoints(userId, 20);
    await checkAndAwardBadges(userId);
    return true;
  }

  // Submit a hardware pulse quick check and award scout points
  Future<void> submitQuickCheck(
    String toiletId,
    String userId,
    String userName,
    bool hasWater,
    bool doorLocks,
    bool safeApproach,
    bool womenSafetyOk,
  ) async {
    await _db
        .collection('toilets')
        .doc(toiletId)
        .collection('quick_checks')
        .add({
          'user_id': userId,
          'has_water': hasWater,
          'door_locks': doorLocks,
          'safe_approach': safeApproach,
          'women_safety_ok': womenSafetyOk,
          'timestamp': FieldValue.serverTimestamp(),
        });
    await _db.collection('toilets').doc(toiletId).update({
      'last_verified': FieldValue.serverTimestamp(),
      'is_women_safe': womenSafetyOk,
      'women_safe_until': Timestamp.fromDate(
        DateTime.now().add(const Duration(hours: 24)),
      ),
    });
    await addScoutPoints(userId, 15);

    if (womenSafetyOk) {
      await _db.collection('users').doc(userId).set({
        'women_safe_verifies': FieldValue.increment(1),
      }, SetOptions(merge: true));
    }
    await checkAndAwardBadges(userId);

    // J1: Silently increment verify_count on the warden sub-document
    final wardenRef = _db
        .collection('users')
        .doc(userId)
        .collection('toilet_wardens')
        .doc(toiletId);
    await wardenRef.set({
      'verify_count': FieldValue.increment(1),
    }, SetOptions(merge: true));

    // J2: Promote to warden if threshold reached
    final wardenSnap = await wardenRef.get();
    final int verifyCount =
        (wardenSnap.data()?['verify_count'] as num?)?.toInt() ?? 0;
    if (verifyCount >= 5) {
      await wardenRef.set({'is_warden': true}, SetOptions(merge: true));
      await _db.collection('toilets').doc(toiletId).update({
        'warden_user_id': userId,
        'warden_name': userName,
      });
    }
  }

  // Stream of the 3 most recent quick checks for a toilet
  Stream<List<Map<String, dynamic>>> getRecentQuickChecks(String toiletId) {
    return _db
        .collection('toilets')
        .doc(toiletId)
        .collection('quick_checks')
        .orderBy('timestamp', descending: true)
        .limit(3)
        .snapshots()
        .map((snapshot) => snapshot.docs.map((doc) => doc.data()).toList());
  }

  // Stream live status computed from the last 10 quick checks (last 60 mins)
  Stream<Map<String, dynamic>> getLiveStatus(String toiletId) {
    return _db
        .collection('toilets')
        .doc(toiletId)
        .collection('quick_checks')
        .orderBy('timestamp', descending: true)
        .limit(10)
        .snapshots()
        .map((snapshot) {
          int waterVotes = 0, lockVotes = 0, safeVotes = 0, count = 0;
          double confidence = 0.0;
          DateTime? mostRecent;

          final now = DateTime.now();

          for (var doc in snapshot.docs) {
            final data = doc.data();
            final ts = data['timestamp'] as Timestamp?;
            if (ts == null) continue;
            final date = ts.toDate();
            final ageMinutes = now.difference(date).inMinutes;

            if (ageMinutes <= 60) {
              if (mostRecent == null || date.isAfter(mostRecent)) {
                mostRecent = date;
              }

              count++;
              confidence += math.exp(-ageMinutes / 30.0);

              if (data['has_water'] == true) waterVotes++;
              if (data['door_locks'] == true) lockVotes++;
              if (data['safe_approach'] == true) safeVotes++;
            }
          }

          return {
            'water': waterVotes > count / 2,
            'lock': lockVotes > count / 2,
            'safe': safeVotes > count / 2,
            'count': count,
            'minutesAgo': mostRecent != null
                ? now.difference(mostRecent).inMinutes
                : 0,
            'confidence': confidence,
          };
        });
  }

  // Count reports filed in the last 7 days for a toilet
  Future<int> getRecentReportCount(String toiletId) async {
    final cutoff = Timestamp.fromDate(
      DateTime.now().subtract(const Duration(days: 7)),
    );
    final query = await _db
        .collection('toilets')
        .doc(toiletId)
        .collection('reports')
        .where('created_at', isGreaterThan: cutoff)
        .get();
    return query.docs.length;
  }

  // Flag a toilet if 3+ reports were filed in the last 48 hours
  Future<void> checkAndFlagToilet(String toiletId) async {
    final cutoff48h = Timestamp.fromDate(
      DateTime.now().subtract(const Duration(hours: 48)),
    );
    final query = await _db
        .collection('toilets')
        .doc(toiletId)
        .collection('reports')
        .where('created_at', isGreaterThan: cutoff48h)
        .get();
    if (query.docs.length >= 3) {
      await _db.collection('toilets').doc(toiletId).update({
        'is_flagged': true,
        'flagged_reason': 'Multiple reports from community',
        'flagged_until': Timestamp.fromDate(
          DateTime.now().add(const Duration(days: 7)),
        ),
      });
    }
  }

  // Cast a community upvote or downvote, or remove vote.
  Future<void> voteToilet(
    String toiletId,
    String userId,
    bool? isUpvote,
  ) async {
    final toiletRef = _db.collection('toilets').doc(toiletId);
    final voteRef = toiletRef.collection('votes').doc(userId);
    final voteSnap = await voteRef.get();
    final Map<String, dynamic> toiletUpdate = {};

    if (voteSnap.exists) {
      final data = voteSnap.data() ?? {};
      final bool prevIsUpvote = data['is_upvote'] as bool? ?? true;
      if (isUpvote == null) {
        toiletUpdate[prevIsUpvote ? 'upvote_count' : 'downvote_count'] =
            FieldValue.increment(-1);
        await voteRef.delete();
      } else if (prevIsUpvote != isUpvote) {
        toiletUpdate[prevIsUpvote ? 'upvote_count' : 'downvote_count'] =
            FieldValue.increment(-1);
        toiletUpdate[isUpvote ? 'upvote_count' : 'downvote_count'] =
            FieldValue.increment(1);
        await voteRef.set({
          'is_upvote': isUpvote,
          'timestamp': FieldValue.serverTimestamp(),
        });
      }
    } else if (isUpvote != null) {
      toiletUpdate[isUpvote ? 'upvote_count' : 'downvote_count'] =
          FieldValue.increment(1);
      await voteRef.set({
        'is_upvote': isUpvote,
        'timestamp': FieldValue.serverTimestamp(),
      });
    }

    if (toiletUpdate.isNotEmpty) {
      await toiletRef.update(toiletUpdate);
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

  // Report a toilet, then check whether it should be auto-flagged.
  // checkAndFlagToilet is best-effort — its failure must not surface as a report failure.
  Future<void> reportToilet(
    String toiletId,
    String userId,
    String reason,
  ) async {
    await _db.collection('toilets').doc(toiletId).collection('reports').add({
      'reason': reason,
      'reported_by': userId,
      'created_at': FieldValue.serverTimestamp(),
    });
    try {
      await checkAndFlagToilet(toiletId);
    } catch (_) {
      // Auto-flagging is best-effort; report was already written successfully.
    }
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
