import { describe, it, expect, beforeAll } from 'vitest';
import { loadCore, type ShauchmapCore } from '../src/core/interop';
import { acquireLocation } from '../src/location/geolocation';

let core: ShauchmapCore;
beforeAll(async () => {
  core = await loadCore();
});

const NOW = 1_788_393_600_000;

function geo(behaviour: (ok: PositionCallback, err: PositionErrorCallback) => void): Geolocation {
  return {
    getCurrentPosition: (ok, err) => behaviour(ok, err as PositionErrorCallback),
    watchPosition: () => 0,
    clearWatch: () => undefined,
  };
}

function pos(timestampMs: number, accuracy: number = 12, lat = 26.2389, lng = 73.0243): GeolocationPosition {
  return {
    coords: {
      latitude: lat,
      longitude: lng,
      accuracy,
      altitude: null,
      altitudeAccuracy: null,
      heading: null,
      speed: null,
      toJSON() { return this; },
    },
    timestamp: timestampMs,
    toJSON() { return this; },
  } as GeolocationPosition;
}

/** A fresh position with NO `coords.accuracy` at all (some engines omit it). */
function posNoAccuracy(timestampMs: number): GeolocationPosition {
  const p = pos(timestampMs);
  delete (p.coords as { accuracy?: number }).accuracy;
  return p;
}

const ERR = { PERMISSION_DENIED: 1, POSITION_UNAVAILABLE: 2, TIMEOUT: 3 } as const;

/** geolocation stub whose Phase-A getCurrentPosition returns `first`, and whose
 *  watchPosition (Phase B) emits `samples` one per tick until cleared.
 *  Instrumented: `.calls` records watch start / clear counts and live watches. */
type StagedGeo = Geolocation & {
  calls: { watchStarts: number; clearWatch: number; liveWatches: () => number };
};
function stagedGeo(
  first: GeolocationPosition | GeolocationPositionError,
  samples: (GeolocationPosition | GeolocationPositionError)[] = [],
): StagedGeo {
  const intervals = new Map<number, ReturnType<typeof setInterval>>();
  let nextId = 1;
  const calls = { watchStarts: 0, clearWatch: 0, liveWatches: () => intervals.size };
  return {
    calls,
    getCurrentPosition: (ok, err) =>
      'code' in first ? (err as PositionErrorCallback)(first) : ok(first as GeolocationPosition),
    watchPosition: (ok, err) => {
      const id = nextId++;
      calls.watchStarts++;
      let i = 0;
      const t = setInterval(() => {
        if (i >= samples.length) return;
        const s = samples[i++];
        if ('code' in s) (err as PositionErrorCallback)?.(s as GeolocationPositionError);
        else (ok as PositionCallback)(s as GeolocationPosition);
      }, 3);
      intervals.set(id, t);
      return id;
    },
    clearWatch: (id) => {
      calls.clearWatch++;
      const t = intervals.get(id);
      if (t) clearInterval(t);
      intervals.delete(id);
    },
  };
}

describe('browser location adapter ', () => {
  it('returns ok for a fresh fix (freshness decided by the core)', async () => {
    const out = await acquireLocation({
      core,
      now: () => NOW,
      geolocation: geo((ok) => ok(pos(NOW - 3000))),
    });
    expect(out.status).toBe('ok');
  });

  it('classifies an old fix as stale (does not fall back)', async () => {
    const out = await acquireLocation({
      core,
      now: () => NOW,
      maxAgeSeconds: 10,
      geolocation: geo((ok) => ok(pos(NOW - 60_000))),
    });
    expect(out.status).toBe('stale');
    if (out.status === 'stale') expect(out.ageSeconds).toBe(60);
  });

  it('flags a future timestamp separately from stale', async () => {
    const out = await acquireLocation({
      core,
      now: () => NOW,
      geolocation: geo((ok) => ok(pos(NOW + 5000))),
    });
    expect(out.status).toBe('future');
  });

  it('maps PERMISSION_DENIED -> denied', async () => {
    const out = await acquireLocation({
      core,
      now: () => NOW,
      geolocation: geo((_ok, err) => err({ code: ERR.PERMISSION_DENIED, message: 'no', ...ERR } as GeolocationPositionError)),
    });
    expect(out.status).toBe('denied');
  });

  it('Phase-A TIMEOUT -> recovery watch finds nothing -> timeout; POSITION_UNAVAILABLE -> unavailable', async () => {
    const t = await acquireLocation({
      core,
      now: () => NOW,
      qualityWindowMs: 30,
      geolocation: stagedGeo({ code: ERR.TIMEOUT, message: 't', ...ERR } as GeolocationPositionError),
    });
    expect(t.status).toBe('timeout');
    const u = await acquireLocation({
      core,
      now: () => NOW,
      geolocation: geo((_ok, err) => err({ code: ERR.POSITION_UNAVAILABLE, message: 'x', ...ERR } as GeolocationPositionError)),
    });
    expect(u.status).toBe('unavailable');
  });

  it('reports unavailable when there is no geolocation API', async () => {
    const out = await acquireLocation({ core, now: () => NOW, geolocation: null });
    expect(out.status).toBe('unavailable');
  });
});

// explicit future-skew boundary cases for the BROWSER ADAPTER.
// The 2 s forward tolerance is a web-adapter normalization only: it clamps a
// slightly-ahead timestamp to `now` before the shared core sees it. It must NOT
// change the shared freshness horizon, and it must NEVER rescue a genuinely
// stale fix.
describe('future-skew tolerance boundary ', () => {
  const at = (deltaMs: number) =>
    acquireLocation({ core, now: () => NOW, maxAgeSeconds: 10, geolocation: geo((ok) => ok(pos(NOW + deltaMs))) });

  it('now → ok', async () => {
    expect((await at(0)).status).toBe('ok');
  });
  it('now + 1 ms → tolerated (clamped to now) → ok', async () => {
    expect((await at(1)).status).toBe('ok');
  });
  it('now + 1999 ms → tolerated (clamped) → ok', async () => {
    expect((await at(1999)).status).toBe('ok');
  });
  it('now + 2000 ms → exactly at tolerance, tolerated (clamped) → ok', async () => {
    expect((await at(2000)).status).toBe('ok');
  });
  it('now + 2001 ms → past tolerance → future', async () => {
    expect((await at(2001)).status).toBe('future');
  });
  it('now + 60 s → future', async () => {
    expect((await at(60_000)).status).toBe('future');
  });

  it('a fix older than the frozen max-age is still STALE — the forward tolerance never backdates a real age', async () => {
    const out = await acquireLocation({
      core,
      now: () => NOW,
      maxAgeSeconds: 10,
      geolocation: geo((ok) => ok(pos(NOW - 11_000))),
    });
    expect(out.status).toBe('stale');
    if (out.status === 'stale') expect(out.ageSeconds).toBe(11);
  });

  it('the shared core rule itself is unchanged: evaluatePositionFreshness still rejects an 11 s-old fix at a 10 s horizon', () => {
    expect(core.evaluatePositionFreshness({ positionTsMs: NOW - 11_000, nowMs: NOW, maxAgeSeconds: 10 })).toBe(false);
    expect(core.evaluatePositionFreshness({ positionTsMs: NOW - 9_000, nowMs: NOW, maxAgeSeconds: 10 })).toBe(true);
  });
});

// the WEB accuracy gate (WEB_MAX_LOCATION_ACCURACY_METERS = 200).
// Freshness AND accuracy are BOTH required. A gate failure is NOT an error — it
// starts a short bounded search and, failing that, returns `imprecise`.
describe('web position accuracy gate ', () => {
  const fresh = (accuracy: number | undefined) =>
    acquireLocation({
      core,
      now: () => NOW,
      maxAgeSeconds: 10,
      qualityWindowMs: 40, // no watch samples -> settles fast as `imprecise`
      geolocation: stagedGeo(pos(NOW - 3000, accuracy as number)),
    });

  it('accuracy 5 m → accepted', async () => expect((await fresh(5)).status).toBe('ok'));
  it('accuracy 50 m → accepted', async () => expect((await fresh(50)).status).toBe('ok'));
  it('accuracy 199.9 m → accepted', async () => expect((await fresh(199.9)).status).toBe('ok'));
  it('accuracy exactly 200 m → accepted (ceiling is inclusive)', async () =>
    expect((await fresh(200)).status).toBe('ok'));

  it('accuracy 200.1 m → not accepted immediately → imprecise (no better fix)', async () => {
    const out = await fresh(200.1);
    expect(out.status).toBe('imprecise');
    if (out.status === 'imprecise') expect(out.bestAccuracyMeters).toBeCloseTo(200.1);
  });
  it('accuracy 500 m → imprecise', async () => {
    const out = await fresh(500);
    expect(out.status).toBe('imprecise');
    if (out.status === 'imprecise') expect(out.bestAccuracyMeters).toBe(500);
  });
  it('accuracy 5000 m → imprecise', async () => {
    expect((await fresh(5000)).status).toBe('imprecise');
  });

  it('accuracy NaN → rejected → imprecise, bestAccuracyMeters null', async () => {
    const out = await fresh(NaN);
    expect(out.status).toBe('imprecise');
    if (out.status === 'imprecise') expect(out.bestAccuracyMeters).toBeNull();
  });
  it('accuracy Infinity → rejected → imprecise', async () => {
    const out = await fresh(Infinity);
    expect(out.status).toBe('imprecise');
    if (out.status === 'imprecise') expect(out.bestAccuracyMeters).toBeNull();
  });
  it('accuracy negative → rejected → imprecise', async () => {
    const out = await fresh(-5);
    expect(out.status).toBe('imprecise');
    if (out.status === 'imprecise') expect(out.bestAccuracyMeters).toBeNull();
  });
  it('accuracy missing → fail closed → imprecise', async () => {
    const out = await acquireLocation({
      core,
      now: () => NOW,
      maxAgeSeconds: 10,
      qualityWindowMs: 40,
      geolocation: stagedGeo(posNoAccuracy(NOW - 3000)),
    });
    expect(out.status).toBe('imprecise');
    if (out.status === 'imprecise') expect(out.bestAccuracyMeters).toBeNull();
  });

  it('freshness is still required alongside accuracy — a perfectly accurate but stale fix is stale', async () => {
    const out = await acquireLocation({
      core,
      now: () => NOW,
      maxAgeSeconds: 10,
      qualityWindowMs: 40,
      geolocation: stagedGeo(pos(NOW - 60_000, 5)),
    });
    expect(out.status).toBe('stale');
  });
  it('an accurate but >2 s future fix is future (timestamp normalization wins first)', async () => {
    const out = await acquireLocation({
      core,
      now: () => NOW,
      maxAgeSeconds: 10,
      qualityWindowMs: 40,
      geolocation: stagedGeo(pos(NOW + 2001, 5)),
    });
    expect(out.status).toBe('future');
  });
});

// staged best-fix acquisition.
describe('staged better-fix acquisition ', () => {
  const run = (geolocation: Geolocation) =>
    acquireLocation({ core, now: () => NOW, maxAgeSeconds: 10, qualityWindowMs: 120, geolocation });

  it('A: Phase A 900 m (imprecise) then a 45 m watch sample → accepted with the 45 m fix', async () => {
    const out = await run(stagedGeo(pos(NOW - 3000, 900), [pos(NOW - 2000, 45)]));
    expect(out.status).toBe('ok');
    if (out.status === 'ok') expect(out.fix.accuracyMeters).toBe(45);
  });

  it('B: 800 → 400 → 250, none ≤ 200 by the deadline → imprecise, best 250 m', async () => {
    const out = await run(stagedGeo(pos(NOW - 3000, 800), [pos(NOW - 2500, 400), pos(NOW - 2000, 250)]));
    expect(out.status).toBe('imprecise');
    if (out.status === 'imprecise') expect(out.bestAccuracyMeters).toBe(250);
  });

  it('C: an 80 m first fix is accepted immediately (no Phase B)', async () => {
    const out = await run(stagedGeo(pos(NOW - 3000, 80), [pos(NOW - 2000, 5)]));
    expect(out.status).toBe('ok');
    if (out.status === 'ok') expect(out.fix.accuracyMeters).toBe(80);
  });

  it('D: a 60 m fix followed by a poorer 600 m sample → keeps the 60 m fix, never regresses', async () => {
    const out = await run(stagedGeo(pos(NOW - 3000, 300), [pos(NOW - 2500, 60), pos(NOW - 2000, 600)]));
    expect(out.status).toBe('ok');
    if (out.status === 'ok') expect(out.fix.accuracyMeters).toBe(60);
  });

  it('E: an accurate but stale fix is rejected through shared freshness', async () => {
    const out = await run(stagedGeo(pos(NOW - 60_000, 30)));
    expect(out.status).toBe('stale');
  });

  it('F: an accurate but >2 s future fix is rejected by timestamp normalization', async () => {
    const out = await run(stagedGeo(pos(NOW + 5000, 30)));
    expect(out.status).toBe('future');
  });
});

// TIMEOUT RECOVERY. A Phase-A getCurrentPosition timeout no
// longer surfaces immediately; the SAME bounded watch stage runs (no seed).
describe('timeout recovery ', () => {
  const TIMEOUT_ERR = { code: ERR.TIMEOUT, message: 't', ...ERR } as GeolocationPositionError;
  const run = (geolocation: Geolocation) =>
    acquireLocation({ core, now: () => NOW, maxAgeSeconds: 10, qualityWindowMs: 120, geolocation });

  it('T1: Phase-A timeout, then a fresh 20 m watch sample → OK (no timeout surfaced)', async () => {
    const out = await run(stagedGeo(TIMEOUT_ERR, [pos(NOW - 2000, 20)]));
    expect(out.status).toBe('ok');
    if (out.status === 'ok') expect(out.fix.accuracyMeters).toBe(20);
  });

  it('T2: Phase-A timeout, watch 500 → 250 → 45 → OK with the 45 m fix', async () => {
    const out = await run(stagedGeo(TIMEOUT_ERR, [pos(NOW - 2600, 500), pos(NOW - 2300, 250), pos(NOW - 2000, 45)]));
    expect(out.status).toBe('ok');
    if (out.status === 'ok') expect(out.fix.accuracyMeters).toBe(45);
  });

  it('T3: Phase-A timeout, watch 500 → 260, window expires → IMPRECISE, best 260 m', async () => {
    const out = await run(stagedGeo(TIMEOUT_ERR, [pos(NOW - 2500, 500), pos(NOW - 2000, 260)]));
    expect(out.status).toBe('imprecise');
    if (out.status === 'imprecise') expect(out.bestAccuracyMeters).toBe(260);
  });

  it('T4: Phase-A timeout, watch receives no position → TIMEOUT', async () => {
    const out = await run(stagedGeo(TIMEOUT_ERR, []));
    expect(out.status).toBe('timeout');
  });

  it('T5: Phase-A timeout, watch only gives invalid/missing accuracy → IMPRECISE, null accuracy', async () => {
    const out = await run(stagedGeo(TIMEOUT_ERR, [posNoAccuracy(NOW - 2000), pos(NOW - 1500, NaN)]));
    expect(out.status).toBe('imprecise');
    if (out.status === 'imprecise') expect(out.bestAccuracyMeters).toBeNull();
  });

  it('T6: Phase-A timeout, watch precise but STALE → not OK (timeout, never a stale GO input)', async () => {
    const out = await run(stagedGeo(TIMEOUT_ERR, [pos(NOW - 60_000, 10), pos(NOW - 90_000, 8)]));
    expect(out.status).toBe('timeout');
  });

  it('T7: Phase-A timeout, watch precise but >2 s FUTURE → future (honest clock behaviour, never accepted)', async () => {
    const out = await run(stagedGeo(TIMEOUT_ERR, [pos(NOW + 5000, 10), pos(NOW + 8000, 12)]));
    expect(out.status).toBe('future');
  });

  it('T8: PERMISSION_DENIED never enters the recovery watch', async () => {
    const g = stagedGeo({ code: ERR.PERMISSION_DENIED, message: 'no', ...ERR } as GeolocationPositionError, [pos(NOW - 2000, 10)]);
    const out = await run(g);
    expect(out.status).toBe('denied');
    expect(g.calls.watchStarts).toBe(0);
  });

  it('T9: a good Phase-A 25 m fix → watchPosition is never called', async () => {
    const g = stagedGeo(pos(NOW - 3000, 25), [pos(NOW - 2000, 5)]);
    const out = await run(g);
    expect(out.status).toBe('ok');
    expect(g.calls.watchStarts).toBe(0);
  });

  it('T10: a fresh Phase-A 600 m fix still runs the quality chase (imprecise seed path)', async () => {
    const g = stagedGeo(pos(NOW - 3000, 600), [pos(NOW - 2000, 40)]);
    const out = await run(g);
    expect(out.status).toBe('ok');
    if (out.status === 'ok') expect(out.fix.accuracyMeters).toBe(40);
    expect(g.calls.watchStarts).toBe(1);
  });
});

// the bounded watch stage always tears itself down.
describe('watch cleanup ', () => {
  const TIMEOUT_ERR = { code: ERR.TIMEOUT, message: 't', ...ERR } as GeolocationPositionError;

  it('clearWatch is called after an early good fix, and there is no leaked watch', async () => {
    const g = stagedGeo(TIMEOUT_ERR, [pos(NOW - 2000, 15)]);
    const out = await acquireLocation({ core, now: () => NOW, qualityWindowMs: 200, geolocation: g });
    expect(out.status).toBe('ok');
    expect(g.calls.watchStarts).toBe(1);
    expect(g.calls.clearWatch).toBeGreaterThanOrEqual(1);
    expect(g.calls.liveWatches()).toBe(0);
  });

  it('clearWatch is called after the deadline when no fix arrives', async () => {
    const g = stagedGeo(TIMEOUT_ERR, []);
    const out = await acquireLocation({ core, now: () => NOW, qualityWindowMs: 40, geolocation: g });
    expect(out.status).toBe('timeout');
    expect(g.calls.clearWatch).toBeGreaterThanOrEqual(1);
    expect(g.calls.liveWatches()).toBe(0);
  });

  it('resolves exactly once even though samples keep arriving after the good fix', async () => {
    const g = stagedGeo(TIMEOUT_ERR, [pos(NOW - 2000, 15), pos(NOW - 1900, 12), pos(NOW - 1800, 10)]);
    let resolutions = 0;
    const p = acquireLocation({ core, now: () => NOW, qualityWindowMs: 120, geolocation: g }).then((r) => {
      resolutions++;
      return r;
    });
    const out = await p;
    await new Promise((r) => setTimeout(r, 60)); // let the extra samples land
    expect(out.status).toBe('ok');
    expect(resolutions).toBe(1);
    expect(g.calls.liveWatches()).toBe(0);
  });

  it('the quality-chase path also clears its watch', async () => {
    const g = stagedGeo(pos(NOW - 3000, 700), [pos(NOW - 2000, 30)]);
    await acquireLocation({ core, now: () => NOW, qualityWindowMs: 120, geolocation: g });
    expect(g.calls.clearWatch).toBeGreaterThanOrEqual(1);
    expect(g.calls.liveWatches()).toBe(0);
  });
});
