import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shauchmap_app/field_audit/field_audit_export.dart';
import 'package:shauchmap_app/field_audit/field_audit_model.dart';
import 'package:shauchmap_app/field_audit/field_audit_store.dart';

FieldAudit _mk(
  String id, {
  RecordContext ctx = RecordContext.mappedRecord,
  AuditStatus status = AuditStatus.completed,
}) {
  final now = DateTime.parse('2026-09-01T09:15:00.000');
  return FieldAudit(
      auditId: id,
      recordContext: ctx,
      queuedAt: now,
      lastSavedAt: now,
      toiletId: ctx == RecordContext.mappedRecord ? 'node_$id' : null,
      toiletName: 'Toilet $id',
    )
    ..status = status
    ..visitStartedAt = now
    ..completedAt = status == AuditStatus.completed ? now : null
    ..mappingOutcome = ctx == RecordContext.mappedRecord
        ? MappingOutcome.foundNearbyButMoved
        : MappingOutcome.notApplicable
    ..water = YesNoNotChecked.yes
    ..soap = YesNoNotChecked.no
    ..fee = FeeKind.paid
    ..feeAmountInr = 5
    ..cleanliness = Cleanliness.poor;
}

void main() {
  test('CSV header is the fixed v2 column list', () {
    final csv = auditsToCsv([_mk('a')]);
    final first = const LineSplitter().convert(csv).first;
    expect(first, kCsvColumns.join(','));
    expect(kCsvColumns, contains('facility_usable_at_visit'));
    expect(kCsvColumns, contains('mapped_option_usable_at_visit'));
    expect(kCsvColumns, contains('soap'));
    expect(kCsvColumns, contains('gps_source'));
    expect(kCsvColumns, contains('gps_accuracy_meters'));
    expect(kCsvColumns, contains('queued_at'));
    expect(kCsvColumns, contains('visit_started_at'));
    expect(kCsvColumns, isNot(contains('usable_at_visit')));
    expect(kCsvColumns, isNot(contains('gps_status')));
  });

  test('enum wire strings verbatim; schema version populated', () {
    final rows = const LineSplitter().convert(auditsToCsv([_mk('a')]));
    final headers = rows.first.split(',');
    final cells = rows[1].split(',');
    String cell(String h) => cells[headers.indexOf(h)];
    expect(cell('mapping_outcome'), 'found_nearby_but_moved');
    expect(cell('soap'), 'no');
    expect(cell('record_context'), 'mapped_record');
    expect(cell('audit_schema_version'), '2');
    expect(cell('fee'), 'paid');
    expect(cell('fee_amount_inr'), '5.0'); // feeAmountInr is a double
  });

  test('fee=free never exports a fee amount', () {
    final a = _mk('free')
      ..fee = FeeKind.free
      ..feeAmountInr = 5;
    final rows = const LineSplitter().convert(auditsToCsv([a]));
    final headers = rows.first.split(',');
    final cells = rows[1].split(',');
    expect(cells[headers.indexOf('fee')], 'free');
    expect(cells[headers.indexOf('fee_amount_inr')], '');
  });

  test('commas / quotes / newlines are RFC-4180 escaped and round-trip', () {
    final a = _mk('esc')
      ..toiletName = 'Sulabh, Clock Tower'
      ..cleanlinessNote = 'wet floor; "slippery"'
      ..notes = 'line one\nline two, still note';
    final csv = auditsToCsv([a]);
    expect(csv.contains('"Sulabh, Clock Tower"'), isTrue);
    expect(csv.contains('"wet floor; ""slippery"""'), isTrue);
    final rec = _parseCsv(csv);
    final h = rec[0];
    final r = rec[1];
    expect(r[h.indexOf('toilet_name')], 'Sulabh, Clock Tower');
    expect(r[h.indexOf('cleanliness_note')], 'wet floor; "slippery"');
    expect(r[h.indexOf('notes')], 'line one\nline two, still note');
  });

  test('completedOnly filters out pending / in_progress / revisit', () {
    final list = [
      _mk('c1', status: AuditStatus.completed),
      _mk('p1', status: AuditStatus.pending),
      _mk('i1', status: AuditStatus.inProgress),
      _mk('r1', status: AuditStatus.revisit),
      _mk('c2', status: AuditStatus.completed),
    ];
    final done = completedOnly(list);
    expect(done.map((e) => e.auditId).toSet(), {'c1', 'c2'});
  });

  test('JSON envelope carries schema_version + kind', () {
    final all = jsonDecode(auditsToJsonString([_mk('a')])) as Map;
    expect(all['schema_version'], '2');
    expect(all['kind'], 'all');
    final done =
        jsonDecode(auditsToJsonString([_mk('a')], kind: 'completed_only'))
            as Map;
    expect(done['kind'], 'completed_only');
  });

  test('manifest counts by status + completed + photos', () {
    final list = [
      _mk('c1', status: AuditStatus.completed)..photoFilenames.add('p1.jpg'),
      _mk('c2', status: AuditStatus.completed)..photoFilenames.add('p1.jpg'),
      _mk('p1', status: AuditStatus.pending),
    ];
    final m = jsonDecode(buildManifest(list)) as Map;
    expect(m['total_records'], 3);
    expect(m['completed_count'], 2);
    expect(m['photo_count'], 1); // de-duplicated
    expect((m['counts_by_status'] as Map)['completed'], 2);
    expect((m['counts_by_status'] as Map)['pending'], 1);
  });

  test('export filenames use SECOND-level timestamps (same-minute unique)', () {
    final t1 = DateTime(2026, 9, 1, 14, 30, 5);
    final t2 = DateTime(2026, 9, 1, 14, 30, 6);
    expect(csvFileName(t1), isNot(csvFileName(t2)));
    expect(bundleFileName(t1), isNot(bundleFileName(t2)));
    expect(csvFileName(t1), endsWith('_143005.csv'));
    expect(bundleFileName(t2), endsWith('_143006.zip'));
  });

  test('evidence bundle ZIP contains backup, completed-only analysis, manifest '
      'and every referenced photo', () async {
    final tmp = Directory.systemTemp.createTempSync('fa2_zip_');
    addTearDown(() => tmp.deleteSync(recursive: true));
    final store = FieldAuditStore(baseDirOverride: tmp);

    final done = _mk('done', status: AuditStatus.completed);
    final photo = await store.savePhotoBytes(
      'done',
      'evidence',
      Uint8List.fromList(const [9, 9, 9, 9]),
    );
    done.photoFilenames.add(photo);
    await store.save(done);

    final pending = _mk('pending', status: AuditStatus.pending);
    await store.save(pending);
    await store.flushAll();

    final all = await store.loadAll();
    final zipPath = await buildEvidenceBundleZipBytesToStore(
      all,
      store,
      at: DateTime(2026, 9, 1, 15, 0, 1),
    );

    final bytes = File(zipPath).readAsBytesSync();
    final arc = ZipDecoder().decodeBytes(bytes);
    final names = arc.files.map((f) => f.name).toSet();
    expect(
      names,
      containsAll(<String>[
        'backup_all.json',
        'analysis_completed.csv',
        'analysis_completed.json',
        'manifest.json',
        'photos/$photo',
      ]),
    );

    // backup keeps pending; analysis is completed-only
    final backup =
        jsonDecode(
              utf8.decode(
                arc.findFile('backup_all.json')!.content as List<int>,
              ),
            )
            as Map;
    expect((backup['audits'] as List).length, 2);
    final analysis =
        jsonDecode(
              utf8.decode(
                arc.findFile('analysis_completed.json')!.content as List<int>,
              ),
            )
            as Map;
    expect((analysis['audits'] as List).length, 1);
    expect(analysis['kind'], 'completed_only');

    // local copy preserved
    expect(File(zipPath).existsSync(), isTrue);
  });
}

/// Minimal RFC-4180 CSV parser for the test.
List<List<String>> _parseCsv(String input) {
  final rows = <List<String>>[];
  var field = StringBuffer();
  var row = <String>[];
  var inQuotes = false;
  for (var i = 0; i < input.length; i++) {
    final ch = input[i];
    if (inQuotes) {
      if (ch == '"') {
        if (i + 1 < input.length && input[i + 1] == '"') {
          field.write('"');
          i++;
        } else {
          inQuotes = false;
        }
      } else {
        field.write(ch);
      }
    } else if (ch == '"') {
      inQuotes = true;
    } else if (ch == ',') {
      row.add(field.toString());
      field = StringBuffer();
    } else if (ch == '\n') {
      row.add(field.toString());
      rows.add(row);
      row = <String>[];
      field = StringBuffer();
    } else if (ch != '\r') {
      field.write(ch);
    }
  }
  if (field.isNotEmpty || row.isNotEmpty) {
    row.add(field.toString());
    rows.add(row);
  }
  return rows;
}
