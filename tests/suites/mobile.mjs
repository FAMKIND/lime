// The phone shell (LIME-78): the dock, the Messages screen (one list, search, filter), the stacked navigation with the browser's
// back button, the chat top bar, and "desktop is untouched". Runs a scripted scenario on a throwaway dev server, in Chrome with
// mobile emulation at 390x844 and 360x780, and in the real Firefox at 390x844 (a viewport only: Firefox has no mobile emulation).
// Skipped (with a note) when Firefox or Chrome is missing.
import crypto from 'node:crypto';
import { launch, browserAvailable, sleep, watchErrors, checkOrigin } from '../lib/harness.mjs';
import { DevServer } from '../lib/dev.mjs';

const wait = (page, fn, arg, ms = 10000) => page.waitForFunction(fn, { polling: 30, timeout: ms }, arg);

// One scenario shared by every run: Mia is the person on the phone.
async function buildScenario(server) {
  const [mia, ned, oli] = [await server.signUp('Mia Moreno'), await server.signUp('Ned Nguyen'), await server.signUp('Oli Okafor')];
  const send = async (u, ops) => (await server.api('POST', '/ops', { token: u.token, body: { device_id: u.device, ops: ops.map(([type, payload]) => ({ op_id: crypto.randomUUID(), type, actor_id: u.userId, device_id: u.device, client_ts: new Date().toISOString(), payload })) } })).body.results;
  const id = () => crypto.randomUUID();
  const say = (conversation_id, content) => ['message.send', { message_id: id(), conversation_id, content }];
  const dm = id(), planning = id(), zed = id(), old = id();
  await send(ned, [['conversation.create', { conversation_id: dm, type: 'direct', member_ids: [mia.userId] }], say(dm, 'Hello Mia'), say(dm, 'Are you free on Friday?')]);
  await sleep(60);
  await send(oli, [['conversation.create', { conversation_id: planning, type: 'group', name: 'Planning', member_ids: [mia.userId, ned.userId] }], say(planning, 'Agenda is up'), say(planning, 'Please read it'), say(planning, 'Bring snacks')]);
  await sleep(60);
  await send(mia, [['conversation.create', { conversation_id: zed, type: 'group', name: 'Zed Team', member_ids: [oli.userId] }]]);
  const longUrl = 'https://www.example.com/an/extremely/long/path/that/keeps/going/and/going/with-no-spaces-at-all-to-break-on-0123456789abcdef';
  await send(oli, [say(zed, 'Welcome to Zed'), say(zed, 'Second one from Oli'), say(zed, longUrl)]);
  const mine = [say(zed, 'Thanks!'), say(zed, 'Glad to be here')];
  await send(mia, mine);
  const thanksId = mine[0][1].message_id;
  await send(oli, [['reaction.toggle', { message_id: thanksId, emoji: '\u{1F44D}', present: true }]]);
  await sleep(60);
  await send(ned, [['conversation.create', { conversation_id: old, type: 'group', name: 'Old news', member_ids: [mia.userId] }], say(old, 'Archived chatter')]);
  await send(mia, [['membership.setStarred', { conversation_id: dm, starred: true }], ['membership.setArchived', { conversation_id: old, archived: true }]]);
  return { mia, ned, oli, dm, planning, zed, old };
}

async function openPhone(browser, server, person, label, errors, { width, height, emulate, hash = '' }) {
  const page = await browser.newPage();
  watchErrors(page, label, errors);
  await page.setViewport(emulate ? { width, height, deviceScaleFactor: 2, isMobile: true, hasTouch: true } : { width, height, deviceScaleFactor: 2 });
  await page.evaluateOnNewDocument((p) => {
    if (!sessionStorage.getItem('e2e-seeded')) {
      sessionStorage.setItem('e2e-seeded', '1');
      sessionStorage.setItem('lime-api-session', JSON.stringify({ userId: p.userId, email: p.email, access_token: p.token, refresh_token: p.refresh, expires_at: Date.now() + 14 * 60 * 1000 }));
      sessionStorage.setItem('lime-demo-session', JSON.stringify({ userId: p.userId, email: p.email }));
    }
    try { localStorage.setItem('lime-device-id', p.device); } catch (e) { /* none */ }
  }, person);
  await page.goto(server.base + 'index.html' + hash, { waitUntil: 'load' });
  await wait(page, () => window.LimeStore && LimeStore.isApi() && LimeStore.getCurrentUserId() && document.querySelectorAll('#m-list .lime-contact').length > 0);
  await sleep(500);
  return page;
}

// The ink box of icons: the mask svg drawn on a canvas, then the bounding box of what is painted (the artwork never fills its box,
// so a font-size alone says nothing about how big an icon looks). Returns [{label, ink:[w,h], tap:[w,h]}].
const measureIcons = (page, items) => page.evaluate(async (items) => {
  const out = []; const cache = {};
  const ink = (url) => cache[url] || (cache[url] = new Promise((resolve) => {
    const img = new Image();
    img.onload = () => {
      const S = 480; const c = document.createElement('canvas'); c.width = S; c.height = S; const x = c.getContext('2d');
      x.drawImage(img, 0, 0, S, S); const d = x.getImageData(0, 0, S, S).data; let x0 = S, y0 = S, x1 = -1, y1 = -1;
      for (let j = 0; j < S; j++) for (let i = 0; i < S; i++) if (d[(j * S + i) * 4 + 3] > 40) { if (i < x0) x0 = i; if (i > x1) x1 = i; if (j < y0) y0 = j; if (j > y1) y1 = j; }
      resolve(x1 < 0 ? null : { w: (x1 - x0 + 1) / S, h: (y1 - y0 + 1) / S });
    };
    img.onerror = () => resolve(null);
    img.src = url.replace(/^url\("?|"?\)$/g, '').replace(/currentColor/g, 'black');
  }));
  for (const [label, sel] of items) {
    const el = [...document.querySelectorAll(sel)].find((e) => { const r = e.getBoundingClientRect(); return r.width > 0 && r.height > 0; });
    if (!el) { out.push({ label, missing: true }); continue; }
    const cs = getComputedStyle(el); const r = el.getBoundingClientRect();
    const mask = cs.webkitMaskImage && cs.webkitMaskImage !== 'none' ? cs.webkitMaskImage : cs.maskImage;
    const btn = el.closest('button'); const br = btn ? btn.getBoundingClientRect() : null;
    const f = mask && mask !== 'none' ? await ink(mask) : null;
    out.push({ label, ink: f ? [Math.round(f.w * r.width * 10) / 10, Math.round(f.h * r.height * 10) / 10] : null, tap: br ? [Math.round(br.width), Math.round(br.height)] : null });
  }
  return out;
}, items);
const isGlass = (page, sel) => page.evaluate((q) => { const cs = getComputedStyle(document.querySelector(q)); const bg = cs.backgroundColor; const alpha = /\/\s*([\d.]+)\)/.exec(bg); return { blur: /blur/.test(cs.backdropFilter || cs.webkitBackdropFilter || ''), alpha: alpha ? parseFloat(alpha[1]) : (/^rgba/.test(bg) ? parseFloat(bg.split(',')[3]) : 1) }; }, sel);


const view = (page) => page.evaluate(() => document.getElementById('layout').dataset.mobileView);
const visible = (page, sel) => page.evaluate((s) => { const el = document.querySelector(s); if (!el) return false; const cs = getComputedStyle(el); const r = el.getBoundingClientRect(); return cs.display !== 'none' && cs.visibility !== 'hidden' && r.width > 0 && r.height > 0; }, sel);
const titles = (page) => page.evaluate(() => [...document.querySelectorAll('#m-list .lime-contact')].map((li) => li.querySelector('.lime-contact__name').textContent));

async function runOne(check, browser, name, server, S, size) {
  const tag = (s) => `${name} ${size.width}x${size.height}: ${s}`;
  const errors = [];
  const page = await openPhone(browser, server, S.mia, tag('page'), errors, size);
  await checkOrigin(page, (n, c, d) => check(tag(n), c, d), 'phone');

  const comp = (root) => page.evaluate((sel) => {
    const c = document.querySelector(sel); const r = c.getBoundingClientRect(); const vis = (q) => { const e = c.querySelector(q); if (!e) return false; const cs = getComputedStyle(e); const b = e.getBoundingClientRect(); return cs.display !== 'none' && cs.visibility !== 'hidden' && b.width > 0 && b.height > 0; };
    const x = (q) => { const e = c.querySelector(q); return e ? Math.round(e.getBoundingClientRect().left) : null; };
    return { display: getComputedStyle(c).display, h: Math.round(r.height), left: Math.round(r.left), right: Math.round(innerWidth - r.right), expanded: c.classList.contains('is-expanded'), placeholder: getComputedStyle(c.querySelector('.lime-composer__input'), '::before').content, shown: { emoji: vis('[data-emoji-btn]'), aa: vis('.lime-composer__tool--aa'), mic: vis('.lime-voice-split__mic'), send: vis('.lime-composer__return'), bold: vis('.lime-composer__toolbar > [data-cmd="bold"]'), overflow: vis('.lime-composer__overflow'), privacy: vis('.lime-composer__privacy') }, xs: { plus: x('[data-attach-btn]'), emoji: x('[data-emoji-btn]'), aa: x('.lime-composer__tool--aa'), mic: x('.lime-voice-split__mic'), send: x('.lime-composer__return') } };
  }, root);
  // ── what a phone no longer shows, and what it does ──
  const gone = await Promise.all(['.seed-layout__left', '.lime-mobile-nav-toggle', '.lime-center-top', '#scope-tablist', '.lime-recent', '.lime-section', '#notif-btn'].map((s) => visible(page, s)));
  check(tag('no drawer, hamburger, breadcrumb row, tabs, Recent row, sections or bell'), gone.every((v) => !v), JSON.stringify(gone));
  check(tag('the dock and the Messages header are showing; the chat bar is not'), (await visible(page, '#m-dock')) && (await visible(page, '#m-logo-btn')) && !(await visible(page, '#m-chatbar')));
  const dock = await page.evaluate(() => ({ labels: [...document.querySelectorAll('#m-dock .m-dock__label')].map((e) => e.textContent), rect: document.getElementById('m-dock').getBoundingClientRect().toJSON(), vh: window.innerHeight, vw: window.innerWidth, pos: getComputedStyle(document.getElementById('m-dock')).position }));
  check(tag('the dock is floating, inside the screen, with the three lowercase labels link, jam, call (account moved to the avatar at the top)'), dock.pos === 'fixed' && dock.labels.join() === 'link,jam,call' && dock.rect.left >= 8 && dock.rect.right <= dock.vw - 8 && dock.rect.bottom <= dock.vh - 8, JSON.stringify(dock.labels));
  // ── LIME-79-fix: the fixed header, glass dock, icon standard, pin size, tints ──
  const head = await page.evaluate(() => { const h = document.getElementById('m-messages-head'); const r = h.getBoundingClientRect(); return { top: r.top, h: r.height, pos: getComputedStyle(h).position, kids: [...h.children].map((e) => e.tagName + (e.className ? '.' + String(e.className).split(' ')[0] : '')), searchInside: !!h.querySelector('.m-search, #m-filter-btn'), toolsTop: document.querySelector('.m-messages__tools').getBoundingClientRect().top }; });
  check(tag('the Messages header is a fixed bar holding only the logo button and the search + avatar pill (chips and filter are not in it)'), head.top === 0 && head.pos === 'absolute' && head.kids.join() === 'BUTTON.m-glass-btn,H1.m-sr-only,DIV.m-glass-pill' && !head.searchInside && head.toolsTop >= head.h - 1, JSON.stringify(head));
  await page.evaluate(() => { document.getElementById('m-list').style.paddingBottom = '1500px'; document.querySelector('.lime-list-col__scroll').scrollTop = 220; });
  await sleep(350);
  const scrolled = await page.evaluate(() => { const h = document.getElementById('m-messages-head').getBoundingClientRect(); const t = document.querySelector('.m-messages__tools').getBoundingClientRect(); const sc = document.querySelector('.lime-list-col__scroll'); return { headTop: h.top, headBottom: h.bottom, toolsBottom: t.bottom, mask: getComputedStyle(sc).webkitMaskImage || getComputedStyle(sc).maskImage, cls: document.getElementById('list-col').className }; });
  check(tag('scrolling the list: the header stays put, search and filter scroll away under it, and the list fades under the header (a mask)'), scrolled.headTop === 0 && scrolled.toolsBottom <= scrolled.headBottom + 1 && /gradient/.test(scrolled.mask) && /is-scrolled-top/.test(scrolled.cls), JSON.stringify(scrolled));
  await page.evaluate(() => { document.getElementById('m-list').style.paddingBottom = ''; document.querySelector('.lime-list-col__scroll').scrollTop = 0; });
  const dockGlass = await isGlass(page, '#m-dock');
  check(tag('the dock is liquid glass: translucent and blurred, and nothing fades out under it'), dockGlass.blur && dockGlass.alpha < 0.8, JSON.stringify(dockGlass));
  // ── LIME-79-fix2 ──
  const shell = await page.evaluate(() => { const meta = document.querySelector('meta[name="theme-color"]'); const rgb = (c) => '#' + (c.match(/\d+/g) || []).slice(0, 3).map((v) => Number(v).toString(16).padStart(2, '0')).join(''); return { meta: meta && meta.content, body: rgb(getComputedStyle(document.body).backgroundColor), html: rgb(getComputedStyle(document.documentElement).backgroundColor), cover: /viewport-fit=cover/.test(document.querySelector('meta[name="viewport"]').content) }; });
  check(tag('status-bar canvas: viewport-fit=cover, the canvas on html and body, and theme-color equal to it (' + shell.meta + ')'), shell.cover && shell.meta === shell.body && shell.html === shell.body, JSON.stringify(shell));
  await page.evaluate(() => LimeAppearance.applyCanvas('sage')); await sleep(150);
  const shellSage = await page.evaluate(() => document.querySelector('meta[name="theme-color"]').content);
  await page.evaluate(() => LimeAppearance.applyTheme('dark')); await sleep(150);
  const shellDark = await page.evaluate(() => ({ meta: document.querySelector('meta[name="theme-color"]').content, body: getComputedStyle(document.body).backgroundColor }));
  await page.evaluate(() => { LimeAppearance.applyCanvas('warm'); LimeAppearance.applyTheme('light'); }); await sleep(150);
  const shellBack = await page.evaluate(() => document.querySelector('meta[name="theme-color"]').content);
  check(tag('theme-color follows a canvas tone change (sage ' + shellSage + '), dark mode (' + shellDark.meta + ') and returns (' + shellBack + ')'), shellSage !== shell.meta && shellDark.meta !== shellSage && shellDark.meta === '#' + (shellDark.body.match(/\d+/g) || []).map((v) => Number(v).toString(16).padStart(2, '0')).join('') && shellBack === shell.meta, JSON.stringify([shell.meta, shellDark, shellSage, shellBack]));
  await page.click('#m-search-btn'); await sleep(200);
  const searchStyle = await page.evaluate(() => { const f = document.querySelector('.m-search'); const cs = getComputedStyle(f); return { outline: cs.outlineStyle, border: cs.borderTopWidth + ' ' + cs.borderTopColor, shadow: cs.boxShadow }; });
  check(tag('the search field has a soft outline: a 1px subtle border at rest and a light ring on focus, no heavy dark outline'), searchStyle.outline === 'none' && /^1px /.test(searchStyle.border) && !/rgb\(1[0-9], /.test(searchStyle.shadow.split(' 0px')[0] || ''), JSON.stringify(searchStyle));
  await page.evaluate(() => document.activeElement.blur());
  await page.click('#m-search-close'); await sleep(200); // the chips and filter come back
  // the filter button: warm neutral hover and press (needs Chrome's DevTools protocol to force :hover and :active)
  if (size.emulate) {
    const cdp = await page.createCDPSession(); await cdp.send('DOM.enable'); await cdp.send('CSS.enable');
    const { root } = await cdp.send('DOM.getDocument'); const { nodeId } = await cdp.send('DOM.querySelector', { nodeId: root.nodeId, selector: '#m-filter-btn' });
    const bg = () => page.evaluate(() => getComputedStyle(document.getElementById('m-filter-btn')).backgroundColor);
    const tok = (name) => page.evaluate((n) => { const t = document.createElement('i'); t.style.background = 'var(' + n + ')'; document.body.appendChild(t); const c = getComputedStyle(t).backgroundColor; t.remove(); return c; }, name);
    const rest = await bg();
    await cdp.send('CSS.forcePseudoState', { nodeId, forcedPseudoClasses: ['hover'] }); const hov = await bg();
    await cdp.send('CSS.forcePseudoState', { nodeId, forcedPseudoClasses: ['active'] }); const act = await bg();
    await cdp.send('CSS.forcePseudoState', { nodeId, forcedPseudoClasses: [] });
    check(tag('the filter button hovers and presses in warm neutrals (the menu-hover tokens), not the primary green'), hov === (await tok('--calm-bg-subtle-hover')) && act === (await tok('--calm-bg-subtle-active')) && hov !== (await tok('--lime-primary-bg')) && act !== (await tok('--lime-primary-bg')), JSON.stringify([rest, hov, act]));
    await cdp.detach();
  }
  const pal = await page.evaluate(() => {
    const cv = document.createElement('canvas'); cv.width = cv.height = 1; const cx = cv.getContext('2d', { willReadFrequently: true });
    const px = (css) => { cx.clearRect(0, 0, 1, 1); cx.fillStyle = '#000'; cx.fillStyle = css; cx.fillRect(0, 0, 1, 1); return [...cx.getImageData(0, 0, 1, 1).data].slice(0, 3).map((v) => v / 255); };
    const lin = (c) => (c <= 0.04045 ? c / 12.92 : Math.pow((c + 0.055) / 1.055, 2.4));
    const lab = ([r, g, b]) => { [r, g, b] = [r, g, b].map(lin); const l = Math.cbrt(0.4122214708 * r + 0.5363325363 * g + 0.0514459929 * b), m = Math.cbrt(0.2119034982 * r + 0.6806995451 * g + 0.1073969566 * b), s2 = Math.cbrt(0.0883024619 * r + 0.2817188376 * g + 0.6299787005 * b); return [0.2104542553 * l + 0.793617785 * m - 0.0040720468 * s2, 1.9779984951 * l - 2.428592205 * m + 0.4505937099 * s2, 0.0259040371 * l + 0.7827717662 * m - 0.808675766 * s2]; };
    const out = {};
    for (const theme of ['light', 'dark']) {
      const wrap = document.createElement('div'); wrap.setAttribute('data-theme', theme); document.body.appendChild(wrap);
      out[theme] = [0, 1, 2, 3, 4, 5, 6, 7].map((n) => { const el = document.createElement('span'); el.className = 'seed-avatar lime-avatar lime-avatar--p' + n; wrap.appendChild(el); const l = lab(px(getComputedStyle(el).backgroundColor)); const c = Math.hypot(l[1], l[2]); const h = (Math.atan2(l[2], l[1]) * 180 / Math.PI + 360) % 360; return { l: Math.round(l[0] * 100) / 100, chroma: Math.round(c * 1000) / 1000, hue: Math.round(h) }; });
      wrap.remove();
    }
    return out;
  });
  check(tag('the new avatar palette has no greens (no OKLCH hue 105 to 195) and no neutrals (chroma >= 0.04; the warm greys are 0.01), in light and dark: hues ' + pal.light.map((t) => t.hue).join(',')), [...pal.light, ...pal.dark].every((t) => (t.hue < 105 || t.hue > 195) && t.chroma >= 0.04), JSON.stringify(pal));
  const dockMe = await page.evaluate(() => { const e = document.getElementById('m-account-avatar'); return { cls: [...e.classList].find((c) => /^lime-avatar--p\d$/.test(c)), bg: getComputedStyle(e).backgroundColor }; });
  check(tag('the account (dock) avatar uses the same palette: ' + dockMe.cls), !!dockMe.cls && dockMe.bg !== 'rgba(0, 0, 0, 0)');
  const rowsStyle = await page.evaluate(() => { const r = document.querySelector('#m-list .lime-contact'); const cs = getComputedStyle(r); const rr = r.getBoundingClientRect(); return { radius: parseFloat(cs.borderTopLeftRadius), left: rr.left, right: innerWidth - rr.right }; });
  check(tag('list rows are rounded (20px) and inset from the screen edges: ' + JSON.stringify(rowsStyle)), rowsStyle.radius >= 16 && rowsStyle.left >= 4 && rowsStyle.right >= 4);
  const rings = await page.evaluate(() => [...document.querySelectorAll('#m-list .lime-avatar-cluster__member')].map((e) => { const cs = getComputedStyle(e); return cs.boxShadow.replace(/^.*?\) /, '') + '|' + cs.borderTopWidth; }));
  check(tag('group stacks: every stacked avatar has the same ring (one size, one token, no border): ' + [...new Set(rings)].length + ' distinct style(s) over ' + rings.length), rings.length >= 2 && new Set(rings).size === 1, JSON.stringify([...new Set(rings)]));
  const badges = await page.evaluate(() => { const get = (e) => { const cs = getComputedStyle(e); const r = e.getBoundingClientRect(); return { h: Math.round(r.height * 10) / 10, minW: r.width, radius: cs.borderTopLeftRadius, bg: cs.backgroundColor, color: cs.color, fs: cs.fontSize, fw: cs.fontWeight, border: cs.borderTopWidth }; }; return { row: get([...document.querySelectorAll('#m-list .lime-contact__badge')].find((b) => b.textContent)), dock: get(document.getElementById('m-dock-badge')) }; });
  check(tag('badges are one style: lime-300 fill, ink numbers, 20px high, 10px radius, 12px/700, no outline (row ' + badges.row.h + 'px, dock ' + badges.dock.h + 'px)'), ['h', 'radius', 'bg', 'color', 'fs', 'fw', 'border'].every((k) => badges.row[k] === badges.dock[k]) && badges.row.bg === 'rgb(163, 225, 138)' && badges.row.h === 20 && badges.row.border === '0px', JSON.stringify(badges));
  // the dock's press: a glass pill under the finger that follows the finger sideways and snaps on release
  {
    const info = () => page.evaluate(() => { const l = document.getElementById('m-dock-lens').getBoundingClientRect(); const cs = getComputedStyle(document.getElementById('m-dock-lens')); return { mid: (l.left + l.right) / 2, w: l.width, opacity: parseFloat(cs.opacity), blur: /blur/.test(cs.backdropFilter || cs.webkitBackdropFilter || ''), pressing: document.getElementById('m-dock').classList.contains('is-pressing'), items: [...document.querySelectorAll('#m-dock .m-dock__item')].map((e) => { const r = e.getBoundingClientRect(); return (r.left + r.right) / 2; }) }; });
    const it0 = (await info()).items;
    await page.evaluate(() => { document.getElementById('toast-container').innerHTML = ''; });
    const dy = await page.evaluate(() => { const r = document.getElementById('m-dock').getBoundingClientRect(); return r.top + r.height / 2; });
    await page.mouse.move(it0[0], dy); await page.mouse.down(); await sleep(250);
    const d0 = await info();
    await page.mouse.move(it0[1] + 20, dy, { steps: 4 }); await sleep(120);
    const d1 = await info();
    await page.mouse.move(it0[2], dy, { steps: 4 }); await sleep(250);
    const d2 = await info();
    check(tag('dock press: holding shows a glass pill under the finger (visible, blurred, translucent)'), d0.pressing && d0.opacity > 0.9 && d0.blur && Math.abs(d0.mid - it0[0]) < 12, JSON.stringify(d0));
    check(tag('dock press: the pill follows the finger sideways while held'), d1.mid > d0.mid + 30 && Math.abs(d1.mid - (it0[1] + 20)) < 14 && Math.abs(d2.mid - it0[2]) < 14, JSON.stringify([d0.mid, d1.mid, d2.mid]));
    await page.mouse.move(it0[2] + 10, dy); await page.mouse.up(); await sleep(450);
    const d3 = await info();
    check(tag('dock press: on release it snaps to the item under the finger, the item is chosen (calls toast) and the pill fades'), /Calls are coming soon/.test(await page.evaluate(() => document.getElementById('toast-container').textContent)) && Math.abs(d3.mid - it0[2]) < 6 && !d3.pressing && d3.opacity < 0.1, JSON.stringify(d3));
    await page.evaluate(() => { document.getElementById('toast-container').innerHTML = ''; });
  }
  const icons1 = await measureIcons(page, [['fab plus', '.m-fab .dew'], ['filter', '#m-filter-btn .dew'], ['dock link', '#m-dock-link .dew'], ['dock jam', '#m-dock-jam .m-icon'], ['dock calls', '#m-dock-calls .m-icon'], ['header search', '#m-search-btn .dew'], ['pin', '.lime-contact--pinned .lime-icon-pin']]);
  const big = (f) => (f.ink ? Math.max(...f.ink) : 0);
  const byName = Object.fromEntries(icons1.map((i) => [i.label, i]));
  check(tag('header and dock icons: a ~24px visible glyph (+/-1.5) in a >= 44px target: ' + icons1.slice(0, 6).map((i) => i.label + ' ' + big(i)).join(', ')), ['header search', 'filter', 'dock link', 'dock jam', 'dock calls'].every((n) => Math.abs(big(byName[n]) - 24) <= 1.5 && Math.min(...byName[n].tap) >= 44) && Math.abs(big(byName['fab plus']) - 30) <= 1.5, JSON.stringify(icons1));
  check(tag('the pin beside a name is 16 to 18px tall'), byName.pin.ink[1] >= 16 && byName.pin.ink[1] <= 18, JSON.stringify(byName.pin.ink));
  const tintPairs = await page.evaluate(() => {
    const cv = document.createElement('canvas'); cv.width = cv.height = 1; const cx = cv.getContext('2d', { willReadFrequently: true });
    const px = (css) => { cx.clearRect(0, 0, 1, 1); cx.fillStyle = '#000'; cx.fillStyle = css; cx.fillRect(0, 0, 1, 1); return [...cx.getImageData(0, 0, 1, 1).data].slice(0, 3).map((v) => v / 255); };
    const lin = (c) => (c <= 0.04045 ? c / 12.92 : Math.pow((c + 0.055) / 1.055, 2.4));
    const lab = ([r, g, b]) => { [r, g, b] = [r, g, b].map(lin); const l = Math.cbrt(0.4122214708 * r + 0.5363325363 * g + 0.0514459929 * b), m = Math.cbrt(0.2119034982 * r + 0.6806995451 * g + 0.1073969566 * b), s2 = Math.cbrt(0.0883024619 * r + 0.2817188376 * g + 0.6299787005 * b); return [0.2104542553 * l + 0.793617785 * m - 0.0040720468 * s2, 1.9779984951 * l - 2.428592205 * m + 0.4505937099 * s2, 0.0259040371 * l + 0.7827717662 * m - 0.808675766 * s2]; };
    const out = {};
    for (const theme of ['light', 'dark']) {
      const wrap = document.createElement('div'); wrap.setAttribute('data-theme', theme); document.body.appendChild(wrap);
      const labs = [0, 1, 2, 3, 4, 5, 6, 7].map((n) => { const el = document.createElement('span'); el.className = 'seed-avatar lime-avatar lime-avatar--p' + n; wrap.appendChild(el); return lab(px(getComputedStyle(el).backgroundColor)); });
      wrap.remove();
      let min = 1e9; for (let i = 0; i < 8; i++) for (let j = i + 1; j < 8; j++) min = Math.min(min, 100 * Math.hypot(labs[i][0] - labs[j][0], labs[i][1] - labs[j][1], labs[i][2] - labs[j][2]));
      out[theme] = Math.round(min * 100) / 100;
    }
    return out;
  });
  check(tag('the eight avatar tints are distinct: the smallest OKLab distance between any two is ' + tintPairs.light + ' in light and ' + tintPairs.dark + ' in dark (>= 7)'), tintPairs.light >= 7 && tintPairs.dark >= 7, JSON.stringify(tintPairs));

  // ── the one list: pinned first, then by recency; unread counts; lowercase time ──
  check(tag('one list: the pinned chat first, then the others by recency (archived left out)'), (await titles(page)).join() === 'Ned Nguyen,Zed Team,Planning', (await titles(page)).join());
  const rows = await page.evaluate(() => [...document.querySelectorAll('#m-list .lime-contact')].map((li) => ({ name: li.querySelector('.lime-contact__name').textContent, badge: li.querySelector('.lime-contact__badge').textContent, pinned: li.classList.contains('lime-contact--pinned'), pinShown: getComputedStyle(li.querySelector('.lime-contact__pin')).display !== 'none', time: li.querySelector('.lime-contact__time--m').textContent, timeShown: getComputedStyle(li.querySelector('.lime-contact__time--m')).display !== 'none', deskTime: getComputedStyle(li.querySelector('.lime-contact__time:not(.lime-contact__time--m)')).display })));
  check(tag('each row shows its unread count (2, 3, 3), and only the pinned one shows the pin icon'), rows.map((r) => r.badge).join() === '2,3,3' && rows.map((r) => r.pinShown).join() === 'true,false,false', JSON.stringify(rows.map((r) => [r.name, r.badge, r.pinShown])));
  check(tag('times are lowercase ("h:mm am/pm") and only the phone time shows'), rows.every((r) => /^\d{1,2}:\d{2} (am|pm)$/.test(r.time) && r.timeShown && r.deskTime === 'none'), rows[0].time);
  check(tag('the dock badge shows the total unread (8), not counting the archived chat'), (await page.evaluate(() => document.getElementById('m-dock-badge').textContent)) === '8');

  // ── search and filter ──
  await page.click('#m-search-btn'); await sleep(200);
  await page.click('#m-search-input');
  await page.keyboard.type('planning');
  await sleep(250);
  check(tag('search narrows the list as you type'), (await titles(page)).join() === 'Planning');
  await page.keyboard.type('zzz');
  await sleep(250);
  check(tag('a search with no matches says so'), /No chats match/.test(await page.evaluate(() => document.getElementById('m-list').textContent)));
  await page.click('#m-search-close'); await sleep(250);
  check(tag('closing the search clears it and brings the chips back'), (await titles(page)).length === 3 && (await visible(page, '#m-chips')));
  const filter = async (f) => { if (f === 'all' || f === 'unread') { await page.click(`#m-chips [data-chip="${f}"]`); await sleep(250); return (await titles(page)).join(); } await page.click('#m-filter-btn'); await sleep(150); await page.click(`#m-filter-menu [data-filter="${f}"]`); await sleep(250); return (await titles(page)).join(); };
  check(tag('the chips (All, Unread) and the filter menu (Pinned, Groups, Archived) show the right chats'), [await filter('unread'), await filter('pinned'), await filter('groups'), await filter('archived')].join(' | ') === 'Ned Nguyen,Zed Team,Planning | Ned Nguyen | Zed Team,Planning | Old news');
  check(tag('the filter button shows when a filter is on, and All brings everything back'), (await page.evaluate(() => document.getElementById('m-filter-btn').classList.contains('is-filtering'))) && (await filter('all')) === 'Ned Nguyen,Zed Team,Planning');
  await page.click('#m-filter-btn'); await sleep(350);
  const fm = await page.evaluate(() => { const m = document.getElementById('m-filter-menu'); const cs = getComputedStyle(m); const r = m.getBoundingClientRect(); const it = m.querySelector('.lime-menu__item'); return { blur: /blur/.test(cs.backdropFilter || cs.webkitBackdropFilter || ''), radius: parseFloat(cs.borderTopLeftRadius), w: r.width, h: r.height, rowH: it.getBoundingClientRect().height, fs: parseFloat(getComputedStyle(it).fontSize), icons: [...m.querySelectorAll('.lime-menu__item')].every((e) => e.querySelector('.dew, .lime-icon-pin') && e.querySelector('.dew, .lime-icon-pin').getBoundingClientRect().left < e.querySelector('.lime-menu__item-label').getBoundingClientRect().left), inside: r.left >= 0 && r.right <= innerWidth && r.bottom <= innerHeight };  });
  check(tag('the filter menu is the glass menu: blurred, large radius, 44px rows of 17px text, an icon at the left of every item, inside the screen'), fm.blur && fm.radius >= 20 && fm.w > 150 && fm.rowH >= 44 && fm.fs === 17 && fm.icons && fm.inside, JSON.stringify(fm));
  await page.keyboard.press('Escape'); await page.evaluate(() => document.body.click()); await sleep(150);

  // ── no sideways scroll, nothing wider than the screen ──
  const over = await page.evaluate(() => ({ doc: document.documentElement.scrollWidth, w: window.innerWidth, wide: [...document.querySelectorAll('#m-messages *')].filter((e) => e.getBoundingClientRect().right > window.innerWidth + 0.5).length }));
  check(tag('the Messages screen does not scroll sideways and nothing is wider than the screen'), over.doc <= over.w && over.wide === 0, JSON.stringify(over));

  // ── stacked navigation ──
  const startHistory = await page.evaluate(() => history.length);
  await page.click(`#m-list [data-conversation-id="${S.planning}"]`);
  await wait(page, () => document.getElementById('layout').dataset.mobileView === 'thread');
  check(tag('tapping a chat pushes the chat screen: the chat bar shows, the dock is gone'), (await visible(page, '#m-chatbar')) && !(await visible(page, '#m-dock')) && (await page.evaluate(() => document.getElementById('m-chat-title-text').textContent)) === 'Planning');
  check(tag('design 02: the back button is only the arrow (no unread count)'), (await page.evaluate(() => { const c = document.getElementById('m-chat-back-count'); return c.hidden || getComputedStyle(c).display === 'none'; })));
  check(tag('the address has #c= for the open chat, and the history grew by one'), (await page.evaluate(() => location.hash)) === '#c=' + S.planning && (await page.evaluate(() => history.length)) === startHistory + 1);
  const barOver = await page.evaluate(() => ({ doc: document.documentElement.scrollWidth, w: window.innerWidth, bar: [...document.querySelectorAll('#m-chatbar > *')].filter((e) => e.getBoundingClientRect().right > window.innerWidth + 0.5 || e.getBoundingClientRect().left < -0.5).length }));
  check(tag('the chat top bar fits the screen'), barOver.doc <= barOver.w && barOver.bar === 0, JSON.stringify(barOver));

  const centre = await page.evaluate(() => {
    const R = (e) => e.getBoundingClientRect(); const glass = (e) => { const cs = getComputedStyle(e); return /blur/.test(cs.backdropFilter || cs.webkitBackdropFilter || '') && parseFloat(cs.borderTopLeftRadius) >= 20 && cs.borderTopWidth !== '0px'; };
    const back = document.getElementById('m-chat-back'); const mid = document.getElementById('m-chat-center'); const tools = document.querySelector('.m-chatbar__tools'); const bar = document.getElementById('m-chatbar'); const th = R(document.getElementById('thread-messages'));
    const b0 = getComputedStyle(bar, '::before');
    return { back: R(back).width, backGlass: glass(back), midGlass: glass(mid), toolsGlass: glass(tools), order: R(back).right <= R(mid).left && R(mid).right <= R(tools).left, midH: R(mid).height, toolsH: R(tools).height, sub: document.getElementById('m-chat-sub').textContent, title: document.getElementById('m-chat-title-text').textContent, fade: /gradient/.test(b0.backgroundImage), barBorder: getComputedStyle(bar).borderBottomWidth, pos: getComputedStyle(bar).position, threadTop: th.top, barTop: R(bar).top, barBottom: R(bar).bottom, doc: document.documentElement.scrollWidth, vw: innerWidth, right: Math.round(innerWidth - R(tools).right) };
  });
  check(tag('design 02: the chat header is floating glass: a round "<" (' + centre.back + 'px), a pill with the avatars, the name and "' + centre.sub + '", and one pill at the right; the messages scroll under them with a soft fade'), centre.back === 52 && centre.backGlass && centre.midGlass && centre.toolsGlass && centre.order && centre.midH === 52 && centre.toolsH === 52 && /^\d+ members$/.test(centre.sub) && centre.fade && centre.barBorder === '0px' && centre.pos === 'absolute' && centre.threadTop <= centre.barTop + 1 && centre.barBottom > centre.threadTop && centre.doc <= centre.vw && centre.right >= 8, JSON.stringify(centre));
  const chatIcons = await measureIcons(page, [['back', '#m-chat-back .dew'], ['search', '#m-chat-search .m-icon'], ['call', '#m-chat-call .m-icon'], ['more', '#m-chat-more .m-icon']]);
  check(tag('chat header icons are one size: ~24px visible glyphs in targets at least 40 wide and 44 high (' + chatIcons.map((i) => i.label + ' ' + Math.max(...i.ink)).join(', ') + ')'), chatIcons.every((i) => Math.abs(Math.max(...i.ink) - 24) <= 1.5 && i.tap[1] >= 44 && i.tap[0] >= 40), JSON.stringify(chatIcons));
  await page.click('#m-chat-center');
  await wait(page, () => document.getElementById('layout').dataset.mobileView === 'panel');
  check(tag('the header\'s avatars and title open the details as a pushed screen'), (await view(page)) === 'panel' && (await visible(page, '#right-panel')));
  const members = await page.evaluate(() => ({ panel: document.getElementById('right-panel').dataset.panel, rows: [...document.querySelectorAll('.lime-members-panel__row')].map((r) => r.querySelector('.lime-members-panel__row-name').textContent + '|' + (r.querySelector('.lime-presence') ? r.querySelector('.lime-presence').dataset.presence : 'none')) }));
  check(tag('Members shows everyone in the group (3), each with a live status icon: ' + members.rows.join(', ')), members.panel === 'members' && members.rows.length === 3 && members.rows.every((r) => /\|(active|away|busy|dnd)$/.test(r)), JSON.stringify(members));
  await page.click('.lime-members-panel__row:nth-child(2)');
  await wait(page, () => document.getElementById('right-panel').dataset.panel === 'profile');
  check(tag('a member\'s details open with the back arrow to Members'), (await visible(page, '#profile-back-btn')));
  await page.click('#profile-back-btn');
  await wait(page, () => document.getElementById('right-panel').dataset.panel === 'members');
  check(tag('"back" from a member returns to Members'), true);
  await page.goBack();
  await wait(page, () => document.getElementById('layout').dataset.mobileView === 'thread');
  check(tag('the browser back button returns from details to the chat'), (await view(page)) === 'thread' && (await visible(page, '#m-chatbar')));
  await page.goBack();
  await wait(page, () => document.getElementById('layout').dataset.mobileView === 'contacts');
  check(tag('and again from the chat to the Messages list (Android back / iOS swipe do the same), with a clean address'), (await view(page)) === 'contacts' && (await page.evaluate(() => location.hash)) === '' && (await visible(page, '#m-dock')));
  await page.goForward();
  await wait(page, () => document.getElementById('layout').dataset.mobileView === 'thread');
  check(tag('forward reopens the same chat'), (await page.evaluate(() => document.getElementById('m-chat-title-text').textContent)) === 'Planning');
  await page.click('#m-chat-back');
  await wait(page, () => document.getElementById('layout').dataset.mobileView === 'contacts');
  check(tag('the on-screen back arrow goes back too'), (await view(page)) === 'contacts');

  // a thread (reply) panel is also a pushed screen
  await page.evaluate((id) => LimeStore.sendMessage(id, { content: 'parent for a thread' }), S.planning);
  await sleep(300);
  await page.evaluate((id) => document.querySelector('#m-list [data-conversation-id="' + id + '"]').click(), S.planning);
  await wait(page, () => document.getElementById('layout').dataset.mobileView === 'thread');
  const parentId = await page.evaluate((id) => LimeStore.listMessages(id, { threadOnly: true }).slice(-1)[0].id, S.planning);
  await page.evaluate((pid, id) => LimeStore.sendMessage(id, { content: 'a reply', replyTo: pid }), parentId, S.planning);
  await sleep(300);
  // ── LIME-79-fix3: under each bubble, the chips and add-reaction at the bubble's left edge, the time and ticks at its right edge, the
  //    reply summary at its left edge (your own bubble here: the parent was sent by Mia) ──
  const align = (pid) => page.evaluate((id) => {
    const m = document.querySelector('#thread-messages [data-message-id="' + id + '"]');
    const L = (e) => e.getBoundingClientRect(); const bub = L(m.querySelector('.lime-message__content'));
    const add = L(m.querySelector('.lime-react-add')); const stamp = L(m.querySelector('.lime-message__stamp')); const sum = m.querySelector('.lime-message__replies');
    return { bubL: bub.left, bubR: bub.right, addL: add.left, stampR: stamp.right, sumL: sum ? L(sum).left : null, sumR: sum ? L(sum).right : null };
  }, pid);
  const al = await align(parentId);
  const near = (a, b) => Math.abs(a - b) <= 6;
  check(tag('under your bubble: add-reaction starts at the bubble\'s left edge (' + Math.round(al.addL - al.bubL) + 'px in), the time and ticks end at its right edge (' + Math.round(al.bubR - al.stampR) + 'px in), the reply summary starts at its left edge (' + Math.round(al.sumL - al.bubL) + 'px in)'), near(al.addL, al.bubL) && near(al.stampR, al.bubR) && al.sumL !== null && near(al.sumL, al.bubL) && al.sumR <= al.bubR + 1, JSON.stringify(al));
  const alR = await page.evaluate(() => { const ms = [...document.querySelectorAll('#thread-messages .lime-message--received')]; const m = ms[ms.length - 1]; const L = (e) => e.getBoundingClientRect(); return { bubL: L(m.querySelector('.lime-message__content')).left, bubR: L(m.querySelector('.lime-message__content')).right, addL: L(m.querySelector('.lime-react-add')).left, stampR: L(m.querySelector('.lime-message__stamp')).right }; });
  check(tag('and the same for others\' bubbles'), near(alR.addL, alR.bubL) && near(alR.stampR, alR.bubR), JSON.stringify(alR));
  const rcpt = await page.evaluate((id) => { const m = document.querySelector('#thread-messages [data-message-id="' + id + '"]'); const t = [...document.querySelectorAll('#thread-messages .lime-message__stamp-time')].map((e) => e.textContent); return { times: t, words: t.some((x) => /sent|delivered/i.test(x)), ticks: m.querySelectorAll('.lime-ticks path').length, label: m.querySelector('.lime-receipt').getAttribute('aria-label') }; }, parentId);
  check(tag('receipts are only the time plus ticks (no "Sent ... delivered" words; two ticks once delivered)'), !rcpt.words && rcpt.ticks === 2 && /^Delivered$/.test(rcpt.label), JSON.stringify(rcpt));
  await page.evaluate((id) => document.querySelector('#thread-messages [data-message-id="' + id + '"] [data-receipt]').click(), parentId);
  await wait(page, () => !!document.querySelector('.m-receipt-pop.is-open'));
  await sleep(250);
  const pop = await page.evaluate(() => { const p = document.querySelector('.m-receipt-pop'); const cs = getComputedStyle(p); const r = p.getBoundingClientRect(); return { text: p.textContent.replace(/\s+/g, ' ').trim(), blur: /blur/.test(cs.backdropFilter || cs.webkitBackdropFilter || ''), inside: r.left >= 0 && r.right <= innerWidth && r.top >= 0 && r.bottom <= innerHeight }; });
  check(tag('tapping the time and ticks opens a glass popover with Sent and Delivered: "' + pop.text + '"'), /Sent\s*\d{1,2}:\d{2} (am|pm)/.test(pop.text) && /Delivered\s*\d{1,2}:\d{2} (am|pm)/.test(pop.text) && pop.blur && pop.inside, JSON.stringify(pop));
  await page.keyboard.press('Escape');
  check(tag('Escape closes the receipt popover'), !(await page.evaluate(() => !!document.querySelector('.m-receipt-pop'))));
  await page.evaluate((pid) => document.querySelector('#thread-messages [data-message-id="' + pid + '"] .lime-message__replies').click(), parentId);
  await wait(page, () => document.getElementById('layout').dataset.mobileView === 'panel');
  check(tag('a thread opens as its own pushed screen with the back arrow'), (await visible(page, '#right-panel-toggle .m-back-icon')) && !(await visible(page, '#right-panel-toggle .dew-sidebar-right-closed')));
  const th = await page.evaluate(() => {
    const L = (e) => e.getBoundingClientRect(); const q = document.querySelector('#replies-quote .lime-message'); const r = document.querySelector('#replies-list .lime-message');
    const edges = (m) => ({ bubL: L(m.querySelector('.lime-message__content')).left, bubR: L(m.querySelector('.lime-message__content')).right, addL: L(m.querySelector('.lime-react-add')).left, stampR: L(m.querySelector('.lime-message__stamp')).right });
    const bg = (m) => getComputedStyle(m.querySelector('.lime-message__content')).backgroundColor;
    return { quote: edges(q), reply: edges(r), quoteSent: q.classList.contains('lime-message--sent'), quoteBg: bg(q), replyBg: bg(r), flat: !!document.querySelector('#replies-list .lime-reply'), foot: getComputedStyle(r.querySelector('.lime-message__foot')).display };
  });
  const nr = (a, b) => Math.abs(a - b) <= 6;
  check(tag('the thread screen uses the same bubbles: your parent message and your reply are green bubbles, no flat rows'), th.quoteSent && th.quoteBg === 'rgb(163, 225, 138)' && th.replyBg === 'rgb(163, 225, 138)' && !th.flat && th.foot === 'flex', JSON.stringify(th));
  check(tag('and the same alignment rules under its bubbles'), nr(th.quote.addL, th.quote.bubL) && nr(th.quote.stampR, th.quote.bubR) && nr(th.reply.addL, th.reply.bubL) && nr(th.reply.stampR, th.reply.bubR), JSON.stringify(th));
  // ── LIME-79-fix4: the thread's composer is the chat's composer ──
  const tc0 = await comp('#replies-composer');
  check(tag('the thread composer is the same collapsed pill as the chat\'s (grid, one line, inside the screen, "Reply..." placeholder)'), tc0.display === 'grid' && !tc0.expanded && tc0.h <= 60 && tc0.left >= 8 && tc0.right >= 8 && /Reply/.test(tc0.placeholder) && !tc0.shown.privacy, JSON.stringify(tc0));
  await page.click('#replies-composer-input');
  await wait(page, () => document.getElementById('replies-composer').classList.contains('is-expanded'));
  await sleep(200);
  const tc1 = await comp('#replies-composer');
  check(tag('expanded: "+", emoji, "Aa" at the left, mic and send at the right (in that order), no B I U, no "...", no "Secure & encrypted" row'), tc1.shown.emoji && tc1.shown.aa && tc1.shown.mic && tc1.shown.send && !tc1.shown.bold && !tc1.shown.overflow && !tc1.shown.privacy && tc1.xs.plus < tc1.xs.emoji && tc1.xs.emoji < tc1.xs.aa && tc1.xs.aa < tc1.xs.mic && tc1.xs.mic < tc1.xs.send, JSON.stringify(tc1));
  const brighter = await page.evaluate(() => {
    const lum = (css) => { const cv = document.createElement('canvas'); cv.width = cv.height = 1; const x = cv.getContext('2d'); x.fillStyle = css; x.fillRect(0, 0, 1, 1); const d = x.getImageData(0, 0, 1, 1).data; const f = (v) => { v /= 255; return v <= 0.03928 ? v / 12.92 : Math.pow((v + 0.055) / 1.055, 2.4); }; return 0.2126 * f(d[0]) + 0.7152 * f(d[1]) + 0.0722 * f(d[2]); };
    const out = {};
    for (const [label, tone, theme] of [['warm', 'warm', 'light'], ['blue tint', 'blue-tint', 'light'], ['pure white', 'pure-white', 'light'], ['lemon', 'lemon', 'light'], ['sage', 'sage', 'light'], ['lilac', 'lilac', 'light'], ['dark', 'warm', 'dark']]) {
      LimeAppearance.applyCanvas(tone); LimeAppearance.applyTheme(theme);
      const c = getComputedStyle(document.getElementById('replies-composer')); out[label] = { bg: lum(c.backgroundColor), canvas: lum(getComputedStyle(document.body).backgroundColor), border: c.borderTopWidth + ' ' + c.borderTopStyle };
    }
    LimeAppearance.applyCanvas('warm'); LimeAppearance.applyTheme('light');
    return out;
  });
  check(tag('the composer is brighter than the canvas in every tone (and in dark), with a soft outline: ' + Object.entries(brighter).map(([k, v]) => k + ' ' + v.bg.toFixed(2) + ' vs ' + v.canvas.toFixed(2)).join(', ')), Object.values(brighter).every((v) => v.bg >= v.canvas && /^1px solid/.test(v.border)) && brighter.warm.bg > brighter.warm.canvas && brighter.dark.bg > brighter.dark.canvas, JSON.stringify(brighter));
  await page.keyboard.type('thread text here');
  await page.click('#replies-composer-aa-btn');
  await wait(page, () => document.getElementById('replies-composer-format-menu').classList.contains('is-open'));
  await sleep(350);
  const fm2 = await page.evaluate(() => { const m = document.getElementById('replies-composer-format-menu'); const cs = getComputedStyle(m); const r = m.getBoundingClientRect(); const it = m.querySelector('.lime-menu__item'); return { items: [...m.querySelectorAll('.lime-menu__item')].map((e) => e.lastChild.textContent.trim()).join(), blur: /blur/.test(cs.backdropFilter || cs.webkitBackdropFilter || ''), radius: parseFloat(cs.borderTopLeftRadius), rowH: it.getBoundingClientRect().height, fs: parseFloat(getComputedStyle(it).fontSize), inside: r.left >= 0 && r.right <= innerWidth && r.top >= 0 && r.bottom <= innerHeight, focusKept: document.activeElement === document.getElementById('replies-composer-input') }; });
  check(tag('"Aa" opens a glass formatting menu: ' + fm2.items), fm2.items === 'Bold,Italic,Underline,Strikethrough,Bulleted list,Numbered list,Indent,Outdent,Align left,Align centre,Align right,Justify' && fm2.blur && fm2.radius >= 20 && fm2.rowH >= 44 && fm2.fs === 17 && fm2.inside && fm2.focusKept, JSON.stringify(fm2));
  await page.evaluate(() => { const i = document.getElementById('replies-composer-input'); i.focus(); const r = document.createRange(); r.selectNodeContents(i); const sel = getSelection(); sel.removeAllRanges(); sel.addRange(r); });
  await page.click('#replies-composer-format-menu [data-cmd="bold"]');
  await sleep(200);
  const bolded = await page.evaluate(() => document.getElementById('replies-composer-input').innerHTML);
  check(tag('choosing Bold in the menu formats the selected text'), /<b>|<strong>/.test(bolded), bolded);
  const circle = await page.evaluate(() => { const b = document.getElementById('replies-composer-send'); const r = b.getBoundingClientRect(); const cs = getComputedStyle(b); const bf = getComputedStyle(b, '::before'); return { w: r.width, h: r.height, radius: cs.borderTopLeftRadius, mask: bf.webkitMaskImage || bf.maskImage, box: parseFloat(bf.width) }; });
  const inkSend = await page.evaluate(async (c) => new Promise((resolve) => { const img = new Image(); img.onload = () => { const S = 480; const cv = document.createElement('canvas'); cv.width = S; cv.height = S; const x = cv.getContext('2d'); x.drawImage(img, 0, 0, S, S); const d = x.getImageData(0, 0, S, S).data; let x0 = S, y0 = S, x1 = -1, y1 = -1; for (let j = 0; j < S; j++) for (let i = 0; i < S; i++) if (d[(j * S + i) * 4 + 3] > 40) { if (i < x0) x0 = i; if (i > x1) x1 = i; if (j < y0) y0 = j; if (j > y1) y1 = j; } resolve(Math.max(x1 - x0 + 1, y1 - y0 + 1) / S * c.box); }; img.src = c.mask.replace(/^url\("?|"?\)$/g, '').replace(/currentColor/g, 'black'); }), circle);
  check(tag('the send button is a perfect circle (' + circle.w + 'x' + circle.h + ', radius ' + circle.radius + ') and its arrow is about 20px (' + Math.round(inkSend * 10) / 10 + ')'), Math.abs(circle.w - circle.h) < 0.5 && circle.w >= 40 && circle.radius === '50%' && Math.abs(inkSend - 20) <= 1.5, JSON.stringify([circle, inkSend]));
  const nBefore = await page.evaluate(() => document.querySelectorAll('#replies-list .lime-message').length);
  await page.keyboard.press('Escape'); await page.evaluate(() => document.body.click());
  await page.click('#replies-composer-send');
  await wait(page, (n) => document.querySelectorAll('#replies-list .lime-message').length === n + 1, nBefore);
  check(tag('sending from the thread composer adds the reply as a bubble'), true);
  await page.evaluate(() => document.getElementById('replies-composer-input').blur()); await sleep(250);
  await page.evaluate(() => window.LimeHoldMenu.open(document.querySelector('#replies-list .lime-message'))); await sleep(250);
  const inThreadMenu = await page.evaluate(() => [...document.querySelectorAll('.m-msg-menu .m-glass-menu__item')].map((e) => e.textContent.trim()).join());
  check(tag('the hold menu in a thread has no "Reply in thread" (you are in it): ' + inThreadMenu), inThreadMenu === 'Copy text', inThreadMenu);
  await page.keyboard.press('Escape');
  await page.click('#right-panel-toggle');
  await wait(page, () => document.getElementById('layout').dataset.mobileView === 'thread');
  check(tag('its back arrow returns to the chat'), (await view(page)) === 'thread');
  await page.goBack();
  await wait(page, () => document.getElementById('layout').dataset.mobileView === 'contacts');

  // ── the dock ──
  await page.click('#m-dock-calls');
  await wait(page, () => /Calls are coming soon/.test(document.getElementById('toast-container').textContent));
  await page.click('#m-dock-jam');
  await wait(page, () => /Jam is coming soon/.test(document.getElementById('toast-container').textContent));
  check(tag('calls and jam show a gentle "coming soon" toast'), true);
  await page.evaluate(() => { document.getElementById('toast-container').innerHTML = ''; }); // toasts now float at the bottom, over Account's last rows
  await page.evaluate(() => { document.getElementById('toast-container').innerHTML = ''; }); // toasts float at the bottom now, over Account's last rows
  await page.click('#m-account-btn');
  await wait(page, () => document.getElementById('settings-modal').classList.contains('is-open') && document.getElementById('settings-modal').classList.contains('is-showing-section'));
  check(tag('account opens Settings on the Profile section, full screen'), (await page.evaluate(() => { const r = document.getElementById('settings-modal').getBoundingClientRect(); return !!document.getElementById('settings-profile-form') && r.width >= window.innerWidth - 1 && r.height >= window.innerHeight - 1; })));
  const sbar = await page.evaluate(() => {
    const back = document.querySelector('.lime-settings__back').getBoundingClientRect(); const t = document.getElementById('settings-pane-title').getBoundingClientRect();
    const close = document.getElementById('settings-modal-close'); const foot = document.querySelector('.lime-settings__footer');
    return { backW: back.width, backH: back.height, backLeft: back.left, titleText: document.getElementById('settings-pane-title').textContent, titleMid: (t.left + t.right) / 2, vw: innerWidth, closeShown: getComputedStyle(close).display !== 'none', footBottom: foot ? foot.getBoundingClientRect().bottom : null, vh: innerHeight };
  });
  check(tag('Account: the native header (a back arrow, the title "Account" centred, no x), no section list, and rows for Login & security and Preferences'), sbar.backW >= 44 && sbar.backH >= 44 && sbar.backLeft < 16 && sbar.titleText === 'Account' && Math.abs(sbar.titleMid - sbar.vw / 2) < 4 && !sbar.closeShown && !(await visible(page, '#settings-nav')) && (await page.evaluate(() => [...document.querySelectorAll('.m-account-link')].map((e) => e.textContent.trim()).join())) === 'Login & security,Preferences', JSON.stringify(sbar));
  check(tag('its Save / Cancel footer is inside the screen'), sbar.footBottom !== null && sbar.footBottom <= sbar.vh + 0.5, JSON.stringify([sbar.footBottom, sbar.vh]));
  // A fresh account's empty timezone makes the Profile form count as "edited" (the select shows a default), so Account may ask
  // "Discard changes?" first. That is existing behaviour; take the Discard.
  const discard = async () => { await sleep(350); if (await visible(page, '#confirm-dialog.is-open, #confirm-dialog[open], .lime-confirm-dialog.is-open')) await page.click('#confirm-dialog-confirm'); };
  const top = () => page.evaluate(() => LimeMobileNav.topOverlay());
  const stateOv = () => page.evaluate(() => JSON.stringify((history.state && history.state.ov) || []));
  check(tag('Account is one history entry on top of Messages (overlays: ' + (await stateOv()) + ')'), (await top()) === 'account' && (await stateOv()) === '["account"]');
  await page.click('[data-account-go="security"]');
  await discard();
  await wait(page, () => document.getElementById('settings-pane-title').textContent === 'Login & security');
  check(tag('Login & security opens as its own screen on top of Account'), (await top()) === 'account-security' && (await stateOv()) === '["account","account-security"]');
  await page.click('.lime-settings__back');
  await wait(page, () => document.getElementById('settings-pane-title').textContent === 'Account');
  check(tag('"<" from Login & security returns to Account'), (await top()) === 'account');
  await page.click('[data-account-go="preferences"]');
  await discard();
  await wait(page, () => document.getElementById('settings-pane-title').textContent === 'Preferences');
  await page.goBack();
  await wait(page, () => document.getElementById('settings-pane-title').textContent === 'Account');
  check(tag('the browser\'s back from Preferences does the same: back on Account'), (await top()) === 'account' && (await visible(page, '#settings-modal')));
  await page.click('.lime-settings__back');
  await discard();
  await wait(page, () => !document.getElementById('settings-modal').classList.contains('is-open'));
  check(tag('"<" from Account returns to Messages: the dock is back, no overlay left in the history entry'), (await view(page)) === 'contacts' && (await visible(page, '#m-dock')) && (await stateOv()) === '[]' && (await top()) === null);
  // Account → Login & security → "<" twice = back where you started
  await page.evaluate(() => { document.getElementById('toast-container').innerHTML = ''; }); // toasts float at the bottom now, over Account's last rows
  await page.click('#m-account-btn');
  await wait(page, () => document.getElementById('settings-modal').classList.contains('is-open') && !!document.querySelector('[data-account-go="security"]'));
  await page.click('[data-account-go="security"]'); await discard();
  await wait(page, () => document.getElementById('settings-pane-title').textContent === 'Login & security');
  await page.click('.lime-settings__back'); await sleep(300);
  await page.click('.lime-settings__back'); await discard();
  await wait(page, () => !document.getElementById('settings-modal').classList.contains('is-open'));
  check(tag('Account > Login & security > "<" twice: back on Messages'), (await view(page)) === 'contacts' && (await stateOv()) === '[]');

  // ── a deep link opens that chat, and back goes to the list ──
  const deep = await openPhone(browser, server, S.mia, tag('deep link'), errors, Object.assign({}, size, { hash: '#c=' + S.zed }));
  await wait(deep, () => document.getElementById('layout').dataset.mobileView === 'thread');
  check(tag('a #c= link opens that chat on a phone'), (await deep.evaluate(() => document.getElementById('m-chat-title-text').textContent)) === 'Zed Team');
  await deep.goBack();
  await wait(deep, () => document.getElementById('layout').dataset.mobileView === 'contacts');
  check(tag('and back from it lands on the Messages list'), (await visible(deep, '#m-dock')));
  await deep.close();

  // ── LIME-82: Messages v2 (design 01): the logo button, the search + avatar pill, chips, the "+" floating button ──
  await page.evaluate(() => { document.getElementById('toast-container').innerHTML = ''; });
  const v2 = await page.evaluate(() => {
    const R = (e) => e.getBoundingClientRect(); const dock = R(document.getElementById('m-dock')); const fab = R(document.getElementById('m-fab')); const logo = R(document.getElementById('m-logo-btn')); const pill = R(document.querySelector('.m-head-pill'));
    const glass = (e) => { const cs = getComputedStyle(e); return /blur/.test(cs.backdropFilter || cs.webkitBackdropFilter || ''); };
    const unread = document.querySelector('#m-list .lime-contact--unread-count'); const time = unread && getComputedStyle(unread.querySelector('.lime-contact__time--m')).color; const name = unread && getComputedStyle(unread.querySelector('.lime-contact__name')).color;
    const h1 = document.querySelector('.m-messages__head h1');
    return { logo: [Math.round(logo.width), Math.round(logo.left)], logoGlass: glass(document.getElementById('m-logo-btn')), pillRight: Math.round(innerWidth - pill.right), pillGlass: glass(document.querySelector('.m-head-pill')), chips: [...document.querySelectorAll('#m-chips .m-chip')].map((c) => c.textContent).join(), fabRight: Math.round(innerWidth - fab.right), fabAboveDock: fab.bottom <= dock.top - 8, fabSize: Math.round(fab.width), fabHit: (() => { const at = document.elementFromPoint(fab.left + fab.width / 2, fab.top + fab.height / 2); return !!(at && document.getElementById('m-fab').contains(at)); })(), timeInk: time === name, h1: !!h1 && h1.textContent === 'Messages' && R(h1).width <= 1, title: !!document.querySelector('.m-messages__title') };
  });
  check(tag('Messages v2: the logo in a round glass button at the left, a glass pill with search and your avatar at the right, chips "All" and "Unread", no visible title (an accessible heading remains)'), v2.logo[0] === 52 && v2.logoGlass && v2.pillGlass && v2.pillRight <= 24 && v2.chips === 'All,Unread' && v2.h1 && !v2.title, JSON.stringify(v2));
  check(tag('the New message "+" floats at the bottom right above the dock (lime shaped, hit-testable), and unread times are ink, not green'), v2.fabRight <= 28 && v2.fabAboveDock && v2.fabSize >= 60 && v2.fabHit && v2.timeInk, JSON.stringify(v2));
  await page.evaluate(() => { document.getElementById('m-list').style.paddingBottom = '1500px'; document.querySelector('.lime-list-col__scroll').scrollTop = 260; });
  await sleep(250);
  await page.click('#m-logo-btn');
  await wait(page, () => document.querySelector('.lime-list-col__scroll').scrollTop < 2, undefined, 4000);
  check(tag('the logo button scrolls the list back to the top'), true);
  await page.evaluate(() => { document.getElementById('m-list').style.paddingBottom = ''; });
  await page.click('#m-search-btn'); await sleep(200);
  const sr = await page.evaluate(() => ({ searching: document.getElementById('m-messages').classList.contains('is-searching'), field: getComputedStyle(document.querySelector('.m-search')).display, chips: getComputedStyle(document.getElementById('m-chips')).display, focused: document.activeElement && document.activeElement.id }));
  check(tag('the search icon opens a search field over the chips and focuses it'), sr.searching && sr.field !== 'none' && sr.chips === 'none' && sr.focused === 'm-search-input', JSON.stringify(sr));
  await page.click('#m-search-close'); await sleep(200);
  const chipState = await page.evaluate(() => [...document.querySelectorAll('#m-chips .m-chip')].map((c) => c.getAttribute('aria-pressed')).join());
  check(tag('"All" is the chip that is on to begin with'), chipState === 'true,false', chipState);

  // ── LIME-82: toasts are glass, about 75% of the width, centred, just above the dock (above the composer in a chat) ──
  const toastBox = async (inChat) => {
    await page.evaluate(() => { document.getElementById('toast-container').innerHTML = ''; LimeToast.show({ title: 'Jam is coming soon', tone: 'info', duration: 0 }); });
    await sleep(500);
    return page.evaluate((chat) => {
      const t = document.querySelector('#toast-container .lime-toast'); const r = t.getBoundingClientRect(); const cs = getComputedStyle(t);
      const ref = chat ? document.getElementById('composer').getBoundingClientRect().top : document.getElementById('m-dock').getBoundingClientRect().top;
      const header = chat ? document.getElementById('m-chatbar').getBoundingClientRect().bottom : document.getElementById('m-messages-head').getBoundingClientRect().bottom;
      return { pct: Math.round(r.width / innerWidth * 100), centre: Math.round(Math.abs((r.left + r.right) / 2 - innerWidth / 2)), gap: Math.round(ref - r.bottom), belowHeader: r.top > header, blur: /blur/.test(cs.backdropFilter || cs.webkitBackdropFilter || ''), radius: parseFloat(cs.borderTopLeftRadius) };
    }, inChat);
  };
  const tm = await toastBox(false);
  check(tag('toast on Messages: glass, ' + tm.pct + '% of the width, centred, ' + tm.gap + 'px above the dock, below the header'), tm.pct >= 73 && tm.pct <= 77 && tm.centre <= 2 && tm.gap >= 4 && tm.gap <= 40 && tm.belowHeader && tm.blur && tm.radius >= 20, JSON.stringify(tm));
  await page.evaluate((id) => document.querySelector('#m-list [data-conversation-id="' + id + '"]').click(), S.zed);
  await wait(page, () => document.getElementById('layout').dataset.mobileView === 'thread');
  await sleep(400);
  const tc = await toastBox(true);
  check(tag('toast in a chat: ' + tc.pct + '% wide, centred, ' + tc.gap + 'px above the composer, never over the header'), tc.pct >= 73 && tc.pct <= 77 && tc.centre <= 2 && tc.gap >= 4 && tc.gap <= 40 && tc.belowHeader && tc.blur, JSON.stringify(tc));
  await page.evaluate(() => { document.getElementById('toast-container').innerHTML = ''; });

  // ── LIME-82: the photo wall and the viewer are on the back stack: back closes the viewer, then the wall, then you are in the chat ──
  const ovNow = () => page.evaluate(() => JSON.stringify((history.state && history.state.ov) || []));
  const flags = () => page.evaluate(() => ({ wall: document.getElementById('photo-wall').classList.contains('is-open'), viewer: document.getElementById('lightbox').classList.contains('is-open'), view: document.getElementById('layout').dataset.mobileView }));
  await page.evaluate(() => { openPhotoWall('no-such-message'); });
  await sleep(150);
  await page.evaluate(() => { openLightbox([{ path: '', name: 'a.png' }, { path: '', name: 'b.png' }], 0, { fromWall: true }); });
  await sleep(150);
  check(tag('wall then viewer: two entries on the stack (' + (await ovNow()) + ')'), (await ovNow()) === '["wall","viewer"]' && (await flags()).viewer);
  await page.goBack(); await sleep(250);
  const f1 = await flags();
  check(tag('back closes the viewer and shows the wall again'), !f1.viewer && f1.wall && (await ovNow()) === '["wall"]', JSON.stringify(f1));
  await page.goBack(); await sleep(250);
  const f2 = await flags();
  check(tag('back again closes the wall and you are in the chat'), !f2.viewer && !f2.wall && f2.view === 'thread' && (await ovNow()) === '[]', JSON.stringify(f2));
  await page.evaluate(() => { openLightbox([{ path: '', name: 'a.png' }], 0, { fromWall: false }); });
  await sleep(150);
  check(tag('a photo opened directly is one entry'), (await ovNow()) === '["viewer"]' && (await flags()).viewer);
  await page.evaluate(() => document.getElementById('lightbox-close').click()); await sleep(300);
  const f3 = await flags();
  check(tag('its close button pops that entry (so back is not left stranded)'), !f3.viewer && f3.view === 'thread' && (await ovNow()) === '[]', JSON.stringify(f3));
  await page.evaluate(() => { openPhotoWall('no-such-message'); }); await sleep(150);
  await page.evaluate(() => document.getElementById('wall-close').click()); await sleep(300);
  check(tag('the wall\'s close button does the same, and Escape too'), !(await flags()).wall && (await ovNow()) === '[]');
  await page.evaluate(() => { openPhotoWall('no-such-message'); }); await sleep(150);
  await page.keyboard.press('Escape'); await sleep(300);
  check(tag('Escape closes the wall through the stack'), !(await flags()).wall && (await ovNow()) === '[]');
  await page.click('#m-chat-back');
  await wait(page, () => document.getElementById('layout').dataset.mobileView === 'contacts');

  // ── LIME-83: the v2 composer: toolbar, the "Aa" menu, formatting that survives into the sent bubble, and a sanitiser that stays strict ──
  const san = await page.evaluate(() => {
    const dirty = '<p style="color:red" onclick="a()" data-align="center">hi<script>alert(1)</script></p>'
      + '<p data-align="evil" data-indent="9" class="x">two</p>'
      + '<p data-indent="2">three</p>'
      + '<ul><li data-align="right" style="x" data-indent="2">item</li></ul>'
      + '<div data-align="center">div</div><span data-align="center">span</span>'
      + '<a href="javascript:alert(1)" onclick="b()">link</a><a href="https://example.com/" style="x">ok</a>'
      + '<img src="x" onerror="c()"><blockquote style="x" data-align="justify">q</blockquote>';
    const clean = sanitizeHtml(dirty);
    const rendered = renderRichHtml(dirty);
    return { clean, hostile: /style=|onclick|onerror|javascript:|<script|<img|class=|<div|<span/i.test(clean + rendered), keeps: ['<p data-align="center">hi</p>', '<p>two</p>', '<p data-indent="2">three</p>', '<li data-align="right">item</li>', '<blockquote data-align="justify">q</blockquote>', '<a href="https://example.com/">ok</a>'].every((x) => clean.includes(x)) };
  });
  check(tag('the sanitiser keeps data-align (center, right, justify) and data-indent (1 to 3) on the right tags and still strips style, on*, javascript: links, class, scripts, images, divs and spans'), !san.hostile && san.keeps, san.clean);
  await page.evaluate(() => { document.getElementById('toast-container').innerHTML = ''; });
  await page.evaluate((id) => document.querySelector('#m-list [data-conversation-id="' + id + '"]').click(), S.dm);
  await wait(page, () => document.getElementById('layout').dataset.mobileView === 'thread');
  await sleep(300);
  await page.click('#composer-input');
  await wait(page, () => document.getElementById('composer').classList.contains('is-expanded'));
  await sleep(250);
  const tb = await page.evaluate(() => {
    const c = document.getElementById('composer'); const tbar = c.querySelector('.lime-composer__toolbar'); const R = (e) => e.getBoundingClientRect();
    const shown = (q) => { const e = c.querySelector(q); if (!e) return false; const r = R(e); return getComputedStyle(e).display !== 'none' && r.width > 0; };
    const left = (q) => Math.round(R(c.querySelector(q)).left);
    const xs = { plus: left('[data-attach-btn]'), emoji: left('[data-emoji-btn]'), aa: left('.lime-composer__tool--aa'), bullets: left('.lime-composer__toolbar > [data-cmd="unorderedList"]'), numbers: left('.lime-composer__toolbar > [data-cmd="orderedList"]'), link: left('.lime-composer__toolbar > [data-cmd="link"]'), code: left('.lime-composer__toolbar > [data-cmd="code"]'), mic: left('.lime-voice-split__mic'), send: left('.lime-composer__return') };
    const order = Object.values(xs); const cr = R(c);
    return { xs, ordered: order.every((v, i) => i === 0 || v > order[i - 1]), hidden: !['.lime-composer__toolbar > [data-cmd="bold"]', '.lime-composer__toolbar > [data-cmd="italic"]', '.lime-composer__toolbar > [data-cmd="underline"]', '.lime-composer__toolbar > [data-cmd="strikethrough"]', '.lime-composer__toolbar > [data-cmd="quote"]', '.lime-composer__overflow'].some(shown), fits: tbar.scrollWidth <= tbar.clientWidth + 1, inside: cr.left >= 8 && cr.right <= innerWidth - 8, sendRight: Math.round(cr.right - R(c.querySelector('.lime-composer__return')).right), glass: /blur/.test(getComputedStyle(c).backdropFilter || getComputedStyle(c).webkitBackdropFilter || '') };
  });
  check(tag('the expanded composer (design 03): "+", emoji, Aa, bulleted list, numbered list, link, code on the left, mic and send on the right, in that order, all fitting, no B I U S or "...", glass'), tb.ordered && tb.hidden && tb.fits && tb.inside && tb.glass, JSON.stringify(tb));
  await page.keyboard.type('Hello world');
  await page.evaluate(() => { const i = document.getElementById('composer-input'); const r = document.createRange(); r.selectNodeContents(i); const sel = getSelection(); sel.removeAllRanges(); sel.addRange(r); });
  const fmt = async (cmd) => { await page.click('#composer-aa-btn'); await wait(page, () => document.getElementById('composer-format-menu').classList.contains('is-open')); await sleep(300); await page.click('#composer-format-menu [data-cmd="' + cmd + '"]'); await sleep(200); };
  const aaGroups = await (async () => { await page.click('#composer-aa-btn'); await wait(page, () => document.getElementById('composer-format-menu').classList.contains('is-open')); await sleep(300); const g = await page.evaluate(() => { const m = document.getElementById('composer-format-menu'); const out = [[]]; [...m.children].forEach((e) => { if (e.classList.contains('lime-menu__divider')) out.push([]); else out[out.length - 1].push(e.dataset.cmd); }); return out.map((x) => x.join()).join(' | '); }); await page.keyboard.press('Escape'); await page.evaluate(() => document.body.click()); await sleep(150); return g; })();
  check(tag('the Aa menu has three groups: ' + aaGroups), aaGroups === 'bold,italic,underline,strikethrough | unorderedList,orderedList,indent,outdent | alignLeft,alignCenter,alignRight,alignJustify', aaGroups);
  await page.evaluate(() => { const i = document.getElementById('composer-input'); i.focus(); const r = document.createRange(); r.selectNodeContents(i); const sel = getSelection(); sel.removeAllRanges(); sel.addRange(r); });
  await fmt('bold');
  await page.evaluate(() => { const i = document.getElementById('composer-input'); i.focus(); const r = document.createRange(); r.selectNodeContents(i); const sel = getSelection(); sel.removeAllRanges(); sel.addRange(r); });
  await fmt('alignCenter');
  await fmt('indent');
  const comp1 = await page.evaluate(() => { const i = document.getElementById('composer-input'); return { html: i.innerHTML, center: !!i.querySelector('[data-align="center"]'), indent: !!i.querySelector('[data-indent="1"]'), bold: !!i.querySelector('b, strong'), style: /style=/.test(i.innerHTML), pressed: [...document.querySelectorAll('#composer-format-menu [aria-pressed="true"]')].map((e) => e.dataset.cmd).sort().join() }; });
  check(tag('Bold, Align centre and Indent apply to the text in the composer (data-align, data-indent, no style), and the active ones show as on: ' + comp1.pressed), comp1.center && comp1.indent && comp1.bold && !comp1.style && /alignCenter/.test(comp1.pressed) && /indent/.test(comp1.pressed) && /bold/.test(comp1.pressed), JSON.stringify(comp1));
  await page.keyboard.press('Escape'); await page.evaluate(() => document.body.click());
  await page.evaluate(() => { document.getElementById('composer-input').focus(); });
  await page.keyboard.press('Enter');
  await wait(page, () => { const m = [...document.querySelectorAll('#thread-messages .lime-message--sent')].pop(); return m && m.querySelector('[data-align="center"]'); });
  const sent1 = await page.evaluate(() => { const m = [...document.querySelectorAll('#thread-messages .lime-message--sent')].pop(); const p = m.querySelector('[data-align="center"]'); const cs = getComputedStyle(p); return { text: p.textContent, align: cs.textAlign, marginLeft: parseFloat(cs.marginLeft), bold: !!m.querySelector('b, strong'), indentAttr: p.getAttribute('data-indent') }; });
  check(tag('the sent bubble shows it: centred, indented, bold ("' + sent1.text + '")'), sent1.text === 'Hello world' && sent1.align === 'center' && sent1.marginLeft > 10 && sent1.bold && sent1.indentAttr === '1', JSON.stringify(sent1));
  await page.click('#composer-input'); await sleep(200);
  await page.keyboard.type('Alpha');
  await page.click('#composer .lime-composer__toolbar > [data-cmd="unorderedList"]'); await sleep(200);
  await page.click('#composer-send'); // Return inside a list adds an item (existing rule), so a list is sent with the arrow
  await wait(page, () => { const m = [...document.querySelectorAll('#thread-messages .lime-message--sent')].pop(); return m && m.querySelector('ul li'); });
  check(tag('the bulleted-list button in the toolbar makes a real list in the sent bubble'), (await page.evaluate(() => { const m = [...document.querySelectorAll('#thread-messages .lime-message--sent')].pop(); return m.querySelector('ul li').textContent; })) === 'Alpha');
  await page.evaluate(() => document.getElementById('composer-input').blur()); await sleep(300);
  await page.click('#m-chat-back');
  await wait(page, () => document.getElementById('layout').dataset.mobileView === 'contacts');

  // ── LIME-79-fix6: New message is a full pushed screen; back always returns to where you came from ──
  const topOv = () => page.evaluate(() => LimeMobileNav.topOverlay());
  const ovState = () => page.evaluate(() => JSON.stringify((history.state && history.state.ov) || []));
  await page.evaluate(() => { document.getElementById('toast-container').innerHTML = ''; }); // earlier toasts would sit over the list
  await page.click('#m-fab');
  await wait(page, () => document.getElementById('picker-modal').classList.contains('is-open'));
  await sleep(200);
  const nm = await page.evaluate(() => {
    const m = document.getElementById('picker-modal'); const r = m.getBoundingClientRect(); const bar = document.querySelector('.lime-picker__bar'); const t = bar.querySelector('.lime-picker__bar-title').getBoundingClientRect();
    const at = document.elementFromPoint(t.left + t.width / 2, t.top + t.height / 2);
    return { w: r.width, h: r.height, vw: innerWidth, vh: innerHeight, title: bar.querySelector('.lime-picker__bar-title').textContent, hit: !!(at && m.contains(at)), start: document.getElementById('picker-start-top').disabled, backShown: bar.querySelector('#picker-back').getBoundingClientRect().width >= 44, closeShown: getComputedStyle(document.getElementById('picker-close')).display !== 'none', backdrop: getComputedStyle(document.getElementById('picker-backdrop')).display, radius: getComputedStyle(m).borderTopLeftRadius };
  });
  check(tag('"+" opens New message as a full screen (' + nm.w + 'x' + nm.h + '), with "<", the title "New message" and a disabled Start, no x, no dimmed backdrop, and really on top'), nm.w >= nm.vw - 0.5 && nm.h >= nm.vh - 0.5 && nm.title === 'New message' && nm.hit && nm.start && nm.backShown && !nm.closeShown && nm.backdrop === 'none' && (await topOv()) === 'new-message', JSON.stringify(nm));
  await page.type('#picker-input', 'Ned');
  await wait(page, () => document.querySelectorAll('#picker-results .lime-picker__result').length > 0);
  await sleep(900); // the directory answer re-draws the list once; tap after it
  await page.click('#picker-results .lime-picker__result');
  await sleep(150);
  const picked = await page.evaluate(() => ({ chips: document.querySelectorAll('#picker-chips .lime-picker__chip').length, start: document.getElementById('picker-start-top').disabled, row: (() => { const r = document.querySelector('#picker-results .lime-picker__result'); const a = r.querySelector('.lime-avatar'); return { h: r.getBoundingClientRect().height, avatar: !!a }; })() }));
  check(tag('picking someone shows a chip and enables Start; the results have avatars and roomy rows (' + Math.round(picked.row.h) + 'px)'), picked.chips === 1 && !picked.start && picked.row.avatar && picked.row.h >= 56, JSON.stringify(picked));
  await page.click('#picker-back');
  await wait(page, () => !document.getElementById('picker-modal').classList.contains('is-open'));
  check(tag('"<" returns to Messages: the dock is back and no overlay is left'), (await view(page)) === 'contacts' && (await visible(page, '#m-dock')) && (await ovState()) === '[]' && (await topOv()) === null);
  await page.click('#m-fab');
  await wait(page, () => document.getElementById('picker-modal').classList.contains('is-open'));
  await page.goBack();
  await wait(page, () => !document.getElementById('picker-modal').classList.contains('is-open'));
  check(tag('the browser\'s back closes New message too'), (await view(page)) === 'contacts' && (await topOv()) === null);
  await page.click('#m-fab');
  await wait(page, () => document.getElementById('picker-modal').classList.contains('is-open'));
  await page.type('#picker-input', 'Oli');
  await wait(page, () => document.querySelectorAll('#picker-results .lime-picker__result').length > 0);
  await sleep(900);
  await page.click('#picker-results .lime-picker__result');
  await page.click('#picker-start-top');
  await wait(page, () => document.getElementById('layout').dataset.mobileView === 'thread' && !document.getElementById('picker-modal').classList.contains('is-open'));
  await sleep(300);
  check(tag('Start opens the chat on top of Messages (not on top of New message)'), (await ovState()) === '[]' && (await topOv()) === null);
  await page.click('#m-chat-back');
  await wait(page, () => document.getElementById('layout').dataset.mobileView === 'contacts');
  check(tag('and "<" from that chat lands on Messages, not on New message'), !(await page.evaluate(() => document.getElementById('picker-modal').classList.contains('is-open'))) && (await visible(page, '#m-dock')));

  // a person opened from Members, and from a thread: "<" uncovers exactly that screen
  await page.evaluate((id) => document.querySelector('#m-list [data-conversation-id="' + id + '"]').click(), S.planning);
  await wait(page, () => document.getElementById('layout').dataset.mobileView === 'thread');
  await page.click('#m-chat-center');
  await wait(page, () => document.getElementById('right-panel').dataset.panel === 'members');
  await page.click('.lime-members-panel__row:nth-child(2)');
  await wait(page, () => document.getElementById('right-panel').dataset.panel === 'profile');
  check(tag('a person opened from Members is an overlay (back arrow shown)'), (await topOv()) === 'person' && (await visible(page, '#profile-back-btn')));
  await page.goBack();
  await wait(page, () => document.getElementById('right-panel').dataset.panel === 'members');
  check(tag('the browser\'s back from a person returns to Members (not to the chat)'), (await view(page)) === 'panel' && (await topOv()) === null);
  await page.click('.lime-members-panel__row:nth-child(2)');
  await wait(page, () => document.getElementById('right-panel').dataset.panel === 'profile');
  await page.click('#profile-back-btn');
  await wait(page, () => document.getElementById('right-panel').dataset.panel === 'members');
  await page.click('#right-panel-toggle');
  await wait(page, () => document.getElementById('layout').dataset.mobileView === 'thread');
  check(tag('"<" from the person returns to Members, and "<" from Members to the chat'), (await view(page)) === 'thread' && (await ovState()) === '[]');
  // the Account screen opened from a person's "Edit profile": back unwinds each step
  await page.click('#m-chat-center');
  await wait(page, () => document.getElementById('right-panel').dataset.panel === 'members');
  await page.evaluate((id) => document.querySelector('.lime-members-panel__row[data-profile-id="' + id + '"]').click(), S.mia.userId);
  await wait(page, () => document.getElementById('right-panel').dataset.panel === 'profile');
  await page.click('#profile-edit-btn');
  await wait(page, () => document.getElementById('settings-modal').classList.contains('is-open') && !!document.querySelector('[data-account-go="security"]'));
  check(tag('Account opened from a person\'s details stacks on top of it (overlays: ' + (await ovState()) + ')'), (await ovState()) === '["person","account"]');
  await page.click('.lime-settings__back'); await discard();
  await wait(page, () => !document.getElementById('settings-modal').classList.contains('is-open'));
  check(tag('"<" from Account returns to that person\'s details'), (await page.evaluate(() => document.getElementById('right-panel').dataset.panel)) === 'profile' && (await view(page)) === 'panel' && (await ovState()) === '["person"]');
  await page.click('#profile-back-btn');
  await wait(page, () => document.getElementById('right-panel').dataset.panel === 'members');
  await page.click('#right-panel-toggle');
  await wait(page, () => document.getElementById('layout').dataset.mobileView === 'thread');
  check(tag('then Members, then the chat: each "<" goes back one step to where you came from'), (await view(page)) === 'thread' && (await ovState()) === '[]');
  // an avatar tapped inside a thread screen: "<" returns to the thread screen, not to the chat
  await page.evaluate((pid) => document.querySelector('#thread-messages [data-message-id="' + pid + '"] .lime-message__replies').click(), parentId);
  await wait(page, () => document.getElementById('right-panel').dataset.panel === 'replies');
  await page.evaluate(() => document.querySelector('#replies-list .lime-avatar[data-profile-id]').click());
  await wait(page, () => document.getElementById('right-panel').dataset.panel === 'profile');
  await page.click('#profile-back-btn');
  await wait(page, () => document.getElementById('right-panel').dataset.panel === 'replies');
  check(tag('a person opened from the thread screen: "<" returns to the thread screen'), (await view(page)) === 'panel' && (await topOv()) === null);
  await page.click('#right-panel-toggle');
  await wait(page, () => document.getElementById('layout').dataset.mobileView === 'thread');
  await page.click('#m-chat-back');
  await wait(page, () => document.getElementById('layout').dataset.mobileView === 'contacts');

  // ── the phone chat (LIME-79) in Zed Team: Oli x3 (a run, then a long link), Mia x2 (a run), a reaction on Mia's first ──
  await page.evaluate((id) => document.querySelector('#m-list [data-conversation-id="' + id + '"]').click(), S.zed);
  await wait(page, () => document.getElementById('layout').dataset.mobileView === 'thread' && document.querySelectorAll('#thread-messages .lime-message').length >= 5);
  await sleep(400);
  const chat = await page.evaluate(() => {
    const rgb = (c) => (c.match(/\d+(\.\d+)?/g) || []).slice(0, 3).map(Number).join(',');
    const msgs = [...document.querySelectorAll('#thread-messages .lime-message')];
    const vw = window.innerWidth; const thread = document.getElementById('thread-messages');
    const info = msgs.map((m) => {
      const bubble = m.querySelector('.lime-message__content'); const br = bubble.getBoundingClientRect();
      const av = m.querySelector('.lime-avatar-frame'); const meta = m.querySelector('.lime-message__meta');
      const stamp = m.querySelector('.lime-message__stamp-time');
      return {
        sent: m.classList.contains('lime-message--sent'), first: m.classList.contains('lime-message--first'), cont: m.classList.contains('lime-message--cont'),
        text: (m.querySelector('.lime-message__text') || {}).textContent, left: br.left, right: br.right, width: br.width,
        bg: rgb(getComputedStyle(bubble).backgroundColor), ink: rgb(getComputedStyle(m.querySelector('.lime-message__text') || bubble).color),
        avatarDisplay: getComputedStyle(av).display, avatarVis: getComputedStyle(av).visibility, metaDisplay: getComputedStyle(meta).display,
        footVisible: getComputedStyle(m.querySelector('.lime-message__foot')).display !== 'none', addVisible: getComputedStyle(m.querySelector('.lime-react-add')).display !== 'none',
        receipt: m.querySelector('.lime-receipt') ? getComputedStyle(m.querySelector('.lime-receipt')).display !== 'none' : null, time: stamp && stamp.textContent,
        overflows: [...m.querySelectorAll('*')].filter((e) => e.getBoundingClientRect().right > vw + 0.5).length,
      };
    });
    return { info, vw, tw: thread.clientWidth, sw: thread.scrollWidth, docSw: document.documentElement.scrollWidth };
  });
  const oli = chat.info.filter((m) => !m.sent), mine = chat.info.filter((m) => m.sent);
  check(tag('a run: only the first of Oli\'s three messages shows the avatar and the name; the next two keep the space but show neither'), oli.length === 3 && oli[0].first && oli[0].avatarVis === 'visible' && oli[0].metaDisplay !== 'none' && oli.slice(1).every((m) => m.cont && m.avatarVis === 'hidden' && m.metaDisplay === 'none'), JSON.stringify(oli.map((m) => [m.first, m.avatarVis, m.metaDisplay])));
  check(tag('your own messages are on the right, in light green (#a3e18a) with ink text, and with no avatar or name'), mine.length === 2 && mine.every((m) => m.bg === '163,225,138' && m.ink.split(',').reduce((x, y) => x + Number(y), 0) < 120 && m.avatarDisplay === 'none' && m.metaDisplay === 'none' && chat.vw - m.right <= 16), JSON.stringify(mine.map((m) => [m.bg, m.ink, m.avatarDisplay, Math.round(chat.vw - m.right)])));
  check(tag('others\' messages are on the left in the neutral bubble (not green), clear of the avatar'), oli.every((m) => m.bg !== '163,225,138' && m.left >= 44 && m.left < chat.vw / 2), JSON.stringify(oli.map((m) => [m.bg, Math.round(m.left)])));
  check(tag('no bubble is wider than about 78% of the thread'), chat.info.every((m) => m.width <= chat.tw * 0.78 + 1), JSON.stringify(chat.info.map((m) => Math.round(m.width / chat.tw * 100))));
  check(tag('nothing overflows the screen: the long link wraps, the thread does not scroll sideways'), chat.info.every((m) => m.overflows === 0) && chat.sw <= chat.tw && chat.docSw <= chat.vw, JSON.stringify({ sw: chat.sw, tw: chat.tw, docSw: chat.docSw, vw: chat.vw }));
  check(tag('under every bubble: the reaction row with add-reaction, and a time written in lowercase'), chat.info.every((m) => m.footVisible && m.addVisible && /^\d{1,2}:\d{2} (am|pm)$|^Sent \d{1,2}:\d{2} (am|pm) \u00b7 delivered \d{1,2}:\d{2} (am|pm)$/.test(m.time)), JSON.stringify(chat.info.map((m) => m.time)));
  check(tag('your messages carry a receipt slot (a check); others\' do not'), mine.every((m) => m.receipt === true) && oli.every((m) => m.receipt === null));
  // reactions: Oli's thumbs-up on Mia's "Thanks!" shows as a chip; the add-reaction button opens the picker and adds one
  check(tag('Oli\'s reaction shows as a chip under Mia\'s message'), await page.evaluate(() => { const m = [...document.querySelectorAll('#thread-messages .lime-message--sent')][0]; return /1/.test(m.querySelector('.lime-message__reactions').textContent) && m.querySelector('.lime-message__reactions').textContent.includes('\u{1F44D}'); }));
  // the add-reaction button opens the same glass menu as press-and-hold, right beside the button (and never the old floating strip)
  await page.evaluate(() => { document.getElementById('toast-container').innerHTML = ''; });
  await page.evaluate(() => [...document.querySelectorAll('#thread-messages .lime-message--received .lime-react-add')][0].click());
  await wait(page, () => !!document.querySelector('.m-msg-menu.is-open'));
  await sleep(250);
  const anchored = await page.evaluate(() => { const b = [...document.querySelectorAll('#thread-messages .lime-message--received .lime-react-add')][0].getBoundingClientRect(); const m = document.querySelector('.m-msg-menu').getBoundingClientRect(); const strip = document.querySelector('.lime-reaction-picker.is-open'); const gap = m.top >= b.bottom ? m.top - b.bottom : b.top - m.bottom; return { gap, overlapX: m.left <= b.right && m.right >= b.left, strip: strip ? getComputedStyle(strip).display : 'none', items: [...document.querySelectorAll('.m-msg-menu .m-glass-menu__item')].map((e) => e.textContent.trim()).join() }; });
  check(tag('the add-reaction button opens the glass reactions menu right beside it (gap ' + Math.round(anchored.gap) + 'px), with Reply and Copy, and no floating emoji strip'), anchored.gap >= 0 && anchored.gap <= 14 && anchored.overlapX && anchored.strip === 'none' && anchored.items === 'Reply in thread,Copy text', JSON.stringify(anchored));
  await page.evaluate(() => document.querySelector('.m-msg-menu [data-emoji="❤️"]').click());
  await wait(page, () => { const m = document.querySelector('#thread-messages .lime-message--received'); return m.querySelector('.lime-message__reactions').textContent.includes('❤'); });
  check(tag('the chosen emoji from that menu appears as a chip'), !(await page.evaluate(() => !!document.querySelector('.m-msg-menu.is-open'))));
  // "+" grows the menu with more emoji
  await page.evaluate(() => [...document.querySelectorAll('#thread-messages .lime-message--received .lime-react-add')][0].click());
  await wait(page, () => !!document.querySelector('.m-msg-menu.is-open'));
  await page.evaluate(() => document.querySelector('.m-msg-menu .m-msg-menu__more').click());
  await sleep(150);
  const more = await page.evaluate(() => { const g = document.querySelector('.m-msg-menu__grid'); const r = document.querySelector('.m-msg-menu').getBoundingClientRect(); return { shown: !g.hidden && g.getBoundingClientRect().height > 40, n: g.querySelectorAll('[data-emoji]').length, inside: r.top >= 0 && r.bottom <= innerHeight && r.left >= 0 && r.right <= innerWidth }; });
  check(tag('"+" opens twelve more emoji inside the same menu, which stays inside the screen'), more.shown && more.n === 12 && more.inside, JSON.stringify(more));
  await page.keyboard.press('Escape');
  check(tag('no inline reply button under bubbles any more (only add-reaction)'), (await page.evaluate(() => document.querySelectorAll('#thread-messages .lime-reply-add').length)) === 0 && (await page.evaluate(() => document.querySelectorAll('#thread-messages .lime-foot-btn').length)) === (await page.evaluate(() => document.querySelectorAll('#thread-messages .lime-message').length)));

  // ── press and hold a message: a glass menu with six quick reactions, Reply in thread, Copy text ──
  const holdAt = async (sel, ms) => {
    const box = await page.evaluate((q) => { const el = document.querySelector(q); el.scrollIntoView({ block: 'center' }); const r = el.getBoundingClientRect(); return { x: r.left + Math.min(r.width / 2, 40), y: r.top + r.height / 2 }; }, sel);
    await sleep(150);
    await page.mouse.move(box.x, box.y); await page.mouse.down(); await sleep(ms); await page.mouse.up();
  };
  await page.evaluate(() => { document.getElementById('toast-container').innerHTML = ''; }); // earlier toasts still cover the top of the thread
  await holdAt('#thread-messages .lime-message--received .lime-message__content', 150);
  await sleep(250);
  check(tag('a short press does not open the hold menu'), !(await page.evaluate(() => !!document.querySelector('.m-msg-menu.is-open'))));
  await holdAt('#thread-messages .lime-message--received .lime-message__content', 560);
  await wait(page, () => !!document.querySelector('.m-msg-menu.is-open'));
  const hold = await page.evaluate(() => {
    const m = document.querySelector('.m-msg-menu'); const r = m.getBoundingClientRect(); const cs = getComputedStyle(m);
    const bubble = document.querySelector('#thread-messages .lime-message--held .lime-message__content');
    return { emoji: [...m.querySelectorAll('.m-msg-menu__react .m-msg-menu__emoji:not(.m-msg-menu__more)')].map((b) => b.dataset.emoji).length, more: !!m.querySelector('.m-msg-menu__more'), items: [...m.querySelectorAll('.m-glass-menu__item')].map((b) => b.textContent.trim()), blur: cs.backdropFilter || cs.webkitBackdropFilter, bg: cs.backgroundColor, radius: parseFloat(cs.borderTopLeftRadius), left: r.left, right: r.right, top: r.top, bottom: r.bottom, vw: innerWidth, vh: innerHeight, rowH: m.querySelector('.m-glass-menu__item').getBoundingClientRect().height, rowFs: parseFloat(getComputedStyle(m.querySelector('.m-glass-menu__item')).fontSize), sel: getComputedStyle(bubble).userSelect || getComputedStyle(bubble).webkitUserSelect, callout: getComputedStyle(bubble).webkitTouchCallout, selection: String(getSelection()).length };
  });
  check(tag('the hold menu has six quick reactions and "more", Reply in thread and Copy text'), hold.emoji === 6 && hold.more && hold.items.join() === 'Reply in thread,Copy text', JSON.stringify(hold));
  check(tag('it is glass: translucent, blurred, a large radius, 44px rows of 17px text, inside the screen'), /blur/.test(hold.blur || '') && hold.bg.includes('rgba') || /blur/.test(hold.blur || ''), hold.blur + ' ' + hold.bg);
  check(tag('the hold menu fits the screen with a large radius and 44px, 17px rows'), hold.left >= 8 && hold.right <= hold.vw - 8 && hold.top >= 0 && hold.bottom <= hold.vh && hold.radius >= 20 && hold.rowH >= 44 && hold.rowFs === 17, JSON.stringify(hold));
  check(tag('the pressed bubble starts no text selection (user-select none) and nothing is selected'), hold.sel === 'none' && hold.selection === 0, JSON.stringify([hold.sel, hold.callout, hold.selection]));
  await page.keyboard.press('Escape');
  check(tag('Escape closes the hold menu'), !(await page.evaluate(() => !!document.querySelector('.m-msg-menu.is-open'))) && !(await page.evaluate(() => !!document.querySelector('.lime-message--held'))));
  await holdAt('#thread-messages .lime-message--received .lime-message__content', 560);
  await wait(page, () => !!document.querySelector('.m-msg-menu.is-open'));
  await page.evaluate(() => document.querySelector('.m-msg-menu [data-emoji="\ud83c\udf89"]').click());
  await wait(page, () => [...document.querySelectorAll('#thread-messages .lime-message--received')][0].querySelector('.lime-message__reactions').textContent.includes('\ud83c\udf89'));
  check(tag('a quick reaction from the hold menu adds a chip'), !(await page.evaluate(() => !!document.querySelector('.m-msg-menu.is-open'))));
  await holdAt('#thread-messages .lime-message--received .lime-message__content', 560);
  await wait(page, () => !!document.querySelector('.m-msg-menu.is-open'));
  await page.evaluate(() => document.querySelector('.m-msg-menu [data-act="copy"]').click());
  await wait(page, () => /Copied|copy/.test(document.getElementById('toast-container').textContent));
  check(tag('Copy text copies and says so'), /Copied/.test(await page.evaluate(() => document.getElementById('toast-container').textContent)));
  await page.evaluate(() => { document.getElementById('toast-container').innerHTML = ''; });
  await holdAt('#thread-messages .lime-message--received .lime-message__content', 560);
  await wait(page, () => !!document.querySelector('.m-msg-menu.is-open'));
  await page.evaluate(() => document.querySelector('.m-msg-menu [data-act="reply"]').click());
  await wait(page, () => document.getElementById('layout').dataset.mobileView === 'panel' && document.getElementById('right-panel').dataset.panel === 'replies');
  check(tag('Reply in thread from the hold menu opens the thread screen'), true);
  await page.click('#right-panel-toggle');
  await wait(page, () => document.getElementById('layout').dataset.mobileView === 'thread');

  // the composer: one pill; grows when the text field is focused; Send wakes up on text; Enter sends; folds back when empty and blurred
  const pill = () => page.evaluate(() => { const c = document.getElementById('composer'); const r = c.getBoundingClientRect(); const cs = (sel) => { const e = c.querySelector(sel); return e ? getComputedStyle(e).display : 'none'; }; const ret = c.querySelector('.lime-composer__return'); return { expanded: c.classList.contains('is-expanded'), h: Math.round(r.height), w: Math.round(r.width), left: Math.round(r.left), bottom: Math.round(window.innerHeight - r.bottom), toolbar: cs('.lime-composer__toolbar'), send: cs('.lime-composer__return'), active: ret.classList.contains('is-active'), disabled: ret.getAttribute('aria-disabled'), placeholder: getComputedStyle(c.querySelector('.lime-composer__input'), '::before').content, hint: c.querySelector('.lime-composer__input').getAttribute('enterkeyhint') }; });
  const p0 = await pill();
  check(tag('the composer starts as one pill (one line high) with "Send message..." and no toolbar or send button'), !p0.expanded && p0.h <= 60 && p0.toolbar === 'none' && p0.send === 'none' && /Send message/.test(p0.placeholder), JSON.stringify(p0));
  check(tag('the keyboard\'s return key is labelled Send (enterkeyhint="send")'), p0.hint === 'send');
  await page.setViewport(Object.assign({}, size.emulate ? { width: size.width, height: Math.round(size.height * 0.55), deviceScaleFactor: 2, isMobile: true, hasTouch: true } : { width: size.width, height: Math.round(size.height * 0.55), deviceScaleFactor: 2 }));
  await sleep(300);
  check(tag('the on-screen keyboard shrinking the page does not by itself expand the toolbar'), !(await pill()).expanded);
  await page.setViewport(size.emulate ? { width: size.width, height: size.height, deviceScaleFactor: 2, isMobile: true, hasTouch: true } : { width: size.width, height: size.height, deviceScaleFactor: 2 });
  await page.click('#composer-input');
  await wait(page, () => document.getElementById('composer').classList.contains('is-expanded'));
  await sleep(200);
  const p1 = await pill();
  check(tag('tapping the text field grows it: the toolbar appears, with Send showing but disabled until there is text'), p1.expanded && p1.toolbar !== 'none' && p1.send !== 'none' && p1.disabled === 'true' && !p1.active, JSON.stringify(p1));
  check(tag('the pill sits inside the screen with side margins and clears the bottom edge'), p1.left >= 8 && p1.w <= size.width - 16 && p1.bottom >= 8, JSON.stringify({ left: p1.left, w: p1.w, bottom: p1.bottom }));
  const retState = () => page.evaluate(() => { const b = document.querySelector('#composer .lime-composer__return'); const cs = getComputedStyle(b); const bf = getComputedStyle(b, '::before'); const r = b.getBoundingClientRect(); return { fs: cs.fontSize, opacity: parseFloat(cs.opacity), bg: cs.backgroundColor, color: cs.color, mask: bf.webkitMaskImage || bf.maskImage, boxW: bf.width, w: Math.round(r.width), h: Math.round(r.height), ariaDisabled: b.getAttribute('aria-disabled') }; });
  const rd = await retState();
  check(tag('the return icon is a real icon now (a mask, no stray "↵" text) and, with no text yet, is disabled: faded, no fill'), rd.fs === '0px' && /svg/.test(rd.mask || '') && rd.opacity < 0.6 && rd.bg === 'rgba(0, 0, 0, 0)' && rd.ariaDisabled === 'true' && rd.w >= 40, JSON.stringify(rd));
  await page.keyboard.type('Hello from the phone');
  const cc = await comp('#composer');
  check(tag('the chat composer expanded: "+", emoji, "Aa" at the left, mic and send at the right, no B I U or "..."'), cc.shown.emoji && cc.shown.aa && cc.shown.mic && cc.shown.send && !cc.shown.bold && !cc.shown.overflow && cc.xs.plus < cc.xs.emoji && cc.xs.emoji < cc.xs.aa && cc.xs.aa < cc.xs.mic && cc.xs.mic < cc.xs.send, JSON.stringify(cc));
  const p2 = await pill();
  check(tag('typing wakes Send up (pale lime, enabled)'), p2.active && p2.disabled === 'false', JSON.stringify(p2));
  const re = await retState();
  const pale = await page.evaluate(() => { const t = document.createElement('i'); t.style.background = 'var(--lime-primary-bg)'; document.body.appendChild(t); const c = getComputedStyle(t).backgroundColor; t.remove(); return c; });
  check(tag('with text the return icon is enabled: full strength on the pale-lime fill'), re.opacity === 1 && re.bg === pale && re.bg !== 'rgba(0, 0, 0, 0)', JSON.stringify([re, pale]));
  if (size.emulate) {
    const cdp = await page.createCDPSession();
    await cdp.send('DOM.enable'); await cdp.send('CSS.enable');
    const { root } = await cdp.send('DOM.getDocument');
    const { nodeId } = await cdp.send('DOM.querySelector', { nodeId: root.nodeId, selector: '#composer .lime-composer__return' });
    await cdp.send('CSS.forcePseudoState', { nodeId, forcedPseudoClasses: ['active'] });
    const pressed = await retState();
    await cdp.send('CSS.forcePseudoState', { nodeId, forcedPseudoClasses: [] });
    const pressedLime = await page.evaluate(() => { const t = document.createElement('i'); t.style.background = 'var(--lime-primary-bg-active)'; document.body.appendChild(t); const c = getComputedStyle(t).backgroundColor; t.remove(); return c; });
    check(tag('pressed, the return icon takes the darker lime step'), pressed.bg === pressedLime && pressed.bg !== re.bg, JSON.stringify([pressed.bg, pressedLime, re.bg]));
    await cdp.detach();
  }
  const before = await page.evaluate((id) => LimeStore.listMessages(id).length, S.zed);
  await page.keyboard.press('Enter');
  await wait(page, (a) => LimeStore.listMessages(a.id).length === a.n + 1, { id: S.zed, n: before });
  const sentLine = await page.evaluate(() => { const ms = [...document.querySelectorAll('#thread-messages .lime-message--sent')]; const last = ms[ms.length - 1]; return { text: last.querySelector('.lime-message__text').textContent, cont: last.classList.contains('lime-message--cont') }; });
  check(tag('the keyboard\'s Return key sends (no new line), the message appears on the right as part of your run'), sentLine.text === 'Hello from the phone' && sentLine.cont === true, JSON.stringify(sentLine));
  const p3 = await pill();
  check(tag('after sending the field is empty and Send is disabled again'), p3.disabled === 'true' && !p3.active && (await page.evaluate(() => document.getElementById('composer-input').textContent)) === '', JSON.stringify(p3));
  await page.evaluate(() => document.getElementById('composer-input').blur());
  await sleep(300);
  check(tag('empty and unfocused, the composer folds back into one pill'), !(await pill()).expanded);
  // the microphone is one button: no caret, no list; pressing it says voice messages are coming soon
  const micInfo = await page.evaluate(() => ({ caret: !!document.querySelector('.lime-voice-split__caret, #voice-mode-toggle, #replies-voice-mode-toggle, #voice-mode-dropdown, #replies-voice-mode-dropdown'), mics: document.querySelectorAll('#composer .lime-voice-split__mic').length, r: document.querySelector('#composer .lime-voice-split__mic').getBoundingClientRect().toJSON() }));
  check(tag('the microphone is a single button: no caret and no device list anywhere, in a >= 40px target'), !micInfo.caret && micInfo.mics === 1 && micInfo.r.width >= 40 && micInfo.r.height >= 40, JSON.stringify(micInfo));
  await page.evaluate(() => { document.getElementById('toast-container').innerHTML = ''; });
  await page.click('#composer .lime-voice-split__mic');
  await wait(page, () => /Voice messages are coming soon/.test(document.getElementById('toast-container').textContent));
  check(tag('pressing the microphone says "Voice messages are coming soon"'), true);
  await page.evaluate(() => { document.getElementById('toast-container').innerHTML = ''; });
  // messages fade out under the composer (a mask on the thread), and not at the top (the glass bar blurs what passes under it)
  const fades = await page.evaluate(() => { const m = document.getElementById('thread-messages'); const cs = getComputedStyle(m); return { mask: cs.webkitMaskImage || cs.maskImage, top: m.getBoundingClientRect().top, padTop: parseFloat(cs.paddingTop) }; });
  check(tag('the thread fades out under the composer: a mask that goes from opaque to transparent near the bottom'), /linear-gradient\(/.test(fades.mask) && /rgb\(0, 0, 0\) calc\(100% - \d+px\), rgba\(0, 0, 0, 0\) calc\(100% - \d+px\)/.test(fades.mask), fades.mask);
  if (size.emulate) {
    // by touch, in Chrome's mobile emulation: a real finger press and hold opens the same menu
    await page.evaluate(() => { document.getElementById('toast-container').innerHTML = ''; const t = document.getElementById('thread-messages'); t.scrollTop = t.scrollHeight; });
    await sleep(250);
    const pt = await page.evaluate(() => { const el = [...document.querySelectorAll('#thread-messages .lime-message--received .lime-message__content')].slice(-1)[0]; const r = el.getBoundingClientRect(); return { x: r.left + 30, y: r.top + r.height / 2 }; });
    await page.touchscreen.touchStart(pt.x, pt.y); await sleep(560);
    const openedByTouch = await page.evaluate(() => !!document.querySelector('.m-msg-menu.is-open'));
    await page.touchscreen.touchEnd();
    await sleep(150);
    check(tag('a finger press and hold (touch) opens the hold menu, and lifting the finger does not close it or click through'), openedByTouch && (await page.evaluate(() => !!document.querySelector('.m-msg-menu.is-open'))));
    await page.keyboard.press('Escape');
    await page.touchscreen.touchStart(pt.x, pt.y); await sleep(120); await page.touchscreen.touchEnd(); await sleep(450);
    check(tag('a quick tap on a bubble does not open it'), !(await page.evaluate(() => !!document.querySelector('.m-msg-menu.is-open'))));
    // a finger that moves (scrolling) cancels the hold
    await page.touchscreen.touchStart(pt.x, pt.y); await page.touchscreen.touchMove(pt.x, pt.y - 80); await sleep(520); await page.touchscreen.touchEnd();
    check(tag('moving the finger (scrolling) cancels the hold'), !(await page.evaluate(() => !!document.querySelector('.m-msg-menu.is-open'))));
  }
  await page.evaluate(() => document.getElementById('composer-input').blur());

  // brand tints: every default avatar uses one of four classes; measured contrast of the ink on each, both themes
  const tints = await page.evaluate(() => {
    const classes = new Set([...document.querySelectorAll('.lime-avatar')].flatMap((e) => [...e.classList].filter((c) => /^lime-avatar--p\d+$/.test(c))));
    const cv = document.createElement('canvas'); cv.width = cv.height = 1; const cx = cv.getContext('2d', { willReadFrequently: true });
    const px = (css) => { cx.clearRect(0, 0, 1, 1); cx.fillStyle = '#000'; cx.fillStyle = css; cx.fillRect(0, 0, 1, 1); return [...cx.getImageData(0, 0, 1, 1).data].slice(0, 3); };
    const lum = (c) => { const f = (v) => { v /= 255; return v <= 0.03928 ? v / 12.92 : Math.pow((v + 0.055) / 1.055, 2.4); }; return 0.2126 * f(c[0]) + 0.7152 * f(c[1]) + 0.0722 * f(c[2]); };
    const out = {};
    for (const theme of ['light', 'dark']) {
      const wrap = document.createElement('div'); wrap.setAttribute('data-theme', theme); document.body.appendChild(wrap);
      out[theme] = [0, 1, 2, 3, 4, 5, 6, 7].map((n) => { const el = document.createElement('span'); el.className = 'seed-avatar lime-avatar lime-avatar--p' + n; wrap.appendChild(el); const cs = getComputedStyle(el); const bg = px(cs.backgroundColor), fg = px(cs.color); const a = lum(bg), b = lum(fg); return { bg: '#' + bg.map((v) => v.toString(16).padStart(2, '0')).join(''), ratio: Math.round((Math.max(a, b) + 0.05) / (Math.min(a, b) + 0.05) * 100) / 100 }; });
      wrap.remove();
    }
    return { classes: [...classes].sort(), out };
  });
  check(tag('default avatars use only the eight brand tints (p0 to p7)'), tints.classes.length > 0 && tints.classes.every((c) => /^lime-avatar--p[0-7]$/.test(c)), tints.classes.join());
  check(tag('ink initials clear 4.5:1 on every tint (light: ' + tints.out.light.map((t) => t.bg + ' ' + t.ratio).join(', ') + '; dark: ' + tints.out.dark.map((t) => t.bg + ' ' + t.ratio).join(', ') + ')'), [...tints.out.light, ...tints.out.dark].every((t) => t.ratio >= 4.5), '');

  // ── the pinned chat's menu still works from the phone's "..." ──
  await page.evaluate((id) => document.querySelector('#m-list [data-conversation-id="' + id + '"]').click(), S.zed);
  await wait(page, () => document.getElementById('layout').dataset.mobileView === 'thread');
  await page.click('#m-chat-more');
  await wait(page, () => document.getElementById('conversation-menu').classList.contains('is-open') && document.querySelectorAll('#conversation-menu [data-action]').length >= 4);
  await sleep(350); // it opens with a short scale-up; measure once it has settled
  const menu = await page.evaluate(() => { const m = document.getElementById('conversation-menu'); const r = m.getBoundingClientRect(); const cs = getComputedStyle(m); const item = m.querySelector('[data-action]'); return { left: r.left, right: r.right, top: r.top, bottom: r.bottom, width: r.width, height: r.height, w: window.innerWidth, h: window.innerHeight, blur: cs.backdropFilter || cs.webkitBackdropFilter, radius: parseFloat(cs.borderTopLeftRadius), rowH: item.getBoundingClientRect().height, rowFs: parseFloat(getComputedStyle(item).fontSize), kbd: getComputedStyle(m.querySelector('.lime-menu__kbd')).display, iconLeft: item.querySelector('.dew').getBoundingClientRect().left < item.querySelector('.lime-menu__item-label').getBoundingClientRect().left, topmost: document.elementFromPoint(r.left + r.width / 2, r.top + 20) === m || m.contains(document.elementFromPoint(r.left + r.width / 2, r.top + 20)) }; });
  check(tag('the "..." button opens the chat menu: really visible (a real box), inside the screen, and on top'), menu.width > 100 && menu.height > 100 && menu.left >= 0 && menu.right <= menu.w && menu.top >= 0 && menu.bottom <= menu.h && menu.topmost, JSON.stringify(menu));
  check(tag('the chat menu is the glass menu: blurred, a large radius, 44px rows of 17px text, icons at the left, no key hints'), /blur/.test(menu.blur || '') && menu.radius >= 20 && menu.rowH >= 44 && menu.rowFs === 17 && menu.iconLeft && menu.kbd === 'none', JSON.stringify(menu));
  await page.keyboard.press('Escape');
  check(tag('zero console or page errors'), errors.length === 0, errors.slice(0, 3).join(' | '));

  // ── LIME-79-fix3: a big group's header: at most two avatars plus "+N", the name cut short, all on one line ──
  if (name === 'Chrome' && size.width === 390) {
    const extra = []; for (const n of ['Pia Park', 'Quin Quade', 'Rae Ross', 'Sol Soto', 'Tam Tran', 'Uma Ueda', 'Val Vega', 'Wes Wu']) extra.push(await server.signUp(n));
    const cid = crypto.randomUUID();
    await server.api('POST', '/ops', { token: S.oli.token, body: { device_id: S.oli.device, ops: [['conversation.create', { conversation_id: cid, type: 'group', name: 'Whole school staff and the extended planning committee', member_ids: [S.mia.userId, S.ned.userId, ...extra.map((u) => u.userId)] }], ['message.send', { message_id: crypto.randomUUID(), conversation_id: cid, content: 'Welcome all' }]].map(([type, payload]) => ({ op_id: crypto.randomUUID(), type, actor_id: S.oli.userId, device_id: S.oli.device, client_ts: new Date().toISOString(), payload })) } });
    const big = await openPhone(browser, server, S.mia, tag('big group'), errors, size);
    await wait(big, (id) => !!document.querySelector('#m-list [data-conversation-id="' + id + '"]'), cid);
    await big.evaluate((id) => document.querySelector('#m-list [data-conversation-id="' + id + '"]').click(), cid);
    await wait(big, () => document.getElementById('layout').dataset.mobileView === 'thread' && document.getElementById('m-chat-title-text').textContent.length > 5);
    await sleep(300);
    const hdr = await big.evaluate(() => {
      const R = (e) => e.getBoundingClientRect(); const bar = R(document.getElementById('m-chatbar'));
      const tiles = [...document.querySelectorAll('#m-chat-avatars .lime-avatar-cluster__member')]; const more = tiles.find((t) => t.classList.contains('lime-avatar-cluster__more'));
      const t = document.getElementById('m-chat-title-text'); const tools = R(document.querySelector('.m-chatbar__tools')); const center = R(document.getElementById('m-chat-center')); const sub = document.getElementById('m-chat-sub');
      return { faces: tiles.length - 1, more: more && more.textContent, members: LimeStore.getMembers(document.querySelector('.lime-contact--active').dataset.conversationId).length, sub: sub.textContent, oneLine: R(t).height < 24 && R(sub).height < 24, truncated: t.scrollWidth > t.clientWidth, within: center.bottom <= bar.bottom && tools.bottom <= bar.bottom && center.right <= tools.left + 1, doc: document.documentElement.scrollWidth, vw: innerWidth };
    });
    check(tag('a big group\'s header (design 02): the list\'s avatar stack with "' + hdr.more + '", the long name cut with an ellipsis, "' + hdr.sub + '" under it, all beside the icon pill, nothing overflowing'), hdr.faces === 3 && hdr.more === '+' + (hdr.members - 1 - 3) && hdr.sub === hdr.members + ' members' && hdr.oneLine && hdr.truncated && hdr.within && hdr.doc <= hdr.vw, JSON.stringify(hdr));
    const stroke = await big.evaluate(() => ['#m-chat-search', '#m-chat-call', '#m-chat-more'].map((id) => { const m = getComputedStyle(document.querySelector(id + ' .m-icon')); const u = decodeURIComponent((m.webkitMaskImage || m.maskImage)); return /stroke-width='1\.7'/.test(u); }));
    check(tag('the three header icons are drawn in one set with the same 1.7 stroke'), stroke.every(Boolean), JSON.stringify(stroke));
    const addColor = await big.evaluate(() => { const b = document.querySelector('.lime-react-add'); const t = document.createElement('i'); t.style.color = 'var(--soil-text-muted)'; document.body.appendChild(t); const c = getComputedStyle(t).color; t.remove(); return { btn: getComputedStyle(b).color, token: c, op: parseFloat(getComputedStyle(b).opacity) }; });
    check(tag('the add-reaction icon is the muted secondary text colour'), addColor.btn === addColor.token && addColor.op < 1, JSON.stringify(addColor));
    await big.close();
  }

  // ── LIME-79-fix: live presence with two clients (Chrome 390 only): Ned signs in and out; Mia's list, chat header and Members follow ──
  if (name === 'Chrome' && size.width === 390) {
    const mia = await openPhone(browser, server, S.mia, tag('presence: Mia'), errors, Object.assign({}, size, { hash: '#c=' + S.dm }));
    await wait(mia, () => document.getElementById('layout').dataset.mobileView === 'thread');
    const seen = () => mia.evaluate((id) => {
      const row = document.querySelector('#m-list [data-conversation-id="' + id + '"] .lime-presence');
      const dot = document.getElementById('m-chat-sub');
      const msg = [...document.querySelectorAll('#thread-messages .lime-message--received .lime-presence')][0];
      const mem = [...document.querySelectorAll('.lime-members-panel__row')].find((r) => /Ned/.test(r.textContent));
      return { row: row && row.dataset.presence, header: dot && dot.dataset.presence, message: msg && msg.dataset.presence, members: mem ? mem.querySelector('.lime-members-panel__row-role').textContent : null, status: LimeStore.getMembers(id).find((p) => /Ned/.test(p.display_name)).status };
    }, S.dm);
    const until = async (fn, ms = 8000) => { const t0 = Date.now(); while (Date.now() - t0 < ms) { if (await fn()) return Date.now() - t0; await sleep(40); } return null; };
    const before = await seen();
    check(tag('presence: with Ned not connected, his status shows as away in the list, the chat header and his message avatars'), before.row === 'away' && before.header === 'away' && before.message === 'away' && before.status === 'offline', JSON.stringify(before));
    const tStart = Date.now();
    const ned = await openPhone(browser, server, S.ned, tag('presence: Ned'), errors, size);
    const tIn = (Date.now() - tStart) + await until(async () => (await seen()).row === 'active' && (await seen()).header === 'active' && (await seen()).message === 'active');
    check(tag('presence: when Ned signs in, Mia\'s list, chat header and message avatar turn active within a few seconds of Ned opening the app, page load included (' + tIn + ' ms)'), tIn !== null && tIn < 5000, JSON.stringify(await seen()));
    await mia.bringToFront(); // Ned's tab came to the front; a click in a background tab never lands
    await mia.click('#m-chat-center');
    await wait(mia, () => document.getElementById('right-panel').dataset.panel === 'members');
    const tMem = await until(async () => /Active/.test((await seen()).members || ''));
    check(tag('presence: Members shows Ned as Active (' + tMem + ' ms)'), tMem !== null, JSON.stringify(await seen()));
    const dmRows = await mia.evaluate(() => [...document.querySelectorAll('.lime-members-panel__row-name')].map((e) => e.textContent));
    check(tag('Members in a DM shows both people: ' + dmRows.join(' and ')), dmRows.length === 2 && dmRows.includes('Ned Nguyen') && dmRows.includes('Mia Moreno'), JSON.stringify(dmRows));
    await ned.close();
    const tOut = await until(async () => { const v = await seen(); return v.row === 'away' && v.header === 'away' && v.message === 'away' && /Away/.test(v.members || ''); });
    check(tag('presence: when Ned closes the app, everything turns to away within a few seconds, with Members open (' + tOut + ' ms)'), tOut !== null && tOut < 5000, JSON.stringify(await seen()));
    await mia.close();
  }
  await page.close();
}

// A phone turned sideways (844x390, a touch screen) keeps the phone layout; a tablet (touch, but 1024x768) and a desktop do not.
async function landscape(check, browser, server, S) {
  const errors = [];
  const page = await openPhone(browser, server, S.mia, 'landscape', errors, { width: 844, height: 390, emulate: true });
  const tag = (t) => `Chrome landscape 844x390: ${t}`;
  const vis = (sel) => visible(page, sel);
  check(tag('the phone layout shows (dock, Messages header; no drawer, tabs or breadcrumb row)'), (await vis('#m-dock')) && (await vis('#m-logo-btn')) && !(await vis('.seed-layout__left')) && !(await vis('#scope-tablist')) && !(await vis('.lime-center-top')));
  const geo = await page.evaluate(() => { const l = document.getElementById('list-col').getBoundingClientRect(); const d = document.getElementById('m-dock').getBoundingClientRect(); return { listW: l.width, vw: innerWidth, dockL: d.left, dockR: d.right, dockB: d.bottom, vh: innerHeight, doc: document.documentElement.scrollWidth }; });
  check(tag('the list is full width, the dock is inside the screen, nothing scrolls sideways'), geo.listW >= geo.vw - 1 && geo.dockL >= 8 && geo.dockR <= geo.vw - 8 && geo.dockB <= geo.vh && geo.doc <= geo.vw, JSON.stringify(geo));
  await page.click(`#m-list [data-conversation-id="${S.dm}"]`); // the first row; lower ones sit under the dock until the list is scrolled
  await wait(page, () => document.getElementById('layout').dataset.mobileView === 'thread');
  await sleep(400);
  const chat = await page.evaluate(() => { const b = document.getElementById('m-chatbar').getBoundingClientRect(); const t = document.getElementById('thread-messages').getBoundingClientRect(); const c = document.getElementById('composer').getBoundingClientRect(); return { barW: b.width, vw: innerWidth, threadW: t.width, composerR: c.right, composerB: c.bottom, vh: innerHeight, doc: document.documentElement.scrollWidth }; });
  check(tag('the chat is full width with its bar and composer inside the screen'), (await vis('#m-chatbar')) && !(await vis('#m-dock')) && chat.barW >= chat.vw - 1 && chat.threadW >= chat.vw - 1 && chat.composerR <= chat.vw && chat.composerB <= chat.vh && chat.doc <= chat.vw, JSON.stringify(chat));
  await page.screenshot({ path: process.env.LIME_SHOTS ? process.env.LIME_SHOTS + 'landscape-chat.png' : '/dev/null' });
  check(tag('zero console or page errors'), errors.length === 0, errors.slice(0, 2).join(' | '));
  await page.close();
  // a tablet (touch, but tall) is not a phone
  const tab = await browser.newPage();
  await tab.setViewport({ width: 1024, height: 768, deviceScaleFactor: 1, isMobile: true, hasTouch: true });
  await tab.evaluateOnNewDocument((p) => {
    sessionStorage.setItem('lime-api-session', JSON.stringify({ userId: p.userId, email: p.email, access_token: p.token, refresh_token: p.refresh, expires_at: Date.now() + 14 * 60 * 1000 }));
    sessionStorage.setItem('lime-demo-session', JSON.stringify({ userId: p.userId, email: p.email }));
    try { localStorage.setItem('lime-device-id', p.device); } catch (e) { /* none */ }
  }, S.mia);
  await tab.goto(server.base + 'index.html', { waitUntil: 'load' });
  await wait(tab, () => window.LimeStore && LimeStore.getCurrentUserId() && document.querySelectorAll('.lime-contact').length > 0);
  await sleep(400);
  check('Chrome tablet 1024x768 (touch): still the desktop layout, no dock', !(await visible(tab, '#m-dock')) && (await visible(tab, '.seed-layout__left')));
  await tab.close();
}

export async function run({ check }) {
  if (!browserAvailable('firefox') || !browserAvailable('chrome')) { check('mobile (skipped: needs both Firefox and Chrome installed)', true, 'skipped'); return; }
  const server = await new DevServer().start();
  const chrome = await launch('chrome');
  const firefox = await launch('firefox');
  try {
    // Each run reads chats and sends messages, so each gets its own freshly built scenario (its own people).
    await runOne(check, chrome, 'Chrome', server, await buildScenario(server), { width: 390, height: 844, emulate: true });
    await runOne(check, chrome, 'Chrome', server, await buildScenario(server), { width: 360, height: 780, emulate: true });
    await runOne(check, firefox, 'Firefox', server, await buildScenario(server), { width: 390, height: 844, emulate: false });
    const S = await buildScenario(server); // for the desktop checks below
    await landscape(check, chrome, server, S);

    // Desktop (>= 768px) is untouched: none of the phone pieces show, and the desktop layout still does.
    const errors = [];
    for (const [browser, name] of [[chrome, 'Chrome'], [firefox, 'Firefox']]) {
      const page = await browser.newPage();
      watchErrors(page, 'desktop', errors);
      await page.setViewport({ width: 1024, height: 768 });
      await page.evaluateOnNewDocument((p) => {
        if (!sessionStorage.getItem('e2e-seeded')) {
          sessionStorage.setItem('e2e-seeded', '1');
          sessionStorage.setItem('lime-api-session', JSON.stringify({ userId: p.userId, email: p.email, access_token: p.token, refresh_token: p.refresh, expires_at: Date.now() + 14 * 60 * 1000 }));
          sessionStorage.setItem('lime-demo-session', JSON.stringify({ userId: p.userId, email: p.email }));
        }
        try { localStorage.setItem('lime-device-id', p.device); } catch (e) { /* none */ }
      }, S.mia);
      await page.goto(server.base + 'index.html', { waitUntil: 'load' });
      await wait(page, () => window.LimeStore && LimeStore.getCurrentUserId() && document.querySelectorAll('.lime-contact').length > 0);
      await sleep(400);
      const pieces = await Promise.all(['#m-dock', '#m-messages', '#m-chatbar', '#m-logo-btn', '#m-fab', '.lime-contact__badge:not(:empty)', '.lime-contact__pin', '.lime-contact__time--m'].map((s) => visible(page, s)));
      const deskPieces = await Promise.all(['.seed-layout__left', '.lime-center-top', '#scope-tablist', '.lime-recent'].map((s) => visible(page, s)));
      check(`${name} desktop 1024x768: none of the phone pieces (dock, Messages header, chat bar, row badge, pin, phone time) show`, pieces.every((v) => !v), JSON.stringify(pieces));
      check(`${name} desktop 1024x768: the sidebar, breadcrumb row, tabs and Recent row still show`, deskPieces.every(Boolean), JSON.stringify(deskPieces));
      check(`${name} desktop 1024x768: zero console or page errors`, errors.length === 0, errors.slice(0, 2).join(' | '));
      await page.close();
    }
  } finally {
    await Promise.allSettled([chrome.close(), firefox.close()]);
    await server.destroy();
  }
}
