// ShauchMap Truth V2 — explicit, evidence-aware domain model.
//
// WHY THIS EXISTS
// ---------------
// The legacy `Toilet` fields cannot represent "we don't know", and the
// original OSM import (not part of this repo — see docs/data-sources.md)
// manufactured almost all of them:
//
//   is_open   : HARD-CODED `True` for every one of the 7,740 imports.
//   is_free   : `(osm tag fee == 'no') OR (osm tag charge is absent)`. The raw
//               `charge` value was DISCARDED, so `is_free == false` proves only
//               that *some* `charge` tag existed — NOT a positive monetary fee
//               (`charge=0` / `charge=free` also yield false). Fee is therefore
//               UNKNOWN for every legacy OSM row, in both directions.
//   has_water : `toilets:handwashing == yes` OR `water_point == yes`. `True`
//               only on an explicit source tag; `False`/absent tells us nothing.
//   has_soap  : HARD-CODED `False`.
//   has_lock  : HARD-CODED `False`.
//   is_wheelchair  : `wheelchair == yes` only ('no'/'limited'/absent all -> False).
//   has_baby_change: `diaper == yes` OR `changing_table == yes` only.
//   is_western / has_sanitary_disposal / needs_confirm : never written by the
//               base importer (the extended importer adds category +
//               needs_confirm for INFERRED petrol-pump / mall candidate rows).
//   category  : base importer HARD-CODES `'govt'` — this is NOT government
//               ownership. The extended importer classifies petrol/mall/other.
//   gender_type: extractor defaults `'unisex'` when the source has no gender
//               tag — this is NOT evidence of unisex access. Only explicit
//               `female` / `male` source tags are meaningful.
//
// This model turns those artefacts back into honest YES / NO / UNKNOWN across
// three dimensions — IDENTITY (context + gender access + record status),
// STATIC FACILITY ATTRIBUTES (fee + amenities), and provenance — and is the
// SINGLE interpretation the presentation layer consumes. Dynamic "open/usable
// right now" is NOT here; that stays in `condition_checks`.
//
// It is ADDITIVE: `Toilet.fromFirestore` still parses every legacy key exactly
// as before (HARD_RULES #1) and ALSO builds a `ToiletTruth`. No production
// document is migrated; legacy docs are adapted on read.

import '../time/instant.dart';

/// Tri-state for a facility attribute. `unknown` is a real, first-class value.
enum EvidenceState { present, absent, unknown }

/// Fee model for the facility. `unknown` is a real value.
enum FeeState { free, paid, unknown }

/// What kind of place this toilet is / sits in. `unknown` is a real value —
/// never "government".
enum FacilityContext {
  unknown,
  publicToilet,
  petrolStation,
  commercial,
  station,
  other,
}

/// Who the facility is for. `unknown` is a real value — never "unisex" by
/// default.
enum GenderAccess { unknown, unisex, men, women }

/// How much we can trust this record's identity.
enum IdentityStatus {
  /// A real OSM-mapped toilet node.
  sourceMapped,

  /// An INFERRED petrol-pump / mall row (`needs_confirm == true`) — a candidate,
  /// not a field-confirmed toilet.
  candidate,

  /// Added by a user (native `truth_v2` or the old wizard).
  communitySubmitted,

  /// Provenance could not be determined.
  unknown,
}

/// Where this toilet's facts came from.
enum ToiletSource {
  /// OpenStreetMap bulk import (`added_by` starts with `osm_`).
  osm,

  /// Written natively by a current Add-Toilet client as `truth_v2`.
  communitySubmission,

  /// Added by a user through the OLD wizard, before `truth_v2` existed.
  legacyCommunity,

  /// Provenance could not be determined.
  unknown,
}

// ---- enum -> string (native V2 serialisation) ----

String _evStr(EvidenceState e) => switch (e) {
      EvidenceState.present => 'present',
      EvidenceState.absent => 'absent',
      EvidenceState.unknown => 'unknown',
    };

String _feeStr(FeeState f) => switch (f) {
      FeeState.free => 'free',
      FeeState.paid => 'paid',
      FeeState.unknown => 'unknown',
    };

String _contextStr(FacilityContext c) => switch (c) {
      FacilityContext.unknown => 'unknown',
      FacilityContext.publicToilet => 'public_toilet',
      FacilityContext.petrolStation => 'petrol_station',
      FacilityContext.commercial => 'commercial',
      FacilityContext.station => 'station',
      FacilityContext.other => 'other',
    };

String _genderStr(GenderAccess g) => switch (g) {
      GenderAccess.unknown => 'unknown',
      GenderAccess.unisex => 'unisex',
      GenderAccess.men => 'men',
      GenderAccess.women => 'women',
    };

// ---- STRICT parsers (return null on ANY non-member — native V2 only) ----

EvidenceState? _evStrict(Object? v) => switch (v) {
      'present' => EvidenceState.present,
      'absent' => EvidenceState.absent,
      'unknown' => EvidenceState.unknown,
      _ => null,
    };

FeeState? _feeStrict(Object? v) => switch (v) {
      'free' => FeeState.free,
      'paid' => FeeState.paid,
      'unknown' => FeeState.unknown,
      _ => null,
    };

FacilityContext? _contextStrict(Object? v) => switch (v) {
      'unknown' => FacilityContext.unknown,
      'public_toilet' => FacilityContext.publicToilet,
      'petrol_station' => FacilityContext.petrolStation,
      'commercial' => FacilityContext.commercial,
      'station' => FacilityContext.station,
      'other' => FacilityContext.other,
      _ => null,
    };

GenderAccess? _genderStrict(Object? v) => switch (v) {
      'unknown' => GenderAccess.unknown,
      'unisex' => GenderAccess.unisex,
      'men' => GenderAccess.men,
      'women' => GenderAccess.women,
      _ => null,
    };

/// The seven static amenity attributes, each tri-state.
class ToiletAmenities {
  final EvidenceState water;
  final EvidenceState soap;
  final EvidenceState lock;
  final EvidenceState western;
  final EvidenceState wheelchair;
  final EvidenceState babyChange;
  final EvidenceState sanitaryDisposal;

  const ToiletAmenities({
    required this.water,
    required this.soap,
    required this.lock,
    required this.western,
    required this.wheelchair,
    required this.babyChange,
    required this.sanitaryDisposal,
  });

  static const ToiletAmenities allUnknown = ToiletAmenities(
    water: EvidenceState.unknown,
    soap: EvidenceState.unknown,
    lock: EvidenceState.unknown,
    western: EvidenceState.unknown,
    wheelchair: EvidenceState.unknown,
    babyChange: EvidenceState.unknown,
    sanitaryDisposal: EvidenceState.unknown,
  );

  /// Serialised amenity map for a native `truth_v2` write. UNKNOWN is written
  /// explicitly as `"unknown"` — omission never means unknown.
  Map<String, String> toV2Map() => {
        'water': _evStr(water),
        'soap': _evStr(soap),
        'lock': _evStr(lock),
        'western': _evStr(western),
        'wheelchair': _evStr(wheelchair),
        'baby_change': _evStr(babyChange),
        'sanitary_disposal': _evStr(sanitaryDisposal),
      };
}

/// The honest, evidence-aware view of one toilet: identity + static facility
/// facts + provenance. NO dynamic "open now" state.
class ToiletTruth {
  /// 2 = native `truth_v2`. 1 = adapted from legacy fields. 0 = fallback.
  final int schemaVersion;
  final ToiletSource source;

  /// When the facts were recorded, when actually known (native V2
  /// `recorded_at`, or a legacy community `created_at`). `null` for OSM imports.
  final DateTime? recordedAt;

  // ---- identity ----
  final FacilityContext context;
  final GenderAccess gender;
  final IdentityStatus identityStatus;

  // ---- static facility attributes ----
  final FeeState fee;
  final ToiletAmenities amenities;

  /// True only when a fully well-formed `truth_v2` block was parsed.
  final bool isNativeV2;

  /// This record is an inferred candidate, not a confirmed toilet.
  bool get isCandidate => identityStatus == IdentityStatus.candidate;

  const ToiletTruth({
    required this.schemaVersion,
    required this.source,
    required this.recordedAt,
    required this.context,
    required this.gender,
    required this.identityStatus,
    required this.fee,
    required this.amenities,
    required this.isNativeV2,
  });

  /// Safe fallback used as the `Toilet` constructor default (direct
  /// construction in tests / non-Firestore paths). Asserts nothing.
  const ToiletTruth.allUnknown()
      : schemaVersion = 0,
        source = ToiletSource.unknown,
        recordedAt = null,
        context = FacilityContext.unknown,
        gender = GenderAccess.unknown,
        identityStatus = IdentityStatus.unknown,
        fee = FeeState.unknown,
        amenities = ToiletAmenities.allUnknown,
        isNativeV2 = false;

  /// Build the truth view for a Firestore `toilets` document.
  ///
  /// Order: a FULLY VALID native `truth_v2` wins; otherwise the conservative
  /// legacy adapter runs, branching on provenance. Never throws — a malformed
  /// `truth_v2` is not partially trusted; it degrades to the legacy adapter.
  factory ToiletTruth.fromFirestore(
    Map<String, dynamic> data, {
    required String addedBy,
  }) {
    final native = _tryParseNativeV2(data['truth_v2']);
    if (native != null) return native;

    final DateTime? createdAt = (data['created_at'] as Instant?)?.toDateTime();

    if (addedBy.isEmpty) {
      return _legacyCommunityAdapter(
        data,
        createdAt,
        sourceOverride: ToiletSource.unknown,
      );
    }
    if (addedBy.startsWith('osm_')) {
      return _legacyOsmAdapter(data, createdAt);
    }
    return _legacyCommunityAdapter(data, createdAt);
  }

  // ------------------------------------------------------- native V2 (STRICT)
  //
  // Returns non-null ONLY when EVERY structural requirement holds: the exact
  // top-level key set, version == 2, a supported native source_type, a real
  // Timestamp recorded_at, a valid fee enum, valid context + gender enums, and
  // an amenities map with EXACTLY the seven keys each holding a valid enum.
  // Any deviation -> null -> the caller falls back conservatively.
  static const Set<String> _v2Keys = {
    'version',
    'source_type',
    'recorded_at',
    'fee',
    'context',
    'gender',
    'amenities',
  };
  static const Set<String> _amenityKeys = {
    'water',
    'soap',
    'lock',
    'western',
    'wheelchair',
    'baby_change',
    'sanitary_disposal',
  };

  static ToiletTruth? _tryParseNativeV2(Object? raw) {
    if (raw is! Map) return null;
    final Map<String, dynamic> m;
    try {
      m = Map<String, dynamic>.from(raw);
    } catch (_) {
      return null;
    }

    final keys = m.keys.map((k) => k.toString()).toSet();
    if (keys.length != _v2Keys.length || !keys.containsAll(_v2Keys))
      return null;

    if (m['version'] != 2) return null;
    if (m['source_type'] != 'community_submission') return null;
    if (m['recorded_at'] is! Instant) return null;

    final fee = _feeStrict(m['fee']);
    if (fee == null) return null;
    final context = _contextStrict(m['context']);
    if (context == null) return null;
    final gender = _genderStrict(m['gender']);
    if (gender == null) return null;

    final amRaw = m['amenities'];
    if (amRaw is! Map) return null;
    final Map<String, dynamic> am;
    try {
      am = Map<String, dynamic>.from(amRaw);
    } catch (_) {
      return null;
    }
    final amKeys = am.keys.map((k) => k.toString()).toSet();
    if (amKeys.length != _amenityKeys.length ||
        !amKeys.containsAll(_amenityKeys)) {
      return null;
    }
    final parsed = <String, EvidenceState>{};
    for (final k in _amenityKeys) {
      final e = _evStrict(am[k]);
      if (e == null) return null;
      parsed[k] = e;
    }

    return ToiletTruth(
      schemaVersion: 2,
      source: ToiletSource.communitySubmission,
      recordedAt: (m['recorded_at'] as Instant).toDateTime(),
      context: context,
      gender: gender,
      identityStatus: IdentityStatus.communitySubmitted,
      fee: fee,
      amenities: ToiletAmenities(
        water: parsed['water']!,
        soap: parsed['soap']!,
        lock: parsed['lock']!,
        western: parsed['western']!,
        wheelchair: parsed['wheelchair']!,
        babyChange: parsed['baby_change']!,
        sanitaryDisposal: parsed['sanitary_disposal']!,
      ),
      isNativeV2: true,
    );
  }

  // ------------------------------------------------------------ legacy: OSM
  static ToiletTruth _legacyOsmAdapter(
    Map<String, dynamic> data,
    DateTime? createdAt,
  ) {
    // The extended importer flags inferred petrol / mall rows with
    // needs_confirm == true (and even synthesises has_water for malls). If the
    // importer itself says "not verified", every positive signal is downgraded
    // to UNKNOWN and the record is a CANDIDATE.
    final bool inferred = data['needs_confirm'] == true;

    EvidenceState sourceListed(Object? v) => (!inferred && v == true)
        ? EvidenceState.present
        : EvidenceState.unknown;

    // FEE: `is_free == false` cannot be distinguished from `charge=0`/`charge=
    // free`; the raw value was discarded. Fee is UNKNOWN in BOTH directions.
    const FeeState fee = FeeState.unknown;

    // IDENTITY — context.
    final String cat = (data['category'] ?? '').toString();
    final FacilityContext context = inferred
        ? _extendedContext(cat)
        // Base importer HARD-CODES 'govt'; that is not evidence of anything.
        : FacilityContext.unknown;

    // IDENTITY — gender. The extractor writes 'female' / 'male' from explicit
    // OSM tags, and 'unisex' as the NO-TAG fallback (not evidence).
    final GenderAccess gender =
        switch ((data['gender_type'] ?? '').toString()) {
      'female' || 'women' => GenderAccess.women,
      'male' || 'men' => GenderAccess.men,
      _ => GenderAccess.unknown,
    };

    return ToiletTruth(
      schemaVersion: 1,
      source: ToiletSource.osm,
      recordedAt: createdAt, // usually null: the OSM importer writes no time
      context: context,
      gender: gender,
      identityStatus:
          inferred ? IdentityStatus.candidate : IdentityStatus.sourceMapped,
      fee: fee,
      amenities: ToiletAmenities(
        water: sourceListed(data['has_water']),
        soap: EvidenceState.unknown, // importer hard-codes false
        lock: EvidenceState.unknown, // importer hard-codes false
        western: EvidenceState.unknown, // importer never writes it
        wheelchair: sourceListed(data['is_wheelchair']),
        babyChange: sourceListed(data['has_baby_change']),
        sanitaryDisposal: EvidenceState.unknown, // importer never writes it
      ),
      isNativeV2: false,
    );
  }

  static FacilityContext _extendedContext(
    String category,
  ) =>
      switch (category) {
        'petrol' => FacilityContext.petrolStation,
        'mall' => FacilityContext.commercial,
        'station' => FacilityContext.station,
        'other' => FacilityContext.other,
        // 'govt' from the extended importer is still its non-evidential default.
        _ => FacilityContext.unknown,
      };

  // ------------------------------------------------ legacy: community wizard
  //
  // The OLD wizard injected defaults, so a stored value cannot be trusted where
  // the control DEFAULTED to a value:
  //   is_open / is_free            -> UNKNOWN.
  //   has_water / has_soap / has_lock -> UNKNOWN (historically defaulted ON).
  //   OFF-default amenity `true`   -> user-listed PRESENT; false -> UNKNOWN.
  //   category 'govt'              -> hidden default -> context UNKNOWN.
  //   category chip value          -> explicit user choice -> mapped context.
  //   gender 'unisex'              -> cannot be told from the default -> UNKNOWN.
  //   gender 'men' / 'women'       -> explicit user choice -> known.
  static ToiletTruth _legacyCommunityAdapter(
    Map<String, dynamic> data,
    DateTime? createdAt, {
    ToiletSource sourceOverride = ToiletSource.legacyCommunity,
  }) {
    EvidenceState offDefault(Object? v) =>
        v == true ? EvidenceState.present : EvidenceState.unknown;

    final FacilityContext context =
        switch ((data['category'] ?? '').toString()) {
      // The old "Public" chip wrote 'government' — a public-toilet CONTEXT, not
      // an ownership claim.
      'government' => FacilityContext.publicToilet,
      'fuel' => FacilityContext.petrolStation,
      'commercial' => FacilityContext.commercial,
      'station' => FacilityContext.station,
      'other' => FacilityContext.other,
      _ => FacilityContext.unknown, // 'govt' hidden default
    };

    final GenderAccess gender =
        switch ((data['gender_type'] ?? '').toString()) {
      'men' || 'male' => GenderAccess.men,
      'women' || 'female' => GenderAccess.women,
      _ => GenderAccess.unknown, // 'unisex' indistinguishable from default
    };

    return ToiletTruth(
      schemaVersion: 1,
      source: sourceOverride,
      recordedAt: createdAt,
      context: context,
      gender: gender,
      identityStatus: sourceOverride == ToiletSource.unknown
          ? IdentityStatus.unknown
          : IdentityStatus.communitySubmitted,
      fee: FeeState.unknown,
      amenities: ToiletAmenities(
        water: EvidenceState.unknown,
        soap: EvidenceState.unknown,
        lock: EvidenceState.unknown,
        western: offDefault(data['is_western']),
        wheelchair: offDefault(data['is_wheelchair']),
        babyChange: offDefault(data['has_baby_change']),
        sanitaryDisposal: offDefault(data['has_sanitary_disposal']),
      ),
      isNativeV2: false,
    );
  }

  // --------------------------------------------------- write V2 (PURE fields)
  /// The PURE, platform-free fields of a NEW community Add-Toilet `truth_v2`
  /// submission — EVERYTHING EXCEPT the `recorded_at` server timestamp.
  ///
  /// Firestore write serialization does NOT belong in the shared
  /// domain core, so the `FieldValue.serverTimestamp()` sentinel that the rules
  /// pin to `request.time` is added by the Android write adapter
  /// (`lib/adapters/toilet_write_adapter.dart` -> `truthV2SubmissionMap`), which
  /// spreads these fields and appends `'recorded_at': FieldValue.serverTimestamp()`.
  /// The resulting document is byte-identical to the legacy in-app
  /// `ToiletTruth.newSubmission(...)` output this replaced.
  static Map<String, dynamic> newSubmissionFields({
    required FeeState fee,
    required FacilityContext context,
    required GenderAccess gender,
    required ToiletAmenities amenities,
  }) {
    return {
      'version': 2,
      'source_type': 'community_submission',
      // 'recorded_at' is appended by the client's Firestore write adapter.
      'fee': _feeStr(fee),
      'context': _contextStr(context),
      'gender': _genderStr(gender),
      'amenities': amenities.toV2Map(),
    };
  }
}
