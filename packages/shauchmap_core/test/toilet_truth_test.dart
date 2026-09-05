// + 4B — Truth V2 domain model. Covers the STRICT native parser and
// BOTH legacy adapters (OSM import, old community wizard) across identity,
// static facility attributes, and provenance. No Firestore is needed.

import 'package:shauchmap_core/shauchmap_core.dart';
import 'package:test/test.dart';

ToiletTruth _osm(Map<String, dynamic> data) =>
    ToiletTruth.fromFirestore(data, addedBy: 'osm_india_import_2026');

ToiletTruth _community(Map<String, dynamic> data) =>
    ToiletTruth.fromFirestore(data, addedBy: 'user_abc123');

const _amenAllUnknown = {
  'water': 'unknown',
  'soap': 'unknown',
  'lock': 'unknown',
  'western': 'unknown',
  'wheelchair': 'unknown',
  'baby_change': 'unknown',
  'sanitary_disposal': 'unknown',
};

Map<String, dynamic> _v2(Map<String, dynamic> over) {
  return {
    'truth_v2': {
      'version': 2,
      'source_type': 'community_submission',
      'recorded_at': Instant.fromDateTime(DateTime(2026, 9, 2, 10)),
      'fee': 'unknown',
      'context': 'unknown',
      'gender': 'unknown',
      'amenities': {..._amenAllUnknown},
      ...over,
    },
  };
}

ToiletTruth _parseV2(Map<String, dynamic> over) =>
    ToiletTruth.fromFirestore(_v2(over), addedBy: 'user_x');

void main() {
  group('legacy OSM — fee is UNKNOWN in every direction', () {
    test('is_free true -> unknown', () {
      expect(_osm({'is_free': true}).fee, FeeState.unknown);
    });
    test('is_free false -> unknown (raw charge value was discarded)', () {
      expect(_osm({'is_free': false}).fee, FeeState.unknown);
    });
    test('is_free missing -> unknown', () {
      expect(_osm({}).fee, FeeState.unknown);
    });
  });

  group('legacy OSM — identity', () {
    test('base category "govt" -> context UNKNOWN, NOT government', () {
      final t = _osm({'category': 'govt'});
      expect(t.context, FacilityContext.unknown);
      expect(t.identityStatus, IdentityStatus.sourceMapped);
    });
    test('default gender "unisex" -> gender UNKNOWN', () {
      expect(_osm({'gender_type': 'unisex'}).gender, GenderAccess.unknown);
    });
    test('missing gender -> gender UNKNOWN', () {
      expect(_osm({}).gender, GenderAccess.unknown);
    });
    test('source "female" -> women (source-listed)', () {
      expect(_osm({'gender_type': 'female'}).gender, GenderAccess.women);
    });
    test('source "male" -> men (source-listed)', () {
      expect(_osm({'gender_type': 'male'}).gender, GenderAccess.men);
    });
    test('needs_confirm true -> CANDIDATE + extended context', () {
      final t = _osm({'needs_confirm': true, 'category': 'petrol'});
      expect(t.identityStatus, IdentityStatus.candidate);
      expect(t.isCandidate, isTrue);
      expect(t.context, FacilityContext.petrolStation);
    });
    test('needs_confirm true still downgrades positive amenities', () {
      final t = _osm({
        'needs_confirm': true,
        'category': 'mall',
        'has_water': true,
      });
      expect(t.context, FacilityContext.commercial);
      expect(t.amenities.water, EvidenceState.unknown);
    });
  });

  group('legacy OSM — static amenities (unchanged from )', () {
    test('has_water true -> present; false/missing -> unknown', () {
      expect(_osm({'has_water': true}).amenities.water, EvidenceState.present);
      expect(_osm({'has_water': false}).amenities.water, EvidenceState.unknown);
      expect(_osm({}).amenities.water, EvidenceState.unknown);
    });
    test('soap / lock / western / sanitary_disposal always unknown', () {
      final t = _osm({'has_soap': true, 'has_lock': true, 'is_western': true});
      expect(t.amenities.soap, EvidenceState.unknown);
      expect(t.amenities.lock, EvidenceState.unknown);
      expect(t.amenities.western, EvidenceState.unknown);
      expect(t.amenities.sanitaryDisposal, EvidenceState.unknown);
    });
    test('wheelchair / baby_change true -> present', () {
      expect(
        _osm({'is_wheelchair': true}).amenities.wheelchair,
        EvidenceState.present,
      );
      expect(
        _osm({'has_baby_change': true}).amenities.babyChange,
        EvidenceState.present,
      );
    });
  });

  group('legacy community — identity', () {
    test('hidden default category "govt" -> context UNKNOWN', () {
      expect(_community({'category': 'govt'}).context, FacilityContext.unknown);
    });
    test(
      'explicit "government" chip -> publicToilet context (not ownership)',
      () {
        expect(
          _community({'category': 'government'}).context,
          FacilityContext.publicToilet,
        );
      },
    );
    test('explicit "fuel" / "commercial" / "station" chips map through', () {
      expect(
        _community({'category': 'fuel'}).context,
        FacilityContext.petrolStation,
      );
      expect(
        _community({'category': 'commercial'}).context,
        FacilityContext.commercial,
      );
      expect(
        _community({'category': 'station'}).context,
        FacilityContext.station,
      );
    });
    test('default gender "unisex" -> UNKNOWN; explicit men/women -> known', () {
      expect(
        _community({'gender_type': 'unisex'}).gender,
        GenderAccess.unknown,
      );
      expect(_community({'gender_type': 'men'}).gender, GenderAccess.men);
      expect(_community({'gender_type': 'women'}).gender, GenderAccess.women);
    });
    test('fee always unknown; status communitySubmitted', () {
      final t = _community({'is_free': false});
      expect(t.fee, FeeState.unknown);
      expect(t.identityStatus, IdentityStatus.communitySubmitted);
    });
    test('OFF-default amenity true -> present', () {
      expect(
        _community({'is_wheelchair': true}).amenities.wheelchair,
        EvidenceState.present,
      );
    });
  });

  group('native truth_v2 — identity round-trips', () {
    test('default all-unknown parses native, identity UNKNOWN', () {
      final t = _parseV2({});
      expect(t.isNativeV2, isTrue);
      expect(t.source, ToiletSource.communitySubmission);
      expect(t.identityStatus, IdentityStatus.communitySubmitted);
      expect(t.context, FacilityContext.unknown);
      expect(t.gender, GenderAccess.unknown);
      expect(t.fee, FeeState.unknown);
    });
    test('explicit context survives', () {
      expect(
        _parseV2({'context': 'petrol_station'}).context,
        FacilityContext.petrolStation,
      );
      expect(
        _parseV2({'context': 'public_toilet'}).context,
        FacilityContext.publicToilet,
      );
    });
    test('explicit gender survives', () {
      expect(_parseV2({'gender': 'women'}).gender, GenderAccess.women);
      expect(_parseV2({'gender': 'unisex'}).gender, GenderAccess.unisex);
    });
    test('explicit fee free / paid survive', () {
      expect(_parseV2({'fee': 'free'}).fee, FeeState.free);
      expect(_parseV2({'fee': 'paid'}).fee, FeeState.paid);
    });
    test('amenity present/absent/unknown round-trip', () {
      final t = _parseV2({
        'amenities': {..._amenAllUnknown, 'water': 'present', 'soap': 'absent'},
      });
      expect(t.amenities.water, EvidenceState.present);
      expect(t.amenities.soap, EvidenceState.absent);
      expect(t.amenities.lock, EvidenceState.unknown);
    });
    test('native V2 wins over legacy booleans on the same doc', () {
      final t = ToiletTruth.fromFirestore({
        ..._v2({'fee': 'free', 'context': 'commercial'}),
        'is_free': false,
        'category': 'govt',
      }, addedBy: 'osm_india_import_2026');
      expect(t.isNativeV2, isTrue);
      expect(t.fee, FeeState.free);
      expect(t.context, FacilityContext.commercial);
    });
  });

  group(
    'native truth_v2 — STRICT: every malformed case -> isNativeV2 false',
    () {
      void malformed(String name, Map<String, dynamic> block) {
        test(name, () {
          final t = ToiletTruth.fromFirestore({
            'truth_v2': block,
          }, addedBy: 'osm_india_import_2026');
          expect(t.isNativeV2, isFalse, reason: name);
          // Falls back conservatively — OSM provenance here.
          expect(t.source, ToiletSource.osm);
          // And surfaces no confident V2 fact from the malformed block.
          expect(t.fee, FeeState.unknown);
          expect(t.context, FacilityContext.unknown);
          expect(t.gender, GenderAccess.unknown);
        });
      }

      Map<String, dynamic> base() => {
            'version': 2,
            'source_type': 'community_submission',
            'recorded_at': Instant.fromDateTime(DateTime(2026, 9, 2)),
            'fee': 'unknown',
            'context': 'unknown',
            'gender': 'unknown',
            'amenities': {..._amenAllUnknown},
          };

      test('truth_v2 is a bare string', () {
        final t = ToiletTruth.fromFirestore({
          'truth_v2': 'nope',
        }, addedBy: 'osm_india_import_2026');
        expect(t.isNativeV2, isFalse);
      });

      malformed('missing source_type', base()..remove('source_type'));
      malformed('unknown source_type', base()..['source_type'] = 'osm');
      malformed('missing recorded_at', base()..remove('recorded_at'));
      malformed('recorded_at wrong type', base()..['recorded_at'] = 'today');
      malformed('missing fee', base()..remove('fee'));
      malformed('bad fee enum', base()..['fee'] = 'gratis');
      malformed('missing context', base()..remove('context'));
      malformed('bad context enum', base()..['context'] = 'nightclub');
      malformed('missing gender', base()..remove('gender'));
      malformed('bad gender enum', base()..['gender'] = 'robot');
      malformed('version is string "2"', base()..['version'] = '2');
      malformed('version != 2', base()..['version'] = 3);
      malformed('missing amenities', base()..remove('amenities'));
      malformed('amenities not a map', base()..['amenities'] = 'none');
      malformed(
        'amenities missing one key',
        base()
          ..['amenities'] = {
            'water': 'unknown',
            'soap': 'unknown',
            'lock': 'unknown',
            'western': 'unknown',
            'wheelchair': 'unknown',
            'baby_change': 'unknown',
          },
      );
      malformed(
        'amenities extra key',
        base()..['amenities'] = {..._amenAllUnknown, 'shower': 'present'},
      );
      malformed(
        'amenity bad enum',
        base()..['amenities'] = {..._amenAllUnknown, 'water': 'yes'},
      );
      malformed('extra truth_v2 key', base()..['confidence'] = 0.9);
      malformed('injected open_now', base()..['open_now'] = true);
    },
  );

  group('unknown provenance', () {
    test('empty added_by => source + status unknown, everything unknown', () {
      final t = ToiletTruth.fromFirestore({
        'is_free': true,
        'category': 'government',
      }, addedBy: '');
      expect(t.source, ToiletSource.unknown);
      expect(t.identityStatus, IdentityStatus.unknown);
      expect(t.fee, FeeState.unknown);
      // category IS read by the community adapter even for unknown provenance;
      // 'government' -> publicToilet context. Provenance/status stay unknown.
      expect(t.context, FacilityContext.publicToilet);
    });
  });

  // Firestore write serialization moved OUT of the core.
  // `newSubmissionFields` is the PURE part (everything except `recorded_at`);
  // the Android write adapter (`truthV2SubmissionMap`) appends the
  // `FieldValue.serverTimestamp()` sentinel. The adapter's byte-identical
  // output vs the legacy in-app `newSubmission()` is covered by the app-side test
  // `test/adapters/firestore_domain_adapter_test.dart`.
  group('newSubmissionFields serialisation (pure)', () {
    test('emits explicit strings incl. context + gender; NO recorded_at', () {
      final m = ToiletTruth.newSubmissionFields(
        fee: FeeState.paid,
        context: FacilityContext.commercial,
        gender: GenderAccess.women,
        amenities: const ToiletAmenities(
          water: EvidenceState.present,
          soap: EvidenceState.absent,
          lock: EvidenceState.unknown,
          western: EvidenceState.unknown,
          wheelchair: EvidenceState.unknown,
          babyChange: EvidenceState.unknown,
          sanitaryDisposal: EvidenceState.unknown,
        ),
      );
      expect(m['version'], 2);
      expect(m['source_type'], 'community_submission');
      expect(m['fee'], 'paid');
      expect(m['context'], 'commercial');
      expect(m['gender'], 'women');
      final am = m['amenities'] as Map<String, String>;
      expect(am['water'], 'present');
      expect(am['soap'], 'absent');
      expect(am.keys.length, 7);
      expect(
          m.containsKey('recorded_at'), isFalse); // added by the write adapter
      expect(m.keys.length, 6);
    });

    test('round-trips through the strict parser', () {
      final m = ToiletTruth.newSubmissionFields(
        fee: FeeState.free,
        context: FacilityContext.publicToilet,
        gender: GenderAccess.unknown,
        amenities: ToiletAmenities.allUnknown,
      );
      final parsed = ToiletTruth.fromFirestore({
        'truth_v2': {
          ...m,
          'recorded_at': Instant.fromDateTime(DateTime(2026, 9, 2)),
        },
      }, addedBy: 'u');
      expect(parsed.isNativeV2, isTrue);
      expect(parsed.fee, FeeState.free);
      expect(parsed.context, FacilityContext.publicToilet);
      expect(parsed.source, ToiletSource.communitySubmission);
    });
  });
}
