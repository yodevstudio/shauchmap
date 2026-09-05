import '../time/instant.dart';
import '../truth/toilet_truth.dart';
import '../evidence/toilet_evidence.dart';

/// The DOMAIN READ MODEL for one toilet. Body is unchanged from the original
/// `lib/services/firestore_service.dart` `Toilet` class; the ONLY differences:
///   * the Firestore factory `Toilet.fromFirestore(DocumentSnapshot)` is
///     replaced by [Toilet.fromMap] `(String id, Map<String,dynamic> data)` —
///     each client's adapter supplies the id + a plain map with timestamps
///     already normalized to [Instant];
///   * the unused write helper `toMap()` is NOT carried here — Firestore write
///     serialization lives in the Android adapter.
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

  // Legacy compatibility fields, kept for round-tripping older Firestore
  // records that still carry them. Not read by GO or any decision logic
  // (see packages/shauchmap_core/lib/src/go/), and no current Android or
  // Instant UI surfaces a "Women Safe" filter, badge, or certification.
  // These carry zero current-condition authority.
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

  /// Truth V2: the explicit YES / NO / UNKNOWN view of this toilet's STATIC
  /// facility facts + provenance.
  final ToiletTruth truth;

  /// Evidence V2: the SERVER-DERIVED summary of community evidence
  /// (ratings / votes / recent condition). Missing / malformed =>
  /// `ToiletEvidence.unavailable` (NOT "zero").
  final ToiletEvidence evidence;

  /// Legacy compatibility only — see the field comments above. Not consumed
  /// by GO and not surfaced as a certification anywhere in the current UI.
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
    this.truth = const ToiletTruth.allUnknown(),
    this.evidence = ToiletEvidence.unavailable,
  });

  /// Build the domain read model from a plain map (id supplied separately).
  /// Field parsing is byte-identical to the original `fromFirestore`; only the
  /// input shape and the timestamp type ([Instant] instead of Firestore
  /// `Timestamp`) differ. The redundant `position.geopoint` read is dropped —
  /// the model stores flat `latitude`/`longitude` and never reads `position`.
  factory Toilet.fromMap(String id, Map<String, dynamic> data) {
    return Toilet(
      id: id,
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
      womenSafeUntil: (data['women_safe_until'] as Instant?)?.toDateTime(),
      flaggedRaw: data['is_flagged'] ?? false,
      flaggedUntil: (data['flagged_until'] as Instant?)?.toDateTime(),
      landmark: data['landmark'] ?? '',
      wardenName: data['warden_name'] as String?,
      addedBy: data['added_by'] ?? '',
      createdAt: (data['created_at'] as Instant?)?.toDateTime(),
      lastVerified: (data['last_verified'] as Instant?)?.toDateTime(),
      upvoteCount: (data['upvote_count'] as num?)?.toInt() ?? 0,
      downvoteCount: (data['downvote_count'] as num?)?.toInt() ?? 0,
      needsConfirm: data['needs_confirm'] ?? false,
      truth: ToiletTruth.fromFirestore(data, addedBy: data['added_by'] ?? ''),
      evidence: ToiletEvidence.fromFirestore(data['evidence_v2']),
    );
  }
}
