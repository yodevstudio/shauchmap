// Copies the REPO-ROOT firestore.rules into this dir so the emulator
// (firebase.json -> "firestore.rules") always evaluates the real file.
// rules_test.mjs additionally asserts byte-equality at startup.
import fs from 'node:fs';
import { fileURLToPath } from 'node:url';
const root = fileURLToPath(new URL('../../firestore.rules', import.meta.url));
const local = fileURLToPath(new URL('./firestore.rules', import.meta.url));
fs.copyFileSync(root, local);
console.log(`synced ${root} -> ./firestore.rules (${fs.statSync(local).size} bytes)`);
