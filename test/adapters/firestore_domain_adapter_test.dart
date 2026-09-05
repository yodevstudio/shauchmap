// The Android <-> shauchmap_core adapter boundary.
//
//  * normalizeFirestoreTimestamps converts EVERY nested Firestore `Timestamp`
//    (truth_v2.recorded_at; evidence_v2.{ratings,votes,condition}.{computed_at,
//    last_event_at}; evidence_v2.condition.{latest_at,valid_until}; top-level
//    created_at / last_verified / flagged_until / women_safe_until) to a core
//    `Instant`, and leaves malformed values alone so the strict parser still
//    rejects them.
//  * toiletFromFirestore(doc) reproduces the legacy in-app `Toilet.fromFirestore`
//    read for representative real document shapes A-E.
//  * truthV2SubmissionMap(...) reproduces the legacy in-app `ToiletTruth.newSubmission`
//    Firestore write shape byte-for-byte (incl. the `recorded_at` server
//    sentinel), preserving Add-Toilet semantics even though the gate is off.

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shauchmap_app/adapters/firestore_domain_adapter.dart';
import 'package:shauchmap_core/shauchmap_core.dart';

Timestamp _ts(String iso) => Timestamp.fromDate(DateTime.parse(iso));

/// The adapter's composition without a DocumentSnapshot:
/// toiletFromFirestore(doc) == Toilet.fromMap(doc.id, normalize(doc.data())).
Toilet _adapt(Map<String, dynamic> data) => Toilet.fromMap(
  'T',
  (normalizeFirestoreTimestamps(data) as Map).cast<String, dynamic>(),
);

void main() {
  group('nested Timestamp normalization', () {
    test('every nested Timestamp -> Instant; malformed passes through', () {
      final raw = {
        'created_at': _ts('2026-06-01T00:00:00Z'),
        'last_verified': _ts('2026-06-02T00:00:00Z'),
        'flagged_until': _ts('2026-06-03T00:00:00Z'),
        'women_safe_until': _ts('2026-06-04T00:00:00Z'),
        'truth_v2': {'recorded_at': _ts('2026-06-05T00:00:00Z')},
        'evidence_v2': {
          'ratings': {
            'computed_at': _ts('2026-06-06T00:00:00Z'),
            'last_event_at': _ts('2026-06-06T00:00:00Z'),
          },
          'votes': {
            'computed_at': _ts('2026-06-07T00:00:00Z'),
            'last_event_at': _ts('2026-06-07T00:00:00Z'),
          },
          'condition': {
            'computed_at': _ts('2026-06-08T00:00:00Z'),
            'last_event_at': _ts('2026-06-08T00:00:00Z'),
            'latest_at': _ts('2026-06-08T00:00:00Z'),
            'valid_until': _ts('2026-06-08T01:00:00Z'),
            'bad_field': 'not-a-timestamp',
          },
        },
      };
      final out = normalizeFirestoreTimestamps(raw) as Map;
      final ev = out['evidence_v2'] as Map;
      final cond = ev['condition'] as Map;

      expect(out['created_at'], isA<Instant>());
      expect(out['last_verified'], isA<Instant>());
      expect(out['flagged_until'], isA<Instant>());
      expect(out['women_safe_until'], isA<Instant>());
      expect((out['truth_v2'] as Map)['recorded_at'], isA<Instant>());
      expect((ev['ratings'] as Map)['computed_at'], isA<Instant>());
      expect((ev['ratings'] as Map)['last_event_at'], isA<Instant>());
      expect((ev['votes'] as Map)['computed_at'], isA<Instant>());
      expect(cond['computed_at'], isA<Instant>());
      expect(cond['last_event_at'], isA<Instant>());
      expect(cond['latest_at'], isA<Instant>());
      expect(cond['valid_until'], isA<Instant>());
      expect(
        cond['bad_field'],
        'not-a-timestamp',
      ); // untouched -> still rejected downstream

      expect(
        (out['created_at'] as Instant).toDateTime().toUtc(),
        DateTime.parse('2026-06-01T00:00:00Z'),
      );
      expect(
        (cond['valid_until'] as Instant).toDateTime().toUtc(),
        DateTime.parse('2026-06-08T01:00:00Z'),
      );
    });
  });

  group('real-document adapter shapes A-E — toiletFromFirestore', () {
    test('A. legacy OSM, no evidence', () async {
      final t = _adapt({
        'name': 'Public Toilet',
        'address': 'Maharashtra, India',
        'added_by': 'osm_india_import_2026',
        'category': 'govt',
        'gender_type': 'unisex',
        'latitude': 20.0631714,
        'longitude': 78.9609611,
        'is_open': true,
        'is_free': true,
        'has_water': false,
      });
      expect(t.id, 'T');
      expect(t.truth.identityStatus, IdentityStatus.sourceMapped);
      expect(t.truth.source, ToiletSource.osm);
      expect(t.truth.fee, FeeState.unknown);
      expect(
        t.truth.gender,
        GenderAccess.unknown,
      ); // 'unisex' default -> UNKNOWN
      expect(t.evidence.present, isFalse);
    });

    test('B. OSM with evidence_v2.ratings', () async {
      final t = _adapt({
        'name': 'Public Toilet',
        'added_by': 'osm_india_import_2026',
        'category': 'govt',
        'latitude': 26.2729044,
        'longitude': 72.9760599,
        'evidence_v2': {
          'version': 1,
          'ratings': {
            'count': 1,
            'average': 3,
            'computed_at': _ts('2026-09-03T11:52:53Z'),
            'last_event_at': _ts('2026-09-03T11:52:50Z'),
          },
        },
      });
      expect(t.evidence.present, isTrue);
      expect(t.evidence.ratings.available, isTrue);
      expect(t.evidence.ratings.count, 1);
      expect(t.evidence.ratings.average, 3.0);
      expect(t.evidence.condition.available, isFalse);
    });

    test(
      'C. FIXTURE (synthetic, schema-valid) condition Evidence V2',
      () async {
        // NOT a production document — a schema-valid condition section built to
        // the authoritative Functions/test contract so the adapter's condition
        // path is exercised. Production currently has ZERO condition docs.
        final t = _adapt({
          'name': 'Fixture Toilet',
          'added_by': 'osm_india_import_2026',
          'latitude': 26.24,
          'longitude': 73.02,
          'evidence_v2': {
            'version': 1,
            'condition': {
              'open': 'yes',
              'water': 'unknown',
              'usable': 'yes',
              'lock': 'unknown',
              'contributor_count': 3,
              'latest_at': _ts('2026-09-03T12:00:00Z'),
              'valid_until': _ts('2026-09-03T13:00:00Z'),
              'computed_at': _ts('2026-09-03T12:01:00Z'),
              'last_event_at': _ts('2026-09-03T12:00:00Z'),
              'support': {
                'open': {'yes': 3, 'no': 0, 'unknown': 0},
                'water': {'yes': 0, 'no': 0, 'unknown': 3},
                'usable': {'yes': 3, 'no': 0, 'unknown': 0},
                'lock': {'yes': 0, 'no': 0, 'unknown': 3},
              },
            },
          },
        });
        expect(t.evidence.condition.available, isTrue);
        expect(t.evidence.condition.usable, ConditionState.yes);
        expect(t.evidence.condition.contributorCount, 3);
        final at = DateTime.parse('2026-09-03T12:30:00Z');
        expect(t.evidence.condition.isCurrentlyValid(at), isTrue);
        expect(
          t.evidence.condition.isCurrentlyValid(
            DateTime.parse('2026-09-03T13:00:01Z'),
          ),
          isFalse,
        ); // passive expiry
      },
    );

    test(
      'D. community-submitted (legacy adapter — no native truth_v2)',
      () async {
        final t = _adapt({
          'name': 'Sulabh Sauchalaya',
          'added_by': 'SOME_USER_UID',
          'created_at': _ts('2026-06-05T14:25:23Z'),
          'category': 'govt',
          'gender_type': 'unisex',
          'latitude': 26.276,
          'longitude': 73.014,
          'has_lock': true,
          'has_soap': true,
          'has_water': true,
        });
        expect(t.truth.identityStatus, IdentityStatus.communitySubmitted);
        expect(t.truth.source, ToiletSource.legacyCommunity);
        expect(t.truth.isNativeV2, isFalse);
        expect(t.createdAt?.toUtc(), DateTime.parse('2026-06-05T14:25:23Z'));
      },
    );

    test(
      'E. MALFORMED native truth_v2 -> falls back to legacy adapter',
      () async {
        final t = _adapt({
          'name': 'Bad V2',
          'added_by': 'SOME_USER_UID',
          'latitude': 26.2,
          'longitude': 73.0,
          'truth_v2': {
            'version': 2,
            'source_type': 'community_submission',
            'recorded_at': _ts('2026-09-01T00:00:00Z'),
            'fee': 'paid',
            'context': 'petrol_station',
            // 'gender' MISSING -> whole block invalid
            'amenities': {
              'water': 'present',
              'soap': 'absent',
              'lock': 'present',
              'western': 'unknown',
              'wheelchair': 'absent',
              'baby_change': 'unknown',
              'sanitary_disposal': 'present',
            },
          },
        });
        expect(t.truth.isNativeV2, isFalse); // strict parser rejected it
        expect(t.truth.identityStatus, IdentityStatus.communitySubmitted);
      },
    );
  });

  group('truthV2SubmissionMap — byte-identical write shape', () {
    test(
      'produces {version, source_type, fee, context, gender, amenities, '
      'recorded_at: <server sentinel>} — same as the legacy in-app newSubmission',
      () {
        final m = truthV2SubmissionMap(
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
        expect((m['amenities'] as Map).length, 7);
        expect((m['amenities'] as Map)['water'], 'present');
        // the deployed rule pins recorded_at == request.time via serverTs():
        expect(m['recorded_at'], isA<FieldValue>());
        expect(m.keys.length, 7);
      },
    );
  });
}
