// ShauchMap GO V2 — the ONE live resolution path .
//
// Every GO surface (the GO button, the home widget, a widget/deep-link tap)
// funnels through `resolveGo`. There is exactly one place that:
//   1. takes the currently loaded toilet pool,
//   2. takes the current user position,
//   3. computes STRAIGHT-LINE distance for each toilet,
//   4. captures ONE `now`,
//   5. calls the frozen `decideGo`.
//
// No surface may keep its own "nearest toilet" ranking loop, and no surface may
// re-implement recommendation policy. The UI formats the returned `GoDecision`;
// it does not change it.
//
// Legacy `is_open`, ratings, votes, community score and star averages are NEVER
// read here — `decideGo` already ignores them and this path adds nothing.

import '../geo/geo.dart';

import '../models/toilet.dart';
import 'go_decision.dart';
import 'go_presentation.dart';

/// Straight-line metres between two lat/lng pairs. Injectable for tests.
typedef DistanceFn = double Function(
    double lat1, double lng1, double lat2, double lng2);

/// Resolve the current GO recommendation from a live pool + position.
///
/// Pass [now] so the whole app shares ONE timestamp for a given resolution
/// (Evidence V2 expiry + moderation-flag expiry both key off it). [distance]
/// defaults to `Geolocator.distanceBetween`.
GoDecision resolveGo({
  required Iterable<Toilet> toilets,
  required double userLat,
  required double userLng,
  required DateTime now,
  DistanceFn distance = geoDistanceMeters,
}) {
  final inputs = <GoInput>[
    for (final t in toilets)
      GoInput(t, distance(userLat, userLng, t.latitude, t.longitude)),
  ];
  return decideGo(inputs, now: now);
}

/// A complete GO resolution: the exact [position] the candidate pool was built
/// from, the [decision], and the [now] it was resolved at. The preview MUST use
/// `snapshot.position` as the authoritative origin — never a later mutation of
/// `_userPosition` . Navigation-time revalidation builds a NEW
/// snapshot.
typedef GoResolutionSnapshot = ({
  GeoPos position,
  GoDecision decision,
  DateTime now,
});

// --------------------------------------------------------- position freshness
//
// Three DISTINCT horizons . NONE is the Evidence V2 60-minute
// CONDITION window — location freshness and evidence freshness are separate.

/// `_userPosition` (an already-held fix) may seed a GO resolution only if this
/// fresh.
const Duration kGoCachedPositionMaxAge = Duration(seconds: 10);

/// A `getLastKnownPosition()` result may seed a GO resolution only if this
/// fresh.
const Duration kGoLastKnownMaxAge = Duration(seconds: 30);

/// At the moment a NEW actionable home-widget suggestion is COMPUTED /
/// PUBLISHED, the backing position must be at least this fresh .
/// This is a PUBLISH-TIME gate, not a continuous guarantee: once published, the
/// row stays visibly cached (with its "Suggestion updated …" timestamp) until
/// Android / the app writes it again. That is safe because a widget/deep-link
/// tap always opens the app and runs a fresh acquire → pool → decideGo →
/// preview/confirmation → Maps. No 30-second background polling.
const Duration kGoActionableWidgetMaxAge = Duration(seconds: 30);

/// True iff [position] is usable as "the user's location right now": its
/// timestamp is not in the future (no negative age) and its age does not exceed
/// [maxAge]. Pure .
bool isGoPositionFresh(
  GeoPos position,
  DateTime now, {
  required Duration maxAge,
}) {
  final age = now.difference(position.timestamp);
  if (age.isNegative) return false; // future timestamp — reject
  return age <= maxAge;
}

/// Whether a freshly-resolved decision is materially different from [previous]
/// for navigation purposes: a different selected toilet, OR a stronger
/// warning/confirmation contract. Used to block launching a stale suggestion
/// .
bool goResultMateriallyChanged(GoDecision previous, GoDecision fresh) {
  if (previous.selected?.id != fresh.selected?.id) return true;
  if (fresh.selected == null) return true;
  if (fresh.requiresConfirmation && !previous.requiresConfirmation) return true;
  // A caution set that gained any member is "materially stronger".
  final gained = fresh.cautions.difference(previous.cautions);
  if (gained.isNotEmpty) return true;
  if (fresh.reason != previous.reason) return true;
  return false;
}

/// The user's choice on the no-suggestion sheet. The active GO flow acts on
/// this AFTER the sheet closes so Retry starts a real new resolution instead of
/// re-entering a still-active flow .
enum GoNullAction { retry, browse, dismiss }

/// The GO flow loop, extracted so its RETRY semantics are testable without a
/// widget harness .
///
/// The loop holds NO lock of its own — the caller's `_isNavigatingFlowActive`
/// guard wraps the whole call, so a Retry loops HERE (a real fresh
/// position + pool + resolve) instead of re-entering a guarded method.
///
/// Returns the `GoResolutionSnapshot` to preview, or null when the user chose
/// browse / dismiss or acquisition failed (the caller shows the error via
/// [onError]).
Future<GoResolutionSnapshot?> runGoFlowLoop({
  required Future<GeoPos?> Function() acquire,
  required Future<List<Toilet>?> Function(GeoPos position) loadPool,
  required GoResolutionSnapshot Function(List<Toilet> pool, GeoPos position)
      resolve,
  required Future<GoNullAction> Function(GoDecision decision) showNull,
  required void Function(String message) onError,
}) async {
  while (true) {
    final pos = await acquire();
    if (pos == null) {
      onError('Cannot locate you right now');
      return null;
    }
    final pool = await loadPool(pos);
    if (pool == null) {
      onError("Couldn't load nearby toilets for GO. Try again.");
      return null;
    }
    final r = resolve(pool, pos);
    if (r.decision.selected != null) return r;
    final action = await showNull(r.decision);
    if (action == GoNullAction.retry) continue;
    return null;
  }
}

/// Given a fresh decision + a widget/deep-link hint id, what should the GO
/// preview focus on? Returns the alternative `GoTarget` to focus, or null to
/// show the normal selected preview . A hint that is the fresh
/// selected, is absent, was dropped from the active tier, or points at a
/// flagged/lower-tier toilet all fall through to null — the hint is never
/// authority.
GoTarget? resolveHintFocus(
  GoDecision fresh,
  String? hintToiletId, {
  required DateTime now,
}) {
  if (hintToiletId == null || hintToiletId.isEmpty) return null;
  final t = findInActiveTier(fresh, hintToiletId, now: now);
  if (t == null || t.isSelected) return null;
  return t;
}

/// The home-widget payload for "no trustworthy suggestion right now" — no
/// position, an empty current-user GO pool, a pool-load failure, or a stale
/// background position . EVERY actionable id/name is cleared
/// so a stale widget tap has no navigation target.
Map<String, String> goWidgetUnavailablePayload({
  required String updatedLabel,
  String message = 'Open ShauchMap to refresh',
}) {
  final out = <String, String>{'last_updated': updatedLabel};
  out['nearest_loo_name'] = message;
  out['nearest_loo_dist'] = '';
  out['toilet_id'] = '';
  for (var i = 1; i <= 3; i++) {
    out['med_${i}_name'] = i == 1 ? message : '';
    out['med_${i}_dist'] = '';
    out['med_${i}_id'] = '';
  }
  return out;
}

/// Build the home-widget SharedPreferences payload from a GO V2 [decision] as a
/// pure `key -> value` map. The caller writes it and
/// calls `HomeWidget.updateWidget`.
///
/// SMALL widget keys: `nearest_loo_name`, `nearest_loo_dist`, `toilet_id`.
/// MEDIUM widget keys: `med_{1..3}_{name,dist,id}` — row 1 is `selected`, rows
/// 2..3 are `decision.alternatives` in order (never a lower-authority toilet).
/// The `*_dist` value carries `<distance> · <compact GO status>` so a
/// fallback / warning / candidate result cannot look like a clean normal
/// recommendation — no reliability %, no "verified", no certainty.
/// `last_updated` is a *suggestion*-computed time, never a verification claim.
/// `decision.selected == null` → delegates to [goWidgetUnavailablePayload].
Map<String, String> goWidgetPayload(
  GoDecision decision, {
  required String updatedLabel,
  required DateTime now,
  String Function(double meters) formatMeters = _defaultMeters,
}) {
  if (decision.selected == null) {
    return goWidgetUnavailablePayload(
      updatedLabel: updatedLabel,
      message: 'No current suggestion',
    );
  }

  final out = <String, String>{'last_updated': updatedLabel};
  final sel = decision.selected!;
  final selDist = decision.selectedDistanceMeters ?? 0;
  final selCond = classifyCondition(sel.evidence.condition, now);
  final selAuth = recommendationAuthority(sel, selCond, now: now);
  final selStatus = goWidgetStatusText(
    goWidgetStatusFor(
      authority: selAuth,
      condition: selCond,
      requiresConfirmation: decision.requiresConfirmation,
      cautions: decision.cautions,
    ),
  );

  String distLine(double m, String status) => '${formatMeters(m)} · $status';

  out['nearest_loo_name'] = sel.name;
  out['nearest_loo_dist'] = distLine(selDist, selStatus);
  out['toilet_id'] = sel.id;

  final rows = <({String name, double dist, String id, String status})>[
    (name: sel.name, dist: selDist, id: sel.id, status: selStatus),
    for (final a in decision.alternatives)
      (
        name: a.toilet.name,
        dist: a.distanceMeters,
        id: a.toilet.id,
        status: goWidgetStatusText(
          goWidgetStatusFor(
            authority: a.authority,
            condition: a.condition,
            requiresConfirmation: a.requiresConfirmation,
            cautions: a.cautions,
          ),
        ),
      ),
  ];
  for (var i = 0; i < 3; i++) {
    if (i < rows.length) {
      out['med_${i + 1}_name'] = rows[i].name;
      out['med_${i + 1}_dist'] = distLine(rows[i].dist, rows[i].status);
      out['med_${i + 1}_id'] = rows[i].id;
    } else {
      out['med_${i + 1}_name'] = '';
      out['med_${i + 1}_dist'] = '';
      out['med_${i + 1}_id'] = '';
    }
  }
  return out;
}

String _defaultMeters(double m) =>
    m >= 1000 ? '${(m / 1000).toStringAsFixed(1)} km' : '${m.round()} m';

/// A navigable GO target found inside a fresh decision's active tier. Carries
/// the FULL domain truth of the fresh target — authority + condition are NOT
/// reconstructed with placeholders .
typedef GoTarget = ({
  Toilet toilet,
  double distanceMeters,
  RecommendationAuthority authority,
  OperationalCondition condition,
  bool requiresConfirmation,
  Set<GoCaution> cautions,
  bool isSelected,
});

/// Locate [toiletId] in a fresh decision's ACTIVE recommendation tier — either
/// as the selected toilet or one of its alternatives. Returns null when the id
/// is no longer part of the active GO result, in which case it MUST NOT be
/// launched through GO. (alternative case) + (deep-link case).
///
/// [now] must be the SAME timestamp the fresh decision was resolved with, so
/// the selected item's authority / condition are derived from the frozen domain
/// path, never guessed.
GoTarget? findInActiveTier(
  GoDecision fresh,
  String toiletId, {
  required DateTime now,
}) {
  if (fresh.selected?.id == toiletId) {
    final t = fresh.selected!;
    final cond = classifyCondition(t.evidence.condition, now);
    final auth = recommendationAuthority(t, cond, now: now);
    return (
      toilet: t,
      distanceMeters: fresh.selectedDistanceMeters ?? 0,
      authority: auth,
      condition: cond,
      requiresConfirmation: fresh.requiresConfirmation,
      cautions: fresh.cautions,
      isSelected: true,
    );
  }
  for (final a in fresh.alternatives) {
    if (a.toilet.id == toiletId) {
      return (
        toilet: a.toilet,
        distanceMeters: a.distanceMeters,
        authority: a.authority,
        condition: a.condition,
        requiresConfirmation: a.requiresConfirmation,
        cautions: a.cautions,
        isSelected: false,
      );
    }
  }
  return null;
}

/// A `GoAlternative` view of a [GoTarget] — carries the target's REAL authority
/// and condition (no placeholder `communityFallback` / `unknown`). Feed this to
/// `presentGoAlternative` / `presentGoDecision` so the confirmation copy matches
/// the fresh target's actual identity.
GoAlternative goAlternativeFromTarget(GoTarget t) => GoAlternative(
      toilet: t.toilet,
      distanceMeters: t.distanceMeters,
      authority: t.authority,
      condition: t.condition,
      requiresConfirmation: t.requiresConfirmation,
      cautions: t.cautions,
    );

/// How un-favourable an operational condition is (higher = worse). Used only to
/// spot a MATERIALLY less-favourable change between a stale and a fresh target
/// . Not a score, not used for ranking.
int _conditionSeverity(OperationalCondition c) => switch (c) {
      OperationalCondition.corroboratedUsable => 0,
      OperationalCondition.singleReportedUsable => 1,
      OperationalCondition.conflictedUsableMajority => 2,
      OperationalCondition.unknown => 3,
      OperationalCondition.singleReportedUnavailable => 4,
      OperationalCondition.conflictedUnavailableMajority => 5,
      OperationalCondition.corroboratedUnavailable => 6,
    };

/// True when navigating to the FRESH target instead of the STALE one would be
/// materially worse for the user : it gained
/// `requiresConfirmation`, gained ANY caution, changed authority, or its
/// operational condition moved to a strictly less-favourable class. A target
/// that is unchanged or SAFER returns false (navigation may continue).
bool goTargetMateriallyWorse(GoTarget stale, GoTarget fresh) {
  if (fresh.requiresConfirmation && !stale.requiresConfirmation) return true;
  if (fresh.cautions.difference(stale.cautions).isNotEmpty) return true;
  if (fresh.authority != stale.authority) return true;
  if (_conditionSeverity(fresh.condition) >
      _conditionSeverity(stale.condition)) {
    return true;
  }
  return false;
}

/// What a navigation-time revalidation should do . PURE — the
/// caller performs the UI. There is exactly ONE confirmation, and it is always
/// based on the FRESH target's metadata; the preview's primary CTA must NOT
/// confirm before revalidation.
enum GoRevalidationOutcome {
  /// Fresh result has no confident selection, the navigated id dropped out of
  /// the active tier, or the whole selected decision materially changed —
  /// re-present the fresh GO result.
  refreshSuggestion,

  /// The specific target got materially worse (gained caution / confirmation /
  /// worse condition / changed authority) — re-present the FRESH target's
  /// focused preview, do NOT launch.
  refreshOption,

  /// Fresh target is navigable but currently requires confirmation — show ONE
  /// confirmation sheet from the fresh metadata, then launch.
  confirmThenLaunch,

  /// Fresh target is navigable and needs no confirmation — launch.
  launch,
}

/// Resolve the revalidation outcome. [targetId] null = navigate the fresh
/// selected; non-null = navigate that alternative id.
GoRevalidationOutcome goRevalidationOutcome(
  GoResolutionSnapshot stale,
  GoResolutionSnapshot fresh, {
  String? targetId,
}) {
  final f = fresh.decision;
  final wantId = targetId ?? f.selected?.id;
  if (f.selected == null || wantId == null) {
    return GoRevalidationOutcome.refreshSuggestion;
  }
  final freshTarget = findInActiveTier(f, wantId, now: fresh.now);
  if (freshTarget == null) return GoRevalidationOutcome.refreshSuggestion;

  // Selected-level material change (a different winner / reason / stronger
  // contract) — only relevant when navigating the selected, not a pinned alt.
  if (targetId == null && goResultMateriallyChanged(stale.decision, f)) {
    return GoRevalidationOutcome.refreshSuggestion;
  }

  final staleTarget = findInActiveTier(stale.decision, wantId, now: stale.now);
  if (staleTarget != null &&
      goTargetMateriallyWorse(staleTarget, freshTarget)) {
    return GoRevalidationOutcome.refreshOption;
  }

  return freshTarget.requiresConfirmation
      ? GoRevalidationOutcome.confirmThenLaunch
      : GoRevalidationOutcome.launch;
}
