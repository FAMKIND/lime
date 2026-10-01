// A tiny WebDriver (classic) client for safaridriver, the Mac's own Safari automation (the same WebKit engine as iOS Safari).
// No dependencies. Safari must have "Allow Remote Automation" on (Safari > Settings > Developer, or `safaridriver --enable`,
// which asks for an administrator password once); until then start() reports `{ unavailable: <reason> }`.
import { spawn } from 'node:child_process';
import net from 'node:net';
import { sleep } from './harness.mjs';

const ELEMENT = 'element-6066-11e4-a52e-4f735466cecf';
const freePort = () => new Promise((resolve) => { const s = net.createServer(); s.listen(0, '127.0.0.1', () => { const { port } = s.address(); s.close(() => resolve(port)); }); });

export class Safari {
  static async start() {
    const port = await freePort();
    const proc = spawn('/usr/bin/safaridriver', ['--port', String(port)], { stdio: 'ignore' });
    const base = `http://127.0.0.1:${port}`;
    for (let i = 0; i < 50; i++) { try { await fetch(base + '/status'); break; } catch (e) { await sleep(100); } }
    const res = await fetch(base + '/session', { method: 'POST', headers: { 'content-type': 'application/json' }, body: JSON.stringify({ capabilities: { alwaysMatch: { browserName: 'safari' } } }) });
    const json = await res.json();
    if (!res.ok || !json.value || !json.value.sessionId) { proc.kill(); return { unavailable: (json.value && json.value.message) || 'safaridriver could not start a session' }; }
    return new Safari(proc, base, json.value.sessionId);
  }
  constructor(proc, base, id) { this.proc = proc; this.root = `${base}/session/${id}`; }
  async call(method, path, body) {
    const r = await fetch(this.root + path, { method, headers: { 'content-type': 'application/json' }, body: body === undefined ? undefined : JSON.stringify(body) });
    const j = await r.json();
    if (!r.ok) throw new Error('safaridriver ' + path + ': ' + ((j.value && j.value.message) || r.status));
    return j.value;
  }
  go(url) { return this.call('POST', '/url', { url }); }
  url() { return this.call('GET', '/url'); }
  exec(script, args = []) { return this.call('POST', '/execute/sync', { script, args }); }
  async find(css) { const el = await this.call('POST', '/element', { using: 'css selector', value: css }); return el[ELEMENT]; }
  click(el) { return this.call('POST', `/element/${el}/click`, {}); }
  keys(el, text) { return this.call('POST', `/element/${el}/value`, { text }); }
  // Polls an in-page expression (a function body returning something truthy) until it holds.
  async until(fnBody, args = [], ms = 10000) {
    const end = Date.now() + ms;
    let last;
    while (Date.now() < end) { try { last = await this.exec('return (function(){' + fnBody + '}).apply(null, arguments);', args); if (last) return last; } catch (e) { last = null; } await sleep(100); }
    throw new Error('Safari: timed out waiting for: ' + fnBody.slice(0, 100));
  }
  async close() { try { await this.call('DELETE', ''); } catch (e) { /* gone */ } this.proc.kill(); }
}
