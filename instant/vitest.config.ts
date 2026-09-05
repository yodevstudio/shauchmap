import { defineConfig } from 'vitest/config';
import preact from '@preact/preset-vite';

export default defineConfig({
  plugins: [preact()],
  test: {
    environment: 'jsdom',
    setupFiles: ['./test/setup.ts'],
    include: ['test/**/*.test.{ts,tsx}'],
    css: false,
    restoreMocks: true,
    clearMocks: true,
    // Neutralize any local instant/.env.local (which may hold real Firebase
    // config) so the suite always runs in a clean fixture-mode env.
    // Individual tests opt into firebase mode with vi.stubEnv.
    env: {
      VITE_DATA_MODE: '',
      VITE_FIREBASE_API_KEY: '',
      VITE_FIREBASE_PROJECT_ID: '',
      VITE_FIREBASE_APP_ID: '',
      VITE_FIREBASE_DATABASE_ID: '',
      VITE_FIREBASE_AUTH_DOMAIN: '',
    },
  },
});
