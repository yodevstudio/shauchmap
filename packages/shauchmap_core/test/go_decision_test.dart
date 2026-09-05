// GO V2 pure recommendation engine. Locks down identity authority,
// operational-evidence classes, corroboration, conflicts, the transparent
// detour guard, determinism, and the metamorphic invariants (ratings/votes/
// static attributes never affect the decision; candidacy/expiry never
// strengthen authority).

import 'dart:math';

import 'package:shauchmap_core/shauchmap_core.dart';
import 'package:test/test.dart';

final DateTime kNow = DateTime(2026, 9, 2, 12, 0, 0);
Instant _ts(DateTime d) => Instant.fromDateTime(d);

ToiletTruth _truth(
  IdentityStatus id, {
  FeeState fee = FeeState.unknown,
  ToiletAmenities amenities = ToiletAmenities.allUnknown,
}) =>
    ToiletTruth(
      schemaVersion: id == IdentityStatus.communitySubmitted ? 2 : 1,
      source: switch (id) {
        IdentityStatus.sourceMapped => ToiletSource.osm,
        IdentityStatus.candidate => ToiletSource.osm,
        IdentityStatus.communitySubmitted => ToiletSource.communitySubmission,
        IdentityStatus.unknown => ToiletSource.unknown,
      },
      recordedAt: null,
      context: FacilityContext.unknown,
      gender: GenderAccess.unknown,
      identityStatus: id,
      fee: fee,
      amenities: amenities,
      isNativeV2: id == IdentityStatus.communitySubmitted,
    );

/// Build a valid server condition-evidence map. Per dimension pass `(yes, no)`;
/// `unknown` is filled to make every dimension sum to [cc].
ToiletEvidence _cond({
  required int cc,
  (int, int) open = (0, 0),
  (int, int) usable = (0, 0),
  (int, int) water = (0, 0),
  (int, int) lock = (0, 0),
  Duration validFor = const Duration(minutes: 40),
  DateTime? now,
}) {
  final n = now ?? kNow;
  String verdict((int, int) s) =>
      s.$1 > s.$2 ? 'yes' : (s.$2 > s.$1 ? 'no' : 'unknown');
  Map<String, int> sup((int, int) s) => {
        'yes': s.$1,
        'no': s.$2,
        'unknown': cc - s.$1 - s.$2,
      };
  if (cc == 0) {
    return ToiletEvidence.fromFirestore({
      'version': 1,
      'condition': {
        'open': 'unknown',
        'water': 'unknown',
        'usable': 'unknown',
        'lock': 'unknown',
        'contributor_count': 0,
        'computed_at': _ts(n.subtract(const Duration(seconds: 5))),
        'last_event_at': _ts(n.subtract(const Duration(seconds: 6))),
        'support': {
          'open': {'yes': 0, 'no': 0, 'unknown': 0},
          'water': {'yes': 0, 'no': 0, 'unknown': 0},
          'usable': {'yes': 0, 'no': 0, 'unknown': 0},
          'lock': {'yes': 0, 'no': 0, 'unknown': 0},
        },
      },
    });
  }
  return ToiletEvidence.fromFirestore({
    'version': 1,
    'condition': {
      'open': verdict(open),
      'water': verdict(water),
      'usable': verdict(usable),
      'lock': verdict(lock),
      'contributor_count': cc,
      'latest_at': _ts(n.subtract(const Duration(minutes: 5))),
      'valid_until': _ts(n.add(validFor)),
      'computed_at': _ts(n.subtract(const Duration(seconds: 5))),
      'last_event_at': _ts(n.subtract(const Duration(seconds: 6))),
      'support': {
        'open': sup(open),
        'water': sup(water),
        'usable': sup(usable),
        'lock': sup(lock),
      },
    },
  });
}

int _idc = 0;
Toilet _toilet({
  String? id,
  IdentityStatus identity = IdentityStatus.sourceMapped,
  bool flagged = false,
  ToiletEvidence? evidence,
  ToiletTruth? truth,
  double starRating = 0,
  int totalRatings = 0,
  int upvoteCount = 0,
  int downvoteCount = 0,
  bool isFree = true,
  bool hasWater = false,
  bool? flaggedRaw,
  Object? flaggedUntil = _unset,
}) =>
    Toilet(
      id: id ?? 't${(_idc++).toString().padLeft(3, '0')}',
      name: 'T',
      address: 'A',
      latitude: 26.3,
      longitude: 73.1,
      category: 'govt',
      starRating: starRating,
      totalRatings: totalRatings,
      isOpen: true,
      isFree: isFree,
      genderType: 'unisex',
      hasWater: hasWater,
      hasSoap: false,
      hasLock: false,
      isWheelchair: false,
      hasBabyChange: false,
      hasSanitaryDisposal: false,
      isWestern: false,
      womenSafeFlag: false,
      flaggedRaw: flaggedRaw ?? flagged,
      flaggedUntil: identical(flaggedUntil, _unset)
          ? (flagged ? DateTime(3000) : null)
          : flaggedUntil as DateTime?,
      addedBy: 'x',
      upvoteCount: upvoteCount,
      downvoteCount: downvoteCount,
      truth: truth ?? _truth(identity),
      evidence: evidence ?? ToiletEvidence.unavailable,
    );

const Object _unset = Object();

GoInput _in(Toilet t, double d) => GoInput(t, d);

void main() {
  group('basics', () {
    test('no toilets => NO_TOILETS, selected null', () {
      final d = decideGo([], now: kNow);
      expect(d.selected, isNull);
      expect(d.reason, GoReason.noToilets);
    });

    test('one source-mapped unknown => it wins, no strong evidence', () {
      final t = _toilet(id: 'only');
      final d = decideGo([_in(t, 120)], now: kNow);
      expect(d.selected!.id, 'only');
      expect(d.reason, GoReason.nearestWithNoStrongEvidence);
      expect(d.requiresConfirmation, isFalse);
      expect(d.cautions, isEmpty);
    });

    test('distance ordering: nearest source-mapped wins', () {
      final a = _toilet(id: 'a');
      final b = _toilet(id: 'b');
      final d = decideGo([_in(b, 300), _in(a, 100)], now: kNow);
      expect(d.selected!.id, 'a');
      expect(d.baselineNearest!.id, 'a');
    });

    test('deterministic tie-break: equal distance => lexical toilet id', () {
      final a = _toilet(id: 'aaa');
      final b = _toilet(id: 'bbb');
      final d1 = decideGo([_in(b, 200), _in(a, 200)], now: kNow);
      final d2 = decideGo([_in(a, 200), _in(b, 200)], now: kNow);
      expect(d1.selected!.id, 'aaa');
      expect(d2.selected!.id, 'aaa');
    });

    test('non-finite distance is dropped', () {
      final a = _toilet(id: 'a');
      final b = _toilet(id: 'b');
      final d = decideGo([_in(a, double.nan), _in(b, 500)], now: kNow);
      expect(d.selected!.id, 'b');
    });

    test('expired evidence ranks exactly as unknown', () {
      final expired = _toilet(
        id: 'exp',
        evidence: _cond(
          cc: 3,
          usable: (3, 0),
          validFor: const Duration(minutes: -1),
        ),
      );
      final near = _toilet(id: 'near');
      // "near" at 100, expired-corroborated at 150 -> near wins (expired == unknown).
      final d = decideGo([_in(expired, 150), _in(near, 100)], now: kNow);
      expect(d.selected!.id, 'near');
      expect(d.reason, GoReason.nearestWithNoStrongEvidence);
    });

    test('unavailable evidence index ranks as unknown', () {
      final a = _toilet(id: 'a'); // ToiletEvidence.unavailable
      final b = _toilet(id: 'b');
      final d = decideGo([_in(a, 100), _in(b, 130)], now: kNow);
      expect(d.selected!.id, 'a');
    });
  });

  group('evidence strength classification', () {
    test(
      '1 yes + 3 unknown => singleClear (not four-person corroboration)',
      () {
        expect(
          classifyEvidenceStrength(const EvidenceSupport(1, 0, 3)),
          EvidenceStrength.singleClear,
        );
      },
    );
    test('2 yes + 0 no => corroboratedClear', () {
      expect(
        classifyEvidenceStrength(const EvidenceSupport(2, 0, 0)),
        EvidenceStrength.corroboratedClear,
      );
    });
    test('2 yes + 1 no => conflictedMajority (NOT clear corroboration)', () {
      expect(
        classifyEvidenceStrength(const EvidenceSupport(2, 1, 0)),
        EvidenceStrength.conflictedMajority,
      );
    });
    test('1 yes + 1 no => tied', () {
      expect(
        classifyEvidenceStrength(const EvidenceSupport(1, 1, 0)),
        EvidenceStrength.tied,
      );
    });
    test('0/0/2 => unknownOnly; 0/0/0 => none', () {
      expect(
        classifyEvidenceStrength(const EvidenceSupport(0, 0, 2)),
        EvidenceStrength.unknownOnly,
      );
      expect(
        classifyEvidenceStrength(const EvidenceSupport(0, 0, 0)),
        EvidenceStrength.none,
      );
    });
  });

  group('positive evidence policy', () {
    test(
      'EX1: A 200 unknown, B 250 SINGLE usable => A (no detour authority)',
      () {
        final a = _toilet(id: 'a');
        final b = _toilet(
          id: 'b',
          evidence: _cond(cc: 1, usable: (1, 0)),
        );
        final d = decideGo([_in(a, 200), _in(b, 250)], now: kNow);
        expect(d.selected!.id, 'a');
        expect(d.reason, GoReason.nearestWithNoStrongEvidence);
      },
    );

    test(
      'EX2: A 200 unknown, B 250 corroborated usable => B (within caps)',
      () {
        final a = _toilet(id: 'a');
        final b = _toilet(
          id: 'b',
          evidence: _cond(cc: 2, usable: (2, 0)),
        );
        final d = decideGo([_in(a, 200), _in(b, 250)], now: kNow);
        expect(d.selected!.id, 'b');
        expect(d.reason, GoReason.recentCorroboratedUsableWithinDetour);
      },
    );

    test(
      'EX3: A 200 unknown, B 500 corroborated usable => A (ratio 2.5x fail)',
      () {
        final a = _toilet(id: 'a');
        final b = _toilet(
          id: 'b',
          evidence: _cond(cc: 2, usable: (2, 0)),
        );
        final d = decideGo([_in(a, 200), _in(b, 500)], now: kNow);
        expect(d.selected!.id, 'a');
      },
    );

    test(
      'EX4: A 1000 unknown, B 1350 corroborated usable => B (+350, 1.35x)',
      () {
        final a = _toilet(id: 'a');
        final b = _toilet(
          id: 'b',
          evidence: _cond(cc: 3, usable: (3, 0)),
        );
        final d = decideGo([_in(a, 1000), _in(b, 1350)], now: kNow);
        expect(d.selected!.id, 'b');
      },
    );

    test(
      'EX5: A 1000 unknown, B 1450 corroborated usable => A (+450 abs fail)',
      () {
        final a = _toilet(id: 'a');
        final b = _toilet(
          id: 'b',
          evidence: _cond(cc: 3, usable: (3, 0)),
        );
        final d = decideGo([_in(a, 1000), _in(b, 1450)], now: kNow);
        expect(d.selected!.id, 'a');
      },
    );

    test('conflicted usable majority does NOT get corroborated promotion', () {
      final a = _toilet(id: 'a');
      final b = _toilet(
        id: 'b',
        evidence: _cond(cc: 3, usable: (2, 1)),
      );
      final d = decideGo([_in(a, 200), _in(b, 240)], now: kNow);
      expect(d.selected!.id, 'a');
    });

    test('open yes + usable unknown is NOT a usability confirmation', () {
      final b = _toilet(
        id: 'b',
        evidence: _cond(cc: 3, open: (3, 0), usable: (0, 0)),
      );
      final a = _toilet(id: 'a');
      final d = decideGo([_in(a, 200), _in(b, 260)], now: kNow);
      expect(d.selected!.id, 'a'); // b's condition is UNKNOWN operationally
    });

    test(
      'a corroborated-usable baseline wins as nearest, reason reflects it',
      () {
        final a = _toilet(
          id: 'a',
          evidence: _cond(cc: 2, usable: (2, 0)),
        );
        final b = _toilet(id: 'b');
        final d = decideGo([_in(a, 100), _in(b, 400)], now: kNow);
        expect(d.selected!.id, 'a');
        expect(d.reason, GoReason.recentCorroboratedUsableWithinDetour);
      },
    );
  });

  group('boundary caps', () {
    test('+400m exactly => within (promotion allowed)', () {
      final a = _toilet(id: 'a');
      final b = _toilet(
        id: 'b',
        evidence: _cond(cc: 2, usable: (2, 0)),
      );
      final d = decideGo([_in(a, 1000), _in(b, 1400)], now: kNow);
      expect(d.selected!.id, 'b'); // 400 <= 400, 1400 <= 1500
    });
    test('+401m => outside absolute cap', () {
      final a = _toilet(id: 'a');
      final b = _toilet(
        id: 'b',
        evidence: _cond(cc: 2, usable: (2, 0)),
      );
      final d = decideGo([_in(a, 1000), _in(b, 1401)], now: kNow);
      expect(d.selected!.id, 'a');
    });
    test('exactly 1.5x => within', () {
      final a = _toilet(id: 'a');
      final b = _toilet(
        id: 'b',
        evidence: _cond(cc: 2, usable: (2, 0)),
      );
      final d = decideGo([_in(a, 200), _in(b, 300)], now: kNow);
      expect(d.selected!.id, 'b'); // 100 <= 400, 300 <= 300
    });
    test('just over 1.5x => outside ratio cap', () {
      final a = _toilet(id: 'a');
      final b = _toilet(
        id: 'b',
        evidence: _cond(cc: 2, usable: (2, 0)),
      );
      final d = decideGo([_in(a, 200), _in(b, 301)], now: kNow);
      expect(d.selected!.id, 'a');
    });
    test('validUntil exact boundary => UNKNOWN (not usable)', () {
      // valid_until == now  => isCurrentlyValid false => unknown.
      final b = _toilet(
        id: 'b',
        evidence: _cond(cc: 2, usable: (2, 0), validFor: Duration.zero),
      );
      final a = _toilet(id: 'a');
      final d = decideGo([_in(a, 200), _in(b, 250)], now: kNow);
      expect(d.selected!.id, 'a');
    });
  });

  group('negative evidence policy', () {
    test(
      'EX6: A 200 corroborated-unavailable, B 250 unknown => B (avoided)',
      () {
        final a = _toilet(
          id: 'a',
          evidence: _cond(cc: 2, usable: (0, 2)),
        );
        final b = _toilet(id: 'b');
        final d = decideGo([_in(a, 200), _in(b, 250)], now: kNow);
        expect(d.selected!.id, 'b');
        expect(d.reason, GoReason.avoidedRecentCorroboratedUnavailable);
      },
    );

    test(
      'corroborated-unavailable and NO reasonable alternative => confirm',
      () {
        final a = _toilet(
          id: 'a',
          evidence: _cond(cc: 3, usable: (0, 3)),
        );
        // B far outside detour.
        final b = _toilet(id: 'b');
        final d = decideGo([_in(a, 200), _in(b, 900)], now: kNow);
        expect(d.selected!.id, 'a');
        expect(d.reason, GoReason.bestMappedOptionCorroboratedUnavailable);
        expect(d.requiresConfirmation, isTrue);
        expect(d.cautions, contains(GoCaution.corroboratedUnavailable));
      },
    );

    test(
      'EX7: A 200 SINGLE-unavailable, B 250 unknown => A (no global veto)',
      () {
        final a = _toilet(
          id: 'a',
          evidence: _cond(cc: 1, usable: (0, 1)),
        );
        final b = _toilet(id: 'b');
        final d = decideGo([_in(a, 200), _in(b, 250)], now: kNow);
        expect(d.selected!.id, 'a');
        expect(d.reason, GoReason.singleNegativeWarning);
        expect(d.cautions, contains(GoCaution.singleReportUnavailable));
        expect(d.requiresConfirmation, isFalse);
      },
    );

    test(
      'EX8: 2 NO + 1 YES usable => CONFLICTED, not corroborated; A stays',
      () {
        final a = _toilet(
          id: 'a',
          evidence: _cond(cc: 3, usable: (1, 2)),
        );
        final b = _toilet(id: 'b');
        final d = decideGo([_in(a, 200), _in(b, 230)], now: kNow);
        expect(d.selected!.id, 'a');
        expect(d.reason, GoReason.conflictedNegativeWarning);
        expect(d.cautions, contains(GoCaution.conflictedUnavailable));
        // and it is NOT treated as corroborated: no confirmation required.
        expect(d.requiresConfirmation, isFalse);
      },
    );

    test('contradiction: usable=yes + open=no => operationally negative', () {
      final a = _toilet(
        id: 'a',
        evidence: _cond(cc: 2, usable: (2, 0), open: (0, 2)),
      );
      final b = _toilet(id: 'b');
      final d = decideGo([_in(a, 200), _in(b, 240)], now: kNow);
      // A is corroborated-unavailable via open=no; B (unknown) is chosen.
      expect(d.selected!.id, 'b');
      expect(d.reason, GoReason.avoidedRecentCorroboratedUnavailable);
    });

    test('water=no alone does NOT veto or force confirmation', () {
      final a = _toilet(
        id: 'a',
        evidence: _cond(cc: 2, usable: (2, 0), water: (0, 2)),
      );
      final b = _toilet(id: 'b');
      final d = decideGo([_in(a, 100), _in(b, 400)], now: kNow);
      expect(d.selected!.id, 'a'); // still usable + nearest
      expect(d.cautions, contains(GoCaution.waterReportedOut));
      expect(d.requiresConfirmation, isFalse);
    });
  });

  group('identity authority', () {
    test(
      'sourceMapped is primary; nearer uncorroborated community does NOT win',
      () {
        final sm = _toilet(id: 'sm', identity: IdentityStatus.sourceMapped);
        final cs = _toilet(
          id: 'cs',
          identity: IdentityStatus.communitySubmitted,
        );
        final d = decideGo([_in(cs, 200), _in(sm, 300)], now: kNow);
        expect(d.selected!.id, 'sm');
        expect(d.reason, GoReason.nearestWithNoStrongEvidence);
      },
    );

    test(
      'community submitted WITH corroborated usable => normal eligibility',
      () {
        final cs = _toilet(
          id: 'cs',
          identity: IdentityStatus.communitySubmitted,
          evidence: _cond(cc: 2, usable: (2, 0)),
        );
        final sm = _toilet(id: 'sm', identity: IdentityStatus.sourceMapped);
        final d = decideGo([_in(cs, 200), _in(sm, 300)], now: kNow);
        expect(d.selected!.id, 'cs'); // nearest AND primary-eligible
      },
    );

    test('candidate is NEVER primary, even with 5 usable condition checks', () {
      final cand = _toilet(
        id: 'cand',
        identity: IdentityStatus.candidate,
        evidence: _cond(cc: 5, usable: (5, 0)),
      );
      final sm = _toilet(id: 'sm', identity: IdentityStatus.sourceMapped);
      final d = decideGo([_in(cand, 100), _in(sm, 900)], now: kNow);
      expect(d.selected!.id, 'sm'); // sm is the only primary
      expect(d.reason, GoReason.nearestWithNoStrongEvidence);
    });

    test('candidate-only pool => candidate fallback, requiresConfirmation', () {
      final cand = _toilet(id: 'cand', identity: IdentityStatus.candidate);
      final d = decideGo([_in(cand, 120)], now: kNow);
      expect(d.selected!.id, 'cand');
      expect(d.reason, GoReason.candidateFallback);
      expect(d.requiresConfirmation, isTrue);
      expect(d.cautions, contains(GoCaution.candidateIdentity));
    });

    test(
      'community-only uncorroborated pool => community fallback + confirm',
      () {
        final cs = _toilet(
          id: 'cs',
          identity: IdentityStatus.communitySubmitted,
        );
        final d = decideGo([_in(cs, 150)], now: kNow);
        expect(d.selected!.id, 'cs');
        expect(d.reason, GoReason.communitySubmissionFallback);
        expect(d.requiresConfirmation, isTrue);
      },
    );

    test('unknown identity only => candidate-tier fallback + confirm', () {
      final u = _toilet(id: 'u', identity: IdentityStatus.unknown);
      final d = decideGo([_in(u, 150)], now: kNow);
      expect(d.selected!.id, 'u');
      expect(d.reason, GoReason.candidateFallback);
      expect(d.cautions, contains(GoCaution.unknownIdentity));
    });

    test('community fallback tier is preferred over candidate tier', () {
      final cs = _toilet(id: 'cs', identity: IdentityStatus.communitySubmitted);
      final cand = _toilet(id: 'cand', identity: IdentityStatus.candidate);
      // candidate is closer, but community tier wins first.
      final d = decideGo([_in(cand, 100), _in(cs, 400)], now: kNow);
      expect(d.selected!.id, 'cs');
      expect(d.reason, GoReason.communitySubmissionFallback);
    });

    test('flagged toilet is excluded from automatic recommendation', () {
      final flag = _toilet(id: 'flag', flagged: true);
      final sm = _toilet(id: 'sm', identity: IdentityStatus.sourceMapped);
      final d = decideGo([_in(flag, 100), _in(sm, 500)], now: kNow);
      expect(d.selected!.id, 'sm');
    });

    test(
      'only flagged options => no confident recommendation, NO alternatives',
      () {
        final f1 = _toilet(id: 'f1', flagged: true);
        final f2 = _toilet(id: 'f2', flagged: true);
        final d = decideGo([_in(f1, 100), _in(f2, 200)], now: kNow);
        expect(d.selected, isNull);
        expect(d.reason, GoReason.onlyFlaggedOrUnconfirmedOptions);
        // a moderation-flagged toilet is never offered as an
        // actionable alternative.
        expect(d.alternatives, isEmpty);
        expect(d.baselineNearest, isNull);
      },
    );
  });

  group('METAMORPHIC: opinion & static attributes never move the winner', () {
    List<GoInput> basePool() => [
          _in(_toilet(id: 'a'), 200),
          _in(
            _toilet(
              id: 'b',
              evidence: _cond(cc: 2, usable: (2, 0)),
            ),
            250,
          ),
          _in(
            _toilet(
              id: 'c',
              evidence: _cond(cc: 1, usable: (0, 1)),
            ),
            240,
          ),
        ];

    test('changing ONLY ratings cannot change the selected id', () {
      final before = decideGo(basePool(), now: kNow).selected!.id;
      final loaded = [
        _in(_toilet(id: 'a', starRating: 4.9, totalRatings: 999), 200),
        _in(
          _toilet(
            id: 'b',
            starRating: 1.1,
            totalRatings: 5,
            evidence: _cond(cc: 2, usable: (2, 0)),
          ),
          250,
        ),
        _in(
          _toilet(
            id: 'c',
            starRating: 5.0,
            totalRatings: 42,
            evidence: _cond(cc: 1, usable: (0, 1)),
          ),
          240,
        ),
      ];
      expect(decideGo(loaded, now: kNow).selected!.id, before);
    });

    test('changing ONLY votes cannot change the selected id', () {
      final before = decideGo(basePool(), now: kNow).selected!.id;
      final voted = [
        _in(_toilet(id: 'a', upvoteCount: 0, downvoteCount: 50), 200),
        _in(
          _toilet(
            id: 'b',
            upvoteCount: 99,
            downvoteCount: 0,
            evidence: _cond(cc: 2, usable: (2, 0)),
          ),
          250,
        ),
        _in(
          _toilet(
            id: 'c',
            upvoteCount: 0,
            downvoteCount: 99,
            evidence: _cond(cc: 1, usable: (0, 1)),
          ),
          240,
        ),
      ];
      expect(decideGo(voted, now: kNow).selected!.id, before);
    });

    test('changing ONLY fee cannot change the generic winner', () {
      final a = _toilet(id: 'a', isFree: true);
      final b = _toilet(id: 'b', isFree: true);
      final w1 = decideGo([_in(a, 100), _in(b, 130)], now: kNow).selected!.id;
      final a2 = _toilet(
        id: 'a',
        truth: _truth(IdentityStatus.sourceMapped, fee: FeeState.paid),
      );
      final b2 = _toilet(
        id: 'b',
        truth: _truth(IdentityStatus.sourceMapped, fee: FeeState.free),
      );
      expect(
        decideGo([_in(a2, 100), _in(b2, 130)], now: kNow).selected!.id,
        w1,
      );
    });

    test('changing ONLY amenity listings cannot change the generic winner', () {
      final present = const ToiletAmenities(
        water: EvidenceState.present,
        soap: EvidenceState.present,
        lock: EvidenceState.present,
        western: EvidenceState.present,
        wheelchair: EvidenceState.present,
        babyChange: EvidenceState.present,
        sanitaryDisposal: EvidenceState.present,
      );
      final a = _toilet(id: 'a');
      final b = _toilet(id: 'b');
      final w1 = decideGo([_in(a, 100), _in(b, 130)], now: kNow).selected!.id;
      final a2 = _toilet(
        id: 'a',
        truth: _truth(IdentityStatus.sourceMapped, amenities: present),
      );
      expect(decideGo([_in(a2, 100), _in(b, 130)], now: kNow).selected!.id, w1);
    });
  });

  // ============================================================
  group('/ escape-pool policy for a corroborated-unavailable baseline', () {
    test(
        'D: baseline corr-unavailable, escape B SINGLE-unavailable within '
        'detour => B, avoided reason, singleReportUnavailable caution, no '
        'confirm', () {
      final a = _toilet(
        id: 'a',
        evidence: _cond(cc: 2, usable: (0, 2)),
      );
      final b = _toilet(
        id: 'b',
        evidence: _cond(cc: 1, usable: (0, 1)),
      );
      final d = decideGo([_in(a, 200), _in(b, 250)], now: kNow);
      expect(d.selected!.id, 'b');
      expect(d.reason, GoReason.avoidedRecentCorroboratedUnavailable);
      expect(d.cautions, contains(GoCaution.singleReportUnavailable));
      expect(d.cautions, isNot(contains(GoCaution.corroboratedUnavailable)));
      expect(d.requiresConfirmation, isFalse);
      // baseline reported is the ORIGINAL nearest primary, not the replacement.
      expect(d.baselineNearest!.id, 'a');
      expect(d.baselineNearestDistanceMeters, 200);
    });

    test(
        'D2: escape B CONFLICTED-unavailable within detour => B, '
        'conflictedUnavailable caution, no confirm', () {
      final a = _toilet(
        id: 'a',
        evidence: _cond(cc: 3, usable: (0, 3)),
      );
      final b = _toilet(
        id: 'b',
        evidence: _cond(cc: 3, usable: (1, 2)),
      );
      final d = decideGo([_in(a, 200), _in(b, 250)], now: kNow);
      expect(d.selected!.id, 'b');
      expect(d.reason, GoReason.avoidedRecentCorroboratedUnavailable);
      expect(d.cautions, contains(GoCaution.conflictedUnavailable));
      expect(d.requiresConfirmation, isFalse);
    });

    test(
        'E: escape B CORROBORATED-usable within detour => B, corroborated '
        'reason, no unavailable caution', () {
      final a = _toilet(
        id: 'a',
        evidence: _cond(cc: 2, usable: (0, 2)),
      );
      final b = _toilet(
        id: 'b',
        evidence: _cond(cc: 2, usable: (2, 0)),
      );
      final d = decideGo([_in(a, 200), _in(b, 250)], now: kNow);
      expect(d.selected!.id, 'b');
      expect(d.reason, GoReason.recentCorroboratedUsableWithinDetour);
      expect(d.cautions, isEmpty);
      expect(d.requiresConfirmation, isFalse);
      expect(d.baselineNearest!.id, 'a');
    });

    test(
        'E2: escape pool {B single-unavailable @240, C corr-usable @260}; '
        'corroborated-usable PROMOTES past the nearer provisional => C', () {
      final a = _toilet(
        id: 'a',
        evidence: _cond(cc: 2, usable: (0, 2)),
      );
      final b = _toilet(
        id: 'b',
        evidence: _cond(cc: 1, usable: (0, 1)),
      );
      final c = _toilet(
        id: 'c',
        evidence: _cond(cc: 2, usable: (2, 0)),
      );
      final d = decideGo([_in(a, 200), _in(b, 240), _in(c, 260)], now: kNow);
      expect(d.selected!.id, 'c');
      expect(d.reason, GoReason.recentCorroboratedUsableWithinDetour);
      expect(d.cautions, isEmpty);
    });

    test(
        'E3: escape pool {B unknown @250, C corr-usable @280}; unknown '
        'provisional replaced by corroborated-usable => C', () {
      final a = _toilet(
        id: 'a',
        evidence: _cond(cc: 3, usable: (0, 3)),
      );
      final b = _toilet(id: 'b', evidence: _cond(cc: 0));
      final c = _toilet(
        id: 'c',
        evidence: _cond(cc: 2, usable: (2, 0)),
      );
      final d = decideGo([_in(a, 200), _in(b, 250), _in(c, 280)], now: kNow);
      expect(d.selected!.id, 'c');
      expect(d.reason, GoReason.recentCorroboratedUsableWithinDetour);
    });

    test(
        'E4: escape pool {B SINGLE-usable @240, C corr-usable @290}; a single '
        'usable report gets NO promotion authority => C', () {
      final a = _toilet(
        id: 'a',
        evidence: _cond(cc: 3, usable: (0, 3)),
      );
      final b = _toilet(
        id: 'b',
        evidence: _cond(cc: 1, usable: (1, 0)),
      );
      final c = _toilet(
        id: 'c',
        evidence: _cond(cc: 2, usable: (2, 0)),
      );
      final d = decideGo([_in(a, 200), _in(b, 240), _in(c, 290)], now: kNow);
      expect(d.selected!.id, 'c');
      expect(d.reason, GoReason.recentCorroboratedUsableWithinDetour);
    });

    test(
        'E5: C corr-usable @700 is OUTSIDE the detour of the original '
        'baseline => it is not in the escape pool; provisional B '
        'single-unavailable wins with its caution', () {
      final a = _toilet(
        id: 'a',
        evidence: _cond(cc: 3, usable: (0, 3)),
      );
      final b = _toilet(
        id: 'b',
        evidence: _cond(cc: 1, usable: (0, 1)),
      );
      final c = _toilet(
        id: 'c',
        evidence: _cond(cc: 3, usable: (3, 0)),
      );
      final d = decideGo([_in(a, 200), _in(b, 250), _in(c, 700)], now: kNow);
      expect(d.selected!.id, 'b');
      expect(d.reason, GoReason.avoidedRecentCorroboratedUnavailable);
      expect(d.cautions, contains(GoCaution.singleReportUnavailable));
      expect(d.requiresConfirmation, isFalse);
    });

    test(
      'E6: only escape candidate B @500 fails the 1.5x ratio guard => keep '
      'the ORIGINAL baseline, requiresConfirmation, corroboratedUnavailable',
      () {
        final a = _toilet(
          id: 'a',
          evidence: _cond(cc: 3, usable: (0, 3)),
        );
        final b = _toilet(id: 'b', evidence: _cond(cc: 0));
        final d = decideGo([_in(a, 200), _in(b, 500)], now: kNow);
        expect(d.selected!.id, 'a');
        expect(d.reason, GoReason.bestMappedOptionCorroboratedUnavailable);
        expect(d.requiresConfirmation, isTrue);
        expect(d.cautions, contains(GoCaution.corroboratedUnavailable));
      },
    );

    test(
        'escape replacement keeps its OWN water/lock cautions alongside the '
        'causal reason', () {
      final a = _toilet(
        id: 'a',
        evidence: _cond(cc: 2, usable: (0, 2)),
      );
      final b = _toilet(
        id: 'b',
        evidence: _cond(cc: 2, usable: (2, 0), water: (0, 2), lock: (0, 2)),
      );
      final d = decideGo([_in(a, 200), _in(b, 250)], now: kNow);
      expect(d.selected!.id, 'b');
      expect(d.reason, GoReason.recentCorroboratedUsableWithinDetour);
      expect(
        d.cautions,
        containsAll(<GoCaution>[
          GoCaution.waterReportedOut,
          GoCaution.lockReportedOut,
        ]),
      );
    });

    test(
      'escape pool never includes another corroborated-unavailable toilet',
      () {
        final a = _toilet(
          id: 'a',
          evidence: _cond(cc: 2, usable: (0, 2)),
        );
        final b = _toilet(
          id: 'b',
          evidence: _cond(cc: 3, usable: (0, 3)),
        );
        final c = _toilet(id: 'c'); // unknown, farther
        final d = decideGo([_in(a, 200), _in(b, 250), _in(c, 300)], now: kNow);
        // b is within detour but also corr-unavailable -> skipped; c wins.
        expect(d.selected!.id, 'c');
        expect(d.reason, GoReason.avoidedRecentCorroboratedUnavailable);
      },
    );
  });

  group('invalid-distance hardening', () {
    test('negative distance is dropped', () {
      final a = _toilet(id: 'a');
      final b = _toilet(id: 'b');
      final d = decideGo([_in(a, -10), _in(b, 500)], now: kNow);
      expect(d.selected!.id, 'b');
    });

    test('infinite distance is dropped', () {
      final a = _toilet(id: 'a');
      final b = _toilet(id: 'b');
      final d = decideGo([_in(a, double.infinity), _in(b, 42)], now: kNow);
      expect(d.selected!.id, 'b');
    });

    test('a zero distance is VALID', () {
      final a = _toilet(id: 'a');
      final d = decideGo([_in(a, 0)], now: kNow);
      expect(d.selected!.id, 'a');
      expect(d.selectedDistanceMeters, 0);
    });

    test('all distances invalid => NO_TOILETS', () {
      final a = _toilet(id: 'a');
      final b = _toilet(id: 'b');
      final d = decideGo([_in(a, double.nan), _in(b, -1)], now: kNow);
      expect(d.selected, isNull);
      expect(d.reason, GoReason.noToilets);
    });
  });

  group('withinEvidenceDetour input validation & boundaries', () {
    test('non-finite / negative inputs => false (fail closed)', () {
      expect(withinEvidenceDetour(double.nan, 100), isFalse);
      expect(withinEvidenceDetour(100, double.nan), isFalse);
      expect(withinEvidenceDetour(double.infinity, 100), isFalse);
      expect(withinEvidenceDetour(100, double.infinity), isFalse);
      expect(withinEvidenceDetour(-1, 100), isFalse);
      expect(withinEvidenceDetour(100, -1), isFalse);
    });

    test('farther < baseline => false', () {
      expect(withinEvidenceDetour(300, 250), isFalse);
    });

    test('equal distances => within (0 detour)', () {
      expect(withinEvidenceDetour(250, 250), isTrue);
    });

    test('exactly +400m and exactly 1.5x => within; just past => outside', () {
      expect(withinEvidenceDetour(1000, 1400), isTrue); // +400, 1.4x
      expect(withinEvidenceDetour(1000, 1401), isFalse); // +401
      expect(withinEvidenceDetour(200, 300), isTrue); // +100, 1.5x
      expect(withinEvidenceDetour(200, 301), isFalse); // 1.505x
    });

    test('baseline 0: only farther 0 is within', () {
      expect(withinEvidenceDetour(0, 0), isTrue);
      expect(withinEvidenceDetour(0, 1), isFalse); // 1 > 0*1.5
    });
  });

  group('/ alternatives are single-tier and carry contract metadata', () {
    test(
        'primary decision: alternatives are all primary, exclude selected, '
        'distance-sorted', () {
      final a = _toilet(id: 'a');
      final b = _toilet(id: 'b');
      final c = _toilet(id: 'c', identity: IdentityStatus.candidate);
      final cs = _toilet(id: 'cs', identity: IdentityStatus.communitySubmitted);
      final d = decideGo([
        _in(a, 100),
        _in(b, 200),
        _in(c, 150),
        _in(cs, 180),
      ], now: kNow);
      expect(d.selected!.id, 'a');
      expect(d.alternatives.map((x) => x.toilet.id), ['b']);
      expect(
        d.alternatives.every(
          (x) =>
              x.authority == RecommendationAuthority.sourceMappedPrimary ||
              x.authority == RecommendationAuthority.communityCorroborated,
        ),
        isTrue,
      );
    });

    test(
      'community-fallback decision: alternatives are community-fallback only',
      () {
        final cs1 = _toilet(
          id: 'cs1',
          identity: IdentityStatus.communitySubmitted,
        );
        final cs2 = _toilet(
          id: 'cs2',
          identity: IdentityStatus.communitySubmitted,
        );
        final cand = _toilet(id: 'cand', identity: IdentityStatus.candidate);
        final d = decideGo([
          _in(cs1, 100),
          _in(cs2, 200),
          _in(cand, 120),
        ], now: kNow);
        expect(d.selected!.id, 'cs1');
        expect(d.alternatives.map((x) => x.toilet.id), ['cs2']);
        expect(
          d.alternatives.single.authority,
          RecommendationAuthority.communityFallback,
        );
        expect(d.alternatives.single.requiresConfirmation, isTrue);
      },
    );

    test(
      'candidate/unknown-fallback decision: alternatives from that tier only',
      () {
        final c1 = _toilet(id: 'c1', identity: IdentityStatus.candidate);
        final u1 = _toilet(id: 'u1', identity: IdentityStatus.unknown);
        final d = decideGo([_in(c1, 100), _in(u1, 200)], now: kNow);
        expect(d.selected!.id, 'c1');
        expect(d.alternatives.map((x) => x.toilet.id), ['u1']);
        expect(
          d.alternatives.single.authority,
          RecommendationAuthority.unknownFallback,
        );
      },
    );

    test(
      'an alternative that is corroborated-unavailable requiresConfirmation; '
      'a single/conflicted-unavailable one does not',
      () {
        final a = _toilet(id: 'a'); // selected, nearest unknown
        final corr = _toilet(
          id: 'corr',
          evidence: _cond(cc: 3, usable: (0, 3)),
        );
        final single = _toilet(
          id: 'sng',
          evidence: _cond(cc: 1, usable: (0, 1)),
        );
        final d = decideGo([
          _in(a, 100),
          _in(corr, 220),
          _in(single, 210),
        ], now: kNow);
        expect(d.selected!.id, 'a');
        final byId = {for (final x in d.alternatives) x.toilet.id: x};
        expect(byId['corr']!.requiresConfirmation, isTrue);
        expect(
          byId['corr']!.cautions,
          contains(GoCaution.corroboratedUnavailable),
        );
        expect(byId['sng']!.requiresConfirmation, isFalse);
        expect(
          byId['sng']!.cautions,
          contains(GoCaution.singleReportUnavailable),
        );
      },
    );

    test('alternatives never contain a moderation-flagged toilet', () {
      final a = _toilet(id: 'a');
      final b = _toilet(id: 'b');
      final f = _toilet(id: 'f', flagged: true);
      final d = decideGo([_in(a, 100), _in(b, 150), _in(f, 120)], now: kNow);
      expect(d.selected!.id, 'a');
      expect(d.alternatives.map((x) => x.toilet.id), ['b']);
    });
  });

  group('baselineNearest is the nearest of the ACTIVE tier', () {
    test(
        'primary tier active => baseline is nearest primary, not a nearer '
        'candidate', () {
      final cand = _toilet(id: 'cand', identity: IdentityStatus.candidate);
      final p1 = _toilet(id: 'p1');
      final p2 = _toilet(id: 'p2');
      final d = decideGo([
        _in(cand, 50),
        _in(p1, 300),
        _in(p2, 400),
      ], now: kNow);
      expect(d.selected!.id, 'p1');
      expect(d.baselineNearest!.id, 'p1');
      expect(d.baselineNearestDistanceMeters, 300);
    });

    test(
        'community-fallback tier active => baseline is nearest community, not '
        'a nearer candidate', () {
      final cand = _toilet(id: 'cand', identity: IdentityStatus.candidate);
      final cs = _toilet(id: 'cs', identity: IdentityStatus.communitySubmitted);
      final d = decideGo([_in(cand, 50), _in(cs, 400)], now: kNow);
      expect(d.selected!.id, 'cs');
      expect(d.baselineNearest!.id, 'cs');
      expect(d.baselineNearestDistanceMeters, 400);
    });

    test(
      'candidate/unknown tier active => baseline is nearest of that tier',
      () {
        final c1 = _toilet(id: 'c1', identity: IdentityStatus.candidate);
        final c2 = _toilet(id: 'c2', identity: IdentityStatus.unknown);
        final d = decideGo([_in(c1, 220), _in(c2, 130)], now: kNow);
        expect(d.selected!.id, 'c2');
        expect(d.baselineNearest!.id, 'c2');
      },
    );

    test(
        'escape branch: baseline stays the ORIGINAL nearest primary even when '
        'a farther toilet is selected', () {
      final a = _toilet(
        id: 'a',
        evidence: _cond(cc: 2, usable: (0, 2)),
      );
      final b = _toilet(
        id: 'b',
        evidence: _cond(cc: 2, usable: (2, 0)),
      );
      final d = decideGo([_in(a, 200), _in(b, 260)], now: kNow);
      expect(d.selected!.id, 'b');
      expect(d.baselineNearest!.id, 'a');
      expect(d.baselineNearestDistanceMeters, 200);
    });

    test('flagged-only / no-toilets => baselineNearest null', () {
      expect(decideGo([], now: kNow).baselineNearest, isNull);
      final f = _toilet(id: 'f', flagged: true);
      expect(decideGo([_in(f, 100)], now: kNow).baselineNearest, isNull);
    });
  });

  group('support-consistency defence (via GO classification)', () {
    test(
        'a condition section whose verdict contradicts its support is treated '
        'as unavailable => ranks as unknown', () {
      // Hand-craft an INCONSISTENT section: usable verdict "yes" but support
      // says {yes:0, no:2}. The client parser must reject the whole section.
      final bad = Toilet(
        id: 'bad',
        name: 'T',
        address: 'A',
        latitude: 26.3,
        longitude: 73.1,
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
        flaggedRaw: false,
        flaggedUntil: null,
        addedBy: 'x',
        upvoteCount: 0,
        downvoteCount: 0,
        truth: _truth(IdentityStatus.sourceMapped),
        evidence: ToiletEvidence.fromFirestore({
          'version': 1,
          'condition': {
            'open': 'unknown',
            'water': 'unknown',
            'usable': 'yes', // <-- contradicts support below
            'lock': 'unknown',
            'contributor_count': 2,
            'latest_at': _ts(kNow.subtract(const Duration(minutes: 5))),
            'valid_until': _ts(kNow.add(const Duration(minutes: 40))),
            'computed_at': _ts(kNow.subtract(const Duration(seconds: 5))),
            'last_event_at': _ts(kNow.subtract(const Duration(seconds: 6))),
            'support': {
              'open': {'yes': 0, 'no': 0, 'unknown': 2},
              'water': {'yes': 0, 'no': 0, 'unknown': 2},
              'usable': {'yes': 0, 'no': 2, 'unknown': 0},
              'lock': {'yes': 0, 'no': 0, 'unknown': 2},
            },
          },
        }),
      );
      expect(bad.evidence.condition.available, isFalse);
      final near = _toilet(id: 'near');
      // If the bad section were trusted it would be corr-usable and could
      // detour; instead it is unknown, so the nearer plain toilet wins.
      final d = decideGo([_in(bad, 250), _in(near, 200)], now: kNow);
      expect(d.selected!.id, 'near');
      expect(d.reason, GoReason.nearestWithNoStrongEvidence);
    });
  });

  // =======================================================
  group('moderation-flag expiry is evaluated against the INJECTED now', () {
    // These dates are deliberately far from the real current date so that the
    // wall-clock `Toilet.isFlagged` getter would give the WRONG answer — only a
    // correct injected-now evaluation passes.

    test(
      'isModerationFlaggedAt: pure helper matches Toilet.isFlagged semantics '
      'but against the supplied now',
      () {
        final t = _toilet(
          id: 't',
          flaggedRaw: true,
          flaggedUntil: DateTime(2001, 1, 1),
        );
        expect(isModerationFlaggedAt(t, DateTime(2000, 1, 1)), isTrue);
        expect(isModerationFlaggedAt(t, DateTime(2001, 1, 1)), isFalse); // ==
        expect(isModerationFlaggedAt(t, DateTime(2002, 1, 1)), isFalse);
        final nullUntil = _toilet(
          id: 'n',
          flaggedRaw: true,
          flaggedUntil: null,
        );
        expect(isModerationFlaggedAt(nullUntil, DateTime(2000)), isFalse);
        final notRaw = _toilet(
          id: 'r',
          flaggedRaw: false,
          flaggedUntil: DateTime(3000),
        );
        expect(isModerationFlaggedAt(notRaw, DateTime(2000)), isFalse);
      },
    );

    test(
      'TEST A — injected PAST now => flag ACTIVE though the real clock would '
      'call it expired',
      () {
        final flagged = _toilet(
          id: 'f',
          flaggedRaw: true,
          flaggedUntil: DateTime(2001, 1, 1),
        );
        // Lone flagged toilet, evaluated at 2000 => still flagged => no
        // confident recommendation.
        final d = decideGo([_in(flagged, 100)], now: DateTime(2000, 1, 1));
        expect(d.selected, isNull);
        expect(d.reason, GoReason.onlyFlaggedOrUnconfirmedOptions);
        expect(d.cautions, contains(GoCaution.moderationFlagged));
        expect(d.alternatives, isEmpty);
        expect(d.baselineNearest, isNull);
      },
    );

    test(
        'TEST B — injected FUTURE now => flag EXPIRED though the real clock '
        'would call it active', () {
      final wasFlagged = _toilet(
        id: 'wf',
        flaggedRaw: true,
        flaggedUntil: DateTime(2099, 1, 1),
      );
      final d = decideGo([_in(wasFlagged, 100)], now: DateTime(2100, 1, 1));
      // No longer flagged => a normal source-mapped primary, and selected.
      expect(d.selected!.id, 'wf');
      expect(d.reason, GoReason.nearestWithNoStrongEvidence);
      expect(d.requiresConfirmation, isFalse);
      expect(d.cautions, isEmpty);
    });

    test('TEST C — flaggedUntil == injected now => NOT flagged', () {
      final at = DateTime(2050, 6, 1, 12);
      final t = _toilet(id: 't', flaggedRaw: true, flaggedUntil: at);
      final d = decideGo([_in(t, 100)], now: at);
      expect(d.selected!.id, 't'); // boundary is exclusive => not flagged
      expect(d.reason, GoReason.nearestWithNoStrongEvidence);
    });

    test('TEST D — flaggedRaw true + flaggedUntil null => NOT flagged', () {
      final t = _toilet(id: 't', flaggedRaw: true, flaggedUntil: null);
      final d = decideGo([_in(t, 100)], now: DateTime(2050));
      expect(d.selected!.id, 't');
    });

    test(
        'TEST E — flaggedRaw false + flaggedUntil in the future => NOT '
        'flagged', () {
      final t = _toilet(
        id: 't',
        flaggedRaw: false,
        flaggedUntil: DateTime(3000),
      );
      final d = decideGo([_in(t, 100)], now: DateTime(2050));
      expect(d.selected!.id, 't');
    });

    test(
        'TEST F — same pool + same injected now => byte-for-byte identical '
        'decision, moderation expiry included', () {
      List<GoInput> pool() => [
            // an active-at-2000 flag, plus real primaries and a fallback
            _in(
              _toilet(
                id: 'flag',
                flaggedRaw: true,
                flaggedUntil: DateTime(2001, 1, 1),
              ),
              90,
            ),
            _in(_toilet(id: 'p1'), 200),
            _in(
              _toilet(
                id: 'p2',
                evidence: _cond(cc: 2, usable: (2, 0)),
              ),
              230,
            ),
            _in(
              _toilet(id: 'cs', identity: IdentityStatus.communitySubmitted),
              150,
            ),
          ];
      final at = DateTime(2000, 1, 1);
      String sig(GoDecision d) => [
            d.selected?.id,
            d.reason.name,
            d.requiresConfirmation,
            (d.cautions.map((c) => c.name).toList()..sort()).join(','),
            d.baselineNearest?.id,
            d.baselineNearestDistanceMeters,
            d.alternatives
                .map(
                  (a) =>
                      '${a.toilet.id}:${a.authority.name}:${a.condition.name}:'
                      '${a.requiresConfirmation}:'
                      '${(a.cautions.map((c) => c.name).toList()..sort()).join("|")}',
                )
                .join(';'),
          ].join('#');

      final first = sig(decideGo(pool(), now: at));
      for (var i = 0; i < 25; i++) {
        expect(sig(decideGo(pool(), now: at)), first);
      }
      // 'flag' is moderation-flagged at 2000 => never selected, never an alt.
      final d = decideGo(pool(), now: at);
      expect(d.selected!.id, isNot('flag'));
      expect(d.alternatives.map((a) => a.toilet.id), isNot(contains('flag')));
    });
  });

  group('PROPERTY / FUZZ (seeded, deterministic)', () {
    final rnd = Random(20260902);

    ToiletEvidence randomEvidence() {
      final roll = rnd.nextInt(5);
      switch (roll) {
        case 0:
          return ToiletEvidence.unavailable;
        case 1:
          return _cond(cc: 0);
        case 2:
          return _cond(cc: 1, usable: (rnd.nextBool() ? 1 : 0, 0));
        case 3:
          return _cond(cc: 2 + rnd.nextInt(3), usable: (2, 0));
        default:
          return _cond(cc: 3, usable: (rnd.nextInt(2), rnd.nextInt(3)));
      }
    }

    List<GoInput> randomPool(int n) => List.generate(n, (i) {
          final ids = [
            IdentityStatus.sourceMapped,
            IdentityStatus.sourceMapped,
            IdentityStatus.communitySubmitted,
            IdentityStatus.candidate,
            IdentityStatus.unknown,
          ];
          return _in(
            _toilet(
              id: 'p${i.toString().padLeft(2, '0')}',
              identity: ids[rnd.nextInt(ids.length)],
              flagged: rnd.nextInt(10) == 0,
              evidence: randomEvidence(),
            ),
            50.0 + rnd.nextInt(4000),
          );
        });

    test('reordering the input list never changes the selected id', () {
      for (var iter = 0; iter < 60; iter++) {
        final pool = randomPool(5 + rnd.nextInt(6));
        final want = decideGo(pool, now: kNow).selected?.id;
        final shuffled = [...pool]..shuffle(rnd);
        expect(decideGo(shuffled, now: kNow).selected?.id, want);
      }
    });

    test('increasing ratings alone never changes the winner', () {
      for (var iter = 0; iter < 40; iter++) {
        final pool = randomPool(4 + rnd.nextInt(5));
        final want = decideGo(pool, now: kNow).selected?.id;
        final bumped = pool
            .map(
              (g) => _in(
                _toilet(
                  id: g.toilet.id,
                  identity: g.toilet.truth.identityStatus,
                  flagged: g.toilet.isFlagged,
                  evidence: g.toilet.evidence,
                  starRating: 4.7,
                  totalRatings: 500,
                ),
                g.distanceMeters,
              ),
            )
            .toList();
        expect(decideGo(bumped, now: kNow).selected?.id, want);
      }
    });

    test('marking a record candidate can never INCREASE its authority', () {
      for (var iter = 0; iter < 40; iter++) {
        final pool = randomPool(4 + rnd.nextInt(5));
        final chosen = decideGo(pool, now: kNow).selected?.id;
        if (chosen == null) continue;
        // Demote the chosen toilet to candidate; it must NOT still be chosen
        // unless it was the only viable option (fallback) — in which case the
        // reason must reflect the identity uncertainty.
        final demoted = pool.map((g) {
          if (g.toilet.id != chosen) return g;
          return _in(
            _toilet(
              id: g.toilet.id,
              identity: IdentityStatus.candidate,
              evidence: g.toilet.evidence,
            ),
            g.distanceMeters,
          );
        }).toList();
        final after = decideGo(demoted, now: kNow);
        if (after.selected?.id == chosen) {
          expect(after.requiresConfirmation, isTrue);
          expect(
            after.reason,
            anyOf(
              GoReason.candidateFallback,
              GoReason.communitySubmissionFallback,
            ),
          );
        }
      }
    });

    test('result-contract invariants hold for every random pool', () {
      for (var iter = 0; iter < 120; iter++) {
        final pool = randomPool(4 + rnd.nextInt(7));
        final d = decideGo(pool, now: kNow);

        // alternatives never contain the selected toilet, never a flagged one,
        // are distance-sorted, and all share ONE authority tier.
        final altIds = d.alternatives.map((a) => a.toilet.id).toList();
        expect(altIds.toSet().length, altIds.length); // no dup
        if (d.selected != null) {
          expect(altIds, isNot(contains(d.selected!.id)));
        }
        for (final a in d.alternatives) {
          expect(a.toilet.isFlagged, isFalse);
        }
        for (var i = 1; i < d.alternatives.length; i++) {
          expect(
            d.alternatives[i - 1].distanceMeters <=
                d.alternatives[i].distanceMeters,
            isTrue,
          );
        }
        final tiers = d.alternatives.map((a) {
          if (a.authority == RecommendationAuthority.sourceMappedPrimary ||
              a.authority == RecommendationAuthority.communityCorroborated) {
            return 'primary';
          }
          if (a.authority == RecommendationAuthority.communityFallback) {
            return 'community';
          }
          return 'candidateOrUnknown';
        }).toSet();
        expect(tiers.length, lessThanOrEqualTo(1));

        // baselineNearest, when present, is one of the input toilets and no
        // farther than the selected distance's tier minimum is not asserted
        // here directly, but it must never be a flagged toilet.
        if (d.baselineNearest != null) {
          expect(d.baselineNearest!.isFlagged, isFalse);
        }

        // requiresConfirmation is consistent with the cautions surface.
        if (d.cautions.contains(GoCaution.corroboratedUnavailable) &&
            d.reason == GoReason.bestMappedOptionCorroboratedUnavailable) {
          expect(d.requiresConfirmation, isTrue);
        }
      }
    });

    test(
        'avoidedRecentCorroboratedUnavailable never selects a corroborated-'
        'unavailable toilet', () {
      for (var iter = 0; iter < 120; iter++) {
        final pool = randomPool(4 + rnd.nextInt(7));
        final d = decideGo(pool, now: kNow);
        if (d.reason != GoReason.avoidedRecentCorroboratedUnavailable) continue;
        final sel = pool.firstWhere((g) => g.toilet.id == d.selected!.id);
        // Re-derive: the selected toilet's condition must not be the
        // corroborated-unavailable class.
        final replayed = decideGo([
          _in(sel.toilet, sel.distanceMeters),
        ], now: kNow);
        expect(
          replayed.cautions.contains(GoCaution.corroboratedUnavailable),
          isFalse,
        );
      }
    });

    test(
      'expiring a corroborated-usable can never strengthen its authority',
      () {
        for (var iter = 0; iter < 40; iter++) {
          final a = _toilet(id: 'a');
          final b = _toilet(
            id: 'b',
            evidence: _cond(cc: 3, usable: (3, 0)),
          );
          final dist = 200.0 + rnd.nextInt(600);
          final live = decideGo([_in(a, 200), _in(b, dist)], now: kNow);
          final expired = decideGo([
            _in(a, 200),
            _in(
              _toilet(
                id: 'b',
                evidence: _cond(
                  cc: 3,
                  usable: (3, 0),
                  validFor: const Duration(minutes: -1),
                ),
              ),
              dist,
            ),
          ], now: kNow);
          // If b won live, expiring its evidence must not keep b winning past
          // the nearest baseline.
          if (live.selected?.id == 'b' && dist > 200) {
            expect(expired.selected?.id, 'a');
          }
        }
      },
    );
  });
}
