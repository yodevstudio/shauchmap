import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:shauchmap_app/field_audit/field_audit_config.dart';
import 'package:shauchmap_app/field_audit/field_audit_model.dart';

void main() {
  test('legacyReference keeps ONLY the allowlisted, identity-free fields', () {
    final now = DateTime(2026, 9, 1);
    final a = FieldAudit(
      auditId: 'fa_ref',
      recordContext: RecordContext.mappedRecord,
      queuedAt: now,
      lastSavedAt: now,
      toiletId: 'node_1',
      legacyReference: {
        // allowlisted
        'is_open': true,
        'is_free': true,
        'has_water': false,
        'has_soap': false,
        'has_lock': false,
        'is_wheelchair': false,
        'is_western': false,
        'category': 'govt',
        'gender_type': 'unisex',
        'needs_confirm': false,
        // MUST be dropped
        'added_by': 'OkzA7s2IQlgNqMTRdluerzg9uhQ2',
        'warden_user_id': 'someUid123456789012345',
        'warden_name': 'Real Person',
        'email': 'person@example.com',
        'star_rating': 4.5,
        'upvote_count': 3,
        'position': {'geohash': 'ts1'},
        'random_unexpected_scalar': 'leak?',
      },
    );

    for (final k in FieldAuditConfig.legacyReferenceAllowlist) {
      expect(a.legacyReference.containsKey(k), isTrue, reason: '$k kept');
    }
    for (final bad in [
      'added_by',
      'warden_user_id',
      'warden_name',
      'email',
      'star_rating',
      'upvote_count',
      'position',
      'random_unexpected_scalar',
    ]) {
      expect(
        a.legacyReference.containsKey(bad),
        isFalse,
        reason: '$bad dropped',
      );
    }
    // and it stays clean through a round-trip
    final b = FieldAudit.fromJson(
      jsonDecode(jsonEncode(a.toJson())) as Map<String, dynamic>,
    );
    expect(
      b.legacyReference.keys.toSet().difference(
        FieldAuditConfig.legacyReferenceAllowlist.toSet(),
      ),
      isEmpty,
    );
  });

  test('a tampered file cannot smuggle extra legacy keys back in', () {
    final b = FieldAudit.fromJson({
      'audit_id': 'fa_tamper',
      'queued_at': '2026-09-01T00:00:00.000',
      'toilet_id': 'node_1',
      'legacy_reference': {
        'is_open': true,
        'added_by': 'sneaky-uid-000000000000',
        'email': 'x@y.z',
      },
    });
    expect(b.legacyReference.keys.toList(), ['is_open']);
  });

  test('classifySourceType buckets provenance without keeping the raw id', () {
    expect(classifySourceType('osm_india_import_2026'), SourceType.osmImport);
    expect(
      classifySourceType('osm_india_import_2026_extended'),
      SourceType.osmImport,
    );
    expect(classifySourceType('osm_import'), SourceType.osmImport);
    expect(
      classifySourceType('OkzA7s2IQlgNqMTRdluerzg9uhQ2'),
      SourceType.community,
    ); // 20+ char uid
    expect(classifySourceType(''), SourceType.unknown);
    expect(classifySourceType(null), SourceType.unknown);
    expect(classifySourceType('field-team-3'), SourceType.other);
  });

  test('source_ref may carry an osm id but never a community uid path', () {
    final now = DateTime(2026, 9, 1);
    final a = FieldAudit(
      auditId: 'fa_src',
      recordContext: RecordContext.mappedRecord,
      queuedAt: now,
      lastSavedAt: now,
      toiletId: 'node_5',
      sourceType: SourceType.osmImport,
      sourceRef: 'node_5',
    );
    final j = a.toJson();
    expect(j['source_type'], 'osm_import');
    expect(j['source_ref'], 'node_5');
    expect(j.containsKey('source_added_by'), isFalse);
  });
}
