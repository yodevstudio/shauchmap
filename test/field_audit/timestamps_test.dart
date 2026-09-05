import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:shauchmap_app/field_audit/field_audit_model.dart';
import 'package:shauchmap_app/field_audit/field_audit_store.dart';

void main() {
  test('queued_at and visit_started_at are independent; queue != visit', () {
    final queued = DateTime.parse('2026-09-01T08:00:00.000');
    final a = FieldAudit(
      auditId: 'fa_t',
      recordContext: RecordContext.mappedRecord,
      queuedAt: queued,
      lastSavedAt: queued,
      toiletId: 'node_1',
    );
    // freshly queued: no visit has happened
    expect(a.queuedAt, queued);
    expect(a.visitStartedAt, isNull);

    // the visit begins later, once
    final visit = DateTime.parse('2026-09-01T13:45:00.000');
    a.visitStartedAt = visit;
    expect(a.visitStartedAt, visit);
    expect(a.queuedAt, queued); // unchanged
  });

  test('visit_started_at survives a JSON round-trip and is NOT reset', () {
    final queued = DateTime.parse('2026-09-01T08:00:00.000');
    final visit = DateTime.parse('2026-09-01T13:45:00.000');
    final a = FieldAudit(
      auditId: 'fa_v',
      recordContext: RecordContext.mappedRecord,
      queuedAt: queued,
      lastSavedAt: queued,
      toiletId: 'node_1',
    )..visitStartedAt = visit;

    final b = FieldAudit.fromJson(
      jsonDecode(jsonEncode(a.toJson())) as Map<String, dynamic>,
    );
    expect(b.queuedAt, queued);
    expect(b.visitStartedAt, visit);

    // re-serialising again keeps the SAME visit time (set-once semantics)
    final c = FieldAudit.fromJson(
      jsonDecode(jsonEncode(b.toJson())) as Map<String, dynamic>,
    );
    expect(c.visitStartedAt, visit);
  });

  test('store reload preserves both timestamps; queue-only records keep '
      'visit_started_at null', () async {
    final tmp = Directory.systemTemp.createTempSync('fa2_ts_');
    addTearDown(() => tmp.deleteSync(recursive: true));
    final store = FieldAuditStore(baseDirOverride: tmp);

    final queued = DateTime.parse('2026-09-01T08:00:00.000');
    final queuedOnly = FieldAudit(
      auditId: 'fa_q',
      recordContext: RecordContext.mappedRecord,
      queuedAt: queued,
      lastSavedAt: queued,
      toiletId: 'node_q',
    );
    await store.save(queuedOnly);

    final visited = FieldAudit(
      auditId: 'fa_x',
      recordContext: RecordContext.mappedRecord,
      queuedAt: queued,
      lastSavedAt: queued,
      toiletId: 'node_x',
    )..visitStartedAt = DateTime.parse('2026-09-01T14:00:00.000');
    await store.save(visited);
    await store.flushAll();

    final back = FieldAuditStore(baseDirOverride: tmp);
    final q = await back.load('fa_q');
    final x = await back.load('fa_x');
    expect(q!.visitStartedAt, isNull);
    expect(q.queuedAt, queued);
    expect(x!.visitStartedAt, DateTime.parse('2026-09-01T14:00:00.000'));
  });
}
