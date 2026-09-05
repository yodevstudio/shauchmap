import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shauchmap_app/widgets/osm_attribution_badge.dart';

void main() {
  testWidgets('OsmAttributionBadge shows the required OSM credit text', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(home: Scaffold(body: OsmAttributionBadge())),
    );

    expect(
      find.text('Toilet data: © OpenStreetMap contributors'),
      findsOneWidget,
    );
  });

  testWidgets(
    'OsmAttributionBadge is tappable (opens the OSM copyright page)',
    (tester) async {
      await tester.pumpWidget(
        const MaterialApp(home: Scaffold(body: OsmAttributionBadge())),
      );

      // A real launchUrl call would hit a platform channel unavailable in the
      // widget-test environment, so this only proves the tap target exists and
      // is wired to a handler — not that the browser actually opens. Full
      // launch-URL behavior is exercised manually on-device.
      expect(find.byType(InkWell), findsOneWidget);
      final inkWell = tester.widget<InkWell>(find.byType(InkWell));
      expect(inkWell.onTap, isNotNull);
    },
  );
}
