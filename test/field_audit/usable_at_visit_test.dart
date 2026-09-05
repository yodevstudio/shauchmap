import 'package:flutter_test/flutter_test.dart';
import 'package:shauchmap_app/field_audit/field_audit_model.dart';

FieldAudit _mk({
  RecordContext ctx = RecordContext.mappedRecord,
  MappingOutcome outcome = MappingOutcome.unknown,
  YesNoUnknown open = YesNoUnknown.unknown,
  YesNoUnknown access = YesNoUnknown.unknown,
  YesNoNotChecked water = YesNoNotChecked.notChecked,
  YesNoNotChecked cubicle = YesNoNotChecked.notChecked,
}) {
  final now = DateTime(2026, 9, 1);
  return FieldAudit(
      auditId: 'x',
      recordContext: ctx,
      queuedAt: now,
      lastSavedAt: now,
      toiletId: ctx == RecordContext.mappedRecord ? 'node_1' : null,
      mappingOutcome: outcome,
    )
    ..openAtVisit = open
    ..publiclyAccessibleAtVisit = access
    ..water = water
    ..usableCubicle = cubicle;
}

void main() {
  group('facility_usable_at_visit', () {
    test('mapped + confirmed + all four required yes => YES', () {
      final a = _mk(
        outcome: MappingOutcome.confirmedAtLocation,
        open: YesNoUnknown.yes,
        access: YesNoUnknown.yes,
        water: YesNoNotChecked.yes,
        cubicle: YesNoNotChecked.yes,
      );
      expect(a.computeFacilityUsable(), FourStateUsable.yes);
    });

    test('moved but physically usable => facility YES', () {
      final a = _mk(
        outcome: MappingOutcome.foundNearbyButMoved,
        open: YesNoUnknown.yes,
        access: YesNoUnknown.yes,
        water: YesNoNotChecked.yes,
        cubicle: YesNoNotChecked.yes,
      );
      expect(a.computeFacilityUsable(), FourStateUsable.yes);
    });

    test('unmapped discovery, usable => facility YES', () {
      final a = _mk(
        ctx: RecordContext.unmappedDiscovery,
        open: YesNoUnknown.yes,
        access: YesNoUnknown.yes,
        water: YesNoNotChecked.yes,
        cubicle: YesNoNotChecked.yes,
      );
      expect(a.computeFacilityUsable(), FourStateUsable.yes);
    });

    test('a required condition explicitly no => facility NO', () {
      expect(
        _mk(
          outcome: MappingOutcome.confirmedAtLocation,
          water: YesNoNotChecked.no,
        ).computeFacilityUsable(),
        FourStateUsable.no,
      );
      expect(
        _mk(
          outcome: MappingOutcome.confirmedAtLocation,
          access: YesNoUnknown.no,
        ).computeFacilityUsable(),
        FourStateUsable.no,
      );
    });

    test('facility observed but a required obs unknown => INDETERMINATE', () {
      final a = _mk(
        outcome: MappingOutcome.confirmedAtLocation,
        open: YesNoUnknown.yes,
        access: YesNoUnknown.yes,
        water: YesNoNotChecked.notChecked, // <-- not checked
        cubicle: YesNoNotChecked.yes,
      );
      expect(a.computeFacilityUsable(), FourStateUsable.indeterminate);
    });

    test('could_not_locate => NOT_OBSERVED', () {
      expect(
        _mk(outcome: MappingOutcome.couldNotLocate).computeFacilityUsable(),
        FourStateUsable.notObserved,
      );
    });

    test('not_a_toilet => NOT_OBSERVED', () {
      expect(
        _mk(outcome: MappingOutcome.notAToilet).computeFacilityUsable(),
        FourStateUsable.notObserved,
      );
    });

    test('unknown outcome with NO functional evidence => NOT_OBSERVED', () {
      expect(
        _mk(outcome: MappingOutcome.unknown).computeFacilityUsable(),
        FourStateUsable.notObserved,
      );
    });

    test('unknown outcome WITH functional evidence => graded', () {
      final a = _mk(outcome: MappingOutcome.unknown, water: YesNoNotChecked.no);
      expect(a.computeFacilityUsable(), FourStateUsable.no);
    });

    test('soap / cleanliness / wheelchair never affect facility usability', () {
      final a =
          _mk(
              outcome: MappingOutcome.confirmedAtLocation,
              open: YesNoUnknown.yes,
              access: YesNoUnknown.yes,
              water: YesNoNotChecked.yes,
              cubicle: YesNoNotChecked.yes,
            )
            ..soap = YesNoNotChecked.no
            ..cleanliness = Cleanliness.poor
            ..wheelchairEntry = YesNoNotChecked.no
            ..accessibleToilet = YesNoNotChecked.no;
      expect(a.computeFacilityUsable(), FourStateUsable.yes);
    });
  });

  group('mapped_option_usable_at_visit', () {
    test('unmapped discovery => NOT_APPLICABLE', () {
      expect(
        _mk(ctx: RecordContext.unmappedDiscovery).computeMappedOptionUsable(),
        MappedOptionUsable.notApplicable,
      );
    });

    test('confirmed + facility yes => mapped option YES', () {
      final a = _mk(
        outcome: MappingOutcome.confirmedAtLocation,
        open: YesNoUnknown.yes,
        access: YesNoUnknown.yes,
        water: YesNoNotChecked.yes,
        cubicle: YesNoNotChecked.yes,
      );
      expect(a.computeMappedOptionUsable(), MappedOptionUsable.yes);
    });

    test('could_not_locate => facility NOT_OBSERVED + mapped option NO', () {
      final a = _mk(outcome: MappingOutcome.couldNotLocate);
      expect(a.computeFacilityUsable(), FourStateUsable.notObserved);
      expect(a.computeMappedOptionUsable(), MappedOptionUsable.no);
    });

    test('not_a_toilet => mapped option NO', () {
      expect(
        _mk(outcome: MappingOutcome.notAToilet).computeMappedOptionUsable(),
        MappedOptionUsable.no,
      );
    });

    test('confirmed but facility no => mapped option NO', () {
      final a = _mk(
        outcome: MappingOutcome.confirmedAtLocation,
        open: YesNoUnknown.no,
      );
      expect(a.computeMappedOptionUsable(), MappedOptionUsable.no);
    });

    test(
      'confirmed but facility indeterminate => mapped option INDETERMINATE',
      () {
        final a = _mk(
          outcome: MappingOutcome.confirmedAtLocation,
          open: YesNoUnknown.yes,
          access: YesNoUnknown.yes,
          water: YesNoNotChecked.yes, // cubicle still not checked
        );
        expect(a.computeFacilityUsable(), FourStateUsable.indeterminate);
        expect(a.computeMappedOptionUsable(), MappedOptionUsable.indeterminate);
      },
    );

    test(
      'moved + physically usable => mapped option INDETERMINATE (not YES)',
      () {
        final a = _mk(
          outcome: MappingOutcome.foundNearbyButMoved,
          open: YesNoUnknown.yes,
          access: YesNoUnknown.yes,
          water: YesNoNotChecked.yes,
          cubicle: YesNoNotChecked.yes,
        );
        expect(a.computeFacilityUsable(), FourStateUsable.yes);
        expect(a.computeMappedOptionUsable(), MappedOptionUsable.indeterminate);
      },
    );

    test('duplicate + physically not usable => mapped option NO', () {
      final a = _mk(
        outcome: MappingOutcome.duplicate,
        water: YesNoNotChecked.no,
      );
      expect(a.computeMappedOptionUsable(), MappedOptionUsable.no);
    });

    test('unknown outcome => mapped option INDETERMINATE', () {
      expect(
        _mk(outcome: MappingOutcome.unknown).computeMappedOptionUsable(),
        MappedOptionUsable.indeterminate,
      );
    });
  });

  test('unmapped discovery forces mapping_outcome to not_applicable', () {
    final a = _mk(ctx: RecordContext.unmappedDiscovery);
    expect(a.mappingOutcome, MappingOutcome.notApplicable);
    a.mappingOutcome = MappingOutcome.confirmedAtLocation; // ignored
    expect(a.mappingOutcome, MappingOutcome.notApplicable);
  });

  test('fee amount is cleared when fee is not paid', () {
    final now = DateTime(2026, 9, 1);
    final a = FieldAudit(
      auditId: 'f',
      recordContext: RecordContext.mappedRecord,
      queuedAt: now,
      lastSavedAt: now,
      fee: FeeKind.paid,
      feeAmountInr: 5,
    );
    expect(a.feeAmountInr, 5);
    a.fee = FeeKind.free;
    a.normaliseFee();
    expect(a.feeAmountInr, isNull);
    // and it never round-trips an impossible combo
    a.fee = FeeKind.free;
    a.feeAmountInr = 5; // pretend a stale UI left it
    expect(a.toJson()['fee_amount_inr'], isNull);
  });
}
