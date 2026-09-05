import { describe, it, expect, beforeAll } from 'vitest';
import { loadCore, type ShauchmapCore } from '../src/core/interop';
import { acquireGoPool } from '../src/domain/geo-pool';
import { runGo, primaryTargetId } from '../src/domain/resolve-go';
import { freshTargetMeta } from '../src/domain/nav-target';
import { DataUnavailableError, type LoadOpts, type RawToiletDoc, type ToiletSource } from '../src/data/source';

const USER = { lat: 26.2389, lng: 73.0243 };
const northLat = (m: number) => USER.lat + m / 111_320;

function src(docs: RawToiletDoc[]): ToiletSource {
  return {
    name: 'fixture',
    async loadCandidates(_u, _o: LoadOpts) {
      return docs;
    },
    async loadById(id) {
      return docs.find((d) => d.id === id) ?? null;
    },
  };
}
function osm(id: string, m: number, extra: Record<string, unknown> = {}): RawToiletDoc {
  return { id, data: { name: id.toUpperCase(), added_by: 'osm_x', latitude: northLat(m), longitude: USER.lng, ...extra } };
}

let core: ShauchmapCore;
beforeAll(async () => {
  core = await loadCore();
});

// near (plain, selected), mid (corroborated-usable alt), far (plain alt)
function conditionUsable(now: number) {
  const T = 60_000;
  return {
    version: 1,
    condition: {
      open: 'yes', water: 'unknown', usable: 'yes', lock: 'unknown', contributor_count: 3,
      latest_at: { __ts__: now - 6 * T }, valid_until: { __ts__: now + 54 * T },
      computed_at: { __ts__: now - 5 * T }, last_event_at: { __ts__: now - 6 * T },
      support: {
        open: { yes: 3, no: 0, unknown: 0 }, water: { yes: 0, no: 0, unknown: 3 },
        usable: { yes: 3, no: 0, unknown: 0 }, lock: { yes: 0, no: 0, unknown: 3 },
      },
    },
  };
}

describe('/t/:id hint focus (frozen Android semantics, via the shared core)', () => {
  const now = Date.now();
  const docs = [osm('near', 100), osm('mid', 180, { evidence_v2: conditionUsable(now) }), osm('far', 900)];

  async function resolve(hintId: string | null) {
    const pool = await acquireGoPool({ source: src(docs), core, user: USER });
    return runGo({ core, pool, nowMs: now, hintId });
  }

  it('hint = a non-selected active-tier alternative -> FOCUSES it (never gains selection)', async () => {
    const r = await resolve('mid');
    expect(r.focus?.id).toBe('mid');
    expect(r.focus?.isSelected).toBe(false);
    expect(r.go.selectedId).toBe('near'); // FOCUS != SELECTED
    expect(r.hintIneligible).toBe(false);
    expect(primaryTargetId(r)).toBe('mid'); // Navigate targets the focus
  });

  it('hint == the selected toilet -> no focus, normal selected view', async () => {
    const r = await resolve('near');
    expect(r.focus).toBeNull();
    expect(r.hintIneligible).toBe(false);
    expect(primaryTargetId(r)).toBe('near');
  });

  it('hint empty -> no focus', async () => {
    const r = await resolve('');
    expect(r.focus).toBeNull();
    expect(r.hintIneligible).toBe(false);
  });

  it('hint = unknown id -> no focus, hintIneligible note shown', async () => {
    const r = await resolve('does-not-exist');
    expect(r.focus).toBeNull();
    expect(r.hintIneligible).toBe(true);
    expect(primaryTargetId(r)).toBe('near'); // falls back to the top pick
  });

  it('hint = moderation-flagged (dropped from the active tier) -> no focus, hintIneligible', async () => {
    const flagged = [
      osm('near', 100),
      osm('flag', 150, { is_flagged: true, flagged_until: { __ts__: now + 2 * 24 * 3600_000 }, evidence_v2: conditionUsable(now) }),
      osm('far', 900),
    ];
    const pool = await acquireGoPool({ source: src(flagged), core, user: USER });
    const r = runGo({ core, pool, nowMs: now, hintId: 'flag' });
    expect(r.focus).toBeNull();
    expect(r.hintIneligible).toBe(true);
  });

 it('freshTargetMeta: alternative target keeps its OWN distance, not the selected one ', async () => {
    const r = await resolve('mid');
    const selMeta = freshTargetMeta(r, r.go.selectedId);
    const altMeta = freshTargetMeta(r, 'mid');
    const focusMeta = freshTargetMeta(r, r.focus!.id);
    expect(selMeta.kind).toBe('selected');
    expect(altMeta.distanceMeters).toBe(r.focus!.distanceMeters);
    expect(altMeta.distanceMeters).not.toBe(selMeta.distanceMeters);
    expect(focusMeta.name).toBe('MID');
  });

  it('never throws for a legitimate empty/ghost hint', async () => {
    await expect(resolve('ghost')).resolves.toBeTruthy();
    await expect(resolve(null)).resolves.toBeTruthy();
  });

  it('smoke: a source failure still propagates (hint path does not swallow it)', async () => {
    const failing: ToiletSource = {
      name: 'fixture',
      async loadCandidates() {
        throw new DataUnavailableError('down', 'backend');
      },
      async loadById() {
        return null;
      },
    };
    await expect(
      acquireGoPool({ source: failing, core, user: USER }),
    ).rejects.toBeInstanceOf(DataUnavailableError);
  });
});
