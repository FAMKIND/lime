// LIME-292c: the eight app icons, drawn procedurally around the lime slice (never changed in shape or position), as SVG layers + flattened SVG + 1024 PNGs.
//   node design/app-icons/build.mjs            (uses the headless Chrome in tests/node_modules/puppeteer-core)
// Output: design/app-icons/<name>/{background,mark,scene}.svg, <name>/<name>{,-dark,-tinted}.svg, png/<name>{,-dark,-tinted}.png
import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

const here = path.dirname(fileURLToPath(import.meta.url));
const root = path.resolve(here, '..', '..');
const INNER = fs.readFileSync(path.join(here, 'source', 'slice-paths.svg'), 'utf8');
const PAL = { ink: '#131b17', lime: '#09a950', mint: '#a3e18a', pale: '#e4f9be', cream: '#f0eee6', paper: '#f9f8f4' };
const W = 1024;

const doc = (body, defs = '') => `<svg xmlns="http://www.w3.org/2000/svg" width="${W}" height="${W}" viewBox="0 0 ${W} ${W}"><defs>${defs}</defs>${body}</svg>\n`;
const T = 'translate(74.50 74.20) scale(3.5660)';
const mark = (inner = INNER, extra = '') => `<g transform="${T}" stroke-linejoin="round" stroke-linecap="round" ${extra}>${inner}</g>`;
// the slice's filled shapes only, one colour, with an outline of the same colour (a die-cut edge)
const silhouette = (color, strokeWidth) => INNER.split('\n').filter((l) => /fill="#/.test(l) && !/fill="none"/.test(l))
  .map((l) => l.replace(/fill="#[0-9a-fA-F]+"/, `fill="${color}" stroke="${color}" stroke-width="${strokeWidth}"`)).join('\n');

const files = {};   // relative path -> content
const put = (rel, content) => { files[rel] = content; };

// ---- Per icon: layers (background, mark, scene?) and the dark variant of the background.
const icons = {};

// 1. lime (the shipped art): background cream, mark as shipped.
icons.lime = {
  background: () => doc(`<rect width="${W}" height="${W}" fill="${PAL.paper}"/>`),
  mark: () => doc(mark()),
  backgroundDark: () => doc(`<rect width="${W}" height="${W}" fill="${PAL.ink}"/><circle cx="512" cy="520" r="470" fill="url(#g)"/>`,
    `<radialGradient id="g"><stop offset="0" stop-color="${PAL.lime}" stop-opacity="0.30"/><stop offset="1" stop-color="${PAL.lime}" stop-opacity="0"/></radialGradient>`),
};

// 2. Dark: the slice glowing softly on near-black with a green radial glow.
icons.dark = {
  background: () => doc(`<rect width="${W}" height="${W}" fill="${PAL.ink}"/><circle cx="520" cy="520" r="560" fill="url(#g)"/>`,
    `<radialGradient id="g"><stop offset="0" stop-color="${PAL.lime}" stop-opacity="0.55"/><stop offset="0.55" stop-color="${PAL.lime}" stop-opacity="0.14"/><stop offset="1" stop-color="${PAL.lime}" stop-opacity="0"/></radialGradient>`),
  mark: () => doc(`<g filter="url(#glow)">${mark()}</g>`,
    `<filter id="glow" x="-20%" y="-20%" width="140%" height="140%"><feGaussianBlur in="SourceAlpha" stdDeviation="26" result="b"/><feFlood flood-color="${PAL.mint}" flood-opacity="0.55"/><feComposite in2="b" operator="in" result="g"/><feMerge><feMergeNode in="g"/><feMergeNode in="SourceGraphic"/></feMerge></filter>`),
};

// 3. Sticker: a die-cut white edge and a soft shadow on a lime-to-mint gradient.
icons.sticker = {
  background: () => doc(`<rect width="${W}" height="${W}" fill="url(#g)"/>`,
    `<linearGradient id="g" x1="0" y1="1" x2="1" y2="0"><stop offset="0" stop-color="${PAL.lime}"/><stop offset="1" stop-color="${PAL.mint}"/></linearGradient>`),
  mark: () => doc(`<g filter="url(#sh)"><g transform="${T}" stroke-linejoin="round">${silhouette('#ffffff', 22)}</g></g>${mark()}`,
    `<filter id="sh" x="-20%" y="-20%" width="150%" height="150%"><feDropShadow dx="0" dy="18" stdDeviation="16" flood-color="${PAL.ink}" flood-opacity="0.35"/></filter>`),
  backgroundDark: () => doc(`<rect width="${W}" height="${W}" fill="url(#g)"/>`,
    `<linearGradient id="g" x1="0" y1="1" x2="1" y2="0"><stop offset="0" stop-color="#05361c"/><stop offset="1" stop-color="#0c7a3b"/></linearGradient>`),
};

// 7. Rainbow: saturated segments, a die-cut edge, on cream.
const RAINBOW = ['#ff3b3b', '#ff7a00', '#ffc400', '#9bdc1f', '#27c95a', '#00c2b8', '#2f7bff', '#6a4bff', '#b34bff', '#ff4fa3'];
const rainbowInner = (() => {
  let i = 0;
  return INNER.split('\n').map((l) => {
    // the first filled shape is the rind: a deep ink, so the saturated segments glow; the rest are the segments, one colour each
    if (/fill="#/.test(l) && !/fill="none"/.test(l)) { const k = i++; return l.replace(/fill="#[0-9a-fA-F]+"/, `fill="${k === 0 ? '#1d2823' : RAINBOW[(k - 1) % RAINBOW.length]}"`); }
    return l;
  }).join('\n');
})();
icons.rainbow = {
  background: () => doc(`<rect width="${W}" height="${W}" fill="${PAL.paper}"/>`),
  mark: () => doc(`<g filter="url(#sh)"><g transform="${T}" stroke-linejoin="round">${silhouette('#ffffff', 22)}</g></g>${mark(rainbowInner)}`,
    `<filter id="sh" x="-20%" y="-20%" width="150%" height="150%"><feDropShadow dx="0" dy="16" stdDeviation="14" flood-color="${PAL.ink}" flood-opacity="0.28"/></filter>`),
  backgroundDark: () => doc(`<rect width="${W}" height="${W}" fill="#1b1f1d"/>`),
};

export { icons, doc, mark, silhouette, files, put, INNER, PAL, W, T, root, here };
