// Navigation-time revalidation . MANDATORY before every Maps
// hand-off. We NEVER open the previously-rendered target blindly.
//
//   reacquire location -> shared freshness -> reload COMPLETE 15 km pool ->
//   shared GO -> shared revalidation -> act on launch / refreshSuggestion /
//   refreshOption / confirmThenLaunch.

import type { ShauchmapCore } from '../core/interop';
import type { RevalOutcome, RevalSide } from '../core/types';
import { isDemo } from '../data/mode';
import type { ToiletSource } from '../data/source';

const REVAL_OUTCOMES: RevalOutcome[] = [
  'launch',
  'refreshSuggestion',
  'refreshOption',
  'confirmThenLaunch',
];
function demoRevalOutcome(): RevalOutcome | null {
  if (!isDemo() || typeof location === 'undefined') return null;
  const v = new URLSearchParams(location.search).get('reval') as RevalOutcome | null;
  return v && REVAL_OUTCOMES.includes(v) ? v : null;
}
import { acquireGoPool, type GoPool } from './geo-pool';
import { acquireLocation, type LocationOutcome } from '../location/geolocation';
import { primaryTargetId, runGo, type GoResult } from './resolve-go';

function sideFrom(pool: GoPool, nowMs: number): RevalSide {
  return {
    userLat: pool.user.lat,
    userLng: pool.user.lng,
    nowMs,
    pool: pool.entries.map((e) => ({ id: e.id, lat: e.lat, lng: e.lng, map: e.map })),
  };
}

export type RevalidationResult =
  | {
      kind: 'resolved';
      outcome: RevalOutcome;
      /** Fresh decision — render this FIRST if it differs. */
      fresh: GoResult;
      freshFix: { lat: number; lng: number; timestampMs: number };
      /** true when the fresh target differs from what the user tapped. */
      targetChanged: boolean;
    }
  | { kind: 'location-problem'; outcome: LocationOutcome }
  | { kind: 'data-problem'; error: Error };

export async function revalidateBeforeNavigate(params: {
  core: ShauchmapCore;
  source: ToiletSource;
  stale: GoResult;
  /** What the user tapped Navigate on (selected id, or an alternative's id). */
  targetId: string | null;
  now?: () => number;
  geolocation?: Geolocation;
}): Promise<RevalidationResult> {
  // The /t/:id hint persists through revalidation — the FRESH decision is
  // resolved WITH it, so the focused facility stays the main card and any
 // confirm/refresh copy is the FRESH focus's own .
  const hintId = params.stale.hintId;
  const now = params.now ?? Date.now;

  const loc = await acquireLocation({
    core: params.core,
    ...(params.now ? { now: params.now } : {}),
    ...(params.geolocation ? { geolocation: params.geolocation } : {}),
  });
  if (loc.status !== 'ok') return { kind: 'location-problem', outcome: loc };

  let freshPool: GoPool;
  try {
    freshPool = await acquireGoPool({
      source: params.source,
      core: params.core,
      user: { lat: loc.fix.lat, lng: loc.fix.lng },
    });
  } catch (error) {
    return { kind: 'data-problem', error: error as Error };
  }

  const freshNow = now();
  const fresh = runGo({ core: params.core, pool: freshPool, nowMs: freshNow, hintId });

  const outcome =
    demoRevalOutcome() ??
    params.core.evaluateRevalidation({
      targetId: params.targetId,
      stale: sideFrom(params.stale.pool, params.stale.nowMs),
      fresh: sideFrom(freshPool, freshNow),
    });

  return {
    kind: 'resolved',
    outcome,
    fresh,
    freshFix: { lat: loc.fix.lat, lng: loc.fix.lng, timestampMs: loc.fix.timestampMs },
    targetChanged: params.targetId != null && primaryTargetId(fresh) !== params.targetId,
  };
}
