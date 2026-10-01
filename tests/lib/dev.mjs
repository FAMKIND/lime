// Starts server/dev-server.mjs on its own port and data folder, can stop and restart it (same port, same data), and signs
// people up through the API so a browser page can start already signed in.
import { spawn } from 'node:child_process';
import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import net from 'node:net';
import { REPO_ROOT, sleep } from './harness.mjs';

export function freePort() {
  return new Promise((resolve) => { const s = net.createServer(); s.listen(0, '127.0.0.1', () => { const { port } = s.address(); s.close(() => resolve(port)); }); });
}

// A running dev server we did not start (the one run.mjs starts for the browser suites): API calls and sign-ups only.
export class Remote {
  constructor(base) { this.base = base; this.origin = new URL(base).origin; }
  async api(method, p, { body, token } = {}) {
    const r = await fetch(this.origin + '/api/v1' + p, { method, headers: Object.assign({ 'content-type': 'application/json' }, token ? { authorization: 'Bearer ' + token } : {}), body: body ? JSON.stringify(body) : undefined });
    const text = await r.text();
    let json = null; try { json = JSON.parse(text); } catch (e) { /* none */ }
    return { status: r.status, body: json };
  }
  // A new account made through the API; returns what a page needs to start signed in.
  async signUp(name, password = 'password123') {
    const email = name.toLowerCase().replace(/[^a-z]+/g, '.') + '.' + Math.random().toString(36).slice(2, 7) + '@example.com';
    const device = 'e2e-' + Math.random().toString(36).slice(2, 8);
    const r = await this.api('POST', '/auth/signup', { body: { email, password, display_name: name, device_id: device } });
    if (r.status !== 201) throw new Error('signup failed: ' + JSON.stringify(r.body));
    return { name, email, password, userId: r.body.user.id, token: r.body.access_token, refresh: r.body.refresh_token, device };
  }
}

export class DevServer extends Remote {
  constructor() { super('http://127.0.0.1:1/public/'); this.dataDir = fs.mkdtempSync(path.join(os.tmpdir(), 'lime-e2e-')); this.proc = null; this.port = 0; }
  get base() { return `http://127.0.0.1:${this.port}/public/`; }
  set base(v) { /* derived from the port */ }
  get origin() { return `http://127.0.0.1:${this.port}`; }
  set origin(v) { /* derived from the port */ }
  async start() {
    if (!this.port) this.port = await freePort();
    this.proc = spawn(process.execPath, [path.join(REPO_ROOT, 'server', 'dev-server.mjs'), '--port', String(this.port), '--data', this.dataDir], { stdio: ['ignore', 'pipe', 'pipe'] });
    this.log = '';
    this.proc.stdout.on('data', (d) => { this.log += d; });
    this.proc.stderr.on('data', (d) => { this.log += d; });
    for (let i = 0; i < 150; i++) {
      try { if ((await fetch(this.origin + '/api/v1/health')).ok) return this; } catch (e) { /* not up */ }
      await sleep(100);
    }
    throw new Error('dev server did not start: ' + this.log);
  }
  stop(signal = 'SIGTERM') { return new Promise((resolve) => { if (!this.proc) return resolve(); this.proc.once('exit', resolve); this.proc.kill(signal); this.proc = null; }); }
  async restart() { await this.stop(); await sleep(200); return this.start(); }
  async destroy() { await this.stop('SIGKILL'); fs.rmSync(this.dataDir, { recursive: true, force: true, maxRetries: 5, retryDelay: 100 }); }

}

// Opens a page already signed in as `person` (tokens in this tab's sessionStorage, exactly where the app keeps them).
export async function openAs(browser, server, person, label, errors, { hash = '' } = {}) {
  const { watchErrors } = await import('./harness.mjs');
  const page = await browser.newPage();
  watchErrors(page, label, errors);
  await page.evaluateOnNewDocument((p, deviceId) => {
    if (!sessionStorage.getItem('e2e-seeded')) { // once per tab, not on every navigation (a signed-out tab must stay signed out)
      sessionStorage.setItem('e2e-seeded', '1');
      sessionStorage.setItem('lime-api-session', JSON.stringify({ userId: p.userId, email: p.email, access_token: p.token, refresh_token: p.refresh, expires_at: Date.now() + 14 * 60 * 1000 }));
      sessionStorage.setItem('lime-demo-session', JSON.stringify({ userId: p.userId, email: p.email }));
    }
    try { localStorage.setItem('lime-device-id', deviceId); } catch (e) { /* none */ }
  }, person, person.device);
  await page.goto(server.base + 'index.html' + hash, { waitUntil: 'load' });
  await page.waitForFunction(() => window.LimeStore && LimeStore.isApi() && LimeStore.getCurrentUserId(), { polling: 20, timeout: 15000 });
  page.person = person;
  return page;
}
