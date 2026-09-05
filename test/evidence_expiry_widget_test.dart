// passive expiry actually re-evaluates the UI, and map-pin colour
// is NOT driven by one recent condition "no".

// evidence fixtures use the core Instant (what toiletFromFirestore
// normalizes Firestore Timestamps to before parsing).
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:shauchmap_app/screens/map_screen.dart' show toiletMarkerIcon;
import 'package:shauchmap_app/services/firestore_service.dart';
import 'package:shauchmap_app/widgets/evidence_status_label.dart';

Instant _ts(DateTime d) => Instant.fromDateTime(d);

Toilet _toilet({
  bool flagged = false,
  ToiletEvidence evidence = ToiletEvidence.unavailable,
}) => Toilet(
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
  flaggedRaw: flagged,
  flaggedUntil: flagged ? DateTime(3000) : null,
  addedBy: 'osm_x',
  evidence: evidence,
);

ToiletEvidence _cond({
  required String open,
  required DateTime now,
  required Duration validFor,
}) {
  final o = open == 'yes'
      ? {'yes': 1, 'no': 0, 'unknown': 0}
      : open == 'no'
      ? {'yes': 0, 'no': 1, 'unknown': 0}
      : {'yes': 0, 'no': 0, 'unknown': 1};
  const u = {'yes': 0, 'no': 0, 'unknown': 1};
  return ToiletEvidence.fromFirestore({
    'version': 1,
    'condition': {
      'open': open,
      'water': 'unknown',
      'usable': 'unknown',
      'lock': 'unknown',
      'contributor_count': 1,
      'latest_at': _ts(now.subtract(const Duration(minutes: 5))),
      'valid_until': _ts(now.add(validFor)),
      'computed_at': _ts(now),
      'last_event_at': _ts(now),
      'support': {'open': o, 'water': u, 'usable': u, 'lock': u},
    },
  });
}

void main() {
  testWidgets(
    'EvidenceStatusLabel shows the verdict, then SELF-EXPIRES to unconfirmed',
    (tester) async {
      // Injected clock so the fake-async pump and the derivation agree on time.
      DateTime fakeNow = DateTime(2026, 9, 2, 12, 0, 0);
      final t = _toilet(
        evidence: _cond(
          open: 'yes',
          now: fakeNow,
          validFor: const Duration(minutes: 30),
        ),
      );

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Center(child: EvidenceStatusLabel(t, clock: () => fakeNow)),
          ),
        ),
      );
      expect(find.text('Recent checks: open'), findsOneWidget);
      expect(find.text('Status unconfirmed'), findsNothing);

      // Wall-clock passes the 30-minute window. Advance BOTH the injected clock
      // and the fake-async clock so the ONE-SHOT expiry Timer fires.
      fakeNow = fakeNow.add(const Duration(minutes: 31));
      await tester.pump(const Duration(minutes: 31));

      expect(find.text('Recent checks: open'), findsNothing);
      expect(find.text('Status unconfirmed'), findsOneWidget);
    },
  );

  testWidgets('EvidenceStatusLabel with no evidence just shows unconfirmed', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(body: Center(child: EvidenceStatusLabel(_toilet()))),
      ),
    );
    expect(find.text('Status unconfirmed'), findsOneWidget);
  });

  test('map pin: one recent condition "no" does NOT colour the pin ', () {
    final now = DateTime(2026, 9, 2, 12, 0, 0);
    final red = BitmapDescriptor.defaultMarkerWithHue(
      BitmapDescriptor.hueRed,
    ).toJson();
    final azure = BitmapDescriptor.defaultMarkerWithHue(
      BitmapDescriptor.hueAzure,
    ).toJson();
    expect(red, isNot(azure)); // sanity

    final closedByOne = _toilet(
      evidence: _cond(
        open: 'no',
        now: now,
        validFor: const Duration(minutes: 30),
      ),
    );
    expect(toiletMarkerIcon(closedByOne, false).toJson(), azure);

    // Only an explicit, still-valid moderation flag turns it red.
    expect(toiletMarkerIcon(_toilet(flagged: true), false).toJson(), red);
    expect(toiletMarkerIcon(_toilet(), false).toJson(), azure);
  });
}
