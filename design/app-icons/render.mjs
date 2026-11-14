// LIME-292c: writes the layer SVGs, the flattened SVGs and the 1024 PNGs (and a contact sheet) for design/app-icons.
import fs from 'node:fs';
import path from 'node:path';
import { icons, PAL, W, root, here } from './build.mjs';
import { PIXEL } from './icons2.mjs';

const { launch } = await import(path.join(root, 'tests', 'lib', 'harness.mjs'));
const only = process.argv.slice(2);
const browser = await launch('chrome');
const page = await browser.newPage();
await page.setViewport({ width: W, height: W, deviceScaleFactor: 1 });

// the pixel icon: sample the real slice at 24x24 and keep three colours
{
  const inner = fs.readFileSync(path.join(here, 'source', 'slice-paths.svg'), 'utf8');
  const svg = `<svg xmlns="http://www.w3.org/2000/svg" width="${W}" height="${W}" viewBox="0 0 ${W} ${W}"><g transform="translate(512 512) scale(0.81) translate(-520 -520)"><g transform="translate(74.50 74.20) scale(3.5660)">${inner}</g></g></svg>`;
  const cells = await page.evaluate(async (svg, size, cell, palette) => {
    const img = new Image(); img.src = 'data:image/svg+xml;utf8,' + encodeURIComponent(svg); await img.decode();
    // 4x supersample, then each cell takes the colour most of its sub-pixels have (the ink outline wins from a quarter of them, so the lines survive)
    const sub = 4, n = size * sub; const c = document.createElement('canvas'); c.width = n; c.height = n; const g = c.getContext('2d');
    const span = size * cell; g.drawImage(img, 512 - span / 2, 512 - span / 2, span, span, 0, 0, n, n);
    const d = g.getImageData(0, 0, n, n).data; const out = [];
    const rgb = (h) => [1, 3, 5].map((i) => parseInt(h.slice(i, i + 2), 16));
    const pal = palette.map((h) => ({ h, v: rgb(h) }));
    for (let y = 0; y < size; y++) for (let x = 0; x < size; x++) {
      const votes = pal.map(() => 0); let solid = 0;
      for (let sy = 0; sy < sub; sy++) for (let sx = 0; sx < sub; sx++) {
        const i = ((y * sub + sy) * n + x * sub + sx) * 4; if (d[i + 3] < 128) continue; solid++;
        let bi = 0, bd = 1e9; pal.forEach((p, k) => { const e = (p.v[0] - d[i]) ** 2 + (p.v[1] - d[i + 1]) ** 2 + (p.v[2] - d[i + 2]) ** 2; if (e < bd) { bd = e; bi = k; } });
        votes[bi]++;
      }
      if (solid < sub * sub * 0.45) continue;
      const ink = votes[2]; let pick = ink >= solid * 0.3 ? 2 : (votes[0] >= votes[1] ? 0 : 1);
      out.push({ x, y, c: pal[pick].h });
    }
    return out;
  }, svg, PIXEL.size, PIXEL.cell, [PAL.lime, PAL.mint, PAL.ink]);
  // the dark rim: the cells on the edge of the silhouette are ink
  const have = new Set(cells.map((c) => c.x + ',' + c.y));
  for (const c of cells) if ([[1, 0], [-1, 0], [0, 1], [0, -1]].some(([dx, dy]) => !have.has((c.x + dx) + ',' + (c.y + dy)))) c.c = PAL.ink;
  PIXEL.cells = cells;
}

const out = (rel, data) => { const p = path.join(here, rel); fs.mkdirSync(path.dirname(p), { recursive: true }); fs.writeFileSync(p, data); };
const stack = (...docs) => docs.map((d) => d.replace(/^<svg[^>]*>/, '').replace(/<\/svg>\s*$/, '')).join('');
const defsOf = (d) => (d.match(/<defs>([\s\S]*?)<\/defs>/) || [, ''])[1];
const bodyOf = (d) => d.replace(/^<svg[^>]*>/, '').replace(/<defs>[\s\S]*?<\/defs>/, '').replace(/<\/svg>\s*$/, '');
const flatten = (bg, ...rest) => `<svg xmlns="http://www.w3.org/2000/svg" width="${W}" height="${W}" viewBox="0 0 ${W} ${W}"><defs>${defsOf(bg)}${rest.map(defsOf).join('')}</defs>${bodyOf(bg)}${rest.map(bodyOf).join('')}</svg>\n`;

async function png(svg, file, transparent = false) {
  await page.setContent(`<html><body style="margin:0;background:${transparent ? 'transparent' : '#fff'}">${svg}</body></html>`);
  fs.mkdirSync(path.dirname(path.join(here, file)), { recursive: true });
  await page.screenshot({ path: path.join(here, file), omitBackground: transparent, clip: { x: 0, y: 0, width: W, height: W } });
}

for (const [name, icon] of Object.entries(icons)) {
  if (only.length && !only.includes(name)) continue;
  const bg = icon.background(), mk = icon.mark();
  out(`${name}/background.svg`, bg); out(`${name}/mark.svg`, mk);
  const bgDark = (icon.backgroundDark || icon.background)();
  if (icon.backgroundDark) out(`${name}/background-dark.svg`, bgDark);
  const flat = flatten(bg, mk), flatDark = flatten(bgDark, mk);
  out(`${name}/${name}.svg`, flat); out(`${name}/${name}-dark.svg`, flatDark);
  // Tinted (Apple's guide): a greyscale mark on transparent; the system supplies the colour
  const tmk = icon.tintedMark ? icon.tintedMark() : mk;
  const tinted = `<svg xmlns="http://www.w3.org/2000/svg" width="${W}" height="${W}" viewBox="0 0 ${W} ${W}"><defs>${defsOf(tmk)}<filter id="grey"><feColorMatrix type="saturate" values="0"/></filter></defs><g filter="url(#grey)">${bodyOf(tmk)}</g></svg>\n`;
  out(`${name}/${name}-tinted.svg`, tinted);
  await png(flat, `png/${name}.png`); await png(flatDark, `png/${name}-dark.png`); await png(tinted, `png/${name}-tinted.png`, true);
  // the layers as PNGs, for the Icon Composer bundle (CoreSVG, which the icon compiler uses, has no filters: the art has them)
  await png(bg, `${name}/layers/background.png`); await png(bgDark, `${name}/layers/background-dark.png`); await png(mk, `${name}/layers/mark.png`, true);
  console.log('drew', name);
}
await browser.close();
