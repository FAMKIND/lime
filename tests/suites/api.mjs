// The dev server and the v1 contract (docs/api.md): every endpoint, permissions, idempotency, DM dedup + alias, backfill,
// feed visibility (no per-user leaks; email and phone rules), files, realtime, and restart persistence.
// Starts its own server on a free port with a throwaway data folder. Seed-teacher sign-in is only checked when the
// gitignored demo password file exists.
import { spawn } from 'node:child_process';
import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import net from 'node:net';
import crypto from 'node:crypto';
import { REPO_ROOT, sleep } from '../lib/harness.mjs';

const freePort = () => new Promise((resolve) => { const s = net.createServer(); s.listen(0, '127.0.0.1', () => { const { port } = s.address(); s.close(() => resolve(port)); }); });
const uuid = () => crypto.randomUUID();

async function startServer(dataDir, port) {
  const proc = spawn(process.execPath, [path.join(REPO_ROOT, 'server', 'dev-server.mjs'), '--port', String(port), '--data', dataDir], { stdio: ['ignore', 'pipe', 'pipe'] });
  let log = '';
  proc.stdout.on('data', (d) => { log += d; });
  proc.stderr.on('data', (d) => { log += d; });
  const base = `http://127.0.0.1:${port}`;
  for (let i = 0; i < 100; i++) {
    try { if ((await fetch(base + '/api/v1/health')).ok) return { proc, base, log: () => log }; } catch (e) { /* not up */ }
    await sleep(100);
  }
  proc.kill();
  throw new Error('server did not start: ' + log);
}
const stopServer = (s, signal = 'SIGTERM') => new Promise((resolve) => { s.proc.once('exit', resolve); s.proc.kill(signal); });

class Client {
  constructor(base, email, name) { this.base = base + '/api/v1'; this.email = email; this.name = name; this.device = 'dev-' + uuid().slice(0, 8); }
  async raw(method, p, { body, headers, token = this.token } = {}) {
    const h = Object.assign({}, headers);
    if (token) h.authorization = 'Bearer ' + token;
    let payload = body;
    if (body && !(body instanceof FormData) && !(body instanceof Uint8Array)) { payload = JSON.stringify(body); h['content-type'] = 'application/json'; }
    return fetch(this.base + p, { method, headers: h, body: payload });
  }
  async json(method, p, opts) { const r = await this.raw(method, p, opts); const text = await r.text(); let j = null; try { j = JSON.parse(text); } catch (e) { /* not json */ } return { status: r.status, body: j }; }
  async signup(password = 'password123') {
    const r = await this.json('POST', '/auth/signup', { body: { email: this.email, password, display_name: this.name, device_id: this.device }, token: null });
    Object.assign(this, { token: r.body.access_token, refresh: r.body.refresh_token, id: r.body.user && r.body.user.id });
    return r;
  }
  op(type, payload) { return { op_id: uuid(), type, actor_id: this.id, device_id: this.device, client_ts: new Date().toISOString(), payload }; }
  async send(...ops) { const r = await this.json('POST', '/ops', { body: { device_id: this.device, ops } }); return r.body.results; }
  async one(type, payload) { return (await this.send(this.op(type, payload)))[0]; }
  changes(since = 0) { return this.json('GET', '/changes?since=' + since).then((r) => r.body); }
  snapshot() { return this.json('GET', '/snapshot').then((r) => r.body); }
  upload(bytes, name, mime) { const f = new FormData(); f.append('file', new Blob([bytes], { type: mime }), name); return this.json('POST', '/files', { body: f }); }
  download(id, headers) { return this.raw('GET', '/files/' + id, { headers }); }
}

// Collects server-sent events from /events.
async function openEvents(client) {
  const t = await client.json('POST', '/events/ticket');
  const ctl = new AbortController();
  const res = await fetch(client.base + '/events?ticket=' + t.body.ticket, { signal: ctl.signal });
  const events = [];
  (async () => {
    const reader = res.body.getReader(); const dec = new TextDecoder(); let buf = '';
    try { for (;;) { const { value, done } = await reader.read(); if (done) break; buf += dec.decode(value); let i; while ((i = buf.indexOf('\n\n')) > -1) { const block = buf.slice(0, i); buf = buf.slice(i + 2); const d = /^data: (.*)$/m.exec(block); if (d) events.push(JSON.parse(d[1])); } } } catch (e) { /* aborted */ }
  })();
  const waitFor = async (pred, ms = 4000) => { const end = Date.now() + ms; while (Date.now() < end) { const f = events.find(pred); if (f) return f; await sleep(20); } return null; };
  return { events, waitFor, ticket: t.body.ticket, status: res.status, close: () => ctl.abort() };
}

export async function run({ check }) {
  const dataDir = fs.mkdtempSync(path.join(os.tmpdir(), 'lime-api-'));
  const port = await freePort();
  let server = await startServer(dataDir, port);
  try {
    const base = server.base;
    // ── health, static, hygiene ──
    const health = await (await fetch(base + '/api/v1/health')).json();
    check('GET /health answers without a token and reports log_start', health.ok === true && health.api === 'v1' && Number.isInteger(health.seq) && Number.isInteger(health.log_start));
    check('serves the app from the repo root (index.html, no-cache)', await fetch(base + '/public/index.html').then((r) => r.status === 200 && /no-cache/.test(r.headers.get('cache-control'))));
    const lan = Object.values(os.networkInterfaces()).flat().find((i) => i && i.family === 'IPv4' && !i.internal);
    check(lan ? 'also answers on the LAN address (bound to 0.0.0.0)' : 'LAN address check (skipped: no network interface)', lan ? await fetch(`http://${lan.address}:${port}/public/index.html`).then((r) => r.status === 200).catch(() => false) : true, lan ? lan.address : 'skipped');
    check('the repo root redirects to the app', await fetch(base + '/', { redirect: 'manual' }).then((r) => r.status === 302 && /public\/index\.html/.test(r.headers.get('location'))));
    check('Range works on media (206)', await fetch(base + '/public/assets/auth-hero.mp4', { headers: { range: 'bytes=0-9' } }).then(async (r) => r.status === 206 && (await r.arrayBuffer()).byteLength === 10));
    check('only public/ and vendor/ are served: no server code, data, tests, seed files, docs, dotfiles, or *.local.* (the demo password)', (await Promise.all(['/server/dev-server.mjs', '/data/auth.json', '/tests/package.json', '/.git/config', '/public/%2e%2e/TEND.md', '/seed-data/test-accounts.local.json', '/seed-data/test-accounts.example.json', '/public/js/demo-config.local.js', '/public/js/anything.local.js', '/docs/api.md', '/package.json', '/.gitignore'].map((u) => fetch(base + u).then((r) => r.status)))).every((s) => s === 404));
    check('no token gives 401 on every protected endpoint', (await Promise.all([['GET', '/snapshot'], ['GET', '/changes?since=0'], ['POST', '/ops'], ['GET', '/profiles?q=ab'], ['POST', '/files'], ['GET', '/link-preview?url=https://a.b'], ['POST', '/events/ticket']].map(([m, p]) => new Client(base).json(m, p, { token: null }).then((r) => r.status)))).every((s) => s === 401));

    // ── auth ──
    const A = new Client(base, 'ada@example.com', 'Ada Lovelace');
    const B = new Client(base, 'bo@example.com', 'Bo Peep');
    const C = new Client(base, 'cy@example.com', 'Cy Young');
    const su = await A.signup(); await B.signup(); await C.signup();
    check('signup returns the person, tokens and a seq', su.status === 201 && su.body.user.display_name === 'Ada Lovelace' && su.body.access_token && su.body.refresh_token && su.body.expires_in === 900 && Number.isInteger(su.body.seq));
    check('signup rejects a taken email, a short password and a bad email', (await new Client(base, 'ada@example.com', 'x').signup()).status === 409
      && (await new Client(base, 'new@example.com', 'x').signup('short')).status === 400 && (await new Client(base, 'not-an-email', 'x').signup()).status === 400);
    const credFile = JSON.parse(fs.readFileSync(path.join(dataDir, 'auth.json'), 'utf8'));
    check('passwords are stored as salted PBKDF2 (>= 600,000 iterations), never plain', credFile.credentials['ada@example.com'].iterations >= 600000 && credFile.credentials['ada@example.com'].hash && !JSON.stringify(credFile).includes('password123'));
    const bad = await new Client(base).json('POST', '/auth/signin', { body: { email: 'ada@example.com', password: 'wrong-password', device_id: 'd1' }, token: null });
    const missing = await new Client(base).json('POST', '/auth/signin', { body: { email: 'nobody@example.com', password: 'wrong-password', device_id: 'd1' }, token: null });
    check('wrong password and unknown email give the same 401 invalid_credentials', bad.status === 401 && missing.status === 401 && bad.body.error.code === 'invalid_credentials' && bad.body.error.message === missing.body.error.message);
    const si = await new Client(base).json('POST', '/auth/signin', { body: { email: 'ada@example.com', password: 'password123', device_id: 'phone-1' }, token: null });
    check('signin works and returns tokens', si.status === 200 && si.body.access_token && si.body.user.id === A.id);
    const r1 = await new Client(base).json('POST', '/auth/refresh', { body: { refresh_token: si.body.refresh_token, device_id: 'phone-1' }, token: null });
    check('refresh returns a new access token and a NEW refresh token (rotation)', r1.status === 200 && r1.body.access_token && r1.body.refresh_token && r1.body.refresh_token !== si.body.refresh_token);
    const reuse = await new Client(base).json('POST', '/auth/refresh', { body: { refresh_token: si.body.refresh_token, device_id: 'phone-1' }, token: null });
    check('reusing an old refresh token is refused and ends that device\'s session', reuse.status === 401
      && (await new Client(base).json('POST', '/auth/refresh', { body: { refresh_token: r1.body.refresh_token, device_id: 'phone-1' }, token: null })).status === 401
      && (await new Client(base).json('GET', '/snapshot', { token: r1.body.access_token })).status === 401);
    const so = await new Client(base).json('POST', '/auth/signin', { body: { email: 'bo@example.com', password: 'password123', device_id: 'tablet' }, token: null });
    check('sign out revokes only that device', (await new Client(base).json('POST', '/auth/signout', { token: so.body.access_token })).status === 204
      && (await new Client(base).json('GET', '/snapshot', { token: so.body.access_token })).status === 401 && (await B.snapshot()).profile.id === B.id);
    check('the access token of a tampered signature is refused', (await new Client(base).json('GET', '/snapshot', { token: A.token.slice(0, -3) + 'xxx' })).status === 401);

    // ── DMs: dedup and alias; idempotency ──
    const dmA = uuid(); const dmB = uuid();
    const opCreate = A.op('conversation.create', { conversation_id: dmA, type: 'direct', member_ids: [B.id] });
    const [c1] = await A.send(opCreate);
    const [c1again] = await A.send(opCreate);
    check('a replayed op_id is a no-op that returns the original result', c1.status === 'applied' && c1again.status === 'duplicate' && c1again.seq === c1.seq);
    const [c2] = await B.send(B.op('conversation.create', { conversation_id: dmB, type: 'direct', member_ids: [A.id] }));
    check('two people creating the same DM converge on the first (canonical id returned)', c2.status === 'applied' && c2.canonical_conversation_id === dmA);
    const bFeed = await B.changes(0);
    check('the second creator gets an alias entry for its own id', bFeed.changes.some((e) => e.alias && e.alias.from === dmB && e.alias.to === dmA));
    check('the alias entry goes only to that person', !(await A.changes(0)).changes.some((e) => e.alias));
    const m0 = await B.one('message.send', { message_id: uuid(), conversation_id: dmB, content: 'sent to my own (losing) id' });
    const aSnap0 = await A.snapshot();
    check('an op naming the losing id is applied to the canonical conversation', m0.status === 'applied' && aSnap0.messages.some((m) => m.content === 'sent to my own (losing) id' && m.conversation_id === dmA));
    check('only one DM exists for the pair', aSnap0.conversations.filter((c) => c.type === 'direct' && c.dm_key).length === 1);
    check('a DM needs exactly one other person and no name', (await A.one('conversation.create', { conversation_id: uuid(), type: 'direct', member_ids: [B.id, C.id] })).error.code === 'invalid_op'
      && (await A.one('conversation.create', { conversation_id: uuid(), type: 'direct', member_ids: [C.id], name: 'x' })).error.code === 'invalid_op');

    // ── messages: validation, permissions, time ──
    const written = '2026-10-01T09:00:00.000Z';
    const sent = A.op('message.send', { message_id: 'msg-a-1', conversation_id: dmA, content: 'hello Bo' }); sent.client_ts = written;
    const [ms] = await A.send(sent);
    const bSnap = await B.snapshot();
    const stored = bSnap.messages.find((m) => m.id === 'msg-a-1');
    check('message.send stores both times: written (client_ts) and delivered (created_at = server time)', ms.status === 'applied' && stored.client_ts === written && stored.created_at === ms.server_ts && stored.created_at !== written);
    check('an empty message is invalid_op', (await A.one('message.send', { message_id: uuid(), conversation_id: dmA, content: '   ' })).error.code === 'invalid_op');
    check('a non-member sending gets not_found (looks the same as no such chat)', (await C.one('message.send', { message_id: uuid(), conversation_id: dmA, content: 'let me in' })).error.code === 'not_found');
    check('reply_to must be in the same conversation; a real reply is fine', (await A.one('message.send', { message_id: uuid(), conversation_id: dmA, content: 'x', reply_to: 'no-such' })).error.code === 'invalid_op'
      && (await B.one('message.send', { message_id: uuid(), conversation_id: dmA, content: 'a reply', reply_to: 'msg-a-1' })).status === 'applied');
    check('actor_id must match the token (403) and unknown types are unsupported_op', (await A.send(Object.assign(A.op('message.send', { message_id: uuid(), conversation_id: dmA, content: 'x' }), { actor_id: B.id })))[0].error.code === 'forbidden'
      && (await A.one('message.delete', {})).error.code === 'unsupported_op');
    check('a batch applies every op, one bad op does not stop the rest', await (async () => {
      const r = await A.send(A.op('message.send', { message_id: uuid(), conversation_id: 'nope', content: 'x' }), A.op('message.send', { message_id: uuid(), conversation_id: dmA, content: 'after the bad one' }));
      return r[0].status === 'rejected' && r[1].status === 'applied';
    })());

    // ── reactions ──
    const rt = A.op('reaction.toggle', { message_id: 'msg-a-1', emoji: '👍', present: true });
    await A.send(rt);
    await A.one('reaction.toggle', { message_id: 'msg-a-1', emoji: '👍', present: true }); // present is idempotent, not a flip
    let reacts = (await B.snapshot()).message_reactions.filter((r) => r.message_id === 'msg-a-1' && r.emoji === '👍');
    check('reaction.toggle present:true is idempotent (twice is still one live reaction)', reacts.length === 1 && reacts[0].removed_at === null);
    await A.one('reaction.toggle', { message_id: 'msg-a-1', emoji: '👍', present: false });
    reacts = (await B.snapshot()).message_reactions.filter((r) => r.message_id === 'msg-a-1');
    check('removing a reaction is a tombstone (removed_at set), not a delete', reacts.length === 1 && !!reacts[0].removed_at);
    check('reacting in a chat you are not in is not_found', (await C.one('reaction.toggle', { message_id: 'msg-a-1', emoji: '👍', present: true })).error.code === 'not_found');

    // ── groups: permissions, add, backfill ──
    const gid = uuid();
    await A.one('conversation.create', { conversation_id: gid, type: 'group', name: 'Staff', member_ids: [B.id] });
    check('only the group owner can rename, delete or add people (403)', (await B.one('conversation.rename', { conversation_id: gid, name: 'x' })).error.code === 'forbidden'
      && (await B.one('conversation.delete', { conversation_id: gid })).error.code === 'forbidden' && (await B.one('membership.add', { conversation_id: gid, user_ids: [C.id] })).error.code === 'forbidden');
    check('a DM cannot be deleted for everyone or have people added', (await A.one('conversation.delete', { conversation_id: dmA })).error.code === 'forbidden' && (await A.one('membership.add', { conversation_id: dmA, user_ids: [C.id] })).error.code === 'forbidden');
    const mg = await A.one('message.send', { message_id: 'msg-g-1', conversation_id: gid, content: 'history before Cy joined' });
    const cBefore = await C.changes(0);
    await A.one('conversation.rename', { conversation_id: gid, name: 'Staff room' });
    const addRes = await A.one('membership.add', { conversation_id: gid, user_ids: [C.id, C.id, B.id] });
    const cFeed = await C.changes(0);
    const backfill = cFeed.changes.find((e) => e.backfill);
    check('adding a person: they get one backfill entry with the whole conversation', addRes.status === 'applied' && backfill && backfill.backfill.conversation.id === gid && backfill.backfill.messages.some((m) => m.id === 'msg-g-1') && backfill.backfill.conversation_members.length === 3);
    check('before being added, C could see nothing of that group', !cBefore.changes.some((e) => (e.op && e.op.payload.conversation_id === gid) || e.backfill));
    check('C\'s feed does not replay the older ops of the group (the backfill covers them)', !cFeed.changes.some((e) => e.op && e.op.type === 'message.send' && e.op.payload.conversation_id === gid));
    check('existing members get the add op with only the people actually added', (await B.changes(0)).changes.some((e) => e.op && e.op.type === 'membership.add' && e.op.payload.user_ids.length === 1 && e.op.payload.user_ids[0] === C.id));
    check('the new member now receives later ops', await (async () => { await A.one('message.send', { message_id: uuid(), conversation_id: gid, content: 'welcome Cy' }); return (await C.changes(cFeed.next)).changes.some((e) => e.op && e.op.payload.content === 'welcome Cy'); })());

    // ── per-user rows never leak ──
    await A.one('membership.setStarred', { conversation_id: gid, starred: true });
    await A.one('membership.setArchived', { conversation_id: gid, archived: true });
    await A.one('membership.markRead', { conversation_id: gid });
    await A.one('conversation.deleteForMe', { conversation_id: dmA });
    const bAll = (await B.changes(0)).changes.map((e) => e.op && e.op.type);
    check('star, archive, read and delete-for-me go only to the person who did them', !bAll.some((t) => /setStarred|setArchived|markRead|deleteForMe/.test(t)) && (await A.changes(0)).changes.some((e) => e.op && e.op.type === 'membership.markRead'));
    const bSnapG = await B.snapshot();
    const aRowSeenByB = bSnapG.conversation_members.find((m) => m.conversation_id === gid && m.user_id === A.id);
    const aSnapG = await A.snapshot();
    check('another member\'s row carries no starred/archived/cleared/read fields; your own does', aRowSeenByB && !('starred' in aRowSeenByB) && !('last_read_at' in aRowSeenByB) && !('archived_at' in aRowSeenByB) && !('cleared_at' in aRowSeenByB)
      && aSnapG.conversation_members.find((m) => m.conversation_id === gid && m.user_id === A.id).starred === true);
    check('last_read_at never moves backwards', await (async () => { const before = (await A.snapshot()).conversation_members.find((m) => m.conversation_id === gid && m.user_id === A.id).last_read_at; await A.one('membership.markRead', { conversation_id: gid, read_through_seq: 1 }); return (await A.snapshot()).conversation_members.find((m) => m.conversation_id === gid && m.user_id === A.id).last_read_at >= before; })());
    check('a conversation deleted by its owner leaves everyone\'s snapshot', await (async () => { const g2 = uuid(); await A.one('conversation.create', { conversation_id: g2, type: 'group', name: 'Temp', member_ids: [B.id] }); const del = await A.one('conversation.delete', { conversation_id: g2 }); return del.status === 'applied' && !(await B.snapshot()).conversations.some((c) => c.id === g2) && (await B.one('message.send', { message_id: uuid(), conversation_id: g2, content: 'x' })).error.code === 'not_found'; })());

    // ── profiles: phone and email rules, directory ──
    const upd = await A.one('profile.update', { patch: { phone: '555-123-4567', bio: 'Maths and puzzles', school: 'Lovelace Academy' } });
    const bFeedP = (await B.changes(0)).changes.find((e) => e.op && e.op.type === 'profile.update');
    check('profile.update reaches co-members with the phone stripped', upd.status === 'applied' && bFeedP && bFeedP.op.payload.patch.bio === 'Maths and puzzles' && !('phone' in bFeedP.op.payload.patch));
    await A.one('profile.update', { patch: { phone: '555-000-9999' } });
    check('a phone-only change is not delivered to anyone else', (await B.changes(0)).changes.filter((e) => e.op && e.op.type === 'profile.update').length === 1);
    check('your own feed keeps your phone', (await A.changes(0)).changes.some((e) => e.op && e.op.type === 'profile.update' && e.op.payload.patch.phone === '555-000-9999'));
    const bSeesA = (await B.snapshot()).profiles.find((p) => p.id === A.id);
    check('a co-member sees your email but never your phone; you see your own phone', bSeesA.email === 'ada@example.com' && !('phone' in bSeesA) && (await A.snapshot()).profile.phone === '555-000-9999');
    check('profile.update rejects fields that are not editable, blank names and someone else\'s file', (await A.one('profile.update', { patch: { email: 'x@y.co' } })).error.code === 'invalid_op'
      && (await A.one('profile.update', { patch: { display_name: '  ' } })).error.code === 'invalid_op' && (await A.one('profile.update', { patch: { avatar_url: 'no-such-file' } })).error.code === 'not_found');
    const dir = async (c, q) => (await c.json('GET', '/profiles?q=' + encodeURIComponent(q))).body;
    const hitsName = (await dir(C, 'lovelace')).profiles;
    check('directory: partial name or school matches, with public fields only', hitsName.length >= 1 && hitsName.every((p) => !('email' in p) && !('phone' in p)) && hitsName.some((p) => p.id === A.id));
    check('directory: exact email finds the person but does not reveal it; partial email finds nobody', (await dir(C, 'ada@example.com')).profiles.some((p) => p.id === A.id) && (await dir(C, 'ada@example.com')).profiles.every((p) => !('email' in p)) && (await dir(C, 'ada@exam')).profiles.length === 0);
    check('directory: exact phone (digits only) finds the person; partial phone finds nobody; no phone in results', (await dir(C, '(555) 000-9999')).profiles.some((p) => p.id === A.id) && (await dir(C, '555-000')).profiles.length === 0 && (await dir(C, '5550009999')).profiles.every((p) => !('phone' in p)));
    check('directory: needs 2+ characters, excludes you, and is capped at 50', (await C.json('GET', '/profiles?q=a')).status === 400 && !(await dir(A, 'ada')).profiles.some((p) => p.id === A.id) && (await dir(C, 'teacher')).profiles.length <= 50);
    const em = await A.one('profile.setEmail', { email: 'ada.new@example.com' });
    check('profile.setEmail: taken is a conflict; a change moves the sign-in too', (await B.one('profile.setEmail', { email: 'ada.new@example.com' })).error.code === 'conflict' && em.status === 'applied'
      && (await new Client(base).json('POST', '/auth/signin', { body: { email: 'ada.new@example.com', password: 'password123', device_id: 'x1' }, token: null })).status === 200
      && (await new Client(base).json('POST', '/auth/signin', { body: { email: 'ada@example.com', password: 'password123', device_id: 'x2' }, token: null })).status === 401);

    // ── files ──
    const bytes = crypto.randomBytes(2048);
    const up = await A.upload(bytes, 'pic.png', 'image/png');
    check('POST /files returns an id, size and mime', up.status === 201 && up.body.file_id && up.body.size === 2048 && up.body.mime === 'image/png');
    check('an unattached file is visible only to its uploader', (await A.download(up.body.file_id)).status === 200 && (await B.download(up.body.file_id)).status === 404);
    const withFile = await A.one('message.send', { message_id: uuid(), conversation_id: dmA, content: 'see attached', attachments: [{ attachment_id: uuid(), file_id: up.body.file_id, name: 'pic.png', size: 2048, mime: 'image/png', width: 10, height: 10, position: 0 }] });
    const dl = await B.download(up.body.file_id);
    check('once attached, members of that conversation can download the exact bytes', withFile.status === 'applied' && dl.status === 200 && Buffer.compare(Buffer.from(await dl.arrayBuffer()), bytes) === 0 && /inline/.test(dl.headers.get('content-disposition')));
    check('people outside the conversation get 404', (await C.download(up.body.file_id)).status === 404 && (await new Client(base).raw('GET', '/files/' + up.body.file_id, { token: null })).status === 401);
    check('a file already attached, or someone else\'s, cannot be attached again', (await B.one('message.send', { message_id: uuid(), conversation_id: dmA, content: 'steal', attachments: [{ attachment_id: uuid(), file_id: up.body.file_id }] })).error.code === 'not_found'
      && (await A.one('message.send', { message_id: uuid(), conversation_id: dmA, content: 'again', attachments: [{ attachment_id: uuid(), file_id: up.body.file_id }] })).error.code === 'conflict');
    check('Range on a file returns 206 with the right slice', await A.download(up.body.file_id, { range: 'bytes=10-19' }).then(async (r) => r.status === 206 && Buffer.compare(Buffer.from(await r.arrayBuffer()), bytes.subarray(10, 20)) === 0));
    const html = await A.upload(Buffer.from('<script>alert(1)</script>'), 'x.html', 'text/html');
    const htmlDl = await A.download(html.body.file_id);
    check('an uploaded .html is never shown inline (forced download, sandboxed)', /attachment/.test(htmlDl.headers.get('content-disposition')) && htmlDl.headers.get('content-type') === 'application/octet-stream' && /sandbox/.test(htmlDl.headers.get('content-security-policy')));
    check('files over 10 MB are refused (413)', (await A.upload(Buffer.alloc(10 * 1024 * 1024 + 10, 1), 'big.bin', 'application/octet-stream')).status === 413);
    const av = await A.upload(crypto.randomBytes(500), 'me.jpg', 'image/jpeg');
    await A.one('profile.update', { patch: { avatar_url: av.body.file_id } });
    check('a profile photo can be read by any signed-in person', (await C.download(av.body.file_id)).status === 200);

    // ── realtime ──
    const evB = await openEvents(B);
    const firstChanged = await evB.waitFor((e) => e.type === 'changed');
    check('GET /events (SSE, with a ticket) starts with the current seq', evB.status === 200 && firstChanged && Number.isInteger(firstChanged.seq));
    check('a ticket works once only', (await fetch(B.base + '/events?ticket=' + evB.ticket)).status === 401);
    const sentLive = await A.one('message.send', { message_id: uuid(), conversation_id: dmA, content: 'live!' });
    check('a member is told about a new op immediately', !!(await evB.waitFor((e) => e.type === 'changed' && e.seq === sentLive.seq)));
    const evA = await openEvents(A);
    check('presence: a co-member connecting shows active', !!(await evB.waitFor((e) => e.type === 'presence' && e.user_id === A.id && e.status === 'active')));
    check('presence: a new connection is told who is already active', !!(await evA.waitFor((e) => e.type === 'presence' && e.user_id === B.id && e.status === 'active')));
    evA.close();
    check('presence: disconnecting shows away', !!(await evB.waitFor((e) => e.type === 'presence' && e.user_id === A.id && e.status === 'away')));
    const D = new Client(base, 'dee@example.com', 'Dee Stranger'); await D.signup();
    const evD = await openEvents(D);
    await evD.waitFor((e) => e.type === 'changed');
    const privateOp = await A.one('message.send', { message_id: uuid(), conversation_id: dmA, content: 'only Ada and Bo can know about this' });
    await sleep(400);
    check('realtime never tells a stranger about an op they may not see', privateOp.status === 'applied' && !evD.events.some((e) => e.type === 'changed' && e.seq === privateOp.seq) && !evD.events.some((e) => e.type === 'presence'));
    check('...and their feed has nothing of it either', (await D.changes(0)).changes.every((e) => e.seq !== privateOp.seq));
    evD.close();
    const P1 = new Client(base, 'pat@example.com', 'Pat One'); await P1.signup();
    const P2 = new Client(base, 'quin@example.com', 'Quin Two'); await P2.signup();
    const evP1 = await openEvents(P1); const evP2 = await openEvents(P2);
    await sleep(200);
    check('presence: people who connected BEFORE becoming chat-mates hear about each other once they are', (!evP1.events.some((e) => e.type === 'presence')) && await (async () => {
      await P1.one('conversation.create', { conversation_id: uuid(), type: 'direct', member_ids: [P2.id] });
      return !!(await evP1.waitFor((e) => e.type === 'presence' && e.user_id === P2.id && e.status === 'active')) && !!(await evP2.waitFor((e) => e.type === 'presence' && e.user_id === P1.id && e.status === 'active'));
    })());
    evP1.close(); evP2.close();
    check('presence is never put in the log or feed', !JSON.stringify(await B.changes(0)).includes('presence'));

    // ── feed mechanics, link preview ──
    const page1 = await B.changes(0).then(async (all) => { const p = await B.json('GET', '/changes?since=0&limit=2'); return { all, p: p.body }; });
    check('GET /changes pages with has_more and next, in seq order', page1.p.changes.length === 2 && page1.p.has_more === true && page1.p.changes[0].seq < page1.p.changes[1].seq && page1.all.changes.every((e, i, a) => !i || e.seq > a[i - 1].seq));
    check('a cursor past the end is 410 cursor_expired', (await B.json('GET', '/changes?since=999999')).status === 410 && (await B.json('GET', '/changes?since=999999')).body.error.code === 'cursor_expired');
    check('/snapshot seq lines up with /changes (nothing missed between them)', await (async () => { const s = await B.snapshot(); const c = await B.changes(s.seq); return c.changes.length === 0; })());
    const lp = (await A.json('GET', '/link-preview?url=' + encodeURIComponent('https://www.edutopia.org/article/differentiated-instruction-strategies'))).body;
    check('link-preview returns the fixture, and the minimal card for anything else; junk is 400', lp.minimal === false && lp.site_name === 'Edutopia'
      && (await A.json('GET', '/link-preview?url=' + encodeURIComponent('https://example.org/x'))).body.minimal === true && (await A.json('GET', '/link-preview?url=notaurl')).status === 400);

    // ── password change, lookup, backfill on create/add (LIME-74 Phase 0) ──
    const lookup = (email) => new Client(base).json('POST', '/auth/lookup', { body: { email }, token: null }).then((r) => r.body && r.body.exists);
    check('POST /auth/lookup says whether an email has an account (dev phase)', (await lookup('bo@example.com')) === true && (await lookup('nobody-here@example.com')) === false);
    const dev2 = new Client(base, 'x', 'x'); dev2.device = 'second-device';
    const bSecond = await new Client(base).json('POST', '/auth/signin', { body: { email: 'bo@example.com', password: 'password123', device_id: 'second-device' }, token: null });
    check('change password: a wrong current password is 403, a short or unchanged one 400', (await B.json('POST', '/auth/password', { body: { current_password: 'nope-nope-1', new_password: 'newpassword1' } })).status === 403
      && (await B.json('POST', '/auth/password', { body: { current_password: 'password123', new_password: 'short' } })).status === 400 && (await B.json('POST', '/auth/password', { body: { current_password: 'password123', new_password: 'password123' } })).status === 400);
    const pw = await B.json('POST', '/auth/password', { body: { current_password: 'password123', new_password: 'newpassword1' } });
    check('change password: this device stays signed in, every OTHER device is signed out, the new password works and the old does not', pw.status === 200
      && (await B.json('GET', '/snapshot')).status === 200 && (await new Client(base).json('GET', '/snapshot', { token: bSecond.body.access_token })).status === 401
      && (await new Client(base).json('POST', '/auth/refresh', { body: { refresh_token: bSecond.body.refresh_token, device_id: 'second-device' }, token: null })).status === 401
      && (await new Client(base).json('POST', '/auth/signin', { body: { email: 'bo@example.com', password: 'newpassword1', device_id: 'third' }, token: null })).status === 200
      && (await new Client(base).json('POST', '/auth/signin', { body: { email: 'bo@example.com', password: 'password123', device_id: 'fourth' }, token: null })).status === 401);
    check('change password needs a signed-in person', (await new Client(base).json('POST', '/auth/password', { body: {}, token: null })).status === 401);
    const E1 = new Client(base, 'eve@example.com', 'Eve First'); await E1.signup();
    const gNew = uuid();
    await A.one('conversation.create', { conversation_id: gNew, type: 'group', name: 'Backfill test', member_ids: [E1.id] });
    const eFeed = await E1.changes(0);
    const createBackfill = eFeed.changes.find((e) => e.backfill && e.backfill.conversation && e.backfill.conversation.id === gNew);
    check('a new conversation: every member learns who is in it (conversation, members and their profiles)', createBackfill && createBackfill.backfill.profiles.some((p) => p.id === A.id && p.email === 'ada.new@example.com') && createBackfill.backfill.conversation_members.length === 2 && createBackfill.backfill.messages.length === 0);
    const F1 = new Client(base, 'fay@example.com', 'Fay Third'); await F1.signup();
    await A.one('membership.add', { conversation_id: gNew, user_ids: [F1.id] });
    const eFeed2 = await E1.changes(eFeed.next);
    const partial = eFeed2.changes.find((e) => e.backfill && !e.backfill.conversation);
    check('adding someone: existing members get a partial backfill with just the new person (member row and profile)', partial && partial.backfill.profiles.length === 1 && partial.backfill.profiles[0].id === F1.id && partial.backfill.conversation_members.length === 1 && !('phone' in partial.backfill.profiles[0]));
    const eveAlias = (await E1.changes(0)).changes.filter((e) => e.alias).length;
    check('and nobody outside the conversation hears of it', (await C.changes(0)).changes.every((e) => !(e.backfill && e.backfill.conversation && e.backfill.conversation.id === gNew)) && eveAlias === 0);

    // ── test accounts (only when the gitignored seed-data/test-accounts.local.json exists) ──
    let testFile = null;
    try { testFile = JSON.parse(fs.readFileSync(path.join(REPO_ROOT, 'seed-data', 'test-accounts.local.json'), 'utf8')); } catch (e) { /* none */ }
    if (testFile) {
      const [t1, t2] = testFile.accounts;
      const T1 = new Client(base, t1.email, t1.display_name); T1.device = 'tdev1';
      const si1 = await T1.json('POST', '/auth/signin', { body: { email: t1.email, password: testFile.password, device_id: 'tdev1' }, token: null });
      Object.assign(T1, { token: si1.body.access_token, id: t1.id });
      const ts = await T1.snapshot();
      const dmWithOther = ts.conversations.find((c) => c.type === 'direct' && ts.conversation_members.some((m) => m.conversation_id === c.id && m.user_id === t2.id));
      check('test accounts: both can sign in with the local file\'s password, and have each other\'s ready DM (no messages)', si1.status === 200 && dmWithOther && ts.messages.filter((m) => m.conversation_id === dmWithOther.id).length === 0);
      check('test accounts: both are members of PS 113 Staff Room', ts.conversations.some((c) => c.name === 'PS 113 Staff Room') && ts.conversation_members.some((m) => m.user_id === t2.id && ts.conversations.find((c) => c.id === m.conversation_id && c.name === 'PS 113 Staff Room')));
      check('test accounts: phone is stored and found by exact match, never shown', ts.profile.phone === t1.phone && !ts.profiles.some((p) => 'phone' in p) && (await dir(C, t1.phone.replace(/\D/g, ''))).profiles.some((p) => p.id === t1.id) && (await dir(C, t1.phone.replace(/\D/g, ''))).profiles.every((p) => !('phone' in p)));
      check('test accounts: their details are filled in plausibly', ts.profile.role && ts.profile.school === 'PS 113' && ts.profile.timezone === 'America/New_York' && ts.profile.bio);
    } else {
      check('test accounts (skipped: no seed-data/test-accounts.local.json here)', true, 'skipped');
    }

    // ── restart persistence ──
    const headBefore = (await A.json('GET', '/health')).body.seq;
    const snapBefore = await A.snapshot();
    await stopServer(server);
    server = await startServer(dataDir, port);
    const aAfter = new Client(server.base, 'ada.new@example.com', 'Ada Lovelace'); aAfter.device = 'dev-after';
    const siAfter = await aAfter.json('POST', '/auth/signin', { body: { email: 'ada.new@example.com', password: 'password123', device_id: 'dev-after' }, token: null });
    Object.assign(aAfter, { token: siAfter.body.access_token, id: A.id });
    const snapAfter = await aAfter.snapshot();
    check('graceful restart: the log head, accounts and every message survive', siAfter.status === 200 && snapAfter.seq === headBefore && snapAfter.messages.length === snapBefore.messages.length);
    check('graceful restart: access tokens issued before it still work', (await A.json('GET', '/snapshot')).status === 200);
    check('graceful restart: files survive and stay authorised', await B.download(up.body.file_id).then((r) => r.status === 200));
    const lastOp = aAfter.op('message.send', { message_id: 'msg-after-restart', conversation_id: dmA, content: 'written just before a crash' });
    const [last] = await aAfter.send(lastOp);
    await stopServer(server, 'SIGKILL'); // no chance to flush state.json: the server must rebuild from the log alone
    fs.rmSync(path.join(dataDir, 'state.json'), { force: true });
    server = await startServer(dataDir, port);
    const snapCrash = await (async () => { const c = new Client(server.base); const s = await c.json('POST', '/auth/signin', { body: { email: 'ada.new@example.com', password: 'password123', device_id: 'dev-after-2' }, token: null }); c.token = s.body.access_token; return c.snapshot(); })();
    check('after a hard kill with no state file, the state is rebuilt from the log (nothing lost)', last.status === 'applied' && snapCrash.messages.some((m) => m.id === 'msg-after-restart') && snapCrash.messages.length === snapBefore.messages.length + 1);
    const afterCrashClient = new Client(server.base); afterCrashClient.device = 'dev-after-2'; afterCrashClient.id = A.id;
    afterCrashClient.token = (await new Client(server.base).json('POST', '/auth/signin', { body: { email: 'ada.new@example.com', password: 'password123', device_id: 'dev-after-2' }, token: null })).body.access_token;
    const [replayed] = await afterCrashClient.send(lastOp);
    check('and the same op_id sent again after the crash is still a duplicate with the same seq', replayed.status === 'duplicate' && replayed.seq === last.seq);

    // ── dev reset ──
    const noHeader = await new Client(server.base).json('POST', '/dev/reset', { token: null });
    check('dev reset needs the X-Lime-Dev header (403 without)', noHeader.status === 403);
    const cursorBefore = (await A.json('GET', '/health')).body.seq;
    const reset = await fetch(server.base + '/api/v1/dev/reset', { method: 'POST', headers: { 'x-lime-dev': '1' } });
    check('dev reset wipes data and ends every session; old cursors expire', reset.status === 200 && (await new Client(server.base).json('GET', '/snapshot', { token: aAfter.token })).status === 401
      && (await fetch(server.base + '/api/v1/health').then((r) => r.json())).seq > cursorBefore);
    const signupAfterReset = await new Client(server.base, 'ada.new@example.com', 'Fresh Ada').signup();
    check('after a reset the same email can sign up again from scratch', signupAfterReset.status === 201);

    // ── seed teachers (only with the gitignored demo password file) ──
    let demoPassword = null;
    try { const src = fs.readFileSync(path.join(REPO_ROOT, 'public', 'js', 'demo-config.local.js'), 'utf8'); const m = /password:\s*'([^']*)'/.exec(src); demoPassword = m && m[1]; } catch (e) { /* none */ }
    if (demoPassword) {
      const jean = await new Client(server.base).json('POST', '/auth/signin', { body: { email: 'jean@chungrajoon.com', password: demoPassword, device_id: 'seed-1' }, token: null });
      check('a seed teacher signs in with the shared demo password', jean.status === 200 && jean.body.user.id === 'teacher-001');
      const jc = new Client(server.base); jc.token = jean.body.access_token; jc.id = 'teacher-001';
      const js = await jc.snapshot();
      check('a seed teacher\'s snapshot has their conversations, and no other person\'s phone', js.conversations.length > 0 && js.profiles.every((p) => !('phone' in p)));
    } else {
      check('seed-teacher sign-in (skipped: no public/js/demo-config.local.js here)', true, 'skipped');
    }
  } finally {
    try { server.proc.kill('SIGKILL'); } catch (e) { /* gone */ }
    fs.rmSync(dataDir, { recursive: true, force: true });
  }
}
