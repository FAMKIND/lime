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
  await send(oli, [say(zed, 'Welcome to Zed')]);
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

const view = (page) => page.evaluate(() => document.getElementById('layout').dataset.mobileView);
const visible = (page, sel) => page.evaluate((s) => { const el = document.querySelector(s); if (!el) return false; const cs = getComputedStyle(el); const r = el.getBoundingClientRect(); return cs.display !== 'none' && cs.visibility !== 'hidden' && r.width > 0 && r.height > 0; }, sel);
const titles = (page) => page.evaluate(() => [...document.querySelectorAll('#m-list .lime-contact')].map((li) => li.querySelector('.lime-contact__name').textContent));

async function runOne(check, browser, name, server, S, size) {
  const tag = (s) => `${name} ${size.width}x${size.height}: ${s}`;
  const errors = [];
  const page = await openPhone(browser, server, S.mia, tag('page'), errors, size);
  await checkOrigin(page, (n, c, d) => check(tag(n), c, d), 'phone');

  // ── what a phone no longer shows, and what it does ──
  const gone = await Promise.all(['.seed-layout__left', '.lime-mobile-nav-toggle', '.lime-center-top', '#scope-tablist', '.lime-recent', '.lime-section', '#notif-btn'].map((s) => visible(page, s)));
  check(tag('no drawer, hamburger, breadcrumb row, tabs, Recent row, sections or bell'), gone.every((v) => !v), JSON.stringify(gone));
  check(tag('the dock and the Messages header are showing; the chat bar is not'), (await visible(page, '#m-dock')) && (await visible(page, '#m-messages .m-messages__title')) && !(await visible(page, '#m-chatbar')));
  const dock = await page.evaluate(() => ({ labels: [...document.querySelectorAll('#m-dock .m-dock__label')].map((e) => e.textContent), rect: document.getElementById('m-dock').getBoundingClientRect().toJSON(), vh: window.innerHeight, vw: window.innerWidth, pos: getComputedStyle(document.getElementById('m-dock')).position }));
  check(tag('the dock is floating, inside the screen, with the four lowercase labels link, jam, calls, account'), dock.pos === 'fixed' && dock.labels.join() === 'link,jam,calls,account' && dock.rect.left >= 8 && dock.rect.right <= dock.vw - 8 && dock.rect.bottom <= dock.vh - 8, JSON.stringify(dock.labels));

  // ── the one list: pinned first, then by recency; unread counts; lowercase time ──
  check(tag('one list: the pinned chat first, then the others by recency (archived left out)'), (await titles(page)).join() === 'Ned Nguyen,Zed Team,Planning', (await titles(page)).join());
  const rows = await page.evaluate(() => [...document.querySelectorAll('#m-list .lime-contact')].map((li) => ({ name: li.querySelector('.lime-contact__name').textContent, badge: li.querySelector('.lime-contact__badge').textContent, pinned: li.classList.contains('lime-contact--pinned'), pinShown: getComputedStyle(li.querySelector('.lime-contact__pin')).display !== 'none', time: li.querySelector('.lime-contact__time--m').textContent, timeShown: getComputedStyle(li.querySelector('.lime-contact__time--m')).display !== 'none', deskTime: getComputedStyle(li.querySelector('.lime-contact__time:not(.lime-contact__time--m)')).display })));
  check(tag('each row shows its unread count (2, 1, 3), and only the pinned one shows the pin icon'), rows.map((r) => r.badge).join() === '2,1,3' && rows.map((r) => r.pinShown).join() === 'true,false,false', JSON.stringify(rows.map((r) => [r.name, r.badge, r.pinShown])));
  check(tag('times are lowercase ("h:mm am/pm") and only the phone time shows'), rows.every((r) => /^\d{1,2}:\d{2} (am|pm)$/.test(r.time) && r.timeShown && r.deskTime === 'none'), rows[0].time);
  check(tag('the dock badge shows the total unread (6), not counting the archived chat'), (await page.evaluate(() => document.getElementById('m-dock-badge').textContent)) === '6');

  // ── search and filter ──
  await page.click('#m-search-input');
  await page.keyboard.type('planning');
  await sleep(250);
  check(tag('search narrows the list as you type'), (await titles(page)).join() === 'Planning');
  await page.keyboard.type('zzz');
  await sleep(250);
  check(tag('a search with no matches says so'), /No chats match/.test(await page.evaluate(() => document.getElementById('m-list').textContent)));
  await page.evaluate(() => { const i = document.getElementById('m-search-input'); i.value = ''; i.dispatchEvent(new Event('input', { bubbles: true })); });
  const filter = async (f) => { await page.click('#m-filter-btn'); await sleep(150); await page.click(`#m-filter-menu [data-filter="${f}"]`); await sleep(250); return (await titles(page)).join(); };
  check(tag('filter Unread / Pinned / Groups / Archived show the right chats'), [await filter('unread'), await filter('pinned'), await filter('groups'), await filter('archived')].join(' | ') === 'Ned Nguyen,Zed Team,Planning | Ned Nguyen | Zed Team,Planning | Old news');
  check(tag('the filter button shows when a filter is on, and All brings everything back'), (await page.evaluate(() => document.getElementById('m-filter-btn').classList.contains('is-filtering'))) && (await filter('all')) === 'Ned Nguyen,Zed Team,Planning');

  // ── no sideways scroll, nothing wider than the screen ──
  const over = await page.evaluate(() => ({ doc: document.documentElement.scrollWidth, w: window.innerWidth, wide: [...document.querySelectorAll('#m-messages *')].filter((e) => e.getBoundingClientRect().right > window.innerWidth + 0.5).length }));
  check(tag('the Messages screen does not scroll sideways and nothing is wider than the screen'), over.doc <= over.w && over.wide === 0, JSON.stringify(over));

  // ── stacked navigation ──
  const startHistory = await page.evaluate(() => history.length);
  await page.click(`#m-list [data-conversation-id="${S.planning}"]`);
  await wait(page, () => document.getElementById('layout').dataset.mobileView === 'thread');
  check(tag('tapping a chat pushes the chat screen: the chat bar shows, the dock is gone'), (await visible(page, '#m-chatbar')) && !(await visible(page, '#m-dock')) && (await page.evaluate(() => document.getElementById('m-chat-title-text').textContent)) === 'Planning');
  check(tag('the back arrow carries the count of OTHER chats\' unread messages (2 + 1 = 3; Planning is open and now read)'), (await page.evaluate(() => document.getElementById('m-chat-back-count').textContent)) === '3');
  check(tag('the address has #c= for the open chat, and the history grew by one'), (await page.evaluate(() => location.hash)) === '#c=' + S.planning && (await page.evaluate(() => history.length)) === startHistory + 1);
  const barOver = await page.evaluate(() => ({ doc: document.documentElement.scrollWidth, w: window.innerWidth, bar: [...document.querySelectorAll('#m-chatbar > *')].filter((e) => e.getBoundingClientRect().right > window.innerWidth + 0.5 || e.getBoundingClientRect().left < -0.5).length }));
  check(tag('the chat top bar fits the screen'), barOver.doc <= barOver.w && barOver.bar === 0, JSON.stringify(barOver));

  await page.click('#m-chat-avatars');
  await wait(page, () => document.getElementById('layout').dataset.mobileView === 'panel');
  check(tag('the avatars open the details/members as a pushed screen'), (await view(page)) === 'panel' && (await visible(page, '#right-panel')));
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
  await page.evaluate((pid) => document.querySelector('#thread-messages [data-message-id="' + pid + '"] .lime-message__replies').click(), parentId);
  await wait(page, () => document.getElementById('layout').dataset.mobileView === 'panel');
  check(tag('a thread opens as its own pushed screen with the back arrow'), (await visible(page, '#right-panel-toggle .m-back-icon')) && !(await visible(page, '#right-panel-toggle .dew-sidebar-right-closed')));
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
  await page.click('#m-dock-account');
  await wait(page, () => document.getElementById('settings-modal').classList.contains('is-open') && document.getElementById('settings-modal').classList.contains('is-showing-section'));
  check(tag('account opens Settings on the Profile section, full screen'), (await page.evaluate(() => { const r = document.getElementById('settings-modal').getBoundingClientRect(); return !!document.getElementById('settings-profile-form') && r.width >= window.innerWidth - 1 && r.height >= window.innerHeight - 1; })));
  await page.click('#settings-modal-close');
  await sleep(400);
  // A fresh account's empty timezone makes the Profile form count as "edited" (the select shows a default), so Settings may ask
  // "Discard changes?" first. That is existing behaviour; take the Discard.
  if (await visible(page, '#confirm-dialog.is-open, #confirm-dialog[open], .lime-confirm-dialog.is-open')) await page.click('#confirm-dialog-confirm');
  await wait(page, () => !document.getElementById('settings-modal').classList.contains('is-open'));

  // ── a deep link opens that chat, and back goes to the list ──
  const deep = await openPhone(browser, server, S.mia, tag('deep link'), errors, Object.assign({}, size, { hash: '#c=' + S.zed }));
  await wait(deep, () => document.getElementById('layout').dataset.mobileView === 'thread');
  check(tag('a #c= link opens that chat on a phone'), (await deep.evaluate(() => document.getElementById('m-chat-title-text').textContent)) === 'Zed Team');
  await deep.goBack();
  await wait(deep, () => document.getElementById('layout').dataset.mobileView === 'contacts');
  check(tag('and back from it lands on the Messages list'), (await visible(deep, '#m-dock')));
  await deep.close();

  // ── the pinned chat's menu still works from the phone's "..." ──
  await page.evaluate((id) => document.querySelector('#m-list [data-conversation-id="' + id + '"]').click(), S.zed);
  await wait(page, () => document.getElementById('layout').dataset.mobileView === 'thread');
  await page.click('#m-chat-more');
  await wait(page, () => document.getElementById('conversation-menu').classList.contains('is-open') && document.querySelectorAll('#conversation-menu [data-action]').length >= 4);
  const menu = await page.evaluate(() => { const r = document.getElementById('conversation-menu').getBoundingClientRect(); return { left: r.left, right: r.right, top: r.top, bottom: r.bottom, w: window.innerWidth, h: window.innerHeight }; });
  check(tag('the "..." button opens the chat menu, inside the screen'), menu.left >= 0 && menu.right <= menu.w && menu.top >= 0 && menu.bottom <= menu.h, JSON.stringify(menu));
  await page.keyboard.press('Escape');
  check(tag('zero console or page errors'), errors.length === 0, errors.slice(0, 3).join(' | '));
  await page.close();
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
      const pieces = await Promise.all(['#m-dock', '#m-messages', '#m-chatbar', '.m-messages__title', '.lime-contact__badge:not(:empty)', '.lime-contact__pin', '.lime-contact__time--m'].map((s) => visible(page, s)));
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
