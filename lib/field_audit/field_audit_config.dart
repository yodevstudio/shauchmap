// Field Audit Mode — compile-time gate + constants.
//
// This whole `lib/field_audit/` feature is an INTERNAL field-research instrument.
// It is compiled into every build but has NO entry point and NO reachable code
// path unless the app is built/run with:
//
//     --dart-define=FIELD_AUDIT_MODE=true
//
// Audit records are stored LOCALLY ONLY. Nothing here writes to production
// Firestore. See docs/field-audit-method.md.
class FieldAuditConfig {
  FieldAuditConfig._();

  /// True only when built with `--dart-define=FIELD_AUDIT_MODE=true`.
  /// A const false in normal builds, so every `if (FieldAuditConfig.enabled)`
  /// branch is dropped by const-folding.
  static const bool enabled = bool.fromEnvironment(
    'FIELD_AUDIT_MODE',
    defaultValue: false,
  );

  /// Local audit schema version. Written into every record and every export.
  ///
  /// v1 (2026-09) — pre-fieldwork development only. NO real audit
  ///     observations were ever collected under it.
  /// v2 (2026-09) — hardened before first field use: split
  ///     facility-usability from map-reliability, evidence-grade GPS, queue vs
  ///     visit timestamps, mapped/unmapped record context, privacy-safe legacy
  ///     snapshot, soap observation, sample metadata.
  static const String schemaVersion = '2';

  /// No auditor PII is collected. A fixed local label is sufficient.
  static const String auditor = 'founder-audit';

  /// Local folder (under the app documents directory) that holds all audit
  /// state. Kept separate from every other part of the app.
  static const String rootFolder = 'field_audit';

  /// The ONLY legacy `toilets` fields copied into an audit record for
  /// comparison. Everything else — and especially any user/warden/reviewer
  /// identity — is deliberately NOT snapshotted.
  static const List<String> legacyReferenceAllowlist = [
    'is_open',
    'is_free',
    'has_water',
    'has_soap',
    'has_lock',
    'is_wheelchair',
    'is_western',
    'category',
    'gender_type',
    'needs_confirm',
  ];
}
