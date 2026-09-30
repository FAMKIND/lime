'use strict';

// LIME-51: theme is now set by index.html's own inline <head> script
// (before first paint) and confirmed/corrected once the real profile
// loads (LimeAppearance.init(), called from initMessagesList below) —
// this raw, unconditional localStorage read (never written by anything,
// confirmed before removing it) predates both and is replaced by them.

// ── Seed data: contacts list + thread (LIME-06) ──────────
// Promoted to top-level (LIME-11), not IIFE-private — the new replies
// panel needs these same pure helpers and can't reach inside the LIME-06
// closure's scope. None of them depend on that closure's own state
// (list/thread/me/etc.), so hoisting changes nothing about how the
// contacts/thread code below already uses them.
//
// LIME-24b: the contacts/thread IIFE further down no longer runs
// synchronously at parse time — it waits on `LimeStore.init()` (the store
// itself is a separate <script>, loaded before this one) — so nothing
// past it in this file can assume its DOM (the list rows, the initial
// thread) already exists yet. The two things that used to depend on
// that (the Recent-row highlight and the mobile view router's contact
// click) are delegated listeners now instead of one-time scans, exactly
// so they don't care when — or whether — a given row exists yet.
const PRESENCE = { online: 'active', busy: 'busy', offline: 'away' };
const PRESENCE_LABEL = { active: 'Active', busy: 'Busy', away: 'Away' };

function presenceFor(status) {
  return PRESENCE[status] || 'away';
}

function shortName(name) {
  const parts = name.trim().split(/\s+/);
  return parts.length < 2 ? name : parts[0] + ' ' + parts[parts.length - 1][0];
}

// Just the first name — used for a group row's "Jean: " sender prefix
// (LIME-19b). A separate, tinier helper than shortName's "First L." form;
// intentionally duplicated (not shared) with the equivalent used inside
// store.js's own getConversationTitle — both are one-liners private to
// their own file, not worth a shared module for.
function firstName(displayName) {
  return displayName.trim().split(/\s+/)[0];
}

function escapeHtml(str) {
  return String(str).replace(/[&<>"']/g, (c) => ({
    '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;',
  }[c]));
}

// LIME-51 — shared by both places Mode appears (the header popover and
// Settings -> Preferences -> Appearance, "the same controls" per
// LIME-50's own precedent), so top-level rather than private to either
// one's own IIFE, the same reasoning escapeHtml above is top-level for.
const THEME_MODES = [
  { id: 'light', label: 'Light' },
  { id: 'dark', label: 'Dark' },
  { id: 'system', label: 'System' },
];

function modeTabsHtml(idPrefix, currentMode) {
  return '<div class="seed-tabs seed-tabs--pill seed-tabs--sm" role="tablist" aria-label="Mode" id="' + idPrefix + '-mode-tabs">'
    + THEME_MODES.map((m) => {
      const active = m.id === currentMode;
      return '<button type="button" class="seed-tab' + (active ? ' seed-tab--active' : '') + '" role="tab" aria-selected="' + active + '" data-theme-mode="' + m.id + '">' + m.label + '</button>';
    }).join('')
    + '</div>';
}

// Canvas tones are light-mode-only (Seed's own convention, per the
// brief) — disabled, not hidden, with the reason stated inline rather
// than just missing, so it reads as "not available right now" instead
// of looking like the feature quietly vanished.
function canvasDisabledNoticeHtml() {
  return '<p class="lime-appearance-disabled-note">Tones apply in light mode.</p>';
}

// LIME-52-fix — one shared picker for Canvas and Pattern, used
// identically by the header popover (#appearance-menu) and Settings ->
// Preferences -> Appearance. Not two copies (LIME-50/52's own
// duplicated appearanceSwatchButtonHtml/canvasSwatchButtonHtml,
// renderAppearanceMenu's Canvas section/renderPreferencesSection's
// Canvas section) — the brief's own explicit ask.
function canvasSwatchButtonHtml(name, hex, isSelected, disabled) {
  return '<button type="button" class="lime-appearance-swatch' + (isSelected ? ' is-selected' : '') + '" data-canvas="' + name + '" style="background:' + hex + '" title="' + escapeHtml(LimeAppearance.CANVAS_LABELS[name]) + '" aria-label="' + escapeHtml(LimeAppearance.CANVAS_LABELS[name]) + '"' + (isSelected ? ' aria-current="true"' : '') + (disabled ? ' disabled' : '') + '></button>';
}

// LIME-52-fix2: `compact` shrinks the shared tile size (36px -> 28px,
// via the --lime-tile-size variable a --compact grid modifier sets) —
// the header popover's own ask ("make the min width smaller"); Settings
// keeps the original, larger size, same shared component either way.
function canvasGridHtml(isDark, compact) {
  const current = LimeStore.getAppearance().canvas;
  return '<div class="lime-appearance-grid' + (compact ? ' lime-appearance-grid--compact' : '') + (isDark ? ' is-disabled' : '') + '">'
    + Object.keys(LimeAppearance.CANVAS_P).map((name) => canvasSwatchButtonHtml(name, LimeAppearance.CANVAS_P[name][0], name === current, isDark)).join('')
    + '</div>';
}

// "None" is its own tile (a plain thumb, not a missing one) so every
// option — including turning patterns off — lives in the same grid,
// same reasoning the canvas swatches don't have a separate "no tone"
// control either. Clicking it also replaces LIME-52's separate
// "Remove" text button for an active upload (per the brief's own
// extension: "None" now does that job for every pattern kind).
function patternNoneThumbHtml(isSelected) {
  return '<button type="button" class="lime-pattern-thumb lime-pattern-thumb--none' + (isSelected ? ' is-selected' : '') + '" data-pattern-kind="none" title="None" aria-label="None"' + (isSelected ? ' aria-current="true"' : '') + '></button>';
}

function patternPresetThumbHtml(preset, isSelected) {
  const uri = LimeAppearance.patternMaskDataUri(preset.id);
  return '<button type="button" class="lime-pattern-thumb' + (isSelected ? ' is-selected' : '') + '" data-pattern-kind="preset" data-pattern-preset="' + preset.id + '" style="mask-image:url(&quot;' + uri + '&quot;);-webkit-mask-image:url(&quot;' + uri + '&quot;)" title="' + escapeHtml(preset.label) + '" aria-label="' + escapeHtml(preset.label) + '"' + (isSelected ? ' aria-current="true"' : '') + '></button>';
}

// LIME-52-fix: any tile the user has dropped into public/assets/patterns/
// (LimeAppearance.detectUserPatternTiles(), file://-safe <img>
// load-probing — no directory listing or fetch works over file://).
function patternUserTileThumbHtml(tile, isSelected) {
  return '<button type="button" class="lime-pattern-thumb' + (isSelected ? ' is-selected' : '') + '" data-pattern-kind="user-tile" data-pattern-tile-id="' + escapeHtml(tile.id) + '" style="mask-image:url(&quot;' + tile.src + '&quot;);-webkit-mask-image:url(&quot;' + tile.src + '&quot;)" title="' + escapeHtml(tile.label) + '" aria-label="' + escapeHtml(tile.label) + '"' + (isSelected ? ' aria-current="true"' : '') + '></button>';
}

// LIME-52-fix2: an active upload's tile is a plain, unclipped wrapper
// (.lime-pattern-tile) around two SIBLING children — the fill
// (.lime-pattern-tile__preview) and the delete button — not the button
// nested inside the masked/background-imaged element. LIME-52-fix's own
// bug: a mask-image (or any background) clips the element it's on,
// including any children rendered inside it, which is exactly what cut
// the x off. Keeping the wrapper itself free of any mask/background is
// what keeps the x fully paintable and the preview showing the real
// image instead of a plain filled square. The actual URL only resolves
// async (LimeStore.getAttachmentUrl), so the preview renders as a
// placeholder carrying data-attachment-path/-style and relies on
// paintAttachments() (below) to fill it in, same two-step pattern every
// other attachment thumbnail in this app already uses.
// LIME-52-fix3: `busy` shows a processing state on the "+" tile itself
// (disabled, a spinner glyph instead of the plus, a "Processing…"
// title) — real feedback for however long a large photo's own decode +
// canvas processing + upload actually takes, and a native `disabled`
// blocks a second pick outright, on top of handleAppearanceClick's own
// uploadBusy check.
function patternUploadThumbHtml(pattern, busy) {
  const isUpload = pattern && pattern.kind === 'upload';
  const addTile = '<button type="button" class="lime-pattern-thumb lime-pattern-thumb--upload' + (busy ? ' is-busy' : '') + '" data-pattern-action="upload" title="' + (busy ? 'Processing…' : 'Upload your own…') + '" aria-label="' + (busy ? 'Processing…' : 'Upload your own…') + '"' + (busy ? ' disabled aria-busy="true"' : '') + '>' + (busy ? '<span class="lime-spinner"></span>' : '<span class="dew dew-plus"></span>') + '</button>';
  if (!isUpload) return addTile;
  const isPhoto = pattern.treatment === 'photo';
  const previewPath = isPhoto ? pattern.photoPath : pattern.texturePath;
  const previewTile = '<span class="lime-pattern-tile is-selected" title="Your upload" aria-label="Your upload" aria-current="true">'
    + '<span class="lime-pattern-tile__preview" data-attachment-path="' + escapeHtml(previewPath || '') + '" data-attachment-style="' + (isPhoto ? 'photo-bg' : 'mask') + '"></span>'
    + '<button type="button" class="lime-pattern-tile__delete" data-pattern-action="remove-upload" title="Remove upload" aria-label="Remove upload">&times;</button>'
    + '</span>';
  return previewTile + addTile;
}

function patternGridHtml(pattern, userTiles, compact) {
  const kind = (pattern && pattern.kind) || 'none';
  const tiles = patternNoneThumbHtml(kind === 'none')
    + LimeAppearance.PATTERN_PRESETS.map((p) => patternPresetThumbHtml(p, kind === 'preset' && pattern.presetId === p.id)).join('')
    + (userTiles || []).map((t) => patternUserTileThumbHtml(t, kind === 'user-tile' && pattern.tileId === t.id)).join('')
    + patternUploadThumbHtml(pattern, uploadBusy);
  return '<div class="lime-appearance-grid' + (compact ? ' lime-appearance-grid--compact' : '') + '">' + tiles + '</div>';
}

function intensityTabsHtml(current) {
  const levels = [{ id: 'low', label: 'Low' }, { id: 'medium', label: 'Medium' }];
  return '<div class="seed-tabs seed-tabs--pill seed-tabs--sm" role="tablist" aria-label="Intensity">'
    + levels.map((l) => {
      const active = l.id === (current || 'low');
      return '<button type="button" class="seed-tab' + (active ? ' seed-tab--active' : '') + '" role="tab" aria-selected="' + active + '" data-pattern-intensity="' + l.id + '">' + l.label + '</button>';
    }).join('')
    + '</div>';
}

// LIME-52-fix: shown only once an upload exists — switches between the
// two processed forms (appearance.js's own processTexture/processPhoto)
// without needing to re-pick the file.
function treatmentTabsHtml(current) {
  const options = [{ id: 'texture', label: 'Texture' }, { id: 'photo', label: 'Photo' }];
  return '<div class="seed-tabs seed-tabs--pill seed-tabs--sm" role="tablist" aria-label="Treatment">'
    + options.map((o) => {
      const active = o.id === current;
      return '<button type="button" class="seed-tab' + (active ? ' seed-tab--active' : '') + '" role="tab" aria-selected="' + active + '" data-pattern-treatment-toggle="' + o.id + '">' + o.label + '</button>';
    }).join('')
    + '</div>';
}

// Intensity applies to every pattern kind (preset, user tile, or an
// uploaded Texture); the Treatment toggle only ever applies to an
// upload — Photo has no "intensity" (it's a full-bleed layer, not a
// low-alpha tint), so it replaces the intensity tabs rather than
// sitting alongside them once an upload is a Photo.
function patternControlsHtml(pattern) {
  if (!pattern || pattern.kind === 'none') return '';
  if (pattern.kind === 'upload') {
    // An uploaded SVG has no Photo form (nothing to blur/cover with a
    // flat vector) — no toggle, just the intensity tabs every other
    // mask-based kind gets.
    if (pattern.isVector) return '<div class="lime-pattern-controls">' + intensityTabsHtml(pattern.intensity) + '</div>';
    return '<div class="lime-pattern-controls">'
      + (pattern.treatment === 'photo' ? '' : intensityTabsHtml(pattern.intensity))
      + treatmentTabsHtml(pattern.treatment || 'texture')
      + '</div>';
  }
  return '<div class="lime-pattern-controls">' + intensityTabsHtml(pattern.intensity) + '</div>';
}

// Resolved once at startup (file:// has no directory listing, so
// detection is <img> load-probing — see appearance.js's own
// detectUserPatternTiles). Empty until/unless it resolves — both
// pickers below just render the built-ins plus None/Upload until then;
// by the time either one is first opened (a user interaction, not page
// load) this has almost always already settled.
let cachedUserPatternTiles = [];
if (window.LimeAppearance) {
  LimeAppearance.detectUserPatternTiles().then((tiles) => { cachedUserPatternTiles = tiles; }).catch(console.error);
}

// LIME-52-fix3 — reliable pattern uploads.
// uploadActiveSurface: which caller (popover or Settings) started the
// current pick — set right before the persistent #pattern-upload-input
// is clicked, read by its own change listener (below), since the input
// itself carries no per-surface context of its own (it's one shared
// element, not rendered fresh per surface any more).
// uploadJobToken/uploadBusy: "one job at a time, latest wins" — a stale
// job (superseded by a second pick before the first finished) discards
// its own result instead of racing the newer one; uploadBusy blocks a
// second pick outright and drives the Upload tile's "Processing…" state.
let uploadActiveSurface = null;
let uploadJobToken = 0;
let uploadBusy = false;

// Deletes whichever of a REPLACED upload's blobs the new state doesn't
// still reference (LIME-52-fix3's own finding: IndexedDB grew by two
// full blobs — Texture + Photo — on every single attempt, including
// ones immediately replaced or cleared). A session-only (blob:) path
// was never written to IndexedDB, so there's nothing to delete for it —
// LimeStore.deleteAttachment already no-ops on those.
function deleteSupersededUploadBlobs(previousPattern, nextPattern) {
  if (!previousPattern || previousPattern.kind !== 'upload') return;
  const nextTexture = nextPattern && nextPattern.texturePath;
  const nextPhoto = nextPattern && nextPattern.photoPath;
  if (previousPattern.texturePath && previousPattern.texturePath !== nextTexture) {
    LimeStore.deleteAttachment(previousPattern.texturePath).catch(console.error);
  }
  if (previousPattern.photoPath && previousPattern.photoPath !== nextPhoto) {
    LimeStore.deleteAttachment(previousPattern.photoPath).catch(console.error);
  }
}

// Runs one upload job end to end: process -> apply live -> persist ->
// clean up the blobs it replaced -> re-render. Never fails silently —
// every rejection path (a validation error, a decode failure, a null
// blob from canvasToBlob, an IndexedDB write failure) reaches setError
// with a message safe to show directly, falling back to a generic one
// if a rejection somehow carries none. A stale, superseded job (token
// mismatch by the time it resolves) discards its own result quietly —
// that's an expected supersession, not a failure, so it isn't reported
// as one.
function runPatternUpload(file, surface) {
  const token = ++uploadJobToken;
  uploadBusy = true;
  surface.rerender();
  const previousPattern = LimeStore.getAppearance().pattern;
  // setError is called strictly AFTER rerender() in every branch below,
  // never before/alongside it — rerender() fully replaces the pane's
  // innerHTML (a fresh, blank error slot each time), so a message set
  // any earlier gets silently wiped the instant the busy-state render
  // that necessarily follows it runs. This was itself a real "fails
  // silently" bug caught while verifying LIME-52-fix3's own fix.
  LimeAppearance.processUploadFile(file).then((pattern) => {
    if (token !== uploadJobToken) return;
    LimeAppearance.applyPattern(pattern);
    return LimeStore.setAppearance({ pattern }).then(() => {
      deleteSupersededUploadBlobs(previousPattern, pattern);
      uploadBusy = false;
      surface.rerender();
      if (surface.setError) {
        surface.setError(pattern.sessionOnly
          ? 'This browsing session doesn\'t support saving uploads (private browsing?) — it\'ll work for now, but won\'t be here next time you open Lime.'
          : '');
      }
    });
  }).catch((err) => {
    console.error(err);
    if (token !== uploadJobToken) return;
    uploadBusy = false;
    surface.rerender();
    if (surface.setError) surface.setError((err && err.message) || 'Couldn\'t use that image. Try a different PNG or JPG.');
  });
}

// The one persistent pattern-upload input (index.html) — wired here,
// once, directly, rather than delegated from a container that LIME-52/
// fix2's own popover and Settings innerHTML both used to re-render the
// input away inside of. uploadActiveSurface (set by handleAppearanceClick's
// own upload-tile branch, below) says which caller to report back to.
const patternUploadInput = document.getElementById('pattern-upload-input');
if (patternUploadInput) {
  patternUploadInput.addEventListener('change', (e) => {
    const input = e.target;
    const surface = uploadActiveSurface;
    uploadActiveSurface = null;
    // Reset immediately, not in a .then/.finally — a native file input
    // never fires a second `change` for re-picking the exact same file
    // otherwise (no value change to detect), which the brief's own
    // matrix explicitly tests ("the same file twice in a row").
    const file = input.files && input.files[0];
    input.value = '';
    if (!surface || !file) return;
    runPatternUpload(file, surface);
  });
}

// LIME-52-fix: one shared handler for every Mode/Canvas/Pattern click,
// used identically by the popover and Settings -> Preferences ->
// Appearance — their two containers each still wire their own click
// listener (one needs e.stopPropagation() to stay open across picks,
// the other doesn't), but the branching logic inside is this one
// function, not two copies. Returns true once it has handled the
// event, so a call site can bail out of its own remaining branches.
function handleAppearanceClick(e, container, rerender, setError) {
  const modeBtn = e.target.closest('[data-theme-mode]');
  if (modeBtn) {
    const mode = modeBtn.dataset.themeMode;
    LimeAppearance.applyTheme(mode);
    LimeStore.setAppearance({ theme: mode }).then(rerender).catch(console.error);
    return true;
  }
  const swatch = e.target.closest('[data-canvas]');
  if (swatch && !swatch.disabled) {
    const name = swatch.dataset.canvas;
    LimeAppearance.applyCanvas(name);
    LimeStore.setAppearance({ canvas: name }).then(rerender).catch(console.error);
    return true;
  }
  const noneBtn = e.target.closest('[data-pattern-kind="none"]');
  if (noneBtn) {
    const previousPattern = LimeStore.getAppearance().pattern;
    LimeAppearance.applyPattern(null);
    LimeStore.setAppearance({ pattern: { kind: 'none' } }).then(() => {
      deleteSupersededUploadBlobs(previousPattern, null);
      rerender();
    }).catch(console.error);
    return true;
  }
  const presetBtn = e.target.closest('[data-pattern-preset]');
  if (presetBtn) {
    const presetId = presetBtn.dataset.patternPreset;
    // Keeps whichever intensity was already set (switching presets
    // shouldn't reset a Medium pick back to Low), defaulting to Low —
    // the brief's own "user-invisible-by-default" — only the first
    // time any pattern is ever chosen.
    const currentIntensity = (LimeStore.getAppearance().pattern || {}).intensity || 'low';
    const pattern = { kind: 'preset', presetId, intensity: currentIntensity };
    LimeAppearance.applyPattern(pattern);
    LimeStore.setAppearance({ pattern }).then(rerender).catch(console.error);
    return true;
  }
  const tileBtn = e.target.closest('[data-pattern-tile-id]');
  if (tileBtn) {
    const tile = cachedUserPatternTiles.find((t) => t.id === tileBtn.dataset.patternTileId);
    if (tile) {
      const currentIntensity = (LimeStore.getAppearance().pattern || {}).intensity || 'low';
      const pattern = { kind: 'user-tile', tileId: tile.id, src: tile.src, width: tile.width, height: tile.height, isVector: tile.isVector, intensity: currentIntensity };
      LimeAppearance.applyPattern(pattern);
      LimeStore.setAppearance({ pattern }).then(rerender).catch(console.error);
    }
    return true;
  }
  const uploadBtn = e.target.closest('[data-pattern-action="upload"]');
  if (uploadBtn) {
    // Ignored outright while a previous pick is still processing (a
    // disabled native `disabled` attribute already blocks this too,
    // below — belt and suspenders, since e.target.closest still finds
    // the button underneath a disabled state in some engines).
    if (uploadBusy || !patternUploadInput) return true;
    uploadActiveSurface = { rerender, setError };
    patternUploadInput.click();
    return true;
  }
  const removeUploadBtn = e.target.closest('[data-pattern-action="remove-upload"]');
  if (removeUploadBtn) {
    const previousPattern = LimeStore.getAppearance().pattern;
    LimeAppearance.applyPattern(null);
    LimeStore.setAppearance({ pattern: { kind: 'none' } }).then(() => {
      deleteSupersededUploadBlobs(previousPattern, null);
      rerender();
    }).catch(console.error);
    return true;
  }
  const intensityBtn = e.target.closest('[data-pattern-intensity]');
  if (intensityBtn) {
    const intensity = intensityBtn.dataset.patternIntensity;
    const current = LimeStore.getAppearance().pattern || { kind: 'none' };
    const pattern = Object.assign({}, current, { intensity });
    LimeAppearance.applyPattern(pattern);
    LimeStore.setAppearance({ pattern }).then(rerender).catch(console.error);
    return true;
  }
  const treatmentBtn = e.target.closest('[data-pattern-treatment-toggle]');
  if (treatmentBtn) {
    const treatment = treatmentBtn.dataset.patternTreatmentToggle;
    const current = LimeStore.getAppearance().pattern || {};
    if (current.kind !== 'upload' || current.treatment === treatment) return true;
    const pattern = Object.assign({}, current, { treatment });
    LimeAppearance.applyPattern(pattern);
    LimeStore.setAppearance({ pattern }).then(rerender).catch(console.error);
    return true;
  }
  return false;
}

// ── Rich-text sanitiser (LIME-37) ────────────────────────
// The one allow-list, used identically on send (before anything is
// stored) and on render (before metadata.html ever reaches the DOM) —
// per the brief's own "the same sanitiser runs on send and on render."
// Nothing here trusts that content already in storage is still safe.
const SANITIZE_ALLOWED_TAGS = new Set(['P', 'BR', 'STRONG', 'B', 'EM', 'I', 'U', 'S', 'A', 'UL', 'OL', 'LI', 'BLOCKQUOTE', 'CODE', 'PRE']);
// Tags whose *content* is never meaningful message text — removed
// entirely, not unwrapped, unlike every other disallowed tag below.
const SANITIZE_DROP_WITH_CONTENT = new Set(['SCRIPT', 'STYLE']);

function sanitizeHrefValue(raw) {
  const href = (raw || '').trim();
  if (!href) return null;
  if (/^(https?|mailto):/i.test(href)) return href;
  // Some other real scheme (javascript:, data:, etc.) — never kept.
  if (/^[a-z][a-z0-9+.-]*:/i.test(href)) return null;
  // No scheme at all — the same "add https:// for a bare domain" the
  // Link toolbar command itself does (brief: "add https:// if there's
  // no scheme"), applied here too so a pasted bare-domain link matches.
  return 'https://' + href;
}

// Depth-first: a node's children are fully sanitised before deciding the
// node's own fate, so unwrapping a disallowed wrapper (a pasted <div> or
// <span>) never skips sanitising what was inside it.
function sanitizeFragment(root) {
  [...root.childNodes].forEach((node) => {
    if (node.nodeType === 3) return; // text node — kept as-is
    if (node.nodeType !== 1) { node.remove(); return; } // comments etc.
    let tag = node.tagName;
    if (SANITIZE_DROP_WITH_CONTENT.has(tag)) { node.remove(); return; }
    // A legacy tag name a real execCommand implementation still emits
    // (confirmed live in Firefox: strikeThrough produces <strike>, not
    // <s>) — normalized to its allow-listed equivalent *before* the
    // allow-list check below, so formatting the user actually applied
    // doesn't silently vanish on send just because of which tag name an
    // old execCommand happened to choose.
    if (tag === 'STRIKE') {
      const replacement = node.ownerDocument.createElement('s');
      while (node.firstChild) replacement.appendChild(node.firstChild);
      root.replaceChild(replacement, node);
      node = replacement;
      tag = 'S';
    }
    sanitizeFragment(node);
    if (!SANITIZE_ALLOWED_TAGS.has(tag)) {
      while (node.firstChild) root.insertBefore(node.firstChild, node);
      node.remove();
      return;
    }
    if (tag === 'A') {
      const safeHref = sanitizeHrefValue(node.getAttribute('href'));
      [...node.attributes].forEach((attr) => node.removeAttribute(attr.name));
      if (safeHref) {
        node.setAttribute('href', safeHref);
      } else {
        // No safe scheme at all (javascript:, an empty href, …) — the
        // brief's own "javascript: links stripped": unwrap rather than
        // leave a link-shaped element with nothing safe to point at.
        while (node.firstChild) root.insertBefore(node.firstChild, node);
        node.remove();
      }
      return;
    }
    // Every other allowed tag (p, br, strong, b, em, i, u, s, ul, ol, li,
    // blockquote, code, pre) takes no attributes in this allow-list —
    // strips a pasted style="…"/onerror="…" etc. regardless of which
    // tag it rode in on.
    [...node.attributes].forEach((attr) => node.removeAttribute(attr.name));
  });
}

// <template> content is inert by spec — no script execution, no image
// fetches, nothing fires while untrusted markup sits inside it — so
// setting .innerHTML here can never itself trigger a payload (an
// <img onerror> parsed into a plain detached <div> can still fire its
// handler once the image load fails, asynchronously; a <template> never
// loads the image at all). Sanitising happens synchronously against that
// inert fragment, so nothing is ever "live" even for an instant.
function sanitizeHtml(html) {
  const template = document.createElement('template');
  template.innerHTML = html == null ? '' : String(html);
  sanitizeFragment(template.content);
  return template.innerHTML;
}

// Render-only: rel/target are a rendering concern (brief: "add … on
// render"), never stored — re-sanitises first (defense in depth; never
// trusts that what's already in metadata.html is still safe) then adds
// them to the sanitised result.
function renderRichHtml(html) {
  const safe = sanitizeHtml(html);
  const template = document.createElement('template');
  template.innerHTML = safe;
  template.content.querySelectorAll('a[href]').forEach((a) => {
    a.setAttribute('rel', 'noopener noreferrer');
    a.setAttribute('target', '_blank');
  });
  return template.innerHTML;
}

// Formatting tags that make metadata.html worth storing at all — <p>/<br>
// alone are just contenteditable's own line structure, not a deliberate
// format, so plain multi-line text still omits metadata.html entirely
// (brief: "omit html when there's no formatting").
const RICH_TEXT_FORMATTING_TAGS = /<(strong|b|em|i|u|s|a|ul|ol|li|blockquote|code|pre)[\s>]/i;

function hasRealFormatting(sanitizedHtml) {
  return RICH_TEXT_FORMATTING_TAGS.test(sanitizedHtml);
}

// ── Shared composer (LIME-37) ────────────────────────────
// One implementation for both the main and reply composers — they only
// ever differed in which ids they used and whether growth rescrolled a
// thread; everything else (expand-on-focus, auto-grow, is-active Send,
// toolbar commands, keyboard shortcuts, paste sanitising, send) was
// duplicated. `rootEl` is the outer footer (#composer/#replies-composer);
// `onSend({ content, metadata })` does whatever that composer's send
// actually means (LimeStore.sendMessage for the main thread, sendMessage
// with replyTo for a reply) — this function only ever produces the
// payload, never talks to the store itself, so it stays reusable for
// wherever a third composer shows up later.
//
// document.execCommand is what the brief sanctions for this prototype
// ("a production editor … would replace it behind the same createComposer
// API"). One real environmental limit found while building this: jsdom
// has no execCommand/queryCommandState implementation at all (confirmed
// directly, not assumed) — every live command/pressed-state check below
// only ever runs for real in an actual browser. The jsdom verification
// for this brief tests the sanitiser, the Enter/list/code keyboard logic,
// and rendering directly (none of which need execCommand); the live
// toolbar interactions are verified in Playwright + Firefox instead,
// matching the brief's own two-part verification split.

// ── Sticky-bottom scrolling (LIME-39) ────────────────────
// Shared by the main thread and the reply list: tracks whether the
// scroller is currently at the bottom (via a live 'scroll' listener, not
// a one-off snapshot — the brief's own Goal covers several distinct
// triggers — composer growth, a new message, an image finishing its
// load — and a live flag answers "should this particular trigger
// auto-scroll" correctly for all of them, including a user who scrolls
// away in the gap between two triggers) and re-pins to the bottom when
// something grows the content, but only if it was already there.
//
// The 'load' listener (not bubbling — captured, so one listener here
// covers every image at any depth) is what fixes the amended bug: an
// attachment's real URL resolves through an IndexedDB round trip
// (LIME-38's own getAttachmentUrl) well after the initial render's own
// pinToBottom() already ran, growing scrollHeight and leaving that
// scrollTop short of the real bottom once the image actually loads.
function createStickyScroll(scrollerEl) {
  let pinned = true;
  function checkPinned() {
    pinned = scrollerEl.scrollHeight - scrollerEl.scrollTop - scrollerEl.clientHeight <= 8;
  }
  function maybeStayAtBottom() {
    if (pinned) scrollerEl.scrollTop = scrollerEl.scrollHeight;
  }
  scrollerEl.addEventListener('scroll', checkPinned);
  scrollerEl.addEventListener('load', (e) => {
    if (e.target.tagName === 'IMG') maybeStayAtBottom();
  }, true);
  return {
    scrollerEl,
    // Unconditional — for moments that should always end up at the
    // bottom regardless of prior position (switching conversations,
    // opening a conversation's thread for the first time, your own
    // message you just sent) — and marks `pinned` true afterward so a
    // later image load or composer growth correctly keeps following.
    pinToBottom() { pinned = true; scrollerEl.scrollTop = scrollerEl.scrollHeight; },
    // Conditional — only if the scroller was already at the bottom
    // (checked live, not assumed) before whatever just grew it.
    maybeStayAtBottom,
  };
}

// for whichever scroller this composer overlaps — only the main
// composer passes one (it's position:absolute over #thread-messages;
// the reply composer is a normal-flow flex sibling of its own list, so
// growing it already reflows the list via flex, no overlap to fix).
// When present, a ResizeObserver on rootEl keeps that scroller's own
// --composer-clearance (read by its padding-bottom in gradients.css) in
// sync with this composer's real height, and re-pins to the bottom
// afterward if the scroller was already there.
function createComposer(rootEl, { onSend, stickyScroll } = {}) {
  const input = rootEl.querySelector('.lime-composer__input');
  const sendBtn = rootEl.querySelector('.lime-composer__return');
  const toolbar = rootEl.querySelector('.lime-composer__toolbar');
  const linkPopover = rootEl.querySelector('[data-link-popover]');
  const linkInput = linkPopover && linkPopover.querySelector('[data-link-input]');
  const linkSubmit = linkPopover && linkPopover.querySelector('[data-link-submit]');
  const linkToolButtons = [...rootEl.querySelectorAll('[data-cmd="link"]')];
  // LIME-38.
  const fileInput = rootEl.querySelector('[data-file-input]');
  const attachBtn = rootEl.querySelector('[data-attach-btn]');
  const attachmentsEl = rootEl.querySelector('[data-attachments]');
  const attachmentsErrorEl = rootEl.querySelector('[data-attachments-error]');
  if (!input) return;

  let savedLinkRange = null;
  // { file, previewUrl } — previewUrl is a client-side object URL for an
  // image chip's thumbnail only (this composer's own preview, made
  // directly from the raw File — nothing has gone through
  // LimeStore.uploadAttachment yet, so there's no `path` to ask
  // getAttachmentUrl for until Send actually runs).
  let pendingAttachments = [];

  function isCaretInside(tagName) {
    const sel = window.getSelection();
    if (!sel || !sel.rangeCount) return false;
    let node = sel.getRangeAt(0).startContainer;
    if (node.nodeType === 3) node = node.parentElement;
    const match = node && node.closest && node.closest(tagName);
    return !!(match && input.contains(match));
  }

  function updatePressedStates() {
    if (!toolbar || !document.queryCommandState) return;
    toolbar.querySelectorAll('[data-cmd]').forEach((btn) => {
      const cmd = btn.dataset.cmd;
      let pressed = false;
      try {
        if (cmd === 'bold') pressed = document.queryCommandState('bold');
        else if (cmd === 'italic') pressed = document.queryCommandState('italic');
        else if (cmd === 'underline') pressed = document.queryCommandState('underline');
        else if (cmd === 'strikethrough') pressed = document.queryCommandState('strikeThrough');
        else if (cmd === 'orderedList') pressed = document.queryCommandState('insertOrderedList');
        else if (cmd === 'unorderedList') pressed = document.queryCommandState('insertUnorderedList');
        else if (cmd === 'quote') pressed = isCaretInside('blockquote');
        else if (cmd === 'code') pressed = isCaretInside('code') || isCaretInside('pre');
        else if (cmd === 'link') pressed = isCaretInside('a');
      } catch (err) { /* queryCommandState on an unsupported command — leave unpressed */ }
      btn.setAttribute('aria-pressed', String(pressed));
    });
  }

  function toggleQuote() {
    document.execCommand('formatBlock', false, isCaretInside('blockquote') ? 'p' : 'blockquote');
  }

  // "Inline code for a selection within a line, a code block otherwise"
  // (brief). A prototype-level heuristic, not a full editor: a selection
  // that reads as one line (no newline in its own flattened text) becomes
  // inline <code>; anything else (a multi-line selection, or no selection
  // at all) turns the current block into a <pre><code> block instead.
  function toggleCode() {
    if (isCaretInside('pre')) { document.execCommand('formatBlock', false, 'p'); return; }
    const sel = window.getSelection();
    const text = sel && sel.rangeCount ? sel.toString() : '';
    if (text && !text.includes('\n')) {
      document.execCommand('insertHTML', false, '<code>' + escapeHtml(text) + '</code>');
    } else {
      document.execCommand('formatBlock', false, 'pre');
    }
  }

  function execCommandFor(cmd) {
    document.execCommand('styleWithCSS', false, false);
    if (cmd === 'bold') document.execCommand('bold');
    else if (cmd === 'italic') document.execCommand('italic');
    else if (cmd === 'underline') document.execCommand('underline');
    else if (cmd === 'strikethrough') document.execCommand('strikeThrough');
    else if (cmd === 'orderedList') document.execCommand('insertOrderedList');
    else if (cmd === 'unorderedList') document.execCommand('insertUnorderedList');
    else if (cmd === 'quote') toggleQuote();
    else if (cmd === 'code') toggleCode();
    updatePressedStates();
  }

  function closeLinkPopover() {
    if (linkPopover) linkPopover.classList.remove('is-open');
  }

  function openLinkPopover(anchorBtn) {
    if (!linkPopover || !linkInput) return;
    const sel = window.getSelection();
    savedLinkRange = sel && sel.rangeCount ? sel.getRangeAt(0).cloneRange() : null;
    let existingHref = '';
    if (isCaretInside('a')) {
      let node = savedLinkRange.startContainer;
      if (node.nodeType === 3) node = node.parentElement;
      const a = node.closest('a');
      if (a) existingHref = a.getAttribute('href') || '';
    }
    linkInput.value = existingHref;
    const rect = anchorBtn.getBoundingClientRect();
    linkPopover.style.left = Math.max(8, rect.left) + 'px';
    linkPopover.style.top = (rect.bottom + 8) + 'px';
    linkPopover.classList.add('is-open');
    linkInput.focus();
    linkInput.select();
  }

  function applyLink() {
    const url = sanitizeHrefValue(linkInput.value);
    closeLinkPopover();
    input.focus();
    if (!url) return;
    const sel = window.getSelection();
    sel.removeAllRanges();
    if (savedLinkRange) sel.addRange(savedLinkRange);
    document.execCommand('styleWithCSS', false, false);
    if (savedLinkRange && !savedLinkRange.collapsed) {
      document.execCommand('createLink', false, url);
    } else {
      document.execCommand('insertHTML', false, '<a href="' + escapeHtml(url) + '">' + escapeHtml(url) + '</a>');
    }
    updatePressedStates();
  }

  if (linkPopover && linkInput && linkSubmit) {
    linkSubmit.addEventListener('click', applyLink);
    linkInput.addEventListener('keydown', (e) => {
      if (e.key === 'Enter') { e.preventDefault(); applyLink(); }
      else if (e.key === 'Escape') { e.preventDefault(); closeLinkPopover(); input.focus(); }
    });
    document.addEventListener('click', (e) => {
      if (!linkPopover.classList.contains('is-open')) return;
      if (linkPopover.contains(e.target)) return;
      if (e.target.closest && e.target.closest('[data-cmd="link"]')) return;
      closeLinkPopover();
    });
  }

  // mousedown, not click — prevents the browser from ever moving
  // focus/selection out of the contenteditable in the first place
  // (clicking a <button> normally would), so the command below always
  // applies to whatever was actually selected, not wherever focus lands
  // after the click. Scoped to [data-cmd] only — the link popover's own
  // input/submit inside this same toolbar need to receive focus normally.
  if (toolbar) {
    toolbar.addEventListener('mousedown', (e) => {
      if (e.target.closest('[data-cmd]')) e.preventDefault();
    });
    toolbar.addEventListener('click', (e) => {
      const btn = e.target.closest('[data-cmd]');
      if (!btn) return;
      const cmd = btn.dataset.cmd;
      if (cmd === 'link') {
        e.stopPropagation(); // same click that opens it would otherwise immediately close it (the document-level close-on-outside-click listener above)
        openLinkPopover(btn);
        return;
      }
      execCommandFor(cmd);
    });
  }

  function isEmpty() {
    return input.textContent.trim().length === 0;
  }

  // ── Attachments (LIME-38) ──────────────────────────────
  function showAttachmentError(message) {
    if (!attachmentsErrorEl) return;
    attachmentsErrorEl.textContent = message;
    attachmentsErrorEl.hidden = false;
  }

  function hideAttachmentError() {
    if (attachmentsErrorEl) attachmentsErrorEl.hidden = true;
  }

  function updateSendActive() {
    if (sendBtn) sendBtn.classList.toggle('is-active', !isEmpty() || pendingAttachments.length > 0);
  }

  function renderAttachmentChips() {
    if (!attachmentsEl) return;
    attachmentsEl.innerHTML = pendingAttachments.map((pending, index) => {
      const isImage = pending.file.type.startsWith('image/');
      const thumb = isImage
        ? '<img class="lime-attachment-chip__thumb" src="' + pending.previewUrl + '" alt="">'
        : '<span class="lime-attachment-chip__icon"><span class="dew dew-file"></span></span>';
      return '<div class="lime-attachment-chip' + (pending.sending ? ' lime-attachment-chip--sending' : '') + '" data-index="' + index + '">'
        + thumb
        + '<div class="lime-attachment-chip__meta">'
        + '<span class="lime-attachment-chip__name">' + escapeHtml(pending.file.name) + '</span>'
        + '<span class="lime-attachment-chip__size">' + formatFileSize(pending.file.size) + '</span>'
        + '</div>'
        + (pending.sending ? '' : '<button type="button" class="lime-attachment-chip__remove" data-remove-attachment title="Remove"><span class="dew dew-close"></span></button>')
        + '</div>';
    }).join('');
  }

  function addFiles(fileList) {
    hideAttachmentError();
    [...fileList].forEach((file) => {
      // LIME-41: the old 5-file-per-message cap is gone — an album (the
      // whole point of this brief) can run well past 5 photos, and the
      // brief's own verification sends 7 in one message. Only the
      // per-file size limit remains.
      if (file.size > MAX_ATTACHMENT_BYTES) {
        showAttachmentError('"' + file.name + '" is over the 10MB limit.');
        return;
      }
      pendingAttachments.push({
        file,
        previewUrl: file.type.startsWith('image/') ? URL.createObjectURL(file) : null,
      });
    });
    renderAttachmentChips();
    updateSendActive();
  }

  function removeAttachment(index) {
    // LIME-41 fix: a size error shown while picking files (e.g. "… is
    // over the 10MB limit") used to stay up even after the reader removed
    // the offending chip — only the *next* addFiles call ever cleared it.
    // Removing a chip is exactly the action that might have just fixed
    // the error, so it clears here too.
    hideAttachmentError();
    const removed = pendingAttachments.splice(index, 1)[0];
    if (removed && removed.previewUrl) URL.revokeObjectURL(removed.previewUrl);
    renderAttachmentChips();
    updateSendActive();
  }

  function clearAttachments() {
    pendingAttachments.forEach((p) => { if (p.previewUrl) URL.revokeObjectURL(p.previewUrl); });
    pendingAttachments = [];
    renderAttachmentChips();
  }

  if (attachBtn && fileInput) {
    attachBtn.addEventListener('click', () => fileInput.click());
    fileInput.addEventListener('change', () => {
      addFiles(fileInput.files);
      fileInput.value = ''; // lets picking the exact same file again re-fire 'change'
    });
  }

  if (attachmentsEl) {
    attachmentsEl.addEventListener('click', (e) => {
      const btn = e.target.closest('[data-remove-attachment]');
      if (!btn) return;
      removeAttachment(Number(btn.closest('[data-index]').dataset.index));
    });
  }

  rootEl.addEventListener('focusin', () => rootEl.classList.add('is-expanded'));
  rootEl.addEventListener('focusout', (e) => {
    if (rootEl.contains(e.relatedTarget)) return;
    if (isEmpty()) rootEl.classList.remove('is-expanded');
  });

  input.addEventListener('input', () => {
    input.style.height = 'auto';
    input.style.height = input.scrollHeight + 'px';
    // LIME-39: the ResizeObserver below (wired when stickyScroll is
    // passed) picks up this height change itself and re-pins the
    // scroller if it was at the bottom — no manual rescroll needed here
    // any more. LIME-10-fix13's old unconditional
    // `growScrollTarget.scrollTop = growScrollTarget.scrollHeight` is
    // gone: it yanked the view to the bottom on every keystroke even if
    // the reader had deliberately scrolled up, which is exactly the
    // "position isn't yanked" case this brief's own Goal calls out.
    updateSendActive();
    updatePressedStates();
  });

  // LIME-39: composer height varies far more now than LIME-10-fix15's
  // static 200px calibration ever anticipated (rich-text lists/quotes
  // from LIME-37, attachment chips from LIME-38) — a fixed clearance
  // value can't cover every state any more, so the scroller's own
  // padding-bottom is driven live from this instead (gradients.css).
  if (stickyScroll && typeof ResizeObserver !== 'undefined') {
    const CLEARANCE_GAP = 16; // --seed-space-4
    const ro = new ResizeObserver(() => {
      const clearance = Math.ceil(rootEl.getBoundingClientRect().height) + CLEARANCE_GAP;
      stickyScroll.scrollerEl.style.setProperty('--composer-clearance', clearance + 'px');
      stickyScroll.maybeStayAtBottom();
    });
    ro.observe(rootEl);
  }

  document.addEventListener('selectionchange', () => {
    if (document.activeElement === input) updatePressedStates();
  });

  input.addEventListener('paste', (e) => {
    e.preventDefault();
    const clipboard = e.clipboardData;
    if (!clipboard) return;
    const html = clipboard.getData('text/html');
    const text = clipboard.getData('text/plain');
    const raw = html || escapeHtml(text).replace(/\n/g, '<br>');
    document.execCommand('insertHTML', false, sanitizeHtml(raw));
  });

  function send() {
    const content = input.innerText.trim();
    // LIME-38: Send is active with text OR attachments, either alone —
    // guard matches that, not "content required" the way LIME-37 left it.
    if (!content && pendingAttachments.length === 0) return;
    // LIME-41 fix: same reasoning as removeAttachment above — an error
    // from an earlier pick shouldn't keep showing once the reader has
    // actually sent (with whatever files passed the check).
    hideAttachmentError();
    const safeHtml = sanitizeHtml(input.innerHTML);
    const metadata = hasRealFormatting(safeHtml) ? { html: safeHtml } : undefined;
    const attachments = pendingAttachments.map((p) => p.file);
    // "Optimistically showing a sending state" (brief) — chips stay
    // visible (greyed, remove button hidden) until onSend's own Promise
    // settles, rather than vanishing the instant Send is clicked; onSend
    // resolving only *after* every upload+message actually landed is
    // what lets this be an honest indicator, not a fake instant one.
    if (attachments.length > 0) {
      pendingAttachments.forEach((p) => { p.sending = true; });
      renderAttachmentChips();
    }
    const result = onSend ? onSend({ content, metadata, attachments }) : null;
    input.innerHTML = '';
    input.style.height = '';
    if (sendBtn) sendBtn.classList.remove('is-active');
    updatePressedStates();
    const finishAttachments = () => clearAttachments();
    if (result && typeof result.then === 'function') result.then(finishAttachments, finishAttachments);
    else finishAttachments();
  }

  input.addEventListener('keydown', (e) => {
    const mod = e.metaKey || e.ctrlKey;
    const key = e.key.toLowerCase();
    if (mod && !e.shiftKey && key === 'b') { e.preventDefault(); execCommandFor('bold'); return; }
    if (mod && !e.shiftKey && key === 'i') { e.preventDefault(); execCommandFor('italic'); return; }
    if (mod && !e.shiftKey && key === 'u') { e.preventDefault(); execCommandFor('underline'); return; }
    if (mod && e.shiftKey && key === 'x') { e.preventDefault(); execCommandFor('strikethrough'); return; }
    if (mod && !e.shiftKey && key === 'k') { e.preventDefault(); if (linkToolButtons[0]) openLinkPopover(linkToolButtons[0]); return; }

    if (e.key === 'Enter') {
      if (mod) { e.preventDefault(); send(); return; } // Cmd/Ctrl+Enter always sends
      if (e.shiftKey) return; // Shift+Enter is always a newline
      if (isCaretInside('li') || isCaretInside('pre') || isCaretInside('code')) return; // adds a new item/line
      e.preventDefault();
      send();
    }
  });

  if (sendBtn) sendBtn.addEventListener('click', send);
}

function formatTime(iso) {
  return new Date(iso).toLocaleTimeString([], { hour: 'numeric', minute: '2-digit' });
}

function formatDay(iso) {
  return new Date(iso).toLocaleDateString([], { weekday: 'long', month: 'long', day: 'numeric' });
}

// The text after "Last reply " in the reply summary (LIME-18) — compares
// calendar days, not elapsed hours, so a reply from 11pm yesterday reads
// "yesterday", not "23 hours ago".
function formatLastReply(iso) {
  const date = new Date(iso);
  const now = new Date();
  const startOfDay = (d) => new Date(d.getFullYear(), d.getMonth(), d.getDate());
  const diffDays = Math.round((startOfDay(now) - startOfDay(date)) / 86400000);
  if (diffDays <= 0) return 'today at ' + formatTime(iso);
  if (diffDays === 1) return 'yesterday at ' + formatTime(iso);
  if (diffDays <= 29) return diffDays + ' days ago';
  return date.toLocaleDateString([], { month: 'short', day: 'numeric' });
}

function formatDuration(seconds) {
  return Math.floor(seconds / 60) + ':' + String(seconds % 60).padStart(2, '0');
}

// ── Attachments (LIME-38, per-file count cap removed by LIME-41) ──
const MAX_ATTACHMENT_BYTES = 10 * 1024 * 1024;

function formatFileSize(bytes) {
  if (bytes < 1024) return bytes + ' B';
  if (bytes < 1024 * 1024) return (bytes / 1024).toFixed(1) + ' KB';
  return (bytes / (1024 * 1024)).toFixed(1) + ' MB';
}

// LIME-41: recorded once at upload time — not deferred to whenever the
// <img> itself first paints — so the album grid can lay itself out (and
// stay laid out identically after a reload) without ever waiting on a
// real image load. Resolves { width, height }, or null for a non-image
// file (nothing to measure) or one the browser can't decode.
function readImageDimensions(file) {
  if (!file.type || !file.type.startsWith('image/')) return Promise.resolve(null);
  return new Promise((resolve) => {
    const url = URL.createObjectURL(file);
    const img = new Image();
    img.onload = () => {
      URL.revokeObjectURL(url);
      resolve({ width: img.naturalWidth, height: img.naturalHeight });
    };
    img.onerror = () => {
      URL.revokeObjectURL(url);
      resolve(null);
    };
    img.src = url;
  });
}

// LIME-42: recorded once at upload time, same reasoning as
// readImageDimensions above — "the duration comes from metadata" per the
// brief, not measured live off the real <audio> element each time it
// renders (which would also work, but would leave the duration label
// blank until the file had actually loaded once, and wouldn't match
// "from metadata"). Resolves a number of seconds, or null for a
// non-audio file or one the browser can't read metadata for.
function readAudioDuration(file) {
  if (!file.type || !file.type.startsWith('audio/')) return Promise.resolve(null);
  return new Promise((resolve) => {
    const url = URL.createObjectURL(file);
    const el = new Audio();
    el.preload = 'metadata';
    el.onloadedmetadata = () => {
      URL.revokeObjectURL(url);
      resolve(Number.isFinite(el.duration) ? el.duration : null);
    };
    el.onerror = () => {
      URL.revokeObjectURL(url);
      resolve(null);
    };
    el.src = url;
  });
}

// LIME-41: an attachment counts as a photo by its recorded mime — the one
// check every attachment-aware reader below uses (album membership,
// lightbox scoping, preview text) so none of them ever branch on
// message.type themselves.
function isImageAttachment(att) {
  return !!(att.mime && att.mime.startsWith('image/'));
}

// LIME-42: same pattern as isImageAttachment above, for a real uploaded
// audio file (never the decorative 'voice' message type, which has no
// attachments at all — see audioPlayerHtml's own comment for why the two
// stay fully separate).
function isAudioAttachment(att) {
  return !!(att.mime && att.mime.startsWith('audio/'));
}

// LIME-41: the attachment-only half of previewFor/plainPreviewFor below —
// "Photo"/"📎 filename" for the single-attachment case (matches LIME-38's
// own wording exactly, legacy or not), "📷 N photos"/"📎 N files"/both
// joined for a real multi-attachment album.
// LIME-42: three-way split (images / audio / everything else), extending
// LIME-41's own two-way version — "🎵 Audio" for the single-audio case
// (the brief's own exact wording, no count, matching "Photo"'s own
// no-count form), "🎵 N audio" ("audio" doesn't pluralize) alongside the
// existing photo/file parts for a real mixed multi-attachment album.
function attachmentSummaryPlain(attachments) {
  const images = attachments.filter(isImageAttachment);
  const audio = attachments.filter(isAudioAttachment);
  const files = attachments.filter((a) => !isImageAttachment(a) && !isAudioAttachment(a));
  if (attachments.length === 1) {
    if (images.length === 1) return 'Photo';
    if (audio.length === 1) return '🎵 Audio';
    return '📎 ' + (files[0].name || 'File');
  }
  const parts = [];
  if (images.length > 0) parts.push('📷 ' + images.length + (images.length === 1 ? ' photo' : ' photos'));
  if (audio.length > 0) parts.push('🎵 ' + audio.length + ' audio');
  if (files.length > 0) parts.push('📎 ' + files.length + (files.length === 1 ? ' file' : ' files'));
  return parts.join(', ');
}

function previewFor(message) {
  if (!message) return '';
  if (message.type === 'voice') return '<span class="dew dew-microphone"></span><span class="lime-contact__preview-text">Voice message</span>';
  if (message.type === 'location') return '<span class="dew dew-camera-on"></span><span class="lime-contact__preview-text">' + escapeHtml(message.metadata && message.metadata.place_name || 'Location') + '</span>';
  // LIME-41: caption text always wins over an attachment summary — a
  // legacy 'image'/'file' message's own content is always null (LIME-38),
  // so this falls straight through to the attachment branch for those.
  if (message.content) return '<span class="lime-contact__preview-text">' + escapeHtml(message.content) + '</span>';
  const attachments = LimeStore.getAttachments(message.id);
  if (attachments.length > 0) return '<span class="lime-contact__preview-text">' + escapeHtml(attachmentSummaryPlain(attachments)) + '</span>';
  return '<span class="lime-contact__preview-text">' + escapeHtml(message.content || '') + '</span>';
}

// Plain-text-only variant of previewFor, for contexts (the reply quote)
// that need a readable label rather than previewFor's icon+span HTML.
function plainPreviewFor(message) {
  if (!message) return '';
  if (message.type === 'voice') return 'Voice message';
  if (message.type === 'location') return message.metadata && message.metadata.place_name || 'Location';
  if (message.content) return message.content;
  const attachments = LimeStore.getAttachments(message.id);
  if (attachments.length > 0) return attachmentSummaryPlain(attachments);
  return message.content || '';
}

// LIME-37: a text message's actual body — shared by the main thread
// (contentHtml) and the reply panel's own reply rows (replyHtml), the two
// places that render a real message rather than a compact one-line
// preview (previewFor/plainPreviewFor stay plain on purpose — a list row
// or a reply's quote summary was never meant to show bold/lists/etc.).
// Re-sanitises metadata.html at render time (never trusts stored data is
// still safe) and wraps it in a <div>, not <p> — the allow-list includes
// block-level tags (ul/blockquote/pre) that <p> can't legally contain.
function messageBodyHtml(message, textClass) {
  const cls = textClass || 'lime-message__text';
  if (message.metadata && message.metadata.html) {
    return '<div class="' + cls + ' lime-rich-text">' + renderRichHtml(message.metadata.html) + '</div>';
  }
  return '<p class="' + cls + '">' + escapeHtml(message.content || '') + '</p>';
}

// LIME-44: the first http(s) URL in a message's plain content — checked
// against the raw `content` string, not the sanitized/rendered HTML
// (metadata.html), since a formatted message's own markup could contain
// a URL inside some other attribute that isn't the actual typed text the
// brief means by "a message's content." Never matches a bare
// javascript:/data: URI or similar — the pattern itself only ever
// recognizes strings starting with http:// or https://, so nothing
// downstream needs to re-check the scheme for safety.
const LINK_PATTERN = /https?:\/\/[^\s<>"']+/;

function firstUrlIn(text) {
  if (!text) return null;
  const match = LINK_PATTERN.exec(text);
  return match ? match[0] : null;
}

// LIME-44: a placeholder slot, inserted synchronously — resolved async by
// paintLinkPreviews below, the same two-step pattern paintAvatar/
// paintAttachments already use for anything needing a lookup after the
// initial render (getLinkPreview's own contract is a Promise, matching
// getAttachmentUrl, even though the local adapter's lookup is instant).
// Scoped to plain text messages only (contentHtml's final branch, and a
// reply's own equivalent) — not album captions, which already carry a
// lot of their own visual weight; not something this brief's own gate
// asks for either.
function linkPreviewSlotHtml(message) {
  const url = firstUrlIn(message.content);
  if (!url) return '';
  return '<div class="lime-link-preview-slot" data-link-preview-url="' + escapeHtml(url) + '"></div>';
}

// LIME-44: two genuinely different shapes, not one template with empty
// fields standing in for the other — a full card (a real fixture: image
// left, site name muted, bold 2-line-clamped title, muted 2-line-clamped
// description) versus the brief's own explicit minimal fallback (the
// domain as the title, the full URL muted underneath, no image at all).
// "The whole card is a link" — a real <a>, not a div with a click
// handler, so browser-native behavior (open in new tab, copy link,
// status bar preview) all work for free; rel="noopener noreferrer"
// since it always opens someone else's, potentially untrusted, page.
function linkPreviewCardHtml(preview) {
  const href = escapeHtml(preview.url);
  if (preview.minimal) {
    return '<a class="lime-link-preview lime-link-preview--minimal" href="' + href + '" target="_blank" rel="noopener noreferrer">'
      + '<div class="lime-link-preview__body">'
      + '<span class="lime-link-preview__title">' + escapeHtml(preview.title) + '</span>'
      + '<span class="lime-link-preview__url">' + href + '</span>'
      + '</div>'
      + '</a>';
  }
  const imageHtml = preview.image_url
    ? '<img class="lime-link-preview__thumb" src="' + escapeHtml(preview.image_url) + '" alt="">'
    : '<span class="lime-link-preview__thumb lime-link-preview__thumb--fallback"><span class="dew dew-link"></span></span>';
  return '<a class="lime-link-preview" href="' + href + '" target="_blank" rel="noopener noreferrer">'
    + imageHtml
    + '<div class="lime-link-preview__body">'
    + (preview.site_name ? '<span class="lime-link-preview__site">' + escapeHtml(preview.site_name) + '</span>' : '')
    + '<span class="lime-link-preview__title">' + escapeHtml(preview.title) + '</span>'
    + (preview.description ? '<span class="lime-link-preview__description">' + escapeHtml(preview.description) + '</span>' : '')
    + '</div>'
    + '</a>';
}

// Resolves every not-yet-painted [data-link-preview-url] slot under
// `container` — same two-step pattern as paintAttachments above.
// getLinkPreview never resolves null for a well-formed URL (the local
// adapter's own contract always returns at least a minimal card), so
// there's no empty-result branch to handle here; only network/adapter
// failure, which real production Edge Function calls could hit even
// though this brief's own local adapter never does.
// `stickyScroll`, when passed, is called explicitly once a card actually
// lands — found live, not assumed: unlike an attachment (which reserves
// its real box size *synchronously*, a placeholder with real CSS
// dimensions from the very first render, so createStickyScroll's own
// 'load'-event mechanism only ever has to handle the image's *content*
// arriving late, never a height change), this slot starts at zero
// height and only grows once getLinkPreview's own Promise resolves —
// a real, asynchronous *layout* shift, not just a late image decode.
// Relying on the 'load'-event mechanism alone here is doubly wrong: (1)
// it never fires at all for a card with no image (the minimal fallback,
// or a real fixture like ReadWriteThink's own image_url: null), so nothing
// would ever re-scroll for those; (2) even for a card WITH an image, it
// measured genuinely flaky live (3 runs: atBottom true/false/true,
// confirmed with instrumented 'load'/'scroll' event logging, not
// assumed from a single run) — a real timing race between the image's
// own 'load' firing and the layout actually settling. An explicit call
// right after the height-changing DOM mutation, the same pattern
// appendMessage/renderThread already use for their own synchronous
// inserts, sidesteps both problems outright.
function paintLinkPreviews(container, stickyScroll) {
  container.querySelectorAll('[data-link-preview-url]:not([data-link-preview-painted])').forEach((slot) => {
    const url = slot.dataset.linkPreviewUrl;
    slot.dataset.linkPreviewPainted = 'true';
    LimeStore.getLinkPreview(url).then((preview) => {
      if (!preview) return;
      // Fills the slot's own innerHTML rather than replacing the slot
      // itself (outerHTML) — the slot is the permanent CSS containment
      // wrapper (container-type/container-name), and per spec a
      // container can never be restyled by its own @container rule
      // (found live: an element with container-type set on itself
      // silently never matches an @container block targeting that same
      // element/class, even though its children inside the same block
      // resize correctly — a real, documented CSS Containment
      // constraint, not a bug, confirmed with a minimal repro before
      // settling on this two-element structure). The card itself lives
      // one level down, as this wrapper's own child, so it CAN respond
      // to the container query.
      slot.classList.toggle('lime-link-preview-slot--minimal', !!preview.minimal);
      slot.innerHTML = linkPreviewCardHtml(preview);
      if (stickyScroll) stickyScroll.maybeStayAtBottom();
    }).catch(console.error);
  });
}

// LIME-41: a single image tile — shared by the 1-image case (no grid
// wrapper, the existing 240×180 thumbnail) and each tile of a real album
// grid (albumHtml below, which adds its own sizing class). `index` is
// this attachment's position within the *image-only* list for its
// message — what the lightbox click handler below reads back
// (data-attachment-index) to know which image within that message's own
// scope was actually clicked. getAttachmentUrl is async, so this renders
// a placeholder synchronously (data-attachment-path, no real src yet) —
// paintAttachments below resolves it after, the same two-step pattern
// paintAvatar already uses for avatars inserted after the initial load.
function imageTileHtml(att, index, extraClass) {
  const path = escapeHtml(att.path || '');
  const name = escapeHtml(att.name || '');
  return '<img class="lime-message__image' + (extraClass ? ' ' + extraClass : '') + '" data-attachment-path="' + path + '" data-attachment-index="' + index + '" alt="' + name + '">';
}

// LIME-42: extension -> { label, tint } for a file card's badge, keyed
// off the attachment's own filename (its real extension — a .docx's own
// mime, application/vnd.openxmlformats-officedocument..., isn't
// obviously "DOC" the way the extension is) so "which badge to show" and
// "keeping the extension" (the truncation requirement below) both read
// from the one source. Only the extensions common enough to recognize at
// a glance get a color; anything else falls back to a plain neutral
// tile with a generic file glyph — today's exact pre-LIME-42 look for
// those, not a guess at a color that wouldn't mean anything.
const FILE_CATEGORY_BY_EXT = {
  pdf: { label: 'PDF', tint: 'bad' },
  doc: { label: 'DOC', tint: 'calm' },
  docx: { label: 'DOC', tint: 'calm' },
  xls: { label: 'XLS', tint: 'good' },
  xlsx: { label: 'XLS', tint: 'good' },
  csv: { label: 'XLS', tint: 'good' },
  ppt: { label: 'PPT', tint: 'warn' },
  pptx: { label: 'PPT', tint: 'warn' },
  zip: { label: 'ZIP', tint: 'neutral' },
  rar: { label: 'ZIP', tint: 'neutral' },
  '7z': { label: 'ZIP', tint: 'neutral' },
  tar: { label: 'ZIP', tint: 'neutral' },
  gz: { label: 'ZIP', tint: 'neutral' },
  txt: { label: 'TXT', tint: 'neutral' },
  md: { label: 'TXT', tint: 'neutral' },
  log: { label: 'TXT', tint: 'neutral' },
};

function fileExtension(name) {
  const match = /\.([a-z0-9]+)$/i.exec(name || '');
  return match ? match[1].toLowerCase() : '';
}

function fileCardHtml(att) {
  const path = escapeHtml(att.path || '');
  const name = att.name || 'file';
  const ext = fileExtension(name);
  const base = ext ? name.slice(0, -(ext.length + 1)) : name;
  const category = FILE_CATEGORY_BY_EXT[ext];
  const badgeHtml = category
    ? '<span class="lime-filecard__badge lime-filecard__badge--' + category.tint + '">' + category.label + '</span>'
    : '<span class="lime-filecard__badge lime-filecard__badge--neutral"><span class="dew dew-file"></span></span>';
  const metaHtml = badgeHtml
    + '<div class="lime-filecard__meta">'
    + '<span class="lime-filecard__name"><span class="lime-filecard__name-base">' + escapeHtml(base) + '</span><span class="lime-filecard__name-ext">' + (ext ? '.' + escapeHtml(ext) : '') + '</span></span>'
    + '<span class="lime-filecard__size">' + formatFileSize(att.size || 0) + '</span>'
    + '</div>';
  // LIME-42: "PDFs and images open in a new tab from the card" — an
  // image attachment never reaches this function at all (it always
  // renders as an album/grid tile via imageTileHtml, never a file card),
  // so only the PDF half of that sentence ever applies here.
  //
  // A real <a target="_blank">, resolved by the exact same
  // paintAttachments pass every other attachment already goes through —
  // not a JS window.open() call, which was tried first and found, live
  // in Firefox, to silently fail: the tab opened but never navigated.
  // A blob: URL is scoped to the Document that created it, and can't
  // reliably be handed to a genuinely separate browsing context opened
  // via window.open(), even same-origin — but a real anchor click's own
  // "open as an auxiliary browsing context" navigation does resolve it
  // correctly, the same proven path the Download link right below
  // already relies on (confirmed working there first).
  const openHtml = att.mime === 'application/pdf'
    ? '<a class="lime-filecard__open" href="#" target="_blank" rel="noopener" data-attachment-path="' + path + '">' + metaHtml + '</a>'
    : '<div class="lime-filecard__open">' + metaHtml + '</div>';
  return '<div class="lime-filecard">'
    + openHtml
    + '<a class="lime-filecard__download" data-attachment-path="' + path + '" data-attachment-download="' + escapeHtml(name) + '" download="' + escapeHtml(name) + '" title="Download"><span class="dew dew-download"></span></a>'
    + '</div>';
}

// LIME-42: real playback for an uploaded audio attachment, styled to
// match the decorative 'voice' message type's own bubble exactly
// (.lime-message__voice/.lime-voice__play/-waveform/-duration, LIME-10)
// per the brief's own "matches the existing voice-message bubble" — but
// under its own class names (.lime-audio-attachment*), never those, so
// this can never accidentally share a selector with that unrelated,
// still-purely-decorative feature, or with a since-found pre-existing
// dead-CSS collision on .lime-message__file-name/-download (a leftover,
// unused `.lime-message__file` block further down lime.css redeclares
// those same bare class names — noted in TEND.md, left alone, out of
// this brief's scope — fileCardHtml above already sidesteps it the same
// way, with its own fresh .lime-filecard__* names).
function audioPlayerHtml(att, index) {
  const path = escapeHtml(att.path || '');
  const duration = att.duration_seconds != null ? att.duration_seconds : 0;
  return '<div class="lime-audio-attachment">'
    + '<button type="button" class="lime-audio-attachment__play" data-audio-player data-attachment-index="' + index + '" aria-label="Play audio" title="Play">'
    + '<span class="dew dew-play"></span>'
    + '</button>'
    + '<div class="lime-audio-attachment__waveform" aria-hidden="true"></div>'
    + '<span class="lime-audio-attachment__duration">' + formatDuration(Math.round(duration)) + '</span>'
    + '<audio class="lime-audio-attachment__el" data-attachment-path="' + path + '" preload="none" hidden></audio>'
    + '</div>';
}

// LIME-41: a message's full attachment set (images as an album grid,
// non-image files as cards below it, any typed text as a caption below
// that) — supersedes LIME-38's one-attachment-per-message
// attachmentContentHtml. `attachments` is always LimeStore.getAttachments
// (message.id)'s own return, which already carries the backward-compat
// synthesis for a pre-LIME-41 message — this function never branches on
// message.type itself. `wrap` controls whether the media/file blocks get
// the main thread's own .lime-message__content bubble (true) or render
// bare the way the (already compact, no-bubble) reply list always used
// attachmentContentHtml's own output (false) — matches how each context
// already differed before this brief.
//
// Grid layout per the brief's own counts: 1 keeps the single 240×180
// thumbnail (no grid); 2 side-by-side; 3 one large + two stacked; 4+ a
// 2×2 grid, the 4th tile carrying a "+N" overlay (images beyond the 4
// shown) once there are more than 4. 5+ also adds an "N photos" label
// that opens the photo wall (openPhotoWall, LIME-41-fix, superseding
// LIME-41's own gallery card modal) — the 2×2 grid alone can't represent
// every image in a large album on its own. The "+N" overlay tile itself
// (LIME-41-fix) opens the wall too, not the viewer at that one photo —
// data-gallery-message-id on that tile specifically, read by the exact
// same delegated click handler the "N photos" label uses.
function albumHtml(message, attachments, options) {
  const wrap = !!(options && options.wrap);
  const images = attachments.filter(isImageAttachment);
  // LIME-42: audio gets its own inline-player treatment, split out from
  // "everything else" the same way images already are — files below is
  // now genuinely "neither photo nor audio", not "everything non-image".
  const audio = attachments.filter(isAudioAttachment);
  const files = attachments.filter((a) => !isImageAttachment(a) && !isAudioAttachment(a));
  let out = '';
  if (images.length === 1) {
    const tile = imageTileHtml(images[0], 0, '');
    out += wrap ? '<div class="lime-message__content lime-message__content--media">' + tile + '</div>' : tile;
  } else if (images.length > 1) {
    const sizeClass = images.length === 2 ? 'lime-album--2' : images.length === 3 ? 'lime-album--3' : 'lime-album--grid';
    const shown = images.slice(0, 4);
    const overlayCount = images.length - 4;
    const isOverflowing = images.length > 4;
    const tiles = shown.map((att, i) => {
      const isMoreTile = isOverflowing && i === 3;
      const overlay = isMoreTile
        ? '<span class="lime-album__more-overlay" aria-hidden="true">+' + overlayCount + '</span>'
        : '';
      const galleryAttr = isMoreTile ? ' data-gallery-message-id="' + escapeHtml(message.id) + '"' : '';
      return '<span class="lime-album__tile"' + galleryAttr + '>' + imageTileHtml(att, i, 'lime-album__img') + overlay + '</span>';
    }).join('');
    const grid = '<div class="lime-album ' + sizeClass + '">' + tiles + '</div>';
    out += wrap ? '<div class="lime-message__content lime-message__content--media">' + grid + '</div>' : grid;
    if (images.length >= 5) {
      out += '<button type="button" class="lime-album__gallery-label" data-gallery-message-id="' + escapeHtml(message.id) + '">' + images.length + ' photos</button>';
    }
  }
  // LIME-41-fix: was a bare, unwrapped <p> with escapeHtml(message.content)
  // — plain text only, formatting silently dropped even when
  // metadata.html was correctly stored (confirmed live: the send path
  // was never the bug). Now shares messageBodyHtml with every text
  // message, the brief's own "share one caption renderer" — renders
  // metadata.html through renderRichHtml when present, exactly the same
  // path a top-level text message already uses. Wrapped in a real
  // .lime-message__content bubble when wrap is true, matching a text
  // message's own bubble exactly (LIME-47's width rules apply for free,
  // since it's the identical markup shape).
  if (message.content) {
    const captionHtml = messageBodyHtml(message, wrap ? 'lime-message__caption' : 'lime-reply__text');
    out += wrap ? '<div class="lime-message__content">' + captionHtml + '</div>' : captionHtml;
  }
  // LIME-42: same .lime-message__content bubble the decorative 'voice'
  // message type itself uses (padded, not the no-padding --media
  // variant images get) — matches that bubble exactly, per the brief.
  audio.forEach((att, i) => {
    const player = audioPlayerHtml(att, i);
    out += wrap ? '<div class="lime-message__content">' + player + '</div>' : player;
  });
  files.forEach((att) => {
    const card = fileCardHtml(att);
    out += wrap ? '<div class="lime-message__content">' + card + '</div>' : card;
  });
  return out;
}

// LIME-47, updated for LIME-41's real multi-attachment data: the reply
// panel's own quote used to show only "Photo"/"📎 filename"
// (plainPreviewFor's caption text, still rendered alongside this —
// unchanged) with no actual media. Reads LimeStore.getAttachments
// directly now rather than the old message-type-only quoteAttachments —
// same backward-compat synthesis, same "+N" thumbnail-overlay design
// this was already built for, now exercised by a real album instead of
// only ever a single legacy attachment.
function quoteMediaHtml(message) {
  const attachments = LimeStore.getAttachments(message.id);
  if (attachments.length === 0) return '';
  const images = attachments.filter(isImageAttachment);
  if (images.length > 0) {
    const path = escapeHtml(images[0].path || '');
    // lime-message__image (also) — the existing document-level lightbox
    // click handler is delegated off that exact class, so a click here
    // opens it for free; lime-replies-panel__quote-thumb only overrides
    // the size (48px, not the thread bubble's 240×180 max).
    const more = images.length > 1
      ? '<span class="lime-replies-panel__quote-thumb-more">+' + (images.length - 1) + '</span>'
      : '';
    return '<div class="lime-replies-panel__quote-media">'
      + '<img class="lime-message__image lime-replies-panel__quote-thumb" data-attachment-path="' + path + '" data-attachment-index="0" alt="">'
      + more
      + '</div>';
  }
  const name = escapeHtml(attachments[0].name || 'file');
  return '<div class="lime-replies-panel__quote-file">'
    + '<span class="dew dew-file"></span>'
    + '<span class="lime-replies-panel__quote-file-name">' + name + '</span>'
    + '</div>';
}

// Resolves every not-yet-painted [data-attachment-path] under `container`
// to a real URL (getAttachmentUrl) and applies it — an <img>'s src, or a
// download link's href. data-attachment-painted marks one done so a
// later call over the same container (e.g. a second message arriving)
// doesn't re-resolve and re-fetch ones already showing correctly.
function paintAttachments(container) {
  container.querySelectorAll('[data-attachment-path]:not([data-attachment-painted])').forEach((el) => {
    const path = el.dataset.attachmentPath;
    el.dataset.attachmentPainted = 'true';
    if (!path) return;
    LimeStore.getAttachmentUrl(path).then((url) => {
      // LIME-42: an audio attachment's hidden <audio> element also needs
      // its src resolved the same lazy, two-step way every other
      // attachment already does — an IMG's own .src assignment.
      if (el.tagName === 'IMG' || el.tagName === 'AUDIO') el.src = url;
      // LIME-52-fix: the appearance-upload preview tile isn't an <img>
      // (it needs mask-image for a Texture, background-image for a
      // Photo) — data-attachment-style names which.
      else if (el.dataset.attachmentStyle === 'photo-bg') el.style.backgroundImage = 'url("' + url + '")';
      else if (el.dataset.attachmentStyle === 'mask') { el.style.maskImage = 'url("' + url + '")'; el.style.webkitMaskImage = 'url("' + url + '")'; }
      else el.href = url;
    }).catch(console.error);
  });
}

// LIME-42: play/pause for a real audio attachment's hidden <audio>
// element — [data-audio-player] only ever appears on audioPlayerHtml's
// own button, never on the decorative 'voice' message type's unrelated
// .lime-voice__play (which carries no such attribute and stays exactly
// as inert as it always was).
document.addEventListener('click', (e) => {
  const btn = e.target.closest('[data-audio-player]');
  if (!btn) return;
  const container = btn.closest('.lime-audio-attachment');
  const audioEl = container && container.querySelector('.lime-audio-attachment__el');
  if (!audioEl) return;
  if (audioEl.paused) {
    // Only one plays at a time — a second player starting shouldn't
    // leave the first one still audibly running behind it.
    document.querySelectorAll('.lime-audio-attachment__el').forEach((el) => {
      if (el !== audioEl && !el.paused) el.pause();
    });
    audioEl.play().catch(console.error);
  } else {
    audioEl.pause();
  }
});

// Icon + aria-label reflect the real <audio> element's own `paused`
// state — covers every path that can change it (the click above, or the
// file simply finishing on its own) rather than just the one click
// handler's own assumption of what state it left things in. play/pause/
// ended don't bubble (spec), so this has to listen on the capturing
// phase, the same technique createStickyScroll's own 'load' listener
// already uses for the identical reason.
function syncAudioPlayerButton(audioEl) {
  const container = audioEl.closest('.lime-audio-attachment');
  const btn = container && container.querySelector('[data-audio-player]');
  if (!btn) return;
  const playing = !audioEl.paused && !audioEl.ended;
  btn.innerHTML = playing
    ? '<svg class="lime-audio-attachment__pause-icon" viewBox="0 0 24 24" aria-hidden="true" focusable="false">'
      + '<rect x="6" y="5" width="4" height="14" rx="1" fill="currentColor"/>'
      + '<rect x="14" y="5" width="4" height="14" rx="1" fill="currentColor"/>'
      + '</svg>'
    : '<span class="dew dew-play"></span>';
  btn.setAttribute('aria-label', playing ? 'Pause audio' : 'Play audio');
  btn.title = playing ? 'Pause' : 'Play';
}

['play', 'pause', 'ended'].forEach((evt) => {
  document.addEventListener(evt, (e) => {
    if (e.target.classList && e.target.classList.contains('lime-audio-attachment__el')) syncAudioPlayerButton(e.target);
  }, true);
});

// Also promoted (LIME-11-fix2) — the reply panel's quote/reply items
// reuse this exact reaction markup/rendering, same reasoning as the
// other promoted helpers above.
const REACTION_PICKER_HTML = '<div class="lime-reaction-picker">'
  + '<button data-emoji="👍">👍</button>'
  + '<button data-emoji="❤️">❤️</button>'
  + '<button data-emoji="😂">😂</button>'
  + '<button data-emoji="😮">😮</button>'
  + '<button data-emoji="🎉">🎉</button>'
  + '<button class="lime-reaction-picker__add" title="More"><span class="dew dew-plus"></span></button>'
  + '</div>';

// LIME-24b: reads live from LimeStore.getReactions rather than taking a
// `reactions` array + separately checking a local hasUserReacted Set — the
// store already returns count and "mine" (whether the current user is one
// of the reactors) per emoji, so there's nothing left to track locally.
function reactionsHtml(messageId) {
  const reactions = LimeStore.getReactions(messageId);
  if (!reactions || reactions.length === 0) return '';
  return reactions
    .map((r) => {
      const active = r.mine ? ' lime-reaction--active' : '';
      return '<button type="button" class="lime-reaction' + active + '" data-emoji="' + r.emoji + '">' + r.emoji + ' <span class="lime-reaction__count">' + r.count + '</span></button>';
    })
    .join('');
}

// Re-renders one message's reaction pills in place (LIME-08) — messageEl
// needs data-message-id since reactionsHtml re-fetches by that id.
function renderReactions(messageEl) {
  const container = messageEl.querySelector('.lime-message__reactions');
  if (container) container.innerHTML = reactionsHtml(messageEl.dataset.messageId);
}

// LIME-18: restores the original Slack-style summary (replier avatars,
// "N replies", "Last reply {when}") in place of LIME-11-fix5's plainer
// "💬 N replies" — like reactions, the count and senders are computed
// live from getRepliesForMessage rather than trusted from the seed
// message's own stale reply_count field. Click reuses the exact same
// openReplies() the "Reply" action button already calls (see the
// "Reply thread panel" closure further down) via a second delegated
// listener on this button's own class. Avatars are the distinct reply
// senders, most recent first, capped at 5 — .seed-avatar-group (Seed's
// own, unmodified) lays them out row-reverse with the last DOM child
// frontmost, so as implemented the *oldest* of the shown avatars ends
// up frontmost/leftmost, not the most recent; flagged at the gate.
function replyIndicatorHtml(messageId) {
  const replies = LimeStore.listReplies(messageId);
  if (replies.length === 0) return '';
  const seenSenders = new Set();
  const avatars = [];
  for (let i = replies.length - 1; i >= 0 && avatars.length < 5; i--) {
    const senderId = replies[i].sender_id;
    if (seenSenders.has(senderId)) continue;
    seenSenders.add(senderId);
    const sender = LimeStore.getProfile(senderId);
    if (sender) avatars.push('<span class="seed-avatar seed-avatar--xs lime-avatar" data-name="' + escapeHtml(sender.display_name) + '"></span>');
  }
  const last = replies[replies.length - 1];
  return '<div class="lime-message__footer">'
    + '<button type="button" class="lime-message__replies" data-message-id="' + messageId + '">'
    + '<span class="seed-avatar-group lime-replies__avatars">' + avatars.join('') + '</span>'
    + '<span class="lime-replies__count">' + replies.length + (replies.length === 1 ? ' reply' : ' replies') + '</span>'
    + '<span class="lime-replies__time">Last reply ' + formatLastReply(last.created_at) + '</span>'
    + '</button>'
    + '</div>';
}

// Keeps the main thread's reply summary correct after a reply is sent
// anywhere (the thread panel), without a full re-render (LIME-17).
// Replaces the whole .lime-message__footer (avatars + count + time all
// change together), not just a count, and paints the fresh avatars —
// they're inserted after the one-time load-time paint pass has already
// run, the same reason handleSend needs its own paintAvatar call.
function refreshReplyIndicator(messageId) {
  const messageEl = document.querySelector('#thread-messages .lime-message[data-message-id="' + messageId + '"]');
  if (!messageEl) return;
  const existing = messageEl.querySelector('.lime-message__footer');
  if (existing) existing.remove();
  const reactionsEl = messageEl.querySelector('.lime-message__reactions');
  if (reactionsEl) reactionsEl.insertAdjacentHTML('afterend', replyIndicatorHtml(messageId));
  messageEl.querySelectorAll('.lime-avatar[data-name]').forEach(paintAvatar);
}

// ── Avatar identity system ──────────────────────────────
// Every .lime-avatar[data-name] gets initials + a color deterministically
// derived from the name (same input always yields the same output, so a
// person's color is stable across the whole app and across reloads).
// Moved above the contacts/thread render below (LIME-18-fix): that
// render's own paintAvatar call (added by LIME-18, for reply-summary
// avatars and to fix a conversation-switch gap) runs during this
// script's very first synchronous pass — before a later `const` in
// this file would otherwise have been initialized, throwing "Cannot
// access 'PALETTE_SIZE' before initialization" and aborting the rest
// of this entire script. That's the actual cause behind a much bigger
// symptom than it looks: once one top-level statement in a script
// throws uncaught, every statement textually after it — every other
// IIFE's click wiring, the reaction picker, the mobile nav, all of
// it — simply never runs. paintAvatar is top-level, not IIFE-private
// (LIME-11), since sent messages, replies, and now conversation
// switches all need to call it themselves — the one-time sweep further
// down only ever reached what already existed at parse time.
const PALETTE_SIZE = 12;

function hashName(name) {
  let hash = 0;
  for (let i = 0; i < name.length; i++) {
    hash = (hash * 31 + name.charCodeAt(i)) | 0;
  }
  return Math.abs(hash) % PALETTE_SIZE;
}

function initialsFor(name) {
  const parts = name.trim().split(/\s+/).filter(Boolean);
  if (parts.length === 0) return '';
  const first = parts[0][0];
  const last = parts.length > 1 ? parts[parts.length - 1][0] : '';
  return (first + last).toUpperCase();
}

function paintAvatar(el) {
  const name = el.dataset.name;
  if (el.dataset.image) {
    const img = document.createElement('img');
    img.src = el.dataset.image;
    img.alt = '';
    el.appendChild(img);
    el.setAttribute('aria-label', name);
    return;
  }
  el.classList.add('lime-avatar--p' + hashName(name));
  el.textContent = initialsFor(name);
  el.setAttribute('aria-label', name);
}

// LIME-20: shared registry for wireDropdownToggle (defined much later
// in this file), so every registered menu can close every *other* one.
// Declared here, not next to the function itself — the reply-composer
// IIFE below calls wireDropdownToggle during this script's very first
// pass, before a later `const` would otherwise be initialized. Exactly
// the LIME-18-fix TDZ crash again; caught this time by actually running
// the app in jsdom before committing, not by reasoning about it.
const registeredDropdowns = new Set();

// LIME-26: CONVERSATION_ACTIONS (below) is module-scope, but Rename and
// Delete need a couple of functions that only exist inside
// initMessagesList's own closure (startRename touches #crumb-thread and
// the rename input directly; selectTopOrEmpty needs the live
// messageConversations list). initMessagesList fills these in once, at
// the end of its own setup — the same bridge-object pattern as
// registeredDropdowns above, just for a different scope gap.
const conversationActionHooks = { startRename: null, selectTopOrEmpty: null };

function initMessagesList() {
  // LIME-50: applies the current user's own stored canvas tone before
  // anything else renders — LimeStore.init() (this function's own
  // caller) has just resolved, so getAppearance() already has the real
  // profile, not the pre-load default.
  if (window.LimeAppearance) LimeAppearance.init();

  const list = document.getElementById('contacts-list');
  const thread = document.getElementById('thread-messages');
  if (!list || !thread) return;

  const threadSticky = createStickyScroll(thread); // LIME-39

  const currentUserId = LimeStore.getCurrentUserId();
  const me = LimeStore.getCurrentUser();
  const crumbThread = document.getElementById('crumb-thread');
  const openProfileAvatars = document.getElementById('open-profile-avatars');

  let currentConversationId = null;
  let lastRenderedDay = null;

  // Members excluding the current user, in the store's own membership
  // order (LIME-24b: this used to read conversation.participants directly;
  // that array no longer exists on a conversation object now that
  // membership is relational — LimeStore.getMembers(id) is the equivalent).
  function otherParticipants(conversation) {
    return LimeStore.getMembers(conversation.id).filter((p) => p.id !== currentUserId);
  }

  // Other participants ordered most-recent-speaker first, then by
  // membership order for anyone who hasn't spoken (LIME-19b). Drives both
  // the list's avatar cluster and the thread header's avatar row — a
  // group's "who's shown first" should track who's actually been talking,
  // not just membership order.
  function orderedOthers(conversation) {
    const others = otherParticipants(conversation);
    const lastSentAt = new Map();
    LimeStore.listMessages(conversation.id).forEach((m) => {
      if (m.sender_id !== currentUserId) lastSentAt.set(m.sender_id, m.created_at);
    });
    return [...others].sort((a, b) => {
      const at = lastSentAt.get(a.id);
      const bt = lastSentAt.get(b.id);
      if (at && bt) return new Date(bt) - new Date(at);
      if (at) return -1;
      if (bt) return 1;
      return 0;
    });
  }

  // ── Reaction picker (add) + reaction pill (toggle) ───────
  // Each reactable container (.lime-message, and — since LIME-11-fix2 —
  // .lime-reply and .lime-replies-panel__quote) has its own local
  // .lime-reaction-picker (a shared single-instance picker wouldn't work
  // with the closest()/querySelector() lookup below, and a shared id
  // would also be invalid HTML repeated across every instance — the
  // markup only carries the class, not an id).
  //
  // REACTABLE used to be just '.lime-message' — the reply panel's old
  // hardcoded messages (LIME-06 left them static) had no real message
  // object to look up, so an `if (!messageId)` fallback quietly created
  // a plain, unpersisted DOM button instead. LIME-11 removed those
  // hardcoded messages entirely and LIME-11-fix2 gave .lime-reply/the
  // quote real data-message-id attributes, so every matched container
  // now always has one — the fallback branch was dead code and is gone.
  const REACTABLE = '.lime-message, .lime-reply, .lime-replies-panel__quote';

  // A reaction made in the thread panel's quote/reply, or in the main
  // thread, must show up everywhere that message is currently on screen
  // (LIME-17) — not just the container the click happened in.
  function renderReactionsEverywhere(messageId) {
    document.querySelectorAll(REACTABLE).forEach((el) => {
      if (el.dataset.messageId === messageId) renderReactions(el);
    });
  }
  // One subscription covers every reaction click anywhere (main thread,
  // reply quote, reply list) — LimeStore.toggleReaction is the only
  // reaction write in the contract (LIME-24b unified the old add-always /
  // toggle-on-existing pair into this one call), and its event is the
  // single source of truth for re-rendering, rather than each click
  // handler re-rendering off its own Promise result.
  document.addEventListener('lime:reactions-changed', (e) => {
    const messageId = e.detail && e.detail.messageId;
    if (messageId) renderReactionsEverywhere(messageId);
  });

  document.addEventListener('click', (e) => {
    const btn = e.target.closest('.lime-message__actions [title="React"]');
    if (btn) {
      // stopImmediatePropagation, not stopPropagation: both this and the
      // "close all open pickers" listener below are bound to the same
      // document target, so stopPropagation (which only blocks moving to
      // a *different* element) wouldn't stop that second listener from
      // firing right after this one and immediately closing what this
      // just opened.
      e.stopImmediatePropagation();
      const container = btn.closest(REACTABLE);
      const picker = container.querySelector('.lime-reaction-picker');
      if (picker && !picker.classList.contains('is-open')) {
        // position:fixed, computed here from the row's own rect — same
        // reasoning as wireDropdownToggle's fixed mode: a scrollable
        // ancestor (the reply panel's list) clips an absolutely
        // positioned popup that opens upward from a row near its top
        // edge, same class of bug LIME-03w fixed for the nav dropdowns.
        const rect = container.getBoundingClientRect();
        picker.style.right = (window.innerWidth - rect.right) + 'px';
        picker.style.bottom = (window.innerHeight - rect.top + 8) + 'px';
      }
      picker?.classList.toggle('is-open');
      return;
    }

    const pickerEmoji = e.target.closest('.lime-reaction-picker [data-emoji]');
    if (pickerEmoji) {
      const msg = pickerEmoji.closest(REACTABLE);
      const messageId = msg.dataset.messageId;
      if (messageId) LimeStore.toggleReaction(messageId, pickerEmoji.dataset.emoji).catch(console.error);
      pickerEmoji.closest('.lime-reaction-picker').classList.remove('is-open');
      return;
    }

    const pill = e.target.closest('.lime-message__reactions .lime-reaction');
    if (pill) {
      const msg = pill.closest(REACTABLE);
      const messageId = msg.dataset.messageId;
      if (!messageId) return;
      LimeStore.toggleReaction(messageId, pill.dataset.emoji).catch(console.error);
    }
  });
  document.addEventListener('click', () => document.querySelectorAll('.lime-reaction-picker.is-open').forEach((p) => p.classList.remove('is-open')));

  function contentHtml(message) {
    if (message.type === 'voice') {
      const duration = message.metadata && message.metadata.duration_seconds || 0;
      return '<div class="lime-message__content lime-message__voice">'
        + '<button type="button" class="lime-voice__play" aria-label="Play voice message"><span class="dew dew-play"></span></button>'
        + '<div class="lime-voice__waveform" aria-hidden="true"></div>'
        + '<span class="lime-voice__duration">' + formatDuration(duration) + '</span>'
        + '</div>';
    }
    if (message.type === 'location') {
      const placeName = message.metadata && message.metadata.place_name || 'Location';
      return '<div class="lime-message__content">'
        + '<div class="lime-message__map" role="img" aria-label="' + escapeHtml(placeName) + '">'
        + '<svg class="lime-message__map-pin" viewBox="0 0 24 24" aria-hidden="true" focusable="false">'
        + '<path fill="currentColor" d="M12 2C7.58 2 4 5.58 4 10c0 5.25 6.34 11.4 7.06 12.06a1.34 1.34 0 0 0 1.88 0C13.66 21.4 20 15.25 20 10c0-4.42-3.58-8-8-8z"/>'
        + '<circle class="lime-message__map-pin-hole" cx="12" cy="10" r="3"/>'
        + '</svg>'
        + '</div>'
        + '</div>';
    }
    // LIME-41: replaces the old message.type === 'image'/'file' branch —
    // getAttachments already carries the backward-compat synthesis for
    // those legacy messages, so a non-empty result covers both eras.
    const attachments = LimeStore.getAttachments(message.id);
    if (attachments.length > 0) {
      return albumHtml(message, attachments, { wrap: true });
    }
    return '<div class="lime-message__content">' + messageBodyHtml(message) + '</div>' + linkPreviewSlotHtml(message);
  }

  function messageHtml(message, sender, isSent) {
    const presence = presenceFor(sender.status);
    // LIME-35: data-profile-id on both the avatar and the sender name —
    // the one delegated [data-profile-id] listener (top-level, below)
    // opens that sender's own details, never a hard-coded person. Empty
    // for UNKNOWN_SENDER (no real profile id) — the listener just no-ops
    // on a lookup miss, same as it would for any other bad/missing id.
    return '<div class="lime-message ' + (isSent ? 'lime-message--sent' : 'lime-message--received') + '" data-message-id="' + message.id + '">'
      + '<span class="lime-avatar-frame lime-avatar-frame--lg">'
      + '<span class="seed-avatar seed-avatar--lg lime-avatar" data-name="' + escapeHtml(sender.display_name) + '" data-profile-id="' + escapeHtml(sender.id || '') + '"></span>'
      + '<span class="lime-presence" data-presence="' + presence + '" role="img" aria-label="' + PRESENCE_LABEL[presence] + '"></span>'
      + '</span>'
      + '<div class="lime-message__col">'
      + '<div class="lime-message__meta">'
      + '<span class="lime-message__sender" data-profile-id="' + escapeHtml(sender.id || '') + '">' + escapeHtml(shortName(sender.display_name)) + '</span>'
      + '<span class="lime-message__time">' + formatTime(message.created_at) + '</span>'
      + '</div>'
      + contentHtml(message)
      + '<div class="lime-message__reactions">' + reactionsHtml(message.id) + '</div>'
      + replyIndicatorHtml(message.id)
      + '</div>'
      + '<div class="lime-message__actions">'
      + '<button title="React"><span>🙂</span></button>'
      + '<button title="Reply"><span class="dew dew-chat"></span></button>'
      + '<button title="More"><span class="dew dew-ellipsis-menu"></span></button>'
      + '</div>'
      + REACTION_PICKER_HTML
      + '</div>';
  }

  // Placeholder for a sender id that doesn't resolve to a real profile —
  // shouldn't happen with today's seed data, but LimeStore.getProfile can
  // return null, and messageHtml needs a display_name/status either way.
  const UNKNOWN_SENDER = { display_name: 'Unknown', status: 'offline' };

  function renderThread(conversationId) {
    currentConversationId = conversationId;
    lastRenderedDay = null;
    const msgs = LimeStore.listMessages(conversationId, { threadOnly: true });
    thread.innerHTML = '';
    if (msgs.length === 0) {
      thread.innerHTML = '<p class="lime-messages__empty">No messages yet.</p>';
      return;
    }
    msgs.forEach((m) => {
      const day = formatDay(m.created_at);
      if (day !== lastRenderedDay) {
        thread.insertAdjacentHTML('beforeend', '<div class="lime-date-divider"><span>' + day + '</span></div>');
        lastRenderedDay = day;
      }
      const isSent = m.sender_id === currentUserId;
      // LIME-19b: a group thread has a different sender per message, not
      // one fixed "teacher" for the whole conversation.
      const sender = isSent ? me : (LimeStore.getProfile(m.sender_id) || UNKNOWN_SENDER);
      thread.insertAdjacentHTML('beforeend', messageHtml(m, sender, isSent));
    });
    // LIME-18: needed for a conversation switch, not just the initial
    // load — the one-time document-wide paintAvatar pass (below, in
    // script order) only ever runs once, so anything renderThread
    // inserts afterward (every subsequent selectConversation call) is
    // otherwise left unpainted, same root cause as LIME-11's handleSend fix.
    thread.querySelectorAll('.lime-avatar[data-name]').forEach(paintAvatar);
    paintAttachments(thread); // LIME-38: same reasoning — resolves every image/file rendered by this pass
    paintLinkPreviews(thread, threadSticky); // LIME-44
    // LIME-11-fix3: covers both the initial page-load render (default
    // conversation) and every subsequent conversation switch, since both
    // paths call this same function — renderThread never scrolled at all
    // before this, always leaving the view at the top of the thread.
    // LIME-39: pinToBottom (not a bare assignment) also marks the
    // scroller "pinned," so any image among what was just inserted that
    // hasn't finished loading yet (an IndexedDB round trip — LIME-38)
    // correctly re-triggers this same scroll once it does, instead of
    // silently leaving the view short of the real bottom.
    threadSticky.pinToBottom();
  }

  // ── Group avatar cluster (LIME-19b) ─────────────────────
  // A reusable "who's in this" mark for group rows, sized to sit inside
  // the same 40px frame a DM's single avatar uses. data-count selects the
  // layout (2 diagonal / 3 triangle / 4 grid); at 5+ others the cluster
  // still caps at 4 tiles — the last becomes a neutral "+N" tile rather
  // than trying to fit a 5th face at this size.
  function avatarClusterMemberHtml(teacher) {
    return '<span class="seed-avatar lime-avatar lime-avatar-cluster__member" data-name="' + escapeHtml(teacher.display_name) + '"></span>';
  }

  function avatarClusterHtml(conversation) {
    const others = orderedOthers(conversation);
    const count = Math.min(others.length, 4);
    let tilesHtml;
    if (others.length > 4) {
      const extra = others.length - 3;
      tilesHtml = others.slice(0, 3).map(avatarClusterMemberHtml).join('')
        + '<span class="lime-avatar-cluster__member lime-avatar-cluster__more">+' + extra + '</span>';
    } else {
      tilesHtml = others.map(avatarClusterMemberHtml).join('');
    }
    return '<span class="lime-avatar-cluster lime-avatar-cluster--lg" data-count="' + count + '">' + tilesHtml + '</span>';
  }

  function directAvatarHtml(conversation) {
    const other = otherParticipants(conversation)[0];
    const presence = presenceFor(other ? other.status : 'offline');
    return '<span class="lime-avatar-frame lime-avatar-frame--lg">'
      + '<span class="seed-avatar seed-avatar--lg lime-avatar" data-name="' + escapeHtml(other ? other.display_name : '') + '"></span>'
      + '<span class="lime-presence" data-presence="' + presence + '" role="img" aria-label="' + PRESENCE_LABEL[presence] + '"></span>'
      + '</span>';
  }

  // For a group, prefixes the preview with who sent it ("Jean: " / "You: ")
  // — previewFor already wraps its text in one .lime-contact__preview-text
  // span (for all three message types), so the prefix is spliced into that
  // same span rather than duplicating previewFor's icon/voice/location
  // branching here.
  function rowPreviewHtml(conversation, latest) {
    if (!latest) return '<span class="lime-contact__preview-text">No messages yet</span>';
    if (conversation.type !== 'group') return previewFor(latest);
    const sender = latest.sender_id === currentUserId ? null : LimeStore.getProfile(latest.sender_id);
    const label = sender ? firstName(sender.display_name) : 'You';
    const prefix = escapeHtml(label + ': ');
    return previewFor(latest).replace('<span class="lime-contact__preview-text">', '<span class="lime-contact__preview-text">' + prefix);
  }

  function conversationRowHtml(conversation, latest) {
    const isGroup = conversation.type === 'group';
    const title = LimeStore.getConversationTitle(conversation);
    const avatarHtml = isGroup ? avatarClusterHtml(conversation) : directAvatarHtml(conversation);
    // LIME-19b-fix: the member count read as an unread/comment count here
    // and was removed from the list — it still shows in the thread header.
    return avatarHtml
      + '<div class="lime-contact__body">'
      + '<span class="lime-contact__name">' + escapeHtml(title) + '</span>'
      + '<span class="lime-contact__preview">' + rowPreviewHtml(conversation, latest) + '</span>'
      + '</div>'
      + '<div class="lime-contact__meta">'
      + '<span class="lime-contact__time">' + (latest ? formatTime(latest.created_at) : '') + '</span>'
      + '</div>';
  }

  function conversationSearchText(conversation) {
    const names = LimeStore.getMembers(conversation.id).map((p) => p.display_name);
    return (LimeStore.getConversationTitle(conversation) + ' ' + names.join(' ')).toLowerCase();
  }

  // Header avatars for whichever conversation is open (#open-profile-avatars).
  // DMs keep the existing two-avatar seed-avatar-group exactly; groups get
  // up to 5 most-recent-speaker-first faces (fits beside the breadcrumb and
  // the "…" button, even at mobile width — the brief flags this 5 cap as
  // something the user may want raised) plus a neutral "+N" tile and a
  // muted total-member-count label. Rebuilt on every selectConversation —
  // this used to be static "Shem R"/"Jean Chung" markup that never changed.
  const HEADER_AVATAR_CAP = 5;

  function conversationHeaderAvatarsHtml(conversation) {
    if (conversation.type !== 'group') {
      const other = otherParticipants(conversation)[0];
      return '<span class="seed-avatar-group lime-topbar__avatars">'
        + '<span class="seed-avatar seed-avatar--sm lime-avatar" data-name="' + escapeHtml(me.display_name) + '"></span>'
        + '<span class="seed-avatar seed-avatar--sm lime-avatar" data-name="' + escapeHtml(other ? other.display_name : '') + '"></span>'
        + '</span>';
    }
    const others = orderedOthers(conversation);
    const shown = others.slice(0, HEADER_AVATAR_CAP);
    const extra = others.length - HEADER_AVATAR_CAP;
    // LIME-19b-fix: seed-avatar-group is row-reverse (first DOM child
    // renders rightmost), so to read left-to-right as "most recent
    // speaker … 5th speaker, then +N", the DOM order has to be built
    // backwards — +N first, then the shown avatars from last to first.
    let avatarsHtml = '';
    if (extra > 0) {
      avatarsHtml += '<span class="seed-avatar seed-avatar--sm lime-avatar-cluster__more" aria-hidden="true">+' + extra + '</span>';
    }
    avatarsHtml += [...shown].reverse().map((t) => '<span class="seed-avatar seed-avatar--sm lime-avatar" data-name="' + escapeHtml(t.display_name) + '"></span>').join('');
    const allNames = others.map((t) => t.display_name).join(', ');
    return '<span class="seed-avatar-group lime-topbar__avatars" title="' + escapeHtml(allNames) + '">' + avatarsHtml + '</span>'
      + '<span class="lime-topbar__member-count">' + LimeStore.getMembers(conversation.id).length + ' members</span>';
  }

  // ── Appearance shortcut (LIME-50) ───────────────────────────
  // Replaces LIME-45's per-chat popover with an app-wide one: the same
  // canvas swatches as Settings -> Preferences -> Appearance, plus a
  // link to the full Preferences section for anything not covered here.
  const appearanceToggle = document.getElementById('appearance-toggle');
  const appearanceMenu = document.getElementById('appearance-menu');

  // LIME-52-fix: Pattern joins Mode/Canvas here (previously Settings-
  // only — "More in Settings" was the only way to reach it from the
  // popover). canvasGridHtml/patternGridHtml/patternControlsHtml are
  // the shared top-level builders also used by Settings ->
  // Preferences -> Appearance, below in this file — not two copies.
  function renderAppearanceMenu() {
    if (!appearanceMenu) return;
    const appearance = LimeStore.getAppearance();
    const isDark = document.documentElement.getAttribute('data-theme') === 'dark';
    appearanceMenu.innerHTML =
      '<div class="lime-menu__label">Mode</div>'
      + modeTabsHtml('appearance-menu', appearance.theme)
      + '<div class="lime-menu__divider"></div>'
      + '<div class="lime-menu__label">Canvas</div>'
      + (isDark ? canvasDisabledNoticeHtml() : '')
      + canvasGridHtml(isDark, true)
      + '<div class="lime-menu__divider"></div>'
      + '<div class="lime-menu__label">Pattern</div>'
      + patternGridHtml(appearance.pattern, cachedUserPatternTiles, true)
      + patternControlsHtml(appearance.pattern)
      + '<p class="lime-appearance-upload-error"></p>'
      + '<div class="lime-menu__divider"></div>'
      + '<button type="button" class="lime-menu__item" data-appearance-action="more"><span class="dew dew-gear"></span>More in Settings</button>';
    paintAttachments(appearanceMenu);
  }

  function setAppearanceMenuUploadError(msg) {
    const errorEl = appearanceMenu && appearanceMenu.querySelector('.lime-appearance-upload-error');
    if (errorEl) errorEl.textContent = msg || '';
  }

  if (appearanceMenu) {
    appearanceMenu.addEventListener('click', (e) => {
      // Same reasoning as the retired LIME-45 popover: stays open across
      // a few picks (a live preview), so interior clicks never reach
      // wireDropdownToggle's shared document-level close listener.
      e.stopPropagation();
      if (handleAppearanceClick(e, appearanceMenu, renderAppearanceMenu, setAppearanceMenuUploadError)) return;
      if (e.target.closest('[data-appearance-action="more"]')) {
        appearanceMenu.classList.remove('is-open');
        document.getElementById('settings-btn')?.click();
      }
    });
  }

  if (appearanceToggle && appearanceMenu) {
    appearanceToggle.addEventListener('click', renderAppearanceMenu);
    // LIME-52-fix3: suppressClose keeps this popover open across the
    // native file picker and while an upload is still processing —
    // uploadActiveSurface is set the instant the Upload tile is clicked
    // (handleAppearanceClick, above) and only cleared once the picker's
    // own change event lands, so it spans the whole OS-dialog window.
    wireDropdownToggle('appearance-toggle', 'appearance-menu', { fixed: true, suppressClose: () => uploadBusy || uploadActiveSurface !== null });
    new MutationObserver(() => {
      appearanceToggle.setAttribute('aria-expanded', String(appearanceMenu.classList.contains('is-open')));
    }).observe(appearanceMenu, { attributes: true, attributeFilter: ['class'] });
  }

  function selectConversation(conversation) {
    document.querySelectorAll('.lime-contact').forEach((el) => el.classList.remove('lime-contact--active'));
    document.querySelectorAll('[data-conversation-id="' + conversation.id + '"]').forEach((el) => el.classList.add('lime-contact--active'));
    if (openProfileAvatars) {
      openProfileAvatars.innerHTML = conversationHeaderAvatarsHtml(conversation);
      openProfileAvatars.querySelectorAll('.lime-avatar[data-name]').forEach(paintAvatar);
    }
    renderThread(conversation.id); // sets currentConversationId — markRead below relies on this already being current
    // LIME-36: opening a conversation clears its own unread state. This
    // emits lime:conversations-changed synchronously (store.js's emit is
    // a plain document.dispatchEvent, not deferred), so renderRecentRow
    // (subscribed to that event, below) already reflects the read/active
    // state correctly by the time this call returns — no separate call
    // needed here.
    LimeStore.markRead(conversation.id).catch(console.error);
    // LIME-35: keep the profile/Members panel in sync with whichever
    // conversation is now open — the old static "Jean Chung" markup
    // never did this at all (the exact staleness this brief fixes), so
    // switching conversations while it was showing left it displaying
    // the previous conversation's person/members. Skipped while a reply
    // thread is open (switching conversations doesn't touch that view).
    const rightPanel = document.getElementById('right-panel');
    if (rightPanel && rightPanel.dataset.panel !== 'replies') {
      showConversationHeaderPanel(conversation, false);
    }
    renderCrumbs(); // crumbThread's own text is renderCrumbs' job now, not set directly here
  }

  // LIME-26: after Delete, the conversation menu always acts on
  // currentConversationId (there's no per-row menu in this app — the
  // caret lives in the topbar for whichever thread is open), so the
  // deleted conversation was always the open one. messageConversations
  // is already fresh by the time this runs — deleteConversation's own
  // emit fires its lime:conversations-changed listener synchronously,
  // before this function is even called.
  function selectTopOrEmpty() {
    if (messageConversations.length > 0) {
      selectConversation(messageConversations[0]);
      return;
    }
    currentConversationId = null;
    document.querySelectorAll('.lime-contact').forEach((el) => el.classList.remove('lime-contact--active'));
    if (openProfileAvatars) openProfileAvatars.innerHTML = '';
    thread.innerHTML = '<p class="lime-messages__empty">No conversations left. Start one from the sidebar.</p>';
    renderCrumbs(); // no .lime-contact--active left — renderCrumbs clears crumbThread's text itself
  }

  // ── Inline rename (LIME-34 — replaces LIME-26's sibling <input>) ──
  // #crumb-thread becomes editable in place: no second element, so
  // nothing else that touches this exact node (the mobile view router's
  // own click listener, bound to it directly at parse time) needs to
  // know rename ever happened here.
  function startRename(conversation) {
    if (!crumbThread) return;

    // plaintext-only strips *pasted* formatting for free; not every
    // browser implements this contentEditable value yet, so fall back to
    // "true" plus a manual paste handler that does the same job.
    let usedPlaintextOnly = true;
    try {
      crumbThread.contentEditable = 'plaintext-only';
      if (crumbThread.contentEditable !== 'plaintext-only') throw new Error('unsupported');
    } catch (e) {
      usedPlaintextOnly = false;
      crumbThread.contentEditable = 'true';
    }
    crumbThread.classList.add('is-editing');

    function onPaste(e) {
      e.preventDefault();
      const text = (e.clipboardData || window.clipboardData).getData('text/plain');
      document.execCommand('insertText', false, text);
    }
    if (!usedPlaintextOnly) crumbThread.addEventListener('paste', onPaste);

    crumbThread.focus();
    // "the whole name selected," per the brief's own reference.
    const range = document.createRange();
    range.selectNodeContents(crumbThread);
    const selection = window.getSelection();
    selection.removeAllRanges();
    selection.addRange(range);

    let finished = false;
    function finish(save) {
      if (finished) return;
      finished = true;
      crumbThread.contentEditable = 'false';
      crumbThread.removeAttribute('contenteditable');
      crumbThread.classList.remove('is-editing');
      crumbThread.removeEventListener('keydown', onKeydown);
      crumbThread.removeEventListener('blur', onBlur);
      if (!usedPlaintextOnly) crumbThread.removeEventListener('paste', onPaste);
      if (save) {
        // An empty value clears the name back to the auto title — the
        // store's own behavior (getConversationTitle falls through to
        // the derived name whenever conversations.name is falsy), not
        // special-cased here.
        const trimmed = crumbThread.textContent.trim();
        LimeStore.renameConversation(conversation.id, trimmed || null).then(() => {
          // lime:conversations-changed (emitted by renameConversation)
          // already repaints this conversation's row everywhere via
          // updateRow — but the breadcrumb isn't a row, and nothing else
          // re-derives it just from that event, so it needs its own
          // update here.
          if (crumbThread) crumbThread.textContent = LimeStore.getConversationTitle(conversation);
        }).catch(console.error);
      } else {
        crumbThread.textContent = LimeStore.getConversationTitle(conversation);
      }
    }

    function onKeydown(e) {
      if (e.key === 'Enter') {
        e.preventDefault();
        finish(true);
      } else if (e.key === 'Escape') {
        e.preventDefault();
        finish(false);
      }
    }
    function onBlur() {
      finish(true);
    }
    crumbThread.addEventListener('keydown', onKeydown);
    crumbThread.addEventListener('blur', onBlur);
  }

  // ── Send message (LIME-07, LIME-37: via the shared createComposer) ──
  const composerEl = document.getElementById('composer');
  if (composerEl) {
    createComposer(composerEl, {
      stickyScroll: threadSticky,
      onSend({ content, metadata, attachments }) {
        if (!currentConversationId) return Promise.resolve();
        const conversationId = currentConversationId;

        function appendMessage(message) {
          if (conversationId !== currentConversationId) return; // switched threads before this resolved
          const emptyState = thread.querySelector('.lime-messages__empty');
          if (emptyState) emptyState.remove();

          const day = formatDay(message.created_at);
          if (day !== lastRenderedDay) {
            thread.insertAdjacentHTML('beforeend', '<div class="lime-date-divider"><span>' + day + '</span></div>');
            lastRenderedDay = day;
          }
          thread.insertAdjacentHTML('beforeend', messageHtml(message, me, true));
          const newAvatar = thread.querySelector('.lime-message:last-child .lime-avatar[data-name]');
          if (newAvatar) paintAvatar(newAvatar); // real bug (LIME-11): paintAvatar only ran once at load, missing every sent message's avatar since LIME-07
          paintAttachments(thread); // LIME-38
          paintLinkPreviews(thread, threadSticky); // LIME-44
          threadSticky.pinToBottom(); // LIME-39: your own message always scrolls into view, and re-pins for any attachment inside it that loads afterward
        }

        // LIME-41 supersedes LIME-38's "text first, then one message per
        // attachment": every file uploads (and has its dimensions/duration
        // read — LIME-42 adds readAudioDuration alongside LIME-41's own
        // readImageDimensions, same reasoning: recorded once at upload
        // time, not measured live off the real <audio> element later),
        // then a single sendMessage carries the caption plus the whole
        // attachments array — one message, not N+1. Upload order doesn't
        // matter here (Promise.all preserves array order regardless of
        // which upload actually finishes first).
        const files = attachments || [];
        return Promise.all(files.map((file) => Promise.all([
          LimeStore.uploadAttachment(file, { conversationId }),
          readImageDimensions(file),
          readAudioDuration(file),
        ]).then(([{ path }, dims, duration]) => ({
          path,
          name: file.name,
          size: file.size,
          mime: file.type,
          width: dims ? dims.width : null,
          height: dims ? dims.height : null,
          duration_seconds: duration,
        })))).then((atts) => LimeStore.sendMessage(conversationId, { content: content || null, metadata, attachments: atts }).then(appendMessage))
          .catch(console.error);
      },
    });
  }

  // ── Merged Messages list (LIME-19b, delegated LIME-24b) ──
  // Direct + group conversations in one list, newest activity first
  // (no-activity conversations last, alphabetical among themselves).
  // refreshList() both builds the list the first time and re-syncs it on
  // every lime:conversations-changed/lime:messages-changed event — rows
  // can be created (a brand new conversation) or disappear (deleted,
  // archived) at any time now, not just reordered, so every pass
  // recomputes the full membership rather than assuming yesterday's set
  // of rows is still the right one. Existing rows are updated and moved
  // in place (never recreated) — later code (recent-highlight and the
  // mobile view router, both further down this file) delegates its own
  // click handling for exactly this reason, rather than binding once to
  // whatever rows happen to exist at that moment.
  function sortConversations(conversations) {
    return [...conversations].sort((a, b) => {
      const la = LimeStore.getLatestActivity(a.id);
      const lb = LimeStore.getLatestActivity(b.id);
      if (la && lb) return new Date(lb.created_at) - new Date(la.created_at);
      if (la) return -1;
      if (lb) return 1;
      return LimeStore.getConversationTitle(a).localeCompare(LimeStore.getConversationTitle(b));
    });
  }

  function buildRow(conversation) {
    const latest = LimeStore.getLatestActivity(conversation.id);
    const li = document.createElement('li');
    li.className = 'lime-contact';
    li.dataset.conversationId = conversation.id;
    li.dataset.searchText = conversationSearchText(conversation);
    li.innerHTML = conversationRowHtml(conversation, latest);
    li.addEventListener('click', () => selectConversation(conversation));
    li.querySelectorAll('.lime-avatar[data-name]').forEach(paintAvatar);
    return li;
  }

  function updateRow(li, conversation) {
    const latest = LimeStore.getLatestActivity(conversation.id);
    const nameEl = li.querySelector('.lime-contact__name');
    const previewEl = li.querySelector('.lime-contact__preview');
    const timeEl = li.querySelector('.lime-contact__time');
    // LIME-26: a rename is the first case where a conversation's own
    // title (not just its preview/time) needs to update in place — added
    // here rather than routing through profile-changed's forceRebuild
    // path, since this is cheap and always correct (the title is always
    // whatever LimeStore.getConversationTitle says right now).
    if (nameEl) nameEl.textContent = LimeStore.getConversationTitle(conversation);
    if (previewEl) previewEl.innerHTML = rowPreviewHtml(conversation, latest);
    if (timeEl) timeEl.textContent = latest ? formatTime(latest.created_at) : '';
  }

  // Shared by "All" and "Starred" (LIME-25) — same row shape, same
  // update-in-place/build-if-missing/drop-if-gone diff, just a different
  // target <ul> and (Starred only) source filter and empty-state message.
  // `forceRebuild` (LIME-31): updateRow only ever touches preview/time —
  // a profile rename changes neither, so a plain sync wouldn't repaint a
  // row's own name/avatar. Passing true skips the "update in place"
  // branch entirely and always rebuilds, for the one event that actually
  // needs it (lime:profile-changed, below).
  function syncSection(container, conversations, emptyMessage, forceRebuild) {
    const sorted = sortConversations(conversations);
    if (sorted.length === 0 && emptyMessage) {
      container.innerHTML = '<li class="lime-contact-list__empty">' + escapeHtml(emptyMessage) + '</li>';
      return sorted;
    }
    const seenIds = new Set();
    sorted.forEach((conversation) => {
      seenIds.add(conversation.id);
      let li = forceRebuild ? null : container.querySelector('[data-conversation-id="' + conversation.id + '"]');
      if (li) {
        updateRow(li, conversation);
      } else {
        const existing = container.querySelector('[data-conversation-id="' + conversation.id + '"]');
        if (existing) existing.remove();
        li = buildRow(conversation);
      }
      // appendChild on an already-attached node moves it — this both
      // places brand-new rows and re-sorts existing ones in the same pass.
      container.appendChild(li);
    });
    [...container.children].forEach((li) => {
      if (!seenIds.has(li.dataset.conversationId)) li.remove();
    });
    return sorted;
  }

  const starredList = document.getElementById('starred-list');
  const archivedList = document.getElementById('archived-list');
  const archivedSection = document.querySelector('.lime-section[data-section-id="archived"]');

  function starredConversations() {
    return LimeStore.listConversations({ types: ['direct', 'group'] }).filter((c) => {
      const membership = LimeStore.getMyMembership(c.id);
      return membership && membership.starred;
    });
  }

  // Archiving removes a conversation from All and Starred (both already
  // exclude archived by default — listConversations only includes them
  // with includeArchived: true) and lists it here instead. The section
  // itself hides entirely when this is empty — a different rule from
  // Starred's own always-shown "Star a chat…" empty message, per the brief.
  function archivedConversations() {
    return LimeStore.listConversations({ types: ['direct', 'group'], includeArchived: true }).filter((c) => {
      const membership = LimeStore.getMyMembership(c.id);
      return membership && membership.archived_at;
    });
  }

  function syncArchivedSection(forceRebuild) {
    if (!archivedList) return;
    const items = archivedConversations();
    syncSection(archivedList, items, null, forceRebuild);
    if (archivedSection) archivedSection.hidden = items.length === 0;
  }

  // ── Recent row (LIME-36) ─────────────────────────────────
  // "The latest activity involving them" is tracked per person, not per
  // conversation: a group's activity only counts toward whichever member
  // actually sent the message (there's no single "the conversation's
  // activity" that belongs to any one of several co-members), while a
  // DM's own latest activity counts toward its one partner regardless of
  // which of the two of you sent it — matching the brief's own "or your
  // latest DM activity with them" as an alternative signal, not just
  // "messages they sent."
  function recentContacts() {
    const conversations = LimeStore.listConversations({ types: ['direct', 'group'] }); // already excludes archived + deleted-for-me
    const latestByPerson = new Map();
    function bump(personId, at) {
      const existing = latestByPerson.get(personId);
      if (!existing || new Date(at) > new Date(existing)) latestByPerson.set(personId, at);
    }
    conversations.forEach((conversation) => {
      const msgs = LimeStore.listMessages(conversation.id); // already respects cleared_at
      const others = LimeStore.getMembers(conversation.id).filter((p) => p.id !== currentUserId);
      if (conversation.type === 'direct') {
        const other = others[0];
        if (!other) return;
        const latest = msgs.length ? msgs[msgs.length - 1].created_at : conversation.created_at;
        bump(other.id, latest);
      } else {
        others.forEach((person) => {
          const theirs = msgs.filter((m) => m.sender_id === person.id);
          if (theirs.length) bump(person.id, theirs[theirs.length - 1].created_at);
        });
      }
    });
    return [...latestByPerson.entries()]
      .map(([id, at]) => ({ person: LimeStore.getProfile(id), at }))
      .filter((entry) => entry.person)
      .sort((a, b) => new Date(b.at) - new Date(a.at))
      .slice(0, 10)
      .map((entry) => entry.person);
  }

  // Unread is "is there anything I haven't read in a conversation I
  // share with this person," not "did this specific person send
  // something unread" — a group's unread message from a *third* member
  // still puts the ring on every other member's own Recent row, per the
  // brief's own "a message from someone else newer than your last_read_at."
  function hasUnreadWith(personId) {
    return LimeStore.listConversations({ types: ['direct', 'group'] }).some((conversation) => {
      const members = LimeStore.getMembers(conversation.id);
      if (!members.some((p) => p.id === personId)) return false;
      const membership = LimeStore.getMyMembership(conversation.id);
      const lastReadAt = membership && membership.last_read_at;
      return LimeStore.listMessages(conversation.id).some((m) => m.sender_id !== currentUserId && (!lastReadAt || new Date(m.created_at) > new Date(lastReadAt)));
    });
  }

  function recentItemHtml(person, { isMe, unread, active } = {}) {
    const presence = presenceFor(person.status);
    const classes = ['lime-recent__item'];
    if (active) classes.push('lime-recent__item--active');
    if (unread) classes.push('lime-recent__item--unread');
    const label = isMe ? 'Me' : shortName(person.display_name);
    const searchText = (isMe ? 'me ' : '') + person.display_name.toLowerCase();
    // data-person-id, not data-profile-id — the latter is LIME-35's own
    // "open this person's details" trigger (a real bug, caught there,
    // came from exactly this kind of attribute collision); a Recent item
    // opens a DM instead (data-recent-me carves out "Me"'s own row,
    // which opens details instead, via the *existing* data-profile-id
    // mechanism — reused deliberately, not reinvented).
    return '<div class="' + classes.join(' ') + '" data-search-text="' + escapeHtml(searchText) + '"'
      + (isMe ? ' data-profile-id="' + person.id + '"' : ' data-person-id="' + person.id + '"') + '>'
      + '<span class="lime-avatar-frame lime-avatar-frame--lg">'
      + '<span class="seed-avatar seed-avatar--lg lime-avatar" data-name="' + escapeHtml(person.display_name) + '"></span>'
      + '<span class="lime-presence" data-presence="' + presence + '" role="img" aria-label="' + PRESENCE_LABEL[presence] + '"></span>'
      + '</span>'
      + '<span class="lime-recent__name">' + escapeHtml(label) + '</span>'
      + '</div>';
  }

  function renderRecentRow() {
    const container = document.querySelector('.lime-recent');
    if (!container) return;
    const me = LimeStore.getCurrentUser();
    if (!me) return;

    // "The active item follows the open DM" — only a DM has a single
    // person to highlight; a group has several co-members, none of them
    // uniquely "the" active Recent item.
    let activeOtherId = null;
    if (currentConversationId) {
      const conversation = LimeStore.getConversation(currentConversationId);
      if (conversation && conversation.type === 'direct') {
        const other = LimeStore.getMembers(conversation.id).find((p) => p.id !== currentUserId);
        if (other) activeOtherId = other.id;
      }
    }

    let html = recentItemHtml(me, { isMe: true });
    recentContacts().forEach((person) => {
      html += recentItemHtml(person, { unread: hasUnreadWith(person.id), active: person.id === activeOtherId });
    });

    // LIME-46: .fade-left/.fade-right now live one level up, as children
    // of .lime-recent-frame (this container's own non-scrolling parent),
    // not inside .lime-recent at all any more — container's own children
    // are only ever .lime-recent__item rows, so a full querySelectorAll
    // removal + fresh insert here can't touch them either way.
    container.querySelectorAll('.lime-recent__item').forEach((el) => el.remove());
    container.insertAdjacentHTML('beforeend', html);
    container.querySelectorAll('.lime-avatar[data-name]').forEach(paintAvatar);
  }

  // Delegated (LIME-24b's own reasoning) — Recent re-renders on every
  // conversations/messages change, so a one-time binding would go stale
  // the same way LIME-35's old sender-avatar handler did.
  document.addEventListener('click', (e) => {
    const item = e.target.closest('[data-person-id]');
    if (!item) return;
    // createConversation already reuses an existing DM via its own
    // dm_key check (a side-effect-free early return, confirmed in
    // store.js) — no need to search for one here first.
    LimeStore.createConversation({ type: 'direct', memberIds: [item.dataset.personId] })
      .then((conversation) => selectConversation(conversation))
      .catch(console.error);
  });

  let messageConversations = syncSection(list, LimeStore.listConversations({ types: ['direct', 'group'] }));
  if (starredList) syncSection(starredList, starredConversations(), 'Star a chat from its title menu.');
  syncArchivedSection();
  renderRecentRow();

  document.addEventListener('lime:conversations-changed', () => {
    messageConversations = syncSection(list, LimeStore.listConversations({ types: ['direct', 'group'] }));
    if (starredList) syncSection(starredList, starredConversations(), 'Star a chat from its title menu.');
    syncArchivedSection();
    renderRecentRow();
  });
  document.addEventListener('lime:messages-changed', () => {
    messageConversations = syncSection(list, LimeStore.listConversations({ types: ['direct', 'group'] }));
    if (starredList) syncSection(starredList, starredConversations(), 'Star a chat from its title menu.');
    syncArchivedSection();
    renderRecentRow();
  });

  // LIME-31: "everywhere updates" for a profile change (own's or, once a
  // future brief lets anyone else's change too, theirs) — rows (name,
  // avatar cluster), the open thread's sender names/avatars, and the
  // open conversation's header avatar group, all forced to rebuild fresh
  // from the store rather than patched, since a rename touches fields
  // none of the lighter per-row update paths above ever look at.
  document.addEventListener('lime:profile-changed', () => {
    messageConversations = syncSection(list, LimeStore.listConversations({ types: ['direct', 'group'] }), null, true);
    if (starredList) syncSection(starredList, starredConversations(), 'Star a chat from its title menu.', true);
    syncArchivedSection(true);

    if (currentConversationId) {
      const conversation = LimeStore.getConversation(currentConversationId);
      if (conversation) {
        renderThread(currentConversationId);
        if (crumbThread) crumbThread.textContent = LimeStore.getConversationTitle(conversation);
        if (openProfileAvatars) {
          openProfileAvatars.innerHTML = conversationHeaderAvatarsHtml(conversation);
          openProfileAvatars.querySelectorAll('.lime-avatar[data-name]').forEach(paintAvatar);
        }
      }
    }

    updateProfileEverywhere();
  });

  // ── Conversation actions menu (LIME-25) ─────────────────
  // Rebuilt fresh from CONVERSATION_ACTIONS every time it opens, for
  // whichever conversation is currently open — never assembled once and
  // left stale, since Star/Unstar's own label depends on live state.
  const conversationMenu = document.getElementById('conversation-menu');
  const conversationMenuToggle = document.getElementById('conversation-menu-toggle');

  // LIME-34: "the same menu everywhere" — every item always renders now
  // (no more isVisible filtering, no more dropping a divider that would
  // otherwise have nothing on one side of it — Archive and Delete both
  // always show, so the divider between them never needs that check).
  // An action `can()` rejects renders disabled instead of hidden, muted,
  // with a one-line reason under its label.
  function renderConversationMenu() {
    if (!conversationMenu || !currentConversationId) return;
    const conversation = LimeStore.getConversation(currentConversationId);
    if (!conversation) return;
    const membership = LimeStore.getMyMembership(currentConversationId);

    conversationMenu.innerHTML = CONVERSATION_ACTIONS.map((action) => {
      if (action.divider) return '<div class="lime-menu__divider" role="separator"></div>';
      const label = typeof action.label === 'function' ? action.label(conversation, membership) : action.label;
      const disabled = !!(action.disabled && action.disabled(conversation, membership));
      const reason = disabled && action.reason ? action.reason(conversation, membership) : null;
      const dangerClass = action.danger && !disabled ? ' lime-menu__item--danger' : '';
      const disabledAttr = disabled ? ' aria-disabled="true"' : '';
      return '<button type="button" class="lime-menu__item' + dangerClass + '" role="menuitem" data-action="' + action.id + '"' + disabledAttr + '>'
        + '<span class="dew ' + action.icon + '"></span>'
        + '<span class="lime-menu__item-label">' + escapeHtml(label)
        + (reason ? '<span class="lime-menu__item-reason">' + escapeHtml(reason) + '</span>' : '')
        + '</span>'
        + '<span class="lime-menu__kbd">' + escapeHtml(action.key) + '</span>'
        + '</button>';
    }).join('');
  }

  function runConversationAction(actionId) {
    if (!currentConversationId) return;
    const action = CONVERSATION_ACTIONS.find((a) => a.id === actionId);
    if (!action) return;
    const conversation = LimeStore.getConversation(currentConversationId);
    const membership = LimeStore.getMyMembership(currentConversationId);
    if (!conversation) return;
    if (action.disabled && action.disabled(conversation, membership)) return;
    action.run(conversation, membership).catch(console.error);
    if (conversationMenu) conversationMenu.classList.remove('is-open');
  }

  if (conversationMenuToggle) {
    // Registered before wireDropdownToggle's own click listener below (on
    // the same button, same event) — listeners fire in registration
    // order, so the menu's contents are already fresh by the time that
    // one measures offsetHeight/offsetWidth to position it.
    conversationMenuToggle.addEventListener('click', renderConversationMenu);
  }
  if (conversationMenu) {
    conversationMenu.addEventListener('click', (e) => {
      const item = e.target.closest('[data-action]');
      if (item) runConversationAction(item.dataset.action);
    });
  }
  // The hint-key shortcut ("like Claude's") — only while the menu is open,
  // and not while the user is actually typing somewhere (a plain "s"
  // keystroke in the composer shouldn't star the open conversation).
  document.addEventListener('keydown', (e) => {
    if (!conversationMenu || !conversationMenu.classList.contains('is-open')) return;
    const active = document.activeElement;
    if (active && (active.tagName === 'INPUT' || active.tagName === 'TEXTAREA' || active.isContentEditable)) return;
    const action = CONVERSATION_ACTIONS.find((a) => a.key && a.key.toLowerCase() === e.key.toLowerCase());
    if (!action || !currentConversationId) return;
    // LIME-34: "its key hint doesn't fire" for a disabled item — the
    // shortcut has to respect the same can()-backed check the menu
    // itself already applies, or e.g. R would rename a DM the menu
    // itself only ever shows greyed out.
    const conversation = LimeStore.getConversation(currentConversationId);
    if (!conversation) return;
    const membership = LimeStore.getMyMembership(currentConversationId);
    if (action.disabled && action.disabled(conversation, membership)) return;
    runConversationAction(action.id);
  });
  // aria-expanded has no single choke point to update from (the menu can
  // close via its own toggle, an outside click, Escape, or another
  // dropdown opening) — a MutationObserver on its own is-open class covers
  // every path without touching wireDropdownToggle's shared logic.
  if (conversationMenu && conversationMenuToggle) {
    new MutationObserver(() => {
      conversationMenuToggle.setAttribute('aria-expanded', String(conversationMenu.classList.contains('is-open')));
    }).observe(conversationMenu, { attributes: true, attributeFilter: ['class'] });
  }
  if (conversationMenuToggle) wireDropdownToggle('conversation-menu-toggle', 'conversation-menu', { fixed: true });

  if (messageConversations.length > 0) {
    selectConversation(messageConversations[0]);
  }

  // LIME-26: fills in the module-scope bridge CONVERSATION_ACTIONS' own
  // rename/delete entries call through (see conversationActionHooks'
  // own comment, near registeredDropdowns, for why the indirection).
  conversationActionHooks.startRename = startRename;
  conversationActionHooks.selectTopOrEmpty = selectTopOrEmpty;

  updateProfileEverywhere();
}

// LIME-30's profile-menu-header population, extended in LIME-31 to also
// cover the sidebar's own user name/avatar (static "Shem R" until now,
// never actually reactive to the session's real current user) — both
// called once at init (from initMessagesList, above) and again on every
// lime:profile-changed.
function updateProfileEverywhere() {
  const user = LimeStore.getCurrentUser();
  if (!user) return;

  // Profile menu header (LIME-30). Phone is "or nothing" here (not "Not
  // set", the settings pane's own convention) — a compact header, not a
  // field list.
  const profileMenuEmail = document.getElementById('profile-menu-email');
  const profileMenuPhone = document.getElementById('profile-menu-phone');
  if (profileMenuEmail) profileMenuEmail.textContent = user.email || '';
  if (profileMenuPhone) profileMenuPhone.textContent = user.phone || '';

  // Sidebar user name + avatar (LIME-31).
  const sidebarAvatar = document.querySelector('#user-btn .lime-avatar');
  const sidebarName = document.querySelector('#user-btn .lime-sidebar__user-name');
  if (sidebarAvatar) repaintAvatar(sidebarAvatar, user.display_name);
  if (sidebarName) sidebarName.textContent = shortName(user.display_name);
}

// Every existing paintAvatar call site before LIME-31 only ever painted a
// brand-new element (renderThread/buildRow/etc. always build fresh
// markup), so a stale lime-avatar--pN class was never a real scenario —
// this is the first place that repaints an *existing* element in place,
// so the old palette class has to be removed first or both would apply,
// and whichever one wins would depend on stylesheet order, not on which
// was painted more recently.
function repaintAvatar(el, name) {
  [...el.classList].forEach((c) => { if (/^lime-avatar--p\d+$/.test(c)) el.classList.remove(c); });
  el.dataset.name = name;
  el.textContent = '';
  paintAvatar(el);
}

// LIME-25/26/34: the title caret's menu, data-driven from the start so
// this stays the only place that needs to change. Final order (the
// brief's own): Star · Rename · Archive/Unarchive · divider · Delete, on
// EVERY conversation now (LIME-34: no more hiding an unavailable item —
// `disabled`/`reason` grey it out with an explanation instead). LIME-27
// will add Share and Copy link here too, between Rename and Archive,
// visible everywhere like the rest.
const CONVERSATION_ACTIONS = [
  {
    id: 'star',
    label: (conversation, membership) => (membership && membership.starred ? 'Unstar' : 'Star'),
    icon: 'dew-star',
    key: 'S',
    danger: false,
    run: (conversation, membership) => LimeStore.setStarred(conversation.id, !(membership && membership.starred)),
  },
  {
    id: 'rename',
    label: 'Rename',
    icon: 'dew-pencil',
    key: 'R',
    danger: false,
    disabled: (conversation) => !LimeStore.can('rename', conversation),
    reason: (conversation) => LimeStore.canReason('rename', conversation),
    run: (conversation) => {
      if (conversationActionHooks.startRename) conversationActionHooks.startRename(conversation);
      return Promise.resolve();
    },
  },
  // LIME-27 adds Share and Copy link here, between Rename and Archive.
  {
    id: 'archive',
    label: (conversation, membership) => (membership && membership.archived_at ? 'Unarchive' : 'Archive'),
    icon: 'dew-archive',
    key: 'A',
    danger: false,
    run: (conversation, membership) => LimeStore.setArchived(conversation.id, !(membership && membership.archived_at)),
  },
  { divider: true },
  {
    id: 'delete',
    // LIME-34: a DM's own "Delete" is delete-for-me (there's no
    // delete-for-everyone for a DM in v1 — Archive already covers "make
    // it go away for just me" for everyone else) — the label makes that
    // distinction explicit rather than reusing the owned-group wording
    // for a meaningfully different action.
    label: (conversation) => (conversation.type === 'direct' ? 'Delete for me' : 'Delete'),
    icon: 'dew-trash',
    key: 'D',
    danger: true,
    disabled: (conversation) => !LimeStore.can('delete', conversation),
    reason: (conversation) => LimeStore.canReason('delete', conversation),
    run: (conversation) => {
      const title = LimeStore.getConversationTitle(conversation);
      if (conversation.type === 'direct') {
        return confirmDialog({
          title: 'Delete for me?',
          message: 'Delete your copy of this chat with ' + title + '? They’ll still have theirs.',
          confirmLabel: 'Delete',
          danger: true,
        }).then((confirmed) => {
          if (!confirmed) return;
          return LimeStore.deleteForMe(conversation.id).then(() => {
            if (conversationActionHooks.selectTopOrEmpty) conversationActionHooks.selectTopOrEmpty();
          });
        });
      }
      return confirmDialog({
        title: 'Delete "' + title + '"?',
        message: 'This removes it for everyone in it. This can’t be undone.',
        confirmLabel: 'Delete',
        danger: true,
      }).then((confirmed) => {
        if (!confirmed) return;
        return LimeStore.deleteConversation(conversation.id).then(() => {
          if (conversationActionHooks.selectTopOrEmpty) conversationActionHooks.selectTopOrEmpty();
        });
      });
    },
  },
];

LimeStore.init().then(initMessagesList).catch(console.error);

// ── Contact preview truncation ───────────────────────────
// text-overflow: ellipsis has no effect on a flex container (only on
// block containers per spec) — .lime-contact__preview is flex so an
// optional leading icon lines up with the text. Wrapping the trailing
// text node in its own span gives ellipsis something it'll actually
// apply to, without needing every instance of the markup rewritten.
(function () {
  document.querySelectorAll('.lime-contact__preview').forEach((el) => {
    const textNodes = [...el.childNodes].filter((n) => n.nodeType === Node.TEXT_NODE && n.textContent.trim());
    if (textNodes.length === 0) return;
    const span = document.createElement('span');
    span.className = 'lime-contact__preview-text';
    textNodes.forEach((n) => span.appendChild(n));
    el.appendChild(span);
  });
})();

// ── Avatar identity system (declarations moved above the contacts/
// thread render below — see LIME-18-fix comment there for why) ──
// This one-time sweep still runs here, after that render: it catches
// the static Recent-row avatars, the sidebar's own avatar, and the
// contact list's rows, none of which call paintAvatar individually.
document.querySelectorAll('.lime-avatar[data-name]').forEach(paintAvatar);

// ── Panel resize (outer left/right dividers) ─────────────
(function () {
  const layout      = document.getElementById('layout');
  const leftHandle  = document.getElementById('left-handle');
  const rightHandle = document.getElementById('right-handle');
  if (!layout || !leftHandle || !rightHandle) return;

  const MIN_LEFT   = 200; // nav-only panel, no conversation list anymore
  const MIN_RIGHT  = 240;
  const MIN_CENTER = 800; // 320px conversation list + 480px chat, both live here now
  const GAP        = 16;

  function getWidth(prop, fallback) {
    return parseFloat(getComputedStyle(layout).getPropertyValue(prop)) || fallback;
  }

  function initResize(handleEl, side) {
    const prop     = side === 'left' ? '--left-width'  : '--right-width';
    const other    = side === 'left' ? '--right-width' : '--left-width';
    const min      = side === 'left' ? MIN_LEFT  : MIN_RIGHT;
    const otherMin = side === 'left' ? MIN_RIGHT : MIN_LEFT;
    const storeKey = side === 'left' ? 'lime-left-width' : 'lime-right-width';

    handleEl.addEventListener('mousedown', (e) => {
      e.preventDefault();

      const startX     = e.clientX;
      const startWidth = getWidth(prop, min);
      let   pendingX   = startX;
      let   rafId      = null;

      handleEl.classList.add('is-dragging');
      layout.classList.add('is-resizing');
      layout.style.willChange         = 'grid-template-columns';
      document.body.style.cursor     = 'col-resize';
      document.body.style.userSelect = 'none';

      function onMove(e) {
        pendingX = e.clientX;
        if (rafId) return;
        rafId = requestAnimationFrame(() => {
          rafId = null;
          const contentW  = layout.clientWidth - 2 * GAP;
          const otherW    = getWidth(other, otherMin);
          const maxWidth  = Math.max(min, contentW - otherW - 2 * GAP - MIN_CENTER);
          const delta     = side === 'left' ? pendingX - startX : startX - pendingX;
          const newWidth  = Math.max(min, Math.min(maxWidth, startWidth + delta));
          layout.style.setProperty(prop, newWidth + 'px');
        });
      }

      function onUp() {
        if (rafId) cancelAnimationFrame(rafId);
        handleEl.classList.remove('is-dragging');
        layout.classList.remove('is-resizing');
        layout.style.willChange        = '';
        document.body.style.cursor     = '';
        document.body.style.userSelect = '';
        document.removeEventListener('mousemove', onMove);
        document.removeEventListener('mouseup',   onUp);
        localStorage.setItem(storeKey, getWidth(prop, min));
      }

      document.addEventListener('mousemove', onMove);
      document.addEventListener('mouseup',   onUp);
    });
  }

  const savedLeft  = localStorage.getItem('lime-left-width');
  const savedRight = localStorage.getItem('lime-right-width');
  if (savedLeft)  layout.style.setProperty('--left-width',  savedLeft  + 'px');
  if (savedRight) layout.style.setProperty('--right-width', savedRight + 'px');

  initResize(leftHandle,  'left');
  initResize(rightHandle, 'right');
})();

// ── Center divider (conversation list ↔ chat) ────────────
(function () {
  const centerBody = document.querySelector('.lime-center-body');
  const listCol    = document.getElementById('list-col');
  const handle     = document.getElementById('center-handle');
  if (!centerBody || !listCol || !handle) return;

  const MIN_LIST      = 240;
  const MIN_CHAT      = 480;
  const HANDLE_WIDTH  = 16;

  function getListWidth() {
    return parseFloat(getComputedStyle(listCol).width) || 320;
  }

  const saved = localStorage.getItem('lime-list-width');
  if (saved) listCol.style.setProperty('--list-width', saved + 'px');

  handle.addEventListener('mousedown', (e) => {
    e.preventDefault();

    const startX     = e.clientX;
    const startWidth = getListWidth();
    let   pendingX   = startX;
    let   rafId      = null;

    handle.classList.add('is-dragging');
    document.body.style.cursor     = 'col-resize';
    document.body.style.userSelect = 'none';

    function onMove(e) {
      pendingX = e.clientX;
      if (rafId) return;
      rafId = requestAnimationFrame(() => {
        rafId = null;
        const maxWidth = Math.max(MIN_LIST, centerBody.clientWidth - HANDLE_WIDTH - MIN_CHAT);
        const delta    = pendingX - startX;
        const newWidth = Math.max(MIN_LIST, Math.min(maxWidth, startWidth + delta));
        listCol.style.setProperty('--list-width', newWidth + 'px');
      });
    }

    function onUp() {
      if (rafId) cancelAnimationFrame(rafId);
      handle.classList.remove('is-dragging');
      document.body.style.cursor     = '';
      document.body.style.userSelect = '';
      document.removeEventListener('mousemove', onMove);
      document.removeEventListener('mouseup',   onUp);
      localStorage.setItem('lime-list-width', getListWidth());
    }

    document.addEventListener('mousemove', onMove);
    document.addEventListener('mouseup',   onUp);
  });
})();

// Wires a toggle button whose icon (a) reflects the current state at rest
// and (b) previews the *other* state on hover — a common affordance for
// "here's what clicking this does". `paint(showAlt)` draws either the
// resting icon or its alternate; `apply(next)` commits a state change.
function wireHoverPreviewToggle(toggle, initial, paint, apply) {
  let state = initial;
  paint(state);

  toggle.addEventListener('mouseenter', () => paint(!state));
  toggle.addEventListener('mouseleave', () => paint(state));
  toggle.addEventListener('click', () => {
    state = !state;
    apply(state);
    paint(!state); // still hovering post-click — keep previewing the next toggle
  });

  // External closers (Escape, a breakpoint change) call this so the
  // toggle's own private state stays in sync and its next click is correct.
  return {
    set(next) {
      state = next;
      apply(state);
      paint(state);
    },
  };
}

// Shared by every trigger that opens/closes the right panel
// (open-profile-avatars, open-replies, #right-panel-toggle itself, the
// mobile router, auto-collapse-on-shrink, and the LIME-03n message
// sender/avatar triggers below) — the single place that actually flips
// the panel's open/closed state, so every trigger stays correct
// regardless of how #right-panel-toggle itself is currently wired.
function setRightPanelOpen(isOpen) {
  const layout = document.getElementById('layout');
  const toggle = document.getElementById('right-panel-toggle');
  if (!layout) return;
  layout.classList.toggle('seed-layout--right-hidden', !isOpen);
  if (toggle) toggle.setAttribute('aria-expanded', String(isOpen));
  localStorage.setItem('lime-right-panel-open', String(isOpen));
  // LIME-35: the panel crumb is "absent when the right panel is closed"
  // — every path that flips this (the close button, crumb-thread,
  // showPersonDetails/showMembers opening it) goes through here, so one
  // call covers all of them instead of each caller remembering to.
  renderCrumbs();
}

// ── Per-person details / group Members panels (LIME-35) ──
// Replaces the old hard-coded "Jean Chung" markup and the one-time
// forEach that used to bind clicks on whatever .lime-message__sender/
// .lime-avatar elements existed at page-parse time (broken the moment a
// conversation switch replaced #thread-messages's content, and it never
// actually identified *which* sender was clicked anyway — every click
// just showed the same static Jean Chung regardless). Top-level, not
// inside initMessagesList's closure — LimeStore and plain DOM lookups
// are all either function needs, so neither has to reach into that
// closure's private state.

// Set only while showPersonDetails was reached *from* the Members list
// — its own back chevron re-shows Members instead of doing nothing
// (there's no other way back to Members once you've clicked through).
let detailsReturnTo = null;

function localTimeFor(timezone) {
  if (!timezone) return null;
  try {
    return new Date().toLocaleTimeString([], { hour: 'numeric', minute: '2-digit', timeZone: timezone }) + ' local time';
  } catch (e) {
    return null; // an unrecognized/invalid timezone string — omit rather than throw
  }
}

function renderProfilePanel(person) {
  const content = document.querySelector('.lime-profile__content');
  if (!content) return;
  const isOwn = person.id === LimeStore.getCurrentUserId();
  const roleSchool = [person.role, person.school].filter(Boolean).join(' · ');
  const localTime = localTimeFor(person.timezone);
  const presence = presenceFor(person.status);

  let html = '';
  if (detailsReturnTo === 'members') {
    html += '<button type="button" class="lime-profile__back" aria-label="Back to Members" title="Back"><span class="dew dew-chevron-left"></span></button>';
  }
  html += '<div class="lime-profile__header">'
    + '<span class="seed-avatar seed-avatar--xl lime-avatar lime-profile__avatar" data-name="' + escapeHtml(person.display_name) + '"></span>'
    + '</div>'
    + '<h2 class="lime-profile__name">' + escapeHtml(person.display_name) + '</h2>';
  if (roleSchool) html += '<p class="lime-profile__title">' + escapeHtml(roleSchool) + '</p>';
  if (person.pronouns) html += '<p class="lime-profile__pronouns">' + escapeHtml(person.pronouns) + '</p>';

  if (person.bio) {
    html += '<section class="lime-profile__section"><h3>About me</h3><p>' + escapeHtml(person.bio) + '</p></section>';
  }

  // email/local time are omitted when missing (the brief's own "missing
  // fields are simply omitted"); status always has a value (presenceFor
  // falls back to "away" for anything it doesn't recognize), so it's
  // never conditionally left out the way the other two are.
  let contact = '';
  if (person.email) contact += '<p><span class="dew dew-chat"></span>' + escapeHtml(person.email) + '</p>';
  if (localTime) contact += '<p><span class="dew dew-calendar"></span>' + escapeHtml(localTime) + '</p>';
  contact += '<p><span class="lime-presence lime-presence--inline" data-presence="' + presence + '" role="img" aria-label="' + PRESENCE_LABEL[presence] + '"></span>' + PRESENCE_LABEL[presence] + '</p>';
  html += '<section class="lime-profile__section"><h3>Contact Information</h3>' + contact + '</section>';

  if (isOwn) {
    html += '<button type="button" class="seed-button seed-button--secondary seed-button--sm lime-profile__edit-btn" id="profile-edit-btn">Edit profile</button>';
  }

  content.innerHTML = html;
  const avatar = content.querySelector('.lime-avatar[data-name]');
  if (avatar) paintAvatar(avatar);
}

// openPanel=false (used only by the "keep the panel in sync with
// whichever conversation is open" call in selectConversation, below)
// updates the content without forcing anything open or switching the
// mobile view — otherwise merely switching conversations would yank
// open a panel the user had deliberately closed, or jump them to the
// mobile panel view while they're just browsing contacts.
function showPersonDetails(profileId, cameFromMembers, openPanel) {
  const person = LimeStore.getProfile(profileId);
  if (!person) return;
  const layout = document.getElementById('layout');
  const rightPanel = document.getElementById('right-panel');
  if (!layout || !rightPanel) return;
  detailsReturnTo = cameFromMembers ? 'members' : null;
  rightPanel.dataset.panel = 'profile';
  // shownProfileId, not profileId — a real bug found live: #right-panel
  // is an ancestor of every button inside it (including its own
  // .lime-profile__back), so naming this attribute the same as the
  // [data-profile-id] selector the global delegated listener (below)
  // matches on made #right-panel itself an unintended match for *any*
  // click bubbling through it — including the back button's own click,
  // which re-triggered showPersonDetails and stomped right back over
  // the showMembers() call the back button was supposed to make.
  rightPanel.dataset.shownProfileId = person.id;
  renderProfilePanel(person);
  if (openPanel !== false) {
    if (layout.classList.contains('seed-layout--right-hidden')) setRightPanelOpen(true);
    layout.setAttribute('data-mobile-view', 'panel');
  }
  renderCrumbs();
}

// Role isn't read from the store (this brief's own scope explicitly
// excludes touching it, and LimeStore.getMembers only ever returns
// profiles, not the membership row role lives on) — derived instead
// from conversations.created_by, already exposed via getConversation,
// which is exactly how role is assigned in the first place (see
// local-adapter.js's normalizeSeed: `role: userId === c.created_by ?
// 'owner' : 'member'`) and nothing anywhere ever changes it afterward.
function renderMembersPanel(conversation) {
  const titleEl = document.querySelector('.lime-members-panel__title');
  const listEl = document.querySelector('.lime-members-panel__list');
  if (!titleEl || !listEl) return;
  titleEl.textContent = LimeStore.getConversationTitle(conversation);
  const members = LimeStore.getMembers(conversation.id);
  listEl.innerHTML = members.map((m) => {
    const isOwner = m.id === conversation.created_by;
    return '<button type="button" class="lime-members-panel__row" data-profile-id="' + m.id + '">'
      + '<span class="seed-avatar seed-avatar--md lime-avatar" data-name="' + escapeHtml(m.display_name) + '"></span>'
      + '<div class="lime-members-panel__row-body">'
      + '<span class="lime-members-panel__row-name">' + escapeHtml(m.display_name) + '</span>'
      + '<span class="lime-members-panel__row-role">' + (isOwner ? 'Owner' : 'Member') + '</span>'
      + '</div>'
      + '</button>';
  }).join('');
  listEl.querySelectorAll('.lime-avatar[data-name]').forEach(paintAvatar);
}

function showMembers(conversation, openPanel) {
  const layout = document.getElementById('layout');
  const rightPanel = document.getElementById('right-panel');
  if (!layout || !rightPanel) return;
  rightPanel.dataset.panel = 'members';
  renderMembersPanel(conversation);
  if (openPanel !== false) {
    if (layout.classList.contains('seed-layout--right-hidden')) setRightPanelOpen(true);
    layout.setAttribute('data-mobile-view', 'panel');
  }
  renderCrumbs();
}

// Shared by #open-profile-avatars' own click handler and
// selectConversation's own "keep it in sync" call (openPanel=false
// there) — a DM's header opens the other person directly; a group's
// opens Members instead of a single person.
function showConversationHeaderPanel(conversation, openPanel) {
  if (!conversation) return;
  if (conversation.type === 'group') {
    showMembers(conversation, openPanel);
    return;
  }
  const other = LimeStore.getMembers(conversation.id).find((p) => p.id !== LimeStore.getCurrentUserId());
  if (other) showPersonDetails(other.id, false, openPanel);
}

// One delegated listener for every avatar/sender-name trigger, per the
// brief's own instruction — thread messages, the reply quote, the reply
// list, and Members rows all just need a data-profile-id attribute
// (already added at each of those HTML-building call sites) to work
// with this, rather than each surface wiring its own click handler.
document.addEventListener('click', (e) => {
  const trigger = e.target.closest('[data-profile-id]');
  if (!trigger || !trigger.dataset.profileId) return;
  showPersonDetails(trigger.dataset.profileId, !!trigger.closest('.lime-members-panel'));
});

// The profile panel's own content is rebuilt on every render (see
// renderProfilePanel), so its Edit-profile/back buttons need a
// delegated listener too, bound once to the stable .lime-profile
// container rather than re-attached after every innerHTML replacement.
(function () {
  const profileEl = document.querySelector('.lime-profile');
  if (!profileEl) return;
  profileEl.addEventListener('click', (e) => {
    if (e.target.closest('#profile-edit-btn')) {
      document.getElementById('settings-btn')?.click();
      return;
    }
    if (e.target.closest('.lime-profile__back')) {
      const activeRow = document.querySelector('.lime-contact--active');
      const conversationId = activeRow && activeRow.dataset.conversationId;
      const conversation = conversationId && LimeStore.getConversation(conversationId);
      if (conversation) showMembers(conversation);
    }
  });
})();

// LIME-35: the one place that computes and writes all three breadcrumb
// segments — Messages/Communities (following the active scope tab) /
// the open conversation's title / whichever panel is currently showing
// (a person's name, "Members", or "Thread", absent when the right
// panel is closed). Called on every state change that could affect any
// of the three, rather than each of those places writing its own
// fragment of the breadcrumb directly.
function renderCrumbs() {
  const crumbTeachers = document.getElementById('crumb-teachers');
  const crumbThread = document.getElementById('crumb-thread');
  const crumbPanel = document.getElementById('crumb-panel');
  const layout = document.getElementById('layout');
  const rightPanel = document.getElementById('right-panel');
  if (!crumbTeachers || !crumbThread || !crumbPanel || !layout || !rightPanel) return;

  const activeTab = document.querySelector('#scope-tablist [role="tab"][aria-selected="true"]');
  if (activeTab) crumbTeachers.textContent = activeTab.textContent.trim();

  // LIME-47: hoisted out of the "not editing" block below (it used to be
  // block-scoped there) — the DM-profile-crumb check further down needs
  // it too, and re-deriving it a second time from the DOM would just be
  // the same lookup twice.
  const activeRow = document.querySelector('.lime-contact--active');
  const conversationId = activeRow && activeRow.dataset.conversationId;
  const conversation = conversationId && LimeStore.getConversation(conversationId);

  // Not editing (LIME-34 owns crumbThread's text while renaming — this
  // would otherwise stomp on the in-progress edit on every state change).
  if (!crumbThread.isContentEditable) {
    // Empty, not left stale, when nothing's open (e.g. the last
    // conversation was just deleted — selectTopOrEmpty's own "none
    // left" branch relies on exactly this to clear the old title).
    crumbThread.textContent = conversation ? LimeStore.getConversationTitle(conversation) : '';
  }

  const panelOpen = !layout.classList.contains('seed-layout--right-hidden');
  let panelLabel = '';
  if (panelOpen) {
    const panelKind = rightPanel.dataset.panel;
    if (panelKind === 'members') {
      panelLabel = 'Members';
    } else if (panelKind === 'replies') {
      panelLabel = 'Thread';
      // "Thread · <parent sender's short name>" on mobile only — a real
      // bug caught live (Playwright): data-mobile-view is sticky (set
      // to "panel" by openReplies unconditionally, regardless of actual
      // window size, and never reset just because the window later
      // grows past 767px), so checking *it* showed the short name on
      // desktop too. window.innerWidth, checked live, is what actually
      // answers "is this mobile right now." text-overflow: ellipsis on
      // the breadcrumb (already in place) is what handles "if it fits,"
      // rather than measuring pixel widths here.
      if (window.innerWidth <= 767) {
        const quoteEl = document.getElementById('replies-quote');
        const senderId = quoteEl && quoteEl.dataset.senderId;
        const sender = senderId && LimeStore.getProfile(senderId);
        if (sender) panelLabel = 'Thread · ' + shortName(sender.display_name);
      }
    } else if (panelKind === 'profile') {
      const person = LimeStore.getProfile(rightPanel.dataset.shownProfileId);
      if (person) {
        // LIME-47: a DM's own title crumb is already that person's name
        // (getConversationTitle) — showing it a second time in the panel
        // crumb ("Messages / Jean Chung / Jean Chung") reads as a
        // mistake, not real information. "Profile" instead, but only
        // when the open DM is *with this exact person* — your own
        // details, or a group member's, still show their real name,
        // since neither of those is already named in the title crumb.
        const isDmWithShownPerson = conversation && conversation.type === 'direct'
          && person.id !== LimeStore.getCurrentUserId()
          && LimeStore.getMembers(conversation.id).some((m) => m.id === person.id);
        panelLabel = isDmWithShownPerson ? 'Profile' : person.display_name;
      }
    }
  }
  crumbPanel.textContent = panelLabel;
}

// ── Left nav panel toggle ────────────────────────────────
// Expanded (icon + label, full conversation list) is the default. The
// header toggle collapses it to Seed's 56px icon rail — it does not hide
// the panel outright.
(function () {
  const layout = document.getElementById('layout');
  const toggle = document.getElementById('left-panel-toggle');
  if (!layout || !toggle) return;

  const icon = toggle.querySelector('.dew');
  const COLLAPSED_WIDTH = 56;

  function paintIcon(isExpanded) {
    icon.classList.toggle('dew-sidebar-left-open',   isExpanded);
    icon.classList.toggle('dew-sidebar-left-closed', !isExpanded);
  }

  function applyExpanded(isExpanded) {
    layout.classList.toggle('seed-layout--collapsed-left', !isExpanded);
    if (isExpanded) {
      const saved = localStorage.getItem('lime-left-width');
      layout.style.setProperty('--left-width', (saved || '200') + 'px');
    } else {
      layout.style.setProperty('--left-width', COLLAPSED_WIDTH + 'px');
    }
    toggle.setAttribute('aria-expanded', String(isExpanded));
    localStorage.setItem('lime-left-panel-open', String(isExpanded));
  }

  // Starts expanded regardless of a stale localStorage value from an older
  // build — only an explicit "false" (the user collapsed it) keeps it closed.
  const saved = localStorage.getItem('lime-left-panel-open') !== 'false';
  applyExpanded(saved);
  wireHoverPreviewToggle(toggle, saved, paintIcon, applyExpanded);
})();

// ── Right profile panel toggle ──────────────────────────
// #right-panel-toggle has moved between .lime-center-top (a full
// open/close toggle) and inside #right-panel (close-only) repeatedly
// across recent briefs — LIME-03l in, LIME-03n out, LIME-03p in,
// LIME-03t out, LIME-03z in again. Currently: close-only, no
// icon-swap, since there's nothing to preview toward.
(function () {
  const layout = document.getElementById('layout');
  const toggle = document.getElementById('right-panel-toggle');
  if (!layout || !toggle) return;

  // Default flipped true -> false (LIME-10-fix9) — only changes first-ever
  // load with no saved preference; setRightPanelOpen always persists
  // whatever it's given, so anyone who already has a saved value (true or
  // false) from before this brief keeps seeing that, not this new default.
  const saved = localStorage.getItem('lime-right-panel-open');
  setRightPanelOpen(saved === null ? false : saved === 'true');

  toggle.addEventListener('click', () => setRightPanelOpen(false));

  // Second trigger: the participant avatar in the center top row opens
  // the panel (never closes it — closing is the dedicated button's job
  // now). The breadcrumb's "Jean Chung" segment (#crumb-thread) used to
  // double as this same trigger, but LIME-03g redefined it to mean "go
  // to thread" instead — it no longer opens the profile panel.
  // LIME-35: which panel it opens now depends on the conversation — a
  // DM opens the other person's own details directly; a group opens
  // Members instead (showConversationHeaderPanel, top-level, branches
  // on conversation.type so this one trigger doesn't have to).
  const openProfileAvatars = document.getElementById('open-profile-avatars');
  if (openProfileAvatars) {
    openProfileAvatars.addEventListener('click', () => {
      const activeRow = document.querySelector('.lime-contact--active');
      const conversationId = activeRow && activeRow.dataset.conversationId;
      const conversation = conversationId && LimeStore.getConversation(conversationId);
      showConversationHeaderPanel(conversation);
    });
  }
})();

// ── Reply thread panel ────────────────────────────────────
// #open-replies (the old trigger this listened for) was deleted from the
// markup back in LIME-06, when the hardcoded thread messages it lived on
// were removed — this whole handler, including the back button, has
// been dead code ever since (its early-return guard always fired since
// that id no longer existed). Rebuilt for LIME-11 as a delegated click
// on any thread message's real "Reply" action instead of a one-time
// forEach, so it keeps working after switching conversations replaces
// #thread-messages's content entirely. LIME-11-fix2 removed the back
// button from the markup entirely (no JS reference needed any more) and
// added reactions to the quote/replies, reusing .lime-message__actions/
// .lime-reaction-picker — see the generalized delegate further down.
(function () {
  const layout      = document.getElementById('layout');
  const rightPanel  = document.getElementById('right-panel');
  const quoteEl     = document.getElementById('replies-quote');
  const metaEl      = document.getElementById('replies-meta');
  const listEl      = document.getElementById('replies-list');
  if (!layout || !rightPanel || !quoteEl || !listEl) return;

  // LIME-39: no clearance mechanism needed here (survey confirmed:
  // #replies-composer is a normal-flow flex sibling of this list, not
  // position:absolute over it like the main composer — growing it
  // already reflows the list via flex, nothing to fix there) — but the
  // same "stay pinned through an attachment's own late-loading image"
  // fix still applies, so this still gets a sticky controller.
  const repliesSticky = createStickyScroll(listEl);

  let currentReplyParentId = null;

  function replyHtml(message, sender) {
    // LIME-41: replaces the old message.type === 'image'/'file' branch,
    // same reasoning as the main thread's contentHtml — a non-empty
    // getAttachments covers both a real album and a legacy single
    // attachment. wrap: false matches attachmentContentHtml's own old
    // unwrapped output here (the reply list has no message bubble chrome).
    const replyAttachments = LimeStore.getAttachments(message.id);
    return '<div class="lime-reply" data-message-id="' + message.id + '">'
      + '<span class="seed-avatar seed-avatar--sm lime-avatar" data-name="' + escapeHtml(sender.display_name) + '" data-profile-id="' + escapeHtml(sender.id) + '"></span>'
      + '<div class="lime-reply__col">'
      + '<div class="lime-reply__meta">'
      + '<span class="lime-reply__sender" data-profile-id="' + escapeHtml(sender.id) + '">' + escapeHtml(shortName(sender.display_name)) + '</span>'
      + '<span class="lime-reply__time">' + formatTime(message.created_at) + '</span>'
      + '</div>'
      + (replyAttachments.length > 0 ? albumHtml(message, replyAttachments, { wrap: false }) : messageBodyHtml(message, 'lime-reply__text') + linkPreviewSlotHtml(message))
      + '<div class="lime-message__reactions">' + reactionsHtml(message.id) + '</div>'
      + '</div>'
      + '<div class="lime-message__actions">'
      + '<button title="React"><span>🙂</span></button>'
      + '</div>'
      + REACTION_PICKER_HTML
      + '</div>';
  }

  function renderQuote(message, sender) {
    quoteEl.dataset.messageId = message.id;
    // data-sender-id (LIME-35): renderCrumbs reads this for the mobile
    // "Thread · <parent sender's short name>" panel-crumb format.
    quoteEl.dataset.senderId = sender.id;
    quoteEl.innerHTML = '<span class="seed-avatar seed-avatar--sm lime-avatar" data-name="' + escapeHtml(sender.display_name) + '" data-profile-id="' + escapeHtml(sender.id) + '"></span>'
      + '<div class="lime-replies-panel__quote-body">'
      + '<span class="lime-replies-panel__quote-sender" data-profile-id="' + escapeHtml(sender.id) + '">' + escapeHtml(shortName(sender.display_name)) + '</span>'
      + quoteMediaHtml(message)
      + '<p class="lime-replies-panel__quote-text">' + escapeHtml(plainPreviewFor(message)) + '</p>'
      + '<div class="lime-message__reactions">' + reactionsHtml(message.id) + '</div>'
      + '</div>'
      + '<div class="lime-message__actions">'
      + '<button title="React"><span>🙂</span></button>'
      + '</div>'
      + REACTION_PICKER_HTML;
    const avatar = quoteEl.querySelector('.lime-avatar[data-name]');
    if (avatar) paintAvatar(avatar);
    paintAttachments(quoteEl); // LIME-47
  }

  // reply_count/last_reply_at on the parent message are stale seed
  // metadata (see data.js) — this always computes the real, live count.
  function renderMeta(replies) {
    if (!metaEl) return;
    if (replies.length === 0) {
      metaEl.textContent = '';
      return;
    }
    const last = replies[replies.length - 1];
    metaEl.textContent = replies.length + (replies.length === 1 ? ' reply' : ' replies')
      + ' · last reply ' + formatLastReply(last.created_at);
  }

  function renderReplies(parentId) {
    const replies = LimeStore.listReplies(parentId);
    renderMeta(replies);
    listEl.innerHTML = '';
    if (replies.length === 0) {
      listEl.innerHTML = '<p class="lime-replies-panel__empty">No replies yet.</p>';
      return;
    }
    replies.forEach((reply) => {
      const sender = LimeStore.getProfile(reply.sender_id);
      if (!sender) return;
      listEl.insertAdjacentHTML('beforeend', replyHtml(reply, sender));
    });
    listEl.querySelectorAll('.lime-avatar[data-name]').forEach(paintAvatar);
    paintAttachments(listEl); // LIME-38
    paintLinkPreviews(listEl, repliesSticky); // LIME-44
  }

  function openReplies(messageId) {
    const message = LimeStore.getMessage(messageId);
    if (!message) return;
    const sender = LimeStore.getProfile(message.sender_id);
    if (!sender) return;
    currentReplyParentId = messageId;
    renderQuote(message, sender);
    renderReplies(messageId);
    if (layout.classList.contains('seed-layout--right-hidden')) setRightPanelOpen(true);
    rightPanel.setAttribute('data-panel', 'replies');
    layout.setAttribute('data-mobile-view', 'panel');
    renderCrumbs();
  }

  document.addEventListener('click', (e) => {
    const replyBtn = e.target.closest('#thread-messages .lime-message__actions [title="Reply"]');
    if (replyBtn) {
      const msg = replyBtn.closest('.lime-message');
      const messageId = msg && msg.dataset.messageId;
      if (messageId) openReplies(messageId);
      return;
    }

    // LIME-11-fix5, renamed by LIME-18: the reply summary under a
    // message is a second trigger for the exact same panel — carries
    // its own data-message-id directly (see replyIndicatorHtml in
    // messageHtml), so no .closest('.lime-message') lookup needed here.
    const indicator = e.target.closest('#thread-messages .lime-message__replies');
    if (indicator) openReplies(indicator.dataset.messageId);
  });

  // Reply composer: LIME-37 replaces the old duplicated expand/collapse +
  // auto-grow + is-active + Enter-to-send block (identical to the main
  // composer's own, minus a stickyScroll option — LIME-39 confirmed this
  // composer doesn't overlap its own list, so it has nothing to fix
  // there) with the same shared createComposer used by the main composer
  // above.
  const repliesComposer = document.getElementById('replies-composer');
  if (repliesComposer) {
    createComposer(repliesComposer, {
      onSend({ content, metadata, attachments }) {
        if (!currentReplyParentId) return Promise.resolve();
        const parentId = currentReplyParentId;
        const parent = LimeStore.getMessage(parentId);
        if (!parent) return Promise.resolve();

        function afterSend() {
          refreshReplyIndicator(parentId);
          renderReplies(parentId); // re-renders the whole list, including paintAttachments (LIME-38)
          repliesSticky.pinToBottom(); // LIME-39
        }

        // sendMessage with replyTo covers replies too (LIME-24b's contract
        // has no separate sendReply) — it already emits
        // lime:messages-changed, which the main list's own listener picks
        // up to re-sort; no manual event dispatch needed here the way the
        // old lime:activity one was. LIME-41 supersedes LIME-38's "text
        // first, then one message per attachment" — one message carries
        // the caption and the whole attachments array, same reasoning as
        // the main composer's own onSend above.
        const files = attachments || [];
        return Promise.all(files.map((file) => Promise.all([
          LimeStore.uploadAttachment(file, { conversationId: parent.conversation_id }),
          readImageDimensions(file),
          readAudioDuration(file),
        ]).then(([{ path }, dims, duration]) => ({
          path,
          name: file.name,
          size: file.size,
          mime: file.type,
          width: dims ? dims.width : null,
          height: dims ? dims.height : null,
          duration_seconds: duration,
        })))).then((atts) => LimeStore.sendMessage(parent.conversation_id, { content: content || null, metadata, replyTo: parentId, attachments: atts }).then(afterSend))
          .catch(console.error);
      },
    });
  }

  // Decorative placeholder, not real navigator.mediaDevices (LIME-10 gate)
  // — a second instance for the reply composer, own unique ids since the
  // main composer's voice-mode-toggle/-dropdown ids are already taken.
  wireDropdownToggle('replies-voice-mode-toggle', 'replies-voice-mode-dropdown', { fixed: true });
  // Same reasoning as the main composer's toolbar overflow menu (LIME-12-fix4).
  wireDropdownToggle('replies-composer-toolbar-overflow', 'replies-composer-toolbar-overflow-dropdown', { fixed: true });
})();

// ── Dropdown toggles (more menu, notifications, user menu) ──
// Same shape three times now (LIME-03r's more-menu, LIME-03u's
// notif/user menus) — one toggle button opens one dropdown, closes on
// any outside click. Generalized rather than copy-pasted a third time.
// `fixed: true` (notif/user menus) computes the dropdown's on-screen
// position from the trigger's own rect before opening it — required
// now that .lime-menu is position:fixed (LIME-03w's original reasoning
// for the old .lime-nav-dropdown, carried over by LIME-21's shared
// class), which has no relative-to-trigger anchor of its own the way
// position:absolute did. LIME-20: every registered dropdown now shares
// one Set (declared
// near the top of this file — see the comment there for why) so
// opening any of them closes whichever other one was open — the old
// per-call document listener alone couldn't do this, since each
// trigger's own stopPropagation() kept that click from ever reaching
// document when switching between two open menus. Fixed-mode menus
// also flip to whichever side of the trigger actually has room instead
// of always opening upward, and Escape closes whichever is open.
function wireDropdownToggle(toggleId, dropdownId, { fixed = false, placement = 'vertical', suppressClose } = {}) {
  const toggle = document.getElementById(toggleId);
  const dropdown = document.getElementById(dropdownId);
  if (!toggle || !dropdown) return;
  registeredDropdowns.add(dropdown);

  toggle.addEventListener('click', (e) => {
    e.stopPropagation();
    const opening = !dropdown.classList.contains('is-open');
    if (opening) {
      registeredDropdowns.forEach((d) => { if (d !== dropdown) d.classList.remove('is-open'); });
    }
    dropdown.classList.toggle('is-open');
    // Position after opening, not before — offsetHeight/offsetWidth are
    // 0 until the dropdown is actually visible (LIME-18-fix4 already
    // established this for the horizontal clamp; the same now applies
    // to the vertical flip added here).
    if (fixed && opening) {
      const rect = toggle.getBoundingClientRect();
      const gap = 8;
      const h = dropdown.offsetHeight;
      const w = dropdown.offsetWidth;

      // LIME-20-fix: notifications opens beside the bell instead of
      // covering the nav items below it — only when there's actually
      // room on the right (a narrow mobile drawer falls back to the
      // same vertical flip-and-clamp every other fixed menu uses).
      const fitsRight = placement === 'right' && rect.right + gap + w <= window.innerWidth - 8;
      if (fitsRight) {
        dropdown.style.left = (rect.right + gap) + 'px';
        dropdown.style.top = Math.max(8, Math.min(rect.top, window.innerHeight - h - 8)) + 'px';
        dropdown.style.bottom = '';
        return;
      }

      const fitsBelow = rect.bottom + gap + h <= window.innerHeight - 8;
      const fitsAbove = rect.top - gap - h >= 8;
      // Neither fits (a very short viewport): use whichever side has
      // more room rather than picking one arbitrarily.
      const openBelow = fitsBelow ? true : fitsAbove ? false : (window.innerHeight - rect.bottom) >= rect.top;
      // Clear the opposite property explicitly — a stale value from a
      // previous opening (when this same menu flipped the other way)
      // would otherwise still apply alongside the new one.
      dropdown.style.top = openBelow ? (rect.bottom + gap) + 'px' : '';
      dropdown.style.bottom = openBelow ? '' : (window.innerHeight - rect.top + gap) + 'px';
      const maxLeft = window.innerWidth - w - 8;
      dropdown.style.left = Math.max(8, Math.min(rect.left, maxLeft)) + 'px';
    }
  });
  // LIME-52-fix3: the appearance popover passes suppressClose so an
  // in-flight pattern upload keeps it open across the native file
  // picker and while processing runs, instead of an incidental outside
  // click (or one that lands oddly during/after the OS dialog) closing
  // it mid-pick.
  document.addEventListener('click', () => {
    if (suppressClose && suppressClose()) return;
    dropdown.classList.remove('is-open');
  });
}

// One shared listener — Escape closes whichever registered dropdown is
// currently open (at most one, per the close-others logic above).
document.addEventListener('keydown', (e) => {
  if (e.key === 'Escape') {
    registeredDropdowns.forEach((d) => d.classList.remove('is-open'));
  }
});

// LIME-20 tried this in fixed mode but had to revert — its CSS was
// still position:absolute then. Now on the shared .lime-menu (LIME-21),
// position:fixed, so it finally shares the same positioning path as
// every other menu.
wireDropdownToggle('more-menu-toggle', 'more-menu', { fixed: true });
// Opens beside the bell, not below it, so the nav items under it (Link,
// Jam) stay visible instead of getting covered (LIME-20-fix).
wireDropdownToggle('notif-btn', 'notif-dropdown', { fixed: true, placement: 'right' });
wireDropdownToggle('user-btn', 'user-dropdown', { fixed: true });
// Decorative placeholder, not a real navigator.mediaDevices list — per
// the LIME-10 gate, real device enumeration needs a live mic-permission
// prompt for a feature that still can't record anything.
wireDropdownToggle('voice-mode-toggle', 'voice-mode-dropdown', { fixed: true });
// Decorative relisting of the toolbar tools .lime-composer__tool--overflow
// hides at narrow widths (LIME-12-fix4) — none of those tools have any
// real formatting behavior wired regardless of width, so this dropdown
// doesn't need to either.
wireDropdownToggle('composer-toolbar-overflow', 'composer-toolbar-overflow-dropdown', { fixed: true });

// LIME-10's original expandable-composer IIFE (expand-on-focus, auto-grow,
// is-active Send) is gone — createComposer (LIME-37, above, called once
// for #composer and once for #replies-composer) now does this for both,
// replacing the two near-identical copies that used to live here and in
// the reply-panel closure.

// ── Shorter composer placeholder on narrow screens (LIME-12-fix4) ──
// A plain textarea placeholder has no native ellipsis truncation the way
// a single-line <input>'s does — "Say something meaningful..." simply
// wraps onto a second line in a narrow mobile viewport, which the
// fixed single-line collapsed height (LIME-10-fix9) then crudely
// clips. A CSS font-size tweak wouldn't have helped: the placeholder
// already inherits --seed-text-sm (14px), the exact value this
// brief's own literal CSS asked for — so this brief's other offered
// option (shorter text via JS) is the one that actually does
// something. Runs once at load, not on resize — the placeholder is
// only ever visible while the input is empty and unfocused, a state a
// live-resizing viewport doesn't really encounter. LIME-37: the
// composer is a contenteditable div now, with no native placeholder
// attribute — data-placeholder (read by CSS's :empty::before) instead.
(function () {
  if (window.innerWidth > 480) return;
  // Only the main composer's placeholder ("Say something meaningful...")
  // is long enough to wrap — the reply composer's ("Reply...") is
  // already short, nothing to shorten there.
  const input = document.getElementById('composer-input');
  if (input) input.dataset.placeholder = 'Message...';
})();

// ── Shorter reply-composer privacy text ─────────────────────
// Not width-gated like the placeholder fix above: the reply composer's
// own column is always narrow (the desktop right panel, or the full
// mobile "panel" view, itself no wider than that same panel), so its
// disclaimer text overflows regardless of the overall window width.
// A <span> does support CSS ellipsis (unlike the placeholder's
// <textarea>), so this was already truncating cleanly — shortened the
// actual text instead, so more of it stays legible in the space it has.
(function () {
  const privacy = document.querySelector('#replies-composer .lime-composer__privacy');
  if (privacy) privacy.innerHTML = '<span class="dew dew-shield-check"></span> Secure &amp; encrypted';
})();

// ── Reset demo data (LIME-24b, dialog swapped in LIME-26) ───
// Clears the persisted snapshot and reloads, so the next LimeStore.init()
// normalizes fresh from the embedded seed again, exactly like a
// first-ever visit.
document.getElementById('reset-demo-data-btn')?.addEventListener('click', () => {
  confirmDialog({
    title: 'Reset demo data?',
    message: 'Anything you’ve sent, replied, or reacted with will be cleared, and the original seed data comes back.',
    confirmLabel: 'Reset',
  }).then((confirmed) => {
    if (!confirmed) return;
    LimeStore.reset().then(() => window.location.reload());
  });
});

// ── Sign out ───────────────────────────────────────────────
// index.html has no auth-gate check on load (a deliberate LIME-05a
// decision — a real gate would redirect here on every direct open,
// breaking this whole workflow without a real backend), so this only
// ends the *current* session; nothing stops opening index.html directly
// again afterward. LIME-31: the actual clear-session-and-redirect logic
// now lives in LimeAuth.signOut() (the auth seam's own signOut, which
// the Settings modal's own Sign out row also calls, via this same
// button) — this handler just calls it, rather than the two duplicating
// the same two lines.
document.getElementById('sign-out-btn')?.addEventListener('click', () => {
  LimeAuth.signOut();
});

// ── Notification click ───────────────────────────────────
// Closes the dropdown. "select that contact" (per the brief's prose)
// isn't actually implemented beyond that — the given behavior only
// closes the dropdown, and the thread has no real per-contact
// switching to hook into (it's a static Shem↔Jean 1:1 throughout).
document.querySelectorAll('.lime-notif').forEach((n) => {
  n.addEventListener('click', (e) => {
    e.preventDefault();
    document.getElementById('notif-dropdown')?.classList.remove('is-open');
  });
});

// ── Shared modal open/close + focus trap (LIME-30) ───────
// Extracted from the search modal (LIME-22 built the original version of
// this) so the new Settings modal doesn't duplicate it. Handles the
// backdrop+modal is-open toggle, initial focus via onOpen, a Tab-trap
// scoped to the modal's own focusable elements, Escape, and returning
// focus on close.
//
// `returnFocusTo` (defaults to `trigger`) is who gets focused back on
// close — not always the same element as `trigger`. Two real bugs, both
// caught by testing in an actual headless Chrome, not by reasoning about
// the code: (1) the original search-modal approach captured
// document.activeElement at open time, but a *programmatic* .click() on
// a <button> doesn't reliably focus it the way a real mouse click does,
// so that capture could silently be the wrong element; fixed by using
// the explicitly-passed trigger instead. (2) Settings' own trigger,
// `#settings-btn`, lives inside the profile dropdown menu, which closes
// itself (and so becomes display:none) as soon as it's clicked — by the
// time the *settings modal* later closes, .focus() on a hidden element
// is a silent no-op, and focus just stays wherever it was. `returnFocusTo`
// lets a caller point focus somewhere that's still actually visible
// (Settings passes #user-btn, the dropdown's own always-visible trigger)
// instead of the specific menu item that opened it.
// `onBeforeClose` (LIME-31) — an optional veto: returning exactly `false`
// cancels the close (Escape, backdrop click, and the close button all go
// through this same path). Settings uses it to ask "Discard changes?"
// before closing over an unsaved Profile edit; the search modal doesn't
// pass one, so its own behavior is unaffected.
function createModal({ trigger, returnFocusTo, backdrop, modal, closeBtn, onOpen, onClose, onBeforeClose }) {
  const focusTarget = returnFocusTo || trigger;

  function focusable() {
    return [...modal.querySelectorAll('button, [href], input, select, textarea, [tabindex]:not([tabindex="-1"])')]
      .filter((el) => !el.disabled && el.offsetParent !== null);
  }

  function onKeydown(e) {
    if (e.key === 'Escape') {
      close();
      return;
    }
    if (e.key !== 'Tab') return;
    const items = focusable();
    if (items.length === 0) return;
    const first = items[0];
    const last  = items[items.length - 1];
    if (e.shiftKey && document.activeElement === first) {
      e.preventDefault();
      last.focus();
    } else if (!e.shiftKey && document.activeElement === last) {
      e.preventDefault();
      first.focus();
    }
  }

  function open() {
    backdrop.classList.add('is-open');
    modal.classList.add('is-open');
    if (onOpen) onOpen();
    document.addEventListener('keydown', onKeydown);
  }

  function finishClose() {
    backdrop.classList.remove('is-open');
    modal.classList.remove('is-open');
    document.removeEventListener('keydown', onKeydown);
    if (onClose) onClose();
    if (focusTarget) focusTarget.focus();
  }

  // LIME-26: onBeforeClose can now also return a Promise (e.g.
  // confirmDialog's own return value) — this was previously always
  // synchronous. A plain `false` still vetoes the close immediately, as
  // before; anything else still closes immediately too, so every
  // existing sync caller (Settings' confirmDiscardIfDirty) is unaffected
  // by this extension.
  function close() {
    if (!onBeforeClose) { finishClose(); return; }
    const result = onBeforeClose();
    if (result === false) return;
    if (result && typeof result.then === 'function') {
      result.then((proceed) => { if (proceed !== false) finishClose(); });
      return;
    }
    finishClose();
  }

  if (trigger) trigger.addEventListener('click', open);
  backdrop.addEventListener('click', close);
  if (closeBtn) closeBtn.addEventListener('click', close);

  return { open, close, focusable };
}

// ── App confirm dialog (LIME-26) ─────────────────────────
// Replaces both native window.confirm() calls (Reset demo data, Settings'
// "Discard changes?") and backs Delete's own confirmation. One static
// modal instance, reused for every call — its content and button labels
// are rewritten per call rather than built fresh, since only one
// confirmation is ever open at a time in this app.
const confirmDialogEls = {
  backdrop: document.getElementById('confirm-dialog-backdrop'),
  modal: document.getElementById('confirm-dialog'),
  title: document.getElementById('confirm-dialog-title'),
  message: document.getElementById('confirm-dialog-message'),
  cancelBtn: document.getElementById('confirm-dialog-cancel'),
  confirmBtn: document.getElementById('confirm-dialog-confirm'),
};

// Escape and a backdrop click both mean "cancel" (the brief's own rule) —
// pendingResult starts false on every call and only ever flips to true
// from the Confirm button's own click, right before it triggers the same
// close() path Escape/backdrop use. Whichever path closes it, onBeforeClose
// below is the single place that resolves the call's Promise and restores
// focus, so all four ways of leaving the dialog behave identically.
let confirmDialogResolve = null;
let confirmDialogPendingResult = false;
let confirmDialogPreviouslyFocused = null;

const confirmDialogModal = confirmDialogEls.modal && confirmDialogEls.backdrop
  ? createModal({
      backdrop: confirmDialogEls.backdrop,
      modal: confirmDialogEls.modal,
      onBeforeClose: () => {
        if (confirmDialogResolve) {
          const resolve = confirmDialogResolve;
          confirmDialogResolve = null;
          resolve(confirmDialogPendingResult);
        }
        if (confirmDialogPreviouslyFocused && confirmDialogPreviouslyFocused.focus) {
          confirmDialogPreviouslyFocused.focus();
        }
        confirmDialogPreviouslyFocused = null;
        return true;
      },
      // Focus lands on Cancel (the brief's own rule) — the safer default
      // for a dialog that can be destructive when confirmed.
      onOpen: () => { if (confirmDialogEls.cancelBtn) confirmDialogEls.cancelBtn.focus(); },
    })
  : null;

function confirmDialog({ title, message, confirmLabel, cancelLabel, danger }) {
  const els = confirmDialogEls;
  if (!confirmDialogModal || !els.title || !els.message || !els.cancelBtn || !els.confirmBtn) {
    return Promise.resolve(false); // the modal markup is missing — fail closed, never silently "confirmed"
  }

  els.title.textContent = title;
  els.message.textContent = message;
  els.cancelBtn.textContent = cancelLabel || 'Cancel';
  els.confirmBtn.textContent = confirmLabel || 'Confirm';
  els.confirmBtn.classList.toggle('seed-button--primary', !danger);
  els.confirmBtn.classList.toggle('lime-confirm-dialog__confirm--danger', !!danger);

  confirmDialogPreviouslyFocused = document.activeElement;
  confirmDialogPendingResult = false;
  els.cancelBtn.onclick = () => { confirmDialogPendingResult = false; confirmDialogModal.close(); };
  els.confirmBtn.onclick = () => { confirmDialogPendingResult = true; confirmDialogModal.close(); };

  return new Promise((resolve) => {
    confirmDialogResolve = resolve;
    confirmDialogModal.open();
  });
}

// ── Image viewer + photo wall (LIME-38/40/40-fix/41, restructured
// LIME-41-fix) ─────────────────────────────────────────────
// Two static instances (the viewer/"lightbox" and the full-screen photo
// wall), one shared backdrop between them — a real two-level stack now,
// not the LIME-41 gallery-card's own "close the other one first, it's a
// hand-off not a stack" workaround. Managed with bespoke open/close/
// focus-trap logic here rather than the shared createModal helper every
// *other* modal in this app uses: two independent createModal instances
// stacked (tried for LIME-41's gallery card) each install their own
// document keydown listener, and a single Escape press fired both —
// fine for a plain hand-off, not for "Escape steps back exactly one
// level," which needs one single owner of the Escape key, not two
// independent ones.
const lightboxEls = {
  modal: document.getElementById('lightbox'),
  closeBtn: document.getElementById('lightbox-close'),
  backBtn: document.getElementById('lightbox-back'),
  img: document.getElementById('lightbox-img'),
  counter: document.getElementById('lightbox-counter'),
  prevBtn: document.getElementById('lightbox-prev'),
  nextBtn: document.getElementById('lightbox-next'),
};
const wallEls = {
  wall: document.getElementById('photo-wall'),
  closeBtn: document.getElementById('wall-close'),
  masonry: document.getElementById('wall-masonry'),
};
const viewerBackdrop = document.getElementById('lightbox-backdrop');

let lightboxOpen = false;
let lightboxOpenedFromWall = false;
let lightboxPreviouslyFocused = null;
let wallOpen = false;
let wallPreviouslyFocused = null;

// LIME-40, scoping changed by LIME-41: a flat list of *attachments*
// (`{ path, name, ... }`, LimeStore.getAttachments' own shape), not
// messages — a message can now carry several. Recomputed fresh on every
// open, not cached, so a message sent while the viewer is closed is
// always reflected next time it opens.
//
// Three different sources, chosen per click (see the click listeners
// below): a message with 2+ images of its own scopes to just that
// message's images (an album's tiles open only onto each other, per the
// brief); a message with 0 or 1 image of its own — a legacy single-
// attachment message, or a new message that just happens to carry one —
// keeps LIME-40's original whole-conversation scope, flattened across
// every message's own images; a wall tile scopes to the wall's own full
// album (LIME-41-fix).
let lightboxImages = [];
let lightboxIndex = 0;

function lightboxUpdateNav() {
  const total = lightboxImages.length;
  const showNav = total > 1;
  if (lightboxEls.prevBtn) lightboxEls.prevBtn.hidden = !showNav || lightboxIndex <= 0;
  if (lightboxEls.nextBtn) lightboxEls.nextBtn.hidden = !showNav || lightboxIndex >= total - 1;
  if (lightboxEls.counter) {
    lightboxEls.counter.hidden = !showNav;
    if (showNav) lightboxEls.counter.textContent = (lightboxIndex + 1) + ' / ' + total;
  }
}

// Resolves through the same LimeStore.getAttachmentUrl every other
// attachment uses — not the DOM thumbnail's own already-resolved src,
// since navigating to a neighbor there's no guarantee a painted
// thumbnail for it even exists on screen right now.
function lightboxShow(index) {
  const att = lightboxImages[index];
  if (!att) return;
  lightboxIndex = index;
  if (att.path) {
    LimeStore.getAttachmentUrl(att.path).then((url) => {
      if (lightboxEls.img) lightboxEls.img.src = url;
    }).catch(console.error);
  }
  if (lightboxEls.img) lightboxEls.img.alt = att.name || '';
  lightboxUpdateNav();
}

function showViewerBackdrop() { if (viewerBackdrop) viewerBackdrop.classList.add('is-open'); }
function hideViewerBackdrop() { if (viewerBackdrop) viewerBackdrop.classList.remove('is-open'); }

// Hides the viewer itself only — never touches the wall or the shared
// backdrop, since this also runs for the "back to all photos" case,
// where both of those need to stay exactly as they were.
function lightboxHideVisualsOnly() {
  if (lightboxEls.img) lightboxEls.img.src = ''; // stop showing the last image while hidden
  if (lightboxEls.modal) lightboxEls.modal.classList.remove('is-open');
  // Siblings of .lime-lightbox, not children of it (LIME-40) — they
  // don't inherit its own display:none-when-closed, so hiding has to
  // set these explicitly too, not just re-gate them on the next open.
  if (lightboxEls.prevBtn) lightboxEls.prevBtn.hidden = true;
  if (lightboxEls.nextBtn) lightboxEls.nextBtn.hidden = true;
  if (lightboxEls.counter) lightboxEls.counter.hidden = true;
  if (lightboxEls.backBtn) lightboxEls.backBtn.hidden = true;
  lightboxImages = [];
  lightboxOpen = false;
}

function closeWallVisualsOnly() {
  if (wallEls.wall) wallEls.wall.classList.remove('is-open');
  if (wallEls.masonry) wallEls.masonry.innerHTML = '';
  wallOpen = false;
}

// The brief's own two-level Escape/close semantics: from the viewer
// *when it was opened from the wall*, one step back re-shows the wall
// (already open underneath — it was never hidden or rebuilt, so its
// scroll position is exactly where it was); everywhere else, a close
// action closes the whole stack down to nothing. Used by Escape, the
// viewer's own × button, the wall's own × button, and a backdrop click —
// one function per meaning, not one meaning re-implemented four times.
function backToWall() {
  lightboxHideVisualsOnly();
  lightboxOpenedFromWall = false;
  if (wallEls.closeBtn) wallEls.closeBtn.focus();
}

function closeStack() {
  const returnTo = wallOpen ? wallPreviouslyFocused : lightboxPreviouslyFocused;
  lightboxHideVisualsOnly();
  lightboxOpenedFromWall = false;
  if (wallOpen) closeWallVisualsOnly();
  hideViewerBackdrop();
  if (returnTo && returnTo.focus) returnTo.focus();
  lightboxPreviouslyFocused = null;
  wallPreviouslyFocused = null;
}

// One step back: the viewer's own close/Escape, when it was opened from
// the wall, goes back to the wall instead of closing everything —
// exactly what the dedicated "back to all photos" button also does, so
// all three (Escape, ×, back-button) agree on what "back" means from
// here. Anywhere else, it's a full close.
function lightboxStepBack() {
  if (lightboxOpenedFromWall) backToWall();
  else closeStack();
}

function openLightbox(images, index, options) {
  const fromWall = !!(options && options.fromWall);
  lightboxImages = images;
  lightboxOpenedFromWall = fromWall;
  if (lightboxEls.backBtn) lightboxEls.backBtn.hidden = !fromWall;
  if (!fromWall) lightboxPreviouslyFocused = document.activeElement;
  showViewerBackdrop();
  if (lightboxEls.modal) lightboxEls.modal.classList.add('is-open');
  lightboxOpen = true;
  lightboxShow(Math.min(Math.max(index, 0), images.length - 1));
  if (lightboxEls.closeBtn) lightboxEls.closeBtn.focus();
}

function openPhotoWall(messageId) {
  if (!wallEls.wall || !wallEls.masonry) return;
  const images = LimeStore.getAttachments(messageId).filter(isImageAttachment);
  wallEls.masonry.innerHTML = images.map((att, i) =>
    '<img class="lime-photo-wall__tile" data-message-id="' + escapeHtml(messageId) + '" data-attachment-path="' + escapeHtml(att.path || '') + '" data-attachment-index="' + i + '" alt="' + escapeHtml(att.name || '') + '">'
  ).join('');
  paintAttachments(wallEls.masonry);
  wallPreviouslyFocused = document.activeElement;
  showViewerBackdrop();
  wallEls.wall.classList.add('is-open');
  wallOpen = true;
  if (wallEls.closeBtn) wallEls.closeBtn.focus();
}

// Direct thumbnail clicks — a thread message, a reply, or a reply quote.
// Excludes anything that also carries data-gallery-message-id (the "+N"
// overlay tile, LIME-41-fix): that tile opens the wall, handled by the
// separate delegated listener below, not the viewer at that one photo.
document.addEventListener('click', (e) => {
  const thumb = e.target.closest('.lime-message__image');
  if (!thumb || thumb.closest('[data-gallery-message-id]') || !lightboxEls.img) return;
  const container = thumb.closest('[data-message-id]');
  const messageId = container && container.dataset.messageId;
  const message = messageId && LimeStore.getMessage(messageId);
  const clickedIndex = Number(thumb.dataset.attachmentIndex || 0);
  let images = [];
  let index = 0;
  if (message) {
    const ownImages = LimeStore.getAttachments(message.id).filter(isImageAttachment);
    if (ownImages.length > 1) {
      // LIME-41: an album's own tiles open scoped to just that message's
      // images, not the whole conversation's — the brief's own "clicking
      // any tile opens the lightbox scoped to that message's own images."
      images = ownImages;
      index = Math.min(clickedIndex, ownImages.length - 1);
    } else {
      // LIME-40's original whole-conversation scope, unchanged for a
      // message with 0 or 1 image of its own — flattened across every
      // message's own images so an album sitting alongside single-image
      // sends in the same conversation still contributes all of its
      // images here, not just a placeholder single entry.
      images = LimeStore.listMessages(message.conversation_id)
        .flatMap((m) => LimeStore.getAttachments(m.id).filter(isImageAttachment).map((att) => Object.assign({}, att, { _messageId: m.id })));
      const foundIndex = images.findIndex((att) => att._messageId === messageId);
      index = foundIndex === -1 ? 0 : foundIndex;
    }
  }
  // The clicked thumbnail's own already-resolved src shows instantly —
  // no need to wait on a second getAttachmentUrl round trip for the
  // very image the user just clicked. openLightbox's own lightboxShow
  // call resolves the "real" URL right after, harmlessly redundant for
  // this first frame.
  openLightbox(images, index, { fromWall: false });
  lightboxEls.img.src = thumb.src;
  lightboxEls.img.alt = thumb.alt;
});

// Wall tiles — always scoped to the wall's own full album (LIME-41-fix).
document.addEventListener('click', (e) => {
  const tile = e.target.closest('.lime-photo-wall__tile');
  if (!tile) return;
  const messageId = tile.dataset.messageId;
  const images = LimeStore.getAttachments(messageId).filter(isImageAttachment);
  const index = Number(tile.dataset.attachmentIndex || 0);
  openLightbox(images, index, { fromWall: true });
  lightboxEls.img.src = tile.src;
  lightboxEls.img.alt = tile.alt;
});

// The "N photos" label and the "+N" overlay tile (both carry
// data-gallery-message-id) — always opens the wall.
document.addEventListener('click', (e) => {
  const trigger = e.target.closest('[data-gallery-message-id]');
  if (!trigger) return;
  openPhotoWall(trigger.dataset.galleryMessageId);
});

if (lightboxEls.closeBtn) lightboxEls.closeBtn.addEventListener('click', lightboxStepBack);
if (lightboxEls.backBtn) lightboxEls.backBtn.addEventListener('click', backToWall);
if (wallEls.closeBtn) wallEls.closeBtn.addEventListener('click', closeStack);
if (viewerBackdrop) {
  viewerBackdrop.addEventListener('click', () => {
    if (lightboxOpen) lightboxStepBack();
    else if (wallOpen) closeStack();
  });
}

if (lightboxEls.prevBtn) lightboxEls.prevBtn.addEventListener('click', () => lightboxShow(lightboxIndex - 1));
if (lightboxEls.nextBtn) lightboxEls.nextBtn.addEventListener('click', () => lightboxShow(lightboxIndex + 1));

function trapModalTab(e, containerEl) {
  if (e.key !== 'Tab' || !containerEl) return;
  const items = [...containerEl.querySelectorAll('button, [href], input, select, textarea, [tabindex]:not([tabindex="-1"])')]
    .filter((el) => !el.disabled && el.offsetParent !== null);
  if (items.length === 0) return;
  const first = items[0];
  const last = items[items.length - 1];
  if (e.shiftKey && document.activeElement === first) { e.preventDefault(); last.focus(); }
  else if (!e.shiftKey && document.activeElement === last) { e.preventDefault(); first.focus(); }
}

// The single owner of Escape (and Tab-trapping) for this whole stack —
// exactly the "handle Escape in one place so nothing double-fires" the
// brief asks for. ←/→ stay scoped to the viewer only, unchanged from
// LIME-40 (doesn't wrap — lightboxShow's own array-bounds check plus the
// arrow buttons' own [hidden] gating already both agree on that).
document.addEventListener('keydown', (e) => {
  if (e.key === 'Escape') {
    if (lightboxOpen) { e.preventDefault(); lightboxStepBack(); }
    else if (wallOpen) { e.preventDefault(); closeStack(); }
    return;
  }
  if (e.key === 'Tab') {
    if (lightboxOpen) trapModalTab(e, lightboxEls.modal);
    else if (wallOpen) trapModalTab(e, wallEls.wall);
    return;
  }
  if (!lightboxOpen) return;
  if (e.key === 'ArrowLeft' && lightboxIndex > 0) { e.preventDefault(); lightboxShow(lightboxIndex - 1); }
  else if (e.key === 'ArrowRight' && lightboxIndex < lightboxImages.length - 1) { e.preventDefault(); lightboxShow(lightboxIndex + 1); }
});

// ── Nav search → global modal ────────────────────────────
// Distinct from the center panel's local filter: this searches everywhere
// (people, messages, jams), opens as a dialog, traps focus, and closes on
// Esc or a backdrop click.
(function () {
  const trigger  = document.getElementById('nav-search-trigger');
  const backdrop = document.getElementById('search-modal-backdrop');
  const modal    = document.getElementById('search-modal');
  const input    = document.getElementById('search-modal-input');
  const closeBtn = document.getElementById('search-modal-close');
  if (!trigger || !modal) return;

  const searchModal = createModal({
    trigger, backdrop, modal, closeBtn,
    onOpen: () => { input.value = ''; input.focus(); },
  });

  // .lime-menu__item, not the old .lime-search-modal__item (LIME-21b
  // unified them) — scoped to modal's own children, so this still only
  // ever matches these 4 result buttons, nothing from any other menu.
  modal.querySelectorAll('.lime-menu__item').forEach((item) => {
    item.addEventListener('click', searchModal.close);
  });
})();

// ── Settings modal (LIME-30, editable as of LIME-31) ──────
// Profile menu → Settings. Profile is a real form now, saved through
// LimeStore.updateProfile; Login & security's Change buttons open inline
// email/password forms through LimeAuth.
(function () {
  const trigger        = document.getElementById('settings-btn');
  const backdrop       = document.getElementById('settings-modal-backdrop');
  const modal          = document.getElementById('settings-modal');
  const closeBtn       = document.getElementById('settings-modal-close');
  const nav            = document.getElementById('settings-nav');
  const pane           = document.getElementById('settings-pane');
  const navSearchInput = document.getElementById('settings-nav-search-input');
  if (!trigger || !modal || !nav || !pane) return;

  const COMMON_TIMEZONES = [
    'America/New_York',
    'America/Chicago',
    'America/Denver',
    'America/Los_Angeles',
    'America/Anchorage',
    'Pacific/Honolulu',
  ];

  const PROFILE_FIELD_KEYS = ['display_name', 'pronouns', 'role', 'school', 'grade_levels', 'subjects', 'bio', 'timezone', 'phone'];

  // Kept in one place rather than derived from the DOM each time (the
  // brief's own "keep it simple" for the search filter) — row labels for
  // a section that isn't currently rendered aren't otherwise knowable.
  const SECTION_ROW_LABELS = {
    profile: ['Photo', 'Display name', 'Pronouns', 'Role', 'School', 'Grade levels', 'Subjects', 'Bio', 'Timezone', 'Phone'],
    security: ['Email', 'Password', 'Sign out'],
    preferences: ['Mode', 'Canvas'],
  };

  // The Profile form's loaded values, for dirty-checking against the
  // live inputs — reset every time renderProfileSection runs (a fresh
  // load, a Discard, or a successful Save all count as "clean" again).
  let profileOriginal = null;

  // LIME-46: wraps whichever section's .lime-settings__body in the shared
  // fade-frame pattern — a non-scrolling .lime-fade-frame that
  // wireScrollFades toggles is-scrolled-* classes on (LIME-50: the mask
  // itself lives on .lime-settings__body directly, gradients.css — no
  // fade divs any more). .lime-settings__body (unchanged identity/id,
  // still targeted by showSection's own scrollTop reset and
  // renderProfileSection's own getElementById('settings-profile-form'))
  // is the actual absolute-fill scroller inside it. Shared by both
  // sections below rather than duplicated, since they're otherwise
  // identical wrapping.
  function settingsBodyFrameOpen() {
    return '<div class="lime-fade-frame lime-settings__body-frame">';
  }
  const SETTINGS_BODY_FRAME_CLOSE = '</div>';

  function paneHeaderHtml(title, description) {
    // The back chevron is part of the pane's own rendered content, not a
    // static sibling — .lime-settings__pane's own display:none/block
    // toggle (mobile only) already gates its visibility, so it never
    // needs a re-render-proof listener of its own; a single delegated
    // click handler on #settings-pane (below) covers it regardless of
    // how many times the pane's content gets replaced.
    return '<button type="button" class="lime-settings__back" aria-label="Back to settings list" title="Back"><span class="dew dew-chevron-left"></span></button>'
      + '<div class="lime-settings__pane-header">'
      + '<h2 class="lime-settings__title" id="settings-pane-title">' + escapeHtml(title) + '</h2>'
      + '<p class="lime-settings__description">' + escapeHtml(description) + '</p>'
      + '</div>';
  }

  // LIME-31-fix: label-left, control-right row (Pronouns/Role/School/Grade
  // levels/Subjects/Timezone/Phone). data-field + a .lime-settings__field-error
  // descendant keep it compatible with fieldErrorEl/clearFieldError/setFieldError
  // below, which were written for the old .lime-settings__field layout.
  function compactRowHtml(key, label, controlHtml) {
    return '<div class="lime-settings__compact-row" data-field="' + key + '" data-row-label="' + escapeHtml(label) + '">'
      + '<label class="lime-settings__compact-label" for="settings-field-' + key + '">' + escapeHtml(label) + '</label>'
      + '<div class="lime-settings__compact-control">' + controlHtml + '<p class="lime-settings__field-error"></p></div>'
      + '</div>';
  }

  function compactInputHtml(key, value, inputAttrs) {
    return '<input class="seed-input" id="settings-field-' + key + '" ' + (inputAttrs || 'type="text"') + ' value="' + escapeHtml(value || '') + '">';
  }

  // LIME-52-fix: label-above, control-below (Mode/Canvas/Pattern) — not
  // label-left/control-right like compactRowHtml above, which was built
  // for a single ≤280px value (an input, a select). A tab strip or a
  // 4-column grid needs its own full-width row, matching the header
  // popover's own label-above structure (.lime-menu__label + control).
  function stackedRowHtml(key, label, controlHtml) {
    return '<div class="lime-settings__stacked-row" data-field="' + key + '" data-row-label="' + escapeHtml(label) + '">'
      + '<div class="lime-settings__stacked-label">' + escapeHtml(label) + '</div>'
      + '<div class="lime-settings__stacked-control">' + controlHtml + '<p class="lime-settings__field-error"></p></div>'
      + '</div>';
  }

  // Login & security row: label + muted description, "Change" opens an
  // inline form after it (see toggleInlineForm).
  function accountRowHtml(key, label, description) {
    return '<div class="lime-settings__account-row" data-row-label="' + escapeHtml(label) + '">'
      + '<div>'
      + '<div class="lime-settings__account-row-label">' + escapeHtml(label) + '</div>'
      + '<div class="lime-settings__account-row-value">' + escapeHtml(description) + '</div>'
      + '</div>'
      + '<button type="button" class="seed-button seed-button--secondary seed-button--sm" data-change="' + key + '">Change</button>'
      + '</div>';
  }

  function fieldHtml(key, label, value, inputAttrs) {
    return '<div class="lime-settings__field" data-field="' + key + '" data-row-label="' + escapeHtml(label) + '">'
      + '<label class="lime-settings__field-label" for="settings-field-' + key + '">' + escapeHtml(label) + '</label>'
      + '<input class="seed-input" id="settings-field-' + key + '" ' + (inputAttrs || 'type="text"') + ' value="' + escapeHtml(value || '') + '">'
      + '<p class="lime-settings__field-error"></p>'
      + '</div>';
  }

  function textareaFieldHtml(key, label, value) {
    return '<div class="lime-settings__field" data-field="' + key + '" data-row-label="' + escapeHtml(label) + '">'
      + '<label class="lime-settings__field-label" for="settings-field-' + key + '">' + escapeHtml(label) + '</label>'
      + '<textarea class="seed-input" id="settings-field-' + key + '">' + escapeHtml(value || '') + '</textarea>'
      + '<p class="lime-settings__field-error"></p>'
      + '</div>';
  }

  function timezoneFieldHtml(value) {
    // The current value is always in the list, even if it isn't one of
    // the "common" ones — otherwise selecting it would silently jump to
    // whatever the <select> defaults to, changing the profile's own
    // timezone as a side effect of just opening the form.
    const zones = (value && !COMMON_TIMEZONES.includes(value)) ? [value].concat(COMMON_TIMEZONES) : COMMON_TIMEZONES;
    const options = zones.map((z) => '<option value="' + escapeHtml(z) + '"' + (z === value ? ' selected' : '') + '>' + escapeHtml(z) + '</option>').join('');
    return compactRowHtml('timezone', 'Timezone', '<select class="seed-input" id="settings-field-timezone">' + options + '</select>');
  }

  function fieldErrorEl(key) {
    const field = pane.querySelector('[data-field="' + key + '"]');
    return field && field.querySelector('.lime-settings__field-error');
  }

  function clearFieldError(key) {
    const field = pane.querySelector('[data-field="' + key + '"]');
    if (!field) return;
    field.classList.remove('has-error');
    const errorEl = fieldErrorEl(key);
    if (errorEl) errorEl.textContent = '';
  }

  function setFieldError(key, message) {
    const field = pane.querySelector('[data-field="' + key + '"]');
    if (!field) return;
    field.classList.add('has-error');
    const errorEl = fieldErrorEl(key);
    if (errorEl) errorEl.textContent = message;
  }

  function getProfileFormValues() {
    const values = {};
    PROFILE_FIELD_KEYS.forEach((key) => {
      const el = document.getElementById('settings-field-' + key);
      if (el) values[key] = el.value;
    });
    return values;
  }

  // Pre-existing bug, found and fixed here (LIME-26): this only makes
  // sense while Profile is actually the rendered section. Once you've
  // navigated away (e.g. to Login & security) its fields aren't in the
  // DOM at all, getProfileFormValues() returns them all as undefined,
  // and every key compares unequal to profileOriginal — a false "dirty"
  // on a completely clean form, the instant you switch back or reopen
  // the modal. Previously invisible: window.confirm auto-accepted in
  // every test, and a silent native popup is easy to miss manually.
  // LIME-26's confirmDialog made it a real, visible, reproducible modal,
  // which is how this surfaced.
  function isProfileFormDirty() {
    if (!profileOriginal) return false;
    if (!document.getElementById('settings-field-display_name')) return false;
    const current = getProfileFormValues();
    return PROFILE_FIELD_KEYS.some((key) => current[key] !== profileOriginal[key]);
  }

  // LIME-31-fix: the footer is always visible; Save/Cancel are disabled
  // instead of the whole bar hiding (brief's "always-visible Save/Cancel").
  function updateFooterState() {
    const dirty = isProfileFormDirty();
    const saveBtn = document.getElementById('settings-save-btn');
    const discardBtn = document.getElementById('settings-discard-btn');
    if (saveBtn) saveBtn.disabled = !dirty;
    if (discardBtn) discardBtn.disabled = !dirty;
  }

  // The brief's own "leaving the section, or closing the modal, with
  // unsaved changes" gate — one function, called from every place that
  // can navigate away from a dirty Profile form (switching nav sections,
  // the mobile back chevron, and closing the modal itself via
  // createModal's onBeforeClose). Resolves false to mean "stay put."
  // LIME-26: now returns a Promise (confirmDialog is async) instead of a
  // plain boolean — every call site below awaits it, and createModal's
  // own onBeforeClose already knows how to await a thenable.
  function confirmDiscardIfDirty() {
    if (!isProfileFormDirty()) return Promise.resolve(true);
    return confirmDialog({
      title: 'Discard changes?',
      message: 'Your unsaved edits to this section will be lost.',
      confirmLabel: 'Discard',
    });
  }

  function renderProfileSection() {
    const user = LimeStore.getCurrentUser();
    profileOriginal = {
      display_name: user.display_name || '',
      pronouns: user.pronouns || '',
      role: user.role || '',
      school: user.school || '',
      grade_levels: (user.grade_levels || []).join(', '),
      subjects: (user.subjects || []).join(', '),
      bio: user.bio || '',
      timezone: user.timezone || '',
      phone: user.phone || '',
    };
    // LIME-31-fix layout: avatar beside Display name, then compact
    // label-left/control-right rows, Bio last, an always-visible footer
    // (Save/Cancel disabled until dirty — see updateFooterState).
    pane.innerHTML = paneHeaderHtml('Profile', 'Your details as others see them across Lime.')
      + settingsBodyFrameOpen()
      + '<div class="lime-settings__body" id="settings-profile-form">'
      + '<div class="lime-settings__profile-top" data-row-label="Photo">'
      + '<div class="lime-settings__profile-photo">'
      + '<span class="seed-avatar seed-avatar--xl lime-avatar" data-name="' + escapeHtml(user.display_name) + '"></span>'
      + '<div class="lime-settings__profile-photo-actions">'
      + '<button type="button" class="seed-button seed-button--secondary seed-button--sm" disabled>Upload photo</button>'
      + '<span class="lime-badge--soon">Soon</span>'
      + '</div>'
      + '</div>'
      + fieldHtml('display_name', 'Display name', profileOriginal.display_name)
      + '</div>'
      + compactRowHtml('pronouns', 'Pronouns', compactInputHtml('pronouns', profileOriginal.pronouns))
      + compactRowHtml('role', 'Role', compactInputHtml('role', profileOriginal.role))
      + compactRowHtml('school', 'School', compactInputHtml('school', profileOriginal.school))
      + compactRowHtml('grade_levels', 'Grade levels', compactInputHtml('grade_levels', profileOriginal.grade_levels))
      + compactRowHtml('subjects', 'Subjects', compactInputHtml('subjects', profileOriginal.subjects))
      + timezoneFieldHtml(profileOriginal.timezone)
      + compactRowHtml('phone', 'Phone', compactInputHtml('phone', profileOriginal.phone, 'type="tel"'))
      + textareaFieldHtml('bio', 'Bio', profileOriginal.bio)
      + '</div>'
      + SETTINGS_BODY_FRAME_CLOSE
      + '<div class="lime-settings__footer">'
      + '<button type="button" class="seed-button seed-button--secondary seed-button--sm" id="settings-discard-btn" disabled>Cancel</button>'
      + '<button type="button" class="seed-button seed-button--primary seed-button--sm" id="settings-save-btn" disabled>Save changes</button>'
      + '</div>';
    pane.querySelectorAll('.lime-avatar[data-name]').forEach(paintAvatar);

    const form = document.getElementById('settings-profile-form');
    if (form) form.addEventListener('input', updateFooterState);

    const discardBtn = document.getElementById('settings-discard-btn');
    if (discardBtn) discardBtn.addEventListener('click', renderProfileSection);

    const saveBtn = document.getElementById('settings-save-btn');
    if (saveBtn) {
      saveBtn.addEventListener('click', () => {
        const values = getProfileFormValues();
        PROFILE_FIELD_KEYS.forEach(clearFieldError);

        if (!values.display_name.trim()) {
          setFieldError('display_name', 'Display name is required.');
          return;
        }
        const phone = values.phone.trim();
        // Loose, per the brief: digits, spaces, +, -, (). Empty is fine
        // (phone isn't required) — only a non-empty value gets checked.
        if (phone && !/^[\d\s()+-]+$/.test(phone)) {
          setFieldError('phone', 'Enter a valid phone number.');
          return;
        }

        const patch = {
          display_name: values.display_name.trim(),
          pronouns: values.pronouns.trim() || null,
          role: values.role.trim() || null,
          school: values.school.trim() || null,
          grade_levels: values.grade_levels.split(',').map((s) => s.trim()).filter(Boolean),
          subjects: values.subjects.split(',').map((s) => s.trim()).filter(Boolean),
          bio: values.bio.trim() || null,
          timezone: values.timezone,
          phone: phone || null,
        };
        saveBtn.disabled = true;
        LimeStore.updateProfile(patch).then(() => {
          renderProfileSection(); // fresh values, and clears the dirty state
        }).catch((err) => {
          saveBtn.disabled = false;
          setFieldError('display_name', err.message);
        });
      });
    }
  }

  function passwordFieldHtml(id, label) {
    return '<div class="lime-settings__field" data-field="' + id + '">'
      + '<label class="lime-settings__field-label" for="settings-' + id + '">' + escapeHtml(label) + '</label>'
      + '<div class="lime-password-field">'
      + '<input class="seed-input" id="settings-' + id + '" type="password">'
      + '<button type="button" class="lime-password-field__toggle" aria-label="Show password"><span class="dew dew-eye-closed"></span></button>'
      + '</div>'
      + '</div>';
  }

  function emailChangeFormHtml() {
    return '<div class="lime-settings__inline-form" id="settings-inline-email">'
      + '<div class="lime-settings__field" data-field="new_email">'
      + '<label class="lime-settings__field-label" for="settings-new-email">New email</label>'
      + '<input class="seed-input" id="settings-new-email" type="email">'
      + '</div>'
      + '<p class="lime-settings__inline-error" id="settings-email-error" hidden></p>'
      + '<div class="lime-settings__inline-form-actions">'
      + '<button type="button" class="seed-button seed-button--secondary seed-button--sm" id="settings-email-cancel-btn">Cancel</button>'
      + '<button type="button" class="seed-button seed-button--primary seed-button--sm" id="settings-email-save-btn">Save</button>'
      + '</div>'
      + '</div>';
  }

  function passwordChangeFormHtml() {
    return '<div class="lime-settings__inline-form" id="settings-inline-password">'
      + passwordFieldHtml('current-password', 'Current password')
      + passwordFieldHtml('new-password', 'New password')
      + passwordFieldHtml('confirm-password', 'Confirm new password')
      + '<p class="lime-settings__inline-error" id="settings-password-error" hidden></p>'
      + '<p class="lime-settings__inline-success" id="settings-password-success" hidden></p>'
      + '<div class="lime-settings__inline-form-actions">'
      + '<button type="button" class="seed-button seed-button--secondary seed-button--sm" id="settings-password-cancel-btn">Cancel</button>'
      + '<button type="button" class="seed-button seed-button--primary seed-button--sm" id="settings-password-save-btn">Save</button>'
      + '</div>'
      + '</div>';
  }

  function wireEmailForm() {
    const saveBtn = document.getElementById('settings-email-save-btn');
    const cancelBtn = document.getElementById('settings-email-cancel-btn');
    if (!saveBtn) return;
    // Cancel just closes the inline form — toggleInlineForm('email') already
    // removes it when one is open, so re-calling it is the whole behavior.
    if (cancelBtn) cancelBtn.addEventListener('click', () => toggleInlineForm('email'));
    saveBtn.addEventListener('click', () => {
      const input = document.getElementById('settings-new-email');
      const errorEl = document.getElementById('settings-email-error');
      errorEl.hidden = true;
      saveBtn.disabled = true;
      LimeAuth.changeEmail(input.value).then(() => {
        renderSecuritySection(); // fresh render shows the new email; the inline form goes with it
      }).catch((err) => {
        saveBtn.disabled = false;
        errorEl.textContent = err.message;
        errorEl.hidden = false;
      });
    });
  }

  function wirePasswordForm() {
    const saveBtn = document.getElementById('settings-password-save-btn');
    const cancelBtn = document.getElementById('settings-password-cancel-btn');
    if (!saveBtn) return;
    if (cancelBtn) cancelBtn.addEventListener('click', () => toggleInlineForm('password'));
    saveBtn.addEventListener('click', () => {
      const current = document.getElementById('settings-current-password').value;
      const next = document.getElementById('settings-new-password').value;
      const confirm = document.getElementById('settings-confirm-password').value;
      const errorEl = document.getElementById('settings-password-error');
      const successEl = document.getElementById('settings-password-success');
      errorEl.hidden = true;
      successEl.hidden = true;
      saveBtn.disabled = true;
      LimeAuth.changePassword({ current, next, confirm }).then((result) => {
        saveBtn.disabled = false;
        successEl.textContent = result.message;
        successEl.hidden = false;
        ['settings-current-password', 'settings-new-password', 'settings-confirm-password'].forEach((id) => {
          document.getElementById(id).value = '';
        });
      }).catch((err) => {
        saveBtn.disabled = false;
        errorEl.textContent = err.message;
        errorEl.hidden = false;
      });
    });
  }

  // Only one inline form open at a time; clicking an already-open row's
  // Change button again closes it (a plain toggle).
  function toggleInlineForm(key) {
    const existingId = 'settings-inline-' + key;
    const existing = document.getElementById(existingId);
    pane.querySelectorAll('.lime-settings__inline-form').forEach((el) => el.remove());
    if (existing) return; // was open — the remove() above already closed it

    const rowLabel = key === 'email' ? 'Email' : 'Password';
    const row = pane.querySelector('[data-row-label="' + rowLabel + '"]');
    if (!row) return;
    if (key === 'email') {
      row.insertAdjacentHTML('afterend', emailChangeFormHtml());
      wireEmailForm();
      const input = document.getElementById('settings-new-email');
      if (input) input.focus();
    } else {
      row.insertAdjacentHTML('afterend', passwordChangeFormHtml());
      wirePasswordForm();
      const input = document.getElementById('settings-current-password');
      if (input) input.focus();
    }
  }

  function renderSecuritySection() {
    const user = LimeStore.getCurrentUser();
    // LIME-31-fix: Notion-style "Account security" / "Account" subsections
    // with headings and dividers, replacing the flat row list. No footer
    // here — changes are per-row via the inline Change forms above.
    pane.innerHTML = paneHeaderHtml('Login & security', 'How you sign in, and how to sign out.')
      + settingsBodyFrameOpen()
      + '<div class="lime-settings__body">'
      + '<h3 class="lime-settings__subsection-heading">Account security</h3>'
      + accountRowHtml('email', 'Email', user.email || 'Not set')
      + accountRowHtml('password', 'Password', 'Set a new password for your account.')
      + '<h3 class="lime-settings__subsection-heading">Account</h3>'
      + '<div class="lime-settings__account-row" data-row-label="Sign out">'
      + '<div class="lime-settings__account-row-label">Sign out</div>'
      + '<button type="button" class="seed-button seed-button--secondary seed-button--sm" id="settings-sign-out-btn">Sign out</button>'
      + '</div>'
      + '</div>'
      + SETTINGS_BODY_FRAME_CLOSE;
  }

  // LIME-52-fix: canvasGridHtml/patternGridHtml/patternControlsHtml are
  // the shared top-level builders also used by the header popover's
  // renderAppearanceMenu, above — not two copies. stackedRowHtml
  // (label-above, control-below) replaces compactRowHtml here for
  // Mode/Canvas/Pattern specifically — a tab strip or a 4-column grid
  // doesn't fit compactRowHtml's ≤280px label-left/control-right shape.
  function renderPreferencesSection() {
    const appearance = LimeStore.getAppearance();
    const isDark = document.documentElement.getAttribute('data-theme') === 'dark';
    pane.innerHTML = paneHeaderHtml('Preferences', 'How Lime looks for you.')
      + settingsBodyFrameOpen()
      + '<div class="lime-settings__body">'
      + '<h3 class="lime-settings__subsection-heading">Appearance</h3>'
      + stackedRowHtml('mode', 'Mode', modeTabsHtml('settings', appearance.theme))
      + stackedRowHtml('canvas', 'Canvas', (isDark ? canvasDisabledNoticeHtml() : '') + canvasGridHtml(isDark))
      + stackedRowHtml('pattern', 'Pattern', patternGridHtml(appearance.pattern, cachedUserPatternTiles) + patternControlsHtml(appearance.pattern))
      + '<p class="lime-settings__description">A subtle texture behind every panel. Sits at low intensity by default, and stays out of the way of anything you read.</p>'
      + '</div>'
      + SETTINGS_BODY_FRAME_CLOSE;
    paintAttachments(pane);
  }

  const SETTINGS_SECTIONS = [
    { id: 'profile', label: 'Profile', render: renderProfileSection },
    { id: 'security', label: 'Login & security', render: renderSecuritySection },
    { id: 'preferences', label: 'Preferences', render: renderPreferencesSection },
  ];

  // LIME-26: returns a Promise now (confirmDiscardIfDirty does) — both
  // call sites below already await it.
  function showSection(id) {
    return confirmDiscardIfDirty().then((proceed) => {
      if (!proceed) return false;
      nav.querySelectorAll('.lime-settings__nav-item').forEach((btn) => {
        btn.classList.toggle('is-active', btn.dataset.settingsSection === id);
      });
      const section = SETTINGS_SECTIONS.find((s) => s.id === id);
      if (section) section.render();
      // LIME-31-fix: the pane itself no longer scrolls (header/footer are
      // fixed); .lime-settings__body is the scrolling zone now.
      const body = pane.querySelector('.lime-settings__body');
      if (body) body.scrollTop = 0;
      // LIME-46: pane.innerHTML was just fully replaced (section.render()
      // above), so both the frame and the body are brand new elements —
      // rewired every time, not just once at parse time, unlike every
      // other wireScrollFades call (those elements are static markup and
      // only ever wired once, at the bottom of this file).
      const bodyFrame = pane.querySelector('.lime-settings__body-frame');
      if (body && bodyFrame) wireScrollFades(body, bodyFrame);
      return true;
    });
  }

  nav.querySelectorAll('.lime-settings__nav-item').forEach((btn) => {
    btn.addEventListener('click', () => {
      showSection(btn.dataset.settingsSection).then((switched) => {
        if (switched) modal.classList.add('is-showing-section'); // only visible ≤767px
      });
    });
  });

  // Delegated (not a direct listener on any one button) so these survive
  // every pane.innerHTML replacement without being re-attached each time.
  pane.addEventListener('click', (e) => {
    if (e.target.closest('.lime-settings__back')) {
      confirmDiscardIfDirty().then((proceed) => {
        if (proceed) modal.classList.remove('is-showing-section');
      });
      return;
    }
    if (e.target.closest('#settings-sign-out-btn')) {
      document.getElementById('sign-out-btn')?.click();
      return;
    }
    if (handleAppearanceClick(e, pane, renderPreferencesSection, (msg) => (msg ? setFieldError('pattern', msg) : clearFieldError('pattern')))) return;
    const changeBtn = e.target.closest('[data-change]');
    if (changeBtn) toggleInlineForm(changeBtn.dataset.change);
  });

  function filterSettings() {
    const query = (navSearchInput.value || '').trim().toLowerCase();
    nav.querySelectorAll('.lime-settings__nav-item').forEach((btn) => {
      const section = SETTINGS_SECTIONS.find((s) => s.id === btn.dataset.settingsSection);
      const rowLabels = SECTION_ROW_LABELS[btn.dataset.settingsSection] || [];
      const matches = !query
        || section.label.toLowerCase().includes(query)
        || rowLabels.some((label) => label.toLowerCase().includes(query));
      btn.style.display = matches ? '' : 'none';
    });
    let firstMatch = null;
    // LIME-31-fix: .lime-settings__row is gone — rows are now one of
    // .lime-settings__field (Display name, Bio), .lime-settings__compact-row
    // (Pronouns/Role/etc.), .lime-settings__profile-top (Photo), or
    // .lime-settings__account-row (Email/Password/Sign out) — all still
    // need the same highlight-and-scroll-into-view treatment.
    pane.querySelectorAll('.lime-settings__field, .lime-settings__compact-row, .lime-settings__profile-top, .lime-settings__account-row').forEach((row) => {
      const isMatch = !!query && (row.dataset.rowLabel || '').toLowerCase().includes(query);
      row.classList.toggle('is-highlighted', isMatch);
      if (isMatch && !firstMatch) firstMatch = row;
    });
    if (firstMatch) firstMatch.scrollIntoView({ block: 'nearest' });
  }

  if (navSearchInput) navSearchInput.addEventListener('input', filterSettings);

  createModal({
    trigger, backdrop, modal, closeBtn,
    // #settings-btn (the trigger) lives inside the profile dropdown,
    // which closes itself the moment it's clicked — by the time this
    // modal closes, focusing the now-hidden trigger would silently do
    // nothing (see createModal's own comment). #user-btn is that
    // dropdown's own trigger and stays visible regardless.
    returnFocusTo: document.getElementById('user-btn'),
    onBeforeClose: confirmDiscardIfDirty,
    onOpen: () => {
      if (navSearchInput) navSearchInput.value = '';
      modal.classList.remove('is-showing-section');
      // LIME-26: showSection is async now (confirmDiscardIfDirty goes
      // through confirmDialog, a Promise, even when it resolves
      // immediately) — filterSettings has to wait for Profile to have
      // actually rendered into the pane, or it reads the pane's stale
      // pre-render content.
      showSection('profile').then(() => {
        filterSettings();
        // Matches the search modal's own pattern (focus its input on
        // open) — without this, focus is left wherever it was, which
        // both reads oddly for a dialog and leaves the Tab-trap starting
        // from an element outside the modal entirely.
        if (navSearchInput) navSearchInput.focus();
      });
    },
  });
})();

// ── Group toggle (Teachers / Groups / Communities) + local search ──
// Switching segments re-scopes both the visible list and what the local
// search field filters — it never touches message content, unlike the
// nav search modal above.
(function () {
  const tablist = document.getElementById('scope-tablist');
  const input   = document.getElementById('local-search-input');
  if (!tablist) return;

  const tabs = [...tablist.querySelectorAll('[role="tab"]')];

  function filter() {
    const query = (input.value || '').trim().toLowerCase();
    const panel = document.querySelector('[data-scope-panel]:not([hidden])');
    if (!panel) return;
    panel.querySelectorAll('[data-search-text]').forEach((item) => {
      item.style.display = (!query || item.dataset.searchText.includes(query)) ? '' : 'none';
    });
  }

  function setScope(scope) {
    tabs.forEach((tab, index) => {
      const active = tab.dataset.scope === scope;
      tab.classList.toggle('seed-tab--active', active);
      tab.setAttribute('aria-selected', String(active));
      if (active) tablist.style.setProperty('--active-index', index);
    });
    document.querySelectorAll('[data-scope-panel]').forEach((panel) => {
      panel.hidden = panel.dataset.scopePanel !== scope;
    });
    // LIME-35: the breadcrumb's first segment tracking whichever scope
    // tab is active ("Messages"/"Communities") is now renderCrumbs' own
    // job (it re-reads the active tab directly) — one renderer for all
    // three crumb segments, not each state-change site writing its own
    // fragment of the breadcrumb.
    renderCrumbs();
    filter();
  }

  tabs.forEach((tab) => tab.addEventListener('click', () => setScope(tab.dataset.scope)));
  if (input) input.addEventListener('input', filter);
})();

// ── Collapsible sections (Recent / Starred / All Teachers, etc.) ───
(function () {
  document.querySelectorAll('.lime-section[data-section-id]').forEach((section) => {
    const toggle = section.querySelector('.lime-section__toggle');
    const key    = 'lime-section-' + section.dataset.sectionId;
    // LIME-26: every section before Archived has defaulted to expanded
    // when nothing's stored yet — Archived is the first that needs a
    // different first-open state ("collapsed by default," the brief's
    // own words), so it's read from a per-section data attribute rather
    // than hardcoding "archived" by name into this shared loop.
    const defaultCollapsed = section.dataset.defaultCollapsed === 'true';

    function setCollapsed(collapsed) {
      section.dataset.collapsed = String(collapsed);
      toggle.setAttribute('aria-expanded', String(!collapsed));
      localStorage.setItem(key, String(collapsed));
    }

    const stored = localStorage.getItem(key);
    setCollapsed(stored === null ? defaultCollapsed : stored === 'true');
    toggle.addEventListener('click', () => setCollapsed(section.dataset.collapsed !== 'true'));
  });
})();

// Contact selection (Recent row) — delegated (LIME-24b): the Messages
// list's own rows now render asynchronously (after LimeStore.init()) and
// can be added or removed later too, so a one-time forEach bound at parse
// time would miss anything that doesn't exist yet at that moment.
document.addEventListener('click', (e) => {
  const contact = e.target.closest('.lime-contact, .lime-recent__item');
  if (!contact) return;
  document.querySelectorAll('.lime-recent__item').forEach((c) => c.classList.remove('lime-recent__item--active'));
  contact.classList.add('lime-recent__item--active');
});

// ── Mobile nav drawer ─────────────────────────────────────
// Push model, no Seed overlay and no backdrop: the drawer just pushes
// the center panel narrower while staying fully visible and
// interactive next to it. The trigger is styled and wired like the
// existing left/right panel toggles (icon swaps open/closed, hover
// previews the alternate) rather than a plain hamburger with its own
// bespoke click handler. It closes via the hamburger, Escape, or
// widening past the mobile breakpoint.
(function () {
  const layout = document.getElementById('layout');
  const toggle = document.getElementById('mobile-nav-toggle');
  if (!layout || !toggle) return;

  const icon = toggle.querySelector('.dew');

  function paintIcon(isOpen) {
    icon.classList.toggle('dew-sidebar-left-open',   !isOpen);
    icon.classList.toggle('dew-sidebar-left-closed',  isOpen);
  }

  function applyOpen(isOpen) {
    layout.classList.toggle('seed-layout--mobile-open', isOpen);
    toggle.setAttribute('aria-expanded', String(isOpen));
  }

  applyOpen(false);
  const nav = wireHoverPreviewToggle(toggle, false, paintIcon, applyOpen);

  document.addEventListener('keydown', (e) => {
    if (e.key === 'Escape' && layout.classList.contains('seed-layout--mobile-open')) {
      nav.set(false);
    }
  });

  const mobileQuery = window.matchMedia('(max-width: 767px)');
  mobileQuery.addEventListener('change', (e) => {
    if (!e.matches) nav.set(false);
  });
})();

// ── Mobile view router (contacts / thread / panel) ───────
// #layout's data-mobile-view is the single source of truth for which
// full-width view shows below 768px (see the [data-mobile-view] rules
// in lime.css); above that breakpoint the attribute is simply inert.
// Triggers here layer onto elements that already have their own
// desktop-oriented click handlers (open-profile-avatars, open-replies)
// rather than replacing them.
(function () {
  const layout = document.getElementById('layout');
  if (!layout) return;

  function setView(view) {
    layout.setAttribute('data-mobile-view', view);
    renderCrumbs();
  }

  // Delegated (LIME-24b), same reasoning as the Recent-row highlight above.
  document.addEventListener('click', (e) => {
    if (e.target.closest('.lime-contact, .lime-recent__item')) setView('thread');
  });

  // #open-replies is stale (removed from the markup back in LIME-06 —
  // getElementById always returns null for it) — .filter(Boolean) has
  // always quietly dropped it; left as-is, not this brief's concern.
  [document.getElementById('open-profile-avatars'), document.getElementById('open-replies')]
    .filter(Boolean)
    .forEach((btn) => btn.addEventListener('click', () => setView('panel')));

  // right-panel-toggle is excluded from the "go to panel" list above —
  // LIME-03z made it close-only again (it lives inside #right-panel
  // once more), so on mobile it should only ever step back to
  // "thread", never open "panel" itself.
  const rightToggle = document.getElementById('right-panel-toggle');
  if (rightToggle) rightToggle.addEventListener('click', () => setView('thread'));

  // LIME-35: #crumb-thread is now purely an *ancestor* crumb — clicking
  // it closes whatever panel is open and returns to the thread (mobile:
  // "thread" view; desktop: the panel just closes), the inverse of its
  // old "opens the panel" job from LIME-03g/34. setRightPanelOpen(false)
  // is a harmless no-op when it's already closed, same as setView
  // re-setting an already-current view — this needs no extra guard for
  // "nothing to close" beyond the existing isContentEditable one, which
  // LIME-34 still needs while renaming in place.
  const crumbThread = document.getElementById('crumb-thread');
  if (crumbThread) {
    crumbThread.addEventListener('click', () => {
      if (crumbThread.isContentEditable) return;
      setRightPanelOpen(false);
      setView('thread');
    });
  }

  const crumbTeachers = document.getElementById('crumb-teachers');
  if (crumbTeachers) crumbTeachers.addEventListener('click', () => setView('contacts'));
})();

// ── Auto-collapse on shrink ────────────────────────────────
// One-shot nudges fired only on the downward crossing of a breakpoint —
// not a persistently forced state. The user's own toggle stays
// authoritative afterward; resizing back up never re-expands
// automatically. Scoped to the 1024px crossing only (desktop → tablet
// or steeper); this doesn't attempt to cover every possible resize
// path (e.g. mobile growing back into tablet range).
(function () {
  const rightToggle = document.getElementById('right-panel-toggle');
  const leftToggle   = document.getElementById('left-panel-toggle');
  let prevWidth = window.innerWidth;

  window.addEventListener('resize', () => {
    const width = window.innerWidth;
    const crossedDownInto1024 = width <= 1024 && prevWidth > 1024;

    if (crossedDownInto1024) {
      if (rightToggle && rightToggle.getAttribute('aria-expanded') === 'true') rightToggle.click();
      if (leftToggle && leftToggle.getAttribute('aria-expanded') === 'true') leftToggle.click();
    }

    prevWidth = width;
  });
})();

// ── Scroll-edge fades ─────────────────────────────────────
// A fade should only be visible when there's actually hidden content
// past that edge — not a permanent overlay that dims content even at
// rest. Toggles is-scrolled-* classes (read by gradients.css's
// .lime-fade-frame system) on `fadeHost`, which is always a *different*
// element than `scrollEl` (LIME-46: every call site below now follows
// this, not just the chat one) — the fade divs live in a non-scrolling
// frame precisely so scrolling the content never moves them; hosting
// them on the scroller itself was this brief's own bug #2 (three of the
// five original areas did exactly that).
function wireScrollFades(scrollEl, fadeHost, { horizontal = false } = {}) {
  if (!scrollEl || !fadeHost) return;

  function update() {
    if (horizontal) {
      const atStart = scrollEl.scrollLeft <= 0;
      const atEnd = scrollEl.scrollLeft + scrollEl.clientWidth >= scrollEl.scrollWidth - 1;
      fadeHost.classList.toggle('is-scrolled-start', !atStart);
      fadeHost.classList.toggle('is-scrolled-end', !atEnd);
    } else {
      const atTop = scrollEl.scrollTop <= 0;
      const atBottom = scrollEl.scrollTop + scrollEl.clientHeight >= scrollEl.scrollHeight - 1;
      fadeHost.classList.toggle('is-scrolled-top', !atTop);
      fadeHost.classList.toggle('is-scrolled-bottom', !atBottom);
    }
  }

  scrollEl.addEventListener('scroll', update);
  // ResizeObserver (not just window resize) matters here: on mobile,
  // .lime-messages/.lime-profile start hidden (display:none) behind
  // whichever view isn't active, so scrollHeight/clientHeight read as
  // 0 at page load. Switching mobile views doesn't fire a window
  // resize, but it does change these elements' box from 0×0 to real
  // dimensions, which ResizeObserver does catch — keeping the fade
  // state from going stale after a view switch.
  if (window.ResizeObserver) {
    new ResizeObserver(update).observe(scrollEl);
  } else {
    window.addEventListener('resize', update);
  }
  update();
}

// LIME-46: scrollEl and fadeHost are now two different elements for
// list-col/profile/recent too, not just messages/chat-body — each area's
// own frame (non-scrolling, hosts the fade divs) is a distinct element
// from its scroller (see lime.css's own comments on each for why the
// split was needed, and which element kept which identity).
wireScrollFades(document.querySelector('.lime-list-col__scroll'), document.querySelector('.lime-list-col'));
wireScrollFades(document.querySelector('.lime-messages'), document.querySelector('.lime-chat-body'));
wireScrollFades(document.querySelector('.lime-profile__scroll'), document.querySelector('.lime-profile'));
wireScrollFades(document.querySelector('.lime-recent'), document.querySelector('.lime-recent-frame'), { horizontal: true });
// New this brief — these two areas had no fades at all before.
wireScrollFades(document.querySelector('.lime-members-panel__list'), document.querySelector('.lime-members-panel__list-frame'));
wireScrollFades(document.querySelector('.lime-replies-panel__list'), document.querySelector('.lime-replies-panel__list-frame'));
wireScrollFades(document.querySelector('.lime-settings__nav-scroll'), document.getElementById('settings-nav'));
// LIME-41-fix: the photo wall's own scroller — fades use --surface-bg
// set directly on #photo-wall itself (the backdrop's own tint, lime.css),
// not a panel color, since there's no white card here to inherit one from.
wireScrollFades(document.getElementById('wall-scroller'), document.getElementById('wall-frame'));
// The settings pane's own body is rebuilt on every section render
// (renderProfileSection/renderSecuritySection, both via
// settingsBodyFrameOpen) — wired from showSection itself, below, not
// here, since the element doesn't exist yet at parse time and gets
// replaced on every section switch.
