import 'package:flutter_test/flutter_test.dart';
import 'package:shauchmap_app/field_audit/field_audit_model.dart';

FieldAudit _mk(AuditStatus status, {DateTime? completedAt}) {
  final now = DateTime(2026, 9, 1, 12);
  return FieldAudit(
      auditId: 'fa_edit',
      recordContext: RecordContext.mappedRecord,
      queuedAt: now,
      lastSavedAt: now,
      toiletId: 'node_1',
    )
    ..status = status
    ..visitStartedAt = now
    ..completedAt =
        completedAt ?? (status == AuditStatus.completed ? now : null);
}

void main() {
  group('beginEdit() — first mutation of a record in an editing session', () {
    test('pending -> in_progress, no completion notice', () {
      final a = _mk(AuditStatus.pending);
      final wasCompleted = a.beginEdit();
      expect(a.status, AuditStatus.inProgress);
      expect(a.completedAt, isNull);
      expect(wasCompleted, isFalse);
    });

    test('in_progress stays in_progress and reports nothing', () {
      final a = _mk(AuditStatus.inProgress);
      expect(a.beginEdit(), isFalse);
      expect(a.status, AuditStatus.inProgress);
    });

    test('completed -> in_progress AND completed_at cleared AND flagged', () {
      final a = _mk(AuditStatus.completed);
      expect(a.completedAt, isNotNull);
      final wasCompleted = a.beginEdit();
      expect(a.status, AuditStatus.inProgress);
      expect(a.completedAt, isNull);
      expect(wasCompleted, isTrue); // UI shows the "completion cleared" notice
    });

    test('revisit -> in_progress AND completed_at cleared', () {
      final a = _mk(AuditStatus.revisit, completedAt: DateTime(2026, 9, 1, 11));
      final wasCompleted = a.beginEdit();
      expect(a.status, AuditStatus.inProgress);
      expect(a.completedAt, isNull);
      // not "completed" specifically, so no dataset-warning toast
      expect(wasCompleted, isFalse);
    });

    test('a second edit of an already-invalidated record is a no-op', () {
      final a = _mk(AuditStatus.completed);
      a.beginEdit();
      final again = a.beginEdit();
      expect(again, isFalse);
      expect(a.status, AuditStatus.inProgress);
      expect(a.completedAt, isNull);
    });
  });

  test('an edited completed record leaves the completed-only dataset until it '
      'is re-completed', () {
    final a = _mk(AuditStatus.completed);
    a.beginEdit(); // one chip changed
    expect(
      a.status,
      isNot(AuditStatus.completed),
    ); // dropped out of the dataset

    // the auditor presses "Save & complete" again
    a.status = AuditStatus.completed;
    a.completedAt = DateTime(2026, 9, 1, 13);
    expect(a.status, AuditStatus.completed);
    expect(a.completedAt, isNotNull);
  });
}
