import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:shauchmap_app/field_audit/field_audit_model.dart';

void main() {
  test('every enum has the exact task wire vocabulary', () {
    expect(RecordContext.values.map(recordContextWire).toList(), [
      'mapped_record',
      'unmapped_discovery',
    ]);
    expect(MappingOutcome.values.map(mappingOutcomeWire).toList(), [
      'confirmed_at_location',
      'found_nearby_but_moved',
      'could_not_locate',
      'duplicate',
      'not_a_toilet',
      'unknown',
      'not_applicable',
    ]);
    // access_prevented was removed in v2.
    expect(
      MappingOutcome.values.map(mappingOutcomeWire),
      isNot(contains('access_prevented')),
    );
    expect(YesNoUnknown.values.map(yesNoUnknownWire).toList(), [
      'yes',
      'no',
      'unknown',
    ]);
    expect(YesNoNotChecked.values.map(yesNoNotCheckedWire).toList(), [
      'yes',
      'no',
      'not_checked',
    ]);
    expect(FeeKind.values.map(feeKindWire).toList(), [
      'free',
      'paid',
      'unknown',
    ]);
    expect(Cleanliness.values.map(cleanlinessWire).toList(), [
      'acceptable',
      'poor',
      'not_checked',
    ]);
    expect(FourStateUsable.values.map(fourStateUsableWire).toList(), [
      'yes',
      'no',
      'indeterminate',
      'not_observed',
    ]);
    expect(MappedOptionUsable.values.map(mappedOptionUsableWire).toList(), [
      'yes',
      'no',
      'indeterminate',
      'not_applicable',
    ]);
    expect(AuditStatus.values.map(auditStatusWire).toList(), [
      'pending',
      'in_progress',
      'completed',
      'revisit',
    ]);
    expect(GpsSource.values.map(gpsSourceWire).toList(), [
      'current',
      'last_known',
      'unavailable',
    ]);
    expect(SourceType.values.map(sourceTypeWire).toList(), [
      'osm_import',
      'community',
      'other',
      'unknown',
    ]);
  });

  test('full FieldAudit JSON round-trip preserves every field (incl. soap, '
      'sample metadata, gps evidence, context)', () {
    final q = DateTime.parse('2026-09-01T08:00:00.000');
    final v = DateTime.parse('2026-09-01T12:30:00.000');
    final gpsTs = DateTime.parse('2026-09-01T12:29:58.000');
    final a =
        FieldAudit(
            auditId: 'fa_1_abc',
            recordContext: RecordContext.mappedRecord,
            queuedAt: q,
            lastSavedAt: v,
            toiletId: 'node_42',
            toiletName: 'Clock Tower Toilet',
            mappedLat: 26.293,
            mappedLng: 73.0187,
            mappedAddress: 'Jodhpur, India',
            sourceType: SourceType.osmImport,
            sourceRef: 'node_42',
            legacyReference: {
              'is_open': true,
              'has_soap': false,
              'category': 'govt',
            },
          )
          ..visitStartedAt = v
          ..status = AuditStatus.completed
          ..completedAt = v
          ..auditorObservedLat = 26.2931
          ..auditorObservedLng = 73.0188
          ..gpsSource = GpsSource.lastKnown
          ..gpsAccuracyMeters = 17.4
          ..gpsPositionTimestamp = gpsTs
          ..gpsAgeSecondsAtCapture = 122
          ..mappingOutcome = MappingOutcome.foundNearbyButMoved
          ..openAtVisit = YesNoUnknown.yes
          ..publiclyAccessibleAtVisit = YesNoUnknown.no
          ..water = YesNoNotChecked.yes
          ..soap = YesNoNotChecked.no
          ..usableCubicle = YesNoNotChecked.notChecked
          ..doorOrLatch = YesNoNotChecked.no
          ..westernSeat = YesNoNotChecked.yes
          ..wheelchairEntry = YesNoNotChecked.no
          ..mensSection = YesNoNotChecked.yes
          ..fee = FeeKind.paid
          ..feeAmountInr = 5
          ..cleanliness = Cleanliness.poor
          ..cleanlinessNote = 'floor wet'
          ..notes = 'attendant present'
          ..samplePlanId = 'jodhpur-2026-09'
          ..sampleStratum = 'core-market'
          ..sampleCluster = 'c3'
          ..sampleSequence = 7
          ..selectionMethod = 'stratified-random'
          ..photoFilenames.add('fa_1_abc__evidence__1.jpg');
    a.recomputeDistance();

    final j = jsonDecode(jsonEncode(a.toJson())) as Map<String, dynamic>;
    final b = FieldAudit.fromJson(j);

    expect(b.recordContext, RecordContext.mappedRecord);
    expect(b.queuedAt, q);
    expect(b.visitStartedAt, v);
    expect(b.completedAt, v);
    expect(b.mappingOutcome, MappingOutcome.foundNearbyButMoved);
    expect(b.publiclyAccessibleAtVisit, YesNoUnknown.no);
    expect(b.water, YesNoNotChecked.yes);
    expect(b.soap, YesNoNotChecked.no);
    expect(b.usableCubicle, YesNoNotChecked.notChecked);
    expect(b.gpsSource, GpsSource.lastKnown);
    expect(b.gpsAccuracyMeters, 17.4);
    expect(b.gpsPositionTimestamp, gpsTs);
    expect(b.gpsAgeSecondsAtCapture, 122);
    expect(b.sourceType, SourceType.osmImport);
    expect(b.sourceRef, 'node_42');
    expect(b.fee, FeeKind.paid);
    expect(b.feeAmountInr, 5);
    expect(b.samplePlanId, 'jodhpur-2026-09');
    expect(b.sampleSequence, 7);
    expect(b.selectionMethod, 'stratified-random');
    expect(b.legacyReference['category'], 'govt');
    expect(b.photoFilenames, ['fa_1_abc__evidence__1.jpg']);
    expect(b.distanceFromMappedPointMeters, isNotNull);

    // derived keys emitted for readers…
    expect(j['facility_usable_at_visit'], isA<String>());
    expect(j['mapped_option_usable_at_visit'], isA<String>());
    // …and recomputed on load, never trusted from disk.
    expect(fourStateUsableWire(b.computeFacilityUsable()), 'no'); // access=no
    // old ambiguous key is gone
    expect(j.containsKey('usable_at_visit'), isFalse);
  });

  test('garbage / missing values never become yes/no — they fall to the safe '
      'default', () {
    final b = FieldAudit.fromJson({
      'audit_id': 'fa_x',
      'queued_at': '2026-09-01T00:00:00.000',
      'toilet_id': 'node_x', // a mapped record
      'water': 'garbage',
      'soap': 42,
      'open_at_visit': null,
      'fee': 'nope',
      'gps_source': 'stale',
      'mapping_outcome': 'access_prevented', // value removed in v2 -> unknown
      'record_context': 'weird', // unrecognised -> inferred from toilet_id
    });
    expect(b.water, YesNoNotChecked.notChecked);
    expect(b.soap, YesNoNotChecked.notChecked);
    expect(b.openAtVisit, YesNoUnknown.unknown);
    expect(b.fee, FeeKind.unknown);
    expect(b.gpsSource, GpsSource.unavailable);
    expect(
      b.recordContext,
      RecordContext.mappedRecord,
    ); // inferred from toilet_id
    expect(
      b.mappingOutcome,
      MappingOutcome.unknown,
    ); // dropped value -> unknown
  });

  test('no toilet_id => inferred unmapped => mapping_outcome forced N/A', () {
    final b = FieldAudit.fromJson({
      'audit_id': 'fa_u',
      'queued_at': '2026-09-01T00:00:00.000',
      'mapping_outcome': 'confirmed_at_location', // ignored for a discovery
    });
    expect(b.recordContext, RecordContext.unmappedDiscovery);
    expect(b.mappingOutcome, MappingOutcome.notApplicable);
  });

  test('a v1 record (started_at, location_result) migrates sensibly', () {
    final b = FieldAudit.fromJson({
      'audit_id': 'fa_v1',
      'started_at': '2026-08-15T09:00:00.000',
      'toilet_id': 'node_9',
      'location_result': 'confirmed_at_location',
      'water': 'yes',
    });
    expect(b.queuedAt, DateTime.parse('2026-08-15T09:00:00.000'));
    expect(b.visitStartedAt, isNull);
    expect(b.recordContext, RecordContext.mappedRecord);
    expect(b.mappingOutcome, MappingOutcome.confirmedAtLocation);
    expect(b.water, YesNoNotChecked.yes);
  });
}
