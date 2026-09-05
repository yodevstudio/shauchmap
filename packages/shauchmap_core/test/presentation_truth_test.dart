// Presentation Truth — verifies the layer turns a `ToiletTruth`
// domain view into honest labels, keeps UNKNOWN first-class, and never renders
// UNKNOWN as YES or NO. The domain adapters themselves are covered by
// toilet_truth_test.dart — here we feed ToiletTruth values straight in.

import 'package:shauchmap_core/shauchmap_core.dart';
import 'package:test/test.dart';

Toilet _toilet({
  ToiletTruth truth = const ToiletTruth.allUnknown(),
  ToiletEvidence evidence = ToiletEvidence.unavailable,
}) {
  return Toilet(
    id: 't1',
    name: 'Test toilet',
    address: 'Somewhere',
    latitude: 26.3,
    longitude: 73.1,
    category: 'govt',
    starRating: 0.0,
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
    addedBy: 'osm_india_import_2026',
    truth: truth,
    evidence: evidence,
  );
}

Instant _ts(DateTime d) => Instant.fromDateTime(d);

ToiletTruth _truth({
  ToiletSource source = ToiletSource.osm,
  bool isNativeV2 = false,
  FeeState fee = FeeState.unknown,
  ToiletAmenities amenities = ToiletAmenities.allUnknown,
  FacilityContext context = FacilityContext.unknown,
  GenderAccess gender = GenderAccess.unknown,
  IdentityStatus identityStatus = IdentityStatus.sourceMapped,
}) {
  return ToiletTruth(
    schemaVersion: isNativeV2 ? 2 : 1,
    source: source,
    recordedAt: null,
    context: context,
    gender: gender,
    identityStatus: identityStatus,
    fee: fee,
    amenities: amenities,
    isNativeV2: isNativeV2,
  );
}

void main() {
  group('open / closed status (dynamic only)', () {
    test('no condition evidence => UNKNOWN, regardless of ToiletTruth', () {
      final p = ToiletPresentation.fromToilet(_toilet());
      expect(p.open, Evidence.unknown);
      expect(p.openLabel, 'Status unconfirmed');
      expect(p.statusUnconfirmed, isTrue);
    });

    test('empty condition summary (count 0) stays UNKNOWN', () {
      final p = ToiletPresentation.withCondition(_toilet(), {
        'count': 0,
        'open': 'unknown',
        'usable': 'unknown',
        'minutesAgo': 0,
      });
      expect(p.open, Evidence.unknown);
    });

    test('recent condition open=yes => "Open now"', () {
      final p = ToiletPresentation.withCondition(_toilet(), {
        'count': 2,
        'open': 'yes',
        'usable': 'unknown',
        'minutesAgo': 12,
      });
      expect(p.open, Evidence.yes);
      expect(p.openLabel, 'Open now');
    });

    test('recent condition open=no => "Closed now" and unusable', () {
      final p = ToiletPresentation.withCondition(_toilet(), {
        'count': 1,
        'open': 'no',
        'usable': 'unknown',
        'minutesAgo': 5,
      });
      expect(p.open, Evidence.no);
      expect(p.openLabel, 'Closed now');
      expect(p.usability, Evidence.no);
      expect(p.usabilityLabel, 'Recent checks: unusable');
    });

    test(
      'a native-V2 facility view never sets a live open state on its own',
      () {
        final p = ToiletPresentation.fromToilet(
          _toilet(truth: _truth(isNativeV2: true, fee: FeeState.free)),
        );
        // Static facility truth is known; dynamic status is still unconfirmed.
        expect(p.open, Evidence.unknown);
        expect(p.fee, FeeState.free);
      },
    );
  });

  group('usability', () {
    test('usable=yes AND not closed => "Usable right now"', () {
      final p = ToiletPresentation.withCondition(_toilet(), {
        'count': 3,
        'open': 'yes',
        'usable': 'yes',
        'minutesAgo': 8,
      });
      expect(p.usability, Evidence.yes);
      expect(p.usabilityLabel, 'Usable right now');
    });

    test('usable=unknown => "Usability unconfirmed"', () {
      final p = ToiletPresentation.withCondition(_toilet(), {
        'count': 1,
        'open': 'yes',
        'usable': 'unknown',
        'minutesAgo': 3,
      });
      expect(p.usability, Evidence.unknown);
    });

    test('usable=no dominates even when open is unknown', () {
      final p = ToiletPresentation.withCondition(_toilet(), {
        'count': 2,
        'open': 'unknown',
        'usable': 'no',
        'minutesAgo': 20,
      });
      expect(p.usability, Evidence.no);
    });
  });

  group('withCondition — DETAIL direct-query passive expiry ', () {
    final t0 = DateTime(2026, 9, 2, 12, 0, 0);
    Map<String, dynamic> summary(int validUntilMs) => {
          'count': 2,
          'open': 'yes',
          'usable': 'yes',
          'minutesAgo': 10,
          'validUntilMs': validUntilMs,
        };

    test('before validUntil => the verdict is surfaced', () {
      final vum = t0.add(const Duration(minutes: 20)).millisecondsSinceEpoch;
      final p = ToiletPresentation.withCondition(
        _toilet(),
        summary(vum),
        now: t0,
      );
      expect(p.open, Evidence.yes);
      expect(p.openLabel, 'Open now');
      expect(p.conditionSource, ConditionSource.liveQuery);
    });

    test(
      'at/after validUntil => drops to UNKNOWN (no Firestore write needed)',
      () {
        final vum = t0.add(const Duration(minutes: 1)).millisecondsSinceEpoch;
        final p = ToiletPresentation.withCondition(
          _toilet(),
          summary(vum),
          now: t0.add(const Duration(minutes: 1)),
        );
        expect(p.open, Evidence.unknown);
        expect(p.usability, Evidence.unknown);
        expect(p.openLabel, 'Status unconfirmed');
        expect(p.conditionSource, ConditionSource.liveQueryExpired);
      },
    );

    test('a summary with no validUntilMs is used as-is (count>0)', () {
      final p = ToiletPresentation.withCondition(
          _toilet(),
          {
            'count': 1,
            'open': 'no',
            'usable': 'unknown',
            'minutesAgo': 5,
          },
          now: t0);
      expect(p.open, Evidence.no);
      expect(p.conditionSource, ConditionSource.liveQuery);
    });
  });

  group('fee presentation', () {
    test('FeeState.unknown => "Fee unconfirmed"', () {
      final p = ToiletPresentation.fromToilet(
        _toilet(truth: _truth(fee: FeeState.unknown)),
      );
      expect(p.fee, FeeState.unknown);
      expect(p.feeLabel, 'Fee unconfirmed');
    });

    test('FeeState.free => community-listed, NOT "verified free"', () {
      final p = ToiletPresentation.fromToilet(
        _toilet(truth: _truth(isNativeV2: true, fee: FeeState.free)),
      );
      expect(p.fee, FeeState.free);
      expect(p.feeLabel, contains('listed'));
      expect(p.feeLabel.toLowerCase(), isNot(contains('verified')));
    });

    test('FeeState.paid => listed', () {
      final p = ToiletPresentation.fromToilet(
        _toilet(truth: _truth(fee: FeeState.paid)),
      );
      expect(p.fee, FeeState.paid);
      expect(p.feeLabel, contains('listed'));
    });
  });

  group('amenity presentation', () {
    ToiletAmenities amen({
      EvidenceState water = EvidenceState.unknown,
      EvidenceState soap = EvidenceState.unknown,
    }) =>
        ToiletAmenities(
          water: water,
          soap: soap,
          lock: EvidenceState.unknown,
          western: EvidenceState.unknown,
          wheelchair: EvidenceState.unknown,
          babyChange: EvidenceState.unknown,
          sanitaryDisposal: EvidenceState.unknown,
        );

    test('EvidenceState.present => AmenityEvidence.listed', () {
      final p = ToiletPresentation.fromToilet(
        _toilet(
          truth: _truth(amenities: amen(water: EvidenceState.present)),
        ),
      );
      expect(p.water, AmenityEvidence.listed);
    });

    test('EvidenceState.absent => AmenityEvidence.notPresent (submitted)', () {
      final p = ToiletPresentation.fromToilet(
        _toilet(
          truth: _truth(
            isNativeV2: true,
            amenities: amen(soap: EvidenceState.absent),
          ),
        ),
      );
      expect(p.soap, AmenityEvidence.notPresent);
    });

    test('EvidenceState.unknown => AmenityEvidence.unknown, never a "No"', () {
      final p = ToiletPresentation.fromToilet(_toilet());
      expect(p.water, AmenityEvidence.unknown);
      expect(p.soap, AmenityEvidence.unknown);
      expect(p.lock, AmenityEvidence.unknown);
      expect(p.western, AmenityEvidence.unknown);
      expect(p.wheelchair, AmenityEvidence.unknown);
      expect(p.babyChange, AmenityEvidence.unknown);
      expect(p.sanitaryDisposal, AmenityEvidence.unknown);
    });
  });

  group('freshness / recency is factual only', () {
    test('no condition checks => no recency label', () {
      final p = ToiletPresentation.fromToilet(_toilet());
      expect(p.conditionRecencyLabel, isNull);
    });

    test('a real recent check => a plain age, never "verified"', () {
      final p = ToiletPresentation.withCondition(_toilet(), {
        'count': 1,
        'open': 'yes',
        'usable': 'yes',
        'minutesAgo': 18,
      });
      expect(p.conditionRecencyLabel, 'Condition checks 18 min ago');
      expect(p.conditionRecencyLabel, isNot(contains('verified')));
    });
  });

  group('provenance is carried through', () {
    test('native V2 flag and source survive to presentation', () {
      final p = ToiletPresentation.fromToilet(
        _toilet(
          truth: _truth(
            source: ToiletSource.communitySubmission,
            isNativeV2: true,
          ),
        ),
      );
      expect(p.isNativeV2, isTrue);
      expect(p.source, ToiletSource.communitySubmission);
    });

    test('legacy OSM adaptation is not flagged native', () {
      final p = ToiletPresentation.fromToilet(
        _toilet(truth: _truth(source: ToiletSource.osm)),
      );
      expect(p.isNativeV2, isFalse);
      expect(p.source, ToiletSource.osm);
    });
  });

  group('identity presentation', () {
    test('base OSM (context unknown) NEVER surfaces "GOVT" / "Government"', () {
      final p = ToiletPresentation.fromToilet(
        _toilet(truth: _truth(context: FacilityContext.unknown)),
      );
      expect(p.context, FacilityContext.unknown);
      expect(p.contextLabel, 'Mapped toilet');
      expect(p.contextLabel.toLowerCase(), isNot(contains('govt')));
      expect(p.contextLabel.toLowerCase(), isNot(contains('government')));
      expect(p.contextLabel.toLowerCase(), isNot(contains('municipal')));
    });

    test('unknown gender surfaces NO label ("Unisex" must not appear)', () {
      final p = ToiletPresentation.fromToilet(
        _toilet(truth: _truth(gender: GenderAccess.unknown)),
      );
      expect(p.gender, GenderAccess.unknown);
      expect(p.genderLabel, isNull);
    });

    test('explicit context / gender produce factual labels', () {
      final p = ToiletPresentation.fromToilet(
        _toilet(
          truth: _truth(
            context: FacilityContext.petrolStation,
            gender: GenderAccess.women,
          ),
        ),
      );
      expect(p.contextLabel, 'Petrol pump');
      expect(p.genderLabel, 'Women only');
    });

    test('a needs_confirm candidate surfaces distinctly', () {
      final p = ToiletPresentation.fromToilet(
        _toilet(
          truth: _truth(
            identityStatus: IdentityStatus.candidate,
            context: FacilityContext.commercial,
          ),
        ),
      );
      expect(p.isCandidate, isTrue);
      expect(p.identityStatus, IdentityStatus.candidate);
    });

    test('a normal source-mapped toilet is NOT a candidate', () {
      final p = ToiletPresentation.fromToilet(
        _toilet(truth: _truth(identityStatus: IdentityStatus.sourceMapped)),
      );
      expect(p.isCandidate, isFalse);
    });
  });

  group('fromEvidence — server-derived condition + ratings/votes', () {
    final now = DateTime(2026, 9, 2, 12, 0, 0);
    final srv = {
      'computed_at': _ts(now.subtract(const Duration(seconds: 5))),
      'last_event_at': _ts(now.subtract(const Duration(seconds: 6))),
    };

    ToiletEvidence ratingsEv(int count, double? avg) =>
        ToiletEvidence.fromFirestore({
          'version': 1,
          'ratings': {'count': count, 'average': avg, ...srv},
        });
    ToiletEvidence votesEv(int up, int down) => ToiletEvidence.fromFirestore({
          'version': 1,
          'votes': {'up': up, 'down': down, ...srv},
        });
    Map<String, int> sup(String v, int cc) => switch (v) {
          'yes' => {'yes': cc, 'no': 0, 'unknown': 0},
          'no' => {'yes': 0, 'no': cc, 'unknown': 0},
          _ => {'yes': 0, 'no': 0, 'unknown': cc},
        };
    ToiletEvidence condEv({
      required String open,
      String usable = 'unknown',
      required int count,
      required DateTime validUntil,
      DateTime? latestAt,
    }) =>
        ToiletEvidence.fromFirestore({
          'version': 1,
          'condition': {
            'open': open,
            'water': 'unknown',
            'usable': usable,
            'lock': 'unknown',
            'contributor_count': count,
            'latest_at':
                _ts(latestAt ?? now.subtract(const Duration(minutes: 12))),
            'valid_until': _ts(validUntil),
            'support': {
              'open': sup(open, count),
              'water': sup('unknown', count),
              'usable': sup(usable, count),
              'lock': sup('unknown', count),
            },
            ...srv,
          },
        });

    test('no evidence => Status unconfirmed, ratings/votes unavailable', () {
      final p = ToiletPresentation.fromEvidence(_toilet(), now: now);
      expect(p.open, Evidence.unknown);
      expect(p.openLabel, 'Status unconfirmed');
      expect(p.conditionSource, ConditionSource.none);
      expect(p.ratingsAvailable, isFalse);
      expect(p.ratingsLabel, isNull);
      expect(p.votesAvailable, isFalse);
    });

    test('valid server condition open=yes => "Recent checks: open"', () {
      final p = ToiletPresentation.fromEvidence(
        _toilet(
          evidence: condEv(
            open: 'yes',
            usable: 'yes',
            count: 2,
            validUntil: now.add(const Duration(minutes: 40)),
          ),
        ),
        now: now,
      );
      expect(p.open, Evidence.yes);
      expect(p.openLabel, 'Recent checks: open');
      expect(p.usabilityLabel, 'Recent checks: usable');
      expect(p.conditionSource, ConditionSource.serverIndex);
      expect(p.conditionCheckCount, 2);
      expect(p.openLabel.toLowerCase(), isNot(contains('verified')));
    });

    test('valid server condition open=no => "Recent checks: closed" + unusable', () {
      final p = ToiletPresentation.fromEvidence(
        _toilet(
          evidence: condEv(
            open: 'no',
            count: 1,
            validUntil: now.add(const Duration(minutes: 30)),
          ),
        ),
        now: now,
      );
      expect(p.open, Evidence.no);
      expect(p.openLabel, 'Recent checks: closed');
      expect(p.usability, Evidence.no);
    });

    test('EXPIRED server condition => UNKNOWN even though stored says yes', () {
      final validUntil = now.add(const Duration(minutes: 1));
      final t = _toilet(
        evidence: condEv(
          open: 'yes',
          usable: 'yes',
          count: 3,
          validUntil: validUntil,
          latestAt: now.subtract(const Duration(minutes: 1)),
        ),
      );
      final before = ToiletPresentation.fromEvidence(
        t,
        now: validUntil.subtract(const Duration(seconds: 1)),
      );
      final after = ToiletPresentation.fromEvidence(t, now: validUntil);
      expect(before.open, Evidence.yes);
      expect(after.open, Evidence.unknown);
      expect(after.openLabel, 'Status unconfirmed');
      expect(after.conditionSource, ConditionSource.serverIndexExpired);
    });

    test('ratings: indexed zero => "No ratings yet"; nonzero => figure', () {
      final zero = ToiletPresentation.fromEvidence(
        _toilet(evidence: ratingsEv(0, null)),
        now: now,
      );
      expect(zero.ratingsAvailable, isTrue);
      expect(zero.ratingsLabel, 'No ratings yet');

      final some = ToiletPresentation.fromEvidence(
        _toilet(evidence: ratingsEv(7, 4.2)),
        now: now,
      );
      expect(some.ratingsLabel, '★ 4.2 · 7 ratings');
    });

    test('votes: 0/0 indexed is available but never a 50%', () {
      final p = ToiletPresentation.fromEvidence(
        _toilet(evidence: votesEv(0, 0)),
        now: now,
      );
      expect(p.votesAvailable, isTrue);
      expect(p.votesUp, 0);
      expect(p.votesDown, 0);
      // there is no percentage / ratio field on the presentation at all
    });

    test('static facility truth still flows through fromEvidence', () {
      final p = ToiletPresentation.fromEvidence(
        _toilet(truth: _truth(context: FacilityContext.petrolStation)),
        now: now,
      );
      expect(p.contextLabel, 'Petrol pump');
      expect(p.feeLabel, 'Fee unconfirmed');
    });
  });

  group('community score guard', () {
    test('0 up / 0 down must never be read as "50% positive"', () {
      final t = _toilet();
      expect(t.communityScore, 0.5);
      final voted = Toilet(
        id: 'x',
        name: 'n',
        address: 'a',
        latitude: 1,
        longitude: 1,
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
        addedBy: 'osm_x',
        upvoteCount: 3,
        downvoteCount: 1,
      );
      expect(voted.communityScore, closeTo(0.75, 0.0001));
    });
  });
}
