import { describe, it, expect } from 'vitest';
import { readFileSync } from 'node:fs';
import { resolve } from 'node:path';
import {
  loadCore,
  wrapForTests,
  CoreVersionMismatchError,
  __resetInteropForTests,
} from '../src/core/interop';
import { CORE_INTEROP_VERSION, ts } from '../src/core/types';

const expected = JSON.parse(
  readFileSync(resolve(__dirname, '../../packages/shauchmap_core/oracle/expected.json'), 'utf8'),
);
const vectors = JSON.parse(
  readFileSync(resolve(__dirname, '../../packages/shauchmap_core/oracle/vectors.json'), 'utf8'),
);

describe('core interop wrapper', () => {
  it('loads the compiled brain and reports interop version 3', async () => {
    const core = await loadCore();
    expect(core.interopVersion).toBe(CORE_INTEROP_VERSION);
    expect(core.interopVersion).toBe(3);
    expect(core.buildVersion).toMatch(/shared-core/);
  });

  it('exposes exactly the six typed operations', async () => {
    const core = await loadCore();
    for (const fn of [
      'evaluateTruth',
      'evaluateEvidence',
      'evaluateGo',
      'evaluateRevalidation',
      'evaluatePositionFreshness',
      'evaluateDistances',
    ] as const) {
      expect(typeof core[fn]).toBe('function');
    }
  });

  it('matches the NATIVE oracle for a truth vector', async () => {
    const core = await loadCore();
    const v = vectors.truth[0];
    expect(core.evaluateTruth(v.map)).toEqual(expected.truth[0].out);
  });

  it('matches the NATIVE oracle for a GO vector (incl. presentation)', async () => {
    const core = await loadCore();
    const i = vectors.go.findIndex((g: { name: string }) => g.name.includes('recentCorroboratedUsableWithinDetour'));
    const v = vectors.go[i];
    const got = core.evaluateGo(v.pool, v.nowMs);
    expect(got).toEqual(expected.go[i].out);
    expect(got.presentation.headline.length).toBeGreaterThan(0);
  });

  it('matches the NATIVE oracle for the /t/:id hint vectors (H1..H8)', async () => {
    const core = await loadCore();
    vectors.hint.forEach((h: { name: string; pool: unknown[]; hintId: string; nowMs: number }, i: number) => {
      const got = core.evaluateGo(h.pool as never, h.nowMs, h.hintId);
      expect(got, h.name).toEqual(expected.hint[i].out);
    });
    // H1: hint == a non-selected active-tier alternative -> focus that alt.
    const h1 = core.evaluateGo(vectors.hint[0].pool as never, vectors.hint[0].nowMs, vectors.hint[0].hintId);
    expect(h1.focus?.id).toBe('mid');
    expect(h1.focus?.isSelected).toBe(false);
    expect(h1.selectedId).toBe('near'); // focus never gains selection authority
    // H2: hint == selected -> focus null.
    const h2 = core.evaluateGo(vectors.hint[1].pool as never, vectors.hint[1].nowMs, vectors.hint[1].hintId);
    expect(h2.focus).toBeNull();
    // no hintId -> no focus key at all.
    const noHint = core.evaluateGo(vectors.hint[0].pool as never, vectors.hint[0].nowMs);
    expect('focus' in noHint).toBe(false);
    // H8: focus presentation comes from presentGoAlternative, not the selected decision.
    const h8 = core.evaluateGo(vectors.hint[7].pool as never, vectors.hint[7].nowMs, vectors.hint[7].hintId);
    expect(h8.focus?.presentation.headline).not.toBe(h8.presentation.headline);
  });

  it('freshness + distance delegate to the core (no TS reimplementation)', async () => {
    const core = await loadCore();
    // age == maxAge exactly -> fresh (core rule uses <=)
    expect(
      core.evaluatePositionFreshness({ positionTsMs: 1000, nowMs: 11000, maxAgeSeconds: 10 }),
    ).toBe(true);
    expect(
      core.evaluatePositionFreshness({ positionTsMs: 999, nowMs: 11000, maxAgeSeconds: 10 }),
    ).toBe(false);
    const d = core.evaluateDistances({ from: { lat: 26.2389, lng: 73.0243 }, to: [{ id: 'same', lat: 26.2389, lng: 73.0243 }] });
    expect(d).toEqual([{ id: 'same', meters: 0 }]);
  });

  it('accepts the {"__ts__": ms} timestamp sentinel', async () => {
    const core = await loadCore();
    const e = core.evaluateEvidence(
      {
        version: 1,
        condition: {
          open: 'yes',
          water: 'unknown',
          usable: 'yes',
          lock: 'unknown',
          contributor_count: 3,
          latest_at: ts(1788393000000),
          valid_until: ts(1788396600000),
          computed_at: ts(1788393100000),
          last_event_at: ts(1788393000000),
          support: {
            open: { yes: 3, no: 0, unknown: 0 },
            water: { yes: 0, no: 0, unknown: 3 },
            usable: { yes: 3, no: 0, unknown: 0 },
            lock: { yes: 0, no: 0, unknown: 3 },
          },
        },
      },
      1788393600000,
    );
    expect(e.present).toBe(true);
    expect(e.condition.isCurrentlyValid).toBe(true);
  });

  it('throws CoreVersionMismatchError when the compiled brain disagrees', () => {
    __resetInteropForTests();
    const stale = {
      interopVersion: 1,
      version: 'stale',
      evaluateTruth: () => '{}',
      evaluateEvidence: () => '{}',
      evaluateGo: () => '{}',
      evaluateRevalidation: () => '{}',
      evaluatePositionFreshness: () => '{}',
      evaluateDistances: () => '{}',
    };
    expect(() => wrapForTests(stale)).toThrow(CoreVersionMismatchError);
  });
});
