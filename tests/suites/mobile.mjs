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
  check(tag('each row shows its unread count (2, 3, 3), and only the pinned one shows the pin icon'), rows.map((r) => r.badge).join() === '2,3,3' && rows.map((r) => r.pinShown).join() === 'true,false,false', JSON.stringify(rows.map((r) => [r.name, r.badge, r.pinShown])));
  check(tag('times are lowercase ("h:mm am/pm") and only the phone time shows'), rows.every((r) => /^\d{1,2}:\d{2} (am|pm)$/.test(r.time) && r.timeShown && r.deskTime === 'none'), rows[0].time);
  check(tag('the dock badge shows the total unread (8), not counting the archived chat'), (await page.evaluate(() => document.getElementById('m-dock-badge').textContent)) === '8');

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
  check(tag('the back arrow carries the count of OTHER chats\' unread messages (2 + 3 = 5; Planning is open and now read)'), (await page.evaluate(() => document.getElementById('m-chat-back-count').textContent)) === '5');
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
  await page.evaluate(() => [...document.querySelectorAll('#thread-messages .lime-message--received .lime-react-add')][0].click());
  await wait(page, () => !!document.querySelector('.lime-reaction-picker.is-open'));
  await page.evaluate(() => document.querySelector('.lime-reaction-picker.is-open [data-emoji="\u2764\ufe0f"]').click());
  await wait(page, () => { const m = document.querySelector('#thread-messages .lime-message--received'); return m.querySelector('.lime-message__reactions').textContent.includes('\u2764'); });
  check(tag('the add-reaction button opens the picker and the chosen emoji appears as a chip'), true);
  await page.evaluate(() => [...document.querySelectorAll('#thread-messages .lime-message--received .lime-reply-add')][1].click());
  await wait(page, () => document.getElementById('layout').dataset.mobileView === 'panel' && document.getElementById('right-panel').dataset.panel === 'replies');
  check(tag('the reply button under a bubble opens the thread screen'), true);
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
  await page.keyboard.type('Hello from the phone');
  const p2 = await pill();
  check(tag('typing wakes Send up (pale lime, enabled)'), p2.active && p2.disabled === 'false', JSON.stringify(p2));
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
      out[theme] = [0, 1, 2, 3].map((n) => { const el = document.createElement('span'); el.className = 'seed-avatar lime-avatar lime-avatar--p' + n; wrap.appendChild(el); const cs = getComputedStyle(el); const bg = px(cs.backgroundColor), fg = px(cs.color); const a = lum(bg), b = lum(fg); return { bg: '#' + bg.map((v) => v.toString(16).padStart(2, '0')).join(''), ratio: Math.round((Math.max(a, b) + 0.05) / (Math.min(a, b) + 0.05) * 100) / 100 }; });
      wrap.remove();
    }
    return { classes: [...classes].sort(), out };
  });
  check(tag('default avatars use only the four brand tints (p0 to p3)'), tints.classes.length > 0 && tints.classes.every((c) => /^lime-avatar--p[0-3]$/.test(c)), tints.classes.join());
  check(tag('ink initials clear 4.5:1 on every tint (light: ' + tints.out.light.map((t) => t.bg + ' ' + t.ratio).join(', ') + '; dark: ' + tints.out.dark.map((t) => t.bg + ' ' + t.ratio).join(', ') + ')'), [...tints.out.light, ...tints.out.dark].every((t) => t.ratio >= 4.5), '');

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
