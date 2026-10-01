// Safari on this Mac (the same WebKit engine as iOS Safari) against the dev server, by the real pages: sign in through the
// sign-in page, send a DM, receive a DM live, and see a profile change arrive. Runs on the LAN address when
// LIME_TEST_ORIGIN=lan (an insecure context, like a phone). Skipped, with the exact fix, until Safari allows remote automation.
import { launch, browserAvailable, sleep, checkOrigin, insecureOrigin } from '../lib/harness.mjs';
import { DevServer, openAs } from '../lib/dev.mjs';
import { Safari } from '../lib/safari.mjs';

export async function run({ check }) {
  const safari = await Safari.start();
  if (safari.unavailable) {
    check('safari (skipped): Safari is not enabled for automation yet. Run `safaridriver --enable` once (it asks for your Mac password), then run this suite again', true, 'skipped: ' + safari.unavailable);
    return;
  }
  if (!browserAvailable('chrome')) { await safari.close(); check('safari (skipped: Chrome not installed, needed as the second person)', true, 'skipped'); return; }
  const server = await new DevServer().start();
  const errors = [];
  const chrome = await launch('chrome');
  try {
    const [sam, cy] = [await server.signUp('Safari Sam'), await server.signUp('Chrome Cy')];
    // 1. Sign in through the real sign-in page.
    await safari.go(server.base + 'auth.html');
    await safari.until('return document.getElementById("auth-email") && window.LimeStore');
    await safari.keys(await safari.find('#auth-email'), sam.email);
    await safari.click(await safari.find('#auth-email-form button[type=submit]'));
    await safari.until('var el=document.getElementById("auth-password"); return el && el.offsetParent !== null');
    await safari.keys(await safari.find('#auth-password'), sam.password);
    await safari.click(await safari.find('#auth-password-form button[type=submit]'));
    await safari.until('return /index\\.html/.test(location.pathname) && window.LimeStore && LimeStore.getCurrentUser()', [], 20000);
    check('Safari: signed in through the real sign-in page, as Safari Sam', (await safari.exec('return LimeStore.getCurrentUser().display_name')) === 'Safari Sam');
    const secure = await safari.exec('return window.isSecureContext');
    check('Safari: ' + (insecureOrigin() ? 'the page is NOT a secure context (like a phone on the LAN)' : 'the page is a secure context (localhost)'), secure === !insecureOrigin(), 'isSecureContext=' + secure);
    check('Safari: the app is on the API backend, with its own device id', await safari.exec('return LimeStore.isApi() && /^web-[0-9a-f-]{36}$/.test(localStorage.getItem("lime-device-id"))'));

    const C = await openAs(chrome, server, cy, 'Cy/chrome', errors);
    await checkOrigin(C, check, 'Chrome');
    // 2. Cy starts a DM with Sam: it appears in Safari live.
    const conv = await C.evaluate((id) => LimeStore.createConversation({ type: 'direct', memberIds: [id] }).then((c) => c.id), sam.userId);
    await safari.until('return !!document.querySelector(\'[data-conversation-id="\' + arguments[0] + \'"]\')', [conv]);
    check('Safari: a DM started by another person appears live in the list', true);
    // 3. Sam sends a DM from Safari by typing in the composer; Cy receives it live.
    await safari.exec('document.querySelector(\'[data-conversation-id="\' + arguments[0] + \'"]\').click();', [conv]);
    await sleep(400);
    await safari.keys(await safari.find('#composer-input'), 'hello from Safari');
    await safari.click(await safari.find('#composer-send'));
    await C.waitForFunction(() => document.getElementById('thread-messages') && document.getElementById('thread-messages').textContent.includes('hello from Safari') || LimeStore.listConversations().some((c) => LimeStore.listMessages(c.id).some((m) => (m.content || '').includes('hello from Safari'))), { polling: 20, timeout: 10000 });
    check('Safari: a DM typed and sent in Safari reaches the other person live', true);
    // 4. Cy sends a DM; Safari receives it live in the open thread.
    await C.evaluate((id) => LimeStore.sendMessage(id, { content: 'hello back from Chrome' }), conv);
    await safari.until('return document.getElementById("thread-messages").textContent.indexOf("hello back from Chrome") > -1', [], 10000);
    check('Safari: a DM from the other person appears live in the open thread', true);
    // 5. A profile change propagates into Safari.
    await C.evaluate(() => LimeStore.updateProfile({ display_name: 'Chrome Cy Renamed' }));
    await safari.until('var p = LimeStore.getProfile(arguments[0]); return p && p.display_name === "Chrome Cy Renamed"', [cy.userId], 10000);
    check('Safari: a profile (name) change by the other person arrives live', true);
    check('Chrome: zero console or page errors', errors.length === 0, errors.join(' | '));
  } finally {
    await safari.close();
    await chrome.close();
    await server.destroy();
  }
}
