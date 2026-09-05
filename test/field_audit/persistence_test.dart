import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:shauchmap_app/field_audit/field_audit_model.dart';
import 'package:shauchmap_app/field_audit/field_audit_store.dart';

void main() {
  late Directory tmp;
  late FieldAuditStore store;

  setUp(() {
    tmp = Directory.systemTemp.createTempSync('fa2_test_');
    store = FieldAuditStore(baseDirOverride: tmp);
  });

  tearDown(() {
    if (tmp.existsSync()) tmp.deleteSync(recursive: true);
  });

  FieldAudit sample(String id, {DateTime? queued}) {
    final now = queued ?? DateTime(2026, 9, 1, 9, id.length);
    return FieldAudit(
      auditId: id,
      recordContext: RecordContext.mappedRecord,
      queuedAt: now,
      lastSavedAt: now,
      toiletId: 'node_$id',
      toiletName: 'Toilet $id',
    )..mappingOutcome = MappingOutcome.confirmedAtLocation;
  }

  test('save + load round-trips a record', () async {
    final a = sample('fa_a')..water = YesNoNotChecked.yes;
    await store.save(a);
    final b = await store.load('fa_a');
    expect(b, isNotNull);
    expect(b!.toiletName, 'Toilet fa_a');
    expect(b.water, YesNoNotChecked.yes);
  });

  test(
    'loadAll is newest visit/queue time first and survives a "restart"',
    () async {
      await store.save(sample('fa_1'));
      await store.save(sample('fa_22'));
      await store.save(sample('fa_333'));
      await store.flushAll();

      final store2 = FieldAuditStore(baseDirOverride: tmp);
      final all = await store2.loadAll();
      expect(all.map((e) => e.auditId), ['fa_333', 'fa_22', 'fa_1']);
    },
  );

  test('CONCURRENCY: 250 overlapping unawaited saves => final persisted state '
      'is the LAST requested one', () async {
    final a = sample('fa_race');
    for (var i = 0; i < 250; i++) {
      a.notes = 'v$i';
      // deliberately NOT awaited — simulates rapid chip/textfield edits
      // ignore: unawaited_futures
      store.save(a);
    }
    await store.flush('fa_race'); // Save / Complete would await this
    final b = await store.load('fa_race');
    expect(b!.notes, 'v249');

    // a final awaited save must also win
    a.notes = 'FINAL';
    a.status = AuditStatus.completed;
    await store.save(a);
    final c = await store.load('fa_race');
    expect(c!.notes, 'FINAL');
    expect(c.status, AuditStatus.completed);
  });

  test('CONCURRENCY: an older snapshot never overwrites a newer one even when '
      'writes interleave', () async {
    final a = sample('fa_order');
    final futures = <Future<void>>[];
    for (var i = 0; i < 60; i++) {
      a.notes = 'n$i';
      futures.add(store.save(a)); // capture, but keep firing
    }
    await Future.wait(futures);
    final b = await store.load('fa_order');
    expect(b!.notes, 'n59');
  });

  test(
    'a partial .tmp file is ignored by loadAll (crash-mid-write safety)',
    () async {
      await store.save(sample('fa_ok'));
      await store.flushAll();
      final dir = Directory('${tmp.path}/field_audit/audits');
      File('${dir.path}/fa_broken.json.tmp').writeAsStringSync('{ not valid');
      final all = await store.loadAll();
      expect(all.map((e) => e.auditId), ['fa_ok']);
    },
  );

  test('a corrupt .json is skipped, the rest of the queue is intact', () async {
    await store.save(sample('fa_good'));
    await store.flushAll();
    final dir = Directory('${tmp.path}/field_audit/audits');
    File('${dir.path}/fa_corrupt.json').writeAsStringSync('NOT JSON');
    final all = await store.loadAll();
    expect(all.map((e) => e.auditId), ['fa_good']);
  });

  test('delete removes the record and its photos', () async {
    final a = sample('fa_del');
    final fn = await store.savePhotoBytes(
      'fa_del',
      'evidence',
      Uint8List.fromList(const [1, 2, 3, 4]),
    );
    a.photoFilenames.add(fn);
    await store.save(a);
    expect(await store.photoFile(fn), isNotNull);
    await store.delete('fa_del');
    expect(await store.load('fa_del'), isNull);
    expect(await store.photoFile(fn), isNull);
  });
}
