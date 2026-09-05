// GO V2 presentation mapper. Pure. Locks the reason/caution copy
// contract, deterministic caution ordering, the null / confirmation / tone
// semantics, and the honesty rules (no "guaranteed / verified toilet /
// reliability % / 100% / definitely open / safe" copy).

import 'package:test/test.dart';
import 'package:shauchmap_core/shauchmap_core.dart';

final _forbidden = RegExp(
  r'guaranteed|verified toilet|reliability\s*%|100\s*%|definitely open|\bsafe\b',
  caseSensitive: false,
);

Toilet _t(String id, {IdentityStatus identity = IdentityStatus.sourceMapped}) =>
    Toilet(
      id: id,
      name: 'T $id',
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
      addedBy: 'x',
      truth: ToiletTruth(
        schemaVersion: 1,
        source: ToiletSource.osm,
        recordedAt: null,
        context: FacilityContext.unknown,
        gender: GenderAccess.unknown,
        identityStatus: identity,
        fee: FeeState.unknown,
        amenities: ToiletAmenities.allUnknown,
        isNativeV2: false,
      ),
      evidence: ToiletEvidence.unavailable,
    );

GoDecision _decision(
  GoReason reason, {
  Toilet? selected,
  bool requiresConfirmation = false,
  Set<GoCaution> cautions = const {},
  List<GoAlternative> alternatives = const [],
}) =>
    GoDecision(
      selected: selected,
      selectedDistanceMeters: selected == null ? null : 120,
      reason: reason,
      requiresConfirmation: requiresConfirmation,
      cautions: cautions,
      alternatives: alternatives,
      baselineNearest: selected,
      baselineNearestDistanceMeters: selected == null ? null : 120,
    );

void main() {
  group('COPY: every GoReason maps to non-empty, non-forbidden copy', () {
    for (final r in GoReason.values) {
      test(r.name, () {
        final withSel = r != GoReason.noToilets &&
            r != GoReason.onlyFlaggedOrUnconfirmedOptions;
        final p = presentGoDecision(
          _decision(r, selected: withSel ? _t('a') : null),
        );
        expect(p.headline.trim(), isNotEmpty);
        expect(p.explanation.trim(), isNotEmpty);
        expect(_forbidden.hasMatch(p.headline), isFalse);
        expect(_forbidden.hasMatch(p.explanation), isFalse);
        expect(p.headline, isNot(contains(r.name))); // no raw enum names
      });
    }
  });

  group('COPY: every GoCaution maps', () {
    test('orderedCautionText covers all caution enum members', () {
      final lines = orderedCautionText(GoCaution.values);
      expect(lines.length, GoCaution.values.length);
      for (final l in lines) {
        expect(l.trim(), isNotEmpty);
        expect(_forbidden.hasMatch(l), isFalse);
      }
    });
  });

  test('caution ordering is DETERMINISTIC, not Set iteration order', () {
    const a = {
      GoCaution.lockReportedOut,
      GoCaution.candidateIdentity,
      GoCaution.corroboratedUnavailable,
      GoCaution.waterReportedOut,
    };
    const b = {
      GoCaution.waterReportedOut,
      GoCaution.corroboratedUnavailable,
      GoCaution.candidateIdentity,
      GoCaution.lockReportedOut,
    };
    expect(orderedCautionText(a), orderedCautionText(b));
    // identity before operational-negative before amenity note
    final ordered = orderedCautionText(a);
    expect(
      ordered.indexOf('Possible toilet location; identity not confirmed.'),
      lessThan(
        ordered.indexOf('Multiple recent condition checks agree this is unavailable.'),
      ),
    );
    expect(
      ordered.indexOf('Multiple recent condition checks agree this is unavailable.'),
      lessThan(
        ordered.indexOf('Recent condition checks indicate that water is unavailable.'),
      ),
    );
  });

  group('NULL results: no navigation', () {
    test('noToilets => navigationAllowed false, no primary CTA, Retry', () {
      final p = presentGoDecision(_decision(GoReason.noToilets));
      expect(p.navigationAllowed, isFalse);
      expect(p.primaryCta, isNull);
      expect(p.requiresConfirmation, isFalse);
      expect(p.secondaryCta, 'Retry');
    });
    test('onlyFlaggedOrUnconfirmedOptions => no navigation, Browse map', () {
      final p = presentGoDecision(
        _decision(
          GoReason.onlyFlaggedOrUnconfirmedOptions,
          cautions: {GoCaution.moderationFlagged},
        ),
      );
      expect(p.navigationAllowed, isFalse);
      expect(p.primaryCta, isNull);
      expect(p.secondaryCta, 'Browse map');
    });
  });

  group('CONFIRMATION contract', () {
    test('requiresConfirmation => primary CTA is "Navigate anyway"', () {
      final p = presentGoDecision(
        _decision(
          GoReason.communitySubmissionFallback,
          selected: _t('a', identity: IdentityStatus.communitySubmitted),
          requiresConfirmation: true,
          cautions: {GoCaution.unconfirmedCommunityIdentity},
        ),
      );
      expect(p.navigationAllowed, isTrue);
      expect(p.requiresConfirmation, isTrue);
      expect(p.primaryCta, 'Navigate anyway');
      expect(p.secondaryCta, 'Choose another option');
    });
    test('normal primary => "Navigate in Maps", no forced confirmation', () {
      final p = presentGoDecision(
        _decision(GoReason.nearestWithNoStrongEvidence, selected: _t('a')),
      );
      expect(p.requiresConfirmation, isFalse);
      expect(p.primaryCta, 'Navigate in Maps');
    });
  });

  group('TONE', () {
    test('corroborated-usable + no negative => positive (green allowed)', () {
      final p = presentGoDecision(
        _decision(
          GoReason.recentCorroboratedUsableWithinDetour,
          selected: _t('a'),
        ),
      );
      expect(p.tone, GoTone.positive);
    });
    test(
        'corroborated-usable + water reported out => still positive on '
        'USABILITY, but the water caution line is shown', () {
      final p = presentGoDecision(
        _decision(
          GoReason.recentCorroboratedUsableWithinDetour,
          selected: _t('a'),
          cautions: {GoCaution.waterReportedOut},
        ),
      );
      // Green reflects corroborated USABILITY; a missing amenity does not
      // negate that, but it must still surface as a caution line.
      expect(p.tone, GoTone.positive);
      expect(
        p.cautions,
        contains('Recent condition checks indicate that water is unavailable.'),
      );
    });
    test('single-negative warning => warning tone', () {
      final p = presentGoDecision(
        _decision(
          GoReason.singleNegativeWarning,
          selected: _t('a'),
          cautions: {GoCaution.singleReportUnavailable},
        ),
      );
      expect(p.tone, GoTone.warning);
    });
    test('plain nearest => neutral tone (NOT green)', () {
      final p = presentGoDecision(
        _decision(GoReason.nearestWithNoStrongEvidence, selected: _t('a')),
      );
      expect(p.tone, GoTone.neutral);
    });
  });

  group('ALTERNATIVE presentation preserves state', () {
    test('corroborated-unavailable alt => requiresConfirmation + caution', () {
      final alt = GoAlternative(
        toilet: _t('x'),
        distanceMeters: 210,
        authority: RecommendationAuthority.sourceMappedPrimary,
        condition: OperationalCondition.corroboratedUnavailable,
        requiresConfirmation: true,
        cautions: const {GoCaution.corroboratedUnavailable},
      );
      final p = presentGoAlternative(alt);
      expect(p.requiresConfirmation, isTrue);
      expect(
        p.cautions,
        contains('Multiple recent condition checks agree this is unavailable.'),
      );
      expect(p.tone, GoTone.warning);
    });
    test('community-fallback alt keeps identity caption, needs confirm', () {
      final alt = GoAlternative(
        toilet: _t('x', identity: IdentityStatus.communitySubmitted),
        distanceMeters: 150,
        authority: RecommendationAuthority.communityFallback,
        condition: OperationalCondition.unknown,
        requiresConfirmation: true,
        cautions: const {GoCaution.unconfirmedCommunityIdentity},
      );
      final p = presentGoAlternative(alt);
      expect(p.headline.toLowerCase(), contains('community'));
      expect(p.requiresConfirmation, isTrue);
    });
    test('clean mapped alt => neutral, no confirmation', () {
      final alt = GoAlternative(
        toilet: _t('x'),
        distanceMeters: 150,
        authority: RecommendationAuthority.sourceMappedPrimary,
        condition: OperationalCondition.unknown,
        requiresConfirmation: false,
        cautions: const {},
      );
      final p = presentGoAlternative(alt);
      expect(p.requiresConfirmation, isFalse);
      expect(p.tone, GoTone.neutral);
    });
  });

  group('an alternative exposes ALL its material cautions (row data)', () {
    test(
      'FOUR cautions (identity + operational + water + lock) => all '
      'four lines, in deterministic order, NONE dropped',
      () {
        final alt = GoAlternative(
          toilet: _t('x', identity: IdentityStatus.candidate),
          distanceMeters: 210,
          authority: RecommendationAuthority.candidateFallback,
          condition: OperationalCondition.singleReportedUnavailable,
          requiresConfirmation: true,
          cautions: const {
            GoCaution.waterReportedOut,
            GoCaution.singleReportUnavailable,
            GoCaution.lockReportedOut,
            GoCaution.candidateIdentity,
          },
        );
        final lines = presentGoAlternative(alt).cautions;
        expect(lines.length, 4); // nothing truncated (no take(3))
        expect(lines, [
          'Possible toilet location; identity not confirmed.',
          'A recent condition check indicates this may be unavailable.',
          'Recent condition checks indicate that water is unavailable.',
          'Recent condition checks indicate that the lock is not working.',
        ]);
      },
    );

    test(
        'single-unavailable + water-out + lock-out => 3 caution lines, '
        'deterministic order, no confirmation forced', () {
      final alt = GoAlternative(
        toilet: _t('x'),
        distanceMeters: 210,
        authority: RecommendationAuthority.sourceMappedPrimary,
        condition: OperationalCondition.singleReportedUnavailable,
        requiresConfirmation: false,
        cautions: const {
          GoCaution.singleReportUnavailable,
          GoCaution.waterReportedOut,
          GoCaution.lockReportedOut,
        },
      );
      final p = presentGoAlternative(alt);
      expect(p.requiresConfirmation, isFalse); // soft cautions don't force it
      expect(p.cautions, [
        'A recent condition check indicates this may be unavailable.',
        'Recent condition checks indicate that water is unavailable.',
        'Recent condition checks indicate that the lock is not working.',
      ]);
    });

    test(
      'identity + operational + amenity cautions all present and ordered',
      () {
        final alt = GoAlternative(
          toilet: _t('x', identity: IdentityStatus.candidate),
          distanceMeters: 210,
          authority: RecommendationAuthority.candidateFallback,
          condition: OperationalCondition.conflictedUnavailableMajority,
          requiresConfirmation: true,
          cautions: const {
            GoCaution.waterReportedOut,
            GoCaution.candidateIdentity,
            GoCaution.conflictedUnavailable,
          },
        );
        final p = presentGoAlternative(alt);
        final iId = p.cautions.indexWhere((l) => l.contains('identity'));
        final iOp = p.cautions.indexWhere((l) => l.contains('conflict'));
        final iAm = p.cautions.indexWhere((l) => l.contains('water'));
        expect(iId, isNonNegative);
        expect(iOp, isNonNegative);
        expect(iAm, isNonNegative);
        expect(iId, lessThan(iOp));
        expect(iOp, lessThan(iAm));
      },
    );
  });

  group('compact home-widget status', () {
    test('plain unknown => "Status unconfirmed"', () {
      expect(
        goWidgetStatusText(
          goWidgetStatusFor(
            authority: RecommendationAuthority.sourceMappedPrimary,
            condition: OperationalCondition.unknown,
            requiresConfirmation: false,
            cautions: const {},
          ),
        ),
        'Status unconfirmed',
      );
    });
    test('corroborated usable => "Recent checks indicate usable"', () {
      expect(
        goWidgetStatusText(
          goWidgetStatusFor(
            authority: RecommendationAuthority.sourceMappedPrimary,
            condition: OperationalCondition.corroboratedUsable,
            requiresConfirmation: false,
            cautions: const {},
          ),
        ),
        'Recent checks indicate usable',
      );
    });
    test('single / conflicted negative => "Recent warning"', () {
      for (final c in [
        OperationalCondition.singleReportedUnavailable,
        OperationalCondition.conflictedUnavailableMajority,
      ]) {
        expect(
          goWidgetStatusFor(
            authority: RecommendationAuthority.sourceMappedPrimary,
            condition: c,
            requiresConfirmation: false,
            cautions: const {},
          ),
          GoWidgetStatus.recentWarning,
        );
      }
    });
    test(
        'candidate / unknown / community / requiresConfirmation => '
        '"Unconfirmed location"', () {
      for (final a in [
        RecommendationAuthority.candidateFallback,
        RecommendationAuthority.unknownFallback,
        RecommendationAuthority.communityFallback,
      ]) {
        expect(
          goWidgetStatusFor(
            authority: a,
            condition: OperationalCondition.unknown,
            requiresConfirmation: true,
            cautions: const {},
          ),
          GoWidgetStatus.unconfirmedLocation,
        );
      }
    });
    test(
        'corroborated unavailable => "Recent checks indicate unavailable — check first" '
        '(wins over identity)', () {
      expect(
        goWidgetStatusText(
          goWidgetStatusFor(
            authority: RecommendationAuthority.candidateFallback,
            condition: OperationalCondition.corroboratedUnavailable,
            requiresConfirmation: true,
            cautions: const {GoCaution.corroboratedUnavailable},
          ),
        ),
        'Recent checks indicate unavailable — check first',
      );
    });
    test('no widget status text contains forbidden certainty copy', () {
      for (final s in GoWidgetStatus.values) {
        expect(_forbidden.hasMatch(goWidgetStatusText(s)), isFalse);
        expect(
          goWidgetStatusText(s).toLowerCase(),
          isNot(contains('verified')),
        );
      }
    });
  });

  test('IDENTITY: candidate vs unknown fallback copy differs, no relabel', () {
    final cand = presentGoDecision(
      _decision(
        GoReason.candidateFallback,
        selected: _t('a', identity: IdentityStatus.candidate),
        requiresConfirmation: true,
      ),
      selectedIdentity: IdentityStatus.candidate,
    );
    final unk = presentGoDecision(
      _decision(
        GoReason.candidateFallback,
        selected: _t('a', identity: IdentityStatus.unknown),
        requiresConfirmation: true,
      ),
      selectedIdentity: IdentityStatus.unknown,
    );
    expect(cand.explanation, isNot(unk.explanation));
    for (final p in [cand, unk]) {
      expect(p.headline.toLowerCase(), isNot(contains('official')));
      expect(p.explanation.toLowerCase(), isNot(contains('government')));
      expect(p.explanation.toLowerCase(), isNot(contains('source mapped')));
    }
  });
}
