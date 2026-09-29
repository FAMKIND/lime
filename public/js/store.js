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
  let currentUserId = null;
  let loggedFallback = false;
  let saveTimer = null;

  function adapter() {
    // The only branch that exists yet — see the file header comment.
    return LocalAdapter;
  }

  function emit(name, detail) {
    document.dispatchEvent(new CustomEvent(name, { detail }));
  }

  function scheduleSave() {
    if (saveTimer) clearTimeout(saveTimer);
    saveTimer = setTimeout(() => {
      saveTimer = null;
      adapter().save({
        profiles: [...profiles.values()],
        conversations,
        conversation_members: members,
        messages,
        message_reactions: reactions,
      });
    }, 100);
  }

  function loadFromAdapter() {
    const state = adapter().load();
    profiles = new Map(state.profiles.map((p) => [p.id, p]));
    conversations = state.conversations;
    members = state.conversation_members;
    messages = state.messages;
    reactions = state.message_reactions;
  }

  // The auth seam (docs/data-model.md): reads lime-demo-session's email
  // and matches it to a profile. No match or no session at all falls back
  // to teacher-002, logged once — not on every call — so the console
  // doesn't fill up with the same notice on every render.
  function resolveCurrentUserId() {
    let email = null;
    try {
      const raw = localStorage.getItem('lime-demo-session');
      if (raw) email = JSON.parse(raw).email;
    } catch (e) {
      // Malformed session value — treat the same as "no session".
    }
    if (email) {
      const match = [...profiles.values()].find((p) => p.email === email);
      if (match) return match.id;
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

  // ── reads ──────────────────────────────────────────────────

  function getProfile(id) {
    return profiles.get(id) || null;
  }

  // Not in docs/data-model.md's original contract list — added in LIME-31
  // (see "Deviations from the contract" there) so changeEmail's own
  // uniqueness check has a way to ask "does any profile already have this
  // email" without reaching into the cache directly.
  function findProfileByEmail(email) {
    return [...profiles.values()].find((p) => p.email === email) || null;
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
      .map((m) => profiles.get(m.user_id))
      .filter(Boolean);
  }

  function getMyMembership(conversationId) {
    return members.find((m) => m.conversation_id === conversationId && m.user_id === currentUserId) || null;
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
      .sort((a, b) => new Date(a.created_at) - new Date(b.created_at));
  }

  function listReplies(messageId) {
    return messages
      .filter((m) => m.reply_to === messageId)
      .sort((a, b) => new Date(a.created_at) - new Date(b.created_at));
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
      .filter((r) => r.message_id === messageId)
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
    return null;
  }

  // ── writes (async — each resolves with the affected record) ──

  function sendMessage(conversationId, options) {
    const opts = options || {};
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
    scheduleSave();
    emit('lime:messages-changed', { conversationId, messageId: message.id, kind: opts.replyTo ? 'reply' : 'message' });
    return Promise.resolve(message);
  }

  function toggleReaction(messageId, emoji) {
    const index = reactions.findIndex((r) => r.message_id === messageId && r.user_id === currentUserId && r.emoji === emoji);
    if (index >= 0) {
      reactions.splice(index, 1);
    } else {
      reactions.push({ message_id: messageId, user_id: currentUserId, emoji, created_at: new Date().toISOString() });
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

  function renameConversation(id, name) {
    const conversation = getConversation(id);
    if (!conversation) return Promise.reject(new Error('LimeStore: no such conversation'));
    conversation.name = name;
    conversation.updated_at = new Date().toISOString();
    scheduleSave();
    emit('lime:conversations-changed', { conversationId: id, kind: 'rename' });
    return Promise.resolve(conversation);
  }

  function setStarred(id, bool) {
    const membership = getMyMembership(id);
    if (!membership) return Promise.reject(new Error('LimeStore: not a member of that conversation'));
    membership.starred = !!bool;
    scheduleSave();
    emit('lime:conversations-changed', { conversationId: id, kind: 'star' });
    return Promise.resolve(membership);
  }

  function setArchived(id, bool) {
    const membership = getMyMembership(id);
    if (!membership) return Promise.reject(new Error('LimeStore: not a member of that conversation'));
    membership.archived_at = bool ? new Date().toISOString() : null;
    scheduleSave();
    emit('lime:conversations-changed', { conversationId: id, kind: 'archive' });
    return Promise.resolve(membership);
  }

  function deleteConversation(id) {
    const conversation = getConversation(id);
    if (!conversation) return Promise.reject(new Error('LimeStore: no such conversation'));
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
    membership.cleared_at = new Date().toISOString();
    scheduleSave();
    emit('lime:conversations-changed', { conversationId: id, kind: 'clear' });
    return Promise.resolve(membership);
  }

  function markRead(conversationId) {
    const membership = getMyMembership(conversationId);
    if (!membership) return Promise.reject(new Error('LimeStore: not a member of that conversation'));
    membership.last_read_at = new Date().toISOString();
    scheduleSave();
    emit('lime:conversations-changed', { conversationId, kind: 'read' });
    return Promise.resolve(membership);
  }

  // LIME-31. Email and password are deliberately absent from this list —
  // they're the auth seam's concern (auth.js), not this whitelist; see
  // docs/data-model.md's production-ready rules.
  const PROFILE_EDITABLE_FIELDS = ['display_name', 'pronouns', 'role', 'school', 'grade_levels', 'subjects', 'bio', 'timezone', 'phone'];

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
    Object.assign(profile, patch, { updated_at: new Date().toISOString() });
    scheduleSave();
    emit('lime:profile-changed', { profileId: profile.id });
    return Promise.resolve(profile);
  }

  // Not part of updateProfile's whitelist — auth.js's changeEmail is the
  // only intended caller (see docs/data-model.md's "Deviations" section).
  function setProfileEmail(id, email) {
    const profile = getProfile(id);
    if (!profile) return Promise.reject(new Error('LimeStore: no such profile'));
    profile.email = email;
    profile.updated_at = new Date().toISOString();
    scheduleSave();
    emit('lime:profile-changed', { profileId: id });
    return Promise.resolve(profile);
  }

  // ── lifecycle ──────────────────────────────────────────────

  function init() {
    loadFromAdapter();
    currentUserId = resolveCurrentUserId();
    return Promise.resolve();
  }

  // Local adapter only, per docs/data-model.md — "reset" has no meaning
  // against a shared database, so a future SupabaseAdapter has no
  // equivalent for the store to call here.
  // Promise.resolve(...): adapter().reset() returns a Promise since
  // LIME-38 (it also clears the lime-files IndexedDB database, not just
  // localStorage) — wrapping it keeps this working if a future adapter's
  // reset() is synchronous instead.
  function reset() {
    return Promise.resolve(adapter().reset()).then(() => init());
  }

  // LIME-38.
  function uploadAttachment(file, options) {
    return adapter().uploadAttachment(file, options);
  }

  function getAttachmentUrl(path) {
    return adapter().getAttachmentUrl(path);
  }

  return {
    init,
    reset,
    getProfile,
    findProfileByEmail,
    getCurrentUserId,
    getCurrentUser,
    getConversation,
    getMembers,
    getMyMembership,
    listConversations,
    listMessages,
    listReplies,
    getMessage,
    getReactions,
    getConversationTitle,
    getLatestActivity,
    can,
    canReason,
    sendMessage,
    toggleReaction,
    createConversation,
    renameConversation,
    setStarred,
    setArchived,
    deleteConversation,
    deleteForMe,
    markRead,
    uploadAttachment,
    getAttachmentUrl,
    updateProfile,
    setProfileEmail,
  };
})();

// A `const` at a classic <script>'s top level is visible to every other
// script sharing this page (app.js's own `LimeStore.xxx()` calls already
// rely on exactly that), but it isn't automatically a `window` property.
// Exposing it explicitly here is just for anything reaching in from
// outside the page's own scripts (devtools, tests) — the app itself never
// needed this assignment to work.
window.LimeStore = LimeStore;
