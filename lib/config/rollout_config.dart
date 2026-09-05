// ShauchMap — release rollout gates.
//
// Compile-time flags for the narrow, honest production gates the current
// release needs. They are set with --dart-define at build time; the DEFAULTS
// are the safe current-release values.

class RolloutConfig {
  RolloutConfig._();

  /// Whether the CONSUMER Add-Toilet flow is available in THIS build.
  ///
  /// DEFAULT: **false** in the current public release.
  ///
  /// WHY: creating a native Truth V2 toilet is only fully safe once there is an
  /// enforceable minimum-supported-app-version story. The repo has NO
  /// version-gate / Remote Config / forced-update mechanism, and the size of
  /// any uncontrolled old-client install base is UNKNOWN. A materially old
  /// client that reads a native `truth_v2` toilet with its legacy parser would
  /// present UNKNOWN identity / fee / amenities as fabricated
  /// "open / free / government / unisex" state.
  ///
  /// SECURITY BOUNDARY: this is NOT one. It is a SHIPPED-CLIENT UX gate and an
  /// accidental-use gate only. A modified or re-compiled client can set
  /// `--dart-define=ADD_TOILET_ENABLED=true` and submit a valid native V2
  /// create against whatever the deployed Firestore rules allow. The only real
  /// enforcement against arbitrary clients is a SERVER rule
  /// (`/toilets` `allow create: if false` in the current server policy). Do not
  /// claim this flag protects old clients or blocks modified clients.
  ///
  /// Re-enable once a min-version policy is enforceable:
  ///   flutter build apk --dart-define=ADD_TOILET_ENABLED=true
  ///
  /// Field Audit Mode (`--dart-define=FIELD_AUDIT_MODE=true`) is a SEPARATE,
  /// local-only flow and is unaffected by this flag. Field Audit never calls
  /// `FirestoreService.addToilet`.
  static const bool addToiletEnabled = bool.fromEnvironment(
    'ADD_TOILET_ENABLED',
    defaultValue: false,
  );

  /// User-facing copy shown when [addToiletEnabled] is false. Used by EVERY
  /// consumer entry point so the copy never diverges.
  static const String addToiletPausedMessage =
      'Adding new toilets is temporarily paused in this release.';

  /// Fail-closed guard for the consumer write boundary
  /// (`FirestoreService.addToilet`). Throws when the consumer Add-Toilet flow
  /// is disabled, so a native V2 create can never be reached from consumer code
  /// even if a UI entry point is missed. Callable in a pure test.
  static void assertConsumerAddToiletAllowed() {
    if (!addToiletEnabled) {
      throw StateError(
        'Consumer Add Toilet is paused in this release '
        '(RolloutConfig.addToiletEnabled == false). This is a client UX / '
        'accidental-use guard, not a security boundary — the server rule is '
        'the real enforcement.',
      );
    }
  }
}
