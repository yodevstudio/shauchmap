import { describe, it, expect } from 'vitest';
import { readFileSync } from 'node:fs';
import { resolve } from 'node:path';

const root = resolve(__dirname, '..');
const manifest = JSON.parse(readFileSync(resolve(root, 'public/manifest.webmanifest'), 'utf8'));
const viteConfig = readFileSync(resolve(root, 'vite.config.ts'), 'utf8');

function pngDims(file: string): { w: number; h: number } {
  const b = readFileSync(resolve(root, 'public', file));
  expect(b.readUInt32BE(0)).toBe(0x89504e47); // PNG signature
  return { w: b.readUInt32BE(16), h: b.readUInt32BE(20) };
}

describe('PWA manifest + icons ', () => {
  it('description does not overclaim', () => {
    const d = manifest.description.toLowerCase();
    expect(d).not.toMatch(/\b(truthful|usable|guaranteed|verified)\b/);
    expect(manifest.name).toBe('ShauchMap Instant');
    expect(manifest.short_name).toBe('ShauchMap');
  });

  it('every PNG icon declares exactly one size, and it matches the real pixels', () => {
    const pngs = manifest.icons.filter((i: { type: string }) => i.type === 'image/png');
    expect(pngs.length).toBeGreaterThanOrEqual(6);
    for (const icon of pngs) {
      expect(icon.sizes, `${icon.src} sizes must be a single WxH`).toMatch(/^\d+x\d+$/);
      const [w, h] = icon.sizes.split('x').map(Number);
      const file = icon.src.replace(/^\//, '');
      const real = pngDims(file);
      expect(real, `${icon.src}`).toEqual({ w, h });
    }
  });

  it('has both 192 and 512 for `any` and for `maskable`', () => {
    const has = (purpose: string, size: string) =>
      manifest.icons.some(
        (i: { purpose: string; sizes: string; type: string }) =>
          i.type === 'image/png' && i.purpose === purpose && i.sizes === size,
      );
    for (const size of ['192x192', '512x512']) {
      expect(has('any', size), `any ${size}`).toBe(true);
      expect(has('maskable', size), `maskable ${size}`).toBe(true);
    }
  });
});

describe('offline app-shell service worker ', () => {
  it('serves the shell for every canonical route offline (no denylist on /t, /q, /go)', () => {
    expect(viteConfig).not.toMatch(/navigateFallbackDenylist/);
    expect(viteConfig).toMatch(/navigateFallbackAllowlist/);
    expect(viteConfig).toMatch(/\/\^\\\/go/); // /^\/go
    expect(viteConfig).toMatch(/\/\^\\\/t\\\//); // /^\/t\//
    expect(viteConfig).toMatch(/\/\^\\\/q\\\//); // /^\/q\//
  });

  it('keeps runtimeCaching empty — no Firestore / evidence ever cached as current', () => {
    expect(viteConfig).toMatch(/runtimeCaching:\s*\[\]/);
  });
});
