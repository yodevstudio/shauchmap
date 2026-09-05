import { describe, it, expect, beforeAll } from 'vitest';
import { loadCore, type ShauchmapCore } from '../src/core/interop';
import { acquireGoPool } from '../src/domain/geo-pool';
import { DataUnavailableError, type LoadOpts, type RawToiletDoc, type ToiletSource } from '../src/data/source';

const USER = { lat: 26.2389, lng: 73.0243 };

function fakeSource(docs: RawToiletDoc[], opts: { delayMs?: number; throwErr?: Error } = {}): ToiletSource {
  return {
    name: 'fixture',
    async loadCandidates(_u, o: LoadOpts) {
      if (opts.throwErr) throw opts.throwErr;
      if (opts.delayMs) await new Promise((r) => setTimeout(r, opts.delayMs));
      if (o.signal?.aborted) throw new DataUnavailableError('aborted', 'timeout');
      return docs;
    },
    async loadById(id) {
      return docs.find((d) => d.id === id) ?? null;
    },
  };
}

// metres north of USER -> lat
const northLat = (m: number) => USER.lat + m / 111_320;

let core: ShauchmapCore;
beforeAll(async () => {
  core = await loadCore();
});

describe('acquireGoPool ', () => {
  it('applies a STRICT 15 km cutoff and never caps the result', async () => {
    const docs: RawToiletDoc[] = [];
    for (let i = 0; i < 120; i++) {
      docs.push({
        id: `t${String(i).padStart(3, '0')}`,
        data: { name: `T${i}`, latitude: northLat(100 + i * 130), longitude: USER.lng, added_by: 'osm_x' },
      });
    }
    // one just beyond 15 km, one far outside
    docs.push({ id: 'edge', data: { name: 'edge', latitude: northLat(15_050), longitude: USER.lng, added_by: 'osm_x' } });
    docs.push({ id: 'far', data: { name: 'far', latitude: northLat(90_000), longitude: USER.lng, added_by: 'osm_x' } });

    const pool = await acquireGoPool({ source: fakeSource(docs), core, user: USER });
    expect(pool.entries.every((e) => e.distanceMeters <= 15_000)).toBe(true);
    expect(pool.entries.find((e) => e.id === 'edge')).toBeUndefined();
    expect(pool.entries.find((e) => e.id === 'far')).toBeUndefined();
    // no arbitrary cap — well over any 50/80/100 limit survives
    expect(pool.entries.length).toBeGreaterThan(100);
    expect(pool.candidateCount).toBe(docs.length);
  });

  it('orders by (distance, then id) deterministically', async () => {
    const docs: RawToiletDoc[] = [
      { id: 'z', data: { latitude: northLat(300), longitude: USER.lng, added_by: 'osm' } },
      { id: 'a', data: { latitude: northLat(300), longitude: USER.lng, added_by: 'osm' } },
      { id: 'm', data: { latitude: northLat(100), longitude: USER.lng, added_by: 'osm' } },
    ];
    const pool = await acquireGoPool({ source: fakeSource(docs), core, user: USER });
    expect(pool.entries.map((e) => e.id)).toEqual(['m', 'a', 'z']);
  });

  it('uses the canonical shared-core distance (matches core.evaluateDistances)', async () => {
    const docs: RawToiletDoc[] = [
      { id: 't', data: { latitude: northLat(423), longitude: USER.lng, added_by: 'osm' } },
    ];
    const pool = await acquireGoPool({ source: fakeSource(docs), core, user: USER });
    const [{ meters }] = core.evaluateDistances({
      from: USER,
      to: [{ id: 't', lat: northLat(423), lng: USER.lng }],
    });
    expect(pool.entries[0].distanceMeters).toBe(meters);
  });

  it('drops candidates without real coordinates', async () => {
    const docs: RawToiletDoc[] = [
      { id: 'ok', data: { latitude: northLat(100), longitude: USER.lng, added_by: 'osm' } },
      { id: 'nocoords', data: { name: 'broken', added_by: 'osm' } },
    ];
    const pool = await acquireGoPool({ source: fakeSource(docs), core, user: USER });
    expect(pool.entries.map((e) => e.id)).toEqual(['ok']);
  });

  it('surfaces an honest timeout instead of an empty pool', async () => {
    await expect(
      acquireGoPool({ source: fakeSource([], { delayMs: 200 }), core, user: USER, timeoutMs: 30 }),
    ).rejects.toBeInstanceOf(DataUnavailableError);
  });

  it('propagates a source failure (never swallows it)', async () => {
    await expect(
      acquireGoPool({
        source: fakeSource([], { throwErr: new DataUnavailableError('partial', 'partial') }),
        core,
        user: USER,
      }),
    ).rejects.toMatchObject({ kind: 'partial' });
  });
});
