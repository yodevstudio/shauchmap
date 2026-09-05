// Generate the PWA raster icons from the APPROVED ShauchMap mark .
// Renders SVG at exact pixel sizes via headless Chromium, writes:
//   public/icons/icon-192.png  icon-512.png  icon-1024.png
//   public/icons/maskable-192.png  maskable-512.png  maskable-1024.png
// Then verifies each file's real pixel dimensions from the PNG IHDR.
import { chromium } from 'playwright';
import { readFileSync, writeFileSync, mkdirSync } from 'node:fs';
import { dirname, join, resolve } from 'node:path';
import { fileURLToPath } from 'node:url';

const iconsDir = resolve(dirname(fileURLToPath(import.meta.url)), '..', 'public', 'icons');
mkdirSync(iconsDir, { recursive: true });

// The mark, viewBox 0 0 1024 1024 (matches public/icons/icon.svg).
const MARK = `
  <defs>
    <linearGradient id="g" x1="0" y1="0" x2="0" y2="1">
      <stop offset="0" stop-color="#20a06a"/><stop offset="1" stop-color="#0c6f4c"/>
    </linearGradient>
    <linearGradient id="w" x1="0" y1="0" x2="0" y2="1">
      <stop offset="0" stop-color="#ffffff"/><stop offset="1" stop-color="#e6f1ec"/>
    </linearGradient>
  </defs>`;
const PIN = (cx, cy, s) => `
  <g transform="translate(${cx - 512 * s} ${cy - 512 * s}) scale(${s})">
    <path fill="url(#w)" d="M512 236c-110 0-199 89-199 199 0 140 175 320 191 336a11 11 0 0 0 16 0c16-16 191-196 191-336 0-110-89-199-199-199z"/>
    <circle cx="512" cy="435" r="118" fill="url(#g)"/>
    <path d="M455 437l40 40 78-84" fill="none" stroke="#ffffff" stroke-width="34" stroke-linecap="round" stroke-linejoin="round"/>
  </g>`;

// "any": rounded-square badge, pin fills most of it (like the launcher icon).
const anySvg = `<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 1024 1024">${MARK}
  <rect x="16" y="16" width="992" height="992" rx="216" fill="url(#g)"/>
  ${PIN(512, 512, 1)}
</svg>`;

// "maskable": green bleeds to the full square (no corners/inset); pin scaled to
// ~0.66 and centred so it survives an aggressive circular/rounded mask.
const maskSvg = `<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 1024 1024">${MARK}
  <rect x="0" y="0" width="1024" height="1024" fill="url(#g)"/>
  ${PIN(512, 512, 0.66)}
</svg>`;

function pngDims(buf) {
  // PNG signature (8) + IHDR length (4) + "IHDR" (4) => width @ offset 16, height @ 20
  if (buf.readUInt32BE(0) !== 0x89504e47) throw new Error('not a PNG');
  return { w: buf.readUInt32BE(16), h: buf.readUInt32BE(20) };
}

const browser = await chromium.launch();
const out = [];
try {
  for (const [name, svg] of [
    ['icon', anySvg],
    ['maskable', maskSvg],
  ]) {
    for (const size of [192, 512, 1024]) {
      const page = await browser.newPage({ viewport: { width: size, height: size }, deviceScaleFactor: 1 });
      await page.setContent(
        `<!doctype html><style>html,body{margin:0}svg{display:block;width:${size}px;height:${size}px}</style>${svg}`,
        { waitUntil: 'networkidle' },
      );
      const png = await page.screenshot({ omitBackground: true, clip: { x: 0, y: 0, width: size, height: size } });
      const file = join(iconsDir, `${name}-${size}.png`);
      writeFileSync(file, png);
      const { w, h } = pngDims(png);
      out.push({ file: `icons/${name}-${size}.png`, declared: `${size}x${size}`, actual: `${w}x${h}`, ok: w === size && h === size });
      await page.close();
    }
  }
} finally {
  await browser.close();
}

for (const r of out) console.log(`${r.ok ? '✓' : '✗'} ${r.file.padEnd(26)} ${r.actual} (want ${r.declared})`);
if (out.some((r) => !r.ok)) {
  console.error('icon dimension mismatch');
  process.exit(1);
}
console.log(`\n${out.length} icons written to public/icons/ — all dimensions verified.`);
