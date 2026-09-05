# ShauchMap Firestore rules test matrix

```
cd test/rules
npm ci
# JAVA_HOME must point at a JDK (e.g. Android Studio's jbr)
npm test
```

`npm test` runs `sync-rules.mjs` first, which copies the **repo-root
`firestore.rules`** into this directory (git-ignored). `rules_test.mjs` then
asserts, at startup, that `./firestore.rules` is byte-for-byte identical to
`../../firestore.rules` and hard-exits (code 1) on any mismatch — so a run can
never pass against a stale copy.
