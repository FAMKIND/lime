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
  // LIME-54: these 4 presets are drawn in-house as inline SVG data URIs
  // — no third-party assets, no credit owed. (An earlier draft tried
  // sourcing real third-party tile files plus a matching pick-your-own
  // upload slot for them; the user dropped that direction on
  // 2026-09-30 and both were removed.)
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

  // ── Uploads (LIME-52-fix) ────────────────────────────────────
  // LIME-52's own upload mechanism (an opaque image, live mix-blend-mode
  // + low opacity) is why the user's PNG upload "didn't show" — an
  // ordinary, mostly-light photo under multiply blend at 10% opacity is
  // close to imperceptible against an already-light canvas (confirmed
  // live, reproduced with a representative test PNG, before writing any
  // of the code below: TEND.md has the exact before/after). Replaced
  // entirely: uploads are processed **once, on a canvas, at upload
  // time** into one of two treatments, never blended live against the
  // canvas at all.
  const UPLOAD_ACCEPTED_MIME = ['image/png', 'image/jpeg', 'image/webp', 'image/gif', 'image/svg+xml'];
  const UPLOAD_MAX_BYTES = 10 * 1024 * 1024;
  const UPLOAD_TEXTURE_MAX_DIM = 400;
  const UPLOAD_PHOTO_MAX_DIM = 1600;
  const UPLOAD_PHOTO_BLUR_PX = 10;
  const UPLOAD_SCRIM_FLOOR = 0.75;
  // LIME-52-fix5: below this, a Texture mask reads as an almost-uniform
  // tint rather than a texture — calibrated against the user's own 6
  // samples (ep_naturalwhite: 9.6, geometry2: 17.3, bananas: 19.2,
  // cork-board: 31.8, leaves: 43.0, ripples: 64.0) plus a live
  // before/after screenshot confirming 9.6 is genuinely invisible and
  // 17.3 is genuinely visible — 15 sits cleanly between the two.
  const UPLOAD_TEXTURE_MIN_STDDEV = 15;

  function validateUploadFile(file) {
    if (!UPLOAD_ACCEPTED_MIME.includes(file.type)) {
      return 'Please choose a PNG, JPG, WebP, GIF or SVG image (that looked like a ' + (file.type || 'file type this app doesn\'t recognise') + ').';
    }
    if (file.size > UPLOAD_MAX_BYTES) {
      return 'Please choose an image under 10 MB.';
    }
    return null;
  }

  // Small/square-ish images default to Texture; larger ones default to
  // Photo. Either way the user can switch via the toggle shown once an
  // upload exists.
  function defaultTreatmentFor(width, height) {
    const longest = Math.max(width, height);
    const ratio = width / height;
    const squareish = ratio >= 0.8 && ratio <= 1.25;
    return (longest <= 600 || squareish) ? 'texture' : 'photo';
  }

  function loadImageFromFile(file) {
    return new Promise((resolve, reject) => {
      const url = URL.createObjectURL(file);
      const img = new Image();
      img.onload = () => resolve(img);
      img.onerror = () => { URL.revokeObjectURL(url); reject(new Error('Could not read this image.')); };
      img.src = url;
    });
  }

  function relLum255(r, g, b) { return 0.2126 * r + 0.7152 * g + 0.0722 * b; }

  // Grayscale -> auto-level (stretch the real min/max to 0-255, so a
  // faint, low-contrast texture still registers once tinted) -> a mild
  // gamma curve (caps density: a busy source photo's alpha doesn't
  // flatten into solid noise once repeated at a small tile size) ->
  // downscale to <=400px. Alpha *is* the processed signal; RGB is set
  // to flat white since only alpha is ever read (mask-image's default
  // mode), matching every built-in preset.
  function processTexture(img) {
    const scale = Math.min(1, UPLOAD_TEXTURE_MAX_DIM / Math.max(img.width, img.height));
    const w = Math.max(1, Math.round(img.width * scale));
    const h = Math.max(1, Math.round(img.height * scale));
    const canvas = document.createElement('canvas');
    canvas.width = w; canvas.height = h;
    const ctx = canvas.getContext('2d');
    ctx.drawImage(img, 0, 0, w, h);
    const imageData = ctx.getImageData(0, 0, w, h);
    const data = imageData.data;
    const gray = new Uint8ClampedArray(w * h);
    let min = 255, max = 0;
    for (let i = 0; i < data.length; i += 4) {
      const g = Math.round(relLum255(data[i], data[i + 1], data[i + 2]));
      gray[i / 4] = g;
      if (g < min) min = g;
      if (g > max) max = g;
    }
    const range = Math.max(max - min, 1);
    let alphaSum = 0;
    const alphas = new Uint8ClampedArray(w * h);
    for (let i = 0; i < data.length; i += 4) {
      const levelled = (gray[i / 4] - min) / range; // 0-1, auto-levelled
      const alpha = Math.round(255 * Math.pow(levelled, 1.4)); // gentle gamma, not a hard clip
      data[i] = 255; data[i + 1] = 255; data[i + 2] = 255; data[i + 3] = alpha;
      alphas[i / 4] = alpha;
      alphaSum += alpha;
    }
    ctx.putImageData(imageData, 0, 0);
    // LIME-52-fix5: auto-levelling always stretches to a full 0-255
    // *range*, even for a barely-textured source — the built-in
    // pre-flight step LIME-52-fix5 was actually root-caused with. A
    // near-white "paper" texture (e.g. the user's own ep_naturalwhite
    // sample) auto-levels into a mask with plenty of range but almost
    // no *variation* — mean alpha 199.6, stddev only 9.6 — which tints
    // the whole canvas by a nearly uniform amount and reads as "nothing
    // happened," confirmed with a live before/after screenshot (TEND.md)
    // showing no visible difference at all. Mean alone doesn't predict
    // this (that same sample's mean was higher than several genuinely
    // visible ones) — standard deviation does, checked against all 6 of
    // the user's own samples plus a mid-tone photo, not guessed.
    const alphaMean = alphaSum / alphas.length;
    let varianceSum = 0;
    for (let i = 0; i < alphas.length; i++) varianceSum += (alphas[i] - alphaMean) ** 2;
    const alphaStddev = Math.sqrt(varianceSum / alphas.length);
    return { canvas, width: w, height: h, alphaStddev };
  }

  // Downscale to <=1600px with a blur baked in at processing time
  // (Canvas2D's own filter, applied once here — never a live CSS filter
  // repainted every frame). Also returns the *processed* image's own
  // luminance range (sampled from a tiny 32x32 copy — plenty for a
  // min/max scan) so applyPattern can compute a scrim that actually
  // guarantees contrast against how the photo really looks once
  // blurred, not the sharp original.
  function processPhoto(img) {
    const scale = Math.min(1, UPLOAD_PHOTO_MAX_DIM / Math.max(img.width, img.height));
    const w = Math.max(1, Math.round(img.width * scale));
    const h = Math.max(1, Math.round(img.height * scale));
    const canvas = document.createElement('canvas');
    canvas.width = w; canvas.height = h;
    const ctx = canvas.getContext('2d');
    ctx.filter = 'blur(' + UPLOAD_PHOTO_BLUR_PX + 'px)';
    ctx.drawImage(img, 0, 0, w, h);
    ctx.filter = 'none';
    const sample = document.createElement('canvas');
    sample.width = 32; sample.height = 32;
    sample.getContext('2d').drawImage(canvas, 0, 0, 32, 32);
    const data = sample.getContext('2d').getImageData(0, 0, 32, 32).data;
    let lumMin = 255, lumMax = 0;
    for (let i = 0; i < data.length; i += 4) {
      const g = relLum255(data[i], data[i + 1], data[i + 2]);
      if (g < lumMin) lumMin = g;
      if (g > lumMax) lumMax = g;
    }
    return { canvas, width: w, height: h, lumMin: Math.round(lumMin), lumMax: Math.round(lumMax) };
  }

  // LIME-52-fix3: rejects on a null blob instead of silently resolving
  // with one — toBlob() returns null (never throws) if the canvas is
  // too large for the browser's own memory/size ceiling, which
  // otherwise produced a garbage 0-byte "upload" that looked like it
  // had worked. Texture keeps PNG (alpha is the signal); Photo moved to
  // JPEG at ~0.85 (a full-size processed photo as PNG could run several
  // MB — slow to encode, slow to write to IndexedDB, and the likely
  // cause of at least some of the reported intermittent failures).
  function canvasToBlob(canvas, mime, quality) {
    return new Promise((resolve, reject) => {
      canvas.toBlob((blob) => {
        if (!blob) { reject(new Error('Couldn\'t process that image. Try a different PNG or JPG.')); return; }
        resolve(blob);
      }, mime || 'image/png', quality);
    });
  }

  // LIME-52-fix3: probed once per session (not per upload) — Firefox
  // private browsing can leave IndexedDB open()-able but reject a real
  // write, so this is a real put/delete round trip, not just whether
  // open() resolves (LocalAdapter.checkStorageAvailable). When it
  // fails, the processed result is kept in memory for the session
  // instead (an object URL, never written anywhere) rather than losing
  // the upload outright — sessionOnly on the returned pattern is how
  // the UI shows the one-time "won't persist" note.
  // LIME-52-fix5: only a TRUE (genuinely available) result is cached.
  // A false one — which now also covers a timeout, since
  // checkStorageAvailable never rejects — is deliberately NOT cached:
  // caching it would mean one transient failure (another tab briefly
  // blocking the database; a one-off slow disk) silently downgrades
  // every later upload for the rest of the session, with no way to
  // recover without a reload.
  let storageAvailablePromise = null;
  function isStorageAvailable() {
    if (storageAvailablePromise) return storageAvailablePromise;
    const probe = window.LimeStore.checkStorageAvailable().then((available) => {
      if (available) storageAvailablePromise = Promise.resolve(true);
      return available;
    });
    return probe;
  }

  // Stores a processed file the normal way (IndexedDB, a real path) when
  // storage works, or falls back to an in-memory object URL — used
  // directly as the "path" (LocalAdapter.getAttachmentUrl passes a
  // blob: path straight through) — when it doesn't.
  function storeUploadFile(file, available) {
    if (available) return window.LimeStore.uploadAttachment(file, { conversationId: 'appearance' });
    return Promise.resolve({ path: URL.createObjectURL(file), sessionOnly: true });
  }

  // Orchestrates the whole "file -> stored, processed pattern" pipeline.
  // Both treatments are processed and uploaded up front (not just the
  // chosen default) so the Texture<->Photo toggle can switch instantly
  // afterwards without re-reading the original file or reprocessing —
  // each treatment reads its own already-uploaded path.
  // Resolves { kind: 'upload', texturePath, photoPath, treatment,
  // isVector, width, height, lumMin?, lumMax?, sessionOnly? } or rejects
  // with a message safe to show the user directly.
  function processUploadFile(file, treatmentOverride) {
    const error = validateUploadFile(file);
    if (error) return Promise.reject(new Error(error));

    return isStorageAvailable().then((available) => {
      if (file.type === 'image/svg+xml') {
        // Already a vector mask, used exactly like a built-in preset — no
        // canvas processing needed or possible (SVG dimensions are
        // usually viewBox-relative, not meaningful pixel measurements),
        // and no Photo form (nothing to blur/cover with a flat vector).
        return storeUploadFile(file, available).then(({ path, sessionOnly }) => ({
          kind: 'upload', texturePath: path, photoPath: null, treatment: 'texture', isVector: true, width: 120, height: 120, sessionOnly,
        }));
      }

      return loadImageFromFile(file).then((img) => {
        let treatment = treatmentOverride || defaultTreatmentFor(img.naturalWidth, img.naturalHeight);
        const texture = processTexture(img);
        const photo = processPhoto(img);
        // LIME-52-fix5: a Texture default whose own processed mask is
        // too faint to read as a texture (see UPLOAD_TEXTURE_MIN_STDDEV,
        // above) auto-switches to Photo instead — "applied but
        // invisible" confirmed as this brief's actual root cause for
        // the user's own near-white sample images, not a hang or a
        // dialog that never opened (both directly tested and ruled
        // out). autoSwitchedToPhoto tells app.js to explain the switch
        // rather than silently doing something the user didn't ask for.
        let autoSwitchedToPhoto = false;
        if (treatment === 'texture' && texture.alphaStddev < UPLOAD_TEXTURE_MIN_STDDEV) {
          treatment = 'photo';
          autoSwitchedToPhoto = true;
        }
        URL.revokeObjectURL(img.src);
        return Promise.all([
          canvasToBlob(texture.canvas, 'image/png'),
          canvasToBlob(photo.canvas, 'image/jpeg', 0.85),
        ]).then(([textureBlob, photoBlob]) => {
          const textureFile = new File([textureBlob], 'pattern-texture.png', { type: 'image/png' });
          const photoFile = new File([photoBlob], 'pattern-photo.jpg', { type: 'image/jpeg' });
          return Promise.all([
            storeUploadFile(textureFile, available),
            storeUploadFile(photoFile, available),
          ]).then(([textureResult, photoResult]) => ({
            kind: 'upload',
            texturePath: textureResult.path,
            photoPath: photoResult.path,
            treatment,
            isVector: false,
            autoSwitchedToPhoto,
            sessionOnly: textureResult.sessionOnly || photoResult.sessionOnly,
            width: texture.width,
            height: texture.height,
            lumMin: photo.lumMin,
            lumMax: photo.lumMax,
          }));
        });
      });
    });
  }

  // The scrim opacity that guarantees >= 4.5:1 for on-canvas text
  // against the photo's own darkest AND lightest processed pixels —
  // computed fresh on every apply (cheap: a short numeric search, not
  // re-processing the image) from the lumMin/lumMax stored once at
  // upload time, so it stays correct across a later tone or mode
  // switch, not just the combination active when the photo was
  // uploaded. Floored at 75% per the brief regardless of how safe a
  // lower value would measure; prefers-reduced-transparency raises that
  // floor further.
  function computeScrimOpacity(scrimHex, textHex, lumMin, lumMax) {
    const scrim = hexToRgb01(scrimHex);
    const reducedTransparency = window.matchMedia && window.matchMedia('(prefers-reduced-transparency: reduce)').matches;
    const floor = reducedTransparency ? 0.9 : UPLOAD_SCRIM_FLOOR;
    for (let o = floor; o <= 1; o += 0.01) {
      const worstDark = mixOverGray(scrim, lumMin, o);
      const worstLight = mixOverGray(scrim, lumMax, o);
      if (contrastRatio(textHex, worstDark) >= 4.5 && contrastRatio(textHex, worstLight) >= 4.5) return Math.round(o * 100) / 100;
    }
    return 1;
  }
  function hexToRgb01(hex) { hex = hex.replace('#', ''); return [0, 2, 4].map((i) => parseInt(hex.slice(i, i + 2), 16)); }
  function mixOverGray(scrimRgb, gray, opacity) { return scrimRgb.map((c) => Math.round(c * opacity + gray * (1 - opacity))); }
  function relLumFromRgb([r, g, b]) { const c = [r, g, b].map((v) => { const s = v / 255; return s <= 0.03928 ? s / 12.92 : Math.pow((s + 0.055) / 1.055, 2.4); }); return 0.2126 * c[0] + 0.7152 * c[1] + 0.0722 * c[2]; }
  function contrastRatio(hexA, rgbB) { const la = relLumFromRgb(hexToRgb01(hexA)), lb = relLumFromRgb(rgbB); const hi = Math.max(la, lb), lo = Math.min(la, lb); return (hi + 0.05) / (lo + 0.05); }

  function applyPattern(pattern) {
    const root = document.documentElement.style;
    const theme = document.documentElement.getAttribute('data-theme') === 'dark' ? 'dark' : 'light';
    const kind = pattern && pattern.kind;
    const intensity = PATTERN_INTENSITY[(pattern && pattern.intensity) || 'low'];

    root.removeProperty('--lime-pattern-mask');
    root.removeProperty('--lime-pattern-tint');
    root.removeProperty('--lime-pattern-size');
    root.removeProperty('--lime-pattern-image');
    root.removeProperty('--lime-pattern-scrim');
    root.removeProperty('--lime-pattern-blend'); // LIME-52's own live-blend mechanism, retired below
    root.removeProperty('--lime-pattern-opacity');
    document.documentElement.removeAttribute('data-pattern-treatment');

    if (kind === 'preset') {
      root.setProperty('--lime-pattern-mask', 'url("' + patternMaskDataUri(pattern.presetId) + '")');
      root.setProperty('--lime-pattern-size', PATTERN_TILE_SIZE[pattern.presetId] || '24px 24px');
      applyPresetTint(root, theme, intensity.tintPct);
    } else if (kind === 'upload' && window.LimeStore) {
      const path = pattern.treatment === 'photo' ? pattern.photoPath : pattern.texturePath;
      if (!path) return;
      LimeStore.getAttachmentUrl(path).then((url) => {
        if (pattern.treatment === 'photo') {
          document.documentElement.setAttribute('data-pattern-treatment', 'photo');
          const canvasHex = getComputedStyle(document.documentElement).getPropertyValue('--seed-soil-0').trim() || (theme === 'dark' ? '#131B17' : '#F9F8F4');
          const textHex = getComputedStyle(document.documentElement).getPropertyValue('--soil-text-muted').trim() || '#787068';
          const scrimOpacity = computeScrimOpacity(canvasHex, textHex, pattern.lumMin != null ? pattern.lumMin : 0, pattern.lumMax != null ? pattern.lumMax : 255);
          const scrimRgba = 'rgba(' + hexToRgb01(canvasHex).join(',') + ',' + scrimOpacity + ')';
          root.setProperty('--lime-pattern-image', 'url("' + url + '")');
          root.setProperty('--lime-pattern-scrim', 'linear-gradient(' + scrimRgba + ',' + scrimRgba + ')');
        } else {
          // 'texture' (raster, processed; or an uploaded SVG used as-is)
          root.setProperty('--lime-pattern-mask', 'url("' + url + '")');
          root.setProperty('--lime-pattern-size', pattern.isVector ? '120px 120px' : (pattern.width || 120) + 'px ' + (pattern.height || 120) + 'px');
          applyPresetTint(root, theme, intensity.tintPct);
        }
      }).catch(console.error);
    }
  }

  // Shared by presets, user tiles, and upload-texture — the one formula
  // every mask-based pattern tints through.
  function applyPresetTint(root, theme, tintPct) {
    const tintTarget = theme === 'dark' ? 'white' : 'var(--seed-soil-900)';
    root.setProperty('--lime-pattern-tint', 'color-mix(in srgb, ' + tintTarget + ' ' + tintPct + '%, transparent)');
  }

  function init() {
    const appearance = window.LimeStore ? LimeStore.getAppearance() : { canvas: 'warm', theme: 'system', pattern: null };
    applyCanvas(appearance.canvas);
    applyTheme(appearance.theme); // also applies the stored pattern, above
    wireSystemThemeListener();
  }

  return {
    CANVAS_P, CANVAS_LABELS, makeCanvasRamp, applyCanvas, applyTheme, resolveTheme, init,
    processUploadFile, validateUploadFile, defaultTreatmentFor,
    PATTERN_PRESETS, PATTERN_INTENSITY, patternMaskDataUri, applyPattern,
  };
})();

window.LimeAppearance = LimeAppearance;
