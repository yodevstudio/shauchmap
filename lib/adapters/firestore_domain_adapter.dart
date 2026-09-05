// ShauchMap Android <-> shauchmap_core adapter boundary.
//
// The shared domain core (`package:shauchmap_core`) is pure Dart and never sees
// a Firestore `Timestamp`, `DocumentSnapshot`, `GeoPoint`, or `FieldValue`.
// This file is the ONE place that converts between them.
//
//   READ  : Firestore document  ->  normalize every nested Timestamp to
//           `Instant`  ->  `Toilet.fromMap(id, data)`  (the core parser).
//   WRITE : the core's PURE `truth_v2` fields  ->  add the
//           `FieldValue.serverTimestamp()` sentinel  ->  Firestore write map.

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:geolocator/geolocator.dart' show Position;
import 'package:shauchmap_core/shauchmap_core.dart';

/// Recursively convert every Firestore [Timestamp] in [value] — at ANY nesting
/// depth (e.g. `truth_v2.recorded_at`, `evidence_v2.ratings.computed_at`,
/// `evidence_v2.condition.valid_until`, top-level `created_at` /
/// `last_verified` / `flagged_until` / `women_safe_until`) — into a core
/// [Instant]. Non-Timestamp values pass through unchanged, so a malformed field
/// (a String where a timestamp is expected) still reaches the strict parser
/// and is still rejected.
Object? normalizeFirestoreTimestamps(Object? value) {
  if (value is Timestamp) {
    return Instant.fromDateTime(value.toDate());
  }
  if (value is Map) {
    return value.map(
      (k, v) => MapEntry(k.toString(), normalizeFirestoreTimestamps(v)),
    );
  }
  if (value is List) {
    return value.map(normalizeFirestoreTimestamps).toList();
  }
  return value;
}

/// Build the shared-core [Toilet] domain read model from a Firestore document.
/// Replaces the legacy in-app `Toilet.fromFirestore(DocumentSnapshot)` factory.
Toilet toiletFromFirestore(DocumentSnapshot doc) {
  final raw = (doc.data() as Map<String, dynamic>?) ?? const {};
  final normalized = (normalizeFirestoreTimestamps(raw) as Map)
      .cast<String, dynamic>();
  return Toilet.fromMap(doc.id, normalized);
}

/// Build the `truth_v2` sub-map for a NEW community Add-Toilet submission.
///
/// Byte-identical to the legacy in-app `ToiletTruth.newSubmission(...)`: the pure
/// core fields (`newSubmissionFields`) plus the `recorded_at` server sentinel
/// the deployed rules pin to `request.time` via `serverTs('recorded_at')`.
Map<String, dynamic> truthV2SubmissionMap({
  required FeeState fee,
  required FacilityContext context,
  required GenderAccess gender,
  required ToiletAmenities amenities,
}) {
  return {
    ...ToiletTruth.newSubmissionFields(
      fee: fee,
      context: context,
      gender: gender,
      amenities: amenities,
    ),
    'recorded_at': FieldValue.serverTimestamp(),
  };
}

// ---------------------------------------------------------------------------
// Location adapter: geolocator `Position` -> shauchmap_core `GeoPos`.
// The GO core is platform-free; `main.dart` acquires a geolocator `Position`
// (also needed by the map/widget) and converts at the GO boundary.
extension GeolocatorPositionToGeoPos on Position {
  GeoPos get asGeoPos =>
      GeoPos(latitude: latitude, longitude: longitude, timestamp: timestamp);
}
