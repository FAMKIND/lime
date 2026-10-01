// Shared helpers: a throwaway static server, browser launching, a tiny
// assertion recorder. No app code lives here.
import { spawn } from 'node:child_process';
import net from 'node:net';
import path from 'node:path';
import os from 'node:os';
import fs from 'node:fs';
import { fileURLToPath } from 'node:url';

export const REPO_ROOT = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '..', '..');
export const sleep = (ms) => new Promise((r) => setTimeout(r, ms));

const BROWSERS = {
  chrome: '/Applications/Google Chrome.app/Contents/MacOS/Google Chrome',
  firefox: '/Applications/Firefox.app/Contents/MacOS/firefox',
};
export const browserAvailable = (name) => fs.existsSync(BROWSERS[name]);

// LIME_TEST_ORIGIN=lan runs the browser suites against this computer's LAN address (an insecure context, like a phone opening
// http://192.168.x.x:8000), where crypto.randomUUID and crypto.subtle do not exist. An explicit http://host[:port] works too.
// Unset: 127.0.0.1 (a secure context, like http://localhost).
export function lanAddress() {
  const i = Object.values(os.networkInterfaces()).flat().find((n) => n && n.family === 'IPv4' && !n.internal);
  return i ? i.address : null;
}
export function testHost() {
  const v = process.env.LIME_TEST_ORIGIN;
  if (!v) return '127.0.0.1';
  if (v === 'lan') { const ip = lanAddress(); if (!ip) throw new Error('LIME_TEST_ORIGIN=lan needs a LAN network interface'); return ip; }
  return new URL(v).hostname;
}
export const insecureOrigin = () => !!process.env.LIME_TEST_ORIGIN;

// In an insecure-origin run, proves the page really is not a secure context (otherwise the run proves nothing).
export async function checkOrigin(page, check, label) {
  const secure = await page.evaluate(() => window.isSecureContext);
  const want = !insecureOrigin();
  check((label || 'page') + ': ' + (want ? 'served from a secure context (localhost)' : 'is NOT a secure context (window.isSecureContext === false), like a phone on the LAN'), secure === want, 'isSecureContext=' + secure);
}

function freePort() {
  return new Promise((resolve, reject) => {
    const srv = net.createServer();
    srv.listen(0, '127.0.0.1', () => { const { port } = srv.address(); srv.close(() => resolve(port)); });
    srv.on('error', reject);
  });
}

// Serves the repo root (so /public/... and /vendor/... work), like the
// preview URL in the README. Own process, own port, stopped afterwards.
export async function startServer() {
  const port = await freePort();
  // LIME_TEST_SERVER=dev runs the same suites against server/dev-server.mjs (LIME-73) instead of the Python static server.
  const dev = process.env.LIME_TEST_SERVER === 'dev';
  const dataDir = dev ? fs.mkdtempSync(path.join(os.tmpdir(), 'lime-dev-')) : null;
  const proc = dev
    ? spawn(process.execPath, [path.join(REPO_ROOT, 'server', 'dev-server.mjs'), '--port', String(port), '--data', dataDir], { stdio: 'ignore' })
    : spawn('python3', ['-m', 'http.server', String(port), '--bind', insecureOrigin() ? '0.0.0.0' : '127.0.0.1'], { cwd: REPO_ROOT, stdio: 'ignore' });
  const base = `http://${testHost()}:${port}/public/`;
  for (let i = 0; i < 50; i++) {
    try { const r = await fetch(base + 'index.html'); if (r.ok) break; } catch (e) { /* not up yet */ }
    await sleep(100);
  }
  const stop = () => new Promise((resolve) => {
    proc.once('exit', () => { if (dataDir) fs.rmSync(dataDir, { recursive: true, force: true, maxRetries: 5, retryDelay: 100 }); resolve(); });
    proc.kill('SIGKILL');
  });
  return { base, port, stop };
}

// puppeteer-core drives the user's *installed* browsers: Chrome over CDP,
// Firefox over WebDriver BiDi (Playwright's patched Firefox is not the
// user's Firefox; see PLOT.md). Background-tab throttling is switched off
// so two tabs in one window behave like two visible windows.
export async function launch(name = 'chrome') {
  const { default: puppeteer } = await import('puppeteer-core');
  return puppeteer.launch({
    executablePath: BROWSERS[name],
    browser: name === 'firefox' ? 'firefox' : 'chrome',
    headless: true,
    protocol: name === 'firefox' ? 'webDriverBiDi' : undefined,
    args: name === 'chrome'
      ? ['--disable-background-timer-throttling', '--disable-renderer-backgrounding', '--disable-backgrounding-occluded-windows']
      : [],
  });
}

// Messages that are noise, not failures (documented in TEND.md).
const IGNORABLE = [
  /demo-config\.local/, // gitignored file; 404 when absent
  /Failed to load resource.*status of (401|403|404|409|410)/, // the app's own expected answers (wrong password, taken email, ...)
  /Failed to load resource.*404/,
  /downloadable font/, // Google Fonts blocked offline
  /ResizeObserver loop/,
  /SecurityError: The operation is insecure/, // Firefox/BiDi on sign-out navigation; pre-existing (LIME-69)
  /favicon/,
];
export const ignorable = (text) => IGNORABLE.some((re) => re.test(text));

export function watchErrors(page, label, sink) {
  page.on('pageerror', (e) => { if (!ignorable(String(e.message))) sink.push(`${label} pageerror: ${e.message}`); });
  page.on('console', (m) => { if (m.type() === 'error' && !ignorable(m.text())) sink.push(`${label} console: ${m.text()}`); });
}

// A suite gets one of these: check(name, condition, detail) records a result.
export function recorder() {
  const results = [];
  return {
    results,
    check(name, condition, detail) { results.push({ name, pass: !!condition, detail: detail === undefined ? '' : String(detail) }); },
  };
}

// Opens a page already "signed in" as a seed teacher (per-tab session).
export async function openSignedIn(browser, base, userId, email, label, errors) {
  const page = await browser.newPage();
  watchErrors(page, label, errors);
  await page.evaluateOnNewDocument((u, e) => {
    if (!sessionStorage.getItem('lime-demo-session')) sessionStorage.setItem('lime-demo-session', JSON.stringify({ userId: u, email: e }));
  }, userId, email);
  await page.goto(base + 'index.html', { waitUntil: 'load' });
  await page.waitForFunction(() => window.LimeStore && LimeStore.getCurrentUserId(), { polling: 10, timeout: 10000 });
  return page;
}

export async function wipeStorage(browser, base) {
  const page = await browser.newPage();
  await page.goto(base + 'auth.html');
  await page.evaluate(() => { localStorage.clear(); sessionStorage.clear(); });
  await page.close();
}

// True when `base` is served by server/dev-server.mjs (the API answers), i.e. the app runs on the API backend.
export async function isDevServer(base) {
  try { const r = await fetch(new URL('/api/v1/health', base)); return r.ok; } catch (e) { return false; }
}
