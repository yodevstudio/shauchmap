// TypeScript mirrors of the canonical JSON shapes produced by the ONE
// authoritative Dart core (packages/shauchmap_core/lib/interop/canonical.dart).
// These DESCRIBE the core's output — the web shell never recomputes it. If the
// core's serializers change, bump CORE_INTEROP_VERSION in lockstep with
// `kCoreInteropVersion` in canonical.dart.

/** Interop contract version. MUST equal `kCoreInteropVersion` in canonical.dart.
 *  v1: truth, evidence, go, revalidation, positionFreshness.
 *  v2: + evaluateDistances (canonical geoDistanceMeters, batched).
 *  v3: evaluateGo input may carry `hintId` -> result gains a `focus` block
 *      (shared resolveHintFocus / goAlternativeFromTarget / presentGoAlternative). */
export const CORE_INTEROP_VERSION = 3;

/** Timestamp sentinel understood by the core adapter: {"__ts__": epochMillis}. */
export interface TsSentinel {
  __ts__: number;
}
export const ts = (epochMillis: number): TsSentinel => ({ __ts__: epochMillis });

// ---- Truth V2 (packages/shauchmap_core/lib/src/truth/toilet_truth.dart) -----
export type ToiletSource = 'osm' | 'communitySubmission' | 'legacyCommunity' | 'unknown';
export type IdentityStatus = 'sourceMapped' | 'candidate' | 'communitySubmitted' | 'unknown';
export type FacilityContext =
  | 'unknown'
  | 'publicToilet'
  | 'petrolStation'
  | 'commercial'
  | 'station'
  | 'other';
export type GenderAccess = 'unknown' | 'unisex' | 'men' | 'women';
export type FeeState = 'free' | 'paid' | 'unknown';
/** Amenity tri-state — serialized from EvidenceState.name. */
export type AmenityState = 'present' | 'absent' | 'unknown';
/** Condition tri-state — serialized from ConditionState.name. */
export type Tri = 'yes' | 'no' | 'unknown';

export interface AmenitiesJson {
  water: AmenityState;
  soap: AmenityState;
  lock: AmenityState;
  western: AmenityState;
  wheelchair: AmenityState;
  babyChange: AmenityState;
  sanitaryDisposal: AmenityState;
}

export interface TruthJson {
  schemaVersion: number;
  source: ToiletSource;
  recordedAtMs: number | null;
  context: FacilityContext;
  gender: GenderAccess;
  identityStatus: IdentityStatus;
  fee: FeeState;
  isNativeV2: boolean;
  isCandidate: boolean;
  amenities: AmenitiesJson;
}

// ---- Evidence V2 (…/lib/src/evidence/toilet_evidence.dart) -----------------
export interface SupportJson {
  yes: number;
  no: number;
  unknown: number;
}
export interface RatingsJson {
  available: boolean;
  count: number;
  average: number;
  isIndexedZero: boolean;
}
export interface VotesJson {
  available: boolean;
  up: number;
  down: number;
  isIndexedZero: boolean;
}
export interface ConditionJson {
  available: boolean;
  open: Tri;
  water: Tri;
  usable: Tri;
  lock: Tri;
  contributorCount: number;
  latestAtMs: number | null;
  validUntilMs: number | null;
  isCurrentlyValid: boolean;
  ageMinutes: number | null;
  supportOpen: SupportJson;
  supportWater: SupportJson;
  supportUsable: SupportJson;
  supportLock: SupportJson;
}
export interface EvidenceJson {
  present: boolean;
  version: number;
  ratings: RatingsJson;
  votes: VotesJson;
  condition: ConditionJson;
}

// ---- GO V2 (…/lib/src/go/go_decision.dart, go_presentation.dart) ----------
export type GoReason =
  | 'noToilets'
  | 'nearestWithNoStrongEvidence'
  | 'recentCorroboratedUsableWithinDetour'
  | 'avoidedRecentCorroboratedUnavailable'
  | 'singleNegativeWarning'
  | 'conflictedNegativeWarning'
  | 'bestMappedOptionCorroboratedUnavailable'
  | 'communitySubmissionFallback'
  | 'candidateFallback'
  | 'onlyFlaggedOrUnconfirmedOptions';

export type GoCaution =
  | 'singleReportUnavailable'
  | 'conflictedUnavailable'
  | 'corroboratedUnavailable'
  | 'unconfirmedCommunityIdentity'
  | 'candidateIdentity'
  | 'unknownIdentity'
  | 'moderationFlagged'
  | 'waterReportedOut'
  | 'lockReportedOut';

export type RecommendationAuthority =
  | 'sourceMappedPrimary'
  | 'communityCorroborated'
  | 'communityFallback'
  | 'candidateFallback'
  | 'unknownFallback'
  | 'flaggedExcluded';

export type OperationalCondition =
  | 'corroboratedUsable'
  | 'singleReportedUsable'
  | 'conflictedUsableMajority'
  | 'unknown'
  | 'singleReportedUnavailable'
  | 'conflictedUnavailableMajority'
  | 'corroboratedUnavailable';

export type GoTone = 'neutral' | 'positive' | 'warning';

export interface GoAlternativeJson {
  id: string;
  distanceMeters: number;
  authority: RecommendationAuthority;
  condition: OperationalCondition;
  requiresConfirmation: boolean;
  cautions: GoCaution[];
}
export interface GoPresentationJson {
  headline: string;
  explanation: string;
  navigationAllowed: boolean;
  requiresConfirmation: boolean;
  primaryCta: string;
  secondaryCta: string | null;
  cautions: string[];
  tone: GoTone;
}
/** The /t/:id deep-link FOCUS — the shared core's `resolveHintFocus` outcome.
 *  Present on GoJson only when `evaluateGo` was given a `hintId`. `null` when the
 *  hint is the selected toilet, absent, or not in the fresh active tier. Carries
 *  the alternative's OWN presentation (`presentGoAlternative`). NEVER selected. */
export interface GoFocusJson {
  id: string;
  distanceMeters: number;
  authority: RecommendationAuthority;
  condition: OperationalCondition;
  requiresConfirmation: boolean;
  cautions: GoCaution[];
  isSelected: false;
  presentation: GoPresentationJson;
}

export interface GoJson {
  selectedId: string | null;
  selectedDistanceMeters: number | null;
  reason: GoReason;
  requiresConfirmation: boolean;
  cautions: GoCaution[];
  alternatives: GoAlternativeJson[];
  baselineNearestId: string | null;
  baselineNearestDistanceMeters: number | null;
  presentation: GoPresentationJson;
  /** Only when a hintId was passed to evaluateGo. */
  focus?: GoFocusJson | null;
}

// ---- revalidation & freshness (…/lib/src/go/go_resolver.dart) -------------
export type RevalOutcome = 'launch' | 'refreshSuggestion' | 'refreshOption' | 'confirmThenLaunch';
export interface RevalResultJson {
  outcome: RevalOutcome;
}
export interface FreshnessResultJson {
  fresh: boolean;
}

// ---- core input shapes --------------------------------------------------
export type FirestoreScalar = string | number | boolean | null;
export type CanonicalValue =
  | FirestoreScalar
  | TsSentinel
  | CanonicalValue[]
  | { [k: string]: CanonicalValue };
export type ToiletMapJson = Record<string, CanonicalValue>;

export interface GoInputItem {
  id: string;
  distanceMeters: number;
  map: ToiletMapJson;
}
export interface RevalPoolItem {
  id: string;
  lat: number;
  lng: number;
  map: ToiletMapJson;
}
export interface RevalSide {
  userLat: number;
  userLng: number;
  nowMs: number;
  pool: RevalPoolItem[];
}
export interface FreshnessInput {
  positionTsMs: number;
  nowMs: number;
  maxAgeSeconds: number;
}
export interface DistanceTarget {
  id: string;
  lat: number;
  lng: number;
}
export interface DistancesInput {
  from: { lat: number; lng: number };
  to: DistanceTarget[];
}
export interface DistanceResult {
  id: string;
  meters: number;
}
export interface DistancesResultJson {
  distances: DistanceResult[];
}

/** The raw global installed by the compiled Dart (globalThis.shauchmapCore). */
export interface ShauchmapCoreGlobal {
  evaluateTruth(jsonToiletMap: string): string;
  evaluateEvidence(jsonEvidenceV2: string, nowMs: number): string;
  evaluateGo(jsonGoInput: string, nowMs: number): string;
  evaluateRevalidation(jsonRevalInput: string): string;
  evaluatePositionFreshness(jsonInput: string): string;
  evaluateDistances(jsonInput: string): string;
  interopVersion: number;
  version: string;
}

declare global {
  // eslint-disable-next-line no-var
  var shauchmapCore: ShauchmapCoreGlobal | undefined;
}
