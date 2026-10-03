// Signing in on a phone with the keyboard open (LIME-79-fix5): the action button stays above the keyboard, and the keyboard's Return
// says and does the next thing. Runs on a throwaway dev server in Chrome with mobile emulation (390x844, 360x780, and 844x390 sideways)
// and, for the Return key behaviour, in the real Firefox. The on-screen keyboard is simulated by shrinking the viewport (what the page
// sees on Android and, through visualViewport, on iOS). Skipped (with a note) when Firefox or Chrome is missing.
import { launch, browserAvailable, sleep, watchErrors } from '../lib/harness.mjs';
import { DevServer } from '../lib/dev.mjs';

const wait = (page, fn, arg, ms = 10000) => page.waitForFunction(fn, { polling: 30, timeout: ms }, arg);
const mobile = (w, h) => ({ width: w, height: h, deviceScaleFactor: 2, isMobile: true, hasTouch: true });

async function openAuth(browser, server, label, errors, viewport) {
  const page = await browser.newPage();
  watchErrors(page, label, errors);
  await page.setViewport(viewport);
  await page.goto(server.base + 'auth.html', { waitUntil: 'load' });
  await wait(page, () => !!window.LimeStore && !!document.getElementById('auth-email'));
  await sleep(300);
  return page;
}
const visibleAboveKeyboard = (page, sel) => page.evaluate((s) => { const el = document.querySelector(s); const r = el.getBoundingClientRect(); const h = window.visualViewport ? window.visualViewport.height : innerHeight; return { top: Math.round(r.top), bottom: Math.round(r.bottom), h: Math.round(h), ok: r.top >= 0 && r.bottom <= h + 0.5 && r.width > 0 }; }, sel);
const stepOf = (page) => page.evaluate(() => [...document.querySelectorAll('.lime-auth__step')].find((e) => !e.hidden).dataset.step);

async function emailFlow(check, browser, server, tag, errors, viewport, keyboardViewport, account) {
  const page = await openAuth(browser, server, tag('page'), errors, viewport);
  const attrs = await page.evaluate(() => { const a = (id) => { const e = document.getElementById(id); return [e.getAttribute('enterkeyhint'), e.getAttribute('autocomplete'), e.type].join('/'); }; return { email: a('auth-email'), password: a('auth-password'), name: a('auth-name'), create: a('auth-create-password'), inputmode: document.getElementById('auth-email').getAttribute('inputmode') }; });
  check(tag('the fields say what Return does and what they are: email next/email, password go/current-password, name next/name, new password go/new-password'), attrs.email === 'next/email/email' && attrs.password === 'go/current-password/password' && attrs.name === 'next/name/text' && attrs.create === 'go/new-password/password' && attrs.inputmode === 'email', JSON.stringify(attrs));
  // the keyboard opens
  await page.click('#auth-email');
  await page.setViewport(keyboardViewport);
  await sleep(450);
  const kb = await page.evaluate(() => ({ cls: document.querySelector('.lime-auth').classList.contains('is-keyboard'), logo: getComputedStyle(document.querySelector('.lime-auth__form-logo')).display, headline: getComputedStyle(document.querySelector('.lime-auth__headline')).display, docScroll: document.documentElement.scrollHeight - innerHeight }));
  const cont = await visibleAboveKeyboard(page, '#auth-email-form button[type=submit]');
  check(tag('keyboard up on the email step: the compact layout shows (logo and headline step aside) and "Continue with email" is above the keyboard (' + cont.bottom + ' of ' + cont.h + 'px)'), kb.cls && kb.logo === 'none' && kb.headline === 'none' && cont.ok, JSON.stringify({ kb, cont }));
  // Return on the email field = Continue
  await page.keyboard.type(account.email);
  await page.keyboard.press('Enter');
  await wait(page, () => document.querySelector('.lime-auth__step[data-step="password"]') && !document.querySelector('.lime-auth__step[data-step="password"]').hidden);
  await sleep(350);
  const onPassword = await page.evaluate(() => ({ focused: document.activeElement && document.activeElement.id, username: document.getElementById('auth-password-username').value }));
  const signIn = await visibleAboveKeyboard(page, '#auth-password-form button[type=submit]');
  check(tag('Return on the email moves to the password step with the password focused, the saved-password pairing field holding the email, and "Sign in" still above the keyboard (' + signIn.bottom + ' of ' + signIn.h + 'px)'), onPassword.focused === 'auth-password' && onPassword.username === account.email && signIn.ok, JSON.stringify({ onPassword, signIn }));
  // Return on the password = Sign in
  await page.keyboard.type(account.password);
  await page.keyboard.press('Enter');
  await wait(page, () => /index\.html/.test(location.pathname), undefined, 15000);
  check(tag('Return on the password signs in (lands on the app)'), true);
  await page.close();
}

async function createFlow(check, browser, server, tag, errors, viewport, keyboardViewport) {
  const page = await openAuth(browser, server, tag('page (create)'), errors, viewport);
  await page.click('#auth-email');
  await page.setViewport(keyboardViewport);
  await sleep(300);
  const email = 'new.' + Math.random().toString(36).slice(2, 8) + '@example.com';
  await page.keyboard.type(email);
  await page.keyboard.press('Enter');
  await wait(page, () => !document.querySelector('.lime-auth__step[data-step="create"]').hidden);
  await sleep(350);
  const create0 = await page.evaluate(() => ({ focused: document.activeElement && document.activeElement.id, username: document.getElementById('auth-create-username').value }));
  const btn0 = await visibleAboveKeyboard(page, '#auth-create-form button[type=submit]');
  check(tag('a new email goes to the create step with the name focused and "Create account" above the keyboard (' + btn0.bottom + ' of ' + btn0.h + 'px)'), create0.focused === 'auth-name' && create0.username === email && btn0.ok, JSON.stringify({ create0, btn0 }));
  await page.keyboard.type('Pat Park');
  await page.keyboard.press('Enter');
  await sleep(250);
  const afterName = await page.evaluate(() => ({ focused: document.activeElement && document.activeElement.id, error: document.getElementById('auth-error').textContent, path: location.pathname }));
  check(tag('Return on the name goes to the password (it does not submit)'), afterName.focused === 'auth-create-password' && !afterName.error && /auth\.html/.test(afterName.path), JSON.stringify(afterName));
  await page.keyboard.type('password123');
  await page.keyboard.press('Enter');
  await sleep(350);
  const noTerms = await page.evaluate(() => ({ focused: document.activeElement && document.activeElement.id, hint: !document.getElementById('auth-terms-hint').hidden, path: location.pathname }));
  const hintVis = await visibleAboveKeyboard(page, '#auth-terms-hint');
  check(tag('Return on the password with the terms box unticked moves to the box with a hint (nothing is created), the hint above the keyboard'), noTerms.focused === 'auth-terms' && noTerms.hint && /auth\.html/.test(noTerms.path) && hintVis.ok, JSON.stringify({ noTerms, hintVis }));
  await page.keyboard.press(' '); // ticks the focused box
  await sleep(150);
  await page.focus('#auth-create-password');
  await page.keyboard.press('Enter');
  await wait(page, () => /index\.html/.test(location.pathname), undefined, 15000);
  check(tag('with the box ticked, Return on the password creates the account (lands on the app)'), true);
  await page.close();
}

export async function run({ check }) {
  if (!browserAvailable('firefox') || !browserAvailable('chrome')) { check('auth-phone (skipped: needs both Firefox and Chrome installed)', true, 'skipped'); return; }
  const server = await new DevServer().start();
  const chrome = await launch('chrome');
  const firefox = await launch('firefox');
  const errors = [];
  try {
    const sizes = [['Chrome 390x844', chrome, mobile(390, 844), mobile(390, 470)], ['Chrome 360x780', chrome, mobile(360, 780), mobile(360, 430)], ['Chrome landscape 844x390', chrome, mobile(844, 390), mobile(844, 200)]];
    for (const [label, browser, vp, kvp] of sizes) {
      const tag = (t) => `${label}: ${t}`;
      await emailFlow(check, browser, server, tag, errors, vp, kvp, await server.signUp('Pat Park'));
      if (label === 'Chrome 390x844') await createFlow(check, browser, server, tag, errors, vp, kvp);
    }
    // Firefox has no mobile emulation: a 390 wide window, with the keyboard simulated by a shorter one
    const ffTag = (t) => `Firefox 390x844: ${t}`;
    await emailFlow(check, firefox, server, ffTag, errors, { width: 390, height: 844 }, { width: 390, height: 470 }, await server.signUp('Pat Park'));
    await createFlow(check, firefox, server, ffTag, errors, { width: 390, height: 844 }, { width: 390, height: 470 });
    check('auth-phone: zero console or page errors', errors.length === 0, errors.slice(0, 3).join(' | '));
  } finally {
    await Promise.allSettled([chrome.close(), firefox.close()]);
    await server.destroy();
  }
}
