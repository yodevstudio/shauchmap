// gender-conflict tests G1–G5.
//
// The gender note Instant shows MUST come from the shared Dart Truth V2 parser /
// legacy adapter — never from the raw Firestore `gender_type` field. These cases
// drive real conflicting documents through the ACTUAL compiled shared core
// (`core.evaluateTruth`) and assert both the core's `gender` enum and the label
// `genderDescriptorFromTruth` derives from it.
import { describe, it, expect, beforeAll } from 'vitest';
import { loadCore, type ShauchmapCore } from '../src/core/interop';
import type { ToiletMapJson } from '../src/core/types';
import { genderDescriptorFromTruth, locationDescriptorFor } from '../src/ui/present';

let core: ShauchmapCore;
beforeAll(async () => {
  core = await loadCore();
});

/** A STRUCTURALLY VALID native `truth_v2` block (exact key set, 7 amenity keys,
 *  version 2, real recorded_at Instant). Only `gender` varies per case. */
function nativeTruthV2(gender: 'unknown' | 'unisex' | 'men' | 'women'): ToiletMapJson {
  return {
    version: 2,
    source_type: 'community_submission',
    recorded_at: { __ts__: Date.now() - 60_000 },
    fee: 'unknown',
    context: 'unknown',
    gender,
    amenities: {
      water: 'unknown',
      soap: 'unknown',
      lock: 'unknown',
      western: 'unknown',
      wheelchair: 'unknown',
      baby_change: 'unknown',
      sanitary_disposal: 'unknown',
    },
  };
}

const truthOf = (doc: ToiletMapJson) => core.evaluateTruth(doc);

describe('gender truth-boundary — display gender comes from the shared core, not raw gender_type', () => {
  it('G1: raw gender_type=female + valid native truth_v2.gender=unknown → core=unknown → NO "Women only"', () => {
    const t = truthOf({
      name: 'Public Toilet',
      added_by: 'community_user_x',
      gender_type: 'female',
      truth_v2: nativeTruthV2('unknown'),
    });
    expect(t.gender).toBe('unknown');
    expect(genderDescriptorFromTruth(t)).toBeNull();
  });

  it('G2: raw gender_type=unisex + valid native truth_v2.gender=women → core=women → "Women only"', () => {
    const t = truthOf({
      name: 'Public Toilet',
      added_by: 'community_user_x',
      gender_type: 'unisex',
      truth_v2: nativeTruthV2('women'),
    });
    expect(t.gender).toBe('women');
    expect(genderDescriptorFromTruth(t)).toBe('Women only');
  });

  it('G3: legacy OSM, raw gender_type=female, no valid native truth_v2 → OSM adapter → women → "Women only"', () => {
    const t = truthOf({
      name: 'PUBLIC TOILET',
      added_by: 'osm_india_import_2026',
      gender_type: 'female',
    });
    expect(t.isNativeV2).toBe(false);
    expect(t.gender).toBe('women');
    expect(genderDescriptorFromTruth(t)).toBe('Women only');
  });

  it('G4: legacy raw gender_type=unisex → legacy adapter → unknown → NO "Unisex"', () => {
    const osm = truthOf({ name: 'x', added_by: 'osm_india_import_2026', gender_type: 'unisex' });
    expect(osm.gender).toBe('unknown');
    expect(genderDescriptorFromTruth(osm)).toBeNull();

    const community = truthOf({ name: 'x', added_by: 'community_user_x', gender_type: 'unisex' });
    expect(community.gender).toBe('unknown');
    expect(genderDescriptorFromTruth(community)).toBeNull();
  });

  it('G5: native truth_v2.gender=unisex → core=unisex → "Unisex" (frozen core presentation permits the label)', () => {
    const t = truthOf({
      name: 'Public Toilet',
      added_by: 'community_user_x',
      gender_type: 'female', // raw disagrees; native wins
      truth_v2: nativeTruthV2('unisex'),
    });
    expect(t.gender).toBe('unisex');
    expect(genderDescriptorFromTruth(t)).toBe('Unisex');
  });

  it('the location descriptor never smuggles gender back in', () => {
    expect(
      locationDescriptorFor({ gender_type: 'female', landmark: 'Behind Nehru Park' }),
    ).toBe('Behind Nehru Park');
    expect(locationDescriptorFor({ gender_type: 'female' })).toBeNull();
  });
});
