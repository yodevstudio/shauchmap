// replaced the obsolete "App loads and shows a CircularProgressIndicator"
// scaffold test (ShauchMapApp needs Firebase and no longer opens on a bare spinner)
// with real component smoke tests for GO-preview surfaces that DON'T need
// Firebase: the live-status label and the travel-mode sheet's distance-honesty
// disclaimer.

// evidence fixtures use the core Instant (what toiletFromFirestore
// normalizes Firestore Timestamps to before parsing).
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shauchmap_app/services/firestore_service.dart';
import 'package:shauchmap_app/widgets/evidence_status_label.dart';
import 'package:shauchmap_app/widgets/travel_mode_sheet.dart';

Instant _ts(DateTime d) => Instant.fromDateTime(d);

Toilet _toilet({ToiletEvidence evidence = ToiletEvidence.unavailable}) =>
    Toilet(
      id: 't1',
      name: 'T',
      address: 'A',
      latitude: 26.3,
      longitude: 73.1,
      category: 'govt',
      starRating: 0,
      totalRatings: 0,
      isOpen: true,
      isFree: true,
      genderType: 'unisex',
      hasWater: false,
      hasSoap: false,
      hasLock: false,
      isWheelchair: false,
      hasBabyChange: false,
      hasSanitaryDisposal: false,
      isWestern: false,
      womenSafeFlag: false,
      flaggedRaw: false,
      flaggedUntil: null,
      addedBy: 'osm_x',
      evidence: evidence,
    );

void main() {
  testWidgets('GO preview live-status label renders "unconfirmed" with no '
      'evidence', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(body: Center(child: EvidenceStatusLabel(_toilet()))),
      ),
    );
    expect(find.text('Status unconfirmed'), findsOneWidget);
  });

  testWidgets('GO preview live-status label surfaces a corroborated "usable" '
      'report', (tester) async {
    final now = DateTime(2026, 9, 2, 12);
    final ev = ToiletEvidence.fromFirestore({
      'version': 1,
      'condition': {
        'open': 'yes',
        'water': 'unknown',
        'usable': 'yes',
        'lock': 'unknown',
        'contributor_count': 2,
        'latest_at': _ts(now.subtract(const Duration(minutes: 3))),
        'valid_until': _ts(now.add(const Duration(minutes: 40))),
        'computed_at': _ts(now),
        'last_event_at': _ts(now),
        'support': {
          'open': {'yes': 2, 'no': 0, 'unknown': 0},
          'water': {'yes': 0, 'no': 0, 'unknown': 2},
          'usable': {'yes': 2, 'no': 0, 'unknown': 0},
          'lock': {'yes': 0, 'no': 0, 'unknown': 2},
        },
      },
    });
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Center(
            child: EvidenceStatusLabel(_toilet(evidence: ev), clock: () => now),
          ),
        ),
      ),
    );
    expect(find.text('Recent checks: open'), findsOneWidget);
  });

  testWidgets('travel-mode sheet labels its times as straight-line estimates, '
      'not a Maps route ETA', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) => Center(
              child: ElevatedButton(
                onPressed: () =>
                    showTravelModeSheet(context, distanceMeters: 1200),
                child: const Text('open'),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    expect(find.textContaining('not a Maps'), findsOneWidget);
    // The word "route" never stands alone as a claim about these times.
    expect(find.text('Route ETA'), findsNothing);
  });
}
