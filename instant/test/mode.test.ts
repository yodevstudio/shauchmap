import { describe, it, expect, afterEach, vi } from 'vitest';
import { dataMode, isDemo, __resetModeForTests } from '../src/data/mode';

afterEach(() => {
  vi.unstubAllEnvs();
  __resetModeForTests();
});

describe('data mode ', () => {
  it('defaults to fixture mode with no env', () => {
    __resetModeForTests();
    expect(dataMode().mode).toBe('fixture');
    expect(isDemo()).toBe(true);
  });

  it('FAILS CLOSED when firebase is requested but config is missing', () => {
    vi.stubEnv('VITE_DATA_MODE', 'firebase');
    __resetModeForTests();
    expect(() => dataMode()).toThrow(/missing config/i);
  });

  it('never silently downgrades firebase -> fixture', () => {
    vi.stubEnv('VITE_DATA_MODE', 'firebase');
    vi.stubEnv('VITE_FIREBASE_API_KEY', 'k');
    __resetModeForTests();
    // still missing projectId/appId/databaseId
    expect(() => dataMode()).toThrow(/projectId|appId|databaseId/);
  });

  it('accepts a complete firebase config', () => {
    vi.stubEnv('VITE_DATA_MODE', 'firebase');
    vi.stubEnv('VITE_FIREBASE_API_KEY', 'k');
    vi.stubEnv('VITE_FIREBASE_PROJECT_ID', 'p');
    vi.stubEnv('VITE_FIREBASE_APP_ID', 'a');
    vi.stubEnv('VITE_FIREBASE_DATABASE_ID', '(default)');
    __resetModeForTests();
    const m = dataMode();
    expect(m.mode).toBe('firebase');
    expect(m.firebase?.projectId).toBe('p');
    expect(isDemo()).toBe(false);
  });

  it('rejects an unknown mode string', () => {
    vi.stubEnv('VITE_DATA_MODE', 'nonsense');
    __resetModeForTests();
    expect(() => dataMode()).toThrow(/must be "fixture" or "firebase"/);
  });
});
