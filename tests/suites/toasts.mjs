// Toasts (LIME-67/68): queue across navigation, at most 3 visible, an error stays, an action works.
import { launch, browserAvailable, watchErrors, sleep, wipeStorage, isDevServer, checkOrigin } from '../lib/harness.mjs';
import { Remote, openAs } from '../lib/dev.mjs';

const visible = (page) => page.evaluate(() => [...document.querySelectorAll('.lime-toast:not(.seed-toast--exiting)')].map((t) => t.querySelector('.seed-toast__title').textContent));

export async function run({ base, check }) {
  const name = browserAvailable('chrome') ? 'chrome' : 'firefox';
  const browser = await launch(name);
  const errors = [];
  try {
    await wipeStorage(browser, base);
    let page;
    if (await isDevServer(base)) {
      // On the dev server the app runs on the API: a fresh account, with one chat to open (a DM with a seed teacher).
      const remote = new Remote(base);
      page = await openAs(browser, remote, await remote.signUp('Toast Tester'), 'toasts', errors);
      await page.evaluate(() => LimeStore.createConversation({ type: 'direct', memberIds: ['teacher-001'] }));
      await page.waitForFunction(() => LimeStore.listConversations().length > 0 && document.querySelector('[data-conversation-id]'), { polling: 20, timeout: 10000 });
    } else {
      page = await browser.newPage();
      watchErrors(page, 'toasts', errors);
      await page.evaluateOnNewDocument(() => { if (!sessionStorage.getItem('lime-demo-session')) sessionStorage.setItem('lime-demo-session', JSON.stringify({ userId: 'teacher-002', email: 'shem@famkind.com' })); });
      await page.goto(base + 'index.html', { waitUntil: 'load' });
      await page.waitForFunction(() => window.LimeToast && window.LimeStore && LimeStore.getCurrentUserId(), { polling: 10, timeout: 10000 });
    }

    await checkOrigin(page, check, 'toasts');

    // Queue across navigation: queued here, shown after the next page load, shown once.
    await page.evaluate(() => LimeToast.queue({ title: 'Queued across pages', tone: 'info' }));
    await page.goto(base + 'index.html', { waitUntil: 'load' });
    await sleep(500);
    check('a queued toast shows after navigation', (await visible(page)).includes('Queued across pages'), JSON.stringify(await visible(page)));
    await page.reload({ waitUntil: 'load' });
    await sleep(400);
    check('and only once (the queue is cleared)', !(await visible(page)).includes('Queued across pages'));

    // Max 3 visible; the oldest leave first.
    await page.evaluate(() => { document.querySelectorAll('.lime-toast').forEach((t) => t.remove()); for (let i = 1; i <= 5; i++) LimeToast.show({ title: 'T' + i, tone: 'info', duration: 0 }); });
    await sleep(500);
    const five = await visible(page);
    check('at most 3 toasts are visible; the newest three stay', five.length === 3 && five.includes('T5') && five.includes('T4') && five.includes('T3'), JSON.stringify(five));

    // An error stays (no auto-dismiss) while an info toast leaves.
    await page.evaluate(() => { document.querySelectorAll('.lime-toast').forEach((t) => t.remove()); LimeToast.show({ title: 'Boom', tone: 'error' }); LimeToast.show({ title: 'Quick', tone: 'info', duration: 300 }); });
    await sleep(900);
    const after = await visible(page);
    check('an error toast stays while a short info toast leaves', after.includes('Boom') && !after.includes('Quick'), JSON.stringify(after));
    await page.click('.lime-toast .seed-toast__dismiss');
    await sleep(400);
    check('dismiss removes it', !(await visible(page)).includes('Boom'));

    // Action button runs and dismisses.
    await page.evaluate(() => { window.__acted = false; LimeToast.show({ title: 'With action', tone: 'success', action: { label: 'Undo', onClick: () => { window.__acted = true; } } }); });
    await page.click('.lime-toast__action');
    await sleep(400);
    check('an action runs its handler and dismisses the toast', (await page.evaluate(() => window.__acted)) && !(await visible(page)).includes('With action'));

    // A real status toast: starring a chat.
    await page.evaluate(() => { document.querySelectorAll('.lime-toast').forEach((t) => t.remove()); });
    const id = await page.evaluate(() => LimeStore.listConversations()[0].id);
    await page.evaluate((cid) => document.querySelector('[data-conversation-id="' + cid + '"]').click(), id);
    await sleep(300);
    check('sending a message does not toast (LIME-68 rule)', await (async () => {
      await page.click('#composer-input'); await page.keyboard.type('hello'); await page.click('#composer-send'); await sleep(500);
      return (await visible(page)).length === 0;
    })());
    check('zero console or page errors', errors.length === 0, errors.join(' | '));
  } finally {
    await browser.close();
  }
}
