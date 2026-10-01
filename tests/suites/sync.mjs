// Two tabs of one browser window, two people (LIME-69): a live message, then no lost writes (20 + 20).
import { launch, browserAvailable, openSignedIn, wipeStorage, sleep, isDevServer } from '../lib/harness.mjs';
import { Remote, openAs } from '../lib/dev.mjs';

async function suiteFor(name, { base, check }) {
  const browser = await launch(name);
  const errors = [];
  const tag = (s) => `${name}: ${s}`;
  try {
    await wipeStorage(browser, base);
    // Local-only backend: two tabs of one browser share localStorage (LIME-69). On the dev server the same checks run
    // against the API instead, with two freshly signed-up people.
    const dev = await isDevServer(base);
    const remote = new Remote(base);
    let A, B, personA, personB;
    if (dev) {
      personA = await remote.signUp('Sync Ada'); personB = await remote.signUp('Sync Bo');
      A = await openAs(browser, remote, personA, 'A', errors);
      B = await openAs(browser, remote, personB, 'B', errors);
      check(tag('two tabs are two different people'), (await A.evaluate(() => LimeStore.getCurrentUserId())) === personA.userId && (await B.evaluate(() => LimeStore.getCurrentUserId())) === personB.userId);
    } else {
      A = await openSignedIn(browser, base, 'teacher-002', 'shem.robinson@ps113.edu', 'A', errors);
      B = await openSignedIn(browser, base, 'teacher-001', 'jean@chungrajoon.com', 'B', errors);
      check(tag('two tabs are two different people'), (await A.evaluate(() => LimeStore.getCurrentUserId())) === 'teacher-002' && (await B.evaluate(() => LimeStore.getCurrentUserId())) === 'teacher-001');
      await A.bringToFront();
      await A.evaluate(() => LimeStore.setStarred(LimeStore.listConversations()[0].id, true)); // creates the first snapshot
      await sleep(500);
    }

    await A.bringToFront();
    const gid = await A.evaluate(async (other) => (await LimeStore.createConversation({ type: 'group', name: 'Sync test', memberIds: [other] })).id, dev ? personB.userId : 'teacher-001');
    await B.waitForFunction((id) => !!document.querySelector('[data-conversation-id="' + id + '"]'), { polling: 10, timeout: 5000 }, gid);
    check(tag('a new group made in A appears in B without a reload'), true);

    for (const pg of [A, B]) await pg.evaluate((id) => document.querySelector('[data-conversation-id="' + id + '"]').click(), gid);
    await sleep(400);
    await A.click('#composer-input');
    await A.keyboard.type('hello from A');
    await A.click('#composer-send');
    await B.waitForFunction(() => document.getElementById('thread-messages').textContent.includes('hello from A'), { polling: 10, timeout: 5000 });
    check(tag('a message sent in A shows live in B\'s open thread'), true);

    // 20 + 20, through the real composer, interleaved as fast as possible.
    const run = (page, t) => page.evaluate(async (prefix) => {
      const input = document.getElementById('composer-input');
      for (let i = 0; i < 20; i++) {
        input.textContent = prefix + i; input.dispatchEvent(new Event('input', { bubbles: true }));
        document.getElementById('composer-send').click();
        await new Promise((r) => setTimeout(r, Math.random() * 15));
      }
    }, t);
    await Promise.all([run(A, 'a-'), run(B, 'b-')]);
    await sleep(2000);
    const grab = (page) => page.evaluate((id) => LimeStore.listMessages(id).filter((m) => /^[ab]-\d+$/.test(m.content)).map((m) => m.content), gid);
    const [ca, cb] = [await grab(A), await grab(B)];
    const stored = dev
      ? (await remote.api('GET', '/snapshot', { token: personA.token })).body.messages.filter((m) => m.conversation_id === gid && /^[ab]-\d+$/.test(m.content)).length
      : await A.evaluate((id) => JSON.parse(localStorage.getItem('lime-state-v1')).messages.filter((m) => m.conversation_id === id && /^[ab]-\d+$/.test(m.content)).length, gid);
    check(tag('no lost writes: all 40 in tab A'), ca.length === 40, ca.length);
    check(tag('no lost writes: all 40 in tab B'), cb.length === 40, cb.length);
    check(tag(dev ? 'no lost writes: all 40 on the server' : 'no lost writes: all 40 in storage'), stored === 40, stored);
    check(tag('both tabs show the same order'), JSON.stringify(ca) === JSON.stringify(cb));
    check(tag('each person\'s messages stay in order'), ['a', 'b'].every((p) => ca.filter((x) => x[0] === p).join() === Array.from({ length: 20 }, (_, i) => p + '-' + i).join()));
    const dom = await B.evaluate((id) => ({ rows: document.querySelectorAll('#thread-messages .lime-message').length, store: LimeStore.listMessages(id, { threadOnly: true }).length }), gid);
    check(tag('B\'s screen shows every message in its store'), dom.rows === dom.store, JSON.stringify(dom));

    // Sign-out in one tab leaves the other signed in; a new tab starts signed out.
    await A.evaluate(() => LimeAuth.signOut());
    await sleep(800);
    check(tag('signing out in A does not sign out B'), /index\.html/.test(B.url()));
    const C = await browser.newPage();
    await C.goto(base + 'index.html', { waitUntil: 'load' });
    await sleep(800);
    check(tag('a brand-new tab starts signed out'), /auth\.html|login\.html/.test(C.url()), C.url());
    check(tag('zero console or page errors'), errors.length === 0, errors.join(' | '));
  } finally {
    await browser.close();
  }
}

export async function run(ctx) {
  // Firefox matters here (storage events, timers, IndexedDB differ); Chrome too.
  for (const name of ['firefox', 'chrome']) {
    if (browserAvailable(name)) await suiteFor(name, ctx);
    else ctx.check(`${name}: installed (skipped, not found)`, true, 'skipped');
  }
}
