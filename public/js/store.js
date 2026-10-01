'use strict';

// LimeStore (LIME-24b) — the one data seam described in
// docs/data-model.md: the UI calls only this, never LocalAdapter (or,
// later, a SupabaseAdapter) directly, and never reads the seed arrays or
// localStorage itself. Reads are synchronous, from an in-memory cache;
// writes are async (return a Promise), update the cache optimistically,
// persist through the adapter (debounced), and emit one of the three
// documented events. LIME_BACKEND is 'local' today — the only adapter
// implemented is LocalAdapter; a 'supabase' branch is future work per the
// switch checklist in docs/data-model.md, not built ahead of need here.
const LIME_BACKEND = 'local';

const LimeStore = (function () {
  let profiles = new Map();
  let conversations = [];
  let members = [];
  let messages = [];
  let reactions = [];
  let messageAttachments = []; // LIME-41
  let currentUserId = null;
  let loggedFallback = false;
  let saveTimer = null;
  // LIME-74: with the dev server running, the store talks to /api/v1 through ApiAdapter (api-adapter.js) instead of
  // LocalAdapter. Reads below are the same either way; only the writes and init differ.
  let api = false;
  const presence = new Map(); // userId -> 'active' (realtime) — anyone else is away
  const directory = new Map(); // people found through the directory, kept so a chip or new chat can show them
  let localAppearance = null; // appearance stays on this device (docs/api.md)

  function adapter() {
    // The only branch that exists yet — see the file header comment.
    return LocalAdapter;
  }

  function emit(name, detail) {
    document.dispatchEvent(new CustomEvent(name, { detail }));
  }

  // ── Merge-on-save (LIME-69) ───────────────────────────────
  // The snapshot in localStorage is shared by every tab, so a save is a
  // three-way merge rather than an overwrite: `base` is the stored state
  // this tab last agreed with, the in-memory tables are "local", and the
  // snapshot stored right now is "latest". Rows are matched by key and
  // never dropped (union), so a stale read can only ever delay a row,
  // never lose it — a tab that finds its row missing from latest writes
  // it back. Removals are soft (reactions carry removed_at). When both
  // sides changed the same field of a row, the newer updated_at wins
  // (ties go to this tab). These are the rules a server would apply to
  // concurrent writes — see docs/data-model.md.
  const TABLE_KEYS = {
    profiles: (r) => r.id,
    conversations: (r) => r.id,
    conversation_members: (r) => r.conversation_id + '|' + r.user_id,
    messages: (r) => r.id,
    message_reactions: (r) => r.message_id + '|' + r.user_id + '|' + r.emoji,
    message_attachments: (r) => r.id,
  };
  let baseRows = {}; // table -> Map(key -> JSON of the row as last stored)
  // A browser can hand a tab a stale read of localStorage, so another tab
  // may save over this tab's just-written field without having seen it.
  // For a short window after each save, changes are therefore detected
  // against the base from *before* that save, which keeps those fields
  // "ours" until the other tab's next merge brings them back.
  const RECENT_WRITE_MS = 1500;
  let recentBases = []; // { at, rows } — the base each recent save started from
  let storedOnce = false; // a snapshot exists (loaded or written) — its later absence means a reset
  let remoteSyncing = false;

  function currentState() {
    return {
      profiles: [...profiles.values()],
      conversations,
      conversation_members: members,
      messages,
      message_reactions: reactions,
      message_attachments: messageAttachments,
    };
  }

  // Key-order-insensitive JSON, so two tabs that built the same row with
  // fields in a different order never look "different" (which would make
  // them write back and forth forever).
  function stable(value) {
    return JSON.stringify(value, (k, v) => {
      if (v && typeof v === 'object' && !Array.isArray(v)) {
        return Object.keys(v).sort().reduce((o, key) => { o[key] = v[key]; return o; }, {});
      }
      return v;
    });
  }

  function rowMap(rows, keyOf) {
    const map = new Map();
    (rows || []).forEach((row) => map.set(keyOf(row), stable(row)));
    return map;
  }

  function rememberBase(state) {
    baseRows = {};
    Object.keys(TABLE_KEYS).forEach((table) => { baseRows[table] = rowMap(state[table], TABLE_KEYS[table]); });
  }

  function baseJsonFor(table, key) {
    const cutoff = Date.now() - RECENT_WRITE_MS;
    recentBases = recentBases.filter((entry) => entry.at >= cutoff);
    const rows = recentBases.length ? recentBases[0].rows : baseRows;
    return rows[table] && rows[table].get(key);
  }

  function rowTime(row) {
    return new Date(row.updated_at || row.created_at || row.joined_at || 0).getTime() || 0;
  }

  function mergeRow(baseJson, local, latest, seenJson) {
    if (stable(local) === stable(latest)) return local;
    // A row older than the one this tab last saw is a stale read, not news.
    if (seenJson && rowTime(latest) < rowTime(JSON.parse(seenJson))) return local;
    const localWins = rowTime(local) >= rowTime(latest);
    if (!baseJson) return localWins ? local : latest;
    const base = JSON.parse(baseJson);
    const out = {};
    new Set(Object.keys(local).concat(Object.keys(latest))).forEach((field) => {
      const same = (a, b) => stable(a) === stable(b);
      const localChanged = !same(local[field], base[field]);
      const latestChanged = !same(latest[field], base[field]);
      const useLocal = localChanged && latestChanged ? localWins : localChanged;
      const value = useLocal ? local[field] : latest[field];
      if (value !== undefined) out[field] = value;
    });
    return out;
  }

  function mergeStates(local, latest) {
    const merged = {};
    Object.keys(TABLE_KEYS).forEach((table) => {
      const keyOf = TABLE_KEYS[table];
      const localByKey = new Map((local[table] || []).map((row) => [keyOf(row), row]));
      const out = [];
      const seen = new Set();
      (latest[table] || []).forEach((row) => {
        const key = keyOf(row);
        seen.add(key);
        const mine = localByKey.get(key);
        out.push(mine ? mergeRow(baseJsonFor(table, key), mine, row, baseRows[table] && baseRows[table].get(key)) : row);
      });
      (local[table] || []).forEach((row) => { if (!seen.has(keyOf(row))) out.push(row); });
      merged[table] = out;
    });
    return merged;
  }

  function adoptState(state) {
    profiles = new Map(state.profiles.map((p) => [p.id, p]));
    conversations = state.conversations;
    members = state.conversation_members;
    messages = state.messages;
    reactions = state.message_reactions;
    messageAttachments = state.message_attachments || [];
  }

  // Which rows differ between what this tab held and what it holds now.
  function changedKeys(before, after) {
    const changed = {};
    Object.keys(TABLE_KEYS).forEach((table) => {
      const oldMap = before[table];
      const keys = new Set();
      rowMap(after[table], TABLE_KEYS[table]).forEach((json, key) => {
        if (oldMap.get(key) !== json) keys.add(key);
      });
      changed[table] = keys;
    });
    return changed;
  }

  function snapshotRows(state) {
    const out = {};
    Object.keys(TABLE_KEYS).forEach((table) => { out[table] = rowMap(state[table], TABLE_KEYS[table]); });
    return out;
  }

  // Tell every view what arrived from another tab, using the same events
  // a local write emits (app.js repaints from them), plus one summary.
  function announceRemote(changed, before) {
    remoteSyncing = true;
    try {
      const msgConversations = new Set();
      changed.messages.forEach((key) => {
        const message = messages.find((m) => m.id === key);
        if (message) msgConversations.add(message.conversation_id);
      });
      msgConversations.forEach((conversationId) => emit('lime:messages-changed', { conversationId, kind: 'remote' }));
      new Set([...changed.message_reactions].map((k) => k.split('|')[0])).forEach((messageId) => {
        emit('lime:reactions-changed', { messageId, kind: 'remote' });
      });
      if (changed.conversations.size || changed.conversation_members.size) {
        emit('lime:conversations-changed', { kind: 'remote' });
      }
      if (changed.profiles.size) {
        emit('lime:profile-changed', { profileId: [...changed.profiles][0], profileIds: [...changed.profiles], kind: 'remote' });
        const mine = profiles.get(currentUserId);
        const was = before.profiles.get(currentUserId);
        if (mine && was && stable(mine.appearance || null) !== stable(JSON.parse(was).appearance || null)) {
          emit('lime:appearance-changed', { appearance: getAppearance(), kind: 'remote' });
        }
      }
      emit('lime:remote-synced', { changed, messageConversations: [...msgConversations] });
    } finally {
      remoteSyncing = false;
    }
  }

  // Merges `latest` (a stored snapshot) into this tab, announcing anything
  // new. Returns true when this tab holds rows latest lacks, so the caller
  // can write them back.
  function absorb(latest) {
    const before = snapshotRows(currentState());
    const merged = mergeStates(currentState(), latest);
    adoptState(merged);
    rememberBase(latest);
    const changed = changedKeys(before, merged);
    if (Object.keys(changed).some((t) => changed[t].size)) announceRemote(changed, before);
    const latestRows = snapshotRows(latest);
    return Object.keys(TABLE_KEYS).some((table) => {
      const mine = rowMap(merged[table], TABLE_KEYS[table]);
      return [...mine].some(([key, json]) => latestRows[table].get(key) !== json);
    });
  }

  // Another tab ran "Reset demo data": the shared snapshot is gone, so
  // anything this tab still holds (or has pending) must not bring it back.
  function handleRemoteReset() {
    if (saveTimer) {
      clearTimeout(saveTimer);
      saveTimer = null;
    }
    storedOnce = false;
    emit('lime:remote-reset');
  }

  function persistNow() {
    const priorBase = baseRows;
    const latest = adapter().peek ? adapter().peek() : null;
    if (latest === null && storedOnce) {
      handleRemoteReset();
      return;
    }
    if (latest !== null) absorb(latest);
    const state = currentState();
    adapter().save(state);
    recentBases.push({ at: Date.now(), rows: priorBase });
    rememberBase(state);
    storedOnce = true;
  }

  // The `storage` event fires in the *other* tabs only, so it is exactly
  // "someone else saved". null newValue/key = the snapshot was removed.
  function onStorage(e) {
    if (api) return; // with the API, tabs sync through the server
    if (e.storageArea && e.storageArea !== window.localStorage) return;
    if (e.key !== null && e.key !== 'lime-state-v1') return;
    if (!currentUserId) return; // not initialised yet
    const latest = e.key === null || e.newValue === null ? null : adapter().peek();
    if (latest === null) {
      if (storedOnce) handleRemoteReset();
      return;
    }
    if (absorb(latest)) scheduleSave(); // we hold rows the other tab's write lacked
  }
  window.addEventListener('storage', onStorage);

  // LIME-29: flushes a pending debounced save immediately, if there is
  // one — a real bug found in verification (not assumed): signOut()
  // navigates away right after, and a real page navigation can drop a
  // still-pending scheduleSave() timer, silently losing whatever wrote
  // most recently (confirmed live: a DM created via the New message
  // picker, then a message sent, then a quick sign-out, lost both in
  // real Firefox and real Chrome — the conversation was gone on the next
  // sign-in). This is the general form of the exact race LIME-33's own
  // createProfile fix (persistNow(), called synchronously from signUp)
  // addressed for one specific write; auth.js's signOut() calls this for
  // every other write.
  function flush() {
    if (api) { ApiAdapter.persistNow(); ApiAdapter.flush(); return; }
    if (saveTimer) {
      clearTimeout(saveTimer);
      saveTimer = null;
      persistNow();
    }
  }

  function scheduleSave() {
    if (saveTimer) clearTimeout(saveTimer);
    saveTimer = setTimeout(() => {
      saveTimer = null;
      persistNow();
    }, 100);
  }

  function loadFromAdapter() {
    const state = adapter().load();
    profiles = new Map(state.profiles.map((p) => [p.id, p]));
    conversations = state.conversations;
    members = state.conversation_members;
    messages = state.messages;
    reactions = state.message_reactions;
    // LIME-41: `|| []` — a snapshot saved before this brief landed has no
    // such key at all; without the fallback this would be `undefined`
    // and every array method below would throw the first time it's read.
    messageAttachments = state.message_attachments || [];
    rememberBase(currentState());
    storedOnce = !!adapter().peek && adapter().peek() !== null;
  }

  // The auth seam (docs/data-model.md): reads the per-tab lime-demo-session
  // (sessionStorage, LIME-69) and resolves it to a profile. LIME-33: the session shape is now
  // { userId, email } (written by LimeAuth.signUp/signInWithPassword) —
  // resolved by userId first, falling back to email for an old-shape
  // session (one written before this brief, still just { email }) so an
  // already-signed-in browser doesn't get silently logged out by this
  // change alone. No match or no session at all falls back to
  // teacher-002, logged once — not on every call. In the real app this
  // fallback is never actually reached: index.html's own session gate
  // (app.js) redirects to login.html first whenever there's no valid
  // session, before LimeStore.init() ever runs. It stays here mainly for
  // jsdom tests that don't bother setting up a session at all.
  function resolveCurrentUserId() {
    let session = null;
    try {
      const raw = sessionStorage.getItem('lime-demo-session'); // LIME-69: per tab
      if (raw) session = JSON.parse(raw);
    } catch (e) {
      // Malformed session value — treat the same as "no session".
    }
    if (session) {
      if (session.userId && profiles.has(session.userId)) return session.userId;
      if (session.email) {
        const match = [...profiles.values()].find((p) => p.email === session.email);
        if (match) return match.id;
      }
    }
    if (!loggedFallback) {
      console.log('[LimeStore] No session matched a profile — defaulting to teacher-002.');
      loggedFallback = true;
    }
    return 'teacher-002';
  }

  function firstName(displayName) {
    return displayName.trim().split(/\s+/)[0];
  }

  // "Jean", "Jean & Mary", "Jean, Mary & Jimin" — the unnamed-group title
  // fallback. Not exercised by any group in today's seed (every one has an
  // explicit name), same as when this first shipped in LIME-19b.
  function joinNames(names) {
    if (names.length <= 1) return names[0] || '';
    if (names.length === 2) return names[0] + ' & ' + names[1];
    return names.slice(0, -1).join(', ') + ' & ' + names[names.length - 1];
  }


  // ── LIME-74: the API backend ─────────────────────────────────────────
  // Re-reads the adapter's view (confirmed + our unconfirmed ops) into the arrays every read below uses.
  function adoptView() {
    const v = ApiAdapter.view();
    profiles = v.profiles;
    conversations = [...v.conversations.values()];
    members = [...v.conversation_members.values()];
    messages = [...v.messages.values()];
    reactions = [...v.message_reactions.values()];
    messageAttachments = [...v.message_attachments.values()];
  }

  // What the UI sees of a person: the stored profile plus things that are not stored (presence; this device's appearance).
  function decorate(p) {
    if (!p || !api) return p;
    const out = Object.assign({}, p);
    out.status = p.id === currentUserId || presence.get(p.id) === 'active' ? 'online' : 'offline';
    if (p.id === currentUserId) out.appearance = localAppearance || undefined;
    return out;
  }

  // Tell every view what changed (same events a local write emits), flagged as coming from outside this tab's own action.
  function emitApiChanges(changed) {
    remoteSyncing = true;
    try {
      const convs = new Set();
      changed.messages.forEach((id) => { const m = ApiAdapter.view().messages.get(id); if (m) convs.add(m.conversation_id); });
      convs.forEach((conversationId) => emit('lime:messages-changed', { conversationId, kind: 'remote' }));
      new Set([...changed.message_reactions].map((k) => k.split('|')[0])).forEach((messageId) => emit('lime:reactions-changed', { messageId, kind: 'remote' }));
      if (changed.conversations.size || changed.conversation_members.size) emit('lime:conversations-changed', { kind: 'remote' });
      if (changed.profiles.size) emit('lime:profile-changed', { profileId: [...changed.profiles][0], profileIds: [...changed.profiles], kind: 'remote' });
      emit('lime:remote-synced', { changed, messageConversations: [...convs] });
    } finally {
      remoteSyncing = false;
    }
  }

  const REJECTED_TITLES = {
    'message.send': 'Message not sent', 'reaction.toggle': 'Reaction not saved', 'conversation.create': 'Couldn’t start the chat',
    'conversation.rename': 'Couldn’t rename the chat', 'conversation.delete': 'Couldn’t delete the chat', 'membership.add': 'Couldn’t add people',
    'profile.update': 'Profile not saved', 'profile.setEmail': 'Email not changed',
  };
  const apiHooks = {
    onViewChanged(changed) { adoptView(); emitApiChanges(changed); },
    onRejected(op, error) {
      // The adapter has already taken the change back out of the view; say so.
      adoptView();
      emit('lime:conversations-changed', { kind: 'rollback' });
      emit('lime:messages-changed', { kind: 'rollback' });
      emit('lime:profile-changed', { kind: 'rollback' });
      if (window.LimeToast) LimeToast.show({ title: REJECTED_TITLES[op.type] || 'Change not saved', body: error.message, tone: 'error' });
    },
    onAlias(from, to) { adoptView(); emit('lime:conversation-aliased', { from, to }); },
    onPresence(userId, status) {
      if (status === 'active') presence.set(userId, 'active'); else presence.delete(userId);
      remoteSyncing = true;
      try { emit('lime:profile-changed', { profileId: userId, kind: 'presence' }); } finally { remoteSyncing = false; }
    },
    onSessionEnded(kind) {
      ApiAdapter.forgetLocal(kind === 'reset');
      if (window.LimeToast) {
        if (kind === 'reset') LimeToast.queue({ title: 'Demo data was reset', body: 'All accounts and changes were cleared.', tone: 'info' });
        else LimeToast.queue({ title: 'You’ve been signed out', body: 'Sign in again to continue.', tone: 'info' });
      }
      if (window.LimeAuth) LimeAuth.signOut({ silent: true });
    },
  };

  // Writes whose outcome the person must see right away (changing an email) wait for the server, up to 10 seconds.
  function apiWriteAndWait(type, payload) {
    const w = ApiAdapter.write(type, payload, { wait: true });
    adoptView();
    const timeout = new Promise((_, reject) => setTimeout(() => reject(new ApiAdapter.ApiError(0, 'offline', 'Can’t reach Lime right now. Check your connection and try again.')), 10000));
    return Promise.race([w.done, timeout]).catch((err) => { ApiAdapter.discard(w.op); adoptView(); throw err; });
  }

  // ── reads ──────────────────────────────────────────────────

  function getProfile(id) {
    return decorate(profiles.get(id) || directory.get(id)) || null;
  }

  // Not in docs/data-model.md's original contract list — added in LIME-31
  // (see "Deviations from the contract" there) so changeEmail's own
  // uniqueness check has a way to ask "does any profile already have this
  // email" without reaching into the cache directly.
  function findProfileByEmail(email) {
    return decorate([...profiles.values()].find((p) => p.email === email)) || null;
  }

  // Not in docs/data-model.md's original contract list — added in
  // LIME-29 (see "Deviations from the contract" there) for the New
  // message picker's own directory search, which needs every profile to
  // filter client-side (name/email/school/phone) — excluding the current
  // user, and sorting, are the picker's own concern, not this read's.
  function listProfiles() {
    return [...profiles.values()].map(decorate);
  }

  function getCurrentUserId() {
    return currentUserId;
  }

  function getCurrentUser() {
    return getProfile(currentUserId);
  }

  function getConversation(id) {
    return conversations.find((c) => c.id === id) || null;
  }

  function getMembers(conversationId) {
    return members
      .filter((m) => m.conversation_id === conversationId)
      .map((m) => getProfile(m.user_id))
      .filter(Boolean);
  }

  function getMyMembership(conversationId) {
    return members.find((m) => m.conversation_id === conversationId && m.user_id === currentUserId) || null;
  }

  // LIME-50/51. Mirrors production's user_settings row (theme/canvas/
  // pattern) — a plain field on the current user's own profile locally,
  // same pattern as updateProfile, not a new adapter capability. `canvas`
  // defaults to 'warm' (today's look, unchanged until a user picks
  // something else); `theme` defaults to 'system', matching the
  // no-stored-preference fallback the head scripts (index/login/signup
  // .html) already assume before any profile has loaded. `pattern` is
  // LIME-52's own concern, included now so callers never have to guard
  // against a missing key.
  const DEFAULT_APPEARANCE = { theme: 'system', canvas: 'warm', pattern: null };

  function getAppearance() {
    const profile = getCurrentUser();
    return Object.assign({}, DEFAULT_APPEARANCE, profile && profile.appearance);
  }

  function listConversations(options) {
    const opts = options || {};
    const types = opts.types;
    const includeArchived = !!opts.includeArchived;
    return members
      .filter((m) => m.user_id === currentUserId)
      .filter((m) => includeArchived || !m.archived_at)
      // LIME-34: "Delete for me" (cleared_at) hides a conversation from
      // your own lists once there's nothing after the clear point left to
      // show — a fresh message from the other person un-hides it again,
      // for free, just by having a created_at past cleared_at.
      .filter((m) => !m.cleared_at || messages.some((msg) => msg.conversation_id === m.conversation_id && new Date(msg.created_at) > new Date(m.cleared_at)))
      .map((m) => getConversation(m.conversation_id))
      .filter((c) => c && !c.deleted_at)
      .filter((c) => !types || types.includes(c.type));
  }

  // Thread order is arrival (the server's order); a message not yet accepted by the server goes last (docs/api.md section 6).
  function byArrival(a, b) {
    return (a._pending ? 1 : 0) - (b._pending ? 1 : 0) || new Date(a.created_at) - new Date(b.created_at);
  }

  function listMessages(conversationId, options) {
    const threadOnly = options && options.threadOnly;
    // LIME-34: cleared_at is per-membership (your own "delete for me"
    // point) — messages at or before it are hidden from you specifically,
    // never from the other person's own read of the same conversation.
    const membership = getMyMembership(conversationId);
    const clearedAt = membership && membership.cleared_at;
    return messages
      .filter((m) => m.conversation_id === conversationId)
      .filter((m) => !clearedAt || new Date(m.created_at) > new Date(clearedAt))
      .filter((m) => !threadOnly || !m.reply_to)
      .sort(byArrival);
  }

  function listReplies(messageId) {
    return messages
      .filter((m) => m.reply_to === messageId)
      .sort(byArrival);
  }

  // Not in docs/data-model.md's original contract list — added as a small,
  // necessary extension (documented there now) since the UI has no other
  // way to resolve a single message id to its record (the reply panel's
  // quote, and finding a reply's parent conversation both need exactly
  // this). The old data.js had the equivalent (findMessageById).
  function getMessage(id) {
    return messages.find((m) => m.id === id) || null;
  }

  function getReactions(messageId) {
    const byEmoji = new Map();
    reactions
      .filter((r) => r.message_id === messageId && !r.removed_at)
      .forEach((r) => {
        if (!byEmoji.has(r.emoji)) byEmoji.set(r.emoji, { emoji: r.emoji, count: 0, mine: false });
        const entry = byEmoji.get(r.emoji);
        entry.count += 1;
        if (r.user_id === currentUserId) entry.mine = true;
      });
    return [...byEmoji.values()];
  }

  function getConversationTitle(conversation) {
    if (conversation.type === 'direct') {
      const other = getMembers(conversation.id).find((p) => p.id !== currentUserId);
      return other ? other.display_name : 'Unknown';
    }
    if (conversation.name) return conversation.name;
    const others = getMembers(conversation.id).filter((p) => p.id !== currentUserId);
    return joinNames(others.map((p) => firstName(p.display_name)));
  }

  function getLatestActivity(conversationId) {
    const msgs = listMessages(conversationId);
    return msgs.length ? msgs[msgs.length - 1] : null;
  }

  // Per docs/data-model.md: owner can rename and delete; DMs can't be
  // renamed (there's no name to change — the title is always derived from
  // the other person). LIME-34: delete is no longer owner-only for a DM —
  // there's no "owner" of one at all, and "delete" there means your own
  // copy (deleteForMe), not deleting it for the other person too, so it's
  // always available regardless of role.
  function can(action, conversation) {
    const membership = getMyMembership(conversation.id);
    const isOwner = !!membership && membership.role === 'owner';
    if (action === 'rename') return isOwner && conversation.type !== 'direct';
    if (action === 'delete') return isOwner || conversation.type === 'direct';
    // LIME-27: groups only — a DM's "owner" flag (whoever created it) is
    // never surfaced as real ownership anywhere else in the app (LIME-34's
    // own "there's no owner of a DM" decision), and the Share popover's UI
    // never shows the add-by-email field for a DM in the first place, so
    // this stays false for one regardless of the stored role.
    if (action === 'addMembers') return isOwner && conversation.type === 'group';
    return false;
  }

  // LIME-34: the one-line reason a disabled menu item shows, kept next to
  // can() itself so the rule and its explanation can't drift apart. Only
  // meaningful when can() is false — returns null otherwise, including for
  // any action can() doesn't know about, rather than guessing a message
  // for a case that was never designed to be disabled in the first place.
  function canReason(action, conversation) {
    if (can(action, conversation)) return null;
    const membership = getMyMembership(conversation.id);
    const isOwner = !!membership && membership.role === 'owner';
    if (action === 'rename') {
      if (conversation.type === 'direct') return 'Direct messages are named after the person';
      if (!isOwner) return 'Only the group owner can rename';
    }
    if (action === 'delete' && !isOwner) return 'Only the group owner can delete.';
    if (action === 'addMembers' && conversation.type === 'group' && !isOwner) return 'Only the group owner can add people.';
    return null;
  }

  // ── writes (async — each resolves with the affected record) ──

  // LIME-41 supersedes LIME-38's "one message per file": `attachments`
  // (an array of { path, name, size, mime, width, height }, each already
  // uploaded via uploadAttachment by the caller — this call only ever
  // records the resulting rows, never touches file bytes itself) can sit
  // on *any* message alongside real `content` — typed text is that
  // message's own caption now, not a separate message. `type` stays
  // 'text' for every new send regardless of whether attachments are
  // present; 'image'/'file' are legacy values this function never
  // produces any more, only ever read back (getAttachments below).
  function sendMessage(conversationId, options) {
    const opts = options || {};
    if (api) {
      const messageId = crypto.randomUUID();
      ApiAdapter.write('message.send', {
        message_id: messageId, conversation_id: conversationId, content: opts.content != null ? opts.content : null, type: 'text',
        metadata: opts.metadata || null, reply_to: opts.replyTo || null,
        attachments: (opts.attachments || []).map((att, index) => ({
          attachment_id: crypto.randomUUID(), file_id: att.path, name: att.name != null ? att.name : null, size: att.size != null ? att.size : null,
          mime: att.mime != null ? att.mime : null, width: att.width != null ? att.width : null, height: att.height != null ? att.height : null,
          duration_seconds: att.duration_seconds != null ? att.duration_seconds : null, position: index,
        })),
      });
      adoptView();
      emit('lime:messages-changed', { conversationId, messageId, kind: opts.replyTo ? 'reply' : 'message' });
      return Promise.resolve(getMessage(messageId));
    }
    const message = {
      id: crypto.randomUUID(),
      conversation_id: conversationId,
      sender_id: currentUserId,
      content: opts.content != null ? opts.content : null,
      type: opts.type || 'text',
      metadata: opts.metadata || null,
      reply_to: opts.replyTo || null,
      created_at: new Date().toISOString(),
      updated_at: new Date().toISOString(),
    };
    messages.push(message);
    (opts.attachments || []).forEach((att, index) => {
      messageAttachments.push({
        id: crypto.randomUUID(),
        message_id: message.id,
        path: att.path,
        name: att.name != null ? att.name : null,
        size: att.size != null ? att.size : null,
        mime: att.mime != null ? att.mime : null,
        width: att.width != null ? att.width : null,
        height: att.height != null ? att.height : null,
        // LIME-42: mirrors width/height's own reasoning exactly — read
        // once at upload time (app.js's readAudioDuration), not measured
        // live off a real <audio> element each time one renders.
        duration_seconds: att.duration_seconds != null ? att.duration_seconds : null,
        position: index,
        created_at: message.created_at,
      });
    });
    scheduleSave();
    emit('lime:messages-changed', { conversationId, messageId: message.id, kind: opts.replyTo ? 'reply' : 'message' });
    return Promise.resolve(message);
  }

  // Sorted by position — the order attachments were actually chosen in,
  // not insertion-into-the-array order (which happens to be the same
  // today, but position is the real, documented contract, not an
  // accident of push order). Falls back to synthesizing a single-row
  // shape from a pre-LIME-41 'image'/'file' message's own metadata.path
  // when this message has no real message_attachments rows at all — the
  // documented backward-compatibility mapping (data-model.md), so every
  // reader can call this one function regardless of which era a message
  // is from, instead of branching on message.type itself.
  function getAttachments(messageId) {
    const rows = messageAttachments
      .filter((a) => a.message_id === messageId)
      .sort((a, b) => a.position - b.position);
    if (rows.length > 0) return rows;
    const message = getMessage(messageId);
    if (message && (message.type === 'image' || message.type === 'file') && message.metadata && message.metadata.path) {
      return [{
        id: message.id + '-legacy',
        message_id: message.id,
        path: message.metadata.path,
        name: message.metadata.name != null ? message.metadata.name : null,
        size: message.metadata.size != null ? message.metadata.size : null,
        mime: message.metadata.mime != null ? message.metadata.mime : null,
        width: null,
        height: null,
        duration_seconds: null,
        position: 0,
        created_at: message.created_at,
      }];
    }
    return [];
  }

  function toggleReaction(messageId, emoji) {
    if (api) {
      const mine = reactions.find((r) => r.message_id === messageId && r.user_id === currentUserId && r.emoji === emoji);
      ApiAdapter.write('reaction.toggle', { message_id: messageId, emoji, present: !(mine && !mine.removed_at) });
      adoptView();
      emit('lime:reactions-changed', { messageId, kind: 'reaction' });
      return Promise.resolve(getReactions(messageId));
    }
    // LIME-69: removing is soft (removed_at) so a merge with another tab
    // can't resurrect it; re-adding the same emoji revives the same row.
    const now = new Date().toISOString();
    const row = reactions.find((r) => r.message_id === messageId && r.user_id === currentUserId && r.emoji === emoji);
    if (row && !row.removed_at) {
      row.removed_at = now;
      row.updated_at = now;
    } else if (row) {
      row.removed_at = null;
      row.updated_at = now;
    } else {
      reactions.push({ message_id: messageId, user_id: currentUserId, emoji, created_at: now, updated_at: now, removed_at: null });
    }
    scheduleSave();
    emit('lime:reactions-changed', { messageId, kind: 'reaction' });
    return Promise.resolve(getReactions(messageId));
  }

  function createConversation(options) {
    const opts = options || {};
    const memberIds = [...new Set([currentUserId].concat(opts.memberIds || []))];
    if (opts.type === 'direct') {
      const dmKey = [...memberIds].sort().join(':');
      const existing = conversations.find((c) => c.dm_key === dmKey);
      if (existing) return Promise.resolve(existing);
    }
    if (api) {
      const conversationId = crypto.randomUUID();
      ApiAdapter.write('conversation.create', {
        conversation_id: conversationId, type: opts.type, name: opts.name || null, description: opts.description || null,
        member_ids: memberIds.filter((u) => u !== currentUserId),
      });
      adoptView();
      emit('lime:conversations-changed', { conversationId, kind: 'create' });
      return Promise.resolve(getConversation(conversationId));
    }
    const now = new Date().toISOString();
    const conversation = {
      id: crypto.randomUUID(),
      type: opts.type,
      name: opts.name || null,
      description: opts.description || null,
      created_by: currentUserId,
      deleted_at: null,
      dm_key: opts.type === 'direct' ? [...memberIds].sort().join(':') : null,
      created_at: now,
      updated_at: now,
    };
    conversations.push(conversation);
    memberIds.forEach((userId) => {
      members.push({
        conversation_id: conversation.id,
        user_id: userId,
        role: userId === currentUserId ? 'owner' : 'member',
        starred: false,
        archived_at: null,
        last_read_at: null,
        joined_at: now,
      });
    });
    scheduleSave();
    emit('lime:conversations-changed', { conversationId: conversation.id, kind: 'create' });
    return Promise.resolve(conversation);
  }

  // LIME-27: the Share popover's own "Add people by email" write —
  // owner-only, groups only (can('addMembers') above). A profile already
  // a member is silently skipped, not an error — inviting someone twice
  // (e.g. two people submitting the same email moments apart) should be a
  // no-op, not a failure. Same member-row shape as createConversation's
  // own push, for consistency.
  function addMembers(conversationId, profileIds) {
    const conversation = getConversation(conversationId);
    if (!conversation) return Promise.reject(new Error('LimeStore: no such conversation'));
    if (!can('addMembers', conversation)) return Promise.reject(new Error('LimeStore: not allowed to add members to this conversation'));
    if (api) {
      const have = new Set(members.filter((m) => m.conversation_id === conversationId).map((m) => m.user_id));
      const added = [...new Set(profileIds || [])].filter((u) => !have.has(u));
      if (added.length === 0) return Promise.resolve(conversation);
      ApiAdapter.write('membership.add', { conversation_id: conversationId, user_ids: added });
      adoptView();
      emit('lime:conversations-changed', { conversationId, kind: 'addMembers' });
      return Promise.resolve(getConversation(conversationId));
    }
    const now = new Date().toISOString();
    const existingIds = new Set(getMembers(conversationId).map((p) => p.id));
    const added = [];
    (profileIds || []).forEach((userId) => {
      if (existingIds.has(userId)) return;
      members.push({
        conversation_id: conversationId,
        user_id: userId,
        role: 'member',
        starred: false,
        archived_at: null,
        last_read_at: null,
        joined_at: now,
      });
      added.push(userId);
    });
    if (added.length === 0) return Promise.resolve(conversation);
    conversation.updated_at = now;
    scheduleSave();
    emit('lime:conversations-changed', { conversationId, kind: 'addMembers' });
    return Promise.resolve(conversation);
  }

  function renameConversation(id, name) {
    const conversation = getConversation(id);
    if (!conversation) return Promise.reject(new Error('LimeStore: no such conversation'));
    if (api) {
      ApiAdapter.write('conversation.rename', { conversation_id: id, name });
      adoptView();
      emit('lime:conversations-changed', { conversationId: id, kind: 'rename' });
      return Promise.resolve(getConversation(id));
    }
    conversation.name = name;
    conversation.updated_at = new Date().toISOString();
    scheduleSave();
    emit('lime:conversations-changed', { conversationId: id, kind: 'rename' });
    return Promise.resolve(conversation);
  }

  function setStarred(id, bool) {
    const membership = getMyMembership(id);
    if (!membership) return Promise.reject(new Error('LimeStore: not a member of that conversation'));
    if (api) {
      ApiAdapter.write('membership.setStarred', { conversation_id: id, starred: !!bool });
      adoptView();
      emit('lime:conversations-changed', { conversationId: id, kind: 'star' });
      return Promise.resolve(getMyMembership(id));
    }
    membership.starred = !!bool;
    membership.updated_at = new Date().toISOString(); // LIME-69: lets a merge order two edits
    scheduleSave();
    emit('lime:conversations-changed', { conversationId: id, kind: 'star' });
    return Promise.resolve(membership);
  }

  function setArchived(id, bool) {
    const membership = getMyMembership(id);
    if (!membership) return Promise.reject(new Error('LimeStore: not a member of that conversation'));
    if (api) {
      ApiAdapter.write('membership.setArchived', { conversation_id: id, archived: !!bool });
      adoptView();
      emit('lime:conversations-changed', { conversationId: id, kind: 'archive' });
      return Promise.resolve(getMyMembership(id));
    }
    membership.archived_at = bool ? new Date().toISOString() : null;
    membership.updated_at = new Date().toISOString(); // LIME-69: lets a merge order two edits
    scheduleSave();
    emit('lime:conversations-changed', { conversationId: id, kind: 'archive' });
    return Promise.resolve(membership);
  }

  function deleteConversation(id) {
    const conversation = getConversation(id);
    if (!conversation) return Promise.reject(new Error('LimeStore: no such conversation'));
    if (api) {
      ApiAdapter.write('conversation.delete', { conversation_id: id });
      adoptView();
      emit('lime:conversations-changed', { conversationId: id, kind: 'delete' });
      return Promise.resolve(getConversation(id));
    }
    conversation.deleted_at = new Date().toISOString();
    scheduleSave();
    emit('lime:conversations-changed', { conversationId: id, kind: 'delete' });
    return Promise.resolve(conversation);
  }

  // LIME-34: "delete for me" — sets only your own membership's
  // cleared_at, never conversations.deleted_at (that's the owner-only,
  // delete-for-everyone path above). listConversations/listMessages both
  // already read cleared_at, so hiding is automatic from here.
  function deleteForMe(id) {
    const membership = getMyMembership(id);
    if (!membership) return Promise.reject(new Error('LimeStore: not a member of that conversation'));
    if (api) {
      ApiAdapter.write('conversation.deleteForMe', { conversation_id: id });
      adoptView();
      emit('lime:conversations-changed', { conversationId: id, kind: 'clear' });
      return Promise.resolve(getMyMembership(id));
    }
    membership.cleared_at = new Date().toISOString();
    membership.updated_at = new Date().toISOString(); // LIME-69: lets a merge order two edits
    scheduleSave();
    emit('lime:conversations-changed', { conversationId: id, kind: 'clear' });
    return Promise.resolve(membership);
  }

  function markRead(conversationId) {
    const membership = getMyMembership(conversationId);
    if (!membership) return Promise.reject(new Error('LimeStore: not a member of that conversation'));
    if (api) {
      ApiAdapter.write('membership.markRead', { conversation_id: conversationId }, { replaceQueued: true });
      adoptView();
      emit('lime:conversations-changed', { conversationId, kind: 'read' });
      return Promise.resolve(getMyMembership(conversationId));
    }
    membership.last_read_at = new Date().toISOString();
    membership.updated_at = new Date().toISOString(); // LIME-69: lets a merge order two edits
    scheduleSave();
    emit('lime:conversations-changed', { conversationId, kind: 'read' });
    return Promise.resolve(membership);
  }

  // LIME-31. Email and password are deliberately absent from this list —
  // they're the auth seam's concern (auth.js), not this whitelist; see
  // docs/data-model.md's production-ready rules.
  // LIME-49: avatar_url added — the profiles.avatar_url column already
  // existed in the schema, just never had a writer.
  const PROFILE_EDITABLE_FIELDS = ['display_name', 'pronouns', 'role', 'school', 'grade_levels', 'subjects', 'bio', 'timezone', 'phone', 'avatar_url'];

  function updateProfile(patch) {
    const profile = getProfile(currentUserId);
    if (!profile) return Promise.reject(new Error('LimeStore: no current profile'));
    const keys = Object.keys(patch || {});
    const invalidKeys = keys.filter((k) => !PROFILE_EDITABLE_FIELDS.includes(k));
    if (invalidKeys.length > 0) {
      return Promise.reject(new Error('LimeStore.updateProfile: not editable — ' + invalidKeys.join(', ')));
    }
    if (keys.includes('display_name') && !patch.display_name.trim()) {
      return Promise.reject(new Error('Display name is required.'));
    }
    if (api) {
      ApiAdapter.write('profile.update', { patch });
      adoptView();
      emit('lime:profile-changed', { profileId: currentUserId });
      return Promise.resolve(getProfile(currentUserId));
    }
    Object.assign(profile, patch, { updated_at: new Date().toISOString() });
    scheduleSave();
    emit('lime:profile-changed', { profileId: profile.id });
    return Promise.resolve(profile);
  }

  // LIME-50. A separate function from updateProfile, not folded into its
  // whitelist: appearance is a device/preference concern with its own
  // production table (user_settings), not a profile field a real
  // SupabaseAdapter would ever expose through the profiles.update RLS
  // policy. `patch` merges onto whatever's already set — {canvas: 'x'}
  // alone never touches theme/pattern.
  function setAppearance(patch) {
    const profile = getProfile(currentUserId);
    if (!profile) return Promise.reject(new Error('LimeStore: no current profile'));
    if (api) {
      // Appearance stays on this device (docs/api.md): kept per person in this browser, never sent to the server.
      localAppearance = Object.assign({}, DEFAULT_APPEARANCE, localAppearance, patch);
      try { localStorage.setItem('lime-appearance:' + currentUserId, JSON.stringify(localAppearance)); } catch (e) { /* session only */ }
      emit('lime:appearance-changed', { appearance: localAppearance });
      return Promise.resolve(localAppearance);
    }
    profile.appearance = Object.assign({}, DEFAULT_APPEARANCE, profile.appearance, patch);
    scheduleSave();
    emit('lime:appearance-changed', { appearance: profile.appearance });
    return Promise.resolve(profile.appearance);
  }

  // Not part of updateProfile's whitelist — auth.js's changeEmail is the
  // only intended caller (see docs/data-model.md's "Deviations" section).
  function setProfileEmail(id, email) {
    const profile = getProfile(id);
    if (!profile) return Promise.reject(new Error('LimeStore: no such profile'));
    if (api) {
      return apiWriteAndWait('profile.setEmail', { email }).then(() => { emit('lime:profile-changed', { profileId: id }); return getProfile(id); });
    }
    profile.email = email;
    profile.updated_at = new Date().toISOString();
    scheduleSave();
    emit('lime:profile-changed', { profileId: id });
    return Promise.resolve(profile);
  }

  // LIME-33: the write half of sign-up — a real profile row for a new
  // local account, shaped exactly like a seeded one (normalizeSeed in
  // local-adapter.js) so the new teacher appears in the directory,
  // presence and avatar-initials code identically to a seed teacher. Per
  // the brief, every field but id/email/display_name is null; app.js
  // already guards array fields with `|| []` (e.g. ~4567) and
  // presenceFor(null) already falls back to 'away', so this doesn't need
  // its own defaults for those. auth.js's signUp is the only intended
  // caller — email/password validation and uniqueness live there, not
  // here (mirrors why setProfileEmail doesn't re-validate either).
  function createProfile(options) {
    const opts = options || {};
    const profile = {
      id: opts.id,
      auth_user_id: null,
      display_name: opts.display_name,
      email: opts.email,
      role: null,
      pronouns: null,
      school: null,
      grade_levels: null,
      subjects: null,
      bio: null,
      timezone: null,
      phone: null,
      status: null,
      avatar_url: null,
      created_at: new Date().toISOString(),
      updated_at: new Date().toISOString(),
    };
    profiles.set(profile.id, profile);
    // A synchronous flush, not scheduleSave()'s 100ms debounce: signUp
    // (auth.js) redirects to index.html right after this resolves, and a
    // debounced write racing a real page navigation can lose the write
    // entirely (browsers can drop a pending timer on unload) — the new
    // account would silently vanish. Account creation isn't a hot path
    // where the debounce's batching matters, unlike per-keystroke writes.
    if (saveTimer) {
      clearTimeout(saveTimer);
      saveTimer = null;
    }
    persistNow();
    emit('lime:profile-changed', { profileId: profile.id });
    return Promise.resolve(profile);
  }

  // ── lifecycle ──────────────────────────────────────────────

  function init() {
    // LIME-74: wait for the backend decision (a quick /api/v1/health probe) before reading anything.
    return LimeBackend.ready.then(() => {
      api = LimeBackend.isApi();
      if (!api) {
        loadFromAdapter();
        currentUserId = resolveCurrentUserId();
        return undefined;
      }
      return initApi();
    });
  }

  function initApi() {
    const session = ApiAdapter.session();
    profiles = new Map(); conversations = []; members = []; messages = []; reactions = []; messageAttachments = [];
    if (!session) { currentUserId = null; return Promise.resolve(); } // the sign-in page: nobody yet
    currentUserId = session.userId;
    try { localAppearance = JSON.parse(localStorage.getItem('lime-appearance:' + session.userId) || 'null'); } catch (e) { localAppearance = null; }
    return ApiAdapter.open(session.userId, apiHooks).then(() => {
      adoptView();
      ApiAdapter.start();
    }).catch((err) => {
      if (err && err.code === 'offline' && window.LimeToast) LimeToast.show({ title: 'Can\u2019t reach Lime', body: 'Connect to the internet or start the server, then reload.', tone: 'warning' });
      else console.error('[LimeStore] could not load your data', err);
    });
  }

  // Local adapter only, per docs/data-model.md — "reset" has no meaning
  // against a shared database, so a future SupabaseAdapter has no
  // equivalent for the store to call here.
  // Promise.resolve(...): adapter().reset() returns a Promise since
  // LIME-38 (it also clears the lime-files IndexedDB database, not just
  // localStorage) — wrapping it keeps this working if a future adapter's
  // reset() is synchronous instead.
  function reset() {
    if (api) return ApiAdapter.devReset().then(() => init()); // everyone connected is sent to sign-in
    return Promise.resolve(adapter().reset()).then(() => init());
  }

  // LIME-38.
  // Appearance backgrounds (conversationId 'appearance') stay on this device; everything else goes to the server.
  const isDeviceLocalPath = (path) => !path || path.indexOf('blob:') === 0 || path.indexOf('appearance/') === 0;

  function uploadAttachment(file, options) {
    if (api && !(options && options.conversationId === 'appearance')) return ApiAdapter.uploadFile(file);
    return adapter().uploadAttachment(file, options);
  }

  function getAttachmentUrl(path) {
    if (api && !isDeviceLocalPath(path)) return ApiAdapter.fileUrl(path);
    return adapter().getAttachmentUrl(path);
  }

  // LIME-52-fix3.
  function deleteAttachment(path) {
    if (api && !isDeviceLocalPath(path)) return Promise.resolve(); // the server tidies up files nothing refers to
    return adapter().deleteAttachment(path);
  }

  function checkStorageAvailable() {
    return adapter().checkStorageAvailable();
  }

  // LIME-44.
  function getLinkPreview(url) {
    if (api) return ApiAdapter.linkPreview(url).catch(() => adapter().getLinkPreview(url));
    return adapter().getLinkPreview(url);
  }

  // LIME-74. Directory search (the server matches name/school partially, email and phone exactly, and never reveals them).
  function rememberProfiles(list) { (list || []).forEach((p) => { if (!profiles.has(p.id)) directory.set(p.id, p); }); }
  function searchProfiles(q) {
    if (!api) return Promise.resolve([]);
    return ApiAdapter.searchProfiles(q).then((list) => { rememberProfiles(list); return list; });
  }
  // Find a person by their exact email: chat-mates we already know, otherwise the directory's exact-email match.
  function lookupProfileByEmail(email) {
    const known = findProfileByEmail(email);
    if (known || !api) return Promise.resolve(known);
    return ApiAdapter.searchProfiles(email).then((list) => { rememberProfiles(list); return list[0] || null; });
  }
  const isApi = () => api;

  return {
    init,
    reset,
    flush,
    isRemoteSyncing: () => remoteSyncing,
    getProfile,
    findProfileByEmail,
    listProfiles,
    getCurrentUserId,
    getCurrentUser,
    getConversation,
    getMembers,
    getMyMembership,
    getAppearance,
    listConversations,
    listMessages,
    listReplies,
    getMessage,
    getReactions,
    getAttachments,
    getConversationTitle,
    getLatestActivity,
    can,
    canReason,
    sendMessage,
    toggleReaction,
    createConversation,
    addMembers,
    renameConversation,
    setStarred,
    setArchived,
    setAppearance,
    deleteConversation,
    deleteForMe,
    markRead,
    uploadAttachment,
    getAttachmentUrl,
    deleteAttachment,
    checkStorageAvailable,
    getLinkPreview,
    searchProfiles,
    lookupProfileByEmail,
    isApi,
    updateProfile,
    setProfileEmail,
    createProfile,
  };
})();

// A `const` at a classic <script>'s top level is visible to every other
// script sharing this page (app.js's own `LimeStore.xxx()` calls already
// rely on exactly that), but it isn't automatically a `window` property.
// Exposing it explicitly here is just for anything reaching in from
// outside the page's own scripts (devtools, tests) — the app itself never
// needed this assignment to work.
window.LimeStore = LimeStore;
