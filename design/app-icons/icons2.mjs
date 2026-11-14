// LIME-292c: Notebook, Chalkboard, Pixel and Apple (the other four are in build.mjs).
import { icons, doc, mark, silhouette, fit, INNER, PAL, W, T } from './build.mjs';

// ---- 4. Notebook: a composition cover: dense, fine white worms on black (vermiculation), a black spine on the left, a large white label with the slice small inside it
// and two ruled lines under it (292d: finer marble, bigger label, smaller slice).
const SPINE = 150;
const LABEL = { x: 262, y: 206, w: 650, h: 612, r: 36 };
const marble = `
  <rect width="${W}" height="${W}" fill="#0a0c0b"/>
  <rect width="${W}" height="${W}" fill="#f4f2ec" filter="url(#worms)"/>
  <rect width="${W}" height="${W}" fill="#f4f2ec" filter="url(#worms2)" opacity="0.9"/>
  <rect width="${W}" height="${W}" fill="#f4f2ec" filter="url(#dots)" opacity="0.7"/>`;
const wormTable = (hits) => Array.from({ length: 40 }, (_, k) => (hits.includes(k) ? 1 : 0)).join(' ');
const marbleDefs = `
  <filter id="worms" x="0" y="0" width="100%" height="100%" color-interpolation-filters="sRGB">
    <feTurbulence type="fractalNoise" baseFrequency="0.0155 0.0185" numOctaves="3" seed="8" result="n"/>
    <feColorMatrix in="n" type="matrix" values="0 0 0 0 1  0 0 0 0 1  0 0 0 0 1  1 0 0 0 0"/>
    <feComponentTransfer><feFuncA type="discrete" tableValues="${wormTable([11, 12, 13, 22, 23, 24, 31, 32])}"/></feComponentTransfer>
  </filter>
  <filter id="worms2" x="0" y="0" width="100%" height="100%" color-interpolation-filters="sRGB">
    <feTurbulence type="fractalNoise" baseFrequency="0.027 0.024" numOctaves="2" seed="31" result="n"/>
    <feColorMatrix in="n" type="matrix" values="0 0 0 0 1  0 0 0 0 1  0 0 0 0 1  1 0 0 0 0"/>
    <feComponentTransfer><feFuncA type="discrete" tableValues="${wormTable([17, 18, 27, 28])}"/></feComponentTransfer>
  </filter>
  <filter id="dots" x="0" y="0" width="100%" height="100%" color-interpolation-filters="sRGB">
    <feTurbulence type="fractalNoise" baseFrequency="0.07" numOctaves="2" seed="5" result="n"/>
    <feColorMatrix in="n" type="matrix" values="0 0 0 0 1  0 0 0 0 1  0 0 0 0 1  1 0 0 0 0"/>
    <feComponentTransfer><feFuncA type="discrete" tableValues="${wormTable([21])}"/></feComponentTransfer>
  </filter>
  <linearGradient id="spine" x1="0" x2="1"><stop offset="0" stop-color="#050706"/><stop offset="0.55" stop-color="#181c1a"/><stop offset="1" stop-color="#0a0d0b"/></linearGradient>
  <filter id="lsh" x="-10%" y="-10%" width="120%" height="125%"><feDropShadow dx="0" dy="10" stdDeviation="12" flood-color="#000" flood-opacity="0.4"/></filter>`;
const label = (dark) => `
  <g filter="url(#lsh)"><rect x="${LABEL.x}" y="${LABEL.y}" width="${LABEL.w}" height="${LABEL.h}" rx="${LABEL.r}" fill="${dark ? '#e9e7df' : '#fbfaf6'}"/></g>
  <rect x="${LABEL.x + 22}" y="${LABEL.y + 22}" width="${LABEL.w - 44}" height="${LABEL.h - 44}" rx="${LABEL.r - 14}" fill="none" stroke="${PAL.ink}" stroke-opacity="0.18" stroke-width="3"/>
  <line x1="${LABEL.x + 90}" y1="${LABEL.y + LABEL.h - 150}" x2="${LABEL.x + LABEL.w - 90}" y2="${LABEL.y + LABEL.h - 150}" stroke="${PAL.ink}" stroke-opacity="0.55" stroke-width="5" stroke-linecap="round"/>
  <line x1="${LABEL.x + 90}" y1="${LABEL.y + LABEL.h - 96}" x2="${LABEL.x + LABEL.w - 170}" y2="${LABEL.y + LABEL.h - 96}" stroke="${PAL.ink}" stroke-opacity="0.55" stroke-width="5" stroke-linecap="round"/>`;
const spineStrip = `<rect width="${SPINE}" height="${W}" fill="url(#spine)"/><rect x="${SPINE - 6}" width="6" height="${W}" fill="#000" opacity="0.35"/>`;
// the slice, small, inside the label (the brand mark's shape, scaled): 0.40 * 861 = ~345 px in a 650 px label
const NOTE_SCALE = 0.40;
const noteMark = () => {
  const cx = LABEL.x + LABEL.w / 2, cy = LABEL.y + 262;
  return `<g transform="translate(${cx} ${cy}) scale(${NOTE_SCALE}) translate(-520 -520)">${mark()}</g>`;
};
icons.notebook = {
  background: () => doc(`${marble}${spineStrip}${label(false)}`, marbleDefs),
  mark: () => doc(noteMark()),
  backgroundDark: () => doc(`${marble}<rect width="${W}" height="${W}" fill="#000" opacity="0.38"/>${spineStrip}${label(true)}`, marbleDefs),
  // Tinted: the slice at the same size as the others (not the label's small one)
  tintedMark: () => doc(fit(mark())),
};

// ---- 5. Chalkboard: a slate-green board, the slice in chalk with dust, a wooden tray along the bottom with a chalk stick.
const chalkDefs = `
  <filter id="rough" x="-10%" y="-10%" width="120%" height="120%">
    <feTurbulence type="fractalNoise" baseFrequency="0.035" numOctaves="2" seed="3" result="t"/>
    <feDisplacementMap in="SourceGraphic" in2="t" scale="9" xChannelSelector="R" yChannelSelector="G" result="d"/>
    <feTurbulence type="fractalNoise" baseFrequency="0.6" numOctaves="2" seed="9" result="g"/>
    <feColorMatrix in="g" type="matrix" values="0 0 0 0 0  0 0 0 0 0  0 0 0 0 0  0 0 0 -2.2 1.95" result="grain"/>
    <feComposite in="d" in2="grain" operator="in"/>
  </filter>
  <filter id="dust" x="-30%" y="-30%" width="160%" height="160%"><feGaussianBlur stdDeviation="22"/></filter>
  <radialGradient id="board" cx="0.45" cy="0.4" r="0.8"><stop offset="0" stop-color="#3c5f4e"/><stop offset="1" stop-color="#26402f"/></radialGradient>
  <linearGradient id="wood" x1="0" y1="0" x2="0" y2="1"><stop offset="0" stop-color="#b98550"/><stop offset="0.5" stop-color="#a06a3a"/><stop offset="1" stop-color="#7a4f2a"/></linearGradient>`;
const boardBg = (dark) => `
  <rect width="${W}" height="${W}" fill="url(#board)"/>
  ${dark ? `<rect width="${W}" height="${W}" fill="#000" opacity="0.32"/>` : ''}
  <ellipse cx="400" cy="330" rx="260" ry="120" fill="#ffffff" opacity="0.07" filter="url(#dust)"/>
  <ellipse cx="640" cy="640" rx="300" ry="140" fill="#ffffff" opacity="0.06" filter="url(#dust)"/>
  <rect y="${W - 150}" width="${W}" height="150" fill="url(#wood)"/>
  <rect y="${W - 150}" width="${W}" height="10" fill="#d9a56a"/>
  <rect y="${W - 24}" width="${W}" height="24" fill="#5c3a1d" opacity="0.55"/>
  <g transform="rotate(-6 790 ${W - 118})"><rect x="690" y="${W - 134}" width="190" height="34" rx="12" fill="#f3f1ea"/><rect x="690" y="${W - 134}" width="190" height="10" rx="5" fill="#ffffff" opacity="0.7"/></g>`;
const chalkInner = INNER.replace(/stroke="#131b17"/g, 'stroke="#fbfaf4"').replace(/fill="#09a950"/g, 'fill="#8fe3a6" fill-opacity="0.42"').replace(/fill="#a3e18a"/g, 'fill="#e2f8c9" fill-opacity="0.30"');
icons.chalkboard = {
  background: () => doc(boardBg(false), chalkDefs),
  mark: () => doc(`<g transform="translate(520 478) scale(0.8) translate(-520 -520)"><g filter="url(#rough)">${mark(chalkInner)}</g></g>`, chalkDefs),
  backgroundDark: () => doc(boardBg(true), chalkDefs),
  tintedMark: () => doc(fit(mark())),
};

// ---- 8. Apple: the slice as a teacher's apple (a stem, a leaf, a gloss) on warm cream.
const APPLE = 'M512 250 C440 190 310 206 260 330 C208 462 262 640 354 742 C410 804 462 800 512 780 C562 800 614 804 670 742 C762 640 816 462 764 330 C714 206 584 190 512 250 Z';
const appleDefs = `
  <clipPath id="body"><path d="${APPLE}" transform="translate(512 520) scale(0.9) translate(-512 -520)"/></clipPath>
  <linearGradient id="skin" x1="0" y1="0" x2="1" y2="1"><stop offset="0" stop-color="#ef5a3d"/><stop offset="1" stop-color="#b8231d"/></linearGradient>
  <filter id="ash" x="-20%" y="-20%" width="150%" height="160%"><feDropShadow dx="0" dy="22" stdDeviation="20" flood-color="#5c2b12" flood-opacity="0.35"/></filter>`;
const appleArt = () => `<g transform="translate(512 560) scale(1.15) translate(-512 -520)">
  <g filter="url(#ash)"><path d="${APPLE}" transform="translate(512 520) scale(0.98) translate(-512 -520)" fill="url(#skin)"/></g>
  <g clip-path="url(#body)"><rect width="${W}" height="${W}" fill="${PAL.pale}"/><g transform="translate(512 540) scale(1.12) translate(-520 -520)">${mark()}</g></g>
  <path d="M512 262 C506 214 520 170 548 132" fill="none" stroke="#5a3a1f" stroke-width="22" stroke-linecap="round"/>
  <path d="M556 168 C610 112 690 118 724 150 C690 214 612 222 556 168 Z" fill="${PAL.lime}" stroke="${PAL.ink}" stroke-width="5" stroke-linejoin="round"/>
  <path d="M572 168 C620 150 664 148 700 150" fill="none" stroke="${PAL.ink}" stroke-opacity="0.45" stroke-width="4" stroke-linecap="round"/>
  <ellipse cx="322" cy="440" rx="30" ry="74" fill="#ffffff" opacity="0.42" transform="rotate(14 322 440)"/></g>`;
icons.apple = {
  background: () => doc(`<rect width="${W}" height="${W}" fill="#f6ead2"/>`),
  mark: () => doc(appleArt(), appleDefs),
  backgroundDark: () => doc(`<rect width="${W}" height="${W}" fill="#3a2a1c"/>`),
};

// ---- 6. Pixel: the 24x24 slice in front of a dark retro screen (scan lines, a faint CRT glow). The cells are filled in by render.mjs, which samples the real mark.
export const PIXEL = { size: 32, cell: 22, cells: [] };
const pixelScreen = (dark) => `
  <rect width="${W}" height="${W}" fill="${dark ? '#08110c' : '#0f1c15'}"/>
  <rect width="${W}" height="${W}" fill="url(#crt)"/>
  <rect x="-40" y="-40" width="${W + 80}" height="${W + 80}" fill="none" stroke="${PAL.lime}" stroke-width="150" opacity="0.30" filter="url(#edge)"/>
  ${Array.from({ length: 171 }, (_, i) => `<rect y="${i * 6}" width="${W}" height="2.6" fill="#000" opacity="0.55"/>`).join('')}
  <rect width="${W}" height="${W}" fill="url(#vig)"/>`;
const pixelDefs = `
  <filter id="edge" x="-20%" y="-20%" width="140%" height="140%"><feGaussianBlur stdDeviation="46"/></filter>
  <radialGradient id="crt" cx="0.5" cy="0.5" r="0.65"><stop offset="0" stop-color="${PAL.lime}" stop-opacity="0.34"/><stop offset="1" stop-color="${PAL.lime}" stop-opacity="0"/></radialGradient>
  <radialGradient id="vig" cx="0.5" cy="0.5" r="0.75"><stop offset="0.6" stop-color="#000" stop-opacity="0"/><stop offset="1" stop-color="#000" stop-opacity="0.55"/></radialGradient>`;
icons.pixel = {
  background: () => doc(pixelScreen(false), pixelDefs),
  mark: () => {
    const { size, cell, cells } = PIXEL;
    const x0 = Math.round(512 - (size * cell) / 2), y0 = Math.round(512 - (size * cell) / 2);
    const rects = cells.map(({ x, y, c }) => `<rect x="${x0 + x * cell}" y="${y0 + y * cell}" width="${cell}" height="${cell}" fill="${c}"/>`).join('');
    return doc(`<g shape-rendering="crispEdges">${rects}</g>`);
  },
  backgroundDark: () => doc(pixelScreen(true), pixelDefs),
};
