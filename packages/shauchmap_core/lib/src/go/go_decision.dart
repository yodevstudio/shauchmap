// ShauchMap GO V2 — PURE, deterministic, explainable recommendation engine.
//
// "Which nearby toilet is the best option to try RIGHT NOW?"
//
// PURE: no Firebase, no BuildContext, no Navigator, no Maps, no network, no
// setState. Inputs are domain models + a straight-line distance + `now`.
//
// WHAT GO DOES NOT KNOW / NEVER USES for a decision:
//   * ratings.average / ratings.count / votes.up / votes.down  (opinion, not
//     operational reliability)
//   * fee / water-listed / soap / lock-listed / western / wheelchair / baby
//     change  (static attributes; future per-user preferences, not generic
//     ranking weights)
//   * actual walking-route time (GO ranks by map/straight-line distance; this
//     is a known product limitation — see docs/truth-evidence-go.md)
//
// It is NOT a weighted score. It is a lexicographic decision tree over three
// variables: IDENTITY authority, DISTANCE (with a transparent detour guard),
// and CURRENT operational CONDITION evidence (from Evidence V2 `support`
// counts, only while the summary is valid).
//
// This is the shared GO decision engine consumed by Android and ShauchMap
// Instant.

import '../evidence/toilet_evidence.dart';
import '../truth/toilet_truth.dart';
import '../models/toilet.dart';

// ---------------------------------------------------------------- constants
//
// PROVISIONAL PRODUCT HEURISTICS — pending empirical calibration against the
// Jodhpur field audit / user tests. NOT scientifically validated. NOT a
// reliability metric and must never be displayed as one.
const double kMaxEvidenceDetourMeters = 400.0;
const double kMaxEvidenceDetourRatio = 1.5;

/// A farther, evidence-supported toilet may replace a nearer baseline ONLY when
/// BOTH provisional guards hold. FAILS CLOSED for structurally invalid input:
/// a non-finite or negative baseline/farther, or `farther < baseline`, returns
/// false before the caps are even considered.
bool withinEvidenceDetour(double baselineMeters, double fartherMeters) {
  if (!baselineMeters.isFinite || !fartherMeters.isFinite) return false;
  if (baselineMeters < 0 || fartherMeters < 0) return false;
  if (fartherMeters < baselineMeters) return false;
  return (fartherMeters - baselineMeters) <= kMaxEvidenceDetourMeters &&
      fartherMeters <= baselineMeters * kMaxEvidenceDetourRatio;
}

/// A GO domain distance is valid only when finite AND >= 0. `0` is valid.
bool _validDistance(double d) => d.isFinite && d >= 0;

// ---------------------------------------------------------------- evidence strength
//
// For ONE dimension whose support counts are {yes, no, unknown}. UNKNOWN
// observations never strengthen a yes/no claim.
enum EvidenceStrength {
  /// yes == 0 && no == 0 && unknown == 0
  none,

  /// yes == 0 && no == 0 && unknown > 0
  unknownOnly,

  /// yes == no && yes > 0
  tied,

  /// winning side == 1 && opposing side == 0  (e.g. 1 yes + 3 unknown)
  singleClear,

  /// winning side >= 2 && opposing side == 0
  corroboratedClear,

  /// winning side > opposing side && opposing side >= 1  (e.g. 2 yes + 1 no)
  conflictedMajority,
}

EvidenceStrength classifyEvidenceStrength(EvidenceSupport s) {
  final int win = s.yes > s.no ? s.yes : s.no;
  final int lose = s.yes > s.no ? s.no : s.yes;
  if (s.yes == 0 && s.no == 0) {
    return s.unknown > 0 ? EvidenceStrength.unknownOnly : EvidenceStrength.none;
  }
  if (s.yes == s.no) return EvidenceStrength.tied;
  if (lose == 0) {
    return win >= 2
        ? EvidenceStrength.corroboratedClear
        : EvidenceStrength.singleClear;
  }
  return EvidenceStrength.conflictedMajority;
}

// ---------------------------------------------------------------- operational condition
//
// GO-level classification of what the RECENT condition evidence says about
// whether this toilet is worth trying now. Derived ONLY from `open` + `usable`
// (water / lock are explanatory cautions, not GO constraints).
enum OperationalCondition {
  corroboratedUsable,
  singleReportedUsable,
  conflictedUsableMajority,

  /// No usable/valid signal, or evidence expired / unavailable / zero
  /// contributors. All of these rank identically (no authority).
  unknown,

  singleReportedUnavailable,
  conflictedUnavailableMajority,
  corroboratedUnavailable,
}

extension OperationalConditionX on OperationalCondition {
  bool get isPositive =>
      this == OperationalCondition.corroboratedUsable ||
      this == OperationalCondition.singleReportedUsable ||
      this == OperationalCondition.conflictedUsableMajority;

  bool get isNegative =>
      this == OperationalCondition.singleReportedUnavailable ||
      this == OperationalCondition.conflictedUnavailableMajority ||
      this == OperationalCondition.corroboratedUnavailable;
}

/// Classify the operational condition from a toilet's server-derived condition
/// evidence at `now`. Expired / unavailable / zero-contributor => `unknown`.
OperationalCondition classifyCondition(ConditionEvidence c, DateTime now) {
  if (!c.isCurrentlyValid(now)) return OperationalCondition.unknown;

  final openStr = classifyEvidenceStrength(c.supportOpen);
  final usableStr = classifyEvidenceStrength(c.supportUsable);

  // ---- NEGATIVE first, and CONSERVATIVE on contradiction. ----
  // A toilet is operationally negative if `usable == no` OR `open == no`.
  final bool openNo = c.open == ConditionState.no;
  final bool usableNo = c.usable == ConditionState.no;
  if (openNo || usableNo) {
    // Use the STRONGEST negative signal among the dimensions that say "no".
    EvidenceStrength worst = EvidenceStrength.none;
    int rank(EvidenceStrength s) => switch (s) {
          EvidenceStrength.corroboratedClear => 3,
          EvidenceStrength.conflictedMajority => 2,
          EvidenceStrength.singleClear => 1,
          _ => 0,
        };
    if (openNo && rank(openStr) > rank(worst)) worst = openStr;
    if (usableNo && rank(usableStr) > rank(worst)) worst = usableStr;
    return switch (worst) {
      EvidenceStrength.corroboratedClear =>
        OperationalCondition.corroboratedUnavailable,
      EvidenceStrength.conflictedMajority =>
        OperationalCondition.conflictedUnavailableMajority,
      _ => OperationalCondition.singleReportedUnavailable,
    };
  }

  // ---- POSITIVE: usable == yes AND open != no (already true here). ----
  // `open == yes && usable == unknown` is NOT a usability confirmation.
  if (c.usable == ConditionState.yes) {
    return switch (usableStr) {
      EvidenceStrength.corroboratedClear =>
        OperationalCondition.corroboratedUsable,
      EvidenceStrength.conflictedMajority =>
        OperationalCondition.conflictedUsableMajority,
      _ => OperationalCondition.singleReportedUsable,
    };
  }

  return OperationalCondition.unknown;
}

// ---------------------------------------------------------------- identity authority
enum RecommendationAuthority {
  /// A real source-mapped toilet — "mapped from a source", NOT "government
  /// verified" or "currently confirmed". Normal primary pool.
  sourceMappedPrimary,

  /// A community submission WITH corroborated-clear recent usable evidence.
  /// Normal primary pool (this is recommendation eligibility only — it never
  /// mutates the stored identity).
  communityCorroborated,

  /// A community submission without corroboration. Fallback tier 1.
  communityFallback,

  /// `needs_confirm` inferred candidate. Fallback tier 2, always
  /// requiresConfirmation. Evidence NEVER promotes it out of this tier.
  candidateFallback,

  /// Provenance unknown. Same or stricter than candidate. Fallback tier 2.
  unknownFallback,

  /// Explicit moderation flag. Excluded from automatic recommendation.
  flaggedExcluded,
}

/// PURE moderation-flag check, evaluated against the caller-supplied [now]
/// instead of the wall clock. Semantics match `Toilet.isFlagged` EXACTLY —
/// active iff `flaggedRaw == true` AND `flaggedUntil != null` AND
/// `flaggedUntil.isAfter(now)`. `flaggedUntil == now` and a null `flaggedUntil`
/// are BOTH "not active". GO must not call the convenience getter, which reads
/// `DateTime.now()` and would break `same pool + same now => same result`.
bool isModerationFlaggedAt(Toilet t, DateTime now) =>
    t.flaggedRaw && (t.flaggedUntil?.isAfter(now) ?? false);

RecommendationAuthority recommendationAuthority(
  Toilet t,
  OperationalCondition cond, {
  required DateTime now,
}) {
  if (isModerationFlaggedAt(t, now)) {
    return RecommendationAuthority.flaggedExcluded;
  }
  switch (t.truth.identityStatus) {
    case IdentityStatus.sourceMapped:
      return RecommendationAuthority.sourceMappedPrimary;
    case IdentityStatus.communitySubmitted:
      return cond == OperationalCondition.corroboratedUsable
          ? RecommendationAuthority.communityCorroborated
          : RecommendationAuthority.communityFallback;
    case IdentityStatus.candidate:
      return RecommendationAuthority.candidateFallback;
    case IdentityStatus.unknown:
      return RecommendationAuthority.unknownFallback;
  }
}

bool _isPrimary(RecommendationAuthority a) =>
    a == RecommendationAuthority.sourceMappedPrimary ||
    a == RecommendationAuthority.communityCorroborated;

// ---------------------------------------------------------------- result model
enum GoReason {
  noToilets,

  /// Chose the nearest eligible toilet; no evidence strong enough to detour.
  nearestWithNoStrongEvidence,

  /// A toilet with corroborated-clear recent usable evidence won, within both
  /// transparent detour guards (0-detour when it is itself the baseline).
  recentCorroboratedUsableWithinDetour,

  /// The nearest primary toilet was corroborated-unavailable; a nearby
  /// alternative within the detour guards was chosen instead. The SELECTED
  /// replacement's own condition cautions still apply (see `cautions`).
  avoidedRecentCorroboratedUnavailable,

  /// Selected the nearest eligible toilet, which carries a SINGLE recent
  /// "unavailable" condition check — kept eligible by distance, flagged as a
  /// caution.
  singleNegativeWarning,

  /// Selected the nearest eligible toilet, which carries a CONFLICTED negative
  /// majority — a caution, not a clear veto.
  conflictedNegativeWarning,

  /// The best mapped option is itself corroborated-unavailable and no
  /// reasonable alternative exists. requiresConfirmation.
  bestMappedOptionCorroboratedUnavailable,

  /// No primary-pool toilet exists; returned the nearest uncorroborated
  /// community submission. requiresConfirmation.
  communitySubmissionFallback,

  /// Only candidate / unknown-identity toilets exist. requiresConfirmation.
  candidateFallback,

  /// Every remaining option is moderation-flagged — no confident
  /// recommendation.
  onlyFlaggedOrUnconfirmedOptions,
}

enum GoCaution {
  singleReportUnavailable,
  conflictedUnavailable,
  corroboratedUnavailable,
  unconfirmedCommunityIdentity,
  candidateIdentity,
  unknownIdentity,
  moderationFlagged,
  waterReportedOut,
  lockReportedOut,
}

/// A non-selected option, carrying enough PURE-domain metadata for to
/// present it without re-deriving GO's semantics. No UI strings; no ratings /
/// votes.
class GoAlternative {
  final Toilet toilet;
  final double distanceMeters;
  final RecommendationAuthority authority;
  final OperationalCondition condition;

  /// True when the caller must get explicit user confirmation before
  /// navigating to THIS alternative (identity uncertainty, or a
  /// corroborated-unavailable condition).
  final bool requiresConfirmation;

  final Set<GoCaution> cautions;

  const GoAlternative({
    required this.toilet,
    required this.distanceMeters,
    required this.authority,
    required this.condition,
    required this.requiresConfirmation,
    required this.cautions,
  });
}

class GoInput {
  final Toilet toilet;

  /// Straight-line distance in metres. Invalid values (NaN, ±Infinity,
  /// negative) are DROPPED. `0` is valid.
  final double distanceMeters;
  const GoInput(this.toilet, this.distanceMeters);
}

class GoDecision {
  /// The recommended toilet, or null when there is no confident recommendation.
  final Toilet? selected;
  final double? selectedDistanceMeters;

  final GoReason reason;

  /// True when the caller MUST present the caution(s) and get explicit user
  /// confirmation before navigating .
  final bool requiresConfirmation;

  final Set<GoCaution> cautions;

  /// Other options from the SAME active recommendation tier as [selected],
  /// distance-sorted, excluding [selected]. Never mixes a lower identity tier
  /// in, and never contains moderation-flagged toilets.
  final List<GoAlternative> alternatives;

  /// The nearest member of the ACTIVE RECOMMENDATION TIER, before any evidence
  /// promotion / avoidance. `null` for the flagged-only / no-recommendation and
  /// no-toilets results. This field explains how evidence changed the selection
  /// relative to the relevant distance baseline; it never changes a winner.
  final Toilet? baselineNearest;
  final double? baselineNearestDistanceMeters;

  const GoDecision({
    required this.selected,
    required this.selectedDistanceMeters,
    required this.reason,
    required this.requiresConfirmation,
    required this.cautions,
    required this.alternatives,
    required this.baselineNearest,
    required this.baselineNearestDistanceMeters,
  });
}

// ---------------------------------------------------------------- the engine
class _Scored {
  final Toilet toilet;
  final double distance;
  final OperationalCondition cond;
  final RecommendationAuthority auth;

  /// The exact `now` used to classify this record — kept so every derived
  /// caution stays PURE (no wall-clock reads).
  final DateTime now;

  _Scored(this.toilet, this.distance, this.cond, this.auth, this.now);

  /// Cautions that describe THIS record's current condition (negative class +
  /// water/lock), independent of whether it was selected.
  Set<GoCaution> get conditionCautions {
    final ce = toilet.evidence.condition;
    final s = <GoCaution>{};
    switch (cond) {
      case OperationalCondition.corroboratedUnavailable:
        s.add(GoCaution.corroboratedUnavailable);
        break;
      case OperationalCondition.singleReportedUnavailable:
        s.add(GoCaution.singleReportUnavailable);
        break;
      case OperationalCondition.conflictedUnavailableMajority:
        s.add(GoCaution.conflictedUnavailable);
        break;
      default:
        break;
    }
    if (ce.isCurrentlyValid(now)) {
      if (ce.water == ConditionState.no) s.add(GoCaution.waterReportedOut);
      if (ce.lock == ConditionState.no) s.add(GoCaution.lockReportedOut);
    }
    return s;
  }

  Set<GoCaution> get identityCautions => switch (auth) {
        RecommendationAuthority.flaggedExcluded => {
            GoCaution.moderationFlagged
          },
        RecommendationAuthority.communityFallback => {
            GoCaution.unconfirmedCommunityIdentity,
          },
        RecommendationAuthority.candidateFallback => {
            GoCaution.candidateIdentity
          },
        RecommendationAuthority.unknownFallback => {GoCaution.unknownIdentity},
        _ => const {},
      };

  Set<GoCaution> get allCautions => {...identityCautions, ...conditionCautions};

  /// Whether navigating to THIS record needs explicit confirmation.
  bool get needsConfirmation =>
      cond == OperationalCondition.corroboratedUnavailable ||
      auth == RecommendationAuthority.communityFallback ||
      auth == RecommendationAuthority.candidateFallback ||
      auth == RecommendationAuthority.unknownFallback;

  GoAlternative toAlternative() => GoAlternative(
        toilet: toilet,
        distanceMeters: distance,
        authority: auth,
        condition: cond,
        requiresConfirmation: needsConfirmation,
        cautions: allCautions,
      );
}

/// Deterministic comparator: distance ascending, then toilet id lexical.
int _byDistanceThenId(_Scored a, _Scored b) {
  final d = a.distance.compareTo(b.distance);
  return d != 0 ? d : a.toilet.id.compareTo(b.toilet.id);
}

_Scored? _firstWhereOrNull(Iterable<_Scored> xs, bool Function(_Scored) test) {
  for (final x in xs) {
    if (test(x)) return x;
  }
  return null;
}

/// Up to 3 nearest alternatives FROM THE GIVEN TIER, excluding [selectedId].
List<GoAlternative> _altsFromTier(List<_Scored> tier, String? selectedId) {
  return tier
      .where((s) => s.toilet.id != selectedId)
      .take(3)
      .map((s) => s.toAlternative())
      .toList(growable: false);
}

/// Decide the GO recommendation. Deterministic: identical inputs (in any list
/// order) always produce the identical result.
GoDecision decideGo(List<GoInput> pool, {required DateTime now}) {
  // 1. Drop structurally invalid distances (NaN, ±Infinity, negative);
  //    classify each surviving toilet.
  final scored = <_Scored>[];
  for (final g in pool) {
    if (!_validDistance(g.distanceMeters)) continue;
    final cond = classifyCondition(g.toilet.evidence.condition, now);
    final auth = recommendationAuthority(g.toilet, cond, now: now);
    scored.add(_Scored(g.toilet, g.distanceMeters, cond, auth, now));
  }
  scored.sort(_byDistanceThenId);

  if (scored.isEmpty) {
    return const GoDecision(
      selected: null,
      selectedDistanceMeters: null,
      reason: GoReason.noToilets,
      requiresConfirmation: false,
      cautions: {},
      alternatives: [],
      baselineNearest: null,
      baselineNearestDistanceMeters: null,
    );
  }

  final primary = scored.where((s) => _isPrimary(s.auth)).toList();

  // ================================================================ PRIMARY
  if (primary.isNotEmpty) {
    final _Scored originalBaseline = primary.first; // distance/id sorted
    final Toilet baseT = originalBaseline.toilet;
    final double baseD = originalBaseline.distance;

    GoDecision primaryResult({
      required _Scored selected,
      required GoReason reason,
    }) =>
        GoDecision(
          selected: selected.toilet,
          selectedDistanceMeters: selected.distance,
          reason: reason,
          requiresConfirmation: selected.needsConfirmation,
          cautions: selected.allCautions,
          alternatives: _altsFromTier(primary, selected.toilet.id),
          baselineNearest: baseT,
          baselineNearestDistanceMeters: baseD,
        );

    // ---- CASE C : the nearest primary is CORROBORATED-UNAVAILABLE.
    if (originalBaseline.cond == OperationalCondition.corroboratedUnavailable) {
      // ESCAPE_POOL: primary toilets that are NOT the original baseline, NOT
      // corroborated-unavailable, and within BOTH detour guards of the
      // ORIGINAL baseline distance.
      final escapePool = primary
          .where(
            (s) =>
                s.toilet.id != baseT.id &&
                s.cond != OperationalCondition.corroboratedUnavailable &&
                withinEvidenceDetour(baseD, s.distance),
          )
          .toList();

      if (escapePool.isEmpty) {
        // Do NOT pretend it is fine; do NOT escape several times farther.
        return GoDecision(
          selected: baseT,
          selectedDistanceMeters: baseD,
          reason: GoReason.bestMappedOptionCorroboratedUnavailable,
          requiresConfirmation: true,
          cautions:
              originalBaseline.allCautions, // {corroboratedUnavailable, ...}
          alternatives: _altsFromTier(primary, baseT.id),
          baselineNearest: baseT,
          baselineNearestDistanceMeters: baseD,
        );
      }

      // PROVISIONAL_BASELINE = nearest ESCAPE_POOL member (distance, then id).
      // Distance — NOT "unknown sounds safer" — selects it. A single or
      // conflicted negative does NOT gain extra detour authority here.
      final _Scored provisional = escapePool.first;

      // Then the SAME positive-promotion principle, but confined to ESCAPE_POOL:
      // ONLY corroborated-clear usable may promote past the provisional
      // baseline. (Any corr-usable in ESCAPE_POOL is automatically within the
      // detour guards of the provisional baseline too, since ESCAPE_POOL is
      // bounded by the — nearer or equal — original baseline.)
      final _Scored? corrUsable = _firstWhereOrNull(
        escapePool,
        (s) => s.cond == OperationalCondition.corroboratedUsable,
      );
      if (corrUsable != null) {
        return primaryResult(
          selected: corrUsable,
          reason: GoReason.recentCorroboratedUsableWithinDetour,
        );
      }
      // Distance wins the escape. The provisional's OWN condition cautions
      // (single / conflicted unavailable, water/lock) are preserved.
      return primaryResult(
        selected: provisional,
        reason: GoReason.avoidedRecentCorroboratedUnavailable,
      );
    }

    // ---- Normal selection policy (original baseline is not corr-unavailable).
    // (b) POSITIVE promotion — ONLY corroborated-clear usable may justify a
    //     detour past the nearest baseline.
    for (final s in primary) {
      if (s.cond != OperationalCondition.corroboratedUsable) continue;
      if (s.toilet.id == baseT.id) break; // baseline itself; handle in (c)
      if (withinEvidenceDetour(baseD, s.distance)) {
        return primaryResult(
          selected: s,
          reason: GoReason.recentCorroboratedUsableWithinDetour,
        );
      }
      break; // a farther corr-usable can only be more out of range
    }

    // (c) Select the nearest baseline. Single / conflicted evidence gets NO
    //     detour authority — it only wins by being the nearest, which it is.
    final GoReason reason = switch (originalBaseline.cond) {
      OperationalCondition.corroboratedUsable =>
        GoReason.recentCorroboratedUsableWithinDetour,
      OperationalCondition.singleReportedUnavailable =>
        GoReason.singleNegativeWarning,
      OperationalCondition.conflictedUnavailableMajority =>
        GoReason.conflictedNegativeWarning,
      _ => GoReason.nearestWithNoStrongEvidence,
    };
    return primaryResult(selected: originalBaseline, reason: reason);
  }

  // ============================================================== FALLBACK
  final community = scored
      .where((s) => s.auth == RecommendationAuthority.communityFallback)
      .toList();
  if (community.isNotEmpty) {
    final s = community.first;
    return GoDecision(
      selected: s.toilet,
      selectedDistanceMeters: s.distance,
      reason: GoReason.communitySubmissionFallback,
      requiresConfirmation: true,
      cautions: s.allCautions, // {unconfirmedCommunityIdentity, ...}
      alternatives: _altsFromTier(community, s.toilet.id),
      baselineNearest: s.toilet,
      baselineNearestDistanceMeters: s.distance,
    );
  }

  final candidateOrUnknown = scored
      .where(
        (s) =>
            s.auth == RecommendationAuthority.candidateFallback ||
            s.auth == RecommendationAuthority.unknownFallback,
      )
      .toList();
  if (candidateOrUnknown.isNotEmpty) {
    final s = candidateOrUnknown.first;
    return GoDecision(
      selected: s.toilet,
      selectedDistanceMeters: s.distance,
      reason: GoReason.candidateFallback,
      requiresConfirmation: true,
      cautions: s.allCautions, // {candidateIdentity | unknownIdentity, ...}
      alternatives: _altsFromTier(candidateOrUnknown, s.toilet.id),
      baselineNearest: s.toilet,
      baselineNearestDistanceMeters: s.distance,
    );
  }

  // Everything left is moderation-flagged -> no confident recommendation and
  // no actionable alternatives.
  return const GoDecision(
    selected: null,
    selectedDistanceMeters: null,
    reason: GoReason.onlyFlaggedOrUnconfirmedOptions,
    requiresConfirmation: false,
    cautions: {GoCaution.moderationFlagged},
    alternatives: [],
    baselineNearest: null,
    baselineNearestDistanceMeters: null,
  );
}
