'use strict';

// LocalAdapter (LIME-24b) — the first implementation of the adapter seam
// docs/data-model.md describes. Persists to localStorage; a later
// SupabaseAdapter implements this exact same shape (load/save/reset)
// against a real database instead. store.js is the only thing that talks
// to this file — nothing else should reference LocalAdapter directly.
const LocalAdapter = (function () {
  const SNAPSHOT_KEY = 'lime-state-v1';

  // ── Attachments (LIME-38) — IndexedDB, not localStorage ──────
  // localStorage's ~5MB total quota can't hold even one attachment near
  // this brief's own 10MB-per-file limit; IndexedDB has no such ceiling
  // in practice. One database, one object store, keyed by `path`.
  const FILES_DB_NAME = 'lime-files';
  const FILES_STORE_NAME = 'attachments';
  const FILES_DB_VERSION = 1;

  function openFilesDb() {
    return new Promise((resolve, reject) => {
      const request = indexedDB.open(FILES_DB_NAME, FILES_DB_VERSION);
      request.onupgradeneeded = () => {
        request.result.createObjectStore(FILES_STORE_NAME, { keyPath: 'path' });
      };
      request.onsuccess = () => resolve(request.result);
      request.onerror = () => reject(request.error);
    });
  }

  // `conversationId` is all `uploadAttachment` gets — there's no
  // `messageId` yet, since the file uploads *before* the message that
  // will reference it exists (sendMessage needs the resolved `path`
  // first). Production's own path shape (schema.sql: conversationId/
  // messageId/filename) isn't available here for that reason — fine,
  // since `path` is opaque to every caller either way (data-model.md).
  function uploadAttachment(file, options) {
    const conversationId = (options && options.conversationId) || 'unfiled';
    const path = conversationId + '/' + crypto.randomUUID() + '-' + file.name;
    return openFilesDb().then((db) => new Promise((resolve, reject) => {
      const tx = db.transaction(FILES_STORE_NAME, 'readwrite');
      tx.objectStore(FILES_STORE_NAME).put({ path, blob: file, name: file.name, mime: file.type, size: file.size });
      tx.oncomplete = () => resolve({ path });
      tx.onerror = () => reject(tx.error);
    }));
  }

  // A fresh object URL every call, never cached here — object URLs are
  // only valid for this page's current lifetime anyway, so there's
  // nothing worth persisting between calls.
  function getAttachmentUrl(path) {
    return openFilesDb().then((db) => new Promise((resolve, reject) => {
      const tx = db.transaction(FILES_STORE_NAME, 'readonly');
      const request = tx.objectStore(FILES_STORE_NAME).get(path);
      request.onsuccess = () => {
        if (!request.result) { reject(new Error('LocalAdapter: no attachment at ' + path)); return; }
        resolve(URL.createObjectURL(request.result.blob));
      };
      request.onerror = () => reject(request.error);
    }));
  }

  // Best-effort, like save()'s own try/catch below — a reset that can't
  // fully clear old attachment blobs shouldn't block the rest of reset
  // (the data snapshot) from going through.
  function resetFiles() {
    return new Promise((resolve) => {
      const request = indexedDB.deleteDatabase(FILES_DB_NAME);
      request.onsuccess = () => resolve();
      request.onerror = () => resolve();
      request.onblocked = () => resolve();
    });
  }

  // ── Link previews (LIME-44) ───────────────────────────────
  // "Built for real and demoed with samples": the *contract*
  // (getLinkPreview(url), resolving to a preview) is the production
  // shape — a real SupabaseAdapter would call the unfurl() Edge Function
  // (docs/data-model.md) and cache the result in a link_previews table
  // instead of this fixture map, but every caller elsewhere (app.js)
  // only ever knows this one Promise-returning function, unchanged
  // either way. No network calls, ever, here — a handful of realistic
  // demo URLs get a full, hand-authored card; anything else gets the
  // brief's own explicit minimal-card fallback (domain as the title, no
  // image), never null — a real unfurl() would also resolve *something*
  // for any well-formed URL, even a bare domain-only fallback, so
  // getLinkPreview here never rejects or resolves null for one either.
  //
  // Images are small inline SVG data URIs, not separate bundled asset
  // files — self-contained in this one file (no new binary asset to
  // manage, no network fetch, nothing to go stale), and deliberately
  // drawn as plain flat-colour cards with a label rather than anything
  // trying to pass as a real screenshot.
  function svgImageDataUri(bg, label) {
    const svg = '<svg xmlns="http://www.w3.org/2000/svg" width="240" height="140">'
      + '<rect width="240" height="140" fill="' + bg + '"/>'
      + '<text x="120" y="76" font-family="system-ui,sans-serif" font-size="20" font-weight="600" fill="#fff" text-anchor="middle">' + label + '</text>'
      + '</svg>';
    return 'data:image/svg+xml,' + encodeURIComponent(svg);
  }

  const LINK_PREVIEW_FIXTURES = {
    'https://www.edutopia.org/article/differentiated-instruction-strategies': {
      title: '10 Differentiated Instruction Strategies That Work',
      description: 'Practical, classroom-tested approaches for reaching every learner, from tiered assignments to flexible grouping.',
      site_name: 'Edutopia',
      image_url: svgImageDataUri('%232d6a4f', 'Edutopia'),
    },
    'https://www.readwritethink.org/classroom-resources/lesson-plans': {
      title: 'Classroom-Ready Lesson Plans',
      description: 'Standards-aligned reading and writing lesson plans for every grade level, free to browse and download.',
      site_name: 'ReadWriteThink',
      image_url: null,
    },
    'https://docs.google.com/forms/d/e/sample-field-trip-permission': {
      title: 'Field Trip Permission Slip — Fall 2026',
      description: 'Please complete this by Friday so your student can join us for the museum visit.',
      site_name: 'Google Forms',
      image_url: svgImageDataUri('%231a73e8', 'Forms'),
    },
  };

  function domainOf(url) {
    try {
      return new URL(url).hostname.replace(/^www\./, '');
    } catch (e) {
      return url;
    }
  }

  function getLinkPreview(url) {
    const fixture = LINK_PREVIEW_FIXTURES[url];
    if (fixture) return Promise.resolve(Object.assign({ url, minimal: false }, fixture));
    return Promise.resolve({
      url,
      minimal: true,
      title: domainOf(url),
      description: null,
      site_name: null,
      image_url: null,
    });
  }

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

  // Same idea as PROFILE_SCHEMA_VERSION, for conversation_members —
  // LIME-34 added cleared_at ("delete for me"). A separate constant
  // rather than folding into the profile one: they version unrelated
  // tables, and a future field on either shouldn't force-invalidate both.
  const MEMBER_SCHEMA_VERSION = 'cleared-v1';

  function seedFingerprint() {
    return hashString(JSON.stringify(window.LIME_SEED_DATA) + JSON.stringify(DEMO_MEMBER_STATE) + PROFILE_SCHEMA_VERSION + MEMBER_SCHEMA_VERSION);
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
          cleared_at: null,
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
      // LIME-41: the seed has no attachments of its own (none of its
      // messages carry metadata.path) — an empty array, not omitted,
      // so callers can always assume the key exists.
      message_attachments: [],
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
              // LIME-41: a snapshot saved before this brief landed has no
              // such key at all — fall back to empty rather than undefined.
              message_attachments: snapshot.message_attachments || [],
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

    // Returns a Promise (unlike load/save) so store.js's own reset() can
    // wait on the IndexedDB deletion too, not just localStorage, before
    // it re-initializes — the "Reset demo data" flow reloads the page
    // right after this resolves.
    reset() {
      localStorage.removeItem(SNAPSHOT_KEY);
      return resetFiles();
    },

    uploadAttachment,
    getAttachmentUrl,
    getLinkPreview,
  };
})();
