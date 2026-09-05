// Presentation Truth layer — ShauchMap.
//
// Turns the domain models into display-ready labels. Consumes:
//   * `Toilet.truth`    — STATIC identity + facility facts (Truth V2).
//   * `Toilet.evidence` — SERVER-DERIVED community evidence (Evidence V2):
//                         ratings / votes / recent condition. Used by
//                         Map / List / GO via `ToiletPresentation.fromEvidence`.
//   * an optional direct raw condition-summary map — the DETAIL screen's
//     high-fidelity source, via `ToiletPresentation.withCondition`.
//
//   Firestore document
//         -> ToiletTruth  +  ToiletEvidence
//         -> ToiletPresentation (this file: labels + tone)
//         -> Map / List / Detail / GO UI
//
//   * `Evidence.unknown` is first-class and must NEVER render as YES or NO.
//   * The imported `is_open` flag is IGNORED for live status.
//   * "server-derived", never "verified". Ratings / votes are opinion, not
//     operational condition.
//   * ABSENT (not indexed) is distinct from an indexed ZERO.
//   * A server-derived condition summary EXPIRES at `validUntil` — past that it
//     is UNKNOWN regardless of the stored yes/no.

import '../evidence/toilet_evidence.dart';
import '../truth/toilet_truth.dart';
import '../models/toilet.dart';

/// Tri-state for a presented live/derived fact. `unknown` is real.
enum Evidence { yes, no, unknown }

/// How an amenity should be shown.
enum AmenityEvidence {
  /// A source or submitter positively listed it. Show "Listed" — reported, NOT
  /// "available / verified right now".
  listed,

  /// A current Add-Toilet submitter explicitly marked it absent. Show
  /// "Not present" — submitted, not independently verified.
  notPresent,

  /// We do not know (covers missing, importer defaults, un-answered adds).
  unknown,
}

/// Where a presentation's condition verdict came from.
enum ConditionSource {
  /// No condition evidence at all.
  none,

  /// A live direct query of `condition_checks` (Detail screen).
  liveQuery,

  /// A live direct query that has passed its conservative `validUntil` —
  /// treated as UNKNOWN until a fresh snapshot recomputes it.
  liveQueryExpired,

  /// The server-derived `evidence_v2.condition` summary, still within its
  /// `validUntil` window.
  serverIndex,

  /// A server-derived summary that has passed `validUntil` — treated as UNKNOWN.
  serverIndexExpired,
}

AmenityEvidence _amenityFrom(EvidenceState e) => switch (e) {
      EvidenceState.present => AmenityEvidence.listed,
      EvidenceState.absent => AmenityEvidence.notPresent,
      EvidenceState.unknown => AmenityEvidence.unknown,
    };

Evidence _evFromCondition(ConditionState c) => switch (c) {
      ConditionState.yes => Evidence.yes,
      ConditionState.no => Evidence.no,
      ConditionState.unknown => Evidence.unknown,
    };

/// The honest, on-read view of one toilet for the current app.
class ToiletPresentation {
  ToiletPresentation._({
    required this.open,
    required this.openLabel,
    required this.usability,
    required this.usabilityLabel,
    required this.conditionSource,
    required this.conditionAgeMinutes,
    required this.conditionCheckCount,
    required this.fee,
    required this.feeLabel,
    required this.water,
    required this.soap,
    required this.lock,
    required this.western,
    required this.wheelchair,
    required this.babyChange,
    required this.sanitaryDisposal,
    required this.source,
    required this.isNativeV2,
    required this.context,
    required this.gender,
    required this.identityStatus,
    required this.contextLabel,
    required this.genderLabel,
    required this.isCandidate,
    required this.ratingsAvailable,
    required this.ratingsCount,
    required this.ratingsAverage,
    required this.votesAvailable,
    required this.votesUp,
    required this.votesDown,
  });

  // ---- live / derived status ----
  final Evidence open;
  final String openLabel;
  final Evidence usability;
  final String usabilityLabel;
  final ConditionSource conditionSource;

  /// Age of the newest counted condition observation, in minutes; null if none.
  final int? conditionAgeMinutes;

  /// How many distinct-account condition observations backed [open]/[usability].
  final int conditionCheckCount;

  // ---- static facility facts (from ToiletTruth) ----
  final FeeState fee;
  final String feeLabel;
  final AmenityEvidence water;
  final AmenityEvidence soap;
  final AmenityEvidence lock;
  final AmenityEvidence western;
  final AmenityEvidence wheelchair;
  final AmenityEvidence babyChange;
  final AmenityEvidence sanitaryDisposal;

  final ToiletSource source;
  final bool isNativeV2;

  // ---- identity ----
  final FacilityContext context;
  final GenderAccess gender;
  final IdentityStatus identityStatus;

  /// Neutral classification label. `FacilityContext.unknown` -> "Mapped toilet".
  final String contextLabel;

  /// Gender-access label, or null when unknown (omit it from the UI).
  final String? genderLabel;

  /// This record is an inferred candidate, not a confirmed toilet.
  final bool isCandidate;

  // ---- server-derived opinion (Evidence V2) ----
  /// False => the ratings index is not available. NOT "zero ratings".
  final bool ratingsAvailable;
  final int ratingsCount;
  final double? ratingsAverage;

  /// False => the votes index is not available. NOT "0/0".
  final bool votesAvailable;
  final int votesUp;
  final int votesDown;

  /// True when we have NOTHING recent to say about live status.
  bool get statusUnconfirmed => open == Evidence.unknown;

  /// Ratings line for Map / List rows.
  ///   null                       -> not indexed: show nothing
  ///   "No ratings yet"           -> indexed zero (a real fact)
  ///   "★ 4.2 · 7 ratings"        -> indexed non-zero
  String? get ratingsLabel {
    if (!ratingsAvailable) return null;
    if (ratingsCount == 0) return 'No ratings yet';
    final avg = ratingsAverage;
    final n = '$ratingsCount rating${ratingsCount == 1 ? '' : 's'}';
    return avg == null ? n : '★ ${avg.toStringAsFixed(1)} · $n';
  }

  /// "Condition checks 18 min ago" — factual evidence age, only when real.
  /// Never a broad "Verified" / "checked recently".
  String? get conditionRecencyLabel {
    final m = conditionAgeMinutes;
    if (m == null || conditionCheckCount == 0) return null;
    if (m < 1) return 'Condition checks just now';
    if (m < 60) return 'Condition checks $m min ago';
    final h = m ~/ 60;
    return 'Condition checks ${h}h ago';
  }

  // ------------------------------------------------------------------- labels
  static String _contextLabel(FacilityContext c) => switch (c) {
        FacilityContext.unknown => 'Mapped toilet',
        FacilityContext.publicToilet => 'Public toilet',
        FacilityContext.petrolStation => 'Petrol pump',
        FacilityContext.commercial => 'Mall / shop',
        FacilityContext.station => 'Station',
        FacilityContext.other => 'Other',
      };

  static String? _genderLabel(GenderAccess g) => switch (g) {
        GenderAccess.unknown => null,
        GenderAccess.unisex => 'Unisex',
        GenderAccess.men => 'Men only',
        GenderAccess.women => 'Women only',
      };

  static String _feeLabel(FeeState f) => switch (f) {
        FeeState.free => 'Free · community-listed',
        FeeState.paid => 'Paid · listed',
        FeeState.unknown => 'Fee unconfirmed',
      };

  static Evidence _usabilityOf(Evidence usableRaw, Evidence openEv) {
    if (usableRaw == Evidence.no || openEv == Evidence.no) return Evidence.no;
    if (usableRaw == Evidence.yes) return Evidence.yes;
    return Evidence.unknown;
  }

  // -------------------------------------------------------------- constructors
  //
  // All three constructors share the STATIC + IDENTITY + server-derived
  // RATINGS/VOTES view (from `t.truth` and `t.evidence`). They differ only in
  // where the CONDITION verdict comes from.

  /// Static + identity + server ratings/votes. Condition = UNKNOWN.
  /// Used where there is no per-toilet condition source (a fresh add, a card).
  factory ToiletPresentation.fromToilet(Toilet t) {
    return ToiletPresentation._condition(
      t,
      open: Evidence.unknown,
      usability: Evidence.unknown,
      conditionSource: ConditionSource.none,
      openLabel: 'Status unconfirmed',
      usabilityLabel: 'Usability unconfirmed',
      ageMinutes: null,
      checkCount: 0,
    );
  }

  /// DETAIL screen: overlay a live direct query of `condition_checks`
  /// (`FirestoreService.getConditionSummary` map: `open`/`usable`/`lock`
  /// 'yes'|'no'|'unknown', `count`, `minutesAgo`, `validUntilMs`). Highest
  /// fidelity for the ONE open toilet.
  ///
  /// PASSIVE EXPIRY: the direct query emits no new Firestore event merely
  /// because 60 minutes elapsed, so this refuses to surface the verdict once
  /// `now >= validUntil` (same conservative earliest-expiry rule as Evidence
  /// V2). Inject [now] for deterministic tests; the caller must schedule a
  /// one-shot rebuild at `validUntilMs`.
  factory ToiletPresentation.withCondition(
    Toilet t,
    Map<String, dynamic>? summary, {
    DateTime? now,
  }) {
    final DateTime at = now ?? DateTime.now();
    final int count = (summary?['count'] as int?) ?? 0;
    if (count == 0) return ToiletPresentation.fromToilet(t);

    final int? validUntilMs = summary?['validUntilMs'] as int?;
    if (validUntilMs != null && at.millisecondsSinceEpoch >= validUntilMs) {
      // Window has elapsed with no new observation — drop to UNKNOWN, but note
      // it WAS a live query that expired (distinct from "never had one").
      return ToiletPresentation._condition(
        t,
        open: Evidence.unknown,
        usability: Evidence.unknown,
        conditionSource: ConditionSource.liveQueryExpired,
        openLabel: 'Status unconfirmed',
        usabilityLabel: 'Usability unconfirmed',
        ageMinutes: (summary?['minutesAgo'] as int?),
        checkCount: count,
      );
    }

    Evidence tri(Object? v) => v == 'yes'
        ? Evidence.yes
        : (v == 'no' ? Evidence.no : Evidence.unknown);
    final openEv = tri(summary?['open']);
    final usableRaw = tri(summary?['usable']);
    final usability = _usabilityOf(usableRaw, openEv);

    return ToiletPresentation._condition(
      t,
      open: openEv,
      usability: usability,
      conditionSource: ConditionSource.liveQuery,
      openLabel: switch (openEv) {
        Evidence.yes => 'Open now',
        Evidence.no => 'Closed now',
        Evidence.unknown => 'Status unconfirmed',
      },
      usabilityLabel: switch (usability) {
        Evidence.yes => 'Usable right now',
        Evidence.no => 'Recent checks: unusable',
        Evidence.unknown => 'Usability unconfirmed',
      },
      ageMinutes: (summary?['minutesAgo'] as int?) ?? 0,
      checkCount: count,
    );
  }

  /// MAP / LIST / GO: use the server-derived `evidence_v2.condition` summary,
  /// but ONLY while it is still within its `validUntil`. Past that it is
  /// UNKNOWN (observations leaving the 60-min window can flip the majority with
  /// no write to re-trigger the function). Inject [now] for deterministic tests.
  factory ToiletPresentation.fromEvidence(Toilet t, {DateTime? now}) {
    final DateTime at = now ?? DateTime.now();
    final c = t.evidence.condition;

    if (!c.available) {
      return ToiletPresentation._condition(
        t,
        open: Evidence.unknown,
        usability: Evidence.unknown,
        conditionSource: ConditionSource.none,
        openLabel: 'Status unconfirmed',
        usabilityLabel: 'Usability unconfirmed',
        ageMinutes: null,
        checkCount: 0,
      );
    }
    if (!c.isCurrentlyValid(at)) {
      // Indexed, but expired — say so, do NOT surface the stale yes/no.
      return ToiletPresentation._condition(
        t,
        open: Evidence.unknown,
        usability: Evidence.unknown,
        conditionSource: ConditionSource.serverIndexExpired,
        openLabel: 'Status unconfirmed',
        usabilityLabel: 'Usability unconfirmed',
        ageMinutes: c.ageMinutes(at),
        checkCount: c.contributorCount,
      );
    }

    final openEv = _evFromCondition(c.open);
    final usableRaw = _evFromCondition(c.usable);
    final usability = _usabilityOf(usableRaw, openEv);
    return ToiletPresentation._condition(
      t,
      open: openEv,
      usability: usability,
      conditionSource: ConditionSource.serverIndex,
      openLabel: switch (openEv) {
        Evidence.yes => 'Recent checks: open',
        Evidence.no => 'Recent checks: closed',
        Evidence.unknown => 'Status unconfirmed',
      },
      usabilityLabel: switch (usability) {
        Evidence.yes => 'Recent checks: usable',
        Evidence.no => 'Recent checks: unusable',
        Evidence.unknown => 'Usability unconfirmed',
      },
      ageMinutes: c.ageMinutes(at),
      checkCount: c.contributorCount,
    );
  }

  /// Shared builder: STATIC + IDENTITY + server RATINGS/VOTES from the toilet,
  /// plus the caller-supplied CONDITION verdict.
  factory ToiletPresentation._condition(
    Toilet t, {
    required Evidence open,
    required Evidence usability,
    required ConditionSource conditionSource,
    required String openLabel,
    required String usabilityLabel,
    required int? ageMinutes,
    required int checkCount,
  }) {
    final tr = t.truth;
    final a = tr.amenities;
    final r = t.evidence.ratings;
    final v = t.evidence.votes;
    return ToiletPresentation._(
      open: open,
      openLabel: openLabel,
      usability: usability,
      usabilityLabel: usabilityLabel,
      conditionSource: conditionSource,
      conditionAgeMinutes: ageMinutes,
      conditionCheckCount: checkCount,
      fee: tr.fee,
      feeLabel: _feeLabel(tr.fee),
      water: _amenityFrom(a.water),
      soap: _amenityFrom(a.soap),
      lock: _amenityFrom(a.lock),
      western: _amenityFrom(a.western),
      wheelchair: _amenityFrom(a.wheelchair),
      babyChange: _amenityFrom(a.babyChange),
      sanitaryDisposal: _amenityFrom(a.sanitaryDisposal),
      source: tr.source,
      isNativeV2: tr.isNativeV2,
      context: tr.context,
      gender: tr.gender,
      identityStatus: tr.identityStatus,
      contextLabel: _contextLabel(tr.context),
      genderLabel: _genderLabel(tr.gender),
      isCandidate: tr.isCandidate,
      ratingsAvailable: r.available,
      ratingsCount: r.count,
      ratingsAverage: r.average,
      votesAvailable: v.available,
      votesUp: v.up,
      votesDown: v.down,
    );
  }
}
