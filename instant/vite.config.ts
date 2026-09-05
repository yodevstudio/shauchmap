import { defineConfig } from 'vite';
import preact from '@preact/preset-vite';
import { VitePWA } from 'vite-plugin-pwa';

// ShauchMap Instant — Preact + TS + Vite. No map libraries. The Dart brain is
// prebuilt to generated/shauchmap_core.js by scripts/build-core.mjs (predev /
// prebuild) and loaded at runtime as a classic script (see core-loader.ts).
export default defineConfig({
  root: '.',
  plugins: [
    preact(),
    VitePWA({
      registerType: 'prompt',
      injectRegister: null, // we register manually in src/pwa.ts
      workbox: {
 // APP SHELL ONLY . The compiled brain + Preact shell + CSS + icons.
        // The Firebase SDK chunk is NOT shell (fixture mode never loads it, and
        // 8.1 does not connect Firebase) so it is excluded from precache.
        // No runtimeCaching at all — Firestore / core evidence is NEVER cached
        // as "current".
        globPatterns: ['**/*.{js,css,html,svg,webmanifest,png}'],
        globIgnores: [
          '**/shauchmap_core.js.deps',
          '**/oracle-result.json',
          // NOT shell — async chunks, never loaded in fixture mode / 8.1
          '**/firebase-*.js',
          '**/geofire-*.js',
          '**/firestore-source-*.js',
          // large launcher PNGs — the OS fetches these on install, not on first
          // paint. Only the 192px icon + 192px maskable stay in the shell cache.
          '**/*-512.png',
          '**/*-1024.png',
        ],
        // Every canonical Instant route (/, /go, /t/:id, /q/:id) is served the
 // cached APP SHELL (index.html) when offline . A cached SHELL is
        // safe; cached toilet EVIDENCE is not — and there is none, because:
        navigateFallback: 'index.html',
        navigateFallbackAllowlist: [/^\/$/, /^\/go/, /^\/t\//, /^\/q\//],
        runtimeCaching: [], // no Firestore / evidence caching, no background sync
        cleanupOutdatedCaches: true,
        clientsClaim: true,
        skipWaiting: false,
      },
      // App shell only: SVG icons are picked up by globPatterns; the large PNG
      // launcher icons are fetched by the OS on install, not precached.
      includeAssets: [],
      manifest: false, // served from public/manifest.webmanifest (hand-authored, brand-correct)
      devOptions: { enabled: false },
    }),
  ],
  build: {
    target: 'es2020',
    cssCodeSplit: false,
    reportCompressedSize: true,
    rollupOptions: {
      output: {
        manualChunks: {
          firebase: ['firebase/app', 'firebase/firestore/lite'],
          geofire: ['geofire-common'],
        },
      },
    },
  },
  server: { port: 5174, strictPort: true, host: '127.0.0.1' },
  preview: { port: 4174, strictPort: true, host: '127.0.0.1' },
});
