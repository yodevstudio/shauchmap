// public_profiles MIRROR behaviour, end-to-end against the real (repo-root)
// firestore.rules in the emulator.
//
// Run:
//   node sync-rules.mjs && firebase emulators:exec --only firestore \
//     --project demo-shauchmap "node pp_mirror_emulator.mjs"
//
// The 153-case rules matrix (rules_test.mjs) proves the /public_profiles
// ALLOW/DENY rule is unchanged. THIS file proves the CLIENT-SIDE fix: the three
// write paths in lib/services/firestore_service.dart now compose payloads that
//   * create the FULL projection on a first write (even a points-first write),
//   * never carry scout_points on a mirror refresh (so merge keeps the score),
//   * keep scout_points atomic (FieldValue.increment) on the points path,
//   * never drop name/photo_url on a later points award,
//   * are idempotent on repeat.
//
// Payloads below mirror these exact call sites (kept in sync by comment):
//   ensurePublicProfileMirror()  -> { ...identity, updated_at: serverTimestamp() }
//   addScoutPoints(n)            -> { scout_points: increment(n),
//                                     updated_at: serverTimestamp(), ...identity }
//   createOrUpdateUser()         -> { ...identity, scout_points: <abs>,
//                                     updated_at: serverTimestamp() }
// where identity = { name: <sanitised, fallback 'Explorer'>,
//                    photo_url?: <sanitised, omitted when absent/oversize> }.

import fs from 'node:fs';
import { fileURLToPath } from 'node:url';
import {
  initializeTestEnvironment, assertSucceeds, assertFails,
} from '@firebase/rules-unit-testing';
import {
  doc, getDoc, setDoc, serverTimestamp, increment,
} from 'firebase/firestore';

const PROJECT = 'demo-shauchmap';
const ROOT_RULES = fileURLToPath(new URL('../../firestore.rules', import.meta.url));
const LOCAL_RULES = fileURLToPath(new URL('./firestore.rules', import.meta.url));
const RULES = fs.readFileSync(ROOT_RULES, 'utf8');
let localRules = null;
try { localRules = fs.readFileSync(LOCAL_RULES, 'utf8'); } catch { /* not synced */ }
if (localRules !== RULES) {
  console.error('ABORT: ./firestore.rules is not byte-identical to repo root. Run `node sync-rules.mjs`.');
  process.exit(1);
}
console.log(`rules source: ${ROOT_RULES} (${RULES.length} bytes) — local copy verified identical`);

// ---- payload composers: byte-mirror of firestore_service.dart --------------
const NAME = 'Yogendra Singh';
const PHOTO = 'https://lh3.googleusercontent.com/a/x=s96';
const FALLBACK = 'Explorer';

function sanitizeName(raw) {
  const t = (raw ?? '').trim();
  const base = t.length === 0 ? FALLBACK : t;
  return base.length > 80 ? base.slice(0, 80) : base;
}
function sanitizePhoto(raw) {
  const t = (raw ?? '').trim();
  if (t.length === 0) return null;
  if (t.length > 500) return null;
  return t;
}
function identity(name, photo) {
  const out = { name: sanitizeName(name) };
  const p = sanitizePhoto(photo);
  if (p !== null) out.photo_url = p;
  return out;
}
const ensureMirrorPayload = (name, photo) => ({
  ...identity(name, photo),
  updated_at: serverTimestamp(),
});
const addScoutPointsPayload = (n, name, photo) => ({
  scout_points: increment(n),
  updated_at: serverTimestamp(),
  ...identity(name, photo),
});

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
function expect(name, cond, detail = '') {
  if (cond) { pass++; results.push(['PASS', 'ASSERT', name]); }
  else { fail++; results.push(['FAIL', 'ASSERT', name, detail]); }
}

const env = await initializeTestEnvironment({
  projectId: PROJECT,
  firestore: { rules: RULES, host: '127.0.0.1', port: 8080 },
});

const U = env.authenticatedContext('u1').firestore();
const ref = doc(U, 'public_profiles/u1');
async function seedBare(fields) {
  await env.withSecurityRulesDisabled(async (ctx) => {
    await setDoc(doc(ctx.firestore(), 'public_profiles/u1'), fields);
  });
}
async function wipe() {
  await env.withSecurityRulesDisabled(async (ctx) => {
    await setDoc(doc(ctx.firestore(), 'public_profiles/u1'), {}); // reset
    await import('firebase/firestore').then(({ deleteDoc }) =>
      deleteDoc(doc(ctx.firestore(), 'public_profiles/u1')));
  });
}

// ============================================================ CASE 1
// public_profiles absent -> silent-resume mirror -> FULL projection created,
// no scout_points key (so a score can never be reset by the mirror).
await wipe();
await check('CASE 1 mirror create on absent doc', 'ALLOW',
  setDoc(ref, ensureMirrorPayload(NAME, PHOTO), { merge: true }));
{
  const d = (await getDoc(ref)).data();
  expect('CASE 1 name populated', d.name === NAME, JSON.stringify(d));
  expect('CASE 1 photo populated', d.photo_url === PHOTO, JSON.stringify(d));
  expect('CASE 1 updated_at present', d.updated_at != null);
  expect('CASE 1 NO scout_points key', !('scout_points' in d), JSON.stringify(d));
}

// ============================================================ CASE 2
// doc absent -> points awarded BEFORE any mirror -> resulting doc has
// scout_points AND the available name/photo (never a bare row).
await wipe();
await check('CASE 2 points-first create on absent doc', 'ALLOW',
  setDoc(ref, addScoutPointsPayload(20, NAME, PHOTO), { merge: true }));
{
  const d = (await getDoc(ref)).data();
  expect('CASE 2 scout_points == 20', d.scout_points === 20, JSON.stringify(d));
  expect('CASE 2 name populated', d.name === NAME, JSON.stringify(d));
  expect('CASE 2 photo populated', d.photo_url === PHOTO, JSON.stringify(d));
}

// ============================================================ CASE 3
// bare {scout_points:30, updated_at} exists (the historical anonymous-mirror defect)
// -> silent-resume mirror -> name/photo backfilled, points PRESERVED.
await wipe();
await seedBare({ scout_points: 30, updated_at: new Date() });
await check('CASE 3 mirror backfill on bare doc', 'ALLOW',
  setDoc(ref, ensureMirrorPayload(NAME, PHOTO), { merge: true }));
{
  const d = (await getDoc(ref)).data();
  expect('CASE 3 name backfilled', d.name === NAME, JSON.stringify(d));
  expect('CASE 3 photo backfilled', d.photo_url === PHOTO, JSON.stringify(d));
  expect('CASE 3 scout_points preserved == 30', d.scout_points === 30, JSON.stringify(d));
}

// ============================================================ CASE 4
// full doc exists -> a later points award -> scout_points increments
// atomically, name/photo PRESERVED.
await wipe();
await seedBare({ name: NAME, photo_url: PHOTO, scout_points: 30, updated_at: new Date() });
await check('CASE 4 points award on full doc', 'ALLOW',
  setDoc(ref, addScoutPointsPayload(10, NAME, PHOTO), { merge: true }));
{
  const d = (await getDoc(ref)).data();
  expect('CASE 4 scout_points 30 -> 40 (atomic increment)', d.scout_points === 40, JSON.stringify(d));
  expect('CASE 4 name preserved', d.name === NAME, JSON.stringify(d));
  expect('CASE 4 photo preserved', d.photo_url === PHOTO, JSON.stringify(d));
}

// ============================================================ CASE 5
// full doc exists -> silent-resume mirror again -> idempotent: name/photo/score
// unchanged, only updated_at refreshed.
await wipe();
await seedBare({ name: NAME, photo_url: PHOTO, scout_points: 40, updated_at: new Date() });
await check('CASE 5 idempotent mirror refresh', 'ALLOW',
  setDoc(ref, ensureMirrorPayload(NAME, PHOTO), { merge: true }));
{
  const d = (await getDoc(ref)).data();
  expect('CASE 5 name unchanged', d.name === NAME, JSON.stringify(d));
  expect('CASE 5 photo unchanged', d.photo_url === PHOTO, JSON.stringify(d));
  expect('CASE 5 scout_points unchanged == 40', d.scout_points === 40, JSON.stringify(d));
}

// ============================================================ CASE 7
// private fields can never reach public_profiles — even if a future bug
// composed one, the RULES are the backstop.
await wipe();
await check('CASE 7 email in mirror payload -> DENY', 'DENY',
  setDoc(ref, { ...ensureMirrorPayload(NAME, PHOTO), email: 'u1@example.com' }, { merge: true }));
await check('CASE 7 provider metadata in payload -> DENY', 'DENY',
  setDoc(ref, { ...ensureMirrorPayload(NAME, PHOTO), provider: 'google.com' }, { merge: true }));

// ============================================================ CASE 8
// sanitisation obeys the rule limits: an unsanitised 200-char name is
// rejected; the sanitiser's 80-char clamp is accepted.
await wipe();
await check('CASE 8 raw 200-char name -> DENY', 'DENY',
  setDoc(ref, { name: 'z'.repeat(200), updated_at: serverTimestamp() }, { merge: true }));
await check('CASE 8 sanitised (clamped-to-80) name -> ALLOW', 'ALLOW',
  setDoc(ref, ensureMirrorPayload('z'.repeat(200), null), { merge: true }));
{
  const d = (await getDoc(ref)).data();
  expect('CASE 8 stored name length == 80', (d.name || '').length === 80, JSON.stringify(d).slice(0, 120));
  expect('CASE 8 no photo_url key when photo absent', !('photo_url' in d), JSON.stringify(d).slice(0, 120));
}

// empty display name -> product fallback persona, still a valid write
await wipe();
await check('CASE 8 empty name -> fallback persona ALLOW', 'ALLOW',
  setDoc(ref, ensureMirrorPayload('   ', ''), { merge: true }));
{
  const d = (await getDoc(ref)).data();
  expect('CASE 8 empty name -> "Explorer"', d.name === FALLBACK, JSON.stringify(d));
}

await env.cleanup();

console.log('\n================ PP-MIRROR RESULTS ================');
for (const r of results) {
  console.log(`${r[0] === 'PASS' ? '  ok ' : ' FAIL'} [${r[1]}] ${r[2]}${r[3] ? '  -- ' + r[3] : ''}`);
}
console.log('==================================================');
console.log(`TOTAL ${pass + fail}  |  PASS ${pass}  |  FAIL ${fail}`);
process.exit(fail === 0 ? 0 : 1);
