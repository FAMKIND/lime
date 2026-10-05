// The op log and the state derived from it (docs/api.md). Everything that changes data goes through
// processOp(); the append-only log is the source of truth and state.json is only a cache of replaying it.
import fs from 'node:fs';
import path from 'node:path';
import { E, ApiError, isStr, isId, isDeviceId, isObj, isEmail, nowIso, ensureDir, writeJsonAtomic, readJson, usernameError } from './util.mjs';

const PROFILE_PATCH_FIELDS = ['display_name', 'pronouns', 'role', 'school', 'grade_levels', 'subjects', 'bio', 'timezone', 'phone', 'avatar_url', 'username'];
const PUBLIC_PROFILE_FIELDS = ['id', 'display_name', 'username', 'school', 'role', 'pronouns', 'grade_levels', 'subjects', 'bio', 'timezone', 'avatar_url'];
const OP_TYPES = ['message.send', 'reaction.toggle', 'conversation.create', 'conversation.rename', 'conversation.delete',
  'conversation.deleteForMe', 'membership.add', 'membership.setStarred', 'membership.setArchived', 'membership.markRead',
  'profile.update', 'profile.setEmail'];
const memberKey = (c, u) => c + '|' + u;
const reactionKey = (m, u, e) => m + '|' + u + '|' + e;

export class Engine {
  constructor({ dataDir, seedLoader, files }) {
    this.dir = dataDir;
    this.seedLoader = seedLoader;
    this.files = files;
    this.listeners = new Set();
    ensureDir(dataDir);
    this.logFile = path.join(dataDir, 'oplog.jsonl');
    this.stateFile = path.join(dataDir, 'state.json');
    this.metaFile = path.join(dataDir, 'meta.json');
    this.sinceSnapshot = 0;
    this.snapshotTimer = null;
    this.boot();
  }

  // ── boot: snapshot + replay, or a full replay, or first-run seed ──
  clearTables() {
    this.profiles = new Map(); this.conversations = new Map(); this.members = new Map(); this.messages = new Map();
    this.reactions = new Map(); this.attachments = new Map(); this.aliases = new Map(); this.dmKeys = new Map();
    this.opIds = new Map(); this.entries = []; this.seq = 0; this.seedProfileIds = [];
  }

  boot() {
    this.meta = readJson(this.metaFile, { log_start: 0 });
    const logged = [];
    if (fs.existsSync(this.logFile)) {
      for (const line of fs.readFileSync(this.logFile, 'utf8').split('\n')) {
        if (!line.trim()) continue;
        try { logged.push(JSON.parse(line)); } catch (e) { console.warn('[engine] skipping an unreadable log line (a crash mid-write?)'); }
      }
    }
    this.clearTables();
    const snap = readJson(this.stateFile, null);
    const head = logged.length ? logged[logged.length - 1].seq : 0;
    let from = 0;
    if (snap && snap.seq <= head && snap.seq >= 0 && (snap.seq === 0 || logged.some((e) => e.seq === snap.seq))) {
      this.loadSnapshot(snap);
      from = snap.seq;
    }
    this.entries = logged; // the feed needs every entry, including ones the snapshot already covers
    for (const entry of logged) if (entry.seq > from) this.applyEntry(entry, true);
    if (logged.length === 0) this.seedFirstRun();
    this.seq = Math.max(this.seq, head);
    console.log(`[engine] ready: ${this.profiles.size} profiles, ${this.messages.size} messages, log head seq ${this.seq}`);
  }

  seedFirstRun() {
    const seed = this.seedLoader();
    const tables = {
      profiles: seed.profiles, conversations: seed.conversations, conversation_members: seed.conversation_members,
      messages: seed.messages, message_reactions: seed.message_reactions, message_attachments: seed.message_attachments,
    };
    const base = Math.max(this.meta.log_start, this.seq);
    this.seq = base;
    this.append({ kind: 'system.seed', audience: [], seed: tables });
    this.persistStateNow();
  }

  loadSnapshot(snap) {
    this.profiles = new Map(snap.profiles.map((r) => [r.id, r]));
    this.conversations = new Map(snap.conversations.map((r) => [r.id, r]));
    this.members = new Map(snap.members.map((r) => [memberKey(r.conversation_id, r.user_id), r]));
    this.messages = new Map(snap.messages.map((r) => [r.id, r]));
    this.reactions = new Map(snap.reactions.map((r) => [reactionKey(r.message_id, r.user_id, r.emoji), r]));
    this.attachments = new Map(snap.attachments.map((r) => [r.id, r]));
    this.aliases = new Map(Object.entries(snap.aliases));
    this.opIds = new Map(snap.opIds);
    this.seedProfileIds = snap.seedProfileIds || [];
    for (const c of this.conversations.values()) if (c.dm_key) this.dmKeys.set(c.dm_key, c.id);
    this.seq = snap.seq;
  }

  persistStateNow() {
    if (this.snapshotTimer) { clearTimeout(this.snapshotTimer); this.snapshotTimer = null; }
    this.sinceSnapshot = 0;
    writeJsonAtomic(this.stateFile, {
      seq: this.seq, profiles: [...this.profiles.values()], conversations: [...this.conversations.values()],
      members: [...this.members.values()], messages: [...this.messages.values()], reactions: [...this.reactions.values()],
      attachments: [...this.attachments.values()], aliases: Object.fromEntries(this.aliases), opIds: [...this.opIds],
      seedProfileIds: this.seedProfileIds,
    });
    writeJsonAtomic(this.metaFile, this.meta);
  }

  persistStateSoon() {
    if (++this.sinceSnapshot >= 200) { this.persistStateNow(); return; }
    if (!this.snapshotTimer) this.snapshotTimer = setTimeout(() => { this.snapshotTimer = null; this.persistStateNow(); }, 3000);
  }

  // Dev only: forget everything. Seq keeps counting up and log_start moves past the old head, so any
  // client cursor from before the reset gets 410 cursor_expired.
  reset() {
    const head = this.seq;
    this.meta = { log_start: head + 1 };
    try { fs.unlinkSync(this.logFile); } catch (e) { /* none */ }
    try { fs.unlinkSync(this.stateFile); } catch (e) { /* none */ }
    this.clearTables();
    this.seq = head;
    this.seedFirstRun();
    this.notify({ seq: this.seq, audience: null });
  }

  // Private overrides for seed teachers (phone numbers), matched by email. Idempotent: only logs a change when a value differs.
  // Returns the matched profiles (so credentials can be attached to them).
  applyPrivateOverrides(accounts) {
    const ts = nowIso();
    const found = [];
    const changed = [];
    for (const a of accounts) {
      const p = [...this.profiles.values()].find((x) => (x.email || '').toLowerCase() === a.email);
      if (!p) continue;
      found.push(p);
      if (a.phone !== undefined && a.phone !== null && p.phone !== a.phone) changed.push(Object.assign({}, p, { phone: a.phone, updated_at: ts }));
    }
    if (changed.length) this.append({ kind: 'system.merge', server_ts: ts, audience: [], merge: { profiles: changed } });
    return found;
  }

  // Seed teachers that define a username (the two test accounts) get it, once, if their stored profile has none yet (data made before
  // usernames existed). Idempotent.
  mergeSeedUsernames(seedProfiles) {
    const changed = [];
    const ts = nowIso();
    for (const sp of seedProfiles) {
      const p = this.profiles.get(sp.id);
      if (p && sp.username && !p.username) changed.push(Object.assign({}, p, { username: sp.username, updated_at: ts }));
    }
    if (changed.length) this.append({ kind: 'system.merge', server_ts: ts, audience: [], merge: { profiles: changed } });
  }

  // ── the log ──
  append(partial) {
    const entry = Object.assign({ seq: ++this.seq, server_ts: nowIso() }, partial);
    if (partial.server_ts) entry.server_ts = partial.server_ts;
    fs.appendFileSync(this.logFile, JSON.stringify(entry) + '\n');
    this.entries.push(entry);
    this.applyEntry(entry, false);
    this.persistStateSoon();
    this.notify(entry);
    return entry;
  }

  // Applies one logged entry to the tables. For ops, the op was already validated when it was accepted,
  // so replay re-runs the same handler (which mutates) and ignores a rejection (should not happen).
  applyEntry(entry, replay) {
    if (replay) this.seq = Math.max(this.seq, entry.seq);
    if (entry.kind === 'system.seed') {
      const t = entry.seed;
      this.profiles = new Map(t.profiles.map((r) => [r.id, r]));
      this.conversations = new Map(t.conversations.map((r) => [r.id, r]));
      this.members = new Map(t.conversation_members.map((r) => [memberKey(r.conversation_id, r.user_id), Object.assign({ updated_at: r.joined_at }, r)]));
      this.messages = new Map(t.messages.map((r) => [r.id, Object.assign({ client_ts: r.created_at }, r)]));
      this.reactions = new Map(t.message_reactions.map((r) => [reactionKey(r.message_id, r.user_id, r.emoji), Object.assign({ updated_at: r.created_at, removed_at: null }, r)]));
      this.attachments = new Map(t.message_attachments.map((r) => [r.id, r]));
      this.dmKeys = new Map([...this.conversations.values()].filter((c) => c.dm_key).map((c) => [c.dm_key, c.id]));
      this.seedProfileIds = t.profiles.map((p) => p.id);
    } else if (entry.kind === 'system.merge') {
      const t = entry.merge;
      (t.profiles || []).forEach((r) => this.profiles.set(r.id, r));
      (t.conversations || []).forEach((r) => { this.conversations.set(r.id, r); if (r.dm_key) this.dmKeys.set(r.dm_key, r.id); });
      (t.conversation_members || []).forEach((r) => this.members.set(memberKey(r.conversation_id, r.user_id), r));
      if (t.seed_profile_ids) this.seedProfileIds = [...new Set([...this.seedProfileIds, ...t.seed_profile_ids])];
    } else if (entry.kind === 'system.profile') {
      this.profiles.set(entry.profile.id, entry.profile);
    } else if (entry.kind === 'alias') {
      this.aliases.set(entry.alias.from, entry.alias.to);
    } else if (entry.kind === 'op' && replay) {
      this.opIds.set(entry.op.op_id, { seq: entry.seq, server_ts: entry.server_ts });
      try { this.runHandler(entry.op, entry.op.actor_id, entry.server_ts, true); } catch (e) { console.warn('[engine] replay skipped ' + entry.op.type + ': ' + e.message); }
    }
  }

  subscribe(fn) { this.listeners.add(fn); return () => this.listeners.delete(fn); }
  notify(entry) { for (const fn of this.listeners) { try { fn(entry); } catch (e) { /* a dead connection */ } } }

  // ── ops ──
  processOp(op, actorId) {
    if (!isObj(op)) throw E.invalidOp('Each op must be an object.');
    const { op_id, type } = op;
    if (!isId(op_id)) throw E.invalidOp('op_id must be a UUID string.');
    if (typeof type !== 'string' || !OP_TYPES.includes(type)) throw E.unsupportedOp(type);
    const done = this.opIds.get(op_id);
    if (done) return { status: 'duplicate', seq: done.seq, server_ts: done.server_ts };
    if (op.actor_id !== actorId) throw E.forbidden('actor_id does not match the signed-in user.');
    if (!isObj(op.payload)) throw E.invalidOp('payload must be an object.');
    if (!isDeviceId(op.device_id)) throw E.invalidOp('device_id must be a UUID (optionally with a prefix like web-).');
    const ts = nowIso();
    const res = this.runHandler(op, actorId, ts, false);
    const entry = this.append({ kind: 'op', server_ts: ts, op: res.op || op, audience: res.audience });
    this.opIds.set(op_id, { seq: entry.seq, server_ts: ts });
    for (const f of res.followups || []) this.append(Object.assign({ server_ts: ts }, f));
    const result = { status: 'applied', seq: entry.seq, server_ts: ts };
    if (res.canonical_conversation_id) result.canonical_conversation_id = res.canonical_conversation_id;
    return result;
  }

  resolveConversation(id) { return this.aliases.get(id) || id; }
  memberIds(convId) { const out = []; for (const m of this.members.values()) if (m.conversation_id === convId) out.push(m.user_id); return out; }
  getMember(convId, userId) { return this.members.get(memberKey(convId, userId)) || null; }

  liveConversationFor(op, actorId, id, { mustBeMember = true } = {}) {
    if (!isId(id)) throw E.invalidOp('conversation_id is required.');
    const cid = this.resolveConversation(id);
    const conv = this.conversations.get(cid);
    if (!conv || conv.deleted_at) throw E.notFound('That conversation does not exist.');
    if (mustBeMember && !this.getMember(cid, actorId)) throw E.notFound('That conversation does not exist.'); // not a member looks the same as not there
    return conv;
  }

  requireOwnerOfGroup(conv, actorId) {
    const m = this.getMember(conv.id, actorId);
    if (conv.type !== 'group') throw E.forbidden('Only groups can do that.');
    if (!m || m.role !== 'owner') throw E.forbidden('Only the group owner can do that.');
  }

  runHandler(op, actorId, ts, replay) {
    const p = op.payload;
    const withConv = (extra) => Object.assign({}, op, { payload: Object.assign({}, p, extra) });
    switch (op.type) {
      case 'message.send': {
        const conv = this.liveConversationFor(op, actorId, p.conversation_id);
        if (!isId(p.message_id)) throw E.invalidOp('message_id is required.');
        if (this.messages.has(p.message_id)) throw E.conflict('That message id is already used.');
        if (p.content != null && !isStr(p.content, 20000)) throw E.invalidOp('content must be text.');
        const atts = p.attachments == null ? [] : p.attachments;
        if (!Array.isArray(atts) || atts.length > 20) throw E.invalidOp('attachments must be a list of at most 20.');
        if (!(typeof p.content === 'string' && p.content.trim()) && atts.length === 0) throw E.invalidOp('A message needs text or an attachment.');
        if (p.metadata != null && !isObj(p.metadata)) throw E.invalidOp('metadata must be an object.');
        let replyTo = null;
        if (p.reply_to != null) {
          const parent = this.messages.get(p.reply_to);
          if (!parent || parent.conversation_id !== conv.id) throw E.invalidOp('reply_to must be a message in the same conversation.');
          replyTo = parent.id;
        }
        const seen = new Set();
        for (const a of atts) {
          if (!isObj(a) || !isId(a.attachment_id) || !isId(a.file_id)) throw E.invalidOp('Each attachment needs attachment_id and file_id.');
          if (this.attachments.has(a.attachment_id) || seen.has(a.attachment_id)) throw E.conflict('That attachment id is already used.');
          seen.add(a.attachment_id);
          if (!replay) {
            const f = this.files.get(a.file_id);
            if (!f || f.uploader !== actorId) throw E.notFound('One of the files was not uploaded by you.');
            if (f.attached_to) throw E.conflict('That file is already attached to a message.');
          }
        }
        const message = {
          id: p.message_id, conversation_id: conv.id, sender_id: actorId, content: p.content == null ? null : p.content,
          type: 'text', metadata: p.metadata || null, reply_to: replyTo, created_at: ts, updated_at: ts,
          client_ts: typeof op.client_ts === 'string' && !isNaN(Date.parse(op.client_ts)) ? op.client_ts : ts,
        };
        this.messages.set(message.id, message);
        atts.forEach((a, i) => {
          this.attachments.set(a.attachment_id, {
            id: a.attachment_id, message_id: message.id, path: a.file_id, name: a.name == null ? null : a.name, size: a.size == null ? null : a.size,
            mime: a.mime == null ? null : a.mime, width: a.width == null ? null : a.width, height: a.height == null ? null : a.height,
            duration_seconds: a.duration_seconds == null ? null : a.duration_seconds, position: a.position == null ? i : a.position, created_at: ts,
          });
          if (!replay) this.files.attach(a.file_id, message.id, conv.id);
        });
        // "Delete for me" hides a conversation until something newer arrives; that is a read-time rule, nothing to write.
        return { op: withConv({ conversation_id: conv.id }), audience: this.memberIds(conv.id) };
      }
      case 'reaction.toggle': {
        const msg = isId(p.message_id) && this.messages.get(p.message_id);
        if (!msg) throw E.notFound('That message does not exist.');
        const conv = this.conversations.get(msg.conversation_id);
        if (!conv || conv.deleted_at || !this.getMember(conv.id, actorId)) throw E.notFound('That message does not exist.');
        if (!isStr(p.emoji, 32) || !p.emoji) throw E.invalidOp('emoji is required.');
        if (typeof p.present !== 'boolean') throw E.invalidOp('present must be true or false.');
        const key = reactionKey(msg.id, actorId, p.emoji);
        const row = this.reactions.get(key);
        if (p.present) {
          if (row) { row.removed_at = null; row.updated_at = ts; } else this.reactions.set(key, { message_id: msg.id, user_id: actorId, emoji: p.emoji, created_at: ts, updated_at: ts, removed_at: null });
        } else if (row && !row.removed_at) { row.removed_at = ts; row.updated_at = ts; }
        return { audience: this.memberIds(conv.id) };
      }
      case 'conversation.create': {
        if (replay && this.conversations.has(p.conversation_id)) return { audience: this.memberIds(p.conversation_id) }; // a deduplicated create changes nothing
        if (!isId(p.conversation_id)) throw E.invalidOp('conversation_id is required.');
        if (this.conversations.has(p.conversation_id) || this.aliases.has(p.conversation_id)) throw E.conflict('That conversation id is already used.');
        if (p.type !== 'direct' && p.type !== 'group') throw E.invalidOp('type must be direct or group.');
        const others = [...new Set(Array.isArray(p.member_ids) ? p.member_ids : [])].filter((u) => u !== actorId);
        if (!others.every((u) => isId(u) && this.profiles.has(u))) throw E.invalidOp('member_ids must be existing people.');
        if (p.name != null && (!isStr(p.name, 200))) throw E.invalidOp('name must be text of at most 200 characters.');
        if (p.description != null && !isStr(p.description, 2000)) throw E.invalidOp('description must be text.');
        if (p.type === 'direct') {
          if (others.length !== 1) throw E.invalidOp('A direct conversation has exactly one other person.');
          if (p.name) throw E.invalidOp('A direct conversation has no name.');
          const dmKey = [actorId, others[0]].sort().join(':');
          const existing = this.dmKeys.get(dmKey);
          if (existing) {
            // Same pair: converge on the first. The loser id becomes an alias, and the actor is told.
            return {
              op: withConv({ conversation_id: existing, orig_conversation_id: p.conversation_id }), audience: this.memberIds(existing),
              canonical_conversation_id: existing,
              followups: [{ kind: 'alias', to: actorId, audience: [actorId], alias: { from: p.conversation_id, to: existing } }],
            };
          }
        }
        const dmKey = p.type === 'direct' ? [actorId, others[0]].sort().join(':') : null;
        const conv = {
          id: p.conversation_id, type: p.type, name: p.name || null, description: p.description || null, created_by: actorId,
          deleted_at: null, dm_key: dmKey, created_at: ts, updated_at: ts,
        };
        this.conversations.set(conv.id, conv);
        if (dmKey) this.dmKeys.set(dmKey, conv.id);
        [actorId, ...others].forEach((u) => this.members.set(memberKey(conv.id, u), {
          conversation_id: conv.id, user_id: u, role: u === actorId ? 'owner' : 'member', starred: false, archived_at: null,
          cleared_at: null, last_read_at: null, joined_at: ts, updated_at: ts,
        }));
        // Everyone in a new conversation learns who else is in it (their profiles; per-person fields only for themselves).
        const everyone = [actorId, ...others];
        return {
          audience: everyone,
          followups: everyone.map((u) => ({ kind: 'backfill', to: u, audience: [u], backfill: this.conversationRows(conv.id, u) })),
        };
      }
      case 'conversation.rename': {
        const conv = this.liveConversationFor(op, actorId, p.conversation_id);
        this.requireOwnerOfGroup(conv, actorId);
        if (!isStr(p.name, 200) || !p.name.trim()) throw E.invalidOp('name is required.');
        conv.name = p.name; conv.updated_at = ts;
        return { op: withConv({ conversation_id: conv.id }), audience: this.memberIds(conv.id) };
      }
      case 'conversation.delete': {
        const conv = this.liveConversationFor(op, actorId, p.conversation_id);
        this.requireOwnerOfGroup(conv, actorId);
        conv.deleted_at = ts; conv.updated_at = ts;
        return { op: withConv({ conversation_id: conv.id }), audience: this.memberIds(conv.id) };
      }
      case 'conversation.deleteForMe': {
        const conv = this.liveConversationFor(op, actorId, p.conversation_id);
        const m = this.getMember(conv.id, actorId);
        m.cleared_at = ts; m.updated_at = ts;
        return { op: withConv({ conversation_id: conv.id }), audience: [actorId] };
      }
      case 'membership.add': {
        const conv = this.liveConversationFor(op, actorId, p.conversation_id);
        this.requireOwnerOfGroup(conv, actorId);
        if (!Array.isArray(p.user_ids) || p.user_ids.length === 0 || p.user_ids.length > 200) throw E.invalidOp('user_ids must be a list of people.');
        if (!p.user_ids.every((u) => isId(u) && this.profiles.has(u))) throw E.invalidOp('user_ids must be existing people.');
        const before = this.memberIds(conv.id);
        const added = [];
        for (const u of new Set(p.user_ids)) {
          if (this.getMember(conv.id, u)) continue;
          this.members.set(memberKey(conv.id, u), {
            conversation_id: conv.id, user_id: u, role: 'member', starred: false, archived_at: null, cleared_at: null,
            last_read_at: null, joined_at: ts, updated_at: ts,
          });
          added.push(u);
        }
        if (added.length) conv.updated_at = ts;
        // Existing members get the op; each new member gets the whole conversation as a backfill entry.
        return {
          op: withConv({ conversation_id: conv.id, user_ids: added }), audience: before,
          // New members get the whole conversation; existing members get just the new people (their member rows and profiles).
          followups: added.map((u) => ({ kind: 'backfill', to: u, audience: [u], backfill: this.conversationRows(conv.id, u) }))
            .concat(added.length ? before.map((u) => ({ kind: 'backfill', to: u, audience: [u], backfill: this.partialRows(conv.id, added, u) })) : []),
        };
      }
      case 'membership.setStarred':
      case 'membership.setArchived':
      case 'membership.markRead': {
        const conv = this.liveConversationFor(op, actorId, p.conversation_id);
        const m = this.getMember(conv.id, actorId);
        if (op.type === 'membership.setStarred') {
          if (typeof p.starred !== 'boolean') throw E.invalidOp('starred must be true or false.');
          m.starred = p.starred;
        } else if (op.type === 'membership.setArchived') {
          if (typeof p.archived !== 'boolean') throw E.invalidOp('archived must be true or false.');
          m.archived_at = p.archived ? ts : null;
        } else {
          let at = ts;
          if (p.read_through_seq != null) {
            if (!Number.isInteger(p.read_through_seq) || p.read_through_seq < 0) throw E.invalidOp('read_through_seq must be a whole number.');
            const e = this.entryAt(p.read_through_seq);
            if (e && e.kind === 'op' && e.op.type === 'message.send' && e.server_ts < ts) at = e.server_ts;
          }
          if (!m.last_read_at || at > m.last_read_at) m.last_read_at = at; // never backwards
        }
        m.updated_at = ts;
        return { op: withConv({ conversation_id: conv.id }), audience: [actorId] };
      }
      case 'profile.update': {
        const profile = this.profiles.get(actorId);
        if (!profile) throw E.notFound('No such profile.');
        const patch = p.patch;
        if (!isObj(patch) || Object.keys(patch).length === 0) throw E.invalidOp('patch must contain at least one field.');
        for (const [k, v] of Object.entries(patch)) {
          if (!PROFILE_PATCH_FIELDS.includes(k)) throw E.invalidOp('Not editable: ' + k + '.');
          if (k === 'display_name') { if (!isStr(v, 200) || !v.trim()) throw E.invalidOp('Display name is required.'); }
          else if (k === 'grade_levels' || k === 'subjects') { if (v !== null && !(Array.isArray(v) && v.length <= 50 && v.every((x) => isStr(x, 100)))) throw E.invalidOp(k + ' must be a list of text.'); }
          else if (k === 'avatar_url') {
            if (v !== null) {
              if (!isId(v)) throw E.invalidOp('avatar_url must be a file id.');
              if (!replay) { const f = this.files.get(v); if (!f || f.uploader !== actorId) throw E.notFound('That photo was not uploaded by you.'); }
            }
          } else if (k === 'username') {
            // optional and unique (ignoring case): null or an empty string clears it
            if (v !== null && v !== '') {
              const err = usernameError(v);
              if (err) throw E.invalidOp(err);
              if (!replay && [...this.profiles.values()].some((x) => x.id !== actorId && (x.username || '').toLowerCase() === v.toLowerCase())) throw E.conflict('That username is taken. Try another.');
            }
          } else if (v !== null && !isStr(v, 5000)) throw E.invalidOp(k + ' must be text.');
        }
        if (patch.username === '') patch.username = null;
        Object.assign(profile, patch, { updated_at: ts });
        if (!replay && patch.avatar_url) this.files.markAvatar(patch.avatar_url, actorId);
        return { audience: this.coMemberIds(actorId, true) };
      }
      case 'profile.setEmail': {
        const profile = this.profiles.get(actorId);
        if (!profile) throw E.notFound('No such profile.');
        if (!isEmail(p.email)) throw E.invalidOp('Enter a valid email address.');
        const email = p.email.trim().toLowerCase();
        const taken = [...this.profiles.values()].find((x) => x.id !== actorId && (x.email || '').toLowerCase() === email);
        if (taken) throw E.conflict('That email is already in use.');
        const old = profile.email;
        profile.email = email; profile.updated_at = ts;
        this.emailChanged && !replay && this.emailChanged(actorId, old, email);
        return { audience: this.coMemberIds(actorId, true) };
      }
      default:
        throw E.unsupportedOp(op.type);
    }
  }

  // ── reads ──
  entryAt(seq) {
    let lo = 0, hi = this.entries.length - 1;
    while (lo <= hi) { const mid = (lo + hi) >> 1; const s = this.entries[mid].seq; if (s === seq) return this.entries[mid]; if (s < seq) lo = mid + 1; else hi = mid - 1; }
    return null;
  }

  firstIndexAfter(seq) {
    let lo = 0, hi = this.entries.length;
    while (lo < hi) { const mid = (lo + hi) >> 1; if (this.entries[mid].seq <= seq) lo = mid + 1; else hi = mid; }
    return lo;
  }

  // People who share at least one (live) conversation with `userId`, plus the user themself when asked.
  coMemberIds(userId, includeSelf = false) {
    const mine = new Set();
    for (const m of this.members.values()) if (m.user_id === userId) mine.add(m.conversation_id);
    const out = new Set(includeSelf ? [userId] : []);
    for (const m of this.members.values()) {
      if (mine.has(m.conversation_id) && !(this.conversations.get(m.conversation_id) || {}).deleted_at) out.add(m.user_id);
    }
    return [...out];
  }

  profileFor(profile, viewerId) {
    const out = Object.assign({}, profile);
    delete out.auth_user_id;
    if (profile.id !== viewerId) delete out.phone; // never shown to anyone else
    return out;
  }

  memberRowFor(row, viewerId) {
    if (row.user_id === viewerId) return Object.assign({}, row);
    return { conversation_id: row.conversation_id, user_id: row.user_id, role: row.role, joined_at: row.joined_at };
  }

  // The current rows of one conversation as `viewerId` may see them (a snapshot slice and a backfill are the same thing).
  conversationRows(convId, viewerId) {
    const conv = this.conversations.get(convId);
    const msgIds = new Set();
    const messages = [];
    for (const m of this.messages.values()) if (m.conversation_id === convId) { messages.push(m); msgIds.add(m.id); }
    const memberRows = [...this.members.values()].filter((m) => m.conversation_id === convId);
    return {
      conversation: Object.assign({}, conv),
      conversation_members: memberRows.map((m) => this.memberRowFor(m, viewerId)),
      messages: messages.map((m) => Object.assign({}, m)),
      message_reactions: [...this.reactions.values()].filter((r) => msgIds.has(r.message_id)),
      message_attachments: [...this.attachments.values()].filter((a) => msgIds.has(a.message_id)),
      profiles: memberRows.map((m) => this.profiles.get(m.user_id)).filter(Boolean).map((p) => this.profileFor(p, viewerId)),
    };
  }

  // Just some people's member rows and profiles in a conversation (what existing members need when others are added).
  partialRows(convId, userIds, viewerId) {
    return {
      conversation_members: userIds.map((u) => this.members.get(memberKey(convId, u))).filter(Boolean).map((m) => this.memberRowFor(m, viewerId)),
      profiles: userIds.map((u) => this.profiles.get(u)).filter(Boolean).map((p) => this.profileFor(p, viewerId)),
    };
  }

  snapshotFor(userId) {
    const mine = [...this.members.values()].filter((m) => m.user_id === userId)
      .map((m) => this.conversations.get(m.conversation_id)).filter((c) => c && !c.deleted_at);
    const ids = new Set(mine.map((c) => c.id));
    const members = [...this.members.values()].filter((m) => ids.has(m.conversation_id));
    const msgIds = new Set();
    const messages = [];
    for (const m of this.messages.values()) if (ids.has(m.conversation_id)) { messages.push(m); msgIds.add(m.id); }
    const people = new Set(members.map((m) => m.user_id));
    people.delete(userId);
    return {
      seq: this.seq,
      profile: this.profileFor(this.profiles.get(userId), userId),
      profiles: [...people].map((id) => this.profiles.get(id)).filter(Boolean).map((p) => this.profileFor(p, userId)),
      conversations: mine,
      conversation_members: members.map((m) => this.memberRowFor(m, userId)),
      messages,
      message_reactions: [...this.reactions.values()].filter((r) => msgIds.has(r.message_id)),
      message_attachments: [...this.attachments.values()].filter((a) => msgIds.has(a.message_id)),
    };
  }

  // One feed entry as `userId` may see it, or null.
  renderEntry(entry, userId) {
    if (entry.kind === 'op') {
      if (!entry.audience.includes(userId)) return null;
      let op = entry.op;
      if (op.type === 'profile.update' && op.actor_id !== userId) {
        const patch = Object.assign({}, op.payload.patch);
        delete patch.phone;
        if (Object.keys(patch).length === 0) return null;
        op = Object.assign({}, op, { payload: Object.assign({}, op.payload, { patch }) });
      }
      return { seq: entry.seq, server_ts: entry.server_ts, op };
    }
    if (entry.kind === 'backfill' && entry.to === userId) return { seq: entry.seq, server_ts: entry.server_ts, backfill: entry.backfill };
    if (entry.kind === 'alias' && entry.to === userId) return { seq: entry.seq, server_ts: entry.server_ts, alias: entry.alias };
    return null;
  }

  changesFor(userId, since, limit) {
    if (!Number.isInteger(since) || since < 0) throw E.badRequest('since must be a whole number.');
    if (since < this.meta.log_start || since > this.seq) throw E.expired();
    const out = [];
    let next = since;
    let i = this.firstIndexAfter(since);
    for (; i < this.entries.length; i++) {
      const e = this.entries[i];
      const rendered = this.renderEntry(e, userId);
      if (rendered) {
        if (out.length >= limit) return { changes: out, next, has_more: true };
        out.push(rendered);
      }
      next = e.seq;
    }
    return { changes: out, next: Math.max(next, since), has_more: false };
  }

  searchProfiles(callerId, q) {
    const text = String(q || '').trim();
    if (text.length < 2) throw E.badRequest('q must be at least 2 characters.');
    const lower = text.toLowerCase();
    const handle = lower.replace(/^@/, ''); // an exact @username, with or without the @
    const digits = text.replace(/\D/g, '');
    const phoneQuery = digits.length >= 7 && digits.length === text.replace(/[\s()+.-]/g, '').length ? digits : null;
    const out = [];
    for (const p of this.profiles.values()) {
      if (p.id === callerId) continue;
      const hit = (p.display_name || '').toLowerCase().includes(lower) || (p.school || '').toLowerCase().includes(lower)
        || (p.email || '').toLowerCase() === lower
        || (!!handle && !!p.username && p.username.toLowerCase() === handle)
        || (phoneQuery && p.phone && String(p.phone).replace(/\D/g, '') === phoneQuery);
      if (!hit) continue;
      const pub = {};
      for (const f of PUBLIC_PROFILE_FIELDS) pub[f] = p[f] === undefined ? null : p[f];
      out.push(pub);
      if (out.length >= 50) break;
    }
    return out;
  }

  createProfile({ id, email, display_name }) {
    const ts = nowIso();
    const profile = {
      id, auth_user_id: null, display_name, email, role: null, pronouns: null, school: null, grade_levels: null, subjects: null,
      bio: null, timezone: null, phone: null, status: null, avatar_url: null, username: null, created_at: ts, updated_at: ts,
    };
    this.append({ kind: 'system.profile', server_ts: ts, audience: [], profile });
    return profile;
  }

  canReadFile(userId, meta) {
    if (meta.uploader === userId || meta.kind === 'avatar') return true;
    for (const a of this.attachments.values()) {
      if (a.path !== meta.file_id) continue;
      const msg = this.messages.get(a.message_id);
      const conv = msg && this.conversations.get(msg.conversation_id);
      if (conv && !conv.deleted_at && this.getMember(conv.id, userId)) return true;
    }
    return false;
  }
}

export { ApiError };
