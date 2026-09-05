// Field Audit — export (CSV + JSON) and the offline EVIDENCE BACKUP bundle.
//
// `auditsToCsv` / `auditsToJsonString` are pure and unit-tested. `shareExport`
// and `shareEvidenceBundle` write files locally FIRST (a copy always survives)
// then hand them to the Android share sheet. No Firebase, no network.
//
//   BACKUP           = ALL records (pending / in_progress / completed / revisit)
//   ANALYSIS DATASET = COMPLETED records only
// Pending queue entries are never presented as completed study observations.

import 'dart:convert';

import 'package:archive/archive.dart';
import 'package:share_plus/share_plus.dart';

import 'field_audit_config.dart';
import 'field_audit_model.dart';
import 'field_audit_store.dart';

const List<String> kCsvColumns = [
  'audit_id',
  'audit_schema_version',
  'auditor',
  'status',
  'record_context',
  'queued_at',
  'visit_started_at',
  'last_saved_at',
  'completed_at',
  'toilet_id',
  'toilet_name',
  'mapped_lat',
  'mapped_lng',
  'mapped_address',
  'source_type',
  'source_ref',
  'auditor_observed_lat',
  'auditor_observed_lng',
  'distance_from_mapped_point_meters',
  'gps_source',
  'gps_accuracy_meters',
  'gps_position_timestamp',
  'gps_age_seconds_at_capture',
  'mapping_outcome',
  'open_at_visit',
  'publicly_accessible_at_visit',
  'water',
  'soap',
  'usable_cubicle',
  'door_or_latch',
  'lighting',
  'western_seat',
  'wheelchair_entry',
  'accessible_toilet',
  'mens_section',
  'womens_section',
  'unisex',
  'fee',
  'fee_amount_inr',
  'cleanliness',
  'cleanliness_note',
  'facility_usable_at_visit',
  'mapped_option_usable_at_visit',
  'ref_is_open',
  'ref_is_free',
  'ref_has_water',
  'ref_has_soap',
  'ref_has_lock',
  'ref_is_wheelchair',
  'ref_is_western',
  'ref_category',
  'ref_gender_type',
  'ref_needs_confirm',
  'sample_plan_id',
  'sample_stratum',
  'sample_cluster',
  'sample_sequence',
  'selection_method',
  'photo_count',
  'photo_filenames',
  'notes',
];

String _csvCell(Object? value) {
  final s = value == null ? '' : value.toString();
  final needsQuote =
      s.contains(',') ||
      s.contains('"') ||
      s.contains('\n') ||
      s.contains('\r');
  if (!needsQuote) return s;
  return '"${s.replaceAll('"', '""')}"';
}

String _num(num? v) => v == null ? '' : v.toString();
String _ref(FieldAudit a, String k) =>
    a.legacyReference.containsKey(k) ? '${a.legacyReference[k]}' : '';

List<String> _row(FieldAudit a) => [
  a.auditId,
  a.auditSchemaVersion,
  a.auditor,
  auditStatusWire(a.status),
  recordContextWire(a.recordContext),
  a.queuedAt.toIso8601String(),
  a.visitStartedAt?.toIso8601String() ?? '',
  a.lastSavedAt.toIso8601String(),
  a.completedAt?.toIso8601String() ?? '',
  a.toiletId ?? '',
  a.toiletName,
  _num(a.mappedLat),
  _num(a.mappedLng),
  a.mappedAddress ?? '',
  sourceTypeWire(a.sourceType),
  a.sourceRef ?? '',
  _num(a.auditorObservedLat),
  _num(a.auditorObservedLng),
  _num(a.distanceFromMappedPointMeters),
  gpsSourceWire(a.gpsSource),
  _num(a.gpsAccuracyMeters),
  a.gpsPositionTimestamp?.toIso8601String() ?? '',
  _num(a.gpsAgeSecondsAtCapture),
  mappingOutcomeWire(a.mappingOutcome),
  yesNoUnknownWire(a.openAtVisit),
  yesNoUnknownWire(a.publiclyAccessibleAtVisit),
  yesNoNotCheckedWire(a.water),
  yesNoNotCheckedWire(a.soap),
  yesNoNotCheckedWire(a.usableCubicle),
  yesNoNotCheckedWire(a.doorOrLatch),
  yesNoNotCheckedWire(a.lighting),
  yesNoNotCheckedWire(a.westernSeat),
  yesNoNotCheckedWire(a.wheelchairEntry),
  yesNoNotCheckedWire(a.accessibleToilet),
  yesNoNotCheckedWire(a.mensSection),
  yesNoNotCheckedWire(a.womensSection),
  yesNoNotCheckedWire(a.unisex),
  feeKindWire(a.fee),
  a.fee == FeeKind.paid ? _num(a.feeAmountInr) : '',
  cleanlinessWire(a.cleanliness),
  a.cleanlinessNote,
  fourStateUsableWire(a.computeFacilityUsable()),
  mappedOptionUsableWire(a.computeMappedOptionUsable()),
  _ref(a, 'is_open'),
  _ref(a, 'is_free'),
  _ref(a, 'has_water'),
  _ref(a, 'has_soap'),
  _ref(a, 'has_lock'),
  _ref(a, 'is_wheelchair'),
  _ref(a, 'is_western'),
  _ref(a, 'category'),
  _ref(a, 'gender_type'),
  _ref(a, 'needs_confirm'),
  a.samplePlanId ?? '',
  a.sampleStratum ?? '',
  a.sampleCluster ?? '',
  _num(a.sampleSequence),
  a.selectionMethod ?? '',
  a.photoFilenames.length.toString(),
  a.photoFilenames.join(';'),
  a.notes,
];

/// One header row + one row per audit. RFC-4180 quoting. Enum strings verbatim.
String auditsToCsv(List<FieldAudit> audits) {
  final b = StringBuffer();
  b.writeln(kCsvColumns.map(_csvCell).join(','));
  for (final a in audits) {
    b.writeln(_row(a).map(_csvCell).join(','));
  }
  return b.toString();
}

/// Full structured objects, pretty-printed, with a schema_version envelope.
String auditsToJsonString(
  List<FieldAudit> audits, {
  DateTime? exportedAt,
  String kind = 'all',
}) {
  final payload = {
    'schema_version': FieldAuditConfig.schemaVersion,
    'app': 'shauchmap-field-audit',
    'kind': kind, // 'all' | 'completed_only'
    'exported_at': (exportedAt ?? DateTime.now()).toIso8601String(),
    'count': audits.length,
    'audits': audits.map((a) => a.toJson()).toList(),
  };
  return const JsonEncoder.withIndent('  ').convert(payload);
}

List<FieldAudit> completedOnly(List<FieldAudit> audits) =>
    audits.where((a) => a.status == AuditStatus.completed).toList();

Map<String, int> countsByStatus(List<FieldAudit> audits) {
  final m = <String, int>{
    'pending': 0,
    'in_progress': 0,
    'completed': 0,
    'revisit': 0,
  };
  for (final a in audits) {
    m[auditStatusWire(a.status)] = (m[auditStatusWire(a.status)] ?? 0) + 1;
  }
  return m;
}

String buildManifest(List<FieldAudit> audits, {DateTime? at}) {
  final completed = completedOnly(audits);
  final photos = <String>{for (final a in audits) ...a.photoFilenames};
  final m = {
    'schema_version': FieldAuditConfig.schemaVersion,
    'app': 'shauchmap-field-audit',
    'exported_at': (at ?? DateTime.now()).toIso8601String(),
    'counts_by_status': countsByStatus(audits),
    'total_records': audits.length,
    'completed_count': completed.length,
    'photo_count': photos.length,
    'note':
        'BACKUP = all records. ANALYSIS DATASET (analysis_completed.*) = '
        'completed records only.',
  };
  return const JsonEncoder.withIndent('  ').convert(m);
}

String _stamp(DateTime t) {
  String two(int n) => n.toString().padLeft(2, '0');
  return '${t.year}${two(t.month)}${two(t.day)}_'
      '${two(t.hour)}${two(t.minute)}${two(t.second)}';
}

String csvFileName([DateTime? t]) =>
    'shauchmap_jodhpur_audit_${_stamp(t ?? DateTime.now())}.csv';
String jsonFileName([DateTime? t]) =>
    'shauchmap_jodhpur_audit_${_stamp(t ?? DateTime.now())}.json';
String bundleFileName([DateTime? t]) =>
    'shauchmap_jodhpur_evidence_${_stamp(t ?? DateTime.now())}.zip';

/// Quick share: CSV + JSON of ALL records, written locally then shared.
Future<({String csvPath, String jsonPath})> shareExport(
  List<FieldAudit> audits,
  FieldAuditStore store,
) async {
  final now = DateTime.now();
  final csv = await store.writeExportString(
    csvFileName(now),
    auditsToCsv(audits),
  );
  final json = await store.writeExportString(
    jsonFileName(now),
    auditsToJsonString(audits, exportedAt: now),
  );
  await Share.shareXFiles(
    [
      XFile(csv.path, mimeType: 'text/csv'),
      XFile(json.path, mimeType: 'application/json'),
    ],
    subject: 'ShauchMap Jodhpur field audit — ALL ${audits.length} records',
    text:
        'BACKUP (all records). Schema v${FieldAuditConfig.schemaVersion}. '
        'No production data written.',
  );
  return (csvPath: csv.path, jsonPath: json.path);
}

/// The evidence backup bundle: one ZIP containing a full backup JSON, the
/// completed-only analysis CSV + JSON, every referenced photo, and a manifest.
/// Written locally first; a local copy is kept even if the share is cancelled.
Future<String> buildEvidenceBundleZipBytesToStore(
  List<FieldAudit> audits,
  FieldAuditStore store, {
  DateTime? at,
}) async {
  final now = at ?? DateTime.now();
  final completed = completedOnly(audits);
  final archive = Archive();

  void addString(String name, String content) =>
      archive.addFile(ArchiveFile.string(name, content));

  addString('backup_all.json', auditsToJsonString(audits, exportedAt: now));
  addString('analysis_completed.csv', auditsToCsv(completed));
  addString(
    'analysis_completed.json',
    auditsToJsonString(completed, exportedAt: now, kind: 'completed_only'),
  );
  addString('manifest.json', buildManifest(audits, at: now));

  final referenced = <String>{for (final a in audits) ...a.photoFilenames};
  var photosIncluded = 0;
  for (final fn in referenced) {
    final f = await store.photoFile(fn);
    if (f == null) continue;
    archive.addFile(ArchiveFile.bytes('photos/$fn', await f.readAsBytes()));
    photosIncluded++;
  }
  addString(
    'manifest_photos.txt',
    'photos_included=$photosIncluded\nphotos_referenced=${referenced.length}\n',
  );

  final zipBytes = ZipEncoder().encode(archive);
  final file = await store.writeExportFile(bundleFileName(now), zipBytes);
  return file.path;
}

Future<String> shareEvidenceBundle(
  List<FieldAudit> audits,
  FieldAuditStore store,
) async {
  final path = await buildEvidenceBundleZipBytesToStore(audits, store);
  final counts = countsByStatus(audits);
  await Share.shareXFiles(
    [XFile(path, mimeType: 'application/zip')],
    subject: 'ShauchMap Jodhpur — EVIDENCE BACKUP',
    text:
        'Evidence bundle (ZIP). BACKUP = all ${audits.length} records; '
        'ANALYSIS DATASET = ${counts['completed'] ?? 0} completed. '
        'Schema v${FieldAuditConfig.schemaVersion}. No production data written.',
  );
  return path;
}
