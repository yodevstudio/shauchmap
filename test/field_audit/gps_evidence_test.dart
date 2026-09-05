import 'package:flutter_test/flutter_test.dart';
import 'package:shauchmap_app/field_audit/field_audit_model.dart';

FieldAudit _mk() {
  final now = DateTime(2026, 9, 1, 12);
  return FieldAudit(
    auditId: 'fa_gps',
    recordContext: RecordContext.mappedRecord,
    queuedAt: now,
    lastSavedAt: now,
    toiletId: 'node_1',
    mappedLat: 26.2900,
    mappedLng: 73.0300,
  );
}

final _t0 = DateTime(2026, 9, 1, 12, 0, 0);
final _t1 = DateTime(2026, 9, 1, 12, 0, 30);
final _now = DateTime(2026, 9, 1, 12, 1, 0);

void main() {
  test(
    'current fix is recorded with accuracy + timestamp + age + distance',
    () {
      final a = _mk();
      final note = a.applyGpsAttempt(
        GpsAttempt.current(26.2905, 73.0305, 6.0, _now),
        now: _now,
      );
      expect(note, isNull);
      expect(a.gpsSource, GpsSource.current);
      expect(a.auditorObservedLat, 26.2905);
      expect(a.gpsAccuracyMeters, 6.0);
      expect(a.gpsPositionTimestamp, _now);
      expect(a.gpsAgeSecondsAtCapture, 0);
      expect(a.distanceFromMappedPointMeters, isNotNull);
    },
  );

  test(
    'last-known fix (no prior) is recorded explicitly as last_known with its '
    'real age — never as current',
    () {
      final a = _mk();
      final note = a.applyGpsAttempt(
        GpsAttempt.lastKnown(26.2907, 73.0307, 40.0, _t0),
        now: _now,
      );
      expect(a.gpsSource, GpsSource.lastKnown);
      expect(a.gpsAgeSecondsAtCapture, 60);
      expect(a.gpsAccuracyMeters, 40.0);
      expect(note, contains('LAST-KNOWN'));
    },
  );

  test(
    'FAILED attempt with NO prior fix => everything cleared to unavailable',
    () {
      final a = _mk();
      final note = a.applyGpsAttempt(const GpsAttempt.failed(), now: _now);
      expect(a.gpsSource, GpsSource.unavailable);
      expect(a.auditorObservedLat, isNull);
      expect(a.auditorObservedLng, isNull);
      expect(a.gpsAccuracyMeters, isNull);
      expect(a.gpsPositionTimestamp, isNull);
      expect(a.gpsAgeSecondsAtCapture, isNull);
      expect(a.distanceFromMappedPointMeters, isNull);
      expect(note, contains('not recorded'));
    },
  );

  test('FAILED attempt with a VALID PRIOR fix => prior evidence untouched, '
      'transient message only', () {
    final a = _mk();
    a.applyGpsAttempt(GpsAttempt.current(26.2905, 73.0305, 6.0, _t1), now: _t1);
    final priorLat = a.auditorObservedLat;
    final priorAcc = a.gpsAccuracyMeters;
    final priorDist = a.distanceFromMappedPointMeters;

    final note = a.applyGpsAttempt(const GpsAttempt.failed(), now: _now);
    expect(note, 'New GPS fix unavailable — previous recorded fix retained.');
    expect(a.gpsSource, GpsSource.current); // NOT downgraded
    expect(a.auditorObservedLat, priorLat);
    expect(a.gpsAccuracyMeters, priorAcc);
    expect(a.distanceFromMappedPointMeters, priorDist);
  });

  test('last-known NEVER replaces an existing current fix', () {
    final a = _mk();
    a.applyGpsAttempt(GpsAttempt.current(26.2905, 73.0305, 6.0, _t1), now: _t1);
    final note = a.applyGpsAttempt(
      GpsAttempt.lastKnown(11.11, 22.22, 99.0, _now), // "newer" but last-known
      now: _now,
    );
    expect(note, contains('current fix is already recorded'));
    expect(a.gpsSource, GpsSource.current);
    expect(a.auditorObservedLat, 26.2905);
  });

  test(
    'a newer last-known replaces an OLDER last-known; an older one does not',
    () {
      final a = _mk();
      a.applyGpsAttempt(
        GpsAttempt.lastKnown(26.2900, 73.0300, 50.0, _t0),
        now: _now,
      );
      // older than what we already have -> ignored
      final older = a.applyGpsAttempt(
        GpsAttempt.lastKnown(1.0, 2.0, 5.0, DateTime(2026, 9, 1, 11, 59, 0)),
        now: _now,
      );
      expect(older, contains('equal/newer fix is already recorded'));
      expect(a.auditorObservedLat, 26.2900);

      // strictly newer last-known -> replaces
      a.applyGpsAttempt(
        GpsAttempt.lastKnown(26.2950, 73.0350, 12.0, _t1),
        now: _now,
      );
      expect(a.auditorObservedLat, 26.2950);
      expect(a.gpsAccuracyMeters, 12.0);
      expect(a.gpsSource, GpsSource.lastKnown);
    },
  );

  test('a fresh current fix always replaces a prior last-known', () {
    final a = _mk();
    a.applyGpsAttempt(
      GpsAttempt.lastKnown(26.2900, 73.0300, 50.0, _t0),
      now: _now,
    );
    a.applyGpsAttempt(
      GpsAttempt.current(26.2960, 73.0360, 4.0, _now),
      now: _now,
    );
    expect(a.gpsSource, GpsSource.current);
    expect(a.auditorObservedLat, 26.2960);
    expect(a.gpsAgeSecondsAtCapture, 0);
  });

  test('export can never show gps_source=unavailable with stale coordinates', () {
    final a = _mk();
    a.applyGpsAttempt(GpsAttempt.current(26.2905, 73.0305, 6.0, _t1), now: _t1);
    // simulate: audit had a fix, then we (hypothetically) force-clear it
    a.applyGpsAttempt(const GpsAttempt.failed(), now: _now); // prior kept
    // now delete the prior to prove the "no prior" branch also stays consistent
    final a2 = _mk();
    a2.applyGpsAttempt(const GpsAttempt.failed(), now: _now);
    final j = a2.toJson();
    expect(j['gps_source'], 'unavailable');
    expect(j['auditor_observed_lat'], isNull);
    expect(j['auditor_observed_lng'], isNull);
    expect(j['distance_from_mapped_point_meters'], isNull);
  });
}
