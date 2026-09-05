// Field Audit — local data model (schema v2).
//
// Pure Dart. No Flutter, no Firestore. Enums serialize to EXACT wire strings
// (never `.name`), so CSV/JSON exports are stable regardless of Dart renames.
//
// TRI-STATE IS SACRED. Every observation defaults to unknown / not_checked and
// is NEVER silently coerced to yes/no.
//
// v2 splits the old ambiguous `usable_at_visit` into TWO independent derived
// concepts:
//   * `facility_usable_at_visit`      — was the physical facility we found usable?
//   * `mapped_option_usable_at_visit` — did this mapped ShauchMap record lead to
//                                       a usable facility at the mapped place?
// See `computeFacilityUsable()` / `computeMappedOptionUsable()` and
// docs/field-audit-method.md.

import 'dart:math';

import 'field_audit_config.dart';

// ---------------------------------------------------------------------------
// Enums + wire mapping
// ---------------------------------------------------------------------------

/// Whether this audit is anchored to a mapped ShauchMap document or is a fresh
/// physical discovery with no map record.
enum RecordContext { mappedRecord, unmappedDiscovery }

const Map<RecordContext, String> _recordContextWire = {
  RecordContext.mappedRecord: 'mapped_record',
  RecordContext.unmappedDiscovery: 'unmapped_discovery',
};

/// What the auditor found at the MAPPED coordinate. Only meaningful for
/// `RecordContext.mappedRecord`; forced to `notApplicable` for discoveries.
/// (`access_prevented` was removed in v2 — access prevention belongs in
/// `publicly_accessible_at_visit = no`, not in "what exists at this point".)
enum MappingOutcome {
  confirmedAtLocation,
  foundNearbyButMoved,
  couldNotLocate,
  duplicate,
  notAToilet,
  unknown,
  notApplicable,
}

const Map<MappingOutcome, String> _mappingOutcomeWire = {
  MappingOutcome.confirmedAtLocation: 'confirmed_at_location',
  MappingOutcome.foundNearbyButMoved: 'found_nearby_but_moved',
  MappingOutcome.couldNotLocate: 'could_not_locate',
  MappingOutcome.duplicate: 'duplicate',
  MappingOutcome.notAToilet: 'not_a_toilet',
  MappingOutcome.unknown: 'unknown',
  MappingOutcome.notApplicable: 'not_applicable',
};

/// yes / no / unknown — for "public access" observations where "unknown" is the
/// honest missing value.
enum YesNoUnknown { yes, no, unknown }

const Map<YesNoUnknown, String> _yesNoUnknownWire = {
  YesNoUnknown.yes: 'yes',
  YesNoUnknown.no: 'no',
  YesNoUnknown.unknown: 'unknown',
};

/// yes / no / not_checked — for functionality/accessibility/facility fields
/// where the honest missing value is "we did not check this".
enum YesNoNotChecked { yes, no, notChecked }

const Map<YesNoNotChecked, String> _yesNoNotCheckedWire = {
  YesNoNotChecked.yes: 'yes',
  YesNoNotChecked.no: 'no',
  YesNoNotChecked.notChecked: 'not_checked',
};

enum FeeKind { free, paid, unknown }

const Map<FeeKind, String> _feeKindWire = {
  FeeKind.free: 'free',
  FeeKind.paid: 'paid',
  FeeKind.unknown: 'unknown',
};

enum Cleanliness { acceptable, poor, notChecked }

const Map<Cleanliness, String> _cleanlinessWire = {
  Cleanliness.acceptable: 'acceptable',
  Cleanliness.poor: 'poor',
  Cleanliness.notChecked: 'not_checked',
};

/// Derived — was the physical facility usable? (`computeFacilityUsable`)
enum FourStateUsable { yes, no, indeterminate, notObserved }

const Map<FourStateUsable, String> _fourStateUsableWire = {
  FourStateUsable.yes: 'yes',
  FourStateUsable.no: 'no',
  FourStateUsable.indeterminate: 'indeterminate',
  FourStateUsable.notObserved: 'not_observed',
};

/// Derived — did the mapped record lead to a usable facility?
/// (`computeMappedOptionUsable`)
enum MappedOptionUsable { yes, no, indeterminate, notApplicable }

const Map<MappedOptionUsable, String> _mappedOptionUsableWire = {
  MappedOptionUsable.yes: 'yes',
  MappedOptionUsable.no: 'no',
  MappedOptionUsable.indeterminate: 'indeterminate',
  MappedOptionUsable.notApplicable: 'not_applicable',
};

enum AuditStatus { pending, inProgress, completed, revisit }

const Map<AuditStatus, String> _auditStatusWire = {
  AuditStatus.pending: 'pending',
  AuditStatus.inProgress: 'in_progress',
  AuditStatus.completed: 'completed',
  AuditStatus.revisit: 'revisit',
};

/// Evidence-grade GPS provenance. A last-known fix is NEVER labelled `current`.
enum GpsSource { current, lastKnown, unavailable }

const Map<GpsSource, String> _gpsSourceWire = {
  GpsSource.current: 'current',
  GpsSource.lastKnown: 'last_known',
  GpsSource.unavailable: 'unavailable',
};

enum SourceType { osmImport, community, other, unknown }

const Map<SourceType, String> _sourceTypeWire = {
  SourceType.osmImport: 'osm_import',
  SourceType.community: 'community',
  SourceType.other: 'other',
  SourceType.unknown: 'unknown',
};

T _fromWire<T>(Map<T, String> wire, Object? raw, T fallback) {
  if (raw is! String) return fallback;
  for (final e in wire.entries) {
    if (e.value == raw) return e.key;
  }
  return fallback;
}

// Public helpers used by the UI / export to render wire strings.
String recordContextWire(RecordContext v) => _recordContextWire[v]!;
String mappingOutcomeWire(MappingOutcome v) => _mappingOutcomeWire[v]!;
String yesNoUnknownWire(YesNoUnknown v) => _yesNoUnknownWire[v]!;
String yesNoNotCheckedWire(YesNoNotChecked v) => _yesNoNotCheckedWire[v]!;
String feeKindWire(FeeKind v) => _feeKindWire[v]!;
String cleanlinessWire(Cleanliness v) => _cleanlinessWire[v]!;
String fourStateUsableWire(FourStateUsable v) => _fourStateUsableWire[v]!;
String mappedOptionUsableWire(MappedOptionUsable v) =>
    _mappedOptionUsableWire[v]!;
String auditStatusWire(AuditStatus v) => _auditStatusWire[v]!;
String gpsSourceWire(GpsSource v) => _gpsSourceWire[v]!;
String sourceTypeWire(SourceType v) => _sourceTypeWire[v]!;

/// Classify a legacy `added_by` value into a coarse provenance bucket WITHOUT
/// retaining the raw identifier (no UID / email ever stored on an audit).
SourceType classifySourceType(String? addedBy) {
  final s = (addedBy ?? '').trim();
  if (s.isEmpty) return SourceType.unknown;
  if (s == 'osm_india_import_2026' ||
      s == 'osm_india_import_2026_extended' ||
      s == 'osm_import' ||
      s.startsWith('osm_')) {
    return SourceType.osmImport;
  }
  // Firebase Auth UIDs are 20+ opaque chars.
  if (s.length >= 20 && RegExp(r'^[A-Za-z0-9]+$').hasMatch(s)) {
    return SourceType.community;
  }
  return SourceType.other;
}

// ---------------------------------------------------------------------------
// Record
// ---------------------------------------------------------------------------

String newAuditId() {
  final ms = DateTime.now().millisecondsSinceEpoch;
  final r = Random().nextInt(0x7fffffff).toRadixString(36);
  return 'fa_${ms}_$r';
}

double? _toDouble(Object? v) =>
    v is num ? v.toDouble() : (v is String ? double.tryParse(v) : null);

int? _toInt(Object? v) => v is int
    ? v
    : (v is num ? v.toInt() : (v is String ? int.tryParse(v) : null));

DateTime? _toDate(Object? v) => v is String ? DateTime.tryParse(v) : null;

/// The outcome of one GPS acquisition attempt, fed to
/// [FieldAudit.applyGpsAttempt]. Keeps the form free of evidence-replacement
/// logic and makes that logic unit-testable.
class GpsAttempt {
  const GpsAttempt.current(
    this.lat,
    this.lng,
    this.accuracyMeters,
    this.positionTimestamp,
  ) : source = GpsSource.current,
      failed = false;

  const GpsAttempt.lastKnown(
    this.lat,
    this.lng,
    this.accuracyMeters,
    this.positionTimestamp,
  ) : source = GpsSource.lastKnown,
      failed = false;

  const GpsAttempt.failed()
    : source = GpsSource.unavailable,
      failed = true,
      lat = null,
      lng = null,
      accuracyMeters = null,
      positionTimestamp = null;

  final GpsSource source;
  final bool failed;
  final double? lat;
  final double? lng;
  final double? accuracyMeters;
  final DateTime? positionTimestamp;
}

class FieldAudit {
  FieldAudit({
    required this.auditId,
    required this.recordContext,
    required this.queuedAt,
    required this.lastSavedAt,
    this.auditSchemaVersion = FieldAuditConfig.schemaVersion,
    this.auditor = FieldAuditConfig.auditor,
    this.status = AuditStatus.pending,
    this.visitStartedAt,
    this.completedAt,
    // mapped-record reference (null for an unmapped discovery)
    this.toiletId,
    this.toiletName = '',
    this.mappedLat,
    this.mappedLng,
    this.mappedAddress,
    // normalised provenance (never a raw UID)
    this.sourceType = SourceType.unknown,
    this.sourceRef,
    Map<String, dynamic>? legacyReference,
    // captured location (evidence-grade)
    this.auditorObservedLat,
    this.auditorObservedLng,
    this.distanceFromMappedPointMeters,
    this.gpsSource = GpsSource.unavailable,
    this.gpsAccuracyMeters,
    this.gpsPositionTimestamp,
    this.gpsAgeSecondsAtCapture,
    // observations
    MappingOutcome mappingOutcome = MappingOutcome.unknown,
    this.openAtVisit = YesNoUnknown.unknown,
    this.publiclyAccessibleAtVisit = YesNoUnknown.unknown,
    this.water = YesNoNotChecked.notChecked,
    this.soap = YesNoNotChecked.notChecked,
    this.usableCubicle = YesNoNotChecked.notChecked,
    this.doorOrLatch = YesNoNotChecked.notChecked,
    this.lighting = YesNoNotChecked.notChecked,
    this.westernSeat = YesNoNotChecked.notChecked,
    this.wheelchairEntry = YesNoNotChecked.notChecked,
    this.accessibleToilet = YesNoNotChecked.notChecked,
    this.mensSection = YesNoNotChecked.notChecked,
    this.womensSection = YesNoNotChecked.notChecked,
    this.unisex = YesNoNotChecked.notChecked,
    this.fee = FeeKind.unknown,
    this.feeAmountInr,
    this.cleanliness = Cleanliness.notChecked,
    this.cleanlinessNote = '',
    this.notes = '',
    List<String>? photoFilenames,
    // sample metadata (populated by a later predefined-sampling task)
    this.samplePlanId,
    this.sampleStratum,
    this.sampleCluster,
    this.sampleSequence,
    this.selectionMethod,
  }) : legacyReference = _filterLegacy(legacyReference),
       photoFilenames = photoFilenames ?? <String>[],
       _mappingOutcome = recordContext == RecordContext.unmappedDiscovery
           ? MappingOutcome.notApplicable
           : mappingOutcome {
    if (fee != FeeKind.paid) feeAmountInr = null;
  }

  final String auditId;
  final String auditSchemaVersion;
  final String auditor;
  AuditStatus status;
  final RecordContext recordContext;

  /// When the record was created / added to the queue. NOT a visit time.
  final DateTime queuedAt;

  /// When the audit form was first genuinely opened for field observation.
  /// Set exactly once; never reset on reopening. Null until the first visit.
  DateTime? visitStartedAt;

  DateTime lastSavedAt;
  DateTime? completedAt;

  final String? toiletId;
  String toiletName;
  final double? mappedLat;
  final double? mappedLng;
  final String? mappedAddress;

  final SourceType sourceType;

  /// e.g. an OSM id. NEVER a community contributor UID.
  final String? sourceRef;

  /// Allowlisted legacy `toilets` fields, for comparison only. Never ground
  /// truth. No identity fields.
  final Map<String, dynamic> legacyReference;

  double? auditorObservedLat;
  double? auditorObservedLng;
  double? distanceFromMappedPointMeters;
  GpsSource gpsSource;
  double? gpsAccuracyMeters;
  DateTime? gpsPositionTimestamp;
  int? gpsAgeSecondsAtCapture;

  MappingOutcome _mappingOutcome;
  MappingOutcome get mappingOutcome => _mappingOutcome;
  set mappingOutcome(MappingOutcome v) {
    // A discovery can never carry a mapping outcome.
    _mappingOutcome = recordContext == RecordContext.unmappedDiscovery
        ? MappingOutcome.notApplicable
        : v;
  }

  YesNoUnknown openAtVisit;
  YesNoUnknown publiclyAccessibleAtVisit;
  YesNoNotChecked water;
  YesNoNotChecked soap;
  YesNoNotChecked usableCubicle;
  YesNoNotChecked doorOrLatch;
  YesNoNotChecked lighting;
  YesNoNotChecked westernSeat;
  YesNoNotChecked wheelchairEntry;
  YesNoNotChecked accessibleToilet;
  YesNoNotChecked mensSection;
  YesNoNotChecked womensSection;
  YesNoNotChecked unisex;
  FeeKind fee;
  double? feeAmountInr;
  Cleanliness cleanliness;
  String cleanlinessNote;
  String notes;

  final List<String> photoFilenames;

  String? samplePlanId;
  String? sampleStratum;
  String? sampleCluster;
  int? sampleSequence;
  String? selectionMethod;

  bool get hasPhotos => photoFilenames.isNotEmpty;

  /// Clear a stale fee amount when the fee is no longer "paid".
  void normaliseFee() {
    if (fee != FeeKind.paid) feeAmountInr = null;
  }

  // -----------------------------------------------------------------------
  // Derived: was a physical toilet actually inspected?
  // -----------------------------------------------------------------------
  bool get _anyFunctionalEvidence =>
      publiclyAccessibleAtVisit != YesNoUnknown.unknown ||
      openAtVisit != YesNoUnknown.unknown ||
      usableCubicle != YesNoNotChecked.notChecked ||
      water != YesNoNotChecked.notChecked;

  bool get physicalFacilityObserved {
    if (recordContext == RecordContext.unmappedDiscovery) return true;
    switch (mappingOutcome) {
      case MappingOutcome.couldNotLocate:
      case MappingOutcome.notAToilet:
      case MappingOutcome.notApplicable:
        return false;
      case MappingOutcome.confirmedAtLocation:
      case MappingOutcome.foundNearbyButMoved:
      case MappingOutcome.duplicate:
        return true;
      case MappingOutcome.unknown:
        // Outcome not stated yet — count it as observed only if the auditor
        // clearly recorded functional evidence about a physical toilet.
        return _anyFunctionalEvidence;
    }
  }

  // -----------------------------------------------------------------------
  // A. facility_usable_at_visit  — physical usability of the toilet we found.
  //    Independent of map reliability (beyond the "was a toilet observed" gate).
  //
  //    NOT_OBSERVED  no physical toilet was inspected
  //                  (could_not_locate / not_a_toilet, or unknown outcome with
  //                   no functional evidence).
  //    NO            a required condition is explicitly false:
  //                  publicly_accessible_at_visit == no
  //                  OR open_at_visit == no OR usable_cubicle == no OR water == no
  //    YES           all four required conditions explicitly satisfied.
  //    INDETERMINATE  toilet inspected but a required observation is
  //                   unknown / not_checked.
  //    (soap, cleanliness, wheelchair are NOT part of this.)
  // -----------------------------------------------------------------------
  FourStateUsable computeFacilityUsable() {
    if (!physicalFacilityObserved) return FourStateUsable.notObserved;
    if (publiclyAccessibleAtVisit == YesNoUnknown.no ||
        openAtVisit == YesNoUnknown.no ||
        usableCubicle == YesNoNotChecked.no ||
        water == YesNoNotChecked.no) {
      return FourStateUsable.no;
    }
    if (publiclyAccessibleAtVisit == YesNoUnknown.yes &&
        openAtVisit == YesNoUnknown.yes &&
        usableCubicle == YesNoNotChecked.yes &&
        water == YesNoNotChecked.yes) {
      return FourStateUsable.yes;
    }
    return FourStateUsable.indeterminate;
  }

  // -----------------------------------------------------------------------
  // B. mapped_option_usable_at_visit  — did THIS mapped record lead to a usable
  //    facility at the mapped place?
  //
  //    NOT_APPLICABLE  unmapped discovery.
  //    NO              not_a_toilet / could_not_locate, OR a physical facility
  //                    was found but facility_usable_at_visit == no.
  //    YES             mapping outcome == confirmed_at_location
  //                    AND facility_usable_at_visit == yes.
  //    INDETERMINATE   moved / duplicate / unknown outcome (no definitive
  //                    mapped-option answer), OR confirmed but insufficient
  //                    functionality evidence.
  // -----------------------------------------------------------------------
  MappedOptionUsable computeMappedOptionUsable() {
    if (recordContext == RecordContext.unmappedDiscovery) {
      return MappedOptionUsable.notApplicable;
    }
    final fac = computeFacilityUsable();
    switch (mappingOutcome) {
      case MappingOutcome.notApplicable:
        return MappedOptionUsable.notApplicable;
      case MappingOutcome.notAToilet:
      case MappingOutcome.couldNotLocate:
        return MappedOptionUsable.no;
      case MappingOutcome.confirmedAtLocation:
        if (fac == FourStateUsable.yes) return MappedOptionUsable.yes;
        if (fac == FourStateUsable.no) return MappedOptionUsable.no;
        return MappedOptionUsable.indeterminate;
      case MappingOutcome.foundNearbyButMoved:
      case MappingOutcome.duplicate:
      case MappingOutcome.unknown:
        if (fac == FourStateUsable.no) return MappedOptionUsable.no;
        return MappedOptionUsable.indeterminate;
    }
  }

  String facilityUsableReason() {
    final v = computeFacilityUsable();
    switch (v) {
      case FourStateUsable.notObserved:
        return 'NOT OBSERVED — no physical toilet was inspected '
            '(mapping outcome ${mappingOutcomeWire(mappingOutcome)}).';
      case FourStateUsable.no:
        final b = <String>[
          if (publiclyAccessibleAtVisit == YesNoUnknown.no)
            'publicly_accessible=no',
          if (openAtVisit == YesNoUnknown.no) 'open=no',
          if (usableCubicle == YesNoNotChecked.no) 'usable_cubicle=no',
          if (water == YesNoNotChecked.no) 'water=no',
        ];
        return 'NO — ${b.join(', ')}';
      case FourStateUsable.yes:
        return 'YES — publicly accessible, open, cubicle usable, water present';
      case FourStateUsable.indeterminate:
        final m = <String>[
          if (publiclyAccessibleAtVisit != YesNoUnknown.yes)
            'publicly_accessible=${yesNoUnknownWire(publiclyAccessibleAtVisit)}',
          if (openAtVisit != YesNoUnknown.yes)
            'open=${yesNoUnknownWire(openAtVisit)}',
          if (usableCubicle != YesNoNotChecked.yes)
            'usable_cubicle=${yesNoNotCheckedWire(usableCubicle)}',
          if (water != YesNoNotChecked.yes)
            'water=${yesNoNotCheckedWire(water)}',
        ];
        return 'INDETERMINATE — unresolved: ${m.join(', ')}';
    }
  }

  String mappedOptionReason() {
    final v = computeMappedOptionUsable();
    switch (v) {
      case MappedOptionUsable.notApplicable:
        return 'N/A — unmapped discovery (no mapped record to evaluate).';
      case MappedOptionUsable.no:
        return 'NO — mapping outcome ${mappingOutcomeWire(mappingOutcome)}'
            '${computeFacilityUsable() == FourStateUsable.no ? ' / facility not usable' : ''}.';
      case MappedOptionUsable.yes:
        return 'YES — confirmed at the mapped point and the facility was usable.';
      case MappedOptionUsable.indeterminate:
        return 'INDETERMINATE — mapping outcome '
            '${mappingOutcomeWire(mappingOutcome)} and/or functionality evidence '
            'is insufficient for a definitive mapped-option answer.';
    }
  }

  /// Unresolved items to surface in the pre-complete QA dialog . Photo is
  /// prompted separately.
  List<String> completionGaps() {
    final g = <String>[];
    if (recordContext == RecordContext.mappedRecord &&
        mappingOutcome == MappingOutcome.unknown) {
      g.add('Mapping outcome is still "unknown"');
    }
    if (recordContext == RecordContext.unmappedDiscovery &&
        toiletName.trim().isEmpty) {
      g.add('No name / descriptor for this unmapped facility');
    }
    if (physicalFacilityObserved) {
      if (publiclyAccessibleAtVisit == YesNoUnknown.unknown) {
        g.add('Public access unresolved');
      }
      if (openAtVisit == YesNoUnknown.unknown) g.add('Open/closed unresolved');
      if (water == YesNoNotChecked.notChecked) g.add('Water not checked');
      if (usableCubicle == YesNoNotChecked.notChecked) {
        g.add('Usable cubicle not checked');
      }
    }
    if (gpsSource == GpsSource.unavailable) g.add('GPS unavailable');
    return g;
  }

  void recomputeDistance() {
    if (mappedLat != null &&
        mappedLng != null &&
        auditorObservedLat != null &&
        auditorObservedLng != null) {
      distanceFromMappedPointMeters = _haversineMeters(
        mappedLat!,
        mappedLng!,
        auditorObservedLat!,
        auditorObservedLng!,
      );
    } else {
      distanceFromMappedPointMeters = null;
    }
  }

  // -----------------------------------------------------------------------
  // Edit-session lifecycle
  //
  // Call [beginEdit] on the FIRST real mutation of a record in an editing
  // session (chip / text / fee / photo / GPS replacement). Merely VIEWING a
  // record must not call it. Any completed / revisit record drops back to
  // in_progress and loses its completion stamp, so it must be re-completed
  // (passing completion QA) before it can re-enter the analysis dataset.
  // Returns true if this edit invalidated a previously COMPLETED record (so the
  // UI can warn once that it must be re-completed to re-enter the dataset).
  // -----------------------------------------------------------------------
  bool beginEdit() {
    final wasCompleted = status == AuditStatus.completed;
    if (status != AuditStatus.inProgress || completedAt != null) {
      status = AuditStatus.inProgress;
      completedAt = null;
    }
    return wasCompleted;
  }

  // -----------------------------------------------------------------------
  // GPS evidence — apply an acquisition attempt WITHOUT ever producing
  // contradictory evidence. Returns a short UI note (or null).
  //
  //  * a `current` fix always replaces whatever was recorded;
  //  * a `last_known` fix replaces only if there is no prior usable fix, or the
  //    prior fix is itself a last_known that is strictly OLDER than this one —
  //    it never replaces/relabels a `current` fix;
  //  * a FAILED attempt: if no prior usable fix exists, clear everything to
  //    `unavailable`; if a prior usable fix exists, keep it untouched.
  // Raw accuracy/age are preserved; no quality threshold is invented.
  // -----------------------------------------------------------------------
  String? applyGpsAttempt(GpsAttempt att, {DateTime? now}) {
    final n = now ?? DateTime.now();
    final hasPrior =
        auditorObservedLat != null &&
        auditorObservedLng != null &&
        gpsSource != GpsSource.unavailable;

    if (att.failed) {
      if (hasPrior) {
        return 'New GPS fix unavailable — previous recorded fix retained.';
      }
      auditorObservedLat = null;
      auditorObservedLng = null;
      gpsSource = GpsSource.unavailable;
      gpsAccuracyMeters = null;
      gpsPositionTimestamp = null;
      gpsAgeSecondsAtCapture = null;
      recomputeDistance();
      return 'No GPS fix available — coordinates not recorded.';
    }

    if (att.source == GpsSource.lastKnown && hasPrior) {
      if (gpsSource == GpsSource.current) {
        return 'Last-known fix ignored — a current fix is already recorded.';
      }
      final priorTs = gpsPositionTimestamp;
      final newTs = att.positionTimestamp;
      if (priorTs != null && (newTs == null || !newTs.isAfter(priorTs))) {
        return 'Last-known fix ignored — an equal/newer fix is already recorded.';
      }
    }

    auditorObservedLat = att.lat;
    auditorObservedLng = att.lng;
    gpsSource = att.source;
    gpsAccuracyMeters = att.accuracyMeters;
    gpsPositionTimestamp = att.positionTimestamp;
    gpsAgeSecondsAtCapture = att.positionTimestamp == null
        ? null
        : n.difference(att.positionTimestamp!).inSeconds.abs();
    recomputeDistance();
    return att.source == GpsSource.lastKnown
        ? 'Recorded a LAST-KNOWN fix (age ${gpsAgeSecondsAtCapture ?? "?"} s).'
        : null;
  }

  // -----------------------------------------------------------------------
  // Serialization
  // -----------------------------------------------------------------------

  Map<String, dynamic> toJson() {
    normaliseFee();
    return {
      'audit_id': auditId,
      'audit_schema_version': auditSchemaVersion,
      'auditor': auditor,
      'status': _auditStatusWire[status],
      'record_context': _recordContextWire[recordContext],
      'queued_at': queuedAt.toIso8601String(),
      'visit_started_at': visitStartedAt?.toIso8601String(),
      'last_saved_at': lastSavedAt.toIso8601String(),
      'completed_at': completedAt?.toIso8601String(),
      'toilet_id': toiletId,
      'toilet_name': toiletName,
      'mapped_lat': mappedLat,
      'mapped_lng': mappedLng,
      'mapped_address': mappedAddress,
      'source_type': _sourceTypeWire[sourceType],
      'source_ref': sourceRef,
      'legacy_reference': legacyReference,
      'auditor_observed_lat': auditorObservedLat,
      'auditor_observed_lng': auditorObservedLng,
      'distance_from_mapped_point_meters': distanceFromMappedPointMeters,
      'gps_source': _gpsSourceWire[gpsSource],
      'gps_accuracy_meters': gpsAccuracyMeters,
      'gps_position_timestamp': gpsPositionTimestamp?.toIso8601String(),
      'gps_age_seconds_at_capture': gpsAgeSecondsAtCapture,
      'mapping_outcome': _mappingOutcomeWire[mappingOutcome],
      'open_at_visit': _yesNoUnknownWire[openAtVisit],
      'publicly_accessible_at_visit':
          _yesNoUnknownWire[publiclyAccessibleAtVisit],
      'water': _yesNoNotCheckedWire[water],
      'soap': _yesNoNotCheckedWire[soap],
      'usable_cubicle': _yesNoNotCheckedWire[usableCubicle],
      'door_or_latch': _yesNoNotCheckedWire[doorOrLatch],
      'lighting': _yesNoNotCheckedWire[lighting],
      'western_seat': _yesNoNotCheckedWire[westernSeat],
      'wheelchair_entry': _yesNoNotCheckedWire[wheelchairEntry],
      'accessible_toilet': _yesNoNotCheckedWire[accessibleToilet],
      'mens_section': _yesNoNotCheckedWire[mensSection],
      'womens_section': _yesNoNotCheckedWire[womensSection],
      'unisex': _yesNoNotCheckedWire[unisex],
      'fee': _feeKindWire[fee],
      'fee_amount_inr': fee == FeeKind.paid ? feeAmountInr : null,
      'cleanliness': _cleanlinessWire[cleanliness],
      'cleanliness_note': cleanlinessNote,
      'notes': notes,
      'photo_filenames': photoFilenames,
      'sample_plan_id': samplePlanId,
      'sample_stratum': sampleStratum,
      'sample_cluster': sampleCluster,
      'sample_sequence': sampleSequence,
      'selection_method': selectionMethod,
      // derived — emitted for readers; recomputed on load, never trusted.
      'facility_usable_at_visit': _fourStateUsableWire[computeFacilityUsable()],
      'mapped_option_usable_at_visit':
          _mappedOptionUsableWire[computeMappedOptionUsable()],
    };
  }

  static FieldAudit fromJson(Map<String, dynamic> j) {
    final now = DateTime.now();
    final ctx = _fromWire<RecordContext>(
      _recordContextWire,
      j['record_context'],
      j['toilet_id'] == null
          ? RecordContext.unmappedDiscovery
          : RecordContext.mappedRecord,
    );
    return FieldAudit(
      auditId: (j['audit_id'] as String?) ?? newAuditId(),
      recordContext: ctx,
      auditSchemaVersion:
          (j['audit_schema_version'] as String?) ??
          FieldAuditConfig.schemaVersion,
      auditor: (j['auditor'] as String?) ?? FieldAuditConfig.auditor,
      status: _fromWire(_auditStatusWire, j['status'], AuditStatus.pending),
      queuedAt: _toDate(j['queued_at']) ?? _toDate(j['started_at']) ?? now,
      visitStartedAt: _toDate(j['visit_started_at']),
      lastSavedAt: _toDate(j['last_saved_at']) ?? now,
      completedAt: _toDate(j['completed_at']),
      toiletId: j['toilet_id'] as String?,
      toiletName: (j['toilet_name'] as String?) ?? '',
      mappedLat: _toDouble(j['mapped_lat']),
      mappedLng: _toDouble(j['mapped_lng']),
      mappedAddress: j['mapped_address'] as String?,
      sourceType: _fromWire(
        _sourceTypeWire,
        j['source_type'],
        SourceType.unknown,
      ),
      sourceRef: j['source_ref'] as String?,
      legacyReference: (j['legacy_reference'] as Map?)?.cast<String, dynamic>(),
      auditorObservedLat: _toDouble(j['auditor_observed_lat']),
      auditorObservedLng: _toDouble(j['auditor_observed_lng']),
      distanceFromMappedPointMeters: _toDouble(
        j['distance_from_mapped_point_meters'],
      ),
      gpsSource: _fromWire(
        _gpsSourceWire,
        j['gps_source'],
        GpsSource.unavailable,
      ),
      gpsAccuracyMeters: _toDouble(j['gps_accuracy_meters']),
      gpsPositionTimestamp: _toDate(j['gps_position_timestamp']),
      gpsAgeSecondsAtCapture: _toInt(j['gps_age_seconds_at_capture']),
      mappingOutcome: _fromWire(
        _mappingOutcomeWire,
        j['mapping_outcome'] ?? j['location_result'],
        MappingOutcome.unknown,
      ),
      openAtVisit: _fromWire(
        _yesNoUnknownWire,
        j['open_at_visit'],
        YesNoUnknown.unknown,
      ),
      publiclyAccessibleAtVisit: _fromWire(
        _yesNoUnknownWire,
        j['publicly_accessible_at_visit'],
        YesNoUnknown.unknown,
      ),
      water: _fromWire(
        _yesNoNotCheckedWire,
        j['water'],
        YesNoNotChecked.notChecked,
      ),
      soap: _fromWire(
        _yesNoNotCheckedWire,
        j['soap'],
        YesNoNotChecked.notChecked,
      ),
      usableCubicle: _fromWire(
        _yesNoNotCheckedWire,
        j['usable_cubicle'],
        YesNoNotChecked.notChecked,
      ),
      doorOrLatch: _fromWire(
        _yesNoNotCheckedWire,
        j['door_or_latch'],
        YesNoNotChecked.notChecked,
      ),
      lighting: _fromWire(
        _yesNoNotCheckedWire,
        j['lighting'],
        YesNoNotChecked.notChecked,
      ),
      westernSeat: _fromWire(
        _yesNoNotCheckedWire,
        j['western_seat'],
        YesNoNotChecked.notChecked,
      ),
      wheelchairEntry: _fromWire(
        _yesNoNotCheckedWire,
        j['wheelchair_entry'],
        YesNoNotChecked.notChecked,
      ),
      accessibleToilet: _fromWire(
        _yesNoNotCheckedWire,
        j['accessible_toilet'],
        YesNoNotChecked.notChecked,
      ),
      mensSection: _fromWire(
        _yesNoNotCheckedWire,
        j['mens_section'],
        YesNoNotChecked.notChecked,
      ),
      womensSection: _fromWire(
        _yesNoNotCheckedWire,
        j['womens_section'],
        YesNoNotChecked.notChecked,
      ),
      unisex: _fromWire(
        _yesNoNotCheckedWire,
        j['unisex'],
        YesNoNotChecked.notChecked,
      ),
      fee: _fromWire(_feeKindWire, j['fee'], FeeKind.unknown),
      feeAmountInr: _toDouble(j['fee_amount_inr']),
      cleanliness: _fromWire(
        _cleanlinessWire,
        j['cleanliness'],
        Cleanliness.notChecked,
      ),
      cleanlinessNote: (j['cleanliness_note'] as String?) ?? '',
      notes: (j['notes'] as String?) ?? '',
      photoFilenames:
          (j['photo_filenames'] as List?)?.whereType<String>().toList() ??
          <String>[],
      samplePlanId: j['sample_plan_id'] as String?,
      sampleStratum: j['sample_stratum'] as String?,
      sampleCluster: j['sample_cluster'] as String?,
      sampleSequence: _toInt(j['sample_sequence']),
      selectionMethod: j['selection_method'] as String?,
    );
  }
}

/// Keep only the allowlisted, non-identity legacy fields.
Map<String, dynamic> _filterLegacy(Map<String, dynamic>? raw) {
  final out = <String, dynamic>{};
  if (raw == null) return out;
  for (final k in FieldAuditConfig.legacyReferenceAllowlist) {
    if (raw.containsKey(k)) {
      final v = raw[k];
      if (v is num || v is bool || v is String) out[k] = v;
    }
  }
  return out;
}

/// Great-circle distance in metres. Local, no plugin — keeps the model
/// pure-Dart and unit-testable.
double _haversineMeters(double lat1, double lon1, double lat2, double lon2) {
  const earthR = 6371000.0;
  double rad(double d) => d * pi / 180.0;
  final dLat = rad(lat2 - lat1);
  final dLon = rad(lon2 - lon1);
  final a =
      sin(dLat / 2) * sin(dLat / 2) +
      cos(rad(lat1)) * cos(rad(lat2)) * sin(dLon / 2) * sin(dLon / 2);
  return earthR * 2 * atan2(sqrt(a), sqrt(1 - a));
}
