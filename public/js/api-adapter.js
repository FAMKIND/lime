'use strict';

// ApiAdapter (LIME-74) — the web app's side of docs/api.md. When the page is served by server/dev-server.mjs, the store keeps
// a local copy of the data (works offline, reloads instantly) and talks to /api/v1 in the background:
//
//   confirmed state  = everything the server has told us, up to `cursor`
//   outbox           = ops this device made that the server has not yet confirmed through the feed
//   view             = confirmed + outbox applied on top (what the UI reads, so a write shows instantly)
//
// A write becomes an op, is applied to the view at once and queued; the queue is sent to POST /ops in order, retrying the
// same op_ids. The server's feed (GET /changes, nudged by realtime events) is applied to the confirmed state, which also
// confirms our own ops. A permanent rejection removes the op and rebuilds the view, which is the rollback.
// Rows are never mutated, only replaced (copy-on-write), so a changed row is simply a different object.
//
// LimeBackend decides which backend a page uses; with no dev server (python server, file://) everything stays local.

const LimeBackend = (function () {
  let mode = 'local';
  const ready = (async function detect() {
    if (typeof fetch !== 'function' || location.protocol === 'file:') return finish('local');
    try {
      const ctl = typeof AbortController === 'function' ? new AbortController() : null;
      const timer = ctl ? setTimeout(() => ctl.abort(), 2500) : null;
      const res = await fetch('/api/v1/health', { signal: ctl ? ctl.signal : undefined, cache: 'no-store' });
      if (timer) clearTimeout(timer);
      if (res.ok && (await res.json()).api === 'v1') return finish('api');
    } catch (e) { /* no API here */ }
    return finish('local');
  })();

  function finish(m) {
    mode = m;
    try { console.log('[Lime] storage backend: ' + (m === 'api' ? 'ApiAdapter (dev server, shared data)' : 'LocalAdapter (this browser only)')); } catch (e) { /* no console */ }
    if (m === 'local' && typeof document !== 'undefined' && document.createElement && typeof navigator !== 'undefined' && navigator.userAgent.indexOf('jsdom') === -1) {
      // The local demo sign-in needs the (gitignored) demo password file; the API never does (the server verifies).
      const s = document.createElement('script');
      s.src = 'js/demo-config.local.js';
      document.head.appendChild(s);
    }
    return m;
  }
  return { get mode() { return mode; }, ready, isApi: () => mode === 'api' };
})();
window.LimeBackend = LimeBackend;

const ApiAdapter = (function () {
  const API = '/api/v1';
  const SESSION_KEY = 'lime-api-session';
  const DEVICE_KEY = 'lime-device-id';
  const CACHE_PREFIX = 'lime-api-cache:';
  const OUTBOX_PREFIX = 'lime-outbox:';
  const TABLES = ['profiles', 'conversations', 'conversation_members', 'messages', 'message_reactions', 'message_attachments'];
  const keyOf = {
    profiles: (r) => r.id,
    conversations: (r) => r.id,
    conversation_members: (r) => r.conversation_id + '|' + r.user_id,
    messages: (r) => r.id,
    message_reactions: (r) => r.message_id + '|' + r.user_id + '|' + r.emoji,
    message_attachments: (r) => r.id,
  };
  const PERMANENT = ['forbidden', 'invalid_op', 'not_found', 'conflict', 'unsupported_op', 'bad_request'];

  class ApiError extends Error {
    constructor(status, code, message) { super(message); this.status = status; this.code = code; }
  }

  // ── ids ──
  function uuidv7() {
    const b = crypto.getRandomValues(new Uint8Array(16));
    let ts = Date.now();
    for (let i = 5; i >= 0; i--) { b[i] = ts % 256; ts = Math.floor(ts / 256); }
    b[6] = (b[6] & 0x0f) | 0x70;
    b[8] = (b[8] & 0x3f) | 0x80;
    const h = Array.from(b, (x) => x.toString(16).padStart(2, '0')).join('');
    return h.slice(0, 8) + '-' + h.slice(8, 12) + '-' + h.slice(12, 16) + '-' + h.slice(16, 20) + '-' + h.slice(20);
  }

  // ── session (tokens per tab in sessionStorage; the device id per browser in localStorage) ──
  function deviceId() {
    try {
      let id = localStorage.getItem(DEVICE_KEY);
      if (!id) { id = 'web-' + crypto.randomUUID(); localStorage.setItem(DEVICE_KEY, id); }
      return id;
    } catch (e) { return 'web-volatile'; }
  }
  function readSession() {
    try { return JSON.parse(sessionStorage.getItem(SESSION_KEY) || 'null'); } catch (e) { return null; }
  }
  function writeSession(s) {
    sessionStorage.setItem(SESSION_KEY, JSON.stringify(s));
    // The same { userId, email } the session gate and LimeStore already read.
    sessionStorage.setItem('lime-demo-session', JSON.stringify({ userId: s.userId, email: s.email }));
  }
  function clearSession() {
    try { sessionStorage.removeItem(SESSION_KEY); sessionStorage.removeItem('lime-demo-session'); } catch (e) { /* nothing */ }
  }

  // ── http ──
  let refreshing = null;
  let hooks = {}; // set by the store: onViewChanged, onRejected, onAlias, onPresence, onSessionEnded, onSyncState

  async function rawFetch(method, path, { body, headers, token, keepalive } = {}) {
    const h = Object.assign({}, headers);
    if (token) h.authorization = 'Bearer ' + token;
    let payload = body;
    if (body && !(body instanceof FormData)) { payload = JSON.stringify(body); h['content-type'] = 'application/json'; }
    let res;
    const send = () => fetch(API + path, { method, headers: h, body: payload, keepalive: !!keepalive, cache: 'no-store' });
    try { res = await send(); } catch (e) {
      // A browser can lose a request to a connection the server had just closed. Sign-in/sign-up/refresh/reset are safe to
      // send once more; ops are retried by the outbox with the same op_ids anyway.
      if (/^\/(auth\/|dev\/)/.test(path)) { try { res = await send(); } catch (e2) { res = null; } }
      if (!res) throw new ApiError(0, 'offline', 'Can’t reach Lime right now. Check your connection and try again.');
    }
    return res;
  }
  async function toJson(res) {
    let data = null;
    try { data = await res.json(); } catch (e) { /* no body (204) */ }
    if (!res.ok) {
      const err = data && data.error ? data.error : { code: 'server_error', message: 'Something went wrong. Try again.' };
      throw new ApiError(res.status, err.code, err.message);
    }
    return data;
  }

  async function refreshTokens() {
    if (refreshing) return refreshing;
    refreshing = (async () => {
      const s = readSession();
      if (!s || !s.refresh_token) throw new ApiError(401, 'unauthenticated', 'Sign in again.');
      const res = await rawFetch('POST', '/auth/refresh', { body: { refresh_token: s.refresh_token, device_id: deviceId() } });
      const data = await toJson(res);
      Object.assign(s, { access_token: data.access_token, refresh_token: data.refresh_token, expires_at: Date.now() + data.expires_in * 1000 - 30000 });
      writeSession(s);
      return s;
    })();
    try { return await refreshing; } finally { refreshing = null; }
  }

  // An authenticated request: refreshes the access token when it is about to expire (or after a 401), once.
  async function http(method, path, opts) {
    const o = opts || {};
    let s = readSession();
    if (!s) throw new ApiError(401, 'unauthenticated', 'Sign in to continue.');
    try {
      if (s.expires_at && s.expires_at < Date.now() + 5000) s = await refreshTokens();
    } catch (e) { if (e.code === 'offline') throw e; return sessionEnded(e); }
    let res = await rawFetch(method, path, Object.assign({}, o, { token: s.access_token }));
    if (res.status === 401) {
      try { s = await refreshTokens(); } catch (e) { if (e.code === 'offline') throw e; return sessionEnded(e); }
      res = await rawFetch(method, path, Object.assign({}, o, { token: s.access_token }));
      if (res.status === 401) return sessionEnded(new ApiError(401, 'unauthenticated', 'Sign in again.'));
    }
    if (o.raw) return res;
    return toJson(res);
  }

  // Tokens no longer work and cannot be refreshed: either another device signed us out, or the dev server was reset.
  let endedHandled = false;
  async function sessionEnded(err) {
    if (!endedHandled) {
      endedHandled = true;
      let kind = 'signed_out';
      try {
        const h = await (await fetch(API + '/health', { cache: 'no-store' })).json();
        if (sync && Number.isInteger(h.log_start) && h.log_start > sync.cursor) kind = 'reset';
      } catch (e) { /* server unreachable: treat as signed out */ }
      if (hooks.onSessionEnded) hooks.onSessionEnded(kind);
    }
    throw err;
  }

  // ── accounts ──
  async function authCall(path, body) {
    const res = await rawFetch('POST', path, { body: Object.assign({ device_id: deviceId() }, body) });
    return toJson(res);
  }
  function startSession(data, email) {
    endedHandled = false;
    writeSession({ userId: data.user.id, email: (data.user.email || email || '').toLowerCase(), access_token: data.access_token, refresh_token: data.refresh_token, expires_at: Date.now() + data.expires_in * 1000 - 30000 });
    return { userId: data.user.id, email: data.user.email || email, displayName: data.user.display_name };
  }
  const signUp = (email, password, displayName) => authCall('/auth/signup', { email, password, display_name: displayName }).then((d) => startSession(d, email));
  const signIn = (email, password) => authCall('/auth/signin', { email, password }).then((d) => startSession(d, email));
  const accountExists = (email) => rawFetch('POST', '/auth/lookup', { body: { email } }).then(toJson).then((d) => !!d.exists);
  const changePassword = (current, next) => http('POST', '/auth/password', { body: { current_password: current, new_password: next } });
  function signOut() {
    const s = readSession();
    if (s && s.access_token) { try { fetch(API + '/auth/signout', { method: 'POST', headers: { authorization: 'Bearer ' + s.access_token }, keepalive: true }); } catch (e) { /* best effort */ } }
    stop();
    clearSession();
  }

  // ── state ──
  function emptyState() {
    const s = {};
    TABLES.forEach((t) => { s[t] = new Map(); });
    return s;
  }
  const shallowClone = (state) => { const c = {}; TABLES.forEach((t) => { c[t] = new Map(state[t]); }); return c; };
  const rowsOf = (state) => { const o = {}; TABLES.forEach((t) => { o[t] = [...state[t].values()]; }); return o; };
  function fromRows(rows) {
    const s = emptyState();
    TABLES.forEach((t) => (rows[t] || []).forEach((r) => s[t].set(keyOf[t](r), r)));
    return s;
  }
  function put(state, table, row, touched) {
    const k = keyOf[table](row);
    state[table].set(k, row);
    if (touched) touched.push({ table, key: k });
  }

  // The op applier: what an op does to the data. The same function is used for our own queued ops (optimistic, ctx.pending)
  // and for the server's feed (confirmed). Mirrors server/lib/engine.mjs. Never throws on rows we do not have.
  function applyOp(state, op, ctx) {
    const p = op.payload || {};
    const ts = ctx.ts;
    const touched = ctx.touched;
    const memberKey = (c, u) => c + '|' + u;
    const myMember = (convId) => state.conversation_members.get(memberKey(convId, op.actor_id));
    switch (op.type) {
      case 'message.send': {
        if (!state.conversations.has(p.conversation_id) || state.messages.has(p.message_id)) return;
        const msg = {
          id: p.message_id, conversation_id: p.conversation_id, sender_id: op.actor_id, content: p.content == null ? null : p.content, type: 'text',
          metadata: p.metadata || null, reply_to: p.reply_to || null, created_at: ts, updated_at: ts, client_ts: op.client_ts || ts,
        };
        if (ctx.pending) msg._pending = true;
        put(state, 'messages', msg, touched);
        (p.attachments || []).forEach((a, i) => put(state, 'message_attachments', {
          id: a.attachment_id, message_id: msg.id, path: a.file_id, name: a.name == null ? null : a.name, size: a.size == null ? null : a.size,
          mime: a.mime == null ? null : a.mime, width: a.width == null ? null : a.width, height: a.height == null ? null : a.height,
          duration_seconds: a.duration_seconds == null ? null : a.duration_seconds, position: a.position == null ? i : a.position, created_at: ts,
        }, touched));
        return;
      }
      case 'reaction.toggle': {
        const msg = state.messages.get(p.message_id);
        if (!msg) return;
        const k = p.message_id + '|' + op.actor_id + '|' + p.emoji;
        const row = state.message_reactions.get(k);
        if (p.present) put(state, 'message_reactions', row ? Object.assign({}, row, { removed_at: null, updated_at: ts }) : { message_id: p.message_id, user_id: op.actor_id, emoji: p.emoji, created_at: ts, updated_at: ts, removed_at: null }, touched);
        else if (row && !row.removed_at) put(state, 'message_reactions', Object.assign({}, row, { removed_at: ts, updated_at: ts }), touched);
        return;
      }
      case 'conversation.create': {
        if (state.conversations.has(p.conversation_id)) return;
        const others = [...new Set(p.member_ids || [])].filter((u) => u !== op.actor_id);
        const dmKey = p.type === 'direct' ? [op.actor_id, others[0]].sort().join(':') : null;
        put(state, 'conversations', { id: p.conversation_id, type: p.type, name: p.name || null, description: p.description || null, created_by: op.actor_id, deleted_at: null, dm_key: dmKey, created_at: ts, updated_at: ts }, touched);
        [op.actor_id].concat(others).forEach((u) => put(state, 'conversation_members', { conversation_id: p.conversation_id, user_id: u, role: u === op.actor_id ? 'owner' : 'member', starred: false, archived_at: null, cleared_at: null, last_read_at: null, joined_at: ts, updated_at: ts }, touched));
        return;
      }
      case 'conversation.rename': case 'conversation.delete': {
        const c = state.conversations.get(p.conversation_id);
        if (!c) return;
        put(state, 'conversations', op.type === 'conversation.rename' ? Object.assign({}, c, { name: p.name, updated_at: ts }) : Object.assign({}, c, { deleted_at: ts, updated_at: ts }), touched);
        return;
      }
      case 'conversation.deleteForMe': case 'membership.setStarred': case 'membership.setArchived': case 'membership.markRead': {
        const m = myMember(p.conversation_id);
        if (!m) return;
        const next = Object.assign({}, m, { updated_at: ts });
        if (op.type === 'conversation.deleteForMe') next.cleared_at = ts;
        else if (op.type === 'membership.setStarred') next.starred = !!p.starred;
        else if (op.type === 'membership.setArchived') next.archived_at = p.archived ? ts : null;
        else if (!m.last_read_at || ts > m.last_read_at) next.last_read_at = ts;
        else return;
        put(state, 'conversation_members', next, touched);
        return;
      }
      case 'membership.add': {
        const c = state.conversations.get(p.conversation_id);
        if (!c) return;
        (p.user_ids || []).forEach((u) => {
          if (state.conversation_members.has(memberKey(c.id, u))) return;
          put(state, 'conversation_members', { conversation_id: c.id, user_id: u, role: 'member', starred: false, archived_at: null, cleared_at: null, last_read_at: null, joined_at: ts, updated_at: ts }, touched);
        });
        put(state, 'conversations', Object.assign({}, c, { updated_at: ts }), touched);
        return;
      }
      case 'profile.update': {
        const row = state.profiles.get(op.actor_id);
        if (row) put(state, 'profiles', Object.assign({}, row, p.patch, { updated_at: ts }), touched);
        return;
      }
      case 'profile.setEmail': {
        const row = state.profiles.get(op.actor_id);
        if (row) put(state, 'profiles', Object.assign({}, row, { email: String(p.email).trim().toLowerCase(), updated_at: ts }), touched);
        return;
      }
      default:
    }
  }

  // A backfill entry (or part of one): rows to merge in by key.
  function mergeBackfill(state, bf) {
    const m = (table, rows) => (rows || []).forEach((r) => {
      const k = keyOf[table](r);
      const mine = state[table].get(k);
      // Never replace our own full member row with the stripped copy of it, and never lose an email we already know.
      state[table].set(k, mine && table === 'profiles' ? Object.assign({}, mine, r) : r);
    });
    if (bf.conversation) m('conversations', [bf.conversation]);
    m('conversation_members', bf.conversation_members);
    m('profiles', bf.profiles);
    m('messages', bf.messages);
    m('message_reactions', bf.message_reactions);
    m('message_attachments', bf.message_attachments);
  }

  // ── the sync engine for one signed-in person ──
  let sync = null;

  function persistSoon() {
    if (!sync || sync.persistTimer) return;
    sync.persistTimer = setTimeout(persistNow, 300);
  }
  function persistNow() {
    if (!sync) return;
    clearTimeout(sync.persistTimer); sync.persistTimer = null;
    try {
      const rows = rowsOf(sync.confirmed);
      rows.messages = rows.messages.map((m) => { const c = Object.assign({}, m); delete c._pending; return c; });
      localStorage.setItem(CACHE_PREFIX + sync.userId, JSON.stringify({ cursor: sync.cursor, rows }));
    } catch (e) {
      try { document.dispatchEvent(new CustomEvent('lime:storage-failed')); } catch (e2) { /* no document */ }
    }
  }
  const persistOutboxEntry = (e) => { try { localStorage.setItem(OUTBOX_PREFIX + sync.userId + ':' + e.op.op_id, JSON.stringify(e.op)); } catch (err) { /* in memory only */ } };
  const forgetOutboxEntry = (e) => { try { localStorage.removeItem(OUTBOX_PREFIX + sync.userId + ':' + e.op.op_id); } catch (err) { /* nothing */ } };
  function loadPersistedOutbox(userId) {
    const out = [];
    try {
      for (let i = 0; i < localStorage.length; i++) {
        const k = localStorage.key(i);
        if (k && k.indexOf(OUTBOX_PREFIX + userId + ':') === 0) { try { out.push({ op: JSON.parse(localStorage.getItem(k)), state: 'queued' }); } catch (e) { /* skip */ } }
      }
    } catch (e) { /* none */ }
    return out.sort((a, b) => (a.op.op_id < b.op.op_id ? -1 : 1)); // UUIDv7 sorts by creation time
  }
  function clearAllLocalData() {
    try {
      const doomed = [];
      for (let i = 0; i < localStorage.length; i++) { const k = localStorage.key(i); if (k && (k.indexOf(CACHE_PREFIX) === 0 || k.indexOf(OUTBOX_PREFIX) === 0)) doomed.push(k); }
      doomed.forEach((k) => localStorage.removeItem(k));
    } catch (e) { /* nothing */ }
  }

  // The view: confirmed state with every unconfirmed op of ours applied on top.
  function buildView() {
    const view = shallowClone(sync.confirmed);
    sync.outbox.forEach((e) => {
      if (e.aliasedTo && e.op.type === 'conversation.create') return; // the server kept another conversation for this pair
      applyOp(view, e.op, { ts: e.op.client_ts, pending: true });
    });
    return view;
  }
  function changedBetween(before, after) {
    const changed = {};
    TABLES.forEach((t) => {
      const set = new Set();
      after[t].forEach((row, k) => { if (before[t].get(k) !== row) set.add(k); });
      before[t].forEach((row, k) => { if (!after[t].has(k)) set.add(k); });
      changed[t] = set;
    });
    return changed;
  }
  const anyChange = (changed) => TABLES.some((t) => changed[t].size > 0);
  function rebuildAndAnnounce() {
    const before = sync.view;
    sync.view = buildView();
    const changed = changedBetween(before, sync.view);
    if (anyChange(changed) && hooks.onViewChanged) hooks.onViewChanged(changed, { remote: true });
    persistSoon();
  }

  function handleAlias(from, to) {
    if (!from || !to || from === to) return;
    sync.outbox.forEach((e) => {
      if (e.op.type === 'conversation.create' && e.op.payload.conversation_id === from) { e.aliasedTo = to; return; }
      if (e.op.payload && e.op.payload.conversation_id === from) {
        e.op = Object.assign({}, e.op, { payload: Object.assign({}, e.op.payload, { conversation_id: to }) });
        persistOutboxEntry(e);
      }
    });
    if (hooks.onAlias) hooks.onAlias(from, to);
  }

  function applyFeed(entries) {
    entries.forEach((entry) => {
      if (entry.op) {
        applyOp(sync.confirmed, entry.op, { ts: entry.server_ts, pending: false });
        const mine = sync.outbox.findIndex((e) => e.op.op_id === entry.op.op_id);
        if (mine > -1) {
          const e = sync.outbox[mine];
          sync.outbox.splice(mine, 1);
          forgetOutboxEntry(e);
          if (e.waiter) e.waiter.resolve({ status: 'applied', seq: entry.seq });
        }
      } else if (entry.backfill) mergeBackfill(sync.confirmed, entry.backfill);
      else if (entry.alias) handleAlias(entry.alias.from, entry.alias.to);
    });
  }

  async function loadSnapshot() {
    const snap = await http('GET', '/snapshot');
    const rows = { profiles: [snap.profile].concat(snap.profiles), conversations: snap.conversations, conversation_members: snap.conversation_members, messages: snap.messages, message_reactions: snap.message_reactions, message_attachments: snap.message_attachments };
    sync.confirmed = fromRows(rows);
    sync.cursor = snap.seq;
  }

  // ── flushing the outbox ──
  async function flush() {
    if (!sync) return;
    if (sync.flushing) { sync.flushAgain = true; return; }
    const s = sync; // sign-out can end the session while a request is in flight
    s.flushing = true;
    try {
      for (;;) {
        const batch = sync.outbox.filter((e) => e.state === 'queued').slice(0, 50);
        if (!batch.length) break;
        let res;
        try { res = await http('POST', '/ops', { body: { device_id: deviceId(), ops: batch.map((e) => e.op) } }); } catch (err) {
          if (err.code === 'offline' || err.status >= 500 || err.status === 429) { scheduleRetry(); } else if (err.code !== 'unauthenticated') { console.error('[Lime] sending changes failed', err); scheduleRetry(); }
          return;
        }
        sync.retryDelay = 1000;
        let rolledBack = false;
        res.results.forEach((r, i) => {
          const e = batch[i];
          if (!e || !sync.outbox.includes(e)) return;
          if (r.status === 'applied' || r.status === 'duplicate') {
            e.state = 'sent';
            if (r.canonical_conversation_id && r.canonical_conversation_id !== e.op.payload.conversation_id) handleAlias(e.op.payload.conversation_id, r.canonical_conversation_id);
            if (e.waiter) { const w = e.waiter; e.waiter = null; sync.waiters.push({ w, r }); }
          } else if (r.status === 'rejected') {
            if (PERMANENT.indexOf(r.error.code) > -1) {
              sync.outbox.splice(sync.outbox.indexOf(e), 1);
              forgetOutboxEntry(e);
              rolledBack = true;
              if (e.waiter) e.waiter.reject(new ApiError(400, r.error.code, r.error.message));
              else if (hooks.onRejected) hooks.onRejected(e.op, r.error);
            }
          }
        });
        if (rolledBack) rebuildAndAnnounce();
        sync.waiters.splice(0).forEach(({ w, r }) => w.resolve(r));
        pull();
      }
    } finally {
      s.flushing = false;
      if (s.flushAgain && sync === s) { s.flushAgain = false; flush(); }
    }
  }
  function scheduleRetry() {
    if (!sync || sync.retryTimer) return;
    sync.retryTimer = setTimeout(() => { if (sync) { sync.retryTimer = null; flush(); } }, sync.retryDelay);
    sync.retryDelay = Math.min(sync.retryDelay * 2, 30000);
  }

  // ── pulling the feed ──
  async function pull() {
    if (!sync) return;
    if (sync.pulling) { sync.pullAgain = true; return; }
    const s = sync;
    s.pulling = true;
    try {
      for (;;) {
        let r;
        try { r = await http('GET', '/changes?since=' + sync.cursor + '&limit=500'); } catch (err) {
          if (err.status === 410) await cursorExpired();
          return;
        }
        if (sync !== s) return; // signed out meanwhile
        if (r.changes.length) applyFeed(r.changes);
        sync.cursor = r.next;
        rebuildAndAnnounce();
        setSyncState(true);
        if (!r.has_more) break;
      }
    } finally {
      s.pulling = false;
      if (s.pullAgain && sync === s) { s.pullAgain = false; pull(); }
    }
  }
  async function cursorExpired() {
    let reset = false;
    try { const h = await (await fetch(API + '/health', { cache: 'no-store' })).json(); reset = Number.isInteger(h.log_start) && h.log_start > sync.cursor; } catch (e) { /* unreachable */ }
    if (reset) { if (hooks.onSessionEnded) hooks.onSessionEnded('reset'); return; }
    try { await loadSnapshot(); rebuildAndAnnounce(); } catch (e) { /* retried on the next poll */ }
  }
  function setSyncState(online) {
    if (sync && sync.online !== online) { sync.online = online; if (hooks.onSyncState) hooks.onSyncState(online); }
  }

  // ── realtime ──
  async function connectEvents() {
    if (!sync || sync.es || sync.connecting || typeof EventSource !== 'function') return;
    sync.connecting = true;
    try {
      const t = await http('POST', '/events/ticket');
      const es = new EventSource(API + '/events?ticket=' + encodeURIComponent(t.ticket));
      sync.es = es;
      es.onopen = () => { if (sync) { sync.eventsDelay = 1000; pull(); flush(); } };
      es.onmessage = (ev) => {
        let m; try { m = JSON.parse(ev.data); } catch (e) { return; }
        if (m.type === 'changed') pull();
        else if (m.type === 'presence' && hooks.onPresence) hooks.onPresence(m.user_id, m.status);
      };
      es.onerror = () => { es.close(); if (sync && sync.es === es) { sync.es = null; setSyncState(false); scheduleReconnect(); } };
    } catch (e) { scheduleReconnect(); } finally { if (sync) sync.connecting = false; }
  }
  function scheduleReconnect() {
    if (!sync || sync.reconnectTimer) return;
    sync.reconnectTimer = setTimeout(() => { if (sync) { sync.reconnectTimer = null; connectEvents(); } }, sync.eventsDelay);
    sync.eventsDelay = Math.min(sync.eventsDelay * 2, 30000);
  }
  function onOnline() { if (sync) { connectEvents(); flush(); pull(); } }
  function onVisible() { if (sync && document.visibilityState === 'visible') { pull(); flush(); connectEvents(); } }
  function onPageHide() { if (sync) { persistNow(); } }

  function stop() {
    if (!sync) return;
    persistNow();
    clearTimeout(sync.retryTimer); clearTimeout(sync.reconnectTimer); clearInterval(sync.pollTimer);
    if (sync.es) sync.es.close();
    window.removeEventListener('online', onOnline);
    document.removeEventListener('visibilitychange', onVisible);
    window.removeEventListener('pagehide', onPageHide);
    sync = null;
  }

  // ── public: open / write / lifecycle ──
  // Loads this person's data (cached copy first, else a snapshot) and returns the view. Throws offline with no cache.
  async function open(userId, h) {
    hooks = h || {};
    stop();
    sync = {
      userId, confirmed: emptyState(), cursor: 0, outbox: [], view: emptyState(), online: true, waiters: [], retryDelay: 1000, eventsDelay: 1000,
      persistTimer: null, retryTimer: null, reconnectTimer: null, pollTimer: null, es: null, flushing: false, pulling: false,
    };
    let cached = null;
    try { cached = JSON.parse(localStorage.getItem(CACHE_PREFIX + userId) || 'null'); } catch (e) { /* ignore */ }
    if (cached && cached.rows && Number.isInteger(cached.cursor)) {
      sync.confirmed = fromRows(cached.rows);
      sync.cursor = cached.cursor;
    } else {
      await loadSnapshot();
    }
    sync.outbox = loadPersistedOutbox(userId);
    sync.view = buildView();
    return sync.view;
  }

  // Starts talking to the server: catch up, send anything queued, open realtime, poll as a fallback.
  function start() {
    if (!sync) return;
    pull(); flush(); connectEvents();
    sync.pollTimer = setInterval(() => { pull(); flush(); connectEvents(); }, 30000);
    window.addEventListener('online', onOnline);
    document.addEventListener('visibilitychange', onVisible);
    window.addEventListener('pagehide', onPageHide);
  }

  // Makes an op from this person, applies it to the view right away and queues it. Returns { op, touched, done }.
  // `done` resolves with the server's result once accepted (and rejects with its reason if refused) — used by the few writes
  // whose outcome the person must see at once (changing an email). `replaceQueued` swaps an unsent op of the same kind
  // (mark-as-read) instead of stacking another.
  function write(type, payload, options) {
    const o = options || {};
    const op = { op_id: uuidv7(), type, actor_id: sync.userId, device_id: deviceId(), client_ts: new Date().toISOString(), payload };
    if (o.replaceQueued) {
      const same = sync.outbox.filter((e) => e.state === 'queued' && e.op.type === type && e.op.payload.conversation_id === payload.conversation_id);
      same.forEach((e) => { sync.outbox.splice(sync.outbox.indexOf(e), 1); forgetOutboxEntry(e); });
    }
    const entry = { op, state: 'queued' };
    let done = Promise.resolve({ status: 'queued' });
    if (o.wait) done = new Promise((resolve, reject) => { entry.waiter = { resolve, reject }; });
    sync.outbox.push(entry);
    persistOutboxEntry(entry);
    const touched = [];
    applyOp(sync.view, op, { ts: op.client_ts, pending: true, touched });
    persistSoon();
    setTimeout(flush, 0);
    return { op, touched, done };
  }
  // Takes back an op that was refused before it could be sent (only used when `wait` writes fail).
  function discard(op) {
    if (!sync) return;
    const i = sync.outbox.findIndex((e) => e.op.op_id === op.op_id);
    if (i > -1) { forgetOutboxEntry(sync.outbox[i]); sync.outbox.splice(i, 1); rebuildAndAnnounce(); }
  }

  // ── files ──
  const urlCache = new Map();
  async function uploadFile(file) {
    const form = new FormData();
    form.append('file', file, file.name);
    const r = await http('POST', '/files', { body: form });
    return { path: r.file_id };
  }
  function fileUrl(fileId) {
    if (!urlCache.has(fileId)) {
      urlCache.set(fileId, (async () => {
        const res = await http('GET', '/files/' + encodeURIComponent(fileId), { raw: true });
        if (!res.ok) throw new ApiError(res.status, 'not_found', 'That file isn’t available.');
        return URL.createObjectURL(await res.blob());
      })().catch((e) => { urlCache.delete(fileId); throw e; }));
    }
    return urlCache.get(fileId);
  }

  const searchProfiles = (q) => http('GET', '/profiles?q=' + encodeURIComponent(q)).then((r) => r.profiles);
  const linkPreview = (url) => http('GET', '/link-preview?url=' + encodeURIComponent(url));
  async function devReset() {
    const res = await rawFetch('POST', '/dev/reset', { headers: { 'x-lime-dev': '1' } });
    await toJson(res);
    stop();
    clearAllLocalData();
    clearSession();
  }

  // Drop everything kept on this device for the signed-out person (or, after a dev reset, for everyone).
  function forgetLocal(everyone) {
    stop();
    if (everyone) clearAllLocalData();
    clearSession();
  }
  function setSessionEmail(email) {
    const s = readSession();
    if (s) { s.email = String(email).toLowerCase(); writeSession(s); }
  }

  return {
    ApiError, forgetLocal, setSessionEmail, open, start, stop, write, discard, flush, pull, persistNow,
    session: readSession, deviceId, signUp, signIn, signOut, accountExists, changePassword,
    uploadFile, fileUrl, searchProfiles, linkPreview, devReset,
    pendingCount: () => (sync ? sync.outbox.length : 0),
    isOnline: () => !sync || sync.online,
    view: () => (sync ? sync.view : emptyState()),
    TABLES,
  };
})();
window.ApiAdapter = ApiAdapter;
