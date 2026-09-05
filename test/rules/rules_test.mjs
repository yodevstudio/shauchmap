// ShauchMap Firestore rules — ALLOW/DENY matrix (2026-09-02 integrity pass).
// Run: firebase emulators:exec --only firestore --project demo-shauchmap "node rules_test.mjs"
//
// This harness reads the REPO-ROOT firestore.rules directly (../../firestore.rules)
// there is no local copy to drift. firebase.json also points the emulator at
// ../../firestore.rules, so the emulator and this SDK evaluate the identical file.
import fs from 'node:fs';
import { fileURLToPath } from 'node:url';
import {
  initializeTestEnvironment, assertSucceeds, assertFails,
} from '@firebase/rules-unit-testing';
import {
  doc, getDoc, setDoc, updateDoc, deleteDoc, collection, addDoc,
  getDocs, query, where, serverTimestamp, GeoPoint, Timestamp,
} from 'firebase/firestore';

const PROJECT = 'demo-shauchmap';

// GUARD: this SDK and the emulator (firebase.json -> ./firestore.rules, synced
// by sync-rules.mjs) must evaluate the IDENTICAL file. Hard-fail on any drift
// so no run can ever report a pass against a stale copy.
const ROOT_RULES = fileURLToPath(new URL('../../firestore.rules', import.meta.url));
const LOCAL_RULES = fileURLToPath(new URL('./firestore.rules', import.meta.url));
const RULES = fs.readFileSync(ROOT_RULES, 'utf8');
let localRules = null;
try { localRules = fs.readFileSync(LOCAL_RULES, 'utf8'); } catch { /* not synced yet */ }
if (localRules !== RULES) {
  console.error(
    'ABORT: test/rules/firestore.rules is NOT byte-identical to the '
    + 'repo-root firestore.rules. Run `node sync-rules.mjs` (npm test does this).');
  process.exit(1);
}
console.log(`rules source: ${ROOT_RULES} (${RULES.length} bytes) — local copy verified identical`);

const GP = new GeoPoint(26.3, 73.1);          // matches lat/lng below exactly
const POS = { geohash: 'ttabc', geopoint: GP };
const YESTERDAY = Timestamp.fromDate(new Date(Date.now() - 86400000));
const TOMORROW = Timestamp.fromDate(new Date(Date.now() + 86400000));
const FARFUTURE = Timestamp.fromDate(new Date('2099-01-01T00:00:00Z'));
const NOW_CLIENT = Timestamp.fromDate(new Date()); // manual "now" — still != request.time

let pass = 0, fail = 0;
const results = [];
async function check(name, kind, p) {
  try {
    await (kind === 'ALLOW' ? assertSucceeds(p) : assertFails(p));
    pass++; results.push(['PASS', kind, name]);
  } catch (e) {
    fail++; results.push(['FAIL', kind, name, String(e).split('\n')[0]]);
  }
}

const env = await initializeTestEnvironment({
  projectId: PROJECT,
  firestore: { rules: RULES, host: '127.0.0.1', port: 8080 },
});

await env.withSecurityRulesDisabled(async (ctx) => {
  const db = ctx.firestore();
  await setDoc(doc(db, 'toilets/t1'), {
    name: 'Seed', address: 'X', latitude: 26.2, longitude: 73.0,
    position: { geohash: 'ts', geopoint: new GeoPoint(26.2, 73.0) },
    added_by: 'osm_import', is_open: true, is_free: true, star_rating: 0, total_ratings: 0,
  });
  await setDoc(doc(db, 'toilets/t1/ratings/bob'), { stars: 2, tags: [], note: '', timestamp: new Date() });
  await setDoc(doc(db, 'toilets/t1/condition_checks/bob'), { open: 'yes', water: 'no', usable: 'yes', timestamp: new Date() });
  await setDoc(doc(db, 'toilets/t1/reports/bob'), { reason: 'Wrong location', created_at: new Date() });
  await setDoc(doc(db, 'toilets/t1/votes/bob'), { is_upvote: true, timestamp: new Date() });
  // alice check-ins for the 4h cooldown tests
  await setDoc(doc(db, 'toilets/t1/check_ins/alice'), { timestamp: Timestamp.fromDate(new Date(Date.now() - 60 * 60 * 1000)) }); // 1h ago
  await setDoc(doc(db, 'toilets/t2/check_ins/alice'), { timestamp: Timestamp.fromDate(new Date(Date.now() - 5 * 60 * 60 * 1000)) }); // 5h ago
  await setDoc(doc(db, 'users/bob'), { name: 'Bob', email: 'b@x.com', scout_points: 10 });
  await setDoc(doc(db, 'users/alice'), { name: 'Alice', email: 'a@x.com', scout_points: 0 });
  await setDoc(doc(db, 'public_profiles/bob'), { name: 'Bob', photo_url: null, scout_points: 10, updated_at: new Date() });
});

const anon = env.unauthenticatedContext().firestore();
const A = env.authenticatedContext('alice').firestore();

// ===================== ANONYMOUS =====================
await check('anon read toilet', 'ALLOW', getDoc(doc(anon, 'toilets/t1')));
await check('anon read ratings', 'ALLOW', getDocs(collection(anon, 'toilets/t1/ratings')));
await check('anon read condition_checks', 'ALLOW', getDocs(collection(anon, 'toilets/t1/condition_checks')));
await check('anon read public_profiles', 'ALLOW', getDocs(collection(anon, 'public_profiles')));
await check('anon read private users/bob', 'DENY', getDoc(doc(anon, 'users/bob')));
await check('anon read check_ins (owner-only)', 'DENY', getDocs(collection(anon, 'toilets/t1/check_ins')));
await check('anon read reports (owner-only)', 'DENY', getDocs(collection(anon, 'toilets/t1/reports')));
await check('anon create rating', 'DENY', setDoc(doc(anon, 'toilets/t1/ratings/x'), { stars: 5, timestamp: serverTimestamp() }));
await check('anon create condition_check', 'DENY', setDoc(doc(anon, 'toilets/t1/condition_checks/x'), { open: 'yes', water: 'yes', usable: 'yes', timestamp: serverTimestamp() }));
await check('anon create toilet', 'DENY', addDoc(collection(anon, 'toilets'), { name: 'x', latitude: 1, longitude: 1, position: POS, added_by: 'x', created_at: serverTimestamp() }));

// ===================== RATINGS — doc id == uid, server ts =====================
await check('A create rating at ratings/alice', 'ALLOW', setDoc(doc(A, 'toilets/t1/ratings/alice'), { stars: 3, tags: ['clean'], note: 'ok', timestamp: serverTimestamp() }));
await check('A edit own rating (overwrite)', 'ALLOW', setDoc(doc(A, 'toilets/t1/ratings/alice'), { stars: 4, tags: [], note: '', timestamp: serverTimestamp() }));
await check('A create rating at ratings/bob (id != uid)', 'DENY', setDoc(doc(A, 'toilets/t1/ratings/bob'), { stars: 5, timestamp: serverTimestamp() }));
await check('A create SECOND rating under random id', 'DENY', setDoc(doc(A, 'toilets/t1/ratings/alice_2'), { stars: 5, timestamp: serverTimestamp() }));
await check('A edit BOB rating', 'DENY', updateDoc(doc(A, 'toilets/t1/ratings/bob'), { stars: 1 }));
await check('A rating stars=0', 'DENY', setDoc(doc(A, 'toilets/t1/ratings/alice'), { stars: 0, timestamp: serverTimestamp() }));
await check('A rating stars=6', 'DENY', setDoc(doc(A, 'toilets/t1/ratings/alice'), { stars: 6, timestamp: serverTimestamp() }));
await check('A rating stars=3.5 float', 'DENY', setDoc(doc(A, 'toilets/t1/ratings/alice'), { stars: 3.5, timestamp: serverTimestamp() }));
await check('A rating with user_name extra field', 'DENY', setDoc(doc(A, 'toilets/t1/ratings/alice'), { stars: 3, user_name: 'Alice R', timestamp: serverTimestamp() }));
await check('A rating with user_id extra field', 'DENY', setDoc(doc(A, 'toilets/t1/ratings/alice'), { stars: 3, user_id: 'alice', timestamp: serverTimestamp() }));
await check('A rating ts = yesterday', 'DENY', setDoc(doc(A, 'toilets/t1/ratings/alice'), { stars: 3, timestamp: YESTERDAY }));
await check('A rating ts = tomorrow', 'DENY', setDoc(doc(A, 'toilets/t1/ratings/alice'), { stars: 3, timestamp: TOMORROW }));
await check('A rating ts = far future', 'DENY', setDoc(doc(A, 'toilets/t1/ratings/alice'), { stars: 3, timestamp: FARFUTURE }));
await check('A rating ts = manual client now', 'DENY', setDoc(doc(A, 'toilets/t1/ratings/alice'), { stars: 3, timestamp: NOW_CLIENT }));
await check('A delete own rating', 'DENY', deleteDoc(doc(A, 'toilets/t1/ratings/alice')));

// ===================== CONDITION CHECKS — doc id == uid =====================
await check('A create condition_checks/alice', 'ALLOW', setDoc(doc(A, 'toilets/t1/condition_checks/alice'), { open: 'yes', water: 'unknown', usable: 'no', timestamp: serverTimestamp() }));
await check('A overwrite own condition check (latest per account)', 'ALLOW', setDoc(doc(A, 'toilets/t1/condition_checks/alice'), { open: 'unknown', water: 'unknown', usable: 'unknown', lock: 'yes', timestamp: serverTimestamp() }));
await check('A condition_checks/bob (id != uid)', 'DENY', setDoc(doc(A, 'toilets/t1/condition_checks/bob'), { open: 'yes', water: 'yes', usable: 'yes', timestamp: serverTimestamp() }));
await check('A SECOND condition check under random id', 'DENY', setDoc(doc(A, 'toilets/t1/condition_checks/alice_x'), { open: 'yes', water: 'yes', usable: 'yes', timestamp: serverTimestamp() }));
await check('A condition_check with user_id field', 'DENY', setDoc(doc(A, 'toilets/t1/condition_checks/alice'), { user_id: 'alice', open: 'yes', water: 'yes', usable: 'yes', timestamp: serverTimestamp() }));
await check('A condition_check invalid tri-state', 'DENY', setDoc(doc(A, 'toilets/t1/condition_checks/alice'), { open: 'maybe', water: 'yes', usable: 'yes', timestamp: serverTimestamp() }));
await check('A condition_check women_safety_ok field', 'DENY', setDoc(doc(A, 'toilets/t1/condition_checks/alice'), { open: 'yes', water: 'yes', usable: 'yes', women_safety_ok: true, timestamp: serverTimestamp() }));
await check('A condition_check missing usable', 'DENY', setDoc(doc(A, 'toilets/t1/condition_checks/alice'), { open: 'yes', water: 'yes', timestamp: serverTimestamp() }));
await check('A condition_check ts = tomorrow', 'DENY', setDoc(doc(A, 'toilets/t1/condition_checks/alice'), { open: 'yes', water: 'yes', usable: 'yes', timestamp: TOMORROW }));
await check('A condition_check ts = yesterday', 'DENY', setDoc(doc(A, 'toilets/t1/condition_checks/alice'), { open: 'yes', water: 'yes', usable: 'yes', timestamp: YESTERDAY }));

// ===================== CHECK-INS — server 4h cooldown =====================
await check('A read own check_in', 'ALLOW', getDoc(doc(A, 'toilets/t1/check_ins/alice')));
await check('A read BOB check_in', 'DENY', getDoc(doc(A, 'toilets/t1/check_ins/bob')));
await check('A check_ins/bob create (id != uid)', 'DENY', setDoc(doc(A, 'toilets/t3/check_ins/bob'), { timestamp: serverTimestamp() }));
await check('A first check-in (t3, new doc)', 'ALLOW', setDoc(doc(A, 'toilets/t3/check_ins/alice'), { timestamp: serverTimestamp() }));
await check('A UPDATE check-in only 1h later (t1) -> cooldown DENY', 'DENY', setDoc(doc(A, 'toilets/t1/check_ins/alice'), { timestamp: serverTimestamp() }));
await check('A UPDATE check-in 5h later (t2) -> cooldown OK', 'ALLOW', setDoc(doc(A, 'toilets/t2/check_ins/alice'), { timestamp: serverTimestamp() }));
await check('A check-in ts = manual client now', 'DENY', setDoc(doc(A, 'toilets/t4/check_ins/alice'), { timestamp: NOW_CLIENT }));
await check('A check-in with extra field', 'DENY', setDoc(doc(A, 'toilets/t4/check_ins/alice'), { note: 'x', timestamp: serverTimestamp() }));
await check('A delete own check-in', 'DENY', deleteDoc(doc(A, 'toilets/t2/check_ins/alice')));

// ===================== REPORTS — doc id == uid =====================
await check('A create reports/alice', 'ALLOW', setDoc(doc(A, 'toilets/t1/reports/alice'), { reason: 'Closed permanently', created_at: serverTimestamp() }));
await check('A correct own report reason', 'ALLOW', setDoc(doc(A, 'toilets/t1/reports/alice'), { reason: 'Wrong location', created_at: serverTimestamp() }));
await check('A reports/bob (id != uid)', 'DENY', setDoc(doc(A, 'toilets/t1/reports/bob'), { reason: 'Inappropriate', created_at: serverTimestamp() }));
await check('A duplicate report under random id', 'DENY', setDoc(doc(A, 'toilets/t1/reports/alice_2'), { reason: 'Inappropriate', created_at: serverTimestamp() }));
await check('A report bad reason', 'DENY', setDoc(doc(A, 'toilets/t1/reports/alice'), { reason: 'lol', created_at: serverTimestamp() }));
await check('A report with reported_by field', 'DENY', setDoc(doc(A, 'toilets/t1/reports/alice'), { reason: 'Inappropriate', reported_by: 'alice', created_at: serverTimestamp() }));
await check('A report ts = far future', 'DENY', setDoc(doc(A, 'toilets/t1/reports/alice'), { reason: 'Inappropriate', created_at: FARFUTURE }));
await check('A read own report', 'ALLOW', getDoc(doc(A, 'toilets/t1/reports/alice')));
await check('A read BOB report', 'DENY', getDoc(doc(A, 'toilets/t1/reports/bob')));
await check('A enumerate reports', 'DENY', getDocs(collection(A, 'toilets/t1/reports')));

// ===================== VOTES =====================
await check('A create own vote', 'ALLOW', setDoc(doc(A, 'toilets/t1/votes/alice'), { is_upvote: true, timestamp: serverTimestamp() }));
await check('A update own vote', 'ALLOW', setDoc(doc(A, 'toilets/t1/votes/alice'), { is_upvote: false, timestamp: serverTimestamp() }));
await check('A delete own vote', 'ALLOW', deleteDoc(doc(A, 'toilets/t1/votes/alice')));
await check('A vote at BOB doc id', 'DENY', setDoc(doc(A, 'toilets/t1/votes/bob'), { is_upvote: true, timestamp: serverTimestamp() }));
await check('A vote is_upvote not bool', 'DENY', setDoc(doc(A, 'toilets/t1/votes/alice'), { is_upvote: 'yes', timestamp: serverTimestamp() }));
await check('A vote extra field', 'DENY', setDoc(doc(A, 'toilets/t1/votes/alice'), { is_upvote: true, weight: 9, timestamp: serverTimestamp() }));
await check('A vote ts = tomorrow', 'DENY', setDoc(doc(A, 'toilets/t1/votes/alice'), { is_upvote: true, timestamp: TOMORROW }));

// ============ TOILET — ALL client creation DENIED ============
// ShauchMap has a public GitHub Release that anyone may install, so the
// installed-client base is uncontrolled -> `/toilets` `allow create: if
// false` in the current server policy.
// EVERY client toilet-create payload — valid native Truth V2 included — is
// denied. The Dart `ADD_TOILET_ENABLED` flag is irrelevant server-side (the
// rule never inspects the client): a re-compiled client that sets it true and
// submits a perfect native-V2 payload is denied exactly the same.
//
// validToilet()/validTruthV2() below build what WOULD have satisfied a
// future create contract preserved in this repo's rules-file history; under
// the current rules they are all DENY.
const JLAT = 26.3, JLNG = 73.1;             // == GP
const AMEN_ALL_UNKNOWN = {
  water: 'unknown', soap: 'unknown', lock: 'unknown', western: 'unknown',
  wheelchair: 'unknown', baby_change: 'unknown', sanitary_disposal: 'unknown',
};
const validTruthV2 = (over = {}) => ({
  version: 2, source_type: 'community_submission', recorded_at: serverTimestamp(),
  fee: 'unknown', context: 'unknown', gender: 'unknown',
  amenities: { ...AMEN_ALL_UNKNOWN }, ...over,
});
const validToilet = () => ({
  name: 'New Public Toilet', address: 'Road', landmark: 'behind ATM',
  latitude: JLAT, longitude: JLNG, position: POS, added_by: 'alice',
  created_at: serverTimestamp(), truth_v2: validTruthV2(),
});

// ---- REQUIRED CURRENT-POLICY CASES (all DENY) ----
await check('CREATE DENIED: signed-in perfectly-valid native Truth V2 create', 'DENY', addDoc(collection(A, 'toilets'), validToilet()));
await check('CREATE DENIED: valid all-UNKNOWN native V2 create', 'DENY', addDoc(collection(A, 'toilets'), {
  ...validToilet(), truth_v2: validTruthV2(),
}));
await check('CREATE DENIED: valid native V2, mixed known/unknown amenities', 'DENY', addDoc(collection(A, 'toilets'), {
  ...validToilet(), truth_v2: validTruthV2({ amenities: { ...AMEN_ALL_UNKNOWN, water: 'present', soap: 'absent' } }),
}));
await check('CREATE DENIED: valid native V2 fee=free', 'DENY', addDoc(collection(A, 'toilets'), {
  ...validToilet(), truth_v2: validTruthV2({ fee: 'free' }),
}));
await check('CREATE DENIED: valid native V2 fee=paid, explicit context+gender', 'DENY', addDoc(collection(A, 'toilets'), {
  ...validToilet(), truth_v2: validTruthV2({ fee: 'paid', context: 'petrol_station', gender: 'women' }),
}));
await check('CREATE DENIED: signed-OUT create (valid-looking payload)', 'DENY', addDoc(collection(anon, 'toilets'), validToilet()));
await check('CREATE DENIED: modified-client create with valid V2 (added_by == uid)', 'DENY', addDoc(collection(A, 'toilets'), validToilet()));
await check('CREATE DENIED: ADD_TOILET_ENABLED=true-equivalent client payload', 'DENY', addDoc(collection(A, 'toilets'), validToilet()));
await check('CREATE DENIED: old legacy is_open/category create (no truth_v2)', 'DENY', addDoc(collection(A, 'toilets'), {
  name: 'Old Public Toilet', latitude: JLAT, longitude: JLNG, position: POS, added_by: 'alice',
  created_at: serverTimestamp(), is_open: true, is_free: true, category: 'government',
}));
await check('CREATE DENIED: malicious arbitrary create (admin/verified injected)', 'DENY', addDoc(collection(A, 'toilets'), {
  ...validToilet(), admin: true, verified: true, star_rating: 5,
}));
await check('CREATE DENIED: create at a different valid location', 'DENY', addDoc(collection(A, 'toilets'), {
  ...validToilet(), latitude: 19.076, longitude: 72.8777,
  position: { geohash: 'te7dd', geopoint: new GeoPoint(19.076, 72.8777) },
}));
// ---- FUTURE CREATE-CONTRACT REGRESSION CASES ----
// Every case below is ALSO denied today simply by `allow create: if false`.
// They are retained ONLY so that, when a native Truth V2 create contract is
// eventually re-enabled, the per-field enum / shape / geo checks can be
// re-pointed to ALLOW/DENY without re-deriving them. They do NOT indicate
// any validation is active in the current rules.
await check('A v2 context bad enum "nightclub"', 'DENY', addDoc(collection(A, 'toilets'), {
  ...validToilet(), truth_v2: validTruthV2({ context: 'nightclub' }),
}));
await check('A v2 gender bad enum "robot"', 'DENY', addDoc(collection(A, 'toilets'), {
  ...validToilet(), truth_v2: validTruthV2({ gender: 'robot' }),
}));
await check('A v2 context missing', 'DENY', addDoc(collection(A, 'toilets'), {
  ...validToilet(), truth_v2: { version: 2, source_type: 'community_submission', recorded_at: serverTimestamp(), fee: 'unknown', gender: 'unknown', amenities: { ...AMEN_ALL_UNKNOWN } },
}));
await check('A v2 gender missing', 'DENY', addDoc(collection(A, 'toilets'), {
  ...validToilet(), truth_v2: { version: 2, source_type: 'community_submission', recorded_at: serverTimestamp(), fee: 'unknown', context: 'unknown', amenities: { ...AMEN_ALL_UNKNOWN } },
}));
await check('A create toilet with NO truth_v2 (legacy-only)', 'DENY', addDoc(collection(A, 'toilets'), {
  name: 'Old Public Toilet', latitude: JLAT, longitude: JLNG, position: POS, added_by: 'alice',
  created_at: serverTimestamp(), is_open: true, is_free: true,
}));
await check('A create toilet legacy is_open alongside truth_v2', 'DENY', addDoc(collection(A, 'toilets'), {
  ...validToilet(), is_open: true,
}));
await check('A create toilet legacy has_water alongside truth_v2', 'DENY', addDoc(collection(A, 'toilets'), {
  ...validToilet(), has_water: true,
}));
await check('A create toilet legacy category alongside truth_v2', 'DENY', addDoc(collection(A, 'toilets'), {
  ...validToilet(), category: 'government',
}));
await check('A create toilet legacy gender_type alongside truth_v2', 'DENY', addDoc(collection(A, 'toilets'), {
  ...validToilet(), gender_type: 'unisex',
}));
await check('A create toilet star_rating alongside truth_v2', 'DENY', addDoc(collection(A, 'toilets'), {
  ...validToilet(), star_rating: 0,
}));
await check('A v2 version != 2 (number 1)', 'DENY', addDoc(collection(A, 'toilets'), {
  ...validToilet(), truth_v2: validTruthV2({ version: 1 }),
}));
await check('A v2 version is string "2"', 'DENY', addDoc(collection(A, 'toilets'), {
  ...validToilet(), truth_v2: validTruthV2({ version: '2' }),
}));
await check('A v2 source_type = osm', 'DENY', addDoc(collection(A, 'toilets'), {
  ...validToilet(), truth_v2: validTruthV2({ source_type: 'osm' }),
}));
await check('A v2 source_type missing', 'DENY', addDoc(collection(A, 'toilets'), {
  ...validToilet(), truth_v2: { version: 2, recorded_at: serverTimestamp(), fee: 'unknown', amenities: { ...AMEN_ALL_UNKNOWN } },
}));
await check('A v2 recorded_at = client now', 'DENY', addDoc(collection(A, 'toilets'), {
  ...validToilet(), truth_v2: validTruthV2({ recorded_at: NOW_CLIENT }),
}));
await check('A v2 recorded_at = yesterday', 'DENY', addDoc(collection(A, 'toilets'), {
  ...validToilet(), truth_v2: validTruthV2({ recorded_at: YESTERDAY }),
}));
await check('A v2 fee bad enum "gratis"', 'DENY', addDoc(collection(A, 'toilets'), {
  ...validToilet(), truth_v2: validTruthV2({ fee: 'gratis' }),
}));
await check('A v2 amenity wrong vocab "yes"', 'DENY', addDoc(collection(A, 'toilets'), {
  ...validToilet(), truth_v2: validTruthV2({ amenities: { ...AMEN_ALL_UNKNOWN, water: 'yes' } }),
}));
await check('A v2 amenities missing a key', 'DENY', addDoc(collection(A, 'toilets'), {
  ...validToilet(), truth_v2: validTruthV2({ amenities: { water: 'unknown', soap: 'unknown', lock: 'unknown', western: 'unknown', wheelchair: 'unknown', baby_change: 'unknown' } }),
}));
await check('A v2 amenities extra key "shower"', 'DENY', addDoc(collection(A, 'toilets'), {
  ...validToilet(), truth_v2: validTruthV2({ amenities: { ...AMEN_ALL_UNKNOWN, shower: 'present' } }),
}));
await check('A v2 truth_v2 extra key "confidence"', 'DENY', addDoc(collection(A, 'toilets'), {
  ...validToilet(), truth_v2: validTruthV2({ confidence: 0.9 }),
}));
await check('A v2 truth_v2 injects open_now', 'DENY', addDoc(collection(A, 'toilets'), {
  ...validToilet(), truth_v2: validTruthV2({ open_now: true }),
}));
await check('A v2 truth_v2 injects women_safe', 'DENY', addDoc(collection(A, 'toilets'), {
  ...validToilet(), truth_v2: validTruthV2({ women_safe: true }),
}));
await check('A v2 truth_v2 injects trust_score', 'DENY', addDoc(collection(A, 'toilets'), {
  ...validToilet(), truth_v2: validTruthV2({ trust_score: 42 }),
}));

// ---- GEO INVARIANT (item 1) ----
await check('A create toilet lat/lng Jodhpur but geopoint Delhi', 'DENY', addDoc(collection(A, 'toilets'), {
  ...validToilet(), latitude: JLAT, longitude: JLNG,
  position: { geohash: 'ttabc', geopoint: new GeoPoint(28.6139, 77.2090) },
}));
await check('A create toilet lng differs from geopoint.longitude', 'DENY', addDoc(collection(A, 'toilets'), {
  ...validToilet(), latitude: JLAT, longitude: 73.5,   // geopoint still 73.1
}));
await check('A create toilet lat differs from geopoint.latitude', 'DENY', addDoc(collection(A, 'toilets'), {
  ...validToilet(), latitude: 26.9,                    // geopoint still 26.3
}));
await check('A create toilet empty geohash', 'DENY', addDoc(collection(A, 'toilets'), {
  ...validToilet(), position: { geohash: '', geopoint: GP },
}));
await check('A create toilet at a DIFFERENT valid location (still DENIED)', 'DENY', addDoc(collection(A, 'toilets'), {
  ...validToilet(), latitude: 19.076, longitude: 72.8777,
  position: { geohash: 'te7dd', geopoint: new GeoPoint(19.076, 72.8777) },
}));
await check('A update toilet last_verified', 'DENY', updateDoc(doc(A, 'toilets/t1'), { last_verified: serverTimestamp() }));
await check('A update toilet star_rating+total', 'DENY', updateDoc(doc(A, 'toilets/t1'), { star_rating: 5, total_ratings: 999 }));
await check('A update toilet is_women_safe', 'DENY', updateDoc(doc(A, 'toilets/t1'), { is_women_safe: true }));
await check('A update toilet warden_user_id', 'DENY', updateDoc(doc(A, 'toilets/t1'), { warden_user_id: 'alice', warden_name: 'Alice' }));
await check('A update toilet is_flagged', 'DENY', updateDoc(doc(A, 'toilets/t1'), { is_flagged: true }));
await check('A update toilet name', 'DENY', updateDoc(doc(A, 'toilets/t1'), { name: 'HACKED' }));
await check('A delete toilet', 'DENY', deleteDoc(doc(A, 'toilets/t1')));
// evidence_v2 is server-owned. Client can neither add it on create nor
// update it afterwards. No rule change was needed — the strict create
// allow-list and `allow update: if false` already cover it; these lock it in.
await check('A update toilet evidence_v2 (server-owned)', 'DENY', updateDoc(doc(A, 'toilets/t1'), {
  evidence_v2: { version: 1, ratings: { count: 999, average: 5 } },
}));
await check('A create toilet with fabricated evidence_v2', 'DENY', addDoc(collection(A, 'toilets'), {
  ...validToilet(), evidence_v2: { version: 1, ratings: { count: 1, average: 5 } },
}));
await check('A create toilet with evidence_v2.condition injected', 'DENY', addDoc(collection(A, 'toilets'), {
  ...validToilet(),
  evidence_v2: { version: 1, condition: { open: 'yes', contributor_count: 5, valid_until: serverTimestamp() } },
}));
await check('A create toilet extra field "email"', 'DENY', addDoc(collection(A, 'toilets'), { ...validToilet(), email: 'a@x.com' }));
await check('A create toilet extra field "admin"', 'DENY', addDoc(collection(A, 'toilets'), { ...validToilet(), admin: true }));
await check('A create toilet extra field "owner_role"', 'DENY', addDoc(collection(A, 'toilets'), { ...validToilet(), owner_role: 'root' }));
await check('A create toilet extra field "verified"', 'DENY', addDoc(collection(A, 'toilets'), { ...validToilet(), verified: true }));
await check('A create toilet extra field "foo"', 'DENY', addDoc(collection(A, 'toilets'), { ...validToilet(), foo: 1 }));
await check('A create toilet extra nested map', 'DENY', addDoc(collection(A, 'toilets'), { ...validToilet(), meta: { a: 1 } }));
await check('A create toilet is_flagged/last_verified/warden', 'DENY', addDoc(collection(A, 'toilets'), { ...validToilet(), is_flagged: true, last_verified: serverTimestamp(), warden_user_id: 'alice' }));
await check('A create toilet star_rating=5', 'DENY', addDoc(collection(A, 'toilets'), { ...validToilet(), star_rating: 5 }));
await check('A create toilet wrong added_by', 'DENY', addDoc(collection(A, 'toilets'), { ...validToilet(), added_by: 'bob' }));
await check('A create toilet forged created_at', 'DENY', addDoc(collection(A, 'toilets'), { ...validToilet(), created_at: YESTERDAY }));
await check('A create toilet latitude 200', 'DENY', addDoc(collection(A, 'toilets'), { ...validToilet(), latitude: 200 }));
await check('A create toilet longitude 999', 'DENY', addDoc(collection(A, 'toilets'), { ...validToilet(), longitude: 999 }));
await check('A create toilet latitude non-number', 'DENY', addDoc(collection(A, 'toilets'), { ...validToilet(), latitude: '26' }));
await check('A create toilet position extra nested key', 'DENY', addDoc(collection(A, 'toilets'), { ...validToilet(), position: { geopoint: GP, geohash: 'ttabc', foo: 1 } }));
await check('A create toilet name too short', 'DENY', addDoc(collection(A, 'toilets'), { ...validToilet(), name: 'ab' }));
await check('A create toilet name too long', 'DENY', addDoc(collection(A, 'toilets'), { ...validToilet(), name: 'z'.repeat(200) }));
await check('A create toilet top-level category rejected (not in allow-list)', 'DENY', addDoc(collection(A, 'toilets'), { ...validToilet(), category: 'nightclub' }));
await check('A create toilet top-level gender_type rejected (not in allow-list)', 'DENY', addDoc(collection(A, 'toilets'), { ...validToilet(), gender_type: 'robot' }));

// ===================== USERS / PRIVACY =====================
await check('A read own users/alice', 'ALLOW', getDoc(doc(A, 'users/alice')));
await check('A write own users/alice', 'ALLOW', setDoc(doc(A, 'users/alice'), { scout_points: 5 }, { merge: true }));
await check('A read BOB users/bob', 'DENY', getDoc(doc(A, 'users/bob')));
await check('A list all users', 'DENY', getDocs(collection(A, 'users')));
await check('A delete own users/alice', 'ALLOW', deleteDoc(doc(A, 'users/alice')));
await check('A delete BOB users/bob', 'DENY', deleteDoc(doc(A, 'users/bob')));

// ===================== PUBLIC PROFILES =====================
await check('anyone read public_profiles', 'ALLOW', getDocs(collection(A, 'public_profiles')));
await check('A write full public_profiles/alice', 'ALLOW', setDoc(doc(A, 'public_profiles/alice'), { name: 'Alice', photo_url: null, scout_points: 30, updated_at: serverTimestamp() }));
await check('A partial-merge {scout_points, updated_at}', 'ALLOW', setDoc(doc(A, 'public_profiles/alice'), { scout_points: 40, updated_at: serverTimestamp() }, { merge: true }));
await check('A public_profiles with email', 'DENY', setDoc(doc(A, 'public_profiles/alice'), { name: 'Alice', email: 'a@x.com', scout_points: 1, updated_at: serverTimestamp() }));
await check('A public_profiles photo_url wrong type (number)', 'DENY', setDoc(doc(A, 'public_profiles/alice'), { name: 'Alice', photo_url: 42, scout_points: 1, updated_at: serverTimestamp() }));
await check('A public_profiles forged updated_at', 'DENY', setDoc(doc(A, 'public_profiles/alice'), { name: 'Alice', photo_url: null, scout_points: 1, updated_at: YESTERDAY }));
await check('A public_profiles negative scout_points', 'DENY', setDoc(doc(A, 'public_profiles/alice'), { name: 'Alice', photo_url: null, scout_points: -5, updated_at: serverTimestamp() }));
await check('A public_profiles name too long', 'DENY', setDoc(doc(A, 'public_profiles/alice'), { name: 'z'.repeat(200), photo_url: null, scout_points: 1, updated_at: serverTimestamp() }));
await check('A write BOB public_profiles', 'DENY', setDoc(doc(A, 'public_profiles/bob'), { name: 'B', scout_points: 1, updated_at: serverTimestamp() }));
await check('A delete own public_profiles', 'ALLOW', deleteDoc(doc(A, 'public_profiles/alice')));
await check('A delete BOB public_profiles', 'DENY', deleteDoc(doc(A, 'public_profiles/bob')));

// ===================== toilet_wardens (private cosmetic) =====================
await check('A write own verify_count', 'ALLOW', setDoc(doc(A, 'users/alice/toilet_wardens/t1'), { verify_count: 3 }, { merge: true }));
await check('A verify_count extra field', 'DENY', setDoc(doc(A, 'users/alice/toilet_wardens/t1'), { verify_count: 3, is_warden: true }, { merge: true }));
await check('A verify_count negative', 'DENY', setDoc(doc(A, 'users/alice/toilet_wardens/t1'), { verify_count: -1 }));
await check('A verify_count wrong type', 'DENY', setDoc(doc(A, 'users/alice/toilet_wardens/t1'), { verify_count: 'lots' }));
await check('A read BOB toilet_wardens', 'DENY', getDoc(doc(A, 'users/bob/toilet_wardens/t1')));

// ===================== catch-all =====================
await check('A read /secret/x', 'DENY', getDoc(doc(A, 'secret/x')));
await check('A write /secret/x', 'DENY', setDoc(doc(A, 'secret/x'), { a: 1 }));

await env.cleanup();

console.log('\n================ RESULTS ================');
for (const r of results) {
  console.log(`${r[0] === 'PASS' ? '  ok ' : ' FAIL'} [${r[1]}] ${r[2]}${r[3] ? '  -- ' + r[3] : ''}`);
}
console.log('========================================');
console.log(`TOTAL ${pass + fail}  |  PASS ${pass}  |  FAIL ${fail}`);
process.exit(fail === 0 ? 0 : 1);
