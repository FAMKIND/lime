// Sign up, sign in, wrong password, the seed-teacher hint, sign out, through the real auth.html in the real browser.
import { launch, browserAvailable, watchErrors, sleep, wipeStorage } from '../lib/harness.mjs';

async function enterEmail(page, base, email) {
  await page.goto(base + 'auth.html', { waitUntil: 'load' });
  await page.type('#auth-email', email);
  await page.click('#auth-email-form button[type=submit]');
}

export async function run({ base, check }) {
  const name = browserAvailable('chrome') ? 'chrome' : 'firefox';
  const browser = await launch(name);
  const errors = [];
  try {
    await wipeStorage(browser, base);
    const page = await browser.newPage();
    watchErrors(page, 'auth', errors);

    // Sign up (new email -> create step)
    await enterEmail(page, base, 'ada@example.com');
    await page.waitForSelector('#auth-name', { visible: true });
    await page.type('#auth-name', 'Ada Lovelace');
    await page.type('#auth-create-password', 'password123');
    const terms = await page.$('#auth-terms');
    if (terms) await terms.click();
    const nav = page.waitForNavigation({ waitUntil: 'load' });
    await page.click('#auth-create-form button[type=submit]');
    await nav;
    await page.waitForFunction(() => window.LimeStore && LimeStore.getCurrentUser(), { polling: 10, timeout: 10000 });
    check('sign up lands in the app as the new person', (await page.evaluate(() => LimeStore.getCurrentUser().display_name)) === 'Ada Lovelace');
    check('sign up stored a credential, never the plain password', await page.evaluate(() => {
      const raw = localStorage.getItem('lime-auth-v1') || '';
      return raw.includes('ada@example.com') && !raw.includes('password123');
    }));
    check('the session is per tab (sessionStorage, not localStorage)', await page.evaluate(() => !!sessionStorage.getItem('lime-demo-session') && !localStorage.getItem('lime-demo-session')));

    // Sign out
    await page.evaluate(() => LimeAuth.signOut());
    await page.waitForFunction(() => /auth\.html|login\.html/.test(location.href), { polling: 10, timeout: 8000 });
    check('sign out returns to the auth page', /auth\.html/.test(page.url()));
    check('sign out clears this tab\'s session', await page.evaluate(() => !sessionStorage.getItem('lime-demo-session')));

    // A signed-out tab can't open the app
    await page.goto(base + 'index.html', { waitUntil: 'load' });
    await sleep(800);
    check('index.html redirects a signed-out tab to sign-in', /auth\.html|login\.html/.test(page.url()), page.url());

    // Sign in: wrong password, then right
    await enterEmail(page, base, 'ada@example.com');
    await page.waitForSelector('#auth-password', { visible: true });
    await page.type('#auth-password', 'not-the-password');
    await page.click('#auth-password-form button[type=submit]');
    await page.waitForFunction(() => (document.getElementById('auth-error') || {}).textContent.trim().length > 0, { polling: 10, timeout: 8000 });
    const wrong = await page.evaluate(() => document.getElementById('auth-error').textContent.trim());
    check('wrong password shows an error and stays on the page', /Incorrect/i.test(wrong) && /auth\.html/.test(page.url()), wrong);
    await page.evaluate(() => { document.getElementById('auth-password').value = ''; });
    await page.type('#auth-password', 'password123');
    const nav2 = page.waitForNavigation({ waitUntil: 'load' });
    await page.click('#auth-password-form button[type=submit]');
    await nav2;
    await page.waitForFunction(() => window.LimeStore && LimeStore.getCurrentUser(), { polling: 10, timeout: 10000 });
    check('sign in with the right password lands in the app', (await page.evaluate(() => LimeStore.getCurrentUser().email)) === 'ada@example.com');
    await page.evaluate(() => LimeAuth.signOut());
    await page.waitForFunction(() => /auth\.html|login\.html/.test(location.href), { polling: 10, timeout: 8000 });

    // Seed teacher with a wrong password: the demo-password hint (or, with no local demo config, the explanation)
    await enterEmail(page, base, 'jean@chungrajoon.com');
    await page.waitForSelector('#auth-password', { visible: true });
    await page.type('#auth-password', 'definitely-wrong-1');
    await page.click('#auth-password-form button[type=submit]');
    await page.waitForFunction(() => (document.getElementById('auth-error') || {}).textContent.trim().length > 0, { polling: 10, timeout: 8000 });
    const hint = await page.evaluate(() => document.getElementById('auth-error').textContent.trim());
    check('seed teacher + wrong password gives the demo-password hint', /shared demo password|Demo credentials aren.t configured/.test(hint), hint);

    // Duplicate email can't sign up
    await enterEmail(page, base, 'jean@chungrajoon.com');
    await sleep(400);
    check('an existing seed email goes to the password step, not sign-up', await page.evaluate(() => !!document.getElementById('auth-password') && document.getElementById('auth-password').offsetParent !== null));

    check('zero console or page errors', errors.length === 0, errors.join(' | '));
  } finally {
    await browser.close();
  }
}
