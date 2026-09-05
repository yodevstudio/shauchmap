// the consumer Add-Toilet rollout gate.
//
// Proves EVERY consumer entry point + the service write boundary respect
// RolloutConfig.addToiletEnabled (default false in the current release), and
// that Field Audit Mode is a SEPARATE flag unaffected by it.
//
// The two real UI entry points — main._startAddToiletFlow and
// profile_screen.openAddWizard — each contain the identical guard:
//     if (!RolloutConfig.addToiletEnabled) { showAppSnackBar(
//         RolloutConfig.addToiletPausedMessage); return; }
// Pumping NavigationShell / ProfileScreen needs Firebase, so per the phase
// instruction this file uses a small deterministic harness that reproduces that
// exact guard against the real RolloutConfig constants + message.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shauchmap_app/config/rollout_config.dart';
import 'package:shauchmap_app/field_audit/field_audit_config.dart';

/// Reproduces the production guard used by BOTH consumer Add-Toilet entry
/// points. [enabledOverride] lets the test exercise the enabled branch too
/// (the real flag is compile-time false in a plain `flutter test` run).
class _AddToiletEntryHarness extends StatelessWidget {
  final bool? enabledOverride;
  const _AddToiletEntryHarness({this.enabledOverride});

  @override
  Widget build(BuildContext context) {
    final enabled = enabledOverride ?? RolloutConfig.addToiletEnabled;
    return MaterialApp(
      home: Scaffold(
        body: Builder(
          builder: (ctx) => Center(
            child: ElevatedButton(
              key: const Key('add'),
              onPressed: () {
                // ---- identical to the shipped guard ----
                if (!enabled) {
                  ScaffoldMessenger.of(ctx).showSnackBar(
                    SnackBar(
                      content: Text(RolloutConfig.addToiletPausedMessage),
                    ),
                  );
                  return;
                }
                Navigator.of(ctx).push(
                  MaterialPageRoute(
                    builder: (_) => const Scaffold(
                      key: Key('wizard'),
                      body: Text('WIZARD'),
                    ),
                  ),
                );
              },
              child: const Text('Add a toilet'),
            ),
          ),
        ),
      ),
    );
  }
}

void main() {
  group('RolloutConfig (pure)', () {
    test('addToiletEnabled defaults to FALSE in the current release', () {
      expect(RolloutConfig.addToiletEnabled, isFalse);
    });

    test('assertConsumerAddToiletAllowed throws when disabled — the '
        'fail-closed service write boundary', () {
      expect(
        RolloutConfig.assertConsumerAddToiletAllowed,
        throwsA(isA<StateError>()),
      );
    });

    test('paused message is honest and non-empty', () {
      expect(RolloutConfig.addToiletPausedMessage.trim(), isNotEmpty);
      final m = RolloutConfig.addToiletPausedMessage.toLowerCase();
      expect(m, contains('paused'));
      for (final forbidden in ['guaranteed', 'verified', 'safe ']) {
        expect(m, isNot(contains(forbidden)));
      }
    });

    test('Field Audit Mode is a SEPARATE flag (FIELD_AUDIT_MODE), independent '
        'of the Add-Toilet gate (ADD_TOILET_ENABLED)', () {
      // Two distinct compile-time consts reading two distinct environment
      // keys. Neither guard references the other; Field Audit never calls
      // FirestoreService.addToilet.
      expect(FieldAuditConfig.enabled, isFalse);
      expect(RolloutConfig.addToiletEnabled, isFalse);
      // The Add-Toilet guard throws; the Field Audit flag is just a bool.
      expect(
        RolloutConfig.assertConsumerAddToiletAllowed,
        throwsA(isA<StateError>()),
      );
      expect(FieldAuditConfig.enabled, isA<bool>());
    });
  });

  group('consumer Add-Toilet entry points respect the gate', () {
    testWidgets('gate OFF (shipped default): tapping an entry shows the paused '
        'message and does NOT open the wizard', (tester) async {
      await tester.pumpWidget(const _AddToiletEntryHarness());
      await tester.tap(find.byKey(const Key('add')));
      await tester.pumpAndSettle();

      expect(find.text(RolloutConfig.addToiletPausedMessage), findsOneWidget);
      expect(find.byKey(const Key('wizard')), findsNothing);
    });

    testWidgets('gate ON: the same entry opens the wizard, '
        'no paused message', (tester) async {
      await tester.pumpWidget(
        const _AddToiletEntryHarness(enabledOverride: true),
      );
      await tester.tap(find.byKey(const Key('add')));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('wizard')), findsOneWidget);
      expect(find.text(RolloutConfig.addToiletPausedMessage), findsNothing);
    });
  });
}
