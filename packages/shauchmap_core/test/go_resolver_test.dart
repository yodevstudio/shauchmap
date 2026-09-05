// The ONE GO resolution path, geo-pool ordering, the
// retry flow loop, the widget/deep-link hint contract, fresh-target metadata,
// position freshness, the resolution snapshot, and the home-widget payload
// builder. Pure (no Firebase, no Geolocator queries: fakes are injected).

import 'package:shauchmap_core/shauchmap_core.dart';
import 'package:test/test.dart';

final DateTime kNow = DateTime(2026, 9, 2, 12, 0, 0);
Instant _ts(DateTime d) => Instant.fromDateTime(d);

ToiletEvidence _cond({
  required int cc,
  (int, int) open = (0, 0),
  (int, int) usable = (0, 0),
}) {
  if (cc == 0) return ToiletEvidence.unavailable;
  String v((int, int) s) =>
      s.$1 > s.$2 ? 'yes' : (s.$2 > s.$1 ? 'no' : 'unknown');
  Map<String, int> sup((int, int) s) => {
        'yes': s.$1,
        'no': s.$2,
        'unknown': cc - s.$1 - s.$2,
      };
  return ToiletEvidence.fromFirestore({
    'version': 1,
    'condition': {
      'open': v(open),
      'water': 'unknown',
      'usable': v(usable),
      'lock': 'unknown',
      'contributor_count': cc,
      'latest_at': _ts(kNow.subtract(const Duration(minutes: 5))),
      'valid_until': _ts(kNow.add(const Duration(minutes: 40))),
      'computed_at': _ts(kNow.subtract(const Duration(seconds: 5))),
      'last_event_at': _ts(kNow.subtract(const Duration(seconds: 6))),
      'support': {
        'open': sup(open),
        'water': {'yes': 0, 'no': 0, 'unknown': cc},
        'usable': sup(usable),
        'lock': {'yes': 0, 'no': 0, 'unknown': cc},
      },
    },
  });
}

Toilet _t(
  String id, {
  IdentityStatus identity = IdentityStatus.sourceMapped,
  bool flagged = false,
  ToiletEvidence? evidence,
  double lat = 26.3,
  double lng = 73.1,
}) =>
    Toilet(
      id: id,
      name: 'T $id',
      address: 'A',
      latitude: lat,
      longitude: lng,
      category: 'govt',
      starRating: 0,
      totalRatings: 0,
      isOpen: true,
      isFree: true,
      genderType: 'unisex',
      hasWater: false,
      hasSoap: false,
      hasLock: false,
      isWheelchair: false,
      hasBabyChange: false,
      hasSanitaryDisposal: false,
      isWestern: false,
      womenSafeFlag: false,
      flaggedRaw: flagged,
      flaggedUntil: flagged ? DateTime(3000) : null,
      addedBy: 'x',
      truth: ToiletTruth(
        schemaVersion: 1,
        source: identity == IdentityStatus.communitySubmitted
            ? ToiletSource.communitySubmission
            : ToiletSource.osm,
        recordedAt: null,
        context: FacilityContext.unknown,
        gender: GenderAccess.unknown,
        identityStatus: identity,
        fee: FeeState.unknown,
        amenities: ToiletAmenities.allUnknown,
        isNativeV2: false,
      ),
      evidence: evidence ?? ToiletEvidence.unavailable,
    );

/// Fake distance fn: a toilet's `lat` field IS its metre distance from the
/// user, so a pool encodes exact straight-line distances via `lat:`.
double _fakeDist(double a, double b, double lat, double lng) => lat;

GeoPos _pos(double lat, double lng, {DateTime? at}) => GeoPos(
      latitude: lat,
      longitude: lng,
      timestamp: at ?? kNow,
    );

GoResolutionSnapshot _snap(GoDecision d) =>
    (position: _pos(0, 0), decision: d, now: kNow);

void main() {
  GoDecision resolve(List<Toilet> pool, {double userLat = 0}) => resolveGo(
        toilets: pool,
        userLat: userLat,
        userLng: 0,
        now: kNow,
        distance: _fakeDist,
      );

  group('GO POOL: resolveGo only sees the pool + position it is handed', () {
    test(
        'a pool centered elsewhere is ranked against the passed position, '
        'never an app-wide toilet set', () {
      // "Jaipur" pool (ids j*), user is "in Jodhpur": distances come from the
      // fake fn using each toilet lat. resolveGo has no other toilet source.
      final jaipur = [_t('j_near', lat: 120), _t('j_far', lat: 9000)];
      final d = resolve(jaipur);
      expect(d.selected!.id, 'j_near');
      // ONLY the handed toilets can ever be considered — no app-wide set.
      expect({
        d.selected!.id,
        ...d.alternatives.map((a) => a.toilet.id),
      }, everyElement(anyOf('j_near', 'j_far')));
    });

    test(
      'nearest-by-distance does NOT win when it is corroborated-unavailable',
      () {
        final a = _t('a', lat: 200, evidence: _cond(cc: 2, usable: (0, 2)));
        final b = _t('b', lat: 250);
        final d = resolve([a, b]);
        expect(d.selected!.id, 'b');
        expect(d.reason, GoReason.avoidedRecentCorroboratedUnavailable);
      },
    );

    test('empty pool => noToilets; flagged-only => no fallback to nearest', () {
      expect(resolve([]).reason, GoReason.noToilets);
      final f = resolve([
        _t('f1', lat: 40, flagged: true),
        _t('f2', lat: 90, flagged: true),
      ]);
      expect(f.selected, isNull);
      expect(f.reason, GoReason.onlyFlaggedOrUnconfirmedOptions);
    });
  });

  group('orderNearest — deterministic ordering, no forced truncation', () {
    test(
        'limit 0 (what getGoPool uses): >120 records all returned, ordered, '
        'nearest first even when the source put it LAST', () {
      final raw = <Ranked<String>>[
        for (var i = 0; i < 130; i++)
          (
            item: 'r${(129 - i).toString().padLeft(3, '0')}',
            distanceKm: (129 - i) * 0.1,
          ),
      ];
      final out = orderNearest(raw, (s) => s, limit: 0);
      expect(out.length, 130); // NOTHING dropped
      expect(out.first, 'r000'); // nearest, was last in input
      expect(out.last, 'r129'); // farthest
    });

    test('distance tie => stable lexical id order', () {
      final raw = <Ranked<String>>[
        (item: 'zebra', distanceKm: 1.0),
        (item: 'alpha', distanceKm: 1.0),
        (item: 'mike', distanceKm: 1.0),
      ];
      expect(orderNearest(raw, (s) => s, limit: 0), ['alpha', 'mike', 'zebra']);
    });

    test(
        'limit <= 0 returns everything; a positive limit still slices (non-GO '
        'callers)', () {
      final raw = <Ranked<String>>[
        (item: 'b', distanceKm: 2.0),
        (item: 'a', distanceKm: 1.0),
        (item: 'c', distanceKm: 3.0),
      ];
      expect(orderNearest(raw, (s) => s, limit: 0), ['a', 'b', 'c']);
      expect(orderNearest(raw, (s) => s, limit: -5), ['a', 'b', 'c']);
      expect(orderNearest(raw, (s) => s, limit: 2), ['a', 'b']);
    });
  });

  group('/ NO pre-engine decision cap — authority reaches decideGo', () {
    List<Toilet> nOf(int count, IdentityStatus id, {bool flagged = false}) => [
          for (var i = 0; i < count; i++)
            _t(
              'x${i.toString().padLeft(3, '0')}',
              identity: id,
              flagged: flagged,
              lat: (i + 1).toDouble(), // nearer than the 81st
            ),
        ];

    test(
        'CASE A: 80 nearer candidates + an 81st sourceMapped primary => '
        'primary authority is NOT lost, no candidate-only fallback', () {
      final pool = [
        ...nOf(80, IdentityStatus.candidate),
        _t('primary', identity: IdentityStatus.sourceMapped, lat: 500),
      ];
      final d = resolve(pool);
      expect(d.selected!.id, 'primary'); // the only primary
      expect(d.reason, GoReason.nearestWithNoStrongEvidence);
      expect(d.reason, isNot(GoReason.candidateFallback));
      expect(d.requiresConfirmation, isFalse);
    });

    test(
        'CASE B: 80 nearer FLAGGED primaries + an 81st unflagged primary => '
        'the unflagged record reaches decideGo (no flagged-only null)', () {
      final pool = [
        ...nOf(80, IdentityStatus.sourceMapped, flagged: true),
        _t('ok', identity: IdentityStatus.sourceMapped, lat: 900),
      ];
      final d = resolve(pool);
      expect(d.selected, isNotNull);
      expect(d.selected!.id, 'ok');
      expect(d.reason, isNot(GoReason.onlyFlaggedOrUnconfirmedOptions));
    });

    test(
        'CASE C: >80 ordinary sourceMapped records — input order never '
        'determines the winner', () {
      final pool = [
        for (var i = 0; i < 95; i++)
          _t('p${i.toString().padLeft(3, '0')}', lat: (i + 1) * 10.0),
      ];
      final want = resolve(pool).selected!.id;
      final shuffled = [...pool.reversed];
      expect(resolve(shuffled).selected!.id, want);
      final rotated = [...pool.skip(40), ...pool.take(40)];
      expect(resolve(rotated).selected!.id, want);
    });
  });

  group('/ isGoPositionFresh boundaries', () {
    final base = DateTime(2026, 9, 2, 12, 0, 0);
    GeoPos at(Duration ago) => _pos(0, 0, at: base.subtract(ago));

    test(
      '29 s old accepted, exactly 30 s accepted (inclusive), 31 s rejected',
      () {
        expect(
          isGoPositionFresh(
            at(const Duration(seconds: 29)),
            base,
            maxAge: const Duration(seconds: 30),
          ),
          isTrue,
        );
        expect(
          isGoPositionFresh(
            at(const Duration(seconds: 30)),
            base,
            maxAge: const Duration(seconds: 30),
          ),
          isTrue,
        );
        expect(
          isGoPositionFresh(
            at(const Duration(seconds: 31)),
            base,
            maxAge: const Duration(seconds: 30),
          ),
          isFalse,
        );
      },
    );

    test('future timestamp (negative age) rejected', () {
      final future = _pos(0, 0, at: base.add(const Duration(seconds: 5)));
      expect(
        isGoPositionFresh(future, base, maxAge: const Duration(hours: 1)),
        isFalse,
      );
    });

    test(
        'the three GO horizons are distinct and NOT the 60-min evidence '
        'window', () {
      expect(kGoCachedPositionMaxAge, const Duration(seconds: 10));
      expect(kGoLastKnownMaxAge, const Duration(seconds: 30));
      expect(kGoActionableWidgetMaxAge, const Duration(seconds: 30));
    });
  });

  group('goTargetMateriallyWorse', () {
    GoTarget tgt({
      Set<GoCaution> cautions = const {},
      bool confirm = false,
      RecommendationAuthority authority =
          RecommendationAuthority.sourceMappedPrimary,
      OperationalCondition condition = OperationalCondition.unknown,
    }) =>
        (
          toilet: _t('x'),
          distanceMeters: 200,
          authority: authority,
          condition: condition,
          requiresConfirmation: confirm,
          cautions: cautions,
          isSelected: false,
        );

    test('unchanged => not worse; navigation may continue', () {
      expect(goTargetMateriallyWorse(tgt(), tgt()), isFalse);
    });
    test('gained a soft caution => worse', () {
      expect(
        goTargetMateriallyWorse(
          tgt(),
          tgt(cautions: {GoCaution.waterReportedOut}),
        ),
        isTrue,
      );
    });
    test('gained requiresConfirmation => worse', () {
      expect(goTargetMateriallyWorse(tgt(), tgt(confirm: true)), isTrue);
    });
    test('changed authority => worse', () {
      expect(
        goTargetMateriallyWorse(
          tgt(),
          tgt(authority: RecommendationAuthority.candidateFallback),
        ),
        isTrue,
      );
    });
    test('condition moved to a less-favourable class => worse', () {
      expect(
        goTargetMateriallyWorse(
          tgt(condition: OperationalCondition.unknown),
          tgt(condition: OperationalCondition.singleReportedUnavailable),
        ),
        isTrue,
      );
    });
    test('condition became SAFER, and a dropped caution => not worse', () {
      expect(
        goTargetMateriallyWorse(
          tgt(
            condition: OperationalCondition.singleReportedUnavailable,
            cautions: {GoCaution.singleReportUnavailable},
          ),
          tgt(condition: OperationalCondition.corroboratedUsable),
        ),
        isFalse,
      );
    });
  });

  group('goRevalidationOutcome — ONE confirmation, on FRESH metadata', () {
    // Builds a snapshot whose selected (or one alternative) is a candidate
    // requiring confirmation, plus an optional alternative.
    GoResolutionSnapshot snap({
      required bool selConfirm,
      Set<GoCaution> selCautions = const {GoCaution.candidateIdentity},
      OperationalCondition selCond = OperationalCondition.unknown,
      RecommendationAuthority selAuth =
          RecommendationAuthority.candidateFallback,
      List<GoAlternative> alts = const [],
      GoReason reason = GoReason.candidateFallback,
    }) {
      final sel = _t('sel', identity: IdentityStatus.candidate);
      return (
        position: _pos(0, 0),
        now: kNow,
        decision: GoDecision(
          selected: sel,
          selectedDistanceMeters: 120,
          reason: reason,
          requiresConfirmation: selConfirm,
          cautions: selCautions,
          alternatives: alts,
          baselineNearest: sel,
          baselineNearestDistanceMeters: 120,
        ),
      );
    }

    GoAlternative altOf(
      String id, {
      bool confirm = false,
      Set<GoCaution> cautions = const {},
      OperationalCondition cond = OperationalCondition.unknown,
      RecommendationAuthority auth =
          RecommendationAuthority.sourceMappedPrimary,
    }) =>
        GoAlternative(
          toilet: _t(id),
          distanceMeters: 200,
          authority: auth,
          condition: cond,
          requiresConfirmation: confirm,
          cautions: cautions,
        );

    test(
        'A: selected candidate requiring confirmation, fresh unchanged => '
        'confirmThenLaunch (exactly one)', () {
      final s = snap(selConfirm: true);
      expect(
        goRevalidationOutcome(s, s),
        GoRevalidationOutcome.confirmThenLaunch,
      );
    });

    test(
        'B: focused candidate alternative, fresh unchanged => '
        'confirmThenLaunch (one, not two)', () {
      final alt = altOf(
        'altC',
        confirm: true,
        cautions: {GoCaution.candidateIdentity},
        auth: RecommendationAuthority.candidateFallback,
      );
      final s = snap(selConfirm: false, alts: [alt]);
      expect(
        goRevalidationOutcome(s, s, targetId: 'altC'),
        GoRevalidationOutcome.confirmThenLaunch,
      );
    });

    test(
        'C: stale target no confirm, fresh target now requires confirm => '
        'refreshOption (fresh preview before Maps)', () {
      final stale = snap(selConfirm: false, alts: [altOf('altC')]);
      final fresh = snap(
        selConfirm: false,
        alts: [
          altOf('altC', confirm: true, cautions: {GoCaution.candidateIdentity}),
        ],
      );
      expect(
        goRevalidationOutcome(stale, fresh, targetId: 'altC'),
        GoRevalidationOutcome.refreshOption,
      );
    });

    test(
      'D: stale target required confirm, fresh target is SAFER and no longer '
      'requires it => launch (no needless stale confirm)',
      () {
        final stale = snap(
          selConfirm: false,
          alts: [
            altOf(
              'altC',
              confirm: true,
              cautions: {GoCaution.singleReportUnavailable},
              cond: OperationalCondition.singleReportedUnavailable,
            ),
          ],
        );
        final fresh = snap(
          selConfirm: false,
          alts: [altOf('altC', cond: OperationalCondition.corroboratedUsable)],
        );
        expect(
          goRevalidationOutcome(stale, fresh, targetId: 'altC'),
          GoRevalidationOutcome.launch,
        );
      },
    );

    test('E: fresh target gained a soft caution => refreshOption', () {
      final stale = snap(selConfirm: false, alts: [altOf('altC')]);
      final fresh = snap(
        selConfirm: false,
        alts: [
          altOf('altC', cautions: {GoCaution.waterReportedOut}),
        ],
      );
      expect(
        goRevalidationOutcome(stale, fresh, targetId: 'altC'),
        GoRevalidationOutcome.refreshOption,
      );
    });

    test('dropped from active tier => refreshSuggestion', () {
      final stale = snap(selConfirm: false, alts: [altOf('altC')]);
      final fresh = snap(selConfirm: false); // altC gone
      expect(
        goRevalidationOutcome(stale, fresh, targetId: 'altC'),
        GoRevalidationOutcome.refreshSuggestion,
      );
    });

    test(
      'selected-level material change (new winner) => refreshSuggestion',
      () {
        final stale = snap(selConfirm: true);
        final other = _t('other', identity: IdentityStatus.sourceMapped);
        final fresh = (
          position: _pos(0, 0),
          now: kNow,
          decision: GoDecision(
            selected: other,
            selectedDistanceMeters: 90,
            reason: GoReason.nearestWithNoStrongEvidence,
            requiresConfirmation: false,
            cautions: const <GoCaution>{},
            alternatives: const <GoAlternative>[],
            baselineNearest: other,
            baselineNearestDistanceMeters: 90,
          ),
        );
        expect(
          goRevalidationOutcome(stale, fresh),
          GoRevalidationOutcome.refreshSuggestion,
        );
      },
    );

    test('plain fresh selected, no confirmation needed => launch', () {
      final sel = _t('sel');
      final s = (
        position: _pos(0, 0),
        now: kNow,
        decision: GoDecision(
          selected: sel,
          selectedDistanceMeters: 100,
          reason: GoReason.nearestWithNoStrongEvidence,
          requiresConfirmation: false,
          cautions: const <GoCaution>{},
          alternatives: const <GoAlternative>[],
          baselineNearest: sel,
          baselineNearestDistanceMeters: 100,
        ),
      );
      expect(goRevalidationOutcome(s, s), GoRevalidationOutcome.launch);
    });
  });

  group('GoResolutionSnapshot carries the resolution position', () {
    test(
      'runGoFlowLoop returns the exact position the pool was built from',
      () async {
        final origin = _pos(26.9, 75.8); // "Jaipur"
        final r = await runGoFlowLoop(
          acquire: () async => origin,
          loadPool: (_) async => [_t('a', lat: 100)],
          resolve: (pool, pos) => (
            position: pos,
            decision: resolveGo(
              toilets: pool,
              userLat: pos.latitude,
              userLng: pos.longitude,
              now: kNow,
              distance: _fakeDist,
            ),
            now: kNow,
          ),
          showNull: (_) async => GoNullAction.dismiss,
          onError: (_) {},
        );
        expect(r, isNotNull);
        expect(r!.position.latitude, origin.latitude);
        expect(r.position.longitude, origin.longitude);
      },
    );
  });

  group('runGoFlowLoop ', () {
    test(
        'Retry runs a REAL new acquire + pool + resolve, then returns the '
        'second decision', () async {
      var acquireCalls = 0;
      var poolCalls = 0;
      var resolveCalls = 0;
      final flakyPool = _t('later', lat: 100);

      final r = await runGoFlowLoop(
        acquire: () async {
          acquireCalls++;
          return _pos(0, 0);
        },
        loadPool: (pos) async {
          poolCalls++;
          return [flakyPool];
        },
        resolve: (pool, pos) {
          resolveCalls++;
          // First pass: pretend the pool yields no confident suggestion.
          if (resolveCalls == 1) {
            return _snap(
              resolveGo(
                toilets: const <Toilet>[],
                userLat: 0,
                userLng: 0,
                now: kNow,
              ),
            );
          }
          return _snap(
            resolveGo(
              toilets: pool,
              userLat: 0,
              userLng: 0,
              now: kNow,
              distance: _fakeDist,
            ),
          );
        },
        showNull: (d) async => GoNullAction.retry,
        onError: (_) {},
      );

      expect(r, isNotNull);
      expect(r!.decision.selected!.id, 'later');
      // A reentrant implementation would have skipped the second resolution.
      expect(acquireCalls, 2);
      expect(poolCalls, 2);
      expect(resolveCalls, 2);
    });

    test('browse / dismiss ends the loop with null (no preview)', () async {
      for (final action in [GoNullAction.browse, GoNullAction.dismiss]) {
        final r = await runGoFlowLoop(
          acquire: () async => _pos(0, 0),
          loadPool: (_) async => const <Toilet>[],
          resolve: (pool, pos) => _snap(
            resolveGo(
              toilets: const <Toilet>[],
              userLat: 0,
              userLng: 0,
              now: kNow,
            ),
          ),
          showNull: (_) async => action,
          onError: (_) {},
        );
        expect(r, isNull);
      }
    });

    test('null position / null pool => onError, loop returns null', () async {
      var msg = '';
      final r1 = await runGoFlowLoop(
        acquire: () async => null,
        loadPool: (_) async => const <Toilet>[],
        resolve: (p, s) => _snap(resolve(const [])),
        showNull: (_) async => GoNullAction.dismiss,
        onError: (m) => msg = m,
      );
      expect(r1, isNull);
      expect(msg, contains('locate'));

      msg = '';
      final r2 = await runGoFlowLoop(
        acquire: () async => _pos(0, 0),
        loadPool: (_) async => null, // pool load failed
        resolve: (p, s) => _snap(resolve(const [])),
        showNull: (_) async => GoNullAction.dismiss,
        onError: (m) => msg = m,
      );
      expect(r2, isNull);
      expect(msg.toLowerCase(), contains("couldn't"));
    });
  });

  group('resolveHintFocus ', () {
    GoDecision withAlts(List<GoAlternative> alts, {Toilet? selected}) =>
        GoDecision(
          selected: selected ?? _t('sel'),
          selectedDistanceMeters: 120,
          reason: GoReason.nearestWithNoStrongEvidence,
          requiresConfirmation: false,
          cautions: const {},
          alternatives: alts,
          baselineNearest: selected ?? _t('sel'),
          baselineNearestDistanceMeters: 120,
        );

    GoAlternative alt(String id, {IdentityStatus? id2}) => GoAlternative(
          toilet: _t(id, identity: id2 ?? IdentityStatus.sourceMapped),
          distanceMeters: 200,
          authority: id2 == IdentityStatus.candidate
              ? RecommendationAuthority.candidateFallback
              : RecommendationAuthority.sourceMappedPrimary,
          condition: OperationalCondition.unknown,
          requiresConfirmation: id2 == IdentityStatus.candidate,
          cautions: id2 == IdentityStatus.candidate
              ? const {GoCaution.candidateIdentity}
              : const {},
        );

    test('valid fresh alternative hint => focus that alternative', () {
      final d = withAlts([alt('altB')]);
      final f = resolveHintFocus(d, 'altB', now: kNow);
      expect(f, isNotNull);
      expect(f!.toilet.id, 'altB');
      expect(f.isSelected, isFalse);
    });
    test('hint that is the fresh SELECTED => null (normal preview)', () {
      final d = withAlts([alt('altB')]);
      expect(resolveHintFocus(d, 'sel', now: kNow), isNull);
    });
    test('stale hint absent from the active tier => null', () {
      final d = withAlts([alt('altB')]);
      expect(resolveHintFocus(d, 'ghost', now: kNow), isNull);
    });
    test('empty / null hint => null', () {
      final d = withAlts([alt('altB')]);
      expect(resolveHintFocus(d, null, now: kNow), isNull);
      expect(resolveHintFocus(d, '', now: kNow), isNull);
    });
  });

  group(
    'findInActiveTier + goAlternativeFromTarget ',
    () {
      test(
        'selected target derives REAL authority + condition (not guessed)',
        () {
          final sel = _t('sel', evidence: _cond(cc: 3, usable: (0, 3)));
          final fresh = GoDecision(
            selected: sel,
            selectedDistanceMeters: 120,
            reason: GoReason.bestMappedOptionCorroboratedUnavailable,
            requiresConfirmation: true,
            cautions: const {GoCaution.corroboratedUnavailable},
            alternatives: const [],
            baselineNearest: sel,
            baselineNearestDistanceMeters: 120,
          );
          final target = findInActiveTier(fresh, 'sel', now: kNow)!;
          expect(target.authority, RecommendationAuthority.sourceMappedPrimary);
          expect(
            target.condition,
            OperationalCondition.corroboratedUnavailable,
          );
        },
      );

      test(
        'a CANDIDATE alternative target stays candidate, never community',
        () {
          final cand = GoAlternative(
            toilet: _t('c', identity: IdentityStatus.candidate),
            distanceMeters: 150,
            authority: RecommendationAuthority.candidateFallback,
            condition: OperationalCondition.unknown,
            requiresConfirmation: true,
            cautions: const {GoCaution.candidateIdentity},
          );
          final fresh = GoDecision(
            selected: _t('sel'),
            selectedDistanceMeters: 100,
            reason: GoReason.nearestWithNoStrongEvidence,
            requiresConfirmation: false,
            cautions: const {},
            alternatives: [cand],
            baselineNearest: _t('sel'),
            baselineNearestDistanceMeters: 100,
          );
          final target = findInActiveTier(fresh, 'c', now: kNow)!;
          expect(target.authority, RecommendationAuthority.candidateFallback);
          final asAlt = goAlternativeFromTarget(target);
          expect(asAlt.authority, RecommendationAuthority.candidateFallback);
          expect(
            asAlt.authority,
            isNot(RecommendationAuthority.communityFallback),
          );
        },
      );

      test('unknown id => null', () {
        final fresh = GoDecision(
          selected: _t('sel'),
          selectedDistanceMeters: 100,
          reason: GoReason.nearestWithNoStrongEvidence,
          requiresConfirmation: false,
          cautions: const {},
          alternatives: const [],
          baselineNearest: _t('sel'),
          baselineNearestDistanceMeters: 100,
        );
        expect(findInActiveTier(fresh, 'ghost', now: kNow), isNull);
      });
    },
  );

  group('goResultMateriallyChanged ', () {
    GoDecision mk({
      String? id,
      bool confirm = false,
      Set<GoCaution> cautions = const {},
      GoReason reason = GoReason.nearestWithNoStrongEvidence,
    }) =>
        GoDecision(
          selected: id == null ? null : _t(id),
          selectedDistanceMeters: id == null ? null : 100,
          reason: reason,
          requiresConfirmation: confirm,
          cautions: cautions,
          alternatives: const [],
          baselineNearest: id == null ? null : _t(id),
          baselineNearestDistanceMeters: id == null ? null : 100,
        );

    test(
        'same id + contract => not changed; new id / confirm / caution => '
        'changed', () {
      expect(goResultMateriallyChanged(mk(id: 'a'), mk(id: 'a')), isFalse);
      expect(goResultMateriallyChanged(mk(id: 'a'), mk(id: 'b')), isTrue);
      expect(goResultMateriallyChanged(mk(id: 'a'), mk()), isTrue);
      expect(
        goResultMateriallyChanged(mk(id: 'a'), mk(id: 'a', confirm: true)),
        isTrue,
      );
      expect(
        goResultMateriallyChanged(
          mk(id: 'a'),
          mk(id: 'a', cautions: {GoCaution.singleReportUnavailable}),
        ),
        isTrue,
      );
    });
    test('a weaker caution set alone => not changed', () {
      expect(
        goResultMateriallyChanged(
          mk(id: 'a', cautions: {GoCaution.waterReportedOut}),
          mk(id: 'a'),
        ),
        isFalse,
      );
    });
  });

  group('goWidgetPayload ', () {
    String fmt(double m) => '${m.round()}m';

    test('clean selected: dist line carries the compact GO status', () {
      final d = GoDecision(
        selected: _t('sel', evidence: _cond(cc: 2, usable: (2, 0))),
        selectedDistanceMeters: 120,
        reason: GoReason.recentCorroboratedUsableWithinDetour,
        requiresConfirmation: false,
        cautions: const {},
        alternatives: const [],
        baselineNearest: _t('sel'),
        baselineNearestDistanceMeters: 120,
      );
      final p = goWidgetPayload(
        d,
        updatedLabel: 'Suggestion updated 4:20 PM',
        now: kNow,
        formatMeters: fmt,
      );
      expect(p['nearest_loo_dist'], '120m · Recent checks indicate usable');
      expect(p['med_1_dist'], '120m · Recent checks indicate usable');
      expect(p['last_updated'], isNot(contains('verified')));
    });

    test(
      'a requires-confirmation candidate selection is NOT shown as clean',
      () {
        final d = GoDecision(
          selected: _t('sel', identity: IdentityStatus.candidate),
          selectedDistanceMeters: 120,
          reason: GoReason.candidateFallback,
          requiresConfirmation: true,
          cautions: const {GoCaution.candidateIdentity},
          alternatives: const [],
          baselineNearest: _t('sel'),
          baselineNearestDistanceMeters: 120,
        );
        final p = goWidgetPayload(
          d,
          updatedLabel: 'x',
          now: kNow,
          formatMeters: fmt,
        );
        expect(p['nearest_loo_dist'], contains('Unconfirmed location'));
      },
    );

    test('a corroborated-unavailable selection warns "check first"', () {
      final d = GoDecision(
        selected: _t('sel', evidence: _cond(cc: 3, usable: (0, 3))),
        selectedDistanceMeters: 120,
        reason: GoReason.bestMappedOptionCorroboratedUnavailable,
        requiresConfirmation: true,
        cautions: const {GoCaution.corroboratedUnavailable},
        alternatives: const [],
        baselineNearest: _t('sel'),
        baselineNearestDistanceMeters: 120,
      );
      final p = goWidgetPayload(
        d,
        updatedLabel: 'x',
        now: kNow,
        formatMeters: fmt,
      );
      expect(p['nearest_loo_dist'], contains('check first'));
    });

    test(
      'medium rows: row1==selected, row2 from alternatives, both statused',
      () {
        final d = GoDecision(
          selected: _t('sel'),
          selectedDistanceMeters: 120,
          reason: GoReason.nearestWithNoStrongEvidence,
          requiresConfirmation: false,
          cautions: const {},
          alternatives: [
            GoAlternative(
              toilet: _t('altA'),
              distanceMeters: 200,
              authority: RecommendationAuthority.sourceMappedPrimary,
              condition: OperationalCondition.singleReportedUnavailable,
              requiresConfirmation: false,
              cautions: const {GoCaution.singleReportUnavailable},
            ),
          ],
          baselineNearest: _t('sel'),
          baselineNearestDistanceMeters: 120,
        );
        final p = goWidgetPayload(
          d,
          updatedLabel: 'x',
          now: kNow,
          formatMeters: fmt,
        );
        expect(p['med_1_id'], 'sel');
        expect(p['med_1_dist'], contains('Status unconfirmed'));
        expect(p['med_2_id'], 'altA');
        expect(p['med_2_dist'], contains('Recent warning'));
        expect(p['med_3_id'], '');
      },
    );

    test(
      'selected == null => every id/name cleared, "No current suggestion"',
      () {
        final p = goWidgetPayload(
          GoDecision(
            selected: null,
            selectedDistanceMeters: null,
            reason: GoReason.onlyFlaggedOrUnconfirmedOptions,
            requiresConfirmation: false,
            cautions: const {GoCaution.moderationFlagged},
            alternatives: const [],
            baselineNearest: null,
            baselineNearestDistanceMeters: null,
          ),
          updatedLabel: 'x',
          now: kNow,
          formatMeters: fmt,
        );
        expect(p['toilet_id'], '');
        expect(p['nearest_loo_name'], 'No current suggestion');
        for (final i in [1, 2, 3]) {
          expect(p['med_${i}_id'], '');
          expect(p['med_${i}_dist'], '');
        }
      },
    );

    test(
      'goWidgetUnavailablePayload clears everything with an honest message',
      () {
        final p = goWidgetUnavailablePayload(
          updatedLabel: 'x',
          message: 'Open ShauchMap to refresh',
        );
        expect(p['nearest_loo_name'], 'Open ShauchMap to refresh');
        expect(p['toilet_id'], '');
        expect(p['med_1_name'], 'Open ShauchMap to refresh');
        expect(p['med_2_name'], '');
        for (final i in [1, 2, 3]) {
          expect(p['med_${i}_id'], '');
        }
      },
    );
  });
}
