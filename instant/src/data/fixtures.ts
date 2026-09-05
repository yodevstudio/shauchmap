// Deterministic, sanitized demo data .
//
// NOTHING here hardcodes a GO / Truth / Evidence outcome — each doc is a plain
// Firestore-shaped map. It flows through normalize -> the REAL shared core, and
// whatever the core says is what the UI shows. Timestamps are JS `Date`s on
// purpose, so the fixture path also exercises normalize.ts.
//
// Anchor: Ghanta Ghar (Clock Tower), Jodhpur. No real person or account.

export interface FixtureDoc {
  id: string;
  data: Record<string, unknown>;
}

export type FixtureWorldName =
  | 'default'
  | 'unknown'
  | 'confirm'
  | 'none'
  | 'empty'
  | 'longname'
  | 'genderconflict';

export const FIXTURE_USER = { lat: 26.2389, lng: 73.0243 };

const MIN = 60_000;

/**
 * A structurally-valid evidence_v2.condition block (the core parser is STRICT:
 * every dimension's support must sum to the SAME contributor_count, and each
 * verdict must equal the strict yes/no majority its counts imply).
 *
 * Pass `[yes, no]` per dimension; `unknown` is auto-filled to hit the count.
 */
function condition(
  now: number,
  opts: {
    ageMin: number;
    valid: boolean;
    contributors: number;
    open?: [number, number];
    water?: [number, number];
    usable?: [number, number];
    lock?: [number, number];
  },
) {
  const cc = opts.contributors;
  const dim = (s?: [number, number]) => {
    const [yes, no] = s ?? [0, 0];
    const unknown = cc - yes - no;
    if (unknown < 0) throw new Error('fixture condition: yes+no exceeds contributor count');
    const verdict = yes > no ? 'yes' : no > yes ? 'no' : 'unknown';
    return { verdict, support: { yes, no, unknown } };
  };
  const parts = {
    open: dim(opts.open),
    water: dim(opts.water),
    usable: dim(opts.usable),
    lock: dim(opts.lock),
  };
  return {
    open: parts.open.verdict,
    water: parts.water.verdict,
    usable: parts.usable.verdict,
    lock: parts.lock.verdict,
    contributor_count: cc,
    latest_at: new Date(now - opts.ageMin * MIN),
    valid_until: new Date(opts.valid ? now + (60 - opts.ageMin) * MIN : now - 5 * MIN),
    computed_at: new Date(now - Math.max(opts.ageMin - 1, 0) * MIN),
    last_event_at: new Date(now - opts.ageMin * MIN),
    support: {
      open: parts.open.support,
      water: parts.water.support,
      usable: parts.usable.support,
      lock: parts.lock.support,
    },
  };
}

/** Offset helper: metres north / east of the anchor -> lat/lng. */
function at(northM: number, eastM: number) {
  const dLat = northM / 111_320;
  const dLng = eastM / (111_320 * Math.cos((FIXTURE_USER.lat * Math.PI) / 180));
  return { latitude: FIXTURE_USER.lat + dLat, longitude: FIXTURE_USER.lng + dLng };
}

function osm(id: string, name: string, pos: { latitude: number; longitude: number }, extra: Record<string, unknown> = {}): FixtureDoc {
  return {
    id,
    data: {
      name,
      address: 'Ghanta Ghar area, Jodhpur',
      added_by: 'osm_india_import_2026',
      category: 'govt',
      gender_type: 'unisex',
      is_open: true,
      is_free: true,
      has_water: false,
      has_soap: false,
      has_lock: false,
      ...pos,
      ...extra,
    },
  };
}

export function fixtureWorld(name: FixtureWorldName, now: number = Date.now()): FixtureDoc[] {
  if (name === 'empty') return [];

  // T1 — nearest, source-mapped, corroborated-clear usable + open. Fresh.
  const t1 = osm('demo_ghantaghar', 'Ghanta Ghar Public Toilet', at(120, 70), {
    has_water: true,
    evidence_v2: {
      version: 1,
      condition: condition(now, {
        ageMin: 6,
        valid: true,
        contributors: 3,
        open: [3, 0],
        usable: [3, 0],
        water: [2, 0],
      }),
    },
  });

  // T2 — source-mapped, no condition evidence at all -> UNKNOWN condition.
  const t2 = osm('demo_sardar_market', 'Sardar Market Toilet', at(-210, 150));

  // T3 — source-mapped, ratings-only evidence. Ratings must NOT become a
  // condition authority.
  const t3 = osm('demo_sojati_gate', 'Sojati Gate Facility', at(300, -160), {
    evidence_v2: {
      version: 1,
      ratings: { available: true, count: 24, average: 3.8 },
    },
  });

  // T4 — source-mapped, CONFLICTED usable majority (2 yes / 2 no). Paid.
  const t4 = osm('demo_clock_pay', 'Clock Tower Pay Toilet', at(-330, -180), {
    is_free: false,
    evidence_v2: {
      version: 1,
      condition: condition(now, {
        ageMin: 12,
        valid: true,
        contributors: 5,
        usable: [2, 3],
        open: [4, 0],
      }),
    },
  });

  // T5 — NATIVE truth_v2 community submission, no corroboration.
  const t5: FixtureDoc = {
    id: 'demo_station_approach',
    data: {
      name: 'Station Approach Toilet (community)',
      address: 'Near Jodhpur Junction',
      added_by: 'user_demo_scout',
      ...at(150, 430),
      truth_v2: {
        version: 2,
        source_type: 'community_submission',
        recorded_at: new Date(now - 3 * 24 * 60 * MIN),
        fee: 'free',
        context: 'station',
        gender: 'unisex',
        amenities: {
          water: 'present',
          soap: 'unknown',
          lock: 'present',
          western: 'unknown',
          wheelchair: 'unknown',
          baby_change: 'unknown',
          sanitary_disposal: 'unknown',
        },
      },
    },
  };

  // T6 — INFERRED candidate (needs_confirm). Petrol station.
  const t6 = osm('demo_hp_pump', 'HP Petrol Pump Toilet', at(70, 40), {
    added_by: 'osm_india_import_2026',
    needs_confirm: true,
    category: 'petrol',
  });

  // T7 — moderation-flagged AND corroborated-unavailable.
  const t7 = osm('demo_old_bus_stand', 'Old Bus Stand Toilet', at(-90, 60), {
    is_flagged: true,
    flagged_until: new Date(now + 2 * 24 * 60 * MIN),
    evidence_v2: {
      version: 1,
      condition: condition(now, {
        ageMin: 8,
        valid: true,
        contributors: 3,
        usable: [0, 3],
        open: [1, 2],
      }),
    },
  });

 // Layout-stress world : hostile-length names / landmark / address, a
  // caution, and 3 long-named alternatives. Semantics unchanged — still real GO.
  const L1 = osm(
    'demo_long_selected',
    'Dr. Sampurnanand Government Community Public Convenience & Sanitation Facility (Block C, Ward 42)',
    at(-360, 190),
    {
      address: 'Near Old Collectorate Circle, Paota B Road, Mandore Region, Jodhpur, Rajasthan 342010',
      landmark: 'Opposite the Regional Transport Office, beside the long-distance state bus terminus gate 3',
      is_free: false,
      evidence_v2: {
        version: 1,
        condition: condition(now, {
          ageMin: 14,
          valid: true,
          contributors: 5,
          usable: [2, 3],
          open: [4, 0],
        }),
      },
    },
  );
  const L2 = osm(
    'demo_long_alt1',
    'Municipal Corporation Public Utility Block — Sardarpura Sub-Zone (Women & Accessible)',
    at(120, 70),
    { gender_type: 'female', is_wheelchair: true, landmark: 'Behind Nehru Park, near the water tank' },
  );
  const L3 = osm(
    'demo_long_alt2',
    'Sulabh International Sauchalaya Complex, Ratanada Aerodrome Approach Road',
    at(-500, -260),
    { address: 'Ratanada, Jodhpur, Rajasthan' },
  );
  const L4 = osm(
    'demo_long_alt3',
    'Community Convenience Point at the Mahamandir Temple Eastern Pilgrim Assembly Ground',
    at(640, -380),
  );

 // Gender truth-boundary world ( visual evidence). Two docs
  // whose RAW gender_type both say 'female' but whose shared-core Truth differs:
  //   GC1 — a VALID native truth_v2 with gender:'unknown' overrides the raw
  //         field → the card must NOT show "Women only".
  //   GC2 — legacy OSM, no native truth_v2 → the OSM adapter maps 'female' →
  //         women → the alternative legitimately shows "Women only".
  const gc1: FixtureDoc = {
    id: 'gc_native_unknown',
    data: {
      name: 'Paota Circle Public Toilet',
      address: 'Paota B Road, Jodhpur, Rajasthan',
      added_by: 'user_demo_scout',
      gender_type: 'female', // raw source tag — NOT authoritative
      ...at(120, 70),
      truth_v2: {
        version: 2,
        source_type: 'community_submission',
        recorded_at: new Date(now - 2 * 24 * 60 * MIN),
        fee: 'free',
        context: 'public_toilet',
        gender: 'unknown', // the authoritative Truth: gender access is NOT known
        amenities: {
          water: 'present',
          soap: 'unknown',
          lock: 'present',
          western: 'unknown',
          wheelchair: 'unknown',
          baby_change: 'unknown',
          sanitary_disposal: 'unknown',
        },
      },
      evidence_v2: {
        version: 1,
        condition: condition(now, {
          ageMin: 7,
          valid: true,
          contributors: 3,
          open: [3, 0],
          usable: [3, 0],
        }),
      },
    },
  };
  const gc2 = osm('gc_legacy_women', 'Nehru Park Ladies Facility', at(220, 110), {
    gender_type: 'female', // legacy OSM tag → adapter → women (authoritative here)
    evidence_v2: {
      version: 1,
      condition: condition(now, {
        ageMin: 10,
        valid: true,
        contributors: 3,
        open: [3, 0],
        usable: [3, 0],
      }),
    },
  });

  switch (name) {
    case 'default':
      return [t1, t2, t3, t4, t5, t6, t7];
    case 'genderconflict':
      return [gc1, gc2];
    case 'unknown':
      // Nearest eligible option has NO condition evidence -> UNKNOWN condition.
      return [t2, t3];
    case 'confirm':
      // Only a candidate + an unconfirmed community submission remain.
      return [t6, t5];
    case 'none':
      // Everything left is moderation-flagged -> no confident recommendation.
      return [t7];
    case 'longname':
      return [L2, L1, L3, L4]; // L2 nearest (selected); L1 the long-name focus target
  }
}

/** A single toilet by id (for /t/:id demo deep links). Falls back to a stub. */
export function fixtureToiletById(id: string, now: number = Date.now()): FixtureDoc | null {
  return fixtureWorld('default', now).find((d) => d.id === id) ?? null;
}
