import { describe, it, expect, beforeAll } from 'vitest';
import { loadCore, type ShauchmapCore } from '../src/core/interop';
import { acquireGoPool } from '../src/domain/geo-pool';
import { runGo } from '../src/domain/resolve-go';
import { revalidateBeforeNavigate } from '../src/domain/revalidate';
import type { RawToiletDoc, ToiletSource } from '../src/data/source';

const USER = { lat: 26.2389, lng: 73.0243 };
const northLat = (m: number) => USER.lat + m / 111_320;

function source(docs: RawToiletDoc[]): ToiletSource {
  return {
    name: 'fixture',
    async loadCandidates() {
      return docs;
    },
    async loadById(id) {
      return docs.find((d) => d.id === id) ?? null;
    },
  };
}

function geoAt(ts: number): Geolocation {
  return {
    getCurrentPosition: (ok) =>
      ok({
        coords: {
          latitude: USER.lat,
          longitude: USER.lng,
          accuracy: 10,
          altitude: null,
          altitudeAccuracy: null,
          heading: null,
          speed: null,
          toJSON() { return this; },
        },
        timestamp: ts,
        toJSON() { return this; },
      } as GeolocationPosition),
    watchPosition: () => 0,
    clearWatch: () => undefined,
  };
}

let core: ShauchmapCore;
beforeAll(async () => {
  core = await loadCore();
});

describe('navigation-time revalidation ', () => {
  const docs: RawToiletDoc[] = [
    { id: 'a', data: { name: 'A', latitude: northLat(120), longitude: USER.lng, added_by: 'osm_x' } },
    { id: 'b', data: { name: 'B', latitude: northLat(300), longitude: USER.lng, added_by: 'osm_x' } },
  ];

  it('re-acquires, rebuilds the full pool, re-runs GO and asks the core for the outcome', async () => {
    const pool = await acquireGoPool({ source: source(docs), core, user: USER });
    const stale = runGo({ core, pool, nowMs: 1_000_000 });

    const now = () => 2_000_000;
    const res = await revalidateBeforeNavigate({
      core,
      source: source(docs),
      stale,
      targetId: stale.go.selectedId,
      now,
      geolocation: geoAt(2_000_000 - 2000),
    });

    expect(res.kind).toBe('resolved');
    if (res.kind === 'resolved') {
      expect(['launch', 'refreshSuggestion', 'refreshOption', 'confirmThenLaunch']).toContain(
        res.outcome,
      );
      expect(res.fresh.go.selectedId).toBe(stale.go.selectedId);
    }
  });

  it('returns a location-problem (never launches) when the fresh fix is stale', async () => {
    const pool = await acquireGoPool({ source: source(docs), core, user: USER });
    const stale = runGo({ core, pool, nowMs: 1_000_000 });
    const res = await revalidateBeforeNavigate({
      core,
      source: source(docs),
      stale,
      targetId: 'a',
      now: () => 5_000_000,
      geolocation: geoAt(5_000_000 - 120_000), // 2 min old
    });
    expect(res.kind).toBe('location-problem');
    if (res.kind === 'location-problem') expect(res.outcome.status).toBe('stale');
  });

 it('keeps the /t/:id focus through revalidation — fresh result focuses the hinted alt, confirm meta is the FOCUS metadata not the selected', async () => {
    const T = 60_000;
    const withEvidence = {
      version: 1,
      condition: {
        open: 'yes', water: 'unknown', usable: 'yes', lock: 'unknown', contributor_count: 3,
        latest_at: { __ts__: 1_000_000 - 6 * T }, valid_until: { __ts__: 1_000_000 + 54 * T },
        computed_at: { __ts__: 1_000_000 - 5 * T }, last_event_at: { __ts__: 1_000_000 - 6 * T },
        support: {
          open: { yes: 3, no: 0, unknown: 0 }, water: { yes: 0, no: 0, unknown: 3 },
          usable: { yes: 3, no: 0, unknown: 0 }, lock: { yes: 0, no: 0, unknown: 3 },
        },
      },
    };
    const pool3 = [
      { id: 'near', data: { name: 'NEAR', latitude: northLat(100), longitude: USER.lng, added_by: 'osm_x' } },
      { id: 'mid', data: { name: 'MID', latitude: northLat(180), longitude: USER.lng, added_by: 'osm_x', evidence_v2: withEvidence } },
      { id: 'far', data: { name: 'FAR', latitude: northLat(900), longitude: USER.lng, added_by: 'osm_x' } },
    ];
    const { acquireGoPool: acq } = await import('../src/domain/geo-pool');
    const pool = await acq({ source: source(pool3), core, user: USER });
    const stale = runGo({ core, pool, nowMs: 1_000_000, hintId: 'mid' });
    expect(stale.focus?.id).toBe('mid');

    const res = await revalidateBeforeNavigate({
      core,
      source: source(pool3),
      stale,
      targetId: 'mid',
      now: () => 2_000_000,
      geolocation: geoAt(2_000_000 - 2000),
    });
    expect(res.kind).toBe('resolved');
    if (res.kind === 'resolved') {
      expect(res.fresh.focus?.id).toBe('mid'); // focus survived
      expect(res.fresh.go.selectedId).toBe('near'); // still not selected
      const { freshTargetMeta } = await import('../src/domain/nav-target');
      const meta = freshTargetMeta(res.fresh, 'mid');
      expect(meta.kind).toBe('focus');
      expect(meta.distanceMeters).toBe(res.fresh.focus!.distanceMeters);
      expect(meta.distanceMeters).not.toBe(res.fresh.go.selectedDistanceMeters);
    }
  });

  it('returns a data-problem when the fresh pool load fails', async () => {
    const failing: ToiletSource = {
      name: 'fixture',
      async loadCandidates() {
        throw new Error('backend down');
      },
      async loadById() {
        return null;
      },
    };
    const pool = await acquireGoPool({ source: source(docs), core, user: USER });
    const stale = runGo({ core, pool, nowMs: 1_000_000 });
    const res = await revalidateBeforeNavigate({
      core,
      source: failing,
      stale,
      targetId: 'a',
      now: () => 2_000_000,
      geolocation: geoAt(2_000_000 - 1000),
    });
    expect(res.kind).toBe('data-problem');
  });
});
