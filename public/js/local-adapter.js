'use strict';

// LocalAdapter (LIME-24b) — the first implementation of the adapter seam
// docs/data-model.md describes. Persists to localStorage; a later
// SupabaseAdapter implements this exact same shape (load/save/reset)
// against a real database instead. store.js is the only thing that talks
// to this file — nothing else should reference LocalAdapter directly.
const LocalAdapter = (function () {
  const SNAPSHOT_KEY = 'lime-state-v1';

  // A cheap, deterministic fingerprint of the embedded seed (djb2), not a
  // cryptographic hash — this only ever needs to answer "has the seed this
  // snapshot was built from changed since," so a collision-resistant hash
  // would be solving a problem this doesn't have.
  function hashString(str) {
    let hash = 5381;
    for (let i = 0; i < str.length; i++) {
      hash = ((hash << 5) + hash + str.charCodeAt(i)) | 0;
    }
    return String(hash >>> 0);
  }

  // Demo defaults (LIME-25) so the prototype isn't empty on first load —
  // the current demo user's own membership starts starred on these two
  // conversations. Mirrored in seed-data/seed.ts's own DEMO_MEMBER_STATE
  // so a database seed matches. Folded into the fingerprint below (not a
  // separate version bump) so any future change to these defaults also
  // invalidates an old snapshot automatically, the same as a real seed
  // data change already does.
  const DEMO_MEMBER_STATE = {
    'teacher-002': {
      'conv-001': { starred: true },
      'conv-010': { starred: true },
    },
  };

  // Bumped when the *shape* normalizeSeed produces changes, even if
  // window.LIME_SEED_DATA and DEMO_MEMBER_STATE themselves didn't (LIME-31
  // added profiles.phone) — otherwise an old snapshot, saved before that
  // field existed, would still "validly" match the fingerprint and load
  // with every profile silently missing it.
  const PROFILE_SCHEMA_VERSION = 'phone-v1';

  function seedFingerprint() {
    return hashString(JSON.stringify(window.LIME_SEED_DATA) + JSON.stringify(DEMO_MEMBER_STATE) + PROFILE_SCHEMA_VERSION);
  }

  // Builds the five normalized tables from the embedded seed — run once,
  // the first time this loads with no valid snapshot yet.
  function normalizeSeed(seed) {
    const loadedAt = new Date().toISOString();

    const profiles = seed.teachers.map((t) => ({
      id: t.id,
      // Nullable until a real login links this seed identity to an auth
      // user (docs/data-model.md's auth seam) — no code path sets this
      // locally today, only a future SupabaseAdapter would.
      auth_user_id: null,
      display_name: t.display_name,
      email: t.email,
      role: t.role,
      pronouns: t.pronouns,
      school: t.school,
      grade_levels: t.grade_levels,
      subjects: t.subjects,
      bio: t.bio,
      timezone: t.timezone,
      // LIME-31: no seed teacher has one — the seed JSON never included a
      // phone field, so this normalizes to null for every seeded profile.
      phone: t.phone || null,
      status: t.status,
      avatar_url: null,
      created_at: loadedAt,
      updated_at: loadedAt,
    }));

    const conversations = [];
    const conversationMembers = [];
    seed.conversations.forEach((c) => {
      // LIME-24a-fix: dm_key makes a DM between two people unique — the
      // two member ids, sorted, joined with ':'. Computed here (and again
      // in the store's own createConversation), never by the UI.
      const dmKey = c.type === 'direct' ? [...c.participants].sort().join(':') : null;
      conversations.push({
        id: c.id,
        type: c.type,
        name: c.name || null,
        description: c.description || null,
        created_by: c.created_by || c.participants[0],
        deleted_at: null,
        dm_key: dmKey,
        created_at: c.created_at,
        updated_at: c.updated_at,
      });
      c.participants.forEach((userId) => {
        const demo = (DEMO_MEMBER_STATE[userId] && DEMO_MEMBER_STATE[userId][c.id]) || {};
        conversationMembers.push({
          conversation_id: c.id,
          user_id: userId,
          role: userId === c.created_by ? 'owner' : 'member',
          starred: demo.starred || false,
          archived_at: null,
          last_read_at: null,
          joined_at: c.created_at,
        });
      });
    });

    const messages = [];
    const messageReactions = [];
    seed.messages.forEach((m) => {
      messages.push({
        id: m.id,
        conversation_id: m.conversation_id,
        sender_id: m.sender_id,
        content: m.content != null ? m.content : null,
        type: m.type,
        metadata: m.metadata || null,
        reply_to: m.reply_to || null,
        created_at: m.created_at,
        updated_at: m.created_at,
      });
      if (m.reactions) {
        // The corrected reactor rule (LIME-24a-fix, replacing the
        // dedupe-only suggestion in the first draft): a reaction's
        // reactors are the conversation's distinct members, in
        // participant order, sliced to min(count, member count) — a
        // reaction can't have more reactors than the conversation has
        // members. seed-data/seed.ts uses this exact same rule (see its
        // own comment) so a local seed and a database seed match.
        const conv = seed.conversations.find((c) => c.id === m.conversation_id);
        const memberIds = conv ? conv.participants : [];
        m.reactions.forEach((r) => {
          const reactorCount = Math.min(r.count, memberIds.length);
          memberIds.slice(0, reactorCount).forEach((userId) => {
            messageReactions.push({
              message_id: m.id,
              user_id: userId,
              emoji: r.emoji,
              created_at: m.created_at,
            });
          });
        });
      }
    });

    return {
      profiles,
      conversations,
      conversation_members: conversationMembers,
      messages,
      message_reactions: messageReactions,
    };
  }

  return {
    // Returns { profiles, conversations, conversation_members, messages,
    // message_reactions } — either a persisted snapshot (if one exists and
    // still matches the current embedded seed's fingerprint) or a fresh
    // normalize of that seed.
    load() {
      const fingerprint = seedFingerprint();
      try {
        const raw = localStorage.getItem(SNAPSHOT_KEY);
        if (raw) {
          const snapshot = JSON.parse(raw);
          if (snapshot.seedVersion === fingerprint) {
            return {
              profiles: snapshot.profiles,
              conversations: snapshot.conversations,
              conversation_members: snapshot.conversation_members,
              messages: snapshot.messages,
              message_reactions: snapshot.message_reactions,
            };
          }
        }
      } catch (e) {
        // Corrupt or unparseable snapshot — fall through to a fresh
        // normalize rather than crashing the whole app over stored state.
      }
      return normalizeSeed(window.LIME_SEED_DATA);
    },

    save(state) {
      const snapshot = Object.assign({ seedVersion: seedFingerprint() }, state);
      try {
        localStorage.setItem(SNAPSHOT_KEY, JSON.stringify(snapshot));
      } catch (e) {
        // Storage full or unavailable (private browsing, quota) — the
        // session keeps working in memory, it just won't survive reload.
      }
    },

    reset() {
      localStorage.removeItem(SNAPSHOT_KEY);
    },
  };
})();
