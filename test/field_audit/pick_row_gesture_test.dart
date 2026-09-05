// Regression test for the Field Audit picker "tap to queue" bug .
//
// The old row was `SmCard(onTap: queue) > InkWell(onLongPress: auditNow)`. The
// inner InkWell won the gesture arena for taps, so a plain tap was silently
// swallowed and only long-press worked. FieldAuditPickRow now puts BOTH
// gestures on ONE InkWell.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shauchmap_app/field_audit/field_audit_pick_toilet_screen.dart';

void main() {
  Widget host({
    required VoidCallback onQueue,
    required VoidCallback onAuditNow,
    bool enabled = true,
  }) {
    return MaterialApp(
      home: Scaffold(
        body: Center(
          child: FieldAuditPickRow(
            title: 'Public Toilet',
            subtitle: '120 m · Somewhere',
            enabled: enabled,
            onQueue: onQueue,
            onAuditNow: onAuditNow,
          ),
        ),
      ),
    );
  }

  testWidgets('a single tap queues exactly once and never audits', (t) async {
    var queued = 0;
    var audited = 0;
    await t.pumpWidget(
      host(onQueue: () => queued++, onAuditNow: () => audited++),
    );

    await t.tap(find.text('Public Toilet'));
    await t.pump();

    expect(queued, 1, reason: 'plain tap must queue');
    expect(audited, 0, reason: 'plain tap must not audit');
  });

  testWidgets('a long-press audits exactly once and never queues', (t) async {
    var queued = 0;
    var audited = 0;
    await t.pumpWidget(
      host(onQueue: () => queued++, onAuditNow: () => audited++),
    );

    await t.longPress(find.text('Public Toilet'));
    await t.pump();

    expect(audited, 1, reason: 'long-press must audit');
    expect(queued, 0, reason: 'long-press must not also queue');
  });

  testWidgets('one gesture never fires both callbacks', (t) async {
    var queued = 0;
    var audited = 0;
    await t.pumpWidget(
      host(onQueue: () => queued++, onAuditNow: () => audited++),
    );

    await t.tap(find.text('Public Toilet'));
    await t.pump();
    await t.longPress(find.text('Public Toilet'));
    await t.pump();

    expect(queued, 1);
    expect(audited, 1);
    expect(
      queued + audited,
      2,
      reason: 'two gestures => exactly two callbacks',
    );
  });

  testWidgets('while disabled (add in flight) neither gesture fires', (
    t,
  ) async {
    var queued = 0;
    var audited = 0;
    await t.pumpWidget(
      host(
        onQueue: () => queued++,
        onAuditNow: () => audited++,
        enabled: false,
      ),
    );

    await t.tap(find.text('Public Toilet'));
    await t.pump();
    await t.longPress(find.text('Public Toilet'));
    await t.pump();

    expect(queued, 0);
    expect(audited, 0);
  });

  testWidgets('exactly one InkWell owns the row gestures', (t) async {
    await t.pumpWidget(host(onQueue: () {}, onAuditNow: () {}));

    final inkwells = find.descendant(
      of: find.byType(FieldAuditPickRow),
      matching: find.byType(InkWell),
    );
    // SmCard contributes one inert InkWell (all callbacks null); ours is the
    // only one with a tap handler.
    final withTap = t
        .widgetList<InkWell>(inkwells)
        .where((w) => w.onTap != null || w.onLongPress != null)
        .toList();
    expect(withTap.length, 1);
    expect(withTap.single.onTap, isNotNull);
    expect(withTap.single.onLongPress, isNotNull);
  });
}
