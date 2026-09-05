// The typed TypeScript wrapper around the ONE authoritative Dart brain.
//
// Rules :
//   - No Dart object graph crosses the boundary — canonical JSON strings only.
//   - The web shell NEVER reimplements Truth / Evidence / GO / revalidation /
//     location-freshness. Every call here delegates to the compiled core.
//   - A compiled-JS / wrapper interop-version disagreement is fatal and loud.

import { loadCoreGlobal } from './core-loader';
import {
  CORE_INTEROP_VERSION,
  type DistanceResult,
  type DistancesInput,
  type DistancesResultJson,
  type EvidenceJson,
  type FreshnessInput,
  type FreshnessResultJson,
  type GoInputItem,
  type GoJson,
  type RevalOutcome,
  type RevalSide,
  type ShauchmapCoreGlobal,
  type ToiletMapJson,
  type TruthJson,
} from './types';

export class CoreVersionMismatchError extends Error {
  constructor(
    readonly compiled: number,
    readonly wrapper: number,
  ) {
    super(
      `ShauchMap core interop mismatch: compiled brain v${compiled}, web wrapper v${wrapper}. ` +
        `Rebuild the core (npm run build:core) or update the web shell — refusing to run with a stale brain.`,
    );
    this.name = 'CoreVersionMismatchError';
  }
}

export interface ShauchmapCore {
  readonly interopVersion: number;
  readonly buildVersion: string;
  evaluateTruth(toiletMap: ToiletMapJson): TruthJson;
  evaluateEvidence(evidenceV2: unknown, nowMs: number): EvidenceJson;
  /** `hintId` (the /t/:id deep-link target) makes the result carry a `focus`. */
  evaluateGo(pool: GoInputItem[], nowMs: number, hintId?: string | null): GoJson;
  evaluateRevalidation(input: {
    targetId: string | null;
    stale: RevalSide;
    fresh: RevalSide;
  }): RevalOutcome;
  evaluatePositionFreshness(input: FreshnessInput): boolean;
  /** Canonical geoDistanceMeters (= Geolocator.distanceBetween), batched. */
  evaluateDistances(input: DistancesInput): DistanceResult[];
}

function wrap(raw: ShauchmapCoreGlobal): ShauchmapCore {
  if (raw.interopVersion !== CORE_INTEROP_VERSION) {
    throw new CoreVersionMismatchError(raw.interopVersion, CORE_INTEROP_VERSION);
  }
  return {
    interopVersion: raw.interopVersion,
    buildVersion: raw.version,
    evaluateTruth: (m) => JSON.parse(raw.evaluateTruth(JSON.stringify(m))) as TruthJson,
    evaluateEvidence: (e, nowMs) =>
      JSON.parse(raw.evaluateEvidence(JSON.stringify(e ?? null), nowMs)) as EvidenceJson,
    evaluateGo: (pool, nowMs, hintId) =>
      JSON.parse(
        raw.evaluateGo(
          JSON.stringify(hintId === undefined ? { pool } : { pool, hintId: hintId ?? '' }),
          nowMs,
        ),
      ) as GoJson,
    evaluateRevalidation: (input) =>
      (JSON.parse(raw.evaluateRevalidation(JSON.stringify(input))) as { outcome: RevalOutcome })
        .outcome,
    evaluatePositionFreshness: (input) =>
      (JSON.parse(raw.evaluatePositionFreshness(JSON.stringify(input))) as FreshnessResultJson)
        .fresh,
    evaluateDistances: (input) =>
      (JSON.parse(raw.evaluateDistances(JSON.stringify(input))) as DistancesResultJson).distances,
  };
}

let cached: Promise<ShauchmapCore> | null = null;

/** Idempotent. Loads + version-checks the core, returns the typed wrapper. */
export function loadCore(): Promise<ShauchmapCore> {
  if (cached) return cached;
  cached = loadCoreGlobal().then(wrap);
  return cached;
}

/** Test-only. */
export function __resetInteropForTests(): void {
  cached = null;
}

/** Test-only: run the version guard + wrapper against an arbitrary raw global. */
export function wrapForTests(raw: ShauchmapCoreGlobal): ShauchmapCore {
  return wrap(raw);
}
