// The tiny, stable JSON-string API over the ShauchMap domain core — the ENTIRE
// surface the ShauchMap Instant web shell calls across the `dart compile js`
// interop boundary.
//
//   evaluateTruth(jsonToiletMap)            -> canonical Truth JSON
//   evaluateEvidence(jsonEvidenceV2, nowMs) -> canonical Evidence JSON
//   evaluateGo(jsonGoInput, nowMs)          -> canonical GoDecision JSON
//                                             (+ "focus" when input has hintId)
//   evaluateRevalidation(jsonRevalInput)    -> {"outcome": "..."}
//   evaluatePositionFreshness(jsonInput)    -> {"fresh": true|false}
//   evaluateDistances(jsonInput)            -> {"distances": [{"id","meters"}]}
//
// Timestamps in the incoming JSON use the sentinel {"__ts__": epoch_ms} and
// are revived to a core `Instant` here — the same normalization the Android
// `firestore_domain_adapter` performs for Firestore `Timestamp` values.

import 'dart:convert';

import '../shauchmap_core.dart';

/// Bumped whenever a function is added to this surface, or the JSON shape of an
/// existing one changes in a way a caller must know about. The compiled-JS brain
/// and the TypeScript wrapper both carry this number and refuse to run if they
/// disagree — the guard against shipping a stale generated core alongside a
/// newer shell.
///
/// 1 — 5 fns: truth, evidence, go, revalidation,
///                        positionFreshness.
/// 2 — +evaluateDistances (canonical geoDistanceMeters,
///                        batched) so the web shell's 15 km pool filter and
///                        distance ordering use the ONE distance primitive.
/// 3 — evaluateGo input may carry `hintId`; when it does the
///                        result gains a `focus` key (the /t/:id deep-link
///                        focus, from the shared `resolveHintFocus` /
///                        `goAlternativeFromTarget` / `presentGoAlternative` —
///                        NOT re-derived in the shell). `focus` is `null` when
///                        the hint is the selected toilet, absent, or not in the
///                        fresh active tier.
const int kCoreInteropVersion = 3;

// ---- {"__ts__": ms} -> Instant --------------------------------------------
dynamic _revive(dynamic v) {
  if (v is Map) {
    if (v.length == 1 && v.containsKey('__ts__')) {
      return Instant.fromEpochMillis((v['__ts__'] as num).toInt());
    }
    return v.map((k, val) => MapEntry(k.toString(), _revive(val)));
  }
  if (v is List) return v.map(_revive).toList();
  return v;
}

Map<String, dynamic> _reviveMap(Map raw) =>
    (_revive(raw) as Map).cast<String, dynamic>();

double _dist(dynamic v) {
  if (v is num) return v.toDouble();
  switch (v) {
    case 'NaN':
      return double.nan;
    case 'Infinity':
      return double.infinity;
    case '-Infinity':
      return double.negativeInfinity;
  }
  return double.parse(v.toString());
}

// ---- canonical serializers ----------------------------------------------------
Map<String, dynamic> _support(EvidenceSupport s) =>
    {'yes': s.yes, 'no': s.no, 'unknown': s.unknown};

Map<String, dynamic> _serTruth(ToiletTruth t) => {
      'schemaVersion': t.schemaVersion,
      'source': t.source.name,
      'recordedAtMs': t.recordedAt?.toUtc().millisecondsSinceEpoch,
      'context': t.context.name,
      'gender': t.gender.name,
      'identityStatus': t.identityStatus.name,
      'fee': t.fee.name,
      'isNativeV2': t.isNativeV2,
      'isCandidate': t.isCandidate,
      'amenities': {
        'water': t.amenities.water.name,
        'soap': t.amenities.soap.name,
        'lock': t.amenities.lock.name,
        'western': t.amenities.western.name,
        'wheelchair': t.amenities.wheelchair.name,
        'babyChange': t.amenities.babyChange.name,
        'sanitaryDisposal': t.amenities.sanitaryDisposal.name,
      },
    };

Map<String, dynamic> _serEvidence(ToiletEvidence e, DateTime now) => {
      'present': e.present,
      'version': e.version,
      'ratings': {
        'available': e.ratings.available,
        'count': e.ratings.count,
        'average': e.ratings.average,
        'isIndexedZero': e.ratings.isIndexedZero,
      },
      'votes': {
        'available': e.votes.available,
        'up': e.votes.up,
        'down': e.votes.down,
        'isIndexedZero': e.votes.isIndexedZero,
      },
      'condition': {
        'available': e.condition.available,
        'open': e.condition.open.name,
        'water': e.condition.water.name,
        'usable': e.condition.usable.name,
        'lock': e.condition.lock.name,
        'contributorCount': e.condition.contributorCount,
        'latestAtMs': e.condition.latestAt?.toUtc().millisecondsSinceEpoch,
        'validUntilMs': e.condition.validUntil?.toUtc().millisecondsSinceEpoch,
        'isCurrentlyValid': e.condition.isCurrentlyValid(now),
        'ageMinutes': e.condition.ageMinutes(now),
        'supportOpen': _support(e.condition.supportOpen),
        'supportWater': _support(e.condition.supportWater),
        'supportUsable': _support(e.condition.supportUsable),
        'supportLock': _support(e.condition.supportLock),
      },
    };

Map<String, dynamic> _serAlt(GoAlternative a) => {
      'id': a.toilet.id,
      'distanceMeters': a.distanceMeters,
      'authority': a.authority.name,
      'condition': a.condition.name,
      'requiresConfirmation': a.requiresConfirmation,
      'cautions': (a.cautions.map((c) => c.name).toList()..sort()),
    };

Map<String, dynamic> _serGo(GoDecision d) {
  final pres = presentGoDecision(
    d,
    selectedIdentity: d.selected?.truth.identityStatus,
  );
  return {
    'selectedId': d.selected?.id,
    'selectedDistanceMeters': d.selectedDistanceMeters,
    'reason': d.reason.name,
    'requiresConfirmation': d.requiresConfirmation,
    'cautions': (d.cautions.map((c) => c.name).toList()..sort()),
    'alternatives': d.alternatives.map(_serAlt).toList(),
    'baselineNearestId': d.baselineNearest?.id,
    'baselineNearestDistanceMeters': d.baselineNearestDistanceMeters,
    'presentation': {
      'headline': pres.headline,
      'explanation': pres.explanation,
      'navigationAllowed': pres.navigationAllowed,
      'requiresConfirmation': pres.requiresConfirmation,
      'primaryCta': pres.primaryCta,
      'secondaryCta': pres.secondaryCta,
      'cautions': pres.cautions,
      'tone': pres.tone.name,
    },
  };
}

/// Serialize a `/t/:id` deep-link FOCUS — the alternative the hint points at,
/// built by the shared `goAlternativeFromTarget` + presented by the shared
/// `presentGoAlternative` (NEVER `presentGoDecision`, so the copy is the
/// alternative's own, not the GO-selected toilet's).
Map<String, dynamic> _serFocus(GoTarget t) {
  final alt = goAlternativeFromTarget(t);
  final pres =
      presentGoAlternative(alt, identity: t.toilet.truth.identityStatus);
  return {
    'id': t.toilet.id,
    'distanceMeters': t.distanceMeters,
    'authority': t.authority.name,
    'condition': t.condition.name,
    'requiresConfirmation': t.requiresConfirmation,
    'cautions': (t.cautions.map((c) => c.name).toList()..sort()),
    'isSelected': t
        .isSelected, // always false for a real focus (guarded in resolveHintFocus)
    'presentation': {
      'headline': pres.headline,
      'explanation': pres.explanation,
      'navigationAllowed': pres.navigationAllowed,
      'requiresConfirmation': pres.requiresConfirmation,
      'primaryCta': pres.primaryCta,
      'secondaryCta': pres.secondaryCta,
      'cautions': pres.cautions,
      'tone': pres.tone.name,
    },
  };
}

Toilet _toilet(String id, Map<String, dynamic> map) => Toilet.fromMap(id, map);

GoResolutionSnapshot _resolve(Map<String, dynamic> side) {
  final double lat = (side['userLat'] as num).toDouble();
  final double lng = (side['userLng'] as num).toDouble();
  final DateTime now = DateTime.fromMillisecondsSinceEpoch(
      (side['nowMs'] as num).toInt(),
      isUtc: true);
  final pool = <Toilet>[
    for (final raw in (side['pool'] as List))
      () {
        final m = _reviveMap((raw as Map)['map'] as Map? ?? {});
        m['latitude'] = raw['lat'] ?? m['latitude'] ?? 0.0;
        m['longitude'] = raw['lng'] ?? m['longitude'] ?? 0.0;
        return _toilet(raw['id'] as String, m);
      }(),
  ];
  final decision = resolveGo(
    toilets: pool,
    userLat: lat,
    userLng: lng,
    now: now,
    // the canonical primitive — identical to Geolocator.distanceBetween.
    distance: geoDistanceMeters,
  );
  return (
    position: GeoPos(latitude: lat, longitude: lng, timestamp: now),
    decision: decision,
    now: now,
  );
}

// ═══════════════════════════ PUBLIC API (String -> String) ═══════════════════

String evaluateTruth(String jsonToiletMap) {
  final m = _reviveMap(jsonDecode(jsonToiletMap) as Map);
  final t = ToiletTruth.fromFirestore(m, addedBy: m['added_by'] ?? '');
  return jsonEncode(_serTruth(t));
}

String evaluateEvidence(String jsonEvidenceV2, num nowMs) {
  final raw = jsonDecode(jsonEvidenceV2);
  final e = ToiletEvidence.fromFirestore(raw == null ? null : _revive(raw));
  final now = DateTime.fromMillisecondsSinceEpoch(nowMs.toInt(), isUtc: true);
  return jsonEncode(_serEvidence(e, now));
}

/// jsonGoInput: an object with a "pool" list of { id, distanceMeters, map } and
/// an optional "hintId" (the /t/:id deep-link target). When "hintId" is present
/// the result gains a "focus" key: the serialized `resolveHintFocus` outcome —
/// the alternative to focus, or `null` when the hint is the selected toilet /
/// absent / not in the fresh active tier. Never adds recommendation authority.
String evaluateGo(String jsonGoInput, num nowMs) {
  final obj = jsonDecode(jsonGoInput) as Map;
  final now = DateTime.fromMillisecondsSinceEpoch(nowMs.toInt(), isUtc: true);
  final inputs = <GoInput>[
    for (final t in (obj['pool'] as List))
      GoInput(
        _toilet((t as Map)['id'] as String, _reviveMap(t['map'] as Map? ?? {})),
        _dist(t['distanceMeters']),
      ),
  ];
  final decision = decideGo(inputs, now: now);
  final out = _serGo(decision);
  if (obj.containsKey('hintId')) {
    final hintId = obj['hintId'] as String?;
    final focus = resolveHintFocus(decision, hintId, now: now);
    out['focus'] = focus == null ? null : _serFocus(focus);
  }
  return jsonEncode(out);
}

/// jsonRevalInput: an object with keys targetId (string or null), stale, fresh.
/// stale/fresh each = { userLat, userLng, nowMs, pool: [ { id, lat, lng, map } ] }.
String evaluateRevalidation(String jsonRevalInput) {
  final obj = jsonDecode(jsonRevalInput) as Map;
  final stale = _resolve((obj['stale'] as Map).cast<String, dynamic>());
  final fresh = _resolve((obj['fresh'] as Map).cast<String, dynamic>());
  final outcome = goRevalidationOutcome(
    stale,
    fresh,
    targetId: obj['targetId'] as String?,
  );
  return jsonEncode({'outcome': outcome.name});
}

/// jsonInput: an object with keys positionTsMs, nowMs, maxAgeSeconds (numbers).
/// Delegates verbatim to the shared [isGoPositionFresh] safety rule — the web
/// shell MUST NOT reimplement location freshness in TypeScript. Latitude and
/// longitude are irrelevant to the rule, so a placeholder GeoPos is built.
String evaluatePositionFreshness(String jsonInput) {
  final o = jsonDecode(jsonInput) as Map;
  final fresh = isGoPositionFresh(
    GeoPos(
      latitude: 0,
      longitude: 0,
      timestamp: DateTime.fromMillisecondsSinceEpoch(
          (o['positionTsMs'] as num).toInt(),
          isUtc: true),
    ),
    DateTime.fromMillisecondsSinceEpoch((o['nowMs'] as num).toInt(),
        isUtc: true),
    maxAge: Duration(seconds: (o['maxAgeSeconds'] as num).toInt()),
  );
  return jsonEncode({'fresh': fresh});
}

/// jsonInput: { "from": {"lat","lng"}, "to": [ {"id","lat","lng"} ] }.
/// Returns { "distances": [ {"id", "meters"} ] } using the ONE canonical
/// primitive [geoDistanceMeters] (byte-for-byte Geolocator.distanceBetween).
/// The web shell uses this for its strict 15 km pool filter and its
/// distance-then-id ordering — it never does trigonometry in TypeScript.
String evaluateDistances(String jsonInput) {
  final o = jsonDecode(jsonInput) as Map;
  final from = (o['from'] as Map);
  final fromLat = (from['lat'] as num).toDouble();
  final fromLng = (from['lng'] as num).toDouble();
  final out = [
    for (final t in (o['to'] as List))
      {
        'id': (t as Map)['id'],
        'meters': geoDistanceMeters(
          fromLat,
          fromLng,
          (t['lat'] as num).toDouble(),
          (t['lng'] as num).toDouble(),
        ),
      }
  ];
  return jsonEncode({'distances': out});
}
