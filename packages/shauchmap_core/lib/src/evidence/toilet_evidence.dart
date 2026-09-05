// ShauchMap Evidence V2 — the client-side view of the SERVER-DERIVED evidence
// summary at `toilets/{id}.evidence_v2`.
//
// WHY IT IS SEPARATE FROM TRUTH V2
// -------------------------------
//   ToiletTruth   = STATIC identity + facility attributes. Slow-changing.
//   ToiletEvidence = DYNAMIC community signals — ratings, votes, recent
//                   condition — recomputed by a trusted Cloud Function from the
//                   secured raw sub-collections. Clients cannot write it. It
//                   lets Map / List / GO read evidence from the toilet document
//                   they already fetch, without an N+1 query.
//
// HONESTY RULES baked in here:
//   * "server-derived", never "verified". Ratings / votes / check-ins are NOT
//     proof of operational condition.
//   * ABSENT != ZERO. A missing section => "not indexed / unavailable". An
//     indexed `count == 0` is a real zero.
//   * Each section is parsed STRICTLY: it counts as `available` only if its full
//     required server shape is valid (correct types, non-negative counts,
//     server timestamps, exact tri-states, structurally consistent condition).
//     One malformed section never invalidates a valid sibling.
//   * Condition carries `validUntil`. Once `now >= validUntil` the derived
//     condition is EXPIRED and must be treated as UNKNOWN, because observations
//     leaving the 60-minute window can flip the majority with no document write
//     to re-trigger the function.
//   * The frozen legacy parent aggregates (`star_rating`, `total_ratings`,
//     `upvote_count`, `downvote_count`) are NEVER a fallback.
//   * Malformed data degrades to unavailable / unknown. Never throws.

import '../time/instant.dart';

/// Condition tri-state as derived by the server. `unknown` is first-class.
enum ConditionState { yes, no, unknown }

ConditionState? _strictCond(Object? v) => switch (v) {
      'yes' => ConditionState.yes,
      'no' => ConditionState.no,
      'unknown' => ConditionState.unknown,
      _ => null,
    };

bool _isNonNegInt(Object? v) => v is int && v >= 0;
DateTime? _ts(Object? v) => v is Instant ? v.toDateTime() : null;

/// The verdict a dimension's support counts MUST imply: strict majority of
/// `yes` or `no`, otherwise `unknown` (a tie, or no yes/no observations at all).
/// Mirrors the server's `deriveCondition` verdict rule exactly.
ConditionState _impliedVerdict(EvidenceSupport s) {
  if (s.yes > s.no) return ConditionState.yes;
  if (s.no > s.yes) return ConditionState.no;
  return ConditionState.unknown;
}

/// Factual support counts for ONE condition dimension, over the valid
/// observations inside the current 60-minute window. `yes + no + unknown`
/// equals the condition `contributorCount` for EVERY dimension. Plain counts —
/// never a confidence / probability.
class EvidenceSupport {
  final int yes;
  final int no;
  final int unknown;
  const EvidenceSupport(this.yes, this.no, this.unknown);

  static const EvidenceSupport zero = EvidenceSupport(0, 0, 0);

  int get total => yes + no + unknown;

  /// Parse + structurally validate one dimension's support map. Returns null
  /// on any non-int / negative value. The `total == contributorCount` check is
  /// done by the caller (it knows the count).
  static EvidenceSupport? parse(Object? raw) {
    if (raw is! Map) return null;
    final m = Map<String, dynamic>.from(raw);
    if (!_isNonNegInt(m['yes']) ||
        !_isNonNegInt(m['no']) ||
        !_isNonNegInt(m['unknown'])) {
      return null;
    }
    return EvidenceSupport(
      m['yes'] as int,
      m['no'] as int,
      m['unknown'] as int,
    );
  }
}

/// Server-derived rating summary. `available == false` => not indexed.
class RatingsEvidence {
  final bool available;
  final int count;
  final double? average;
  final DateTime? computedAt;

  const RatingsEvidence._({
    required this.available,
    required this.count,
    required this.average,
    required this.computedAt,
  });

  static const RatingsEvidence unavailable = RatingsEvidence._(
    available: false,
    count: 0,
    average: null,
    computedAt: null,
  );

  /// A genuine indexed zero (server looked and there are no ratings).
  bool get isIndexedZero => available && count == 0;

  /// STRICT: requires a non-negative int `count`, server `computed_at` +
  /// `last_event_at`, and an `average` that is null iff `count == 0` and a
  /// finite number in [1, 5] iff `count > 0`. Anything else => unavailable.
  static RatingsEvidence parse(Object? raw) {
    if (raw is! Map) return unavailable;
    final m = Map<String, dynamic>.from(raw);
    if (!_isNonNegInt(m['count'])) return unavailable;
    if (_ts(m['computed_at']) == null || _ts(m['last_event_at']) == null) {
      return unavailable;
    }
    final int count = m['count'] as int;
    final Object? avg = m['average'];
    if (count == 0) {
      if (avg != null) return unavailable; // inconsistent
      return RatingsEvidence._(
        available: true,
        count: 0,
        average: null,
        computedAt: _ts(m['computed_at']),
      );
    }
    if (avg is! num || !avg.isFinite || avg < 1.0 || avg > 5.0) {
      return unavailable;
    }
    return RatingsEvidence._(
      available: true,
      count: count,
      average: avg.toDouble(),
      computedAt: _ts(m['computed_at']),
    );
  }
}

/// Server-derived vote counts. `available == false` => not indexed.
class VotesEvidence {
  final bool available;
  final int up;
  final int down;
  final DateTime? computedAt;

  const VotesEvidence._({
    required this.available,
    required this.up,
    required this.down,
    required this.computedAt,
  });

  static const VotesEvidence unavailable = VotesEvidence._(
    available: false,
    up: 0,
    down: 0,
    computedAt: null,
  );

  bool get isIndexedZero => available && up == 0 && down == 0;

  /// STRICT: non-negative int `up` + `down`, server `computed_at` +
  /// `last_event_at`. Anything else => unavailable.
  static VotesEvidence parse(Object? raw) {
    if (raw is! Map) return unavailable;
    final m = Map<String, dynamic>.from(raw);
    if (!_isNonNegInt(m['up']) || !_isNonNegInt(m['down'])) return unavailable;
    if (_ts(m['computed_at']) == null || _ts(m['last_event_at']) == null) {
      return unavailable;
    }
    return VotesEvidence._(
      available: true,
      up: m['up'] as int,
      down: m['down'] as int,
      computedAt: _ts(m['computed_at']),
    );
  }
}

/// Server-derived recent-condition summary. Independent tri-state per dimension.
class ConditionEvidence {
  final bool available;
  final ConditionState open;
  final ConditionState water;
  final ConditionState usable;
  final ConditionState lock;

  /// Distinct condition-check documents (== distinct accounts) inside the
  /// window at the time of the last server recomputation. NOT "verified users".
  final int contributorCount;

  final DateTime? latestAt;

  /// Earliest `(observationTime + 60 min)` among the observations used. Once
  /// `now >= validUntil` the summary is EXPIRED — see [isCurrentlyValid].
  final DateTime? validUntil;

  final DateTime? computedAt;

  /// Per-dimension factual support counts. For each, `total ==
  /// contributorCount` (structurally validated on parse).
  final EvidenceSupport supportOpen;
  final EvidenceSupport supportWater;
  final EvidenceSupport supportUsable;
  final EvidenceSupport supportLock;

  const ConditionEvidence._({
    required this.available,
    required this.open,
    required this.water,
    required this.usable,
    required this.lock,
    required this.contributorCount,
    required this.latestAt,
    required this.validUntil,
    required this.computedAt,
    required this.supportOpen,
    required this.supportWater,
    required this.supportUsable,
    required this.supportLock,
  });

  static const ConditionEvidence unavailable = ConditionEvidence._(
    available: false,
    open: ConditionState.unknown,
    water: ConditionState.unknown,
    usable: ConditionState.unknown,
    lock: ConditionState.unknown,
    contributorCount: 0,
    latestAt: null,
    validUntil: null,
    computedAt: null,
    supportOpen: EvidenceSupport.zero,
    supportWater: EvidenceSupport.zero,
    supportUsable: EvidenceSupport.zero,
    supportLock: EvidenceSupport.zero,
  );

  /// True only when the summary exists AND has not passed its conservative
  /// expiry. `validUntil == null` (no observations) is NOT currently valid.
  bool isCurrentlyValid(DateTime now) =>
      available && validUntil != null && now.isBefore(validUntil!);

  /// Minutes since the newest observation, or null.
  int? ageMinutes(DateTime now) => latestAt == null
      ? null
      : now.difference(latestAt!).inMinutes.clamp(0, 1 << 30);

  /// STRICT: every dimension an exact tri-state; a non-negative int
  /// `contributor_count`; server `computed_at` + `last_event_at`; a `support`
  /// map with all four dimensions, each `{yes,no,unknown}` non-negative ints
  /// summing to `contributor_count`. Each declared verdict MUST equal the
  /// verdict its own support counts imply (strict `yes`/`no` majority, else
  /// `unknown`) — a self-contradictory section is rejected whole. When
  /// `contributor_count == 0` there must be NO `latest_at` / `valid_until`,
  /// every verdict `unknown`, and every support count 0. When `> 0`,
  /// `latest_at` + `valid_until` must both be Timestamps. Any inconsistency
  /// => unavailable.
  static ConditionEvidence parse(Object? raw) {
    if (raw is! Map) return unavailable;
    final m = Map<String, dynamic>.from(raw);

    final open = _strictCond(m['open']);
    final water = _strictCond(m['water']);
    final usable = _strictCond(m['usable']);
    final lock = _strictCond(m['lock']);
    if (open == null || water == null || usable == null || lock == null) {
      return unavailable;
    }
    if (!_isNonNegInt(m['contributor_count'])) return unavailable;
    if (_ts(m['computed_at']) == null || _ts(m['last_event_at']) == null) {
      return unavailable;
    }
    final int cc = m['contributor_count'] as int;

    // ---- support block: required, all four dims, sums == contributor_count ----
    final Object? supRaw = m['support'];
    if (supRaw is! Map) return unavailable;
    final sup = Map<String, dynamic>.from(supRaw);
    final sOpen = EvidenceSupport.parse(sup['open']);
    final sWater = EvidenceSupport.parse(sup['water']);
    final sUsable = EvidenceSupport.parse(sup['usable']);
    final sLock = EvidenceSupport.parse(sup['lock']);
    if (sOpen == null || sWater == null || sUsable == null || sLock == null) {
      return unavailable;
    }
    if (sOpen.total != cc ||
        sWater.total != cc ||
        sUsable.total != cc ||
        sLock.total != cc) {
      return unavailable;
    }

    // ---- verdict <-> support consistency: the declared tri-state MUST be the
    // one the counts imply. A summary whose `usable: "yes"` is contradicted by
    // `support.usable: {yes:1,no:2}` is internally broken -> reject the WHOLE
    // section rather than trust either half.
    if (_impliedVerdict(sOpen) != open ||
        _impliedVerdict(sWater) != water ||
        _impliedVerdict(sUsable) != usable ||
        _impliedVerdict(sLock) != lock) {
      return unavailable;
    }

    final DateTime? latestAt = _ts(m['latest_at']);
    final DateTime? validUntil = _ts(m['valid_until']);

    if (cc == 0) {
      if (m['latest_at'] != null || m['valid_until'] != null) {
        return unavailable;
      }
      if (open != ConditionState.unknown ||
          water != ConditionState.unknown ||
          usable != ConditionState.unknown ||
          lock != ConditionState.unknown) {
        return unavailable;
      }
      return ConditionEvidence._(
        available: true,
        open: ConditionState.unknown,
        water: ConditionState.unknown,
        usable: ConditionState.unknown,
        lock: ConditionState.unknown,
        contributorCount: 0,
        latestAt: null,
        validUntil: null,
        computedAt: _ts(m['computed_at']),
        supportOpen: EvidenceSupport.zero,
        supportWater: EvidenceSupport.zero,
        supportUsable: EvidenceSupport.zero,
        supportLock: EvidenceSupport.zero,
      );
    }

    if (latestAt == null || validUntil == null) return unavailable;
    return ConditionEvidence._(
      available: true,
      open: open,
      water: water,
      usable: usable,
      lock: lock,
      contributorCount: cc,
      latestAt: latestAt,
      validUntil: validUntil,
      computedAt: _ts(m['computed_at']),
      supportOpen: sOpen,
      supportWater: sWater,
      supportUsable: sUsable,
      supportLock: sLock,
    );
  }
}

/// The whole `evidence_v2` map, parsed defensively. Sections are lazily created
/// server-side, so it is fine for only some to be present; each is validated
/// independently.
class ToiletEvidence {
  /// False when there is no usable `evidence_v2` map at all.
  final bool present;
  final int version;
  final RatingsEvidence ratings;
  final VotesEvidence votes;
  final ConditionEvidence condition;

  const ToiletEvidence._({
    required this.present,
    required this.version,
    required this.ratings,
    required this.votes,
    required this.condition,
  });

  static const ToiletEvidence unavailable = ToiletEvidence._(
    present: false,
    version: 0,
    ratings: RatingsEvidence.unavailable,
    votes: VotesEvidence.unavailable,
    condition: ConditionEvidence.unavailable,
  );

  /// Parse `data['evidence_v2']`. Missing / wrong version / malformed => a fully
  /// unavailable view. Never throws. NEVER reads legacy parent aggregates.
  factory ToiletEvidence.fromFirestore(Object? raw) {
    if (raw is! Map) return unavailable;
    final Map<String, dynamic> m;
    try {
      m = Map<String, dynamic>.from(raw);
    } catch (_) {
      return unavailable;
    }
    if (m['version'] != 1) return unavailable;
    return ToiletEvidence._(
      present: true,
      version: 1,
      ratings: RatingsEvidence.parse(m['ratings']),
      votes: VotesEvidence.parse(m['votes']),
      condition: ConditionEvidence.parse(m['condition']),
    );
  }
}
