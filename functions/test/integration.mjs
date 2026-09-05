// Evidence V2 — Firestore + Functions EMULATOR integration test.
//
// Run:  npm run build
//       firebase emulators:exec --only firestore,functions --project demo-shauchmap "node test/integration.mjs"
//
// Proves the trigger pipeline end to end: a raw sub-collection write causes the
// trusted server to recompute and write `toilets/{id}.evidence_v2`, without a
// client ever being able to write that field, and without `truth_v2` / identity
// being touched.

import {
  initializeTestEnvironment,
  assertFails,
} from "@firebase/rules-unit-testing";
import {
  doc,
  getDoc,
  setDoc,
  updateDoc,
  deleteDoc,
  addDoc,
  collection,
  serverTimestamp,
  GeoPoint,
} from "firebase/firestore";
import { readFileSync } from "node:fs";
import { fileURLToPath } from "node:url";

const PROJECT = "demo-shauchmap";
const RULES = readFileSync(
  fileURLToPath(new URL("../../firestore.rules", import.meta.url)),
  "utf8",
);

let pass = 0;
let fail = 0;
const log = [];
function ok(name) {
  pass++;
  log.push(`  ok  ${name}`);
}
function bad(name, err) {
  fail++;
  log.push(` FAIL ${name}  -- ${String(err).split("\n")[0]}`);
}

const sleep = (ms) => new Promise((r) => setTimeout(r, ms));

/** Poll a toilet doc until `predicate(evidence_v2)` is true, or time out. */
async function waitFor(db, tid, predicate, label, timeoutMs = 20000) {
  const start = Date.now();
  let last;
  while (Date.now() - start < timeoutMs) {
    const snap = await getDoc(doc(db, `toilets/${tid}`));
    const data = snap.data() || {};
    last = data.evidence_v2;
    try {
      if (predicate(data.evidence_v2, data)) return last;
    } catch {
      /* keep polling */
    }
    await sleep(400);
  }
  throw new Error(`timeout waiting for ${label}; last evidence_v2=${JSON.stringify(last)}`);
}

const env = await initializeTestEnvironment({
  projectId: PROJECT,
  firestore: {
    rules: RULES,
    host: "127.0.0.1",
    port: Number(process.env.FIRESTORE_EMULATOR_HOST?.split(":")[1] || 8080),
  },
});

const GP = new GeoPoint(26.3, 73.1);
const seededTruth = {
  version: 2,
  source_type: "community_submission",
  recorded_at: new Date(),
  fee: "unknown",
  context: "unknown",
  gender: "unknown",
  amenities: {
    water: "unknown",
    soap: "unknown",
    lock: "unknown",
    western: "unknown",
    wheelchair: "unknown",
    baby_change: "unknown",
    sanitary_disposal: "unknown",
  },
};

await env.withSecurityRulesDisabled(async (ctx) => {
  const db = ctx.firestore();
  for (const tid of ["tR", "tC", "tV", "tW", "tX"]) {
    await setDoc(doc(db, `toilets/${tid}`), {
      name: `Seed ${tid}`,
      latitude: 26.3,
      longitude: 73.1,
      position: { geopoint: GP, geohash: "ttabc" },
      added_by: "seed",
      truth_v2: seededTruth,
    });
  }
});

const A = env.authenticatedContext("alice").firestore();
const B = env.authenticatedContext("bob").firestore();

// 1. rating create -> evidence_v2.ratings
try {
  await setDoc(doc(A, "toilets/tR/ratings/alice"), {
    stars: 4,
    tags: [],
    note: "",
    timestamp: serverTimestamp(),
  });
  const ev = await waitFor(
    A,
    "tR",
    (e) => e?.ratings?.count === 1 && e.ratings.average === 4,
    "ratings count=1 avg=4",
  );
  if (ev.version === 1 && ev.ratings.computed_at && ev.ratings.last_event_at) {
    ok("rating create -> evidence_v2.ratings {count:1, average:4}");
  } else bad("rating create shape", JSON.stringify(ev.ratings));
} catch (e) {
  bad("rating create -> evidence_v2.ratings", e);
}

// 2. rating edit -> recomputed from authoritative docs (still one doc)
try {
  await setDoc(doc(A, "toilets/tR/ratings/alice"), {
    stars: 2,
    tags: [],
    note: "",
    timestamp: serverTimestamp(),
  });
  await waitFor(
    A,
    "tR",
    (e) => e?.ratings?.count === 1 && e.ratings.average === 2,
    "ratings recomputed avg=2",
  );
  ok("rating edit -> aggregate recomputed (count still 1, average 2)");
} catch (e) {
  bad("rating edit -> recomputed", e);
}

// 2b. truth_v2 untouched by the ratings trigger
try {
  const snap = await getDoc(doc(A, "toilets/tR"));
  const t = snap.data().truth_v2;
  if (t && t.version === 2 && t.context === "unknown" && t.fee === "unknown") {
    ok("ratings trigger did NOT alter truth_v2 / identity");
  } else bad("truth_v2 mutated", JSON.stringify(t));
} catch (e) {
  bad("truth_v2 untouched check", e);
}

// 3. condition create -> evidence_v2.condition + valid_until
try {
  await setDoc(doc(A, "toilets/tC/condition_checks/alice"), {
    open: "yes",
    water: "unknown",
    usable: "yes",
    timestamp: serverTimestamp(),
  });
  const ev = await waitFor(
    A,
    "tC",
    (e) =>
      e?.condition?.open === "yes" &&
      e.condition.usable === "yes" &&
      e.condition.contributor_count === 1,
    "condition open=yes contributor_count=1",
  );
  const sup = ev.condition.support;
  const sumsOk =
    sup &&
    ["open", "water", "usable", "lock"].every(
      (d) => sup[d].yes + sup[d].no + sup[d].unknown === 1,
    ) &&
    sup.open.yes === 1 &&
    sup.usable.yes === 1 &&
    sup.water.unknown === 1 &&
    sup.lock.unknown === 1;
  if (ev.condition.valid_until && ev.condition.latest_at && sumsOk) {
    ok("condition create -> verdicts + support counts (yes+no+unknown == contributor_count)");
  } else bad("condition support/valid_until shape", JSON.stringify(ev.condition));
} catch (e) {
  bad("condition create -> evidence_v2.condition", e);
}

// 4. second distinct account -> tie -> unknown, contributor_count=2, support ok
try {
  await setDoc(doc(B, "toilets/tC/condition_checks/bob"), {
    open: "no",
    water: "unknown",
    usable: "unknown",
    timestamp: serverTimestamp(),
  });
  const ev = await waitFor(
    A,
    "tC",
    (e) => e?.condition?.open === "unknown" && e.condition.contributor_count === 2,
    "condition tie -> unknown, contributor_count=2",
  );
  const s = ev.condition.support;
  const sumsOk = ["open", "water", "usable", "lock"].every(
    (d) => s[d].yes + s[d].no + s[d].unknown === 2,
  );
  if (s.open.yes === 1 && s.open.no === 1 && sumsOk) {
    ok("second account -> majority recomputed (tie -> unknown), support open {1,1,0}, sums == 2");
  } else bad("second-account support shape", JSON.stringify(s));
} catch (e) {
  bad("second account -> majority recomputed", e);
}

// 5. vote create / update / delete — NO artificial sleeps.
// `shouldApplyEvent` now RE-APPLIES on an equal millisecond watermark, so
// rapid successive writes on the same doc converge to the authoritative state
// even when the emulator gives them the same ~1s-resolution `event.time`. Every
// execution recomputes from the current `votes` collection, never a delta.
try {
  await setDoc(doc(A, "toilets/tV/votes/alice"), {
    is_upvote: true,
    timestamp: serverTimestamp(),
  });
  await waitFor(A, "tV", (e) => e?.votes?.up === 1 && e.votes.down === 0, "vote up=1");
  await setDoc(doc(A, "toilets/tV/votes/alice"), {
    is_upvote: false,
    timestamp: serverTimestamp(),
  });
  await waitFor(A, "tV", (e) => e?.votes?.up === 0 && e.votes.down === 1, "vote flipped down=1");
  await deleteDoc(doc(A, "toilets/tV/votes/alice"));
  await waitFor(A, "tV", (e) => e?.votes?.up === 0 && e.votes.down === 0, "vote removed -> 0/0");
  ok("vote create/update/delete (no sleeps) -> 0/0, authoritative (not 50%)");
} catch (e) {
  bad("vote create/update/delete", e);
}

// 6. client CANNOT update an existing toilet's evidence_v2
try {
  await assertFails(
    updateDoc(doc(A, "toilets/tW"), {
      evidence_v2: { version: 1, ratings: { count: 999, average: 5 } },
    }),
  );
  ok("client update of toilets/{id}.evidence_v2 is DENIED (allow update: if false)");
} catch (e) {
  bad("client cannot update evidence_v2", e);
}

// 7. NO client can create a toilet at all — with or without a fabricated
//    evidence_v2. (`/toilets` `allow create: if false` in the current server
//    policy; a future native-V2 create contract is preserved in this repo's
//    rules file history for once a minimum-supported-client-version policy
//    exists.)
try {
  const good = {
    name: "New Public Toilet",
    latitude: 26.3,
    longitude: 73.1,
    position: { geopoint: GP, geohash: "ttabc" },
    added_by: "alice",
    created_at: serverTimestamp(),
    truth_v2: { ...seededTruth, recorded_at: serverTimestamp() },
  };
  // Even a perfectly valid native Truth V2 client create is DENIED.
  await assertFails(addDoc(collection(A, "toilets"), good));
  // And so is one carrying a fabricated evidence_v2 map.
  await assertFails(
    addDoc(collection(A, "toilets"), {
      ...good,
      evidence_v2: { version: 1, ratings: { count: 1, average: 5 } },
    }),
  );
  ok("all client toilet creation DENIED (valid V2 + evidence_v2 injection)");
} catch (e) {
  bad("new-toilet create denied", e);
}

// 9. concurrency: rapid repeat write -> final count is authoritative, not doubled
try {
  await setDoc(doc(B, "toilets/tW/ratings/bob"), {
    stars: 5,
    tags: [],
    note: "",
    timestamp: serverTimestamp(),
  });
  await setDoc(doc(B, "toilets/tW/ratings/bob"), {
    stars: 3,
    tags: [],
    note: "",
    timestamp: serverTimestamp(),
  });
  await waitFor(
    A,
    "tW",
    (e) => e?.ratings?.count === 1 && e.ratings.average === 3,
    "rapid rewrite -> count 1 (authoritative, not delta-doubled)",
  );
  ok("rapid re-write -> recompute stays authoritative (count 1, not 2)");
} catch (e) {
  bad("concurrency: authoritative recompute", e);
}

// 10. CROSS-SECTION: near-simultaneous rating + vote + condition on ONE toilet.
// The final parent must carry ALL THREE evidence sections with correct values,
// no sibling lost, and truth_v2 byte/field-equivalent (field-path writes).
try {
  const truthBefore = JSON.stringify(
    (await getDoc(doc(A, "toilets/tX"))).data().truth_v2,
  );
  await Promise.all([
    setDoc(doc(A, "toilets/tX/ratings/alice"), {
      stars: 5,
      tags: [],
      note: "",
      timestamp: serverTimestamp(),
    }),
    setDoc(doc(A, "toilets/tX/votes/alice"), {
      is_upvote: true,
      timestamp: serverTimestamp(),
    }),
    setDoc(doc(A, "toilets/tX/condition_checks/alice"), {
      open: "yes",
      water: "unknown",
      usable: "yes",
      timestamp: serverTimestamp(),
    }),
  ]);
  const ev = await waitFor(
    A,
    "tX",
    (e) =>
      e?.version === 1 &&
      e.ratings?.count === 1 &&
      e.ratings.average === 5 &&
      e.votes?.up === 1 &&
      e.votes.down === 0 &&
      e.condition?.open === "yes" &&
      e.condition.usable === "yes" &&
      e.condition.contributor_count === 1,
    "all three evidence_v2 sections present + correct",
    30000,
  );
  const truthAfter = JSON.stringify(
    (await getDoc(doc(A, "toilets/tX"))).data().truth_v2,
  );
  if (
    ev.ratings.last_event_at &&
    ev.votes.last_event_at &&
    ev.condition.last_event_at &&
    truthAfter === truthBefore
  ) {
    ok("cross-section: ratings + votes + condition all present, no sibling lost, truth_v2 unchanged");
  } else {
    bad("cross-section shape / truth_v2 drift", truthAfter);
  }
} catch (e) {
  bad("cross-section near-simultaneous writes", e);
}

// 11. field-path write proves sibling safety: after all of the above, tX still
// has every section; a further single-section write must not drop the others.
try {
  await setDoc(doc(B, "toilets/tX/ratings/bob"), {
    stars: 3,
    tags: [],
    note: "",
    timestamp: serverTimestamp(),
  });
  const ev = await waitFor(
    A,
    "tX",
    (e) => e?.ratings?.count === 2 && e.votes?.up === 1 && e.condition?.open === "yes",
    "one more rating -> ratings updated, votes + condition intact",
  );
  ok(
    `single-section write preserves siblings (ratings.count=${ev.ratings.count}, votes.up=${ev.votes.up}, condition.open=${ev.condition.open})`,
  );
} catch (e) {
  bad("single-section write preserves siblings", e);
}

await env.cleanup();

console.log("\n================ EVIDENCE V2 EMULATOR INTEGRATION ================");
for (const l of log) console.log(l);
console.log("================================================================");
console.log(`TOTAL ${pass + fail}  |  PASS ${pass}  |  FAIL ${fail}`);
process.exit(fail === 0 ? 0 : 1);
