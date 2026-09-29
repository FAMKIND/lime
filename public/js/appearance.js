'use strict';

// Appearance (LIME-50 canvas, LIME-51 mode, LIME-52 pattern) — one
// app-wide canvas tone, retuning Seed's own neutral (soil) ramp from one
// choice so every surface, panel, text and border derived from it
// updates together; light/dark/system mode, setting data-theme on
// <html> before Seed's own comprehensive [data-theme="dark"] token
// block (tokens.css) takes over almost everything else; and a subtle
// background pattern (preset or uploaded), one fixed layer behind every
// panel (body::before, lime.css).
//
// hexToHsl/hslToHex/clamp/makeCanvasRamp and the CANVAS_P preset data
// below are ported from Seed's own brand customiser
// (vendor/seed/components/layout/layout.html ~48-88), with attribution
// per the brief — vendor/ itself can't be edited, and Lime needs this
// logic to run against its own stored preference, not Seed's demo-only
// localStorage keys. Not modified beyond the port itself.
const LimeAppearance = (function () {
  function hexToHsl(hex) {
    hex = hex.replace('#', '');
    const r = parseInt(hex.slice(0, 2), 16) / 255;
    const g = parseInt(hex.slice(2, 4), 16) / 255;
    const b = parseInt(hex.slice(4, 6), 16) / 255;
    const max = Math.max(r, g, b), min = Math.min(r, g, b);
    let h, s;
    const l = (max + min) / 2;
    if (max === min) {
      h = s = 0;
    } else {
      const d = max - min;
      s = l > 0.5 ? d / (2 - max - min) : d / (max + min);
      switch (max) {
        case r: h = (g - b) / d + (g < b ? 6 : 0); break;
        case g: h = (b - r) / d + 2; break;
        default: h = (r - g) / d + 4;
      }
      h /= 6;
    }
    return [h * 360, s * 100, l * 100];
  }

  function hslToHex(h, s, l) {
    s /= 100; l /= 100;
    const a = s * Math.min(l, 1 - l);
    const f = (n) => { const k = (n + h / 30) % 12; return l - a * Math.max(Math.min(k - 3, 9 - k, 1), -1); };
    return '#' + [f(0), f(8), f(4)].map((x) => Math.round(x * 255).toString(16).padStart(2, '0')).join('').toUpperCase();
  }

  function clamp(v, lo, hi) { return Math.max(lo, Math.min(hi, v)); }

  // Canvas ramp: near-whites have misleadingly high HSL saturation.
  // Attenuate heavily so dark stops stay warm-grey, never a saturated
  // version of the chosen hue — Seed's own colour-theory safeguard,
  // ported verbatim.
  function makeCanvasRamp(hex) {
    const hsl = hexToHsl(hex), h = hsl[0], l = hsl[2], s = Math.min(hsl[1] * 0.3, 8);
    return [hex.toUpperCase(),
      hslToHex(h, s * 0.8, clamp(l - 3, 88, 96)), hslToHex(h, s * 0.9, clamp(l - 8, 78, 92)),
      hslToHex(h, s * 1.0, clamp(l - 17, 65, 87)), hslToHex(h, s * 1.1, clamp(l - 27, 52, 80)),
      hslToHex(h, s * 1.2, clamp(l - 40, 38, 68)), hslToHex(h, s * 1.3, clamp(l - 52, 24, 55)),
      hslToHex(h, s * 1.3, clamp(l - 62, 14, 43)), hslToHex(h, s * 1.2, clamp(l - 68, 7, 30)),
      hslToHex(h, s * 1.1, clamp(l - 73, 3, 18)), hslToHex(h, s * 1.1, clamp(l - 70, 5, 22))];
  }

  // Seed's own 5 presets, ported verbatim (11 stops each, matching
  // SOIL_KEYS below in order) — 'warm' is byte-identical to Lime's own
  // live raw ramp (tokens.css), so selecting it changes nothing.
  // 'lemon'/'sage'/'lilac' are LIME-50's own 3 additions, generated
  // (not hand-picked) via makeCanvasRamp from a chosen pale base hex —
  // 'sage' needed its base hex tuned twice: once in LIME-50 (#EAF1E6 ->
  // #E3EDDC, to clear muted-text-vs-canvas) and again in LIME-50-fix
  // (#E3EDDC -> #D8E6D0), once --lime-layer-surface (lime.css) — a
  // slightly darker layer than bare canvas — became what muted text
  // actually sits on; 'lemon'/'lilac' cleared both rounds on the first
  // try. See TEND.md's own LIME-50/LIME-50-fix entries for the measured
  // tables.
  const CANVAS_P = {
    warm: ['#F9F8F4', '#E8E4DB', '#D8D3C8', '#C0BAB0', '#A09890', '#787068', '#504840', '#342E28', '#221E18', '#141210', '#1C1B18'],
    'cool-gray': ['#F8F8F8', '#EBEBEB', '#DEDEDE', '#CECECE', '#ABABAB', '#888888', '#555555', '#333333', '#1F1F1F', '#111111', '#1A1A1A'],
    'warm-cream': ['#FDF8F0', '#EEE8DC', '#DDD6C8', '#C8BFAE', '#A8A090', '#857C6C', '#5A5248', '#3D372E', '#26221B', '#171410', '#201E18'],
    'blue-tint': ['#F0F4F8', '#E0E8F0', '#CCD9E8', '#AABDD0', '#8AA0B8', '#6A8098', '#4A6070', '#2D4055', '#1A2838', '#0E1620', '#182030'],
    'pure-white': ['#FFFFFF', '#F0F0F0', '#E0E0E0', '#CCCCCC', '#AAAAAA', '#888888', '#555555', '#333333', '#1A1A1A', '#0D0D0D', '#1A1A1A'],
    lemon: makeCanvasRamp('#FBF3D0'),
    sage: makeCanvasRamp('#D8E6D0'),
    lilac: makeCanvasRamp('#F1ECF6'),
  };

  const CANVAS_LABELS = {
    warm: 'Warm', 'cool-gray': 'Cool gray', 'warm-cream': 'Warm cream',
    'blue-tint': 'Blue tint', 'pure-white': 'Pure white',
    lemon: 'Lemon', sage: 'Sage', lilac: 'Lilac',
  };

  // Matches Seed's own SOIL_K order. --seed-soil-900 is deliberately
  // absent — Lime pins it to a fixed theme-invariant ink (lime.css,
  // its own comment explains why: the avatar identity system reads it
  // directly) and a canvas tone must never move it.
  const SOIL_KEYS = ['--seed-soil-0', '--seed-soil-100', '--seed-soil-200', '--seed-soil-300', '--seed-soil-400', '--seed-soil-500', '--seed-soil-600', '--seed-soil-700', '--seed-soil-800', '--seed-soil-950'];
  // Same order as SOIL_KEYS, skipping index 9 (900) out of each preset's
  // own 11-value array (index order: 0,100,200,...,900,950).
  const SOIL_RAMP_INDEXES = [0, 1, 2, 3, 4, 5, 6, 7, 8, 10];

  function applyCanvas(name) {
    const ramp = CANVAS_P[name] || CANVAS_P.warm;
    const root = document.documentElement.style;
    SOIL_KEYS.forEach((key, i) => root.setProperty(key, ramp[SOIL_RAMP_INDEXES[i]]));
  }

  // LIME-51 — mode: 'light' | 'dark' | 'system'.
  //
  // The raw localStorage key (not LimeStore, which loads asynchronously)
  // is what index.html/login.html/signup.html's own inline <head>
  // scripts read to set data-theme before first paint, avoiding a flash
  // of light theme. applyTheme keeps that key in sync every time it
  // runs — the head scripts' own fallback ('system' when the key is
  // absent) matches DEFAULT_APPEARANCE.theme (store.js) exactly, so a
  // brand-new profile with no stored choice yet behaves identically
  // whichever one happens to run first.
  const THEME_STORAGE_KEY = 'lime-theme';
  let systemThemeQuery = null;

  function resolveTheme(mode) {
    if (mode === 'dark' || mode === 'light') return mode;
    return (window.matchMedia && window.matchMedia('(prefers-color-scheme: dark)').matches) ? 'dark' : 'light';
  }

  function applyTheme(mode) {
    document.documentElement.setAttribute('data-theme', resolveTheme(mode));
    try { localStorage.setItem(THEME_STORAGE_KEY, mode); } catch (e) { /* private mode, etc. — visual apply above still worked */ }
    // An uploaded pattern's own blend mode depends on the resolved theme
    // (multiply in light, screen in dark, per the brief) — reapply
    // whatever pattern is currently stored so a theme switch (including
    // a live System follow) updates it too, not just a fresh pattern pick.
    if (window.LimeStore) applyPattern(LimeStore.getAppearance().pattern);
  }

  // Installed once, ever — re-reads the stored mode fresh on every fire
  // rather than closing over whatever mode was active when this was set
  // up, since the user can switch into or out of 'system' at any time
  // after this listener already exists.
  function wireSystemThemeListener() {
    if (systemThemeQuery || !window.matchMedia) return;
    systemThemeQuery = window.matchMedia('(prefers-color-scheme: dark)');
    const onChange = () => {
      let mode;
      try { mode = localStorage.getItem(THEME_STORAGE_KEY) || 'system'; } catch (e) { mode = 'system'; }
      if (mode === 'system') applyTheme('system');
    };
    if (systemThemeQuery.addEventListener) systemThemeQuery.addEventListener('change', onChange);
    else if (systemThemeQuery.addListener) systemThemeQuery.addListener(onChange); // older Safari/Firefox
  }

  // LIME-52 — one fixed background layer (body::before, lime.css) behind
  // every panel, in one of three states: no pattern; a preset, rendered
  // as a low-alpha ink tint masked into the pattern's own shape (so it
  // recolours with the tone and mode automatically, no separate light/
  // dark asset needed); or an uploaded image, blended against body's own
  // canvas colour via mix-blend-mode (multiply in light, screen in dark
  // — the brief's own explicit choice, since those two modes darken/
  // lighten toward the backdrop rather than fighting it).
  //
  // public/assets/patterns/ was empty when this ran — no Subtle
  // Patterns tiles to use — so all 4 presets here are generated inline
  // (SVG data URIs), the brief's own documented fallback. Nothing here
  // is sourced from Subtle Patterns, so no CC BY-SA credit line is
  // shown; TEND.md/data-model.md both flag this so a later brief adding
  // real Subtle Patterns assets knows to add the credit then, not now.
  const PATTERN_PRESETS = [
    { id: 'dots', label: 'Dots' },
    { id: 'grid', label: 'Grid' },
    { id: 'diagonal', label: 'Diagonal' },
    { id: 'noise', label: 'Noise' },
  ];
  const PATTERN_TILE_SIZE = { dots: '24px 24px', grid: '24px 24px', diagonal: '24px 24px', noise: '64px 64px' };
  // Low is the default the moment a pattern is first picked (the
  // brief's own "user-invisible-by-default intensity"). Both levels
  // verified against on-canvas text (date dividers, sender names,
  // times) at >= 4.5:1 across all 8 canvas tones plus dark before
  // shipping either value — computed analytically (TEND.md's own
  // table), not screenshot-sampled: 11% failed dark mode specifically
  // (4.49:1, the darkest canvas of the set, so it had the least room),
  // found while writing that check. 9% clears it with real margin
  // (4.77:1) without needing a separate per-theme value.
  const PATTERN_INTENSITY = {
    low: { tintPct: 6, blendOpacity: 0.10 },
    medium: { tintPct: 9, blendOpacity: 0.18 },
  };

  // Mask images use the alpha channel (the default mask mode for a
  // referenced image, not luminance) — white shapes on a transparent
  // ground are exactly "shape = visible, gap = not," independent of
  // whatever colour --lime-pattern-tint below actually is.
  function patternMaskSvg(presetId) {
    if (presetId === 'dots') {
      return '<svg xmlns="http://www.w3.org/2000/svg" width="24" height="24"><circle cx="4" cy="4" r="1.6" fill="#fff"/><circle cx="16" cy="16" r="1.6" fill="#fff"/></svg>';
    }
    if (presetId === 'grid') {
      return '<svg xmlns="http://www.w3.org/2000/svg" width="24" height="24"><path d="M0 0 H24 M0 12 H24 M0 0 V24 M12 0 V24" stroke="#fff" stroke-width="1"/></svg>';
    }
    if (presetId === 'diagonal') {
      return '<svg xmlns="http://www.w3.org/2000/svg" width="24" height="24"><path d="M-4 4 L4 -4 M-4 28 L28 -4 M16 28 L28 16" stroke="#fff" stroke-width="1.5"/></svg>';
    }
    // 'noise' — a real fractal-noise texture (feTurbulence), not a
    // hand-placed scatter standing in for one; feColorMatrix maps its
    // own luminance straight onto the output alpha, so the mask's
    // "shape" is the noise field itself, at every grey level, not just
    // fully-on/fully-off.
    return '<svg xmlns="http://www.w3.org/2000/svg" width="64" height="64">'
      + '<filter id="n"><feTurbulence type="fractalNoise" baseFrequency="0.9" numOctaves="2" stitchTiles="stitch" result="t"/>'
      + '<feColorMatrix in="t" type="matrix" values="0 0 0 0 1  0 0 0 0 1  0 0 0 0 1  0 0 0 0.6 0"/></filter>'
      + '<rect width="64" height="64" filter="url(#n)"/></svg>';
  }

  function patternMaskDataUri(presetId) {
    return 'data:image/svg+xml,' + encodeURIComponent(patternMaskSvg(presetId));
  }

  function applyPattern(pattern) {
    const root = document.documentElement.style;
    const theme = document.documentElement.getAttribute('data-theme') === 'dark' ? 'dark' : 'light';
    const kind = pattern && pattern.kind;
    const intensity = PATTERN_INTENSITY[(pattern && pattern.intensity) || 'low'];

    root.removeProperty('--lime-pattern-mask');
    root.removeProperty('--lime-pattern-tint');
    root.removeProperty('--lime-pattern-image');
    root.removeProperty('--lime-pattern-blend');
    root.removeProperty('--lime-pattern-opacity');

    if (kind === 'preset') {
      root.setProperty('--lime-pattern-mask', 'url("' + patternMaskDataUri(pattern.presetId) + '")');
      root.setProperty('--lime-pattern-size', PATTERN_TILE_SIZE[pattern.presetId] || '24px 24px');
      // Tints toward ink in light, white in dark — matching LIME-50-fix's
      // own established convention for every other tone-relative layer
      // (surface/hover/active). Mixing toward ink unconditionally (an
      // earlier draft of this function did) would darken an
      // already-dark canvas further in dark mode instead of lifting it,
      // fighting that convention rather than following it — found while
      // writing this brief's own contrast verification, not visually.
      const tintTarget = theme === 'dark' ? 'white' : 'var(--seed-soil-900)';
      root.setProperty('--lime-pattern-tint', 'color-mix(in srgb, ' + tintTarget + ' ' + intensity.tintPct + '%, transparent)');
    } else if (kind === 'upload' && pattern.path && window.LimeStore) {
      // getAttachmentUrl is async (IndexedDB) — applies once resolved,
      // same pattern LIME-45's own photo backgrounds used for the same
      // reason (a fresh object URL isn't available synchronously).
      LimeStore.getAttachmentUrl(pattern.path).then((url) => {
        root.setProperty('--lime-pattern-image', 'url("' + url + '")');
        root.setProperty('--lime-pattern-blend', theme === 'dark' ? 'screen' : 'multiply');
        root.setProperty('--lime-pattern-opacity', String(intensity.blendOpacity));
      }).catch(console.error);
    }
  }

  function init() {
    const appearance = window.LimeStore ? LimeStore.getAppearance() : { canvas: 'warm', theme: 'system', pattern: null };
    applyCanvas(appearance.canvas);
    applyTheme(appearance.theme); // also applies the stored pattern, above
    wireSystemThemeListener();
  }

  return {
    CANVAS_P, CANVAS_LABELS, makeCanvasRamp, applyCanvas, applyTheme, resolveTheme, init,
    PATTERN_PRESETS, PATTERN_INTENSITY, patternMaskDataUri, applyPattern,
  };
})();

window.LimeAppearance = LimeAppearance;
