// Lime dev server (LIME-73): serves the repo root like the Python server did, plus the /api/v1 contract from
// docs/api.md. Node built-ins only. A development tool for the local network, NOT for the internet.
//
//   node server/dev-server.mjs [--port 8000] [--data ./data]
import http from 'node:http';
import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import { ApiError, E, mimeFor, isId, uuid } from './lib/util.mjs';
import { Engine } from './lib/engine.mjs';
import { Auth, checkSignup } from './lib/auth.mjs';
import { Files, MAX_FILE_BYTES, readBody, parseMultipartFile } from './lib/files.mjs';
import { loadSeed, loadDemoPassword } from './lib/seed.mjs';

const REPO_ROOT = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '..');
const arg = (name) => { const i = process.argv.indexOf('--' + name); return i > -1 ? process.argv[i + 1] : undefined; };
const PORT = Number(arg('port') || process.env.PORT || 8000);
const DATA_DIR = path.resolve(arg('data') || process.env.LIME_DATA_DIR || path.join(REPO_ROOT, 'data'));
const STATIC_DIRS = ['public', 'vendor']; // the only parts of the repo that are ever served
const JSON_LIMIT = 1024 * 1024;

// ── boot ──
const seedData = loadSeed(REPO_ROOT);
const demoPassword = loadDemoPassword(REPO_ROOT);
const files = new Files(DATA_DIR);
const engine = new Engine({ dataDir: DATA_DIR, seedLoader: () => seedData, files });
const auth = new Auth(DATA_DIR, demoPassword);
await auth.ensureSeedCredentials(engine.seedProfileIds.map((id) => engine.profiles.get(id)).filter(Boolean));
engine.emailChanged = (userId, oldEmail, newEmail) => auth.renameEmail(userId, oldEmail, newEmail);
files.sweep();
setInterval(() => files.sweep(), 60 * 60 * 1000).unref();

// ── realtime: SSE connections and presence ──
const connections = new Map(); // userId -> Set(res)
const sse = (res, data, id) => res.write((id != null ? 'id: ' + id + '\n' : '') + 'data: ' + JSON.stringify(data) + '\n\n');
function broadcastPresence(userId, status) {
  for (const other of engine.coMemberIds(userId)) {
    if (other === userId) continue;
    for (const res of connections.get(other) || []) sse(res, { type: 'presence', user_id: userId, status });
  }
}
engine.subscribe((entry) => {
  if (entry.audience === null) { for (const set of connections.values()) for (const res of set) sse(res, { type: 'changed', seq: entry.seq }, entry.seq); return; }
  for (const userId of entry.audience || []) for (const res of connections.get(userId) || []) sse(res, { type: 'changed', seq: entry.seq }, entry.seq);
});
setInterval(() => { for (const set of connections.values()) for (const res of set) res.write(': keep-alive\n\n'); }, 20000).unref();

function openEvents(req, res, userId) {
  res.writeHead(200, { 'Content-Type': 'text/event-stream', 'Cache-Control': 'no-cache', Connection: 'keep-alive', 'X-Accel-Buffering': 'no' });
  res.write('retry: 3000\n\n');
  const set = connections.get(userId) || new Set();
  connections.set(userId, set);
  const first = set.size === 0;
  set.add(res);
  sse(res, { type: 'changed', seq: engine.seq }, engine.seq); // tells a (re)connecting client where the log is now
  for (const other of engine.coMemberIds(userId)) if (other !== userId && connections.get(other) && connections.get(other).size) sse(res, { type: 'presence', user_id: other, status: 'active' });
  if (first) broadcastPresence(userId, 'active');
  req.on('close', () => {
    set.delete(res);
    if (set.size === 0) { connections.delete(userId); broadcastPresence(userId, 'away'); }
  });
}

// ── http helpers ──
function sendJson(res, status, body, headers) {
  const text = JSON.stringify(body);
  res.writeHead(status, Object.assign({ 'Content-Type': 'application/json; charset=utf-8', 'Cache-Control': 'no-store', 'X-Content-Type-Options': 'nosniff' }, headers));
  res.end(text);
}
const sendError = (res, e) => sendJson(res, e.status, { error: { code: e.code, message: e.message } }, e.retryAfter ? { 'Retry-After': String(e.retryAfter) } : undefined);

async function jsonBody(req) {
  const raw = await readBody(req, JSON_LIMIT);
  if (!raw.length) return {};
  try { const v = JSON.parse(raw.toString('utf8')); if (v === null || typeof v !== 'object') throw 0; return v; } catch (e) { throw E.badRequest('The request body must be a JSON object.'); }
}
function requireAuth(req) {
  const m = /^Bearer (.+)$/.exec(req.headers.authorization || '');
  if (!m) throw E.unauthenticated();
  return auth.verifyAccess(m[1]);
}

// ── /api/v1 ──
async function api(req, res, url) {
  const route = req.method + ' ' + url.pathname.replace(/^\/api\/v1/, '');
  switch (route) {
    case 'GET /health': return sendJson(res, 200, { ok: true, api: 'v1', seq: engine.seq });

    case 'POST /auth/signup': {
      const body = await jsonBody(req);
      checkSignup(body);
      const email = body.email.trim().toLowerCase();
      if (auth.hasEmail(email) || [...engine.profiles.values()].some((p) => (p.email || '').toLowerCase() === email)) throw E.conflict('That email is already in use.');
      const userId = uuid();
      await auth.createAccount(email, body.password, userId);
      const profile = engine.createProfile({ id: userId, email, display_name: body.display_name.trim() });
      const tokens = auth.tokensFor(userId, body.device_id);
      return sendJson(res, 201, Object.assign({ user: engine.profileFor(profile, userId) }, tokens, { seq: engine.seq }));
    }
    case 'POST /auth/signin': {
      const body = await jsonBody(req);
      if (typeof body.email !== 'string' || typeof body.password !== 'string' || !isId(body.device_id)) throw E.badRequest('email, password and device_id are required.');
      const userId = await auth.verify(body.email.trim().toLowerCase(), body.password);
      const profile = engine.profiles.get(userId);
      if (!profile) throw E.invalidCredentials();
      return sendJson(res, 200, Object.assign({ user: engine.profileFor(profile, userId) }, auth.tokensFor(userId, body.device_id), { seq: engine.seq }));
    }
    case 'POST /auth/refresh': {
      const body = await jsonBody(req);
      if (typeof body.refresh_token !== 'string' || !isId(body.device_id)) throw E.badRequest('refresh_token and device_id are required.');
      return sendJson(res, 200, auth.refresh(body.refresh_token, body.device_id).tokens);
    }
    case 'POST /auth/signout': {
      const { userId, deviceId } = requireAuth(req);
      auth.signOut(userId, deviceId);
      res.writeHead(204); return res.end();
    }

    case 'POST /ops': {
      const { userId } = requireAuth(req);
      const body = await jsonBody(req);
      if (!Array.isArray(body.ops) || body.ops.length === 0 || body.ops.length > 100) throw E.badRequest('ops must be a list of 1 to 100 ops.');
      const results = body.ops.map((op) => {
        const op_id = op && typeof op === 'object' ? op.op_id : undefined;
        try { return Object.assign({ op_id }, engine.processOp(op, userId)); } catch (e) {
          if (!(e instanceof ApiError)) throw e;
          return { op_id, status: 'rejected', error: { code: e.code, message: e.message } };
        }
      });
      return sendJson(res, 200, { results });
    }
    case 'GET /changes': {
      const { userId } = requireAuth(req);
      const since = url.searchParams.has('since') ? Number(url.searchParams.get('since')) : 0;
      const limit = url.searchParams.has('limit') ? Number(url.searchParams.get('limit')) : 200;
      if (!Number.isInteger(limit) || limit < 1) throw E.badRequest('limit must be a positive whole number.');
      return sendJson(res, 200, engine.changesFor(userId, since, Math.min(limit, 1000)));
    }
    case 'GET /snapshot': {
      const { userId } = requireAuth(req);
      return sendJson(res, 200, engine.snapshotFor(userId));
    }

    case 'POST /files': {
      const { userId } = requireAuth(req);
      const ct = req.headers['content-type'] || '';
      if (!/^multipart\/form-data/i.test(ct)) throw E.badRequest('Expected multipart/form-data.');
      const body = await readBody(req, MAX_FILE_BYTES + 64 * 1024);
      const part = parseMultipartFile(body, ct);
      if (part.bytes.length > MAX_FILE_BYTES) throw E.tooLarge();
      if (part.bytes.length === 0) throw E.badRequest('That file is empty.');
      const meta = files.create({ uploader: userId, name: part.name, mime: part.mime, bytes: part.bytes });
      return sendJson(res, 201, { file_id: meta.file_id, size: meta.size, mime: meta.mime, name: meta.name });
    }
    case 'POST /events/ticket': {
      const { userId, deviceId } = requireAuth(req);
      return sendJson(res, 200, { ticket: auth.issueTicket(userId, deviceId), expires_in: 60 });
    }
    case 'GET /events': {
      let userId;
      if (url.searchParams.has('ticket')) userId = auth.redeemTicket(url.searchParams.get('ticket')).userId;
      else userId = requireAuth(req).userId;
      return openEvents(req, res, userId);
    }
    case 'GET /profiles': {
      const { userId } = requireAuth(req);
      return sendJson(res, 200, { profiles: engine.searchProfiles(userId, url.searchParams.get('q')) });
    }
    case 'GET /link-preview': {
      requireAuth(req);
      let target;
      try { target = new URL(url.searchParams.get('url') || ''); } catch (e) { throw E.badRequest('url must be an absolute http or https URL.'); }
      if (target.protocol !== 'http:' && target.protocol !== 'https:') throw E.badRequest('url must be an absolute http or https URL.');
      return sendJson(res, 200, await seedData.linkPreview(target.href));
    }
    case 'POST /dev/reset': {
      if (req.headers['x-lime-dev'] !== '1') throw E.forbidden('Send the header X-Lime-Dev: 1 to confirm a dev reset.');
      engine.reset(); auth.reset(); files.reset();
      await auth.ensureSeedCredentials(engine.seedProfileIds.map((id) => engine.profiles.get(id)).filter(Boolean));
      for (const set of connections.values()) for (const r of set) r.end();
      connections.clear();
      return sendJson(res, 200, { ok: true, seq: engine.seq });
    }
    default: {
      const m = /^GET \/files\/([A-Za-z0-9._:-]{1,80})$/.exec(route);
      if (m) return downloadFile(req, res, requireAuth(req).userId, m[1]);
      throw E.notFound('No such endpoint.');
    }
  }
}

// Authorised download. Only inert types are shown inline; anything else is forced to download and sandboxed,
// so an uploaded .html can never run as part of the app.
function serveBytes(req, res, file, size, mime, extraHeaders) {
  const headers = Object.assign({ 'Content-Type': mime, 'Accept-Ranges': 'bytes', 'X-Content-Type-Options': 'nosniff' }, extraHeaders);
  const range = /^bytes=(\d*)-(\d*)$/.exec(req.headers.range || '');
  if (range && (range[1] || range[2])) {
    let start = range[1] === '' ? size - Number(range[2]) : Number(range[1]);
    let end = range[1] === '' || range[2] === '' ? size - 1 : Math.min(Number(range[2]), size - 1);
    if (start < 0) start = 0;
    if (start >= size || start > end) { res.writeHead(416, { 'Content-Range': 'bytes */' + size }); return res.end(); }
    res.writeHead(206, Object.assign(headers, { 'Content-Range': `bytes ${start}-${end}/${size}`, 'Content-Length': end - start + 1 }));
    return req.method === 'HEAD' ? res.end() : fs.createReadStream(file, { start, end }).pipe(res);
  }
  res.writeHead(200, Object.assign(headers, { 'Content-Length': size }));
  return req.method === 'HEAD' ? res.end() : fs.createReadStream(file).pipe(res);
}

function downloadFile(req, res, userId, id) {
  const meta = files.get(id);
  if (!meta || !engine.canReadFile(userId, meta)) throw E.notFound('That file does not exist.'); // not allowed looks the same as not there
  const inline = /^(image\/(png|jpe?g|gif|webp)|audio\/|video\/|application\/pdf)/i.test(meta.mime);
  const name = encodeURIComponent(meta.name || 'file');
  return serveBytes(req, res, files.pathFor(id), meta.size, inline ? meta.mime : 'application/octet-stream', {
    'Content-Disposition': (inline ? 'inline' : 'attachment') + "; filename*=UTF-8''" + name,
    'Content-Security-Policy': 'sandbox', 'Cache-Control': 'private, max-age=300',
  });
}

// ── static files ──
function serveStatic(req, res, url) {
  let rel;
  try { rel = decodeURIComponent(url.pathname); } catch (e) { res.writeHead(400); return res.end('Bad request'); }
  if (rel === '/') { res.writeHead(302, { Location: '/public/index.html' }); return res.end(); }
  const parts = rel.split('/').filter(Boolean);
  if (parts.some((p) => p === '..' || p.startsWith('.') || p.includes('\0')) || !STATIC_DIRS.includes(parts[0])) { res.writeHead(404); return res.end('Not found'); }
  let file = path.join(REPO_ROOT, ...parts);
  if (!file.startsWith(REPO_ROOT + path.sep)) { res.writeHead(404); return res.end('Not found'); }
  let stat;
  try { stat = fs.statSync(file); if (stat.isDirectory()) { file = path.join(file, 'index.html'); stat = fs.statSync(file); } } catch (e) { res.writeHead(404); return res.end('Not found'); }
  const mime = mimeFor(file);
  const live = /^(text\/html|text\/css|text\/javascript)/.test(mime);
  return serveBytes(req, res, file, stat.size, mime, { 'Cache-Control': live ? 'no-cache' : 'public, max-age=300', 'Last-Modified': stat.mtime.toUTCString() });
}

const server = http.createServer(async (req, res) => {
  const url = new URL(req.url, 'http://localhost');
  try {
    if (url.pathname === '/api/v1' || url.pathname.startsWith('/api/v1/')) return await api(req, res, url);
    if (req.method !== 'GET' && req.method !== 'HEAD') { res.writeHead(405, { Allow: 'GET, HEAD' }); return res.end(); }
    return serveStatic(req, res, url);
  } catch (e) {
    if (e instanceof ApiError) return res.headersSent ? res.end() : sendError(res, e);
    console.error('[server] unexpected error on ' + req.method + ' ' + url.pathname + ':', e);
    if (!res.headersSent) return sendJson(res, 500, { error: { code: 'server_error', message: 'Something went wrong on the server.' } });
    res.end();
  }
});
server.requestTimeout = 5 * 60 * 1000;

server.on('error', (e) => {
  if (e.code === 'EADDRINUSE') {
    console.error(`\nPort ${PORT} is already in use. Is the Python server (or another Lime server) still running?\nStop it, or start this one elsewhere: node server/dev-server.mjs --port 8001\n`);
  } else console.error('Server error:', e);
  process.exit(1);
});

server.listen(PORT, '0.0.0.0', () => {
  const lan = Object.values(os.networkInterfaces()).flat().filter((i) => i && i.family === 'IPv4' && !i.internal).map((i) => i.address);
  console.log('\nLime dev server (not for the internet)');
  console.log(`  This computer:  http://localhost:${PORT}/public/index.html`);
  for (const ip of lan) console.log(`  On your network: http://${ip}:${PORT}/public/index.html   (phones on the same Wi-Fi)`);
  console.log(`  API:            http://localhost:${PORT}/api/v1/health`);
  console.log(`  Data folder:    ${DATA_DIR}`);
  if (!demoPassword) console.log('  Note: public/js/demo-config.local.js not found, so seed teachers cannot sign in to the API until one exists and the data is reset.');
  console.log('');
});

function shutdown() { try { engine.persistStateNow(); } catch (e) { /* best effort */ } process.exit(0); }
process.on('SIGINT', shutdown);
process.on('SIGTERM', shutdown);
