// Fixed label tables: core enum value -> short honest phrase .
//
// This is NOT decision logic — Truth / Evidence / GO semantics already ran in
// the Dart core. Here we only translate the core's own enum output for display.
// Rules: never strengthen. "Listed" not "available". "Checked" not "now".
// UNKNOWN reads as genuinely unknown. Ratings/votes are never condition facts.
// "Condition check" is the public name for this signal — never "report",
// which is reserved for the separate moderation/reporting channel.

import type {
  ConditionJson,
  GoCaution,
  GoJson,
  IdentityStatus,
  OperationalCondition,
  RecommendationAuthority,
  Tri,
  TruthJson,
} from '../core/types';

export function identityLabel(s: IdentityStatus): string {
  switch (s) {
    case 'sourceMapped':
      return 'Mapped from an open data source';
    case 'communitySubmitted':
      return 'Added by a community contributor';
    case 'candidate':
      return 'Unconfirmed candidate location';
    case 'unknown':
      return 'Source unknown';
  }
}

export function authorityLabel(a: RecommendationAuthority): string {
  switch (a) {
    case 'sourceMappedPrimary':
      return 'Mapped source';
    case 'communityCorroborated':
      return 'Community + recent condition checks';
    case 'communityFallback':
      return 'Community, unconfirmed';
    case 'candidateFallback':
      return 'Candidate, needs confirmation';
    case 'unknownFallback':
      return 'Provenance unknown';
    case 'flaggedExcluded':
      return 'Flagged for moderation';
  }
}

/** Condition summary line. Deliberately cautious; expired -> unknown upstream. */
export function conditionLabel(c: OperationalCondition): string {
  switch (c) {
    case 'corroboratedUsable':
      return 'Recent condition checks agree it was usable';
    case 'singleReportedUsable':
      return 'One recent condition check said usable';
    case 'conflictedUsableMajority':
      return 'Recent condition checks mostly usable, but not agreed';
    case 'unknown':
      return 'No recent condition checks';
    case 'singleReportedUnavailable':
      return 'One recent condition check said not usable';
    case 'conflictedUnavailableMajority':
      return 'Recent condition checks mostly not usable, but not agreed';
    case 'corroboratedUnavailable':
      return 'Recent condition checks agree it was not usable';
  }
}

export function cautionLabel(c: GoCaution): string {
  switch (c) {
    case 'singleReportUnavailable':
      return 'Only one recent condition check says it was not usable';
    case 'conflictedUnavailable':
      return 'Recent condition checks disagree on whether it is usable';
    case 'corroboratedUnavailable':
      return 'Multiple recent condition checks say it was not usable';
    case 'unconfirmedCommunityIdentity':
      return 'Community-added and not yet confirmed';
    case 'candidateIdentity':
      return 'This is a candidate location, not a confirmed toilet';
    case 'unknownIdentity':
      return 'We could not confirm where this record came from';
    case 'moderationFlagged':
      return 'Flagged for moderation review';
    case 'waterReportedOut':
      return 'A recent condition check found water out';
    case 'lockReportedOut':
      return 'A recent condition check found lock / access out';
  }
}

const TRI: Record<Tri, string> = { yes: 'Yes', no: 'No', unknown: 'Unknown' };
export const triLabel = (t: Tri): string => TRI[t];

export function feeLabel(t: TruthJson): string {
  if (t.fee === 'free') return 'Free';
  if (t.fee === 'paid') return 'Paid';
  return 'Fee unknown';
}

/** A plain read of the core's Evidence condition verdicts for the SELECTED
 *  toilet (GoJson doesn't carry its OperationalCondition). Labeling only. */
export function conditionSummaryFromEvidence(c: ConditionJson): string {
  if (!c.available || !c.isCurrentlyValid) return 'No recent condition checks';
  if (c.usable === 'yes') return 'Recently checked usable';
  if (c.usable === 'no') return 'Recently checked not usable';
  if (c.open === 'yes') return 'Recently checked open';
  if (c.open === 'no') return 'Recently checked closed';
  return 'Recent condition checks were inconclusive';
}

/** Only shown when the core says the condition summary is currently valid. */
export function conditionFreshness(c: ConditionJson): string | null {
  if (!c.available || !c.isCurrentlyValid || c.ageMinutes == null) return null;
  const m = c.ageMinutes;
  if (m <= 1) return 'Updated just now';
  if (m < 60) return `Updated ${m} min ago`;
  return 'Updated over an hour ago';
}

/** Ratings line — opinion, never condition. null when absent (not indexed). */
export function ratingsLine(e: {
  ratings: { available: boolean; count: number; average: number; isIndexedZero: boolean };
}): string | null {
  if (!e.ratings.available) return null;
  if (e.ratings.count === 0) return 'No ratings yet';
  return `${e.ratings.average.toFixed(1)} average from ${e.ratings.count} rating${
    e.ratings.count === 1 ? '' : 's'
  } (opinion, not current condition)`;
}

export interface GoView {
  headline: string;
  explanation: string;
  tone: GoJson['presentation']['tone'];
  primaryCta: string;
  secondaryCta: string | null;
  navigationAllowed: boolean;
  requiresConfirmation: boolean;
  cautions: string[];
}

/** Pass the core's presentation block straight through — no reinterpretation. */
export function goView(go: GoJson): GoView {
  const p = go.presentation;
  return {
    headline: p.headline,
    explanation: p.explanation,
    tone: p.tone,
    primaryCta: p.primaryCta,
    secondaryCta: p.secondaryCta,
    navigationAllowed: p.navigationAllowed,
    requiresConfirmation: p.requiresConfirmation,
    cautions: p.cautions,
  };
}

export function metersLabel(m: number | null): string {
  if (m == null || !Number.isFinite(m)) return '';
  if (m < 950) return `${Math.round(m / 10) * 10} m away`;
  return `${(m / 1000).toFixed(m < 9500 ? 1 : 0)} km away`;
}

/**
 * A TRUTHFUL, non-sensitive *location* descriptor from descriptive fields that
 * are already on the document — no reverse geocoding, no Places/Maps, no
 * fabrication . Priority: landmark → a locality-bearing address (never the
 * bare state) → null. Returns null when the data offers nothing useful (the
 * common "Public Toilet / Rajasthan, India" case); distance then stands alone.
 *
 * This function is descriptive only. It deliberately does NOT touch
 * `gender_type` — restricted-gender is a *factual* claim and must come from the
 * shared Truth V2 result via `genderDescriptorFromTruth`, never from the raw
 * Firestore field .
 */
export function locationDescriptorFor(rawMap: Record<string, unknown> | undefined): string | null {
  if (!rawMap) return null;
  const landmark = typeof rawMap['landmark'] === 'string' ? rawMap['landmark'].trim() : '';
  const address = typeof rawMap['address'] === 'string' ? rawMap['address'].trim() : '';
  if (landmark) return landmark;
  if (address && !/^(rajasthan,\s*)?india$/i.test(address) && /[,\s]/.test(address)) {
    return address.replace(/\s+/g, ' ');
  }
  return null;
}

/**
 * The restricted-gender note, translated 1:1 from the AUTHORITATIVE gender that
 * the shared Dart Truth V2 parser / legacy adapter already decided
 * (`core.evaluateTruth(map).gender`). This is a label table for a single enum
 * the core produced — it does NOT re-derive gender from raw fields and does NOT
 * recreate any Truth precedence in TypeScript .
 *
 * Mapping mirrors the frozen core presentation table
 * (`presentation_truth.dart` `_genderLabel`): women → "Women only",
 * men → "Men only", unisex → "Unisex", unknown → null (omit from the UI).
 */
export function genderDescriptorFromTruth(truth: Pick<TruthJson, 'gender'>): string | null {
  switch (truth.gender) {
    case 'women':
      return 'Women only';
    case 'men':
      return 'Men only';
    case 'unisex':
      return 'Unisex';
    case 'unknown':
      return null;
  }
}

/**
 * Compose the secondary line shown under a toilet name: the descriptive
 * location part first, then the Truth-derived gender note. Either half may be
 * absent; returns null when both are.
 */
export function secondaryDescriptor(
  rawMap: Record<string, unknown> | undefined,
  truth: Pick<TruthJson, 'gender'>,
): string | null {
  const parts = [locationDescriptorFor(rawMap), genderDescriptorFromTruth(truth)].filter(
    (p): p is string => !!p,
  );
  return parts.length ? parts.join(' · ') : null;
}
