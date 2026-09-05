// App-shell PWA registration . Prompt-to-update; no runtime
// caching of Firestore or core evidence — an offline app never shows a stale
// "current" recommendation.
import { registerSW } from 'virtual:pwa-register';

export function registerPwa() {
  if (import.meta.env.DEV) return;
  const update = registerSW({
    immediate: true,
    onNeedRefresh() {
      // Minimal, unobtrusive: reload to pick up the new shell.
      if (confirm('A new version of ShauchMap Instant is available. Reload now?')) {
        void update(true);
      }
    },
    onOfflineReady() {
      console.info('[ShauchMap Instant] app shell ready offline (status still needs a connection).');
    },
  });
}
