// ShauchMap GO V2 — PRESENTATION layer.
//
// The frozen engine (`go_decision.dart`) emits NO strings. This file is the ONE
// place that turns a `GoDecision` into user-facing copy + structured view
// semantics for every GO surface (live GO sheet, home-widget labels, deep-link
// preview).
//
// RULES
//   * NO ranking / policy logic here. It only maps an already-decided result.
//   * Never expose internal enum names to users.
//   * Never say: guaranteed / safe / verified toilet / definitely open / 100% /
//     reliability percentage.
//   * Caution order is DETERMINISTIC — driven by `_cautionRank`, never by Set
//     iteration order.
//   * A moderation-flagged record is never presented as an automatically
//     navigable selection (the engine already excludes it; this layer refuses
//     to render a Navigate CTA for the flagged-only result).

import '../truth/toilet_truth.dart' show IdentityStatus;
import 'go_decision.dart';

/// Visual tone for the selected / alternative marker + accent. Green is allowed
/// ONLY when corroborated positive condition evidence backs the selection.
enum GoTone { neutral, positive, warning }

/// One rendered caution line: stable [rank] for ordering + display [text].
class GoCautionLine {
  final int rank;
  final String text;
  const GoCautionLine(this.rank, this.text);
}

/// Fully-resolved, display-ready view of a `GoDecision` (or of one
/// `GoAlternative`). Pure data — no widgets.
class GoPresentation {
  /// Short headline for the sheet / widget ("Nearest mapped option", …).
  final String headline;

  /// One or two plain sentences explaining WHY the engine chose this.
  final String explanation;

  /// False → the UI must not offer a Navigate action at all (null results).
  final bool navigationAllowed;

  /// True → the UI MUST get an explicit confirmation tap before MapLauncher.
  final bool requiresConfirmation;

  /// Primary call-to-action label, or null when [navigationAllowed] is false.
  final String? primaryCta;

  /// Secondary action label (always present when there is a primary CTA).
  final String? secondaryCta;

  /// Cautions in DETERMINISTIC order, already de-duplicated.
  final List<String> cautions;

  final GoTone tone;

  const GoPresentation({
    required this.headline,
    required this.explanation,
    required this.navigationAllowed,
    required this.requiresConfirmation,
    required this.primaryCta,
    required this.secondaryCta,
    required this.cautions,
    required this.tone,
  });
}

// --------------------------------------------------------------- caution copy
//
// Lower rank sorts first. The ordering is: identity uncertainty, then the
// strongest operational-negative, then softer negatives, then amenity notes.
int _cautionRank(GoCaution c) => switch (c) {
      GoCaution.moderationFlagged => 0,
      GoCaution.unknownIdentity => 1,
      GoCaution.candidateIdentity => 2,
      GoCaution.unconfirmedCommunityIdentity => 3,
      GoCaution.corroboratedUnavailable => 4,
      GoCaution.conflictedUnavailable => 5,
      GoCaution.singleReportUnavailable => 6,
      GoCaution.waterReportedOut => 7,
      GoCaution.lockReportedOut => 8,
    };

String _cautionText(GoCaution c) => switch (c) {
      GoCaution.moderationFlagged =>
        'This location is under moderation review and is not offered automatically.',
      GoCaution.unknownIdentity => 'Location identity is not confirmed.',
      GoCaution.candidateIdentity =>
        'Possible toilet location; identity not confirmed.',
      GoCaution.unconfirmedCommunityIdentity =>
        'Community-added location; identity not yet corroborated.',
      GoCaution.corroboratedUnavailable =>
        'Multiple recent condition checks agree this is unavailable.',
      GoCaution.conflictedUnavailable =>
        'Recent condition checks conflict, with more indicating unavailable.',
      GoCaution.singleReportUnavailable =>
        'A recent condition check indicates this may be unavailable.',
      GoCaution.waterReportedOut =>
        'Recent condition checks indicate that water is unavailable.',
      GoCaution.lockReportedOut =>
        'Recent condition checks indicate that the lock is not working.',
    };

/// Deterministically ordered, de-duplicated caution lines for a set of
/// `GoCaution`s. Exposed for tests + for rendering an alternative's cautions.
List<String> orderedCautionText(Iterable<GoCaution> cautions) {
  final unique = cautions.toSet().toList()
    ..sort((a, b) => _cautionRank(a).compareTo(_cautionRank(b)));
  return unique.map(_cautionText).toList(growable: false);
}

// --------------------------------------------------------------- reason copy

class _ReasonCopy {
  final String headline;
  final String explanation;
  const _ReasonCopy(this.headline, this.explanation);
}

_ReasonCopy _reasonCopy(GoReason r, {IdentityStatus? selectedIdentity}) {
  switch (r) {
    case GoReason.nearestWithNoStrongEvidence:
      return const _ReasonCopy(
        'Nearest mapped option',
        'No recent evidence is strong enough to justify sending you farther. '
            'Showing the nearest mapped option.',
      );
    case GoReason.recentCorroboratedUsableWithinDetour:
      return const _ReasonCopy(
        'Recent checks indicate usable',
        'Multiple recent condition checks agree this option is usable, so GO '
            'prefers it within a small nearby detour.',
      );
    case GoReason.avoidedRecentCorroboratedUnavailable:
      return const _ReasonCopy(
        'Avoided an option recent checks flag unavailable',
        'The nearest mapped option has multiple recent condition checks '
            'indicating unavailable, so GO suggests another nearby option.',
      );
    case GoReason.singleNegativeWarning:
      return const _ReasonCopy(
        'Nearest option, with a warning',
        'A recent condition check indicates the nearest option may be '
            'unavailable. GO warns you, but does not reroute everyone based on '
            'one check.',
      );
    case GoReason.conflictedNegativeWarning:
      return const _ReasonCopy(
        'Nearest option, with a warning',
        'Recent condition checks conflict. GO keeps the nearer option and shows '
            'the warning.',
      );
    case GoReason.bestMappedOptionCorroboratedUnavailable:
      return const _ReasonCopy(
        'No good nearby option',
        'Multiple recent condition checks agree this option is unavailable, and '
            'GO found no reasonable nearby alternative.',
      );
    case GoReason.communitySubmissionFallback:
      return const _ReasonCopy(
        'Community-added location',
        'No normal mapped option is available in the current GO pool. This '
            'community-added location needs confirmation.',
      );
    case GoReason.candidateFallback:
      if (selectedIdentity == IdentityStatus.unknown) {
        return const _ReasonCopy(
          'Unconfirmed location',
          'No normal mapped option is available in the current GO pool. The '
              'source and identity of this location are not confirmed.',
        );
      }
      return const _ReasonCopy(
        'Unconfirmed location',
        'No normal mapped option is available in the current GO pool. This is a '
            'possible toilet location; its identity is not confirmed.',
      );
    case GoReason.noToilets:
      return const _ReasonCopy(
        'No GO suggestion',
        "ShauchMap can't produce a nearby GO suggestion right now.",
      );
    case GoReason.onlyFlaggedOrUnconfirmedOptions:
      return const _ReasonCopy(
        'No confident GO suggestion',
        'No confident GO suggestion right now.',
      );
  }
}

// --------------------------------------------------------------- main mapper

GoTone _toneFor(GoDecision d) {
  if (d.selected == null) return GoTone.warning;
  // Green ONLY when corroborated positive evidence backs the pick and no
  // unavailable / identity caution is attached.
  final hasNegative = d.cautions.any(
    (c) =>
        c == GoCaution.corroboratedUnavailable ||
        c == GoCaution.conflictedUnavailable ||
        c == GoCaution.singleReportUnavailable ||
        c == GoCaution.unconfirmedCommunityIdentity ||
        c == GoCaution.candidateIdentity ||
        c == GoCaution.unknownIdentity ||
        c == GoCaution.moderationFlagged,
  );
  if (d.reason == GoReason.recentCorroboratedUsableWithinDetour &&
      !hasNegative) {
    return GoTone.positive;
  }
  if (d.requiresConfirmation || hasNegative) return GoTone.warning;
  return GoTone.neutral;
}

/// Map a whole `GoDecision` to display semantics.
///
/// [selectedIdentity] is the Truth-V2 identity of `decision.selected` (used only
/// to word the candidate-vs-unknown fallback copy). Provenance is NEVER
/// relabelled — a corroborated community submission is still "community-added".
GoPresentation presentGoDecision(
  GoDecision decision, {
  IdentityStatus? selectedIdentity,
}) {
  final copy = _reasonCopy(decision.reason, selectedIdentity: selectedIdentity);
  final cautions = orderedCautionText(decision.cautions);

  // Null results: no automatic recommendation, no Navigate action. We do NOT
  // fall back to nearest-by-distance (that would bypass GO's safety policy).
  if (decision.selected == null) {
    final browseOnly =
        decision.reason == GoReason.onlyFlaggedOrUnconfirmedOptions
            ? 'Browse map'
            : 'Retry';
    return GoPresentation(
      headline: copy.headline,
      explanation: decision.reason == GoReason.noToilets
          ? "ShauchMap can't produce a nearby GO suggestion from the currently "
              'available pool.'
          : copy.explanation,
      navigationAllowed: false,
      requiresConfirmation: false,
      primaryCta: null,
      secondaryCta: browseOnly,
      cautions: cautions,
      tone: GoTone.warning,
    );
  }

  return GoPresentation(
    headline: copy.headline,
    explanation: copy.explanation,
    navigationAllowed: true,
    requiresConfirmation: decision.requiresConfirmation,
    primaryCta:
        decision.requiresConfirmation ? 'Navigate anyway' : 'Navigate in Maps',
    secondaryCta: decision.requiresConfirmation
        ? 'Choose another option'
        : 'Choose another option',
    cautions: cautions,
    tone: _toneFor(decision),
  );
}

// ------------------------------------------------- compact home-widget status
//
// The Android home widget shows only name + distance + id. Without this a
// fallback / warning / candidate result would look exactly like a clean normal
// recommendation. This compresses the GO semantics into one honest phrase per
// row — no reliability %, no "verified", no certainty, no
// hidden candidate/community fallback.
enum GoWidgetStatus {
  unconfirmed,
  recentUsable,
  recentWarning,
  unconfirmedLocation,
  reportedUnavailable,
}

String goWidgetStatusText(GoWidgetStatus s) => switch (s) {
      GoWidgetStatus.unconfirmed => 'Status unconfirmed',
      GoWidgetStatus.recentUsable => 'Recent checks indicate usable',
      GoWidgetStatus.recentWarning => 'Recent warning',
      GoWidgetStatus.unconfirmedLocation => 'Unconfirmed location',
      GoWidgetStatus.reportedUnavailable =>
        'Recent checks indicate unavailable — check first',
    };

/// Compact status for one widget row, from the row's real authority + condition
/// + confirmation contract. Identity uncertainty and a corroborated-unavailable
/// condition always win over a plain "unconfirmed".
GoWidgetStatus goWidgetStatusFor({
  required RecommendationAuthority authority,
  required OperationalCondition condition,
  required bool requiresConfirmation,
  required Set<GoCaution> cautions,
}) {
  if (condition == OperationalCondition.corroboratedUnavailable ||
      cautions.contains(GoCaution.corroboratedUnavailable)) {
    return GoWidgetStatus.reportedUnavailable;
  }
  if (requiresConfirmation ||
      authority == RecommendationAuthority.communityFallback ||
      authority == RecommendationAuthority.candidateFallback ||
      authority == RecommendationAuthority.unknownFallback ||
      cautions.contains(GoCaution.unconfirmedCommunityIdentity) ||
      cautions.contains(GoCaution.candidateIdentity) ||
      cautions.contains(GoCaution.unknownIdentity)) {
    return GoWidgetStatus.unconfirmedLocation;
  }
  if (condition == OperationalCondition.singleReportedUnavailable ||
      condition == OperationalCondition.conflictedUnavailableMajority ||
      cautions.contains(GoCaution.singleReportUnavailable) ||
      cautions.contains(GoCaution.conflictedUnavailable)) {
    return GoWidgetStatus.recentWarning;
  }
  if (condition == OperationalCondition.corroboratedUsable) {
    return GoWidgetStatus.recentUsable;
  }
  return GoWidgetStatus.unconfirmed;
}

/// Map ONE `GoAlternative` to display semantics (a compact row).
GoPresentation presentGoAlternative(
  GoAlternative alt, {
  IdentityStatus? identity,
}) {
  // Derive a headline from the alternative's authority + condition, reusing the
  // caution copy for the body.
  final String headline = switch (alt.authority) {
    RecommendationAuthority.sourceMappedPrimary => 'Mapped option',
    RecommendationAuthority.communityCorroborated =>
      'Community-added, recent checks indicate usable',
    RecommendationAuthority.communityFallback => 'Community-added location',
    RecommendationAuthority.candidateFallback => 'Unconfirmed location',
    RecommendationAuthority.unknownFallback => 'Unconfirmed location',
    RecommendationAuthority.flaggedExcluded => 'Under moderation review',
  };
  final cautions = orderedCautionText(alt.cautions);
  final GoTone tone =
      alt.condition == OperationalCondition.corroboratedUsable &&
              alt.cautions.isEmpty
          ? GoTone.positive
          : (alt.requiresConfirmation || alt.cautions.isNotEmpty)
              ? GoTone.warning
              : GoTone.neutral;
  return GoPresentation(
    headline: headline,
    explanation: cautions.isEmpty
        ? 'A nearby alternative from the same recommendation tier.'
        : cautions.first,
    navigationAllowed: alt.authority != RecommendationAuthority.flaggedExcluded,
    requiresConfirmation: alt.requiresConfirmation,
    primaryCta: alt.requiresConfirmation ? 'Navigate anyway' : 'Navigate',
    secondaryCta: 'Back',
    cautions: cautions,
    tone: tone,
  );
}
