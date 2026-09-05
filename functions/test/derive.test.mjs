// PURE derivation tests for Evidence V2. No emulator, no network.
// Run: npm test  (builds TS first)  — or: node --test test/derive.test.mjs
import test from "node:test";
import assert from "node:assert/strict";

import {
  deriveRatings,
  deriveVotes,
  deriveCondition,
  parseConditionObs,
  computeValidUntil,
  shouldApplyEvent,
  CONDITION_WINDOW_MS,
} from "../lib/derive.js";

const MIN = 60 * 1000;

// ============================================================ RATINGS
test("ratings: empty -> count 0, average null (NOT zero)", () => {
  const r = deriveRatings([]);
  assert.equal(r.count, 0);
  assert.equal(r.average, null);
});

test("ratings: one valid", () => {
  assert.deepEqual(deriveRatings([{ stars: 4 }]), { count: 1, average: 4 });
});

test("ratings: multiple average correct", () => {
  const r = deriveRatings([{ stars: 5 }, { stars: 4 }, { stars: 3 }, { stars: 3 }]);
  assert.deepEqual(r, { count: 4, average: 3.75 });
});

test("ratings: an edit is still one doc (re-queried collection, not events)", () => {
  assert.deepEqual(deriveRatings([{ stars: 2 }, { stars: 5 }]), {
    count: 2,
    average: 3.5,
  });
});

test("ratings: a document without a VALID rating is NOT counted", () => {
  const r = deriveRatings([
    { stars: 4 },
    { stars: 0 }, // out of range
    { stars: 9 }, // out of range
    { stars: 3.5 }, // not an integer
    { stars: "5" }, // wrong type
    { stars: null },
    {}, // missing
  ]);
  assert.equal(r.count, 1); // ONLY the valid `4`
  assert.equal(r.average, 4);
});

test("ratings: all invalid -> count 0, average null", () => {
  const r = deriveRatings([{ stars: 0 }, { stars: "x" }, {}]);
  assert.deepEqual(r, { count: 0, average: null });
});

// ============================================================ VOTES
test("votes: zero -> {0,0}, never a 50%", () => {
  assert.deepEqual(deriveVotes([]), { up: 0, down: 0 });
});
test("votes: up only / down only / mixed", () => {
  assert.deepEqual(deriveVotes([{ isUpvote: true }, { isUpvote: true }]), { up: 2, down: 0 });
  assert.deepEqual(deriveVotes([{ isUpvote: false }]), { up: 0, down: 1 });
  assert.deepEqual(
    deriveVotes([{ isUpvote: true }, { isUpvote: false }, { isUpvote: true }]),
    { up: 2, down: 1 },
  );
});
test("votes: a value that is NOT exactly true/false increments NEITHER", () => {
  const r = deriveVotes([
    { isUpvote: "yes" },
    { isUpvote: null },
    { isUpvote: 1 },
    { isUpvote: undefined },
    {}, // missing
    { isUpvote: "true" },
  ]);
  assert.deepEqual(r, { up: 0, down: 0 });
});

// ============================================================ CONDITION
const NOW = 1_000_000_000_000;
const obs = (mins, o = {}) => ({
  open: "unknown",
  water: "unknown",
  usable: "unknown",
  lock: "unknown",
  timestampMs: NOW - mins * MIN,
  ...o,
});

test("condition: no observations -> all unknown, count 0, validUntil null", () => {
  const s = deriveCondition([], NOW);
  assert.equal(s.open, "unknown");
  assert.equal(s.contributorCount, 0);
  assert.equal(s.latestAtMs, null);
  assert.equal(s.validUntilMs, null);
  assert.deepEqual(s.support.open, { yes: 0, no: 0, unknown: 0 });
});

// -------- support counts --------
function assertSupportSums(s) {
  for (const dim of ["open", "water", "usable", "lock"]) {
    const d = s.support[dim];
    assert.equal(
      d.yes + d.no + d.unknown,
      s.contributorCount,
      `support.${dim} sum must equal contributor_count`,
    );
  }
}

test("support: [yes] => {yes:1,no:0,unknown:0}", () => {
  const s = deriveCondition([obs(5, { open: "yes" })], NOW);
  assert.deepEqual(s.support.open, { yes: 1, no: 0, unknown: 0 });
  assertSupportSums(s);
});

test("support: [yes, unknown] => {yes:1,no:0,unknown:1}, verdict yes", () => {
  const s = deriveCondition(
    [obs(5, { open: "yes" }), obs(6, { open: "unknown" })],
    NOW,
  );
  assert.deepEqual(s.support.open, { yes: 1, no: 0, unknown: 1 });
  assert.equal(s.open, "yes");
  assertSupportSums(s);
});

test("support: [yes,yes,no] => {yes:2,no:1,unknown:0}, verdict yes", () => {
  const s = deriveCondition(
    [obs(5, { open: "yes" }), obs(6, { open: "yes" }), obs(7, { open: "no" })],
    NOW,
  );
  assert.deepEqual(s.support.open, { yes: 2, no: 1, unknown: 0 });
  assert.equal(s.open, "yes");
  assertSupportSums(s);
});

test("support: [yes,no] tie => unknown verdict, support {yes:1,no:1,unknown:0}", () => {
  const s = deriveCondition(
    [obs(5, { open: "yes" }), obs(6, { open: "no" })],
    NOW,
  );
  assert.equal(s.open, "unknown");
  assert.deepEqual(s.support.open, { yes: 1, no: 1, unknown: 0 });
  assertSupportSums(s);
});

test("support: absent lock contributes to lock.unknown; sums hold", () => {
  const noLock = {
    open: "yes",
    water: "unknown",
    usable: "yes",
    timestampMs: NOW - 5 * MIN,
  };
  const s = deriveCondition([noLock, obs(6, { open: "yes", usable: "yes" })], NOW);
  assert.equal(s.contributorCount, 2);
  assert.deepEqual(s.support.lock, { yes: 0, no: 0, unknown: 2 });
  assert.deepEqual(s.support.usable, { yes: 2, no: 0, unknown: 0 });
  assertSupportSums(s);
});

test("support: a malformed observation is excluded from ALL support counts", () => {
  const s = deriveCondition(
    [obs(5, { open: "maybe" }), obs(6, { open: "yes", usable: "no" })],
    NOW,
  );
  assert.equal(s.contributorCount, 1);
  assert.deepEqual(s.support.open, { yes: 1, no: 0, unknown: 0 });
  assert.deepEqual(s.support.usable, { yes: 0, no: 1, unknown: 0 });
  assertSupportSums(s);
});

test("support: an expired (>60m) observation is excluded from support counts", () => {
  const s = deriveCondition(
    [obs(75, { open: "no" }), obs(10, { open: "yes" })],
    NOW,
  );
  assert.equal(s.contributorCount, 1);
  assert.deepEqual(s.support.open, { yes: 1, no: 0, unknown: 0 });
  assertSupportSums(s);
});

// -------- verdict <-> support consistency --------
// The client rejects any condition section whose declared verdict is not the
// one its own support counts imply. The server must therefore NEVER emit an
// inconsistent pair. `impliedVerdict` mirrors the client rule exactly.
function impliedVerdict(d) {
  if (d.yes > d.no) return "yes";
  if (d.no > d.yes) return "no";
  return "unknown";
}
function assertVerdictMatchesSupport(s) {
  for (const dim of ["open", "water", "usable", "lock"]) {
    assert.equal(
      s[dim],
      impliedVerdict(s.support[dim]),
      `${dim}: declared verdict must equal support-implied verdict`,
    );
  }
}

test("consistency: derived verdict always equals its support-implied verdict", () => {
  const cases = [
    [],
    [obs(5, { open: "yes" })],
    [obs(5, { open: "no" })],
    [obs(5, { open: "yes" }), obs(6, { open: "no" })], // tie -> unknown
    [obs(5, { open: "yes" }), obs(6, { open: "yes" }), obs(7, { open: "no" })],
    [obs(5, { open: "unknown" }), obs(6, { water: "no" }), obs(7, { usable: "yes" })],
  ];
  for (const c of cases) assertVerdictMatchesSupport(deriveCondition(c, NOW));
});

test("consistency: fuzz 400 random observation sets — verdict never contradicts support", () => {
  let seed = 20260902;
  const rnd = () => ((seed = (seed * 1103515245 + 12345) & 0x7fffffff) / 0x7fffffff);
  const tri = () => ["yes", "no", "unknown"][Math.floor(rnd() * 3)];
  for (let i = 0; i < 400; i++) {
    const n = Math.floor(rnd() * 6);
    const list = [];
    for (let k = 0; k < n; k++) {
      list.push(
        obs(Math.floor(rnd() * 80), {
          open: tri(),
          water: tri(),
          usable: tri(),
          lock: tri(),
        }),
      );
    }
    const s = deriveCondition(list, NOW);
    assertVerdictMatchesSupport(s);
    assertSupportSums(s);
  }
});

test("condition: single yes / single no", () => {
  assert.equal(deriveCondition([obs(5, { open: "yes" })], NOW).open, "yes");
  assert.equal(deriveCondition([obs(5, { open: "no" })], NOW).open, "no");
});

test("condition: tie -> unknown", () => {
  assert.equal(
    deriveCondition([obs(5, { open: "yes" }), obs(6, { open: "no" })], NOW).open,
    "unknown",
  );
});

test("condition: strict majority; unknown abstains", () => {
  assert.equal(
    deriveCondition(
      [obs(5, { open: "yes" }), obs(6, { open: "yes" }), obs(7, { open: "no" })],
      NOW,
    ).open,
    "yes",
  );
  assert.equal(
    deriveCondition(
      [obs(5, { open: "yes" }), obs(6, { open: "unknown" }), obs(7, { open: "unknown" })],
      NOW,
    ).open,
    "yes",
  );
});

test("condition: dimensions independent (incl. lock)", () => {
  const s = deriveCondition(
    [
      obs(5, { open: "yes", water: "no", usable: "unknown", lock: "no" }),
      obs(6, { open: "yes", water: "no", usable: "yes", lock: "no" }),
    ],
    NOW,
  );
  assert.equal(s.open, "yes");
  assert.equal(s.water, "no");
  assert.equal(s.usable, "yes");
  assert.equal(s.lock, "no");
});

test("condition: >60 min excluded; exactly 60m included; 60m+1ms excluded", () => {
  const at60 = { ...obs(0, { open: "no" }), timestampMs: NOW - CONDITION_WINDOW_MS };
  const past60 = { ...obs(0, { open: "yes" }), timestampMs: NOW - CONDITION_WINDOW_MS - 1 };
  const s = deriveCondition([at60, past60], NOW);
  assert.equal(s.open, "no");
  assert.equal(s.contributorCount, 1);
});

test("condition: future observation defensively excluded", () => {
  const future = { ...obs(0, { open: "yes" }), timestampMs: NOW + 5 * MIN };
  const s = deriveCondition([future, obs(5, { open: "no" })], NOW);
  assert.equal(s.open, "no");
  assert.equal(s.contributorCount, 1);
});

// -------- defensive document validation --------
test("condition: a malformed observation is DROPPED, not counted", () => {
  const s = deriveCondition(
    [obs(5, { open: "maybe" }), obs(6, { open: "yes" })],
    NOW,
  );
  assert.equal(s.open, "yes");
  assert.equal(s.contributorCount, 1); // the "maybe" doc did NOT contribute
});

test("condition: bad timestamp -> dropped", () => {
  const bad = { open: "yes", water: "yes", usable: "yes", lock: "yes", timestampMs: "soon" };
  const s = deriveCondition([bad, obs(5, { open: "no" })], NOW);
  assert.equal(s.open, "no");
  assert.equal(s.contributorCount, 1);
});

test("condition: missing required tri field -> dropped", () => {
  const bad = { open: "yes", usable: "yes", lock: "yes", timestampMs: NOW - 5 * MIN }; // no water
  const s = deriveCondition([bad, obs(5, { open: "no" })], NOW);
  assert.equal(s.contributorCount, 1);
  assert.equal(s.open, "no");
});

test("condition: bad lock value -> whole observation dropped", () => {
  const bad = obs(5, { open: "yes", lock: "jammed" });
  const s = deriveCondition([bad, obs(6, { open: "no" })], NOW);
  assert.equal(s.contributorCount, 1);
  assert.equal(s.open, "no");
});

test("condition: absent lock defaults to unknown, observation still valid", () => {
  const noLock = { open: "yes", water: "unknown", usable: "unknown", timestampMs: NOW - 5 * MIN };
  const s = deriveCondition([noLock], NOW);
  assert.equal(s.contributorCount, 1);
  assert.equal(s.open, "yes");
  assert.equal(s.lock, "unknown");
});

test("parseConditionObs: returns null / a validated object", () => {
  assert.equal(parseConditionObs({ open: "x", water: "yes", usable: "yes", timestampMs: 1 }), null);
  assert.equal(parseConditionObs({ open: "yes", water: "yes", usable: "yes", timestampMs: NaN }), null);
  const ok = parseConditionObs({ open: "yes", water: "no", usable: "unknown", timestampMs: 42 });
  assert.deepEqual(ok, { open: "yes", water: "no", usable: "unknown", lock: "unknown", timestampMs: 42 });
});

// -------- valid_until --------
test("validUntil: single = ts + 60m; multiple = EARLIEST expiry", () => {
  assert.equal(
    deriveCondition([obs(5, { open: "yes" })], NOW).validUntilMs,
    NOW - 5 * MIN + CONDITION_WINDOW_MS,
  );
  assert.equal(
    deriveCondition(
      [obs(5, { open: "yes" }), obs(20, { open: "yes" }), obs(50, { open: "no" })],
      NOW,
    ).validUntilMs,
    NOW - 50 * MIN + CONDITION_WINDOW_MS,
  );
  assert.equal(computeValidUntil([100, 200, 50], 10), 60);
  assert.equal(computeValidUntil([], 10), null);
});

test("SPEC E case — 11:01 yes, 11:02 yes, 11:59 no", () => {
  const T = 1_700_000_000_000;
  const w = CONDITION_WINDOW_MS;
  const list = [
    { open: "yes", water: "unknown", usable: "unknown", lock: "unknown", timestampMs: T + 1 * MIN },
    { open: "yes", water: "unknown", usable: "unknown", lock: "unknown", timestampMs: T + 2 * MIN },
    { open: "no", water: "unknown", usable: "unknown", lock: "unknown", timestampMs: T + 59 * MIN },
  ];
  const at1200 = deriveCondition(list, T + 60 * MIN, w);
  assert.equal(at1200.open, "yes");
  assert.equal(at1200.validUntilMs, T + 61 * MIN); // earliest expiry = 11:01 + 60m
  const afterExpiry = deriveCondition(list, at1200.validUntilMs + 1, w);
  assert.equal(afterExpiry.open, "unknown"); // 1 yes vs 1 no once 11:01 leaves
});

// ============================================================ CONCURRENCY
test("guard: no stored watermark -> apply", () => {
  assert.equal(shouldApplyEvent(null, 100), true);
  assert.equal(shouldApplyEvent(undefined, 100), true);
});
test("guard: strictly newer -> apply", () => {
  assert.equal(shouldApplyEvent(100, 101), true);
});
test("guard: strictly OLDER -> skip (out-of-order event cannot clobber)", () => {
  assert.equal(shouldApplyEvent(200, 100), false);
});
test("guard: EQUAL millisecond watermark -> APPLY (same-ms events not dropped)", () => {
  assert.equal(shouldApplyEvent(150, 150), true);
});
test("guard: non-finite incoming -> THROWS (no invented ordering)", () => {
  assert.throws(() => shouldApplyEvent(100, NaN));
  assert.throws(() => shouldApplyEvent(100, Number("nope")));
});
