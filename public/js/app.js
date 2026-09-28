'use strict';

// Theme
const theme = localStorage.getItem('lime-theme');
if (theme) document.documentElement.setAttribute('data-theme', theme);

// ── Seed data: contacts list + thread (LIME-06) ──────────
// Promoted to top-level (LIME-11), not IIFE-private — the new replies
// panel needs these same pure helpers and can't reach inside the LIME-06
// closure's scope. None of them depend on that closure's own state
// (list/thread/me/etc.), so hoisting changes nothing about how the
// contacts/thread code below already uses them.
//
// LIME-24b: the contacts/thread IIFE further down no longer runs
// synchronously at parse time — it waits on `LimeStore.init()` (the store
// itself is a separate <script>, loaded before this one) — so nothing
// past it in this file can assume its DOM (the list rows, the initial
// thread) already exists yet. The two things that used to depend on
// that (the Recent-row highlight and the mobile view router's contact
// click) are delegated listeners now instead of one-time scans, exactly
// so they don't care when — or whether — a given row exists yet.
const PRESENCE = { online: 'active', busy: 'busy', offline: 'away' };
const PRESENCE_LABEL = { active: 'Active', busy: 'Busy', away: 'Away' };

function presenceFor(status) {
  return PRESENCE[status] || 'away';
}

function shortName(name) {
  const parts = name.trim().split(/\s+/);
  return parts.length < 2 ? name : parts[0] + ' ' + parts[parts.length - 1][0];
}

// Just the first name — used for a group row's "Jean: " sender prefix
// (LIME-19b). A separate, tinier helper than shortName's "First L." form;
// intentionally duplicated (not shared) with the equivalent used inside
// store.js's own getConversationTitle — both are one-liners private to
// their own file, not worth a shared module for.
function firstName(displayName) {
  return displayName.trim().split(/\s+/)[0];
}

function escapeHtml(str) {
  return String(str).replace(/[&<>"']/g, (c) => ({
    '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;',
  }[c]));
}

function formatTime(iso) {
  return new Date(iso).toLocaleTimeString([], { hour: 'numeric', minute: '2-digit' });
}

function formatDay(iso) {
  return new Date(iso).toLocaleDateString([], { weekday: 'long', month: 'long', day: 'numeric' });
}

// The text after "Last reply " in the reply summary (LIME-18) — compares
// calendar days, not elapsed hours, so a reply from 11pm yesterday reads
// "yesterday", not "23 hours ago".
function formatLastReply(iso) {
  const date = new Date(iso);
  const now = new Date();
  const startOfDay = (d) => new Date(d.getFullYear(), d.getMonth(), d.getDate());
  const diffDays = Math.round((startOfDay(now) - startOfDay(date)) / 86400000);
  if (diffDays <= 0) return 'today at ' + formatTime(iso);
  if (diffDays === 1) return 'yesterday at ' + formatTime(iso);
  if (diffDays <= 29) return diffDays + ' days ago';
  return date.toLocaleDateString([], { month: 'short', day: 'numeric' });
}

function formatDuration(seconds) {
  return Math.floor(seconds / 60) + ':' + String(seconds % 60).padStart(2, '0');
}

function previewFor(message) {
  if (!message) return '';
  if (message.type === 'voice') return '<span class="dew dew-microphone"></span><span class="lime-contact__preview-text">Voice message</span>';
  if (message.type === 'location') return '<span class="dew dew-camera-on"></span><span class="lime-contact__preview-text">' + escapeHtml(message.metadata && message.metadata.place_name || 'Location') + '</span>';
  return '<span class="lime-contact__preview-text">' + escapeHtml(message.content || '') + '</span>';
}

// Plain-text-only variant of previewFor, for contexts (the reply quote)
// that need a readable label rather than previewFor's icon+span HTML.
function plainPreviewFor(message) {
  if (!message) return '';
  if (message.type === 'voice') return 'Voice message';
  if (message.type === 'location') return message.metadata && message.metadata.place_name || 'Location';
  return message.content || '';
}

// Also promoted (LIME-11-fix2) — the reply panel's quote/reply items
// reuse this exact reaction markup/rendering, same reasoning as the
// other promoted helpers above.
const REACTION_PICKER_HTML = '<div class="lime-reaction-picker">'
  + '<button data-emoji="👍">👍</button>'
  + '<button data-emoji="❤️">❤️</button>'
  + '<button data-emoji="😂">😂</button>'
  + '<button data-emoji="😮">😮</button>'
  + '<button data-emoji="🎉">🎉</button>'
  + '<button class="lime-reaction-picker__add" title="More"><span class="dew dew-plus"></span></button>'
  + '</div>';

// LIME-24b: reads live from LimeStore.getReactions rather than taking a
// `reactions` array + separately checking a local hasUserReacted Set — the
// store already returns count and "mine" (whether the current user is one
// of the reactors) per emoji, so there's nothing left to track locally.
function reactionsHtml(messageId) {
  const reactions = LimeStore.getReactions(messageId);
  if (!reactions || reactions.length === 0) return '';
  return reactions
    .map((r) => {
      const active = r.mine ? ' lime-reaction--active' : '';
      return '<button type="button" class="lime-reaction' + active + '" data-emoji="' + r.emoji + '">' + r.emoji + ' <span class="lime-reaction__count">' + r.count + '</span></button>';
    })
    .join('');
}

// Re-renders one message's reaction pills in place (LIME-08) — messageEl
// needs data-message-id since reactionsHtml re-fetches by that id.
function renderReactions(messageEl) {
  const container = messageEl.querySelector('.lime-message__reactions');
  if (container) container.innerHTML = reactionsHtml(messageEl.dataset.messageId);
}

// LIME-18: restores the original Slack-style summary (replier avatars,
// "N replies", "Last reply {when}") in place of LIME-11-fix5's plainer
// "💬 N replies" — like reactions, the count and senders are computed
// live from getRepliesForMessage rather than trusted from the seed
// message's own stale reply_count field. Click reuses the exact same
// openReplies() the "Reply" action button already calls (see the
// "Reply thread panel" closure further down) via a second delegated
// listener on this button's own class. Avatars are the distinct reply
// senders, most recent first, capped at 5 — .seed-avatar-group (Seed's
// own, unmodified) lays them out row-reverse with the last DOM child
// frontmost, so as implemented the *oldest* of the shown avatars ends
// up frontmost/leftmost, not the most recent; flagged at the gate.
function replyIndicatorHtml(messageId) {
  const replies = LimeStore.listReplies(messageId);
  if (replies.length === 0) return '';
  const seenSenders = new Set();
  const avatars = [];
  for (let i = replies.length - 1; i >= 0 && avatars.length < 5; i--) {
    const senderId = replies[i].sender_id;
    if (seenSenders.has(senderId)) continue;
    seenSenders.add(senderId);
    const sender = LimeStore.getProfile(senderId);
    if (sender) avatars.push('<span class="seed-avatar seed-avatar--xs lime-avatar" data-name="' + escapeHtml(sender.display_name) + '"></span>');
  }
  const last = replies[replies.length - 1];
  return '<div class="lime-message__footer">'
    + '<button type="button" class="lime-message__replies" data-message-id="' + messageId + '">'
    + '<span class="seed-avatar-group lime-replies__avatars">' + avatars.join('') + '</span>'
    + '<span class="lime-replies__count">' + replies.length + (replies.length === 1 ? ' reply' : ' replies') + '</span>'
    + '<span class="lime-replies__time">Last reply ' + formatLastReply(last.created_at) + '</span>'
    + '</button>'
    + '</div>';
}

// Keeps the main thread's reply summary correct after a reply is sent
// anywhere (the thread panel), without a full re-render (LIME-17).
// Replaces the whole .lime-message__footer (avatars + count + time all
// change together), not just a count, and paints the fresh avatars —
// they're inserted after the one-time load-time paint pass has already
// run, the same reason handleSend needs its own paintAvatar call.
function refreshReplyIndicator(messageId) {
  const messageEl = document.querySelector('#thread-messages .lime-message[data-message-id="' + messageId + '"]');
  if (!messageEl) return;
  const existing = messageEl.querySelector('.lime-message__footer');
  if (existing) existing.remove();
  const reactionsEl = messageEl.querySelector('.lime-message__reactions');
  if (reactionsEl) reactionsEl.insertAdjacentHTML('afterend', replyIndicatorHtml(messageId));
  messageEl.querySelectorAll('.lime-avatar[data-name]').forEach(paintAvatar);
}

// ── Avatar identity system ──────────────────────────────
// Every .lime-avatar[data-name] gets initials + a color deterministically
// derived from the name (same input always yields the same output, so a
// person's color is stable across the whole app and across reloads).
// Moved above the contacts/thread render below (LIME-18-fix): that
// render's own paintAvatar call (added by LIME-18, for reply-summary
// avatars and to fix a conversation-switch gap) runs during this
// script's very first synchronous pass — before a later `const` in
// this file would otherwise have been initialized, throwing "Cannot
// access 'PALETTE_SIZE' before initialization" and aborting the rest
// of this entire script. That's the actual cause behind a much bigger
// symptom than it looks: once one top-level statement in a script
// throws uncaught, every statement textually after it — every other
// IIFE's click wiring, the reaction picker, the mobile nav, all of
// it — simply never runs. paintAvatar is top-level, not IIFE-private
// (LIME-11), since sent messages, replies, and now conversation
// switches all need to call it themselves — the one-time sweep further
// down only ever reached what already existed at parse time.
const PALETTE_SIZE = 12;

function hashName(name) {
  let hash = 0;
  for (let i = 0; i < name.length; i++) {
    hash = (hash * 31 + name.charCodeAt(i)) | 0;
  }
  return Math.abs(hash) % PALETTE_SIZE;
}

function initialsFor(name) {
  const parts = name.trim().split(/\s+/).filter(Boolean);
  if (parts.length === 0) return '';
  const first = parts[0][0];
  const last = parts.length > 1 ? parts[parts.length - 1][0] : '';
  return (first + last).toUpperCase();
}

function paintAvatar(el) {
  const name = el.dataset.name;
  if (el.dataset.image) {
    const img = document.createElement('img');
    img.src = el.dataset.image;
    img.alt = '';
    el.appendChild(img);
    el.setAttribute('aria-label', name);
    return;
  }
  el.classList.add('lime-avatar--p' + hashName(name));
  el.textContent = initialsFor(name);
  el.setAttribute('aria-label', name);
}

// LIME-20: shared registry for wireDropdownToggle (defined much later
// in this file), so every registered menu can close every *other* one.
// Declared here, not next to the function itself — the reply-composer
// IIFE below calls wireDropdownToggle during this script's very first
// pass, before a later `const` would otherwise be initialized. Exactly
// the LIME-18-fix TDZ crash again; caught this time by actually running
// the app in jsdom before committing, not by reasoning about it.
const registeredDropdowns = new Set();

function initMessagesList() {
  const list = document.getElementById('contacts-list');
  const thread = document.getElementById('thread-messages');
  if (!list || !thread) return;

  const currentUserId = LimeStore.getCurrentUserId();
  const me = LimeStore.getCurrentUser();
  const crumbThread = document.getElementById('crumb-thread');
  const openProfileAvatars = document.getElementById('open-profile-avatars');
  const composerInput = document.getElementById('composer-input');
  const composerSend = document.getElementById('composer-send');

  let currentConversationId = null;
  let lastRenderedDay = null;

  // Members excluding the current user, in the store's own membership
  // order (LIME-24b: this used to read conversation.participants directly;
  // that array no longer exists on a conversation object now that
  // membership is relational — LimeStore.getMembers(id) is the equivalent).
  function otherParticipants(conversation) {
    return LimeStore.getMembers(conversation.id).filter((p) => p.id !== currentUserId);
  }

  // Other participants ordered most-recent-speaker first, then by
  // membership order for anyone who hasn't spoken (LIME-19b). Drives both
  // the list's avatar cluster and the thread header's avatar row — a
  // group's "who's shown first" should track who's actually been talking,
  // not just membership order.
  function orderedOthers(conversation) {
    const others = otherParticipants(conversation);
    const lastSentAt = new Map();
    LimeStore.listMessages(conversation.id).forEach((m) => {
      if (m.sender_id !== currentUserId) lastSentAt.set(m.sender_id, m.created_at);
    });
    return [...others].sort((a, b) => {
      const at = lastSentAt.get(a.id);
      const bt = lastSentAt.get(b.id);
      if (at && bt) return new Date(bt) - new Date(at);
      if (at) return -1;
      if (bt) return 1;
      return 0;
    });
  }

  // ── Reaction picker (add) + reaction pill (toggle) ───────
  // Each reactable container (.lime-message, and — since LIME-11-fix2 —
  // .lime-reply and .lime-replies-panel__quote) has its own local
  // .lime-reaction-picker (a shared single-instance picker wouldn't work
  // with the closest()/querySelector() lookup below, and a shared id
  // would also be invalid HTML repeated across every instance — the
  // markup only carries the class, not an id).
  //
  // REACTABLE used to be just '.lime-message' — the reply panel's old
  // hardcoded messages (LIME-06 left them static) had no real message
  // object to look up, so an `if (!messageId)` fallback quietly created
  // a plain, unpersisted DOM button instead. LIME-11 removed those
  // hardcoded messages entirely and LIME-11-fix2 gave .lime-reply/the
  // quote real data-message-id attributes, so every matched container
  // now always has one — the fallback branch was dead code and is gone.
  const REACTABLE = '.lime-message, .lime-reply, .lime-replies-panel__quote';

  // A reaction made in the thread panel's quote/reply, or in the main
  // thread, must show up everywhere that message is currently on screen
  // (LIME-17) — not just the container the click happened in.
  function renderReactionsEverywhere(messageId) {
    document.querySelectorAll(REACTABLE).forEach((el) => {
      if (el.dataset.messageId === messageId) renderReactions(el);
    });
  }
  // One subscription covers every reaction click anywhere (main thread,
  // reply quote, reply list) — LimeStore.toggleReaction is the only
  // reaction write in the contract (LIME-24b unified the old add-always /
  // toggle-on-existing pair into this one call), and its event is the
  // single source of truth for re-rendering, rather than each click
  // handler re-rendering off its own Promise result.
  document.addEventListener('lime:reactions-changed', (e) => {
    const messageId = e.detail && e.detail.messageId;
    if (messageId) renderReactionsEverywhere(messageId);
  });

  document.addEventListener('click', (e) => {
    const btn = e.target.closest('.lime-message__actions [title="React"]');
    if (btn) {
      // stopImmediatePropagation, not stopPropagation: both this and the
      // "close all open pickers" listener below are bound to the same
      // document target, so stopPropagation (which only blocks moving to
      // a *different* element) wouldn't stop that second listener from
      // firing right after this one and immediately closing what this
      // just opened.
      e.stopImmediatePropagation();
      const container = btn.closest(REACTABLE);
      const picker = container.querySelector('.lime-reaction-picker');
      if (picker && !picker.classList.contains('is-open')) {
        // position:fixed, computed here from the row's own rect — same
        // reasoning as wireDropdownToggle's fixed mode: a scrollable
        // ancestor (the reply panel's list) clips an absolutely
        // positioned popup that opens upward from a row near its top
        // edge, same class of bug LIME-03w fixed for the nav dropdowns.
        const rect = container.getBoundingClientRect();
        picker.style.right = (window.innerWidth - rect.right) + 'px';
        picker.style.bottom = (window.innerHeight - rect.top + 8) + 'px';
      }
      picker?.classList.toggle('is-open');
      return;
    }

    const pickerEmoji = e.target.closest('.lime-reaction-picker [data-emoji]');
    if (pickerEmoji) {
      const msg = pickerEmoji.closest(REACTABLE);
      const messageId = msg.dataset.messageId;
      if (messageId) LimeStore.toggleReaction(messageId, pickerEmoji.dataset.emoji).catch(console.error);
      pickerEmoji.closest('.lime-reaction-picker').classList.remove('is-open');
      return;
    }

    const pill = e.target.closest('.lime-message__reactions .lime-reaction');
    if (pill) {
      const msg = pill.closest(REACTABLE);
      const messageId = msg.dataset.messageId;
      if (!messageId) return;
      LimeStore.toggleReaction(messageId, pill.dataset.emoji).catch(console.error);
    }
  });
  document.addEventListener('click', () => document.querySelectorAll('.lime-reaction-picker.is-open').forEach((p) => p.classList.remove('is-open')));

  function contentHtml(message) {
    if (message.type === 'voice') {
      const duration = message.metadata && message.metadata.duration_seconds || 0;
      return '<div class="lime-message__content lime-message__voice">'
        + '<button type="button" class="lime-voice__play" aria-label="Play voice message"><span class="dew dew-play"></span></button>'
        + '<div class="lime-voice__waveform" aria-hidden="true"></div>'
        + '<span class="lime-voice__duration">' + formatDuration(duration) + '</span>'
        + '</div>';
    }
    if (message.type === 'location') {
      const placeName = message.metadata && message.metadata.place_name || 'Location';
      return '<div class="lime-message__content">'
        + '<div class="lime-message__map" role="img" aria-label="' + escapeHtml(placeName) + '">'
        + '<svg class="lime-message__map-pin" viewBox="0 0 24 24" aria-hidden="true" focusable="false">'
        + '<path fill="currentColor" d="M12 2C7.58 2 4 5.58 4 10c0 5.25 6.34 11.4 7.06 12.06a1.34 1.34 0 0 0 1.88 0C13.66 21.4 20 15.25 20 10c0-4.42-3.58-8-8-8z"/>'
        + '<circle class="lime-message__map-pin-hole" cx="12" cy="10" r="3"/>'
        + '</svg>'
        + '</div>'
        + '</div>';
    }
    return '<div class="lime-message__content"><p class="lime-message__text">' + escapeHtml(message.content || '') + '</p></div>';
  }

  function messageHtml(message, sender, isSent) {
    const presence = presenceFor(sender.status);
    return '<div class="lime-message ' + (isSent ? 'lime-message--sent' : 'lime-message--received') + '" data-message-id="' + message.id + '">'
      + '<span class="lime-avatar-frame lime-avatar-frame--lg">'
      + '<span class="seed-avatar seed-avatar--lg lime-avatar" data-name="' + escapeHtml(sender.display_name) + '"></span>'
      + '<span class="lime-presence" data-presence="' + presence + '" role="img" aria-label="' + PRESENCE_LABEL[presence] + '"></span>'
      + '</span>'
      + '<div class="lime-message__col">'
      + '<div class="lime-message__meta">'
      + '<span class="lime-message__sender">' + escapeHtml(shortName(sender.display_name)) + '</span>'
      + '<span class="lime-message__time">' + formatTime(message.created_at) + '</span>'
      + '</div>'
      + contentHtml(message)
      + '<div class="lime-message__reactions">' + reactionsHtml(message.id) + '</div>'
      + replyIndicatorHtml(message.id)
      + '</div>'
      + '<div class="lime-message__actions">'
      + '<button title="React"><span>🙂</span></button>'
      + '<button title="Reply"><span class="dew dew-chat"></span></button>'
      + '<button title="More"><span class="dew dew-ellipsis-menu"></span></button>'
      + '</div>'
      + REACTION_PICKER_HTML
      + '</div>';
  }

  // Placeholder for a sender id that doesn't resolve to a real profile —
  // shouldn't happen with today's seed data, but LimeStore.getProfile can
  // return null, and messageHtml needs a display_name/status either way.
  const UNKNOWN_SENDER = { display_name: 'Unknown', status: 'offline' };

  function renderThread(conversationId) {
    currentConversationId = conversationId;
    lastRenderedDay = null;
    const msgs = LimeStore.listMessages(conversationId, { threadOnly: true });
    thread.innerHTML = '';
    if (msgs.length === 0) {
      thread.innerHTML = '<p class="lime-messages__empty">No messages yet.</p>';
      return;
    }
    msgs.forEach((m) => {
      const day = formatDay(m.created_at);
      if (day !== lastRenderedDay) {
        thread.insertAdjacentHTML('beforeend', '<div class="lime-date-divider"><span>' + day + '</span></div>');
        lastRenderedDay = day;
      }
      const isSent = m.sender_id === currentUserId;
      // LIME-19b: a group thread has a different sender per message, not
      // one fixed "teacher" for the whole conversation.
      const sender = isSent ? me : (LimeStore.getProfile(m.sender_id) || UNKNOWN_SENDER);
      thread.insertAdjacentHTML('beforeend', messageHtml(m, sender, isSent));
    });
    // LIME-18: needed for a conversation switch, not just the initial
    // load — the one-time document-wide paintAvatar pass (below, in
    // script order) only ever runs once, so anything renderThread
    // inserts afterward (every subsequent selectConversation call) is
    // otherwise left unpainted, same root cause as LIME-11's handleSend fix.
    thread.querySelectorAll('.lime-avatar[data-name]').forEach(paintAvatar);
    // LIME-11-fix3: covers both the initial page-load render (default
    // conversation) and every subsequent conversation switch, since both
    // paths call this same function — renderThread never scrolled at all
    // before this, always leaving the view at the top of the thread.
    thread.scrollTop = thread.scrollHeight;
  }

  // ── Group avatar cluster (LIME-19b) ─────────────────────
  // A reusable "who's in this" mark for group rows, sized to sit inside
  // the same 40px frame a DM's single avatar uses. data-count selects the
  // layout (2 diagonal / 3 triangle / 4 grid); at 5+ others the cluster
  // still caps at 4 tiles — the last becomes a neutral "+N" tile rather
  // than trying to fit a 5th face at this size.
  function avatarClusterMemberHtml(teacher) {
    return '<span class="seed-avatar lime-avatar lime-avatar-cluster__member" data-name="' + escapeHtml(teacher.display_name) + '"></span>';
  }

  function avatarClusterHtml(conversation) {
    const others = orderedOthers(conversation);
    const count = Math.min(others.length, 4);
    let tilesHtml;
    if (others.length > 4) {
      const extra = others.length - 3;
      tilesHtml = others.slice(0, 3).map(avatarClusterMemberHtml).join('')
        + '<span class="lime-avatar-cluster__member lime-avatar-cluster__more">+' + extra + '</span>';
    } else {
      tilesHtml = others.map(avatarClusterMemberHtml).join('');
    }
    return '<span class="lime-avatar-cluster lime-avatar-cluster--lg" data-count="' + count + '">' + tilesHtml + '</span>';
  }

  function directAvatarHtml(conversation) {
    const other = otherParticipants(conversation)[0];
    const presence = presenceFor(other ? other.status : 'offline');
    return '<span class="lime-avatar-frame lime-avatar-frame--lg">'
      + '<span class="seed-avatar seed-avatar--lg lime-avatar" data-name="' + escapeHtml(other ? other.display_name : '') + '"></span>'
      + '<span class="lime-presence" data-presence="' + presence + '" role="img" aria-label="' + PRESENCE_LABEL[presence] + '"></span>'
      + '</span>';
  }

  // For a group, prefixes the preview with who sent it ("Jean: " / "You: ")
  // — previewFor already wraps its text in one .lime-contact__preview-text
  // span (for all three message types), so the prefix is spliced into that
  // same span rather than duplicating previewFor's icon/voice/location
  // branching here.
  function rowPreviewHtml(conversation, latest) {
    if (!latest) return '<span class="lime-contact__preview-text">No messages yet</span>';
    if (conversation.type !== 'group') return previewFor(latest);
    const sender = latest.sender_id === currentUserId ? null : LimeStore.getProfile(latest.sender_id);
    const label = sender ? firstName(sender.display_name) : 'You';
    const prefix = escapeHtml(label + ': ');
    return previewFor(latest).replace('<span class="lime-contact__preview-text">', '<span class="lime-contact__preview-text">' + prefix);
  }

  function conversationRowHtml(conversation, latest) {
    const isGroup = conversation.type === 'group';
    const title = LimeStore.getConversationTitle(conversation);
    const avatarHtml = isGroup ? avatarClusterHtml(conversation) : directAvatarHtml(conversation);
    // LIME-19b-fix: the member count read as an unread/comment count here
    // and was removed from the list — it still shows in the thread header.
    return avatarHtml
      + '<div class="lime-contact__body">'
      + '<span class="lime-contact__name">' + escapeHtml(title) + '</span>'
      + '<span class="lime-contact__preview">' + rowPreviewHtml(conversation, latest) + '</span>'
      + '</div>'
      + '<div class="lime-contact__meta">'
      + '<span class="lime-contact__time">' + (latest ? formatTime(latest.created_at) : '') + '</span>'
      + '</div>';
  }

  function conversationSearchText(conversation) {
    const names = LimeStore.getMembers(conversation.id).map((p) => p.display_name);
    return (LimeStore.getConversationTitle(conversation) + ' ' + names.join(' ')).toLowerCase();
  }

  // Header avatars for whichever conversation is open (#open-profile-avatars).
  // DMs keep the existing two-avatar seed-avatar-group exactly; groups get
  // up to 5 most-recent-speaker-first faces (fits beside the breadcrumb and
  // the "…" button, even at mobile width — the brief flags this 5 cap as
  // something the user may want raised) plus a neutral "+N" tile and a
  // muted total-member-count label. Rebuilt on every selectConversation —
  // this used to be static "Shem R"/"Jean Chung" markup that never changed.
  const HEADER_AVATAR_CAP = 5;

  function conversationHeaderAvatarsHtml(conversation) {
    if (conversation.type !== 'group') {
      const other = otherParticipants(conversation)[0];
      return '<span class="seed-avatar-group lime-topbar__avatars">'
        + '<span class="seed-avatar seed-avatar--sm lime-avatar" data-name="' + escapeHtml(me.display_name) + '"></span>'
        + '<span class="seed-avatar seed-avatar--sm lime-avatar" data-name="' + escapeHtml(other ? other.display_name : '') + '"></span>'
        + '</span>';
    }
    const others = orderedOthers(conversation);
    const shown = others.slice(0, HEADER_AVATAR_CAP);
    const extra = others.length - HEADER_AVATAR_CAP;
    // LIME-19b-fix: seed-avatar-group is row-reverse (first DOM child
    // renders rightmost), so to read left-to-right as "most recent
    // speaker … 5th speaker, then +N", the DOM order has to be built
    // backwards — +N first, then the shown avatars from last to first.
    let avatarsHtml = '';
    if (extra > 0) {
      avatarsHtml += '<span class="seed-avatar seed-avatar--sm lime-avatar-cluster__more" aria-hidden="true">+' + extra + '</span>';
    }
    avatarsHtml += [...shown].reverse().map((t) => '<span class="seed-avatar seed-avatar--sm lime-avatar" data-name="' + escapeHtml(t.display_name) + '"></span>').join('');
    const allNames = others.map((t) => t.display_name).join(', ');
    return '<span class="seed-avatar-group lime-topbar__avatars" title="' + escapeHtml(allNames) + '">' + avatarsHtml + '</span>'
      + '<span class="lime-topbar__member-count">' + LimeStore.getMembers(conversation.id).length + ' members</span>';
  }

  function selectConversation(conversation) {
    document.querySelectorAll('.lime-contact').forEach((el) => el.classList.remove('lime-contact--active'));
    document.querySelectorAll('[data-conversation-id="' + conversation.id + '"]').forEach((el) => el.classList.add('lime-contact--active'));
    if (crumbThread) crumbThread.textContent = LimeStore.getConversationTitle(conversation);
    if (openProfileAvatars) {
      openProfileAvatars.innerHTML = conversationHeaderAvatarsHtml(conversation);
      openProfileAvatars.querySelectorAll('.lime-avatar[data-name]').forEach(paintAvatar);
    }
    renderThread(conversation.id);
  }

  // ── Send message (LIME-07) ─────────────────────────────
  function handleSend() {
    if (!composerInput || !currentConversationId) return;
    const content = composerInput.value.trim();
    if (!content) return;
    const conversationId = currentConversationId;

    LimeStore.sendMessage(conversationId, { content }).then((message) => {
      if (conversationId !== currentConversationId) return; // switched threads before this resolved
      const emptyState = thread.querySelector('.lime-messages__empty');
      if (emptyState) emptyState.remove();

      const day = formatDay(message.created_at);
      if (day !== lastRenderedDay) {
        thread.insertAdjacentHTML('beforeend', '<div class="lime-date-divider"><span>' + day + '</span></div>');
        lastRenderedDay = day;
      }
      thread.insertAdjacentHTML('beforeend', messageHtml(message, me, true));
      const newAvatar = thread.querySelector('.lime-message:last-child .lime-avatar[data-name]');
      if (newAvatar) paintAvatar(newAvatar); // real bug (LIME-11): paintAvatar only ran once at load, missing every sent message's avatar since LIME-07
      thread.scrollTop = thread.scrollHeight;
    }).catch(console.error);

    // Clearing the composer doesn't wait on the write — LIME-24b's
    // optimistic-update principle applies to the *cache* (updated
    // synchronously inside the store before its Promise resolves), but the
    // UI's own "instant" feel has always meant not waiting on anything.
    composerInput.value = '';
    composerInput.style.height = ''; // drop the auto-grow inline height (LIME-10)
    // Setting .value directly doesn't fire an 'input' event, so the
    // is-active toggle (LIME-10-fix14, wired to that event elsewhere)
    // never sees this clear on its own — reset it here explicitly,
    // otherwise Send stays looking "active" after a message is sent.
    if (composerSend) composerSend.classList.remove('is-active');
  }

  if (composerInput) {
    composerInput.addEventListener('keydown', (e) => {
      if (e.key === 'Enter' && !e.shiftKey) {
        e.preventDefault();
        handleSend();
      }
    });
  }
  if (composerSend) composerSend.addEventListener('click', handleSend);

  // ── Merged Messages list (LIME-19b, delegated LIME-24b) ──
  // Direct + group conversations in one list, newest activity first
  // (no-activity conversations last, alphabetical among themselves).
  // refreshList() both builds the list the first time and re-syncs it on
  // every lime:conversations-changed/lime:messages-changed event — rows
  // can be created (a brand new conversation) or disappear (deleted,
  // archived) at any time now, not just reordered, so every pass
  // recomputes the full membership rather than assuming yesterday's set
  // of rows is still the right one. Existing rows are updated and moved
  // in place (never recreated) — later code (recent-highlight and the
  // mobile view router, both further down this file) delegates its own
  // click handling for exactly this reason, rather than binding once to
  // whatever rows happen to exist at that moment.
  function sortConversations(conversations) {
    return [...conversations].sort((a, b) => {
      const la = LimeStore.getLatestActivity(a.id);
      const lb = LimeStore.getLatestActivity(b.id);
      if (la && lb) return new Date(lb.created_at) - new Date(la.created_at);
      if (la) return -1;
      if (lb) return 1;
      return LimeStore.getConversationTitle(a).localeCompare(LimeStore.getConversationTitle(b));
    });
  }

  function buildRow(conversation) {
    const latest = LimeStore.getLatestActivity(conversation.id);
    const li = document.createElement('li');
    li.className = 'lime-contact';
    li.dataset.conversationId = conversation.id;
    li.dataset.searchText = conversationSearchText(conversation);
    li.innerHTML = conversationRowHtml(conversation, latest);
    li.addEventListener('click', () => selectConversation(conversation));
    li.querySelectorAll('.lime-avatar[data-name]').forEach(paintAvatar);
    return li;
  }

  function updateRow(li, conversation) {
    const latest = LimeStore.getLatestActivity(conversation.id);
    const previewEl = li.querySelector('.lime-contact__preview');
    const timeEl = li.querySelector('.lime-contact__time');
    if (previewEl) previewEl.innerHTML = rowPreviewHtml(conversation, latest);
    if (timeEl) timeEl.textContent = latest ? formatTime(latest.created_at) : '';
  }

  // Shared by "All" and "Starred" (LIME-25) — same row shape, same
  // update-in-place/build-if-missing/drop-if-gone diff, just a different
  // target <ul> and (Starred only) source filter and empty-state message.
  function syncSection(container, conversations, emptyMessage) {
    const sorted = sortConversations(conversations);
    if (sorted.length === 0 && emptyMessage) {
      container.innerHTML = '<li class="lime-contact-list__empty">' + escapeHtml(emptyMessage) + '</li>';
      return sorted;
    }
    const seenIds = new Set();
    sorted.forEach((conversation) => {
      seenIds.add(conversation.id);
      let li = container.querySelector('[data-conversation-id="' + conversation.id + '"]');
      if (li) {
        updateRow(li, conversation);
      } else {
        li = buildRow(conversation);
      }
      // appendChild on an already-attached node moves it — this both
      // places brand-new rows and re-sorts existing ones in the same pass.
      container.appendChild(li);
    });
    [...container.children].forEach((li) => {
      if (!seenIds.has(li.dataset.conversationId)) li.remove();
    });
    return sorted;
  }

  const starredList = document.getElementById('starred-list');

  function starredConversations() {
    return LimeStore.listConversations({ types: ['direct', 'group'] }).filter((c) => {
      const membership = LimeStore.getMyMembership(c.id);
      return membership && membership.starred;
    });
  }

  let messageConversations = syncSection(list, LimeStore.listConversations({ types: ['direct', 'group'] }));
  if (starredList) syncSection(starredList, starredConversations(), 'Star a chat from its title menu.');

  document.addEventListener('lime:conversations-changed', () => {
    messageConversations = syncSection(list, LimeStore.listConversations({ types: ['direct', 'group'] }));
    if (starredList) syncSection(starredList, starredConversations(), 'Star a chat from its title menu.');
  });
  document.addEventListener('lime:messages-changed', () => {
    messageConversations = syncSection(list, LimeStore.listConversations({ types: ['direct', 'group'] }));
    if (starredList) syncSection(starredList, starredConversations(), 'Star a chat from its title menu.');
  });

  // ── Conversation actions menu (LIME-25) ─────────────────
  // Rebuilt fresh from CONVERSATION_ACTIONS every time it opens, for
  // whichever conversation is currently open — never assembled once and
  // left stale, since Star/Unstar's own label depends on live state.
  const conversationMenu = document.getElementById('conversation-menu');
  const conversationMenuToggle = document.getElementById('conversation-menu-toggle');

  function renderConversationMenu() {
    if (!conversationMenu || !currentConversationId) return;
    const conversation = LimeStore.getConversation(currentConversationId);
    if (!conversation) return;
    const membership = LimeStore.getMyMembership(currentConversationId);
    conversationMenu.innerHTML = CONVERSATION_ACTIONS
      .filter((action) => !action.isVisible || action.isVisible(conversation, membership))
      .map((action) => {
        const label = typeof action.label === 'function' ? action.label(conversation, membership) : action.label;
        const dangerClass = action.danger ? ' lime-menu__item--danger' : '';
        return '<button type="button" class="lime-menu__item' + dangerClass + '" role="menuitem" data-action="' + action.id + '">'
          + '<span class="dew ' + action.icon + '"></span>' + escapeHtml(label)
          + '<span class="lime-menu__kbd">' + escapeHtml(action.key) + '</span>'
          + '</button>';
      })
      .join('');
  }

  function runConversationAction(actionId) {
    if (!currentConversationId) return;
    const action = CONVERSATION_ACTIONS.find((a) => a.id === actionId);
    if (!action) return;
    const conversation = LimeStore.getConversation(currentConversationId);
    const membership = LimeStore.getMyMembership(currentConversationId);
    if (!conversation) return;
    action.run(conversation, membership).catch(console.error);
    if (conversationMenu) conversationMenu.classList.remove('is-open');
  }

  if (conversationMenuToggle) {
    // Registered before wireDropdownToggle's own click listener below (on
    // the same button, same event) — listeners fire in registration
    // order, so the menu's contents are already fresh by the time that
    // one measures offsetHeight/offsetWidth to position it.
    conversationMenuToggle.addEventListener('click', renderConversationMenu);
  }
  if (conversationMenu) {
    conversationMenu.addEventListener('click', (e) => {
      const item = e.target.closest('[data-action]');
      if (item) runConversationAction(item.dataset.action);
    });
  }
  // The hint-key shortcut ("like Claude's") — only while the menu is open,
  // and not while the user is actually typing somewhere (a plain "s"
  // keystroke in the composer shouldn't star the open conversation).
  document.addEventListener('keydown', (e) => {
    if (!conversationMenu || !conversationMenu.classList.contains('is-open')) return;
    const active = document.activeElement;
    if (active && (active.tagName === 'INPUT' || active.tagName === 'TEXTAREA' || active.isContentEditable)) return;
    const action = CONVERSATION_ACTIONS.find((a) => a.key.toLowerCase() === e.key.toLowerCase());
    if (action) runConversationAction(action.id);
  });
  // aria-expanded has no single choke point to update from (the menu can
  // close via its own toggle, an outside click, Escape, or another
  // dropdown opening) — a MutationObserver on its own is-open class covers
  // every path without touching wireDropdownToggle's shared logic.
  if (conversationMenu && conversationMenuToggle) {
    new MutationObserver(() => {
      conversationMenuToggle.setAttribute('aria-expanded', String(conversationMenu.classList.contains('is-open')));
    }).observe(conversationMenu, { attributes: true, attributeFilter: ['class'] });
  }
  if (conversationMenuToggle) wireDropdownToggle('conversation-menu-toggle', 'conversation-menu', { fixed: true });

  if (messageConversations.length > 0) {
    selectConversation(messageConversations[0]);
  }
}

// LIME-25: the title caret's menu. One action today (Star); built as a
// data-driven list from the start, per the brief, so LIME-26/27 add Rename,
// Share, Copy link, Archive and Delete as more entries here, not by
// restructuring how the menu itself is built or wired.
const CONVERSATION_ACTIONS = [
  {
    id: 'star',
    label: (conversation, membership) => (membership && membership.starred ? 'Unstar' : 'Star'),
    icon: 'dew-star',
    key: 'S',
    danger: false,
    isVisible: () => true,
    run: (conversation, membership) => LimeStore.setStarred(conversation.id, !(membership && membership.starred)),
  },
];

LimeStore.init().then(initMessagesList).catch(console.error);

// ── Contact preview truncation ───────────────────────────
// text-overflow: ellipsis has no effect on a flex container (only on
// block containers per spec) — .lime-contact__preview is flex so an
// optional leading icon lines up with the text. Wrapping the trailing
// text node in its own span gives ellipsis something it'll actually
// apply to, without needing every instance of the markup rewritten.
(function () {
  document.querySelectorAll('.lime-contact__preview').forEach((el) => {
    const textNodes = [...el.childNodes].filter((n) => n.nodeType === Node.TEXT_NODE && n.textContent.trim());
    if (textNodes.length === 0) return;
    const span = document.createElement('span');
    span.className = 'lime-contact__preview-text';
    textNodes.forEach((n) => span.appendChild(n));
    el.appendChild(span);
  });
})();

// ── Avatar identity system (declarations moved above the contacts/
// thread render below — see LIME-18-fix comment there for why) ──
// This one-time sweep still runs here, after that render: it catches
// the static Recent-row avatars, the sidebar's own avatar, and the
// contact list's rows, none of which call paintAvatar individually.
document.querySelectorAll('.lime-avatar[data-name]').forEach(paintAvatar);

// ── Panel resize (outer left/right dividers) ─────────────
(function () {
  const layout      = document.getElementById('layout');
  const leftHandle  = document.getElementById('left-handle');
  const rightHandle = document.getElementById('right-handle');
  if (!layout || !leftHandle || !rightHandle) return;

  const MIN_LEFT   = 200; // nav-only panel, no conversation list anymore
  const MIN_RIGHT  = 240;
  const MIN_CENTER = 800; // 320px conversation list + 480px chat, both live here now
  const GAP        = 16;

  function getWidth(prop, fallback) {
    return parseFloat(getComputedStyle(layout).getPropertyValue(prop)) || fallback;
  }

  function initResize(handleEl, side) {
    const prop     = side === 'left' ? '--left-width'  : '--right-width';
    const other    = side === 'left' ? '--right-width' : '--left-width';
    const min      = side === 'left' ? MIN_LEFT  : MIN_RIGHT;
    const otherMin = side === 'left' ? MIN_RIGHT : MIN_LEFT;
    const storeKey = side === 'left' ? 'lime-left-width' : 'lime-right-width';

    handleEl.addEventListener('mousedown', (e) => {
      e.preventDefault();

      const startX     = e.clientX;
      const startWidth = getWidth(prop, min);
      let   pendingX   = startX;
      let   rafId      = null;

      handleEl.classList.add('is-dragging');
      layout.classList.add('is-resizing');
      layout.style.willChange         = 'grid-template-columns';
      document.body.style.cursor     = 'col-resize';
      document.body.style.userSelect = 'none';

      function onMove(e) {
        pendingX = e.clientX;
        if (rafId) return;
        rafId = requestAnimationFrame(() => {
          rafId = null;
          const contentW  = layout.clientWidth - 2 * GAP;
          const otherW    = getWidth(other, otherMin);
          const maxWidth  = Math.max(min, contentW - otherW - 2 * GAP - MIN_CENTER);
          const delta     = side === 'left' ? pendingX - startX : startX - pendingX;
          const newWidth  = Math.max(min, Math.min(maxWidth, startWidth + delta));
          layout.style.setProperty(prop, newWidth + 'px');
        });
      }

      function onUp() {
        if (rafId) cancelAnimationFrame(rafId);
        handleEl.classList.remove('is-dragging');
        layout.classList.remove('is-resizing');
        layout.style.willChange        = '';
        document.body.style.cursor     = '';
        document.body.style.userSelect = '';
        document.removeEventListener('mousemove', onMove);
        document.removeEventListener('mouseup',   onUp);
        localStorage.setItem(storeKey, getWidth(prop, min));
      }

      document.addEventListener('mousemove', onMove);
      document.addEventListener('mouseup',   onUp);
    });
  }

  const savedLeft  = localStorage.getItem('lime-left-width');
  const savedRight = localStorage.getItem('lime-right-width');
  if (savedLeft)  layout.style.setProperty('--left-width',  savedLeft  + 'px');
  if (savedRight) layout.style.setProperty('--right-width', savedRight + 'px');

  initResize(leftHandle,  'left');
  initResize(rightHandle, 'right');
})();

// ── Center divider (conversation list ↔ chat) ────────────
(function () {
  const centerBody = document.querySelector('.lime-center-body');
  const listCol    = document.getElementById('list-col');
  const handle     = document.getElementById('center-handle');
  if (!centerBody || !listCol || !handle) return;

  const MIN_LIST      = 240;
  const MIN_CHAT      = 480;
  const HANDLE_WIDTH  = 16;

  function getListWidth() {
    return parseFloat(getComputedStyle(listCol).width) || 320;
  }

  const saved = localStorage.getItem('lime-list-width');
  if (saved) listCol.style.setProperty('--list-width', saved + 'px');

  handle.addEventListener('mousedown', (e) => {
    e.preventDefault();

    const startX     = e.clientX;
    const startWidth = getListWidth();
    let   pendingX   = startX;
    let   rafId      = null;

    handle.classList.add('is-dragging');
    document.body.style.cursor     = 'col-resize';
    document.body.style.userSelect = 'none';

    function onMove(e) {
      pendingX = e.clientX;
      if (rafId) return;
      rafId = requestAnimationFrame(() => {
        rafId = null;
        const maxWidth = Math.max(MIN_LIST, centerBody.clientWidth - HANDLE_WIDTH - MIN_CHAT);
        const delta    = pendingX - startX;
        const newWidth = Math.max(MIN_LIST, Math.min(maxWidth, startWidth + delta));
        listCol.style.setProperty('--list-width', newWidth + 'px');
      });
    }

    function onUp() {
      if (rafId) cancelAnimationFrame(rafId);
      handle.classList.remove('is-dragging');
      document.body.style.cursor     = '';
      document.body.style.userSelect = '';
      document.removeEventListener('mousemove', onMove);
      document.removeEventListener('mouseup',   onUp);
      localStorage.setItem('lime-list-width', getListWidth());
    }

    document.addEventListener('mousemove', onMove);
    document.addEventListener('mouseup',   onUp);
  });
})();

// Wires a toggle button whose icon (a) reflects the current state at rest
// and (b) previews the *other* state on hover — a common affordance for
// "here's what clicking this does". `paint(showAlt)` draws either the
// resting icon or its alternate; `apply(next)` commits a state change.
function wireHoverPreviewToggle(toggle, initial, paint, apply) {
  let state = initial;
  paint(state);

  toggle.addEventListener('mouseenter', () => paint(!state));
  toggle.addEventListener('mouseleave', () => paint(state));
  toggle.addEventListener('click', () => {
    state = !state;
    apply(state);
    paint(!state); // still hovering post-click — keep previewing the next toggle
  });

  // External closers (Escape, a breakpoint change) call this so the
  // toggle's own private state stays in sync and its next click is correct.
  return {
    set(next) {
      state = next;
      apply(state);
      paint(state);
    },
  };
}

// Shared by every trigger that opens/closes the right panel
// (open-profile-avatars, open-replies, #right-panel-toggle itself, the
// mobile router, auto-collapse-on-shrink, and the LIME-03n message
// sender/avatar triggers below) — the single place that actually flips
// the panel's open/closed state, so every trigger stays correct
// regardless of how #right-panel-toggle itself is currently wired.
function setRightPanelOpen(isOpen) {
  const layout = document.getElementById('layout');
  const toggle = document.getElementById('right-panel-toggle');
  if (!layout) return;
  layout.classList.toggle('seed-layout--right-hidden', !isOpen);
  if (toggle) toggle.setAttribute('aria-expanded', String(isOpen));
  localStorage.setItem('lime-right-panel-open', String(isOpen));
}

// ── Left nav panel toggle ────────────────────────────────
// Expanded (icon + label, full conversation list) is the default. The
// header toggle collapses it to Seed's 56px icon rail — it does not hide
// the panel outright.
(function () {
  const layout = document.getElementById('layout');
  const toggle = document.getElementById('left-panel-toggle');
  if (!layout || !toggle) return;

  const icon = toggle.querySelector('.dew');
  const COLLAPSED_WIDTH = 56;

  function paintIcon(isExpanded) {
    icon.classList.toggle('dew-sidebar-left-open',   isExpanded);
    icon.classList.toggle('dew-sidebar-left-closed', !isExpanded);
  }

  function applyExpanded(isExpanded) {
    layout.classList.toggle('seed-layout--collapsed-left', !isExpanded);
    if (isExpanded) {
      const saved = localStorage.getItem('lime-left-width');
      layout.style.setProperty('--left-width', (saved || '200') + 'px');
    } else {
      layout.style.setProperty('--left-width', COLLAPSED_WIDTH + 'px');
    }
    toggle.setAttribute('aria-expanded', String(isExpanded));
    localStorage.setItem('lime-left-panel-open', String(isExpanded));
  }

  // Starts expanded regardless of a stale localStorage value from an older
  // build — only an explicit "false" (the user collapsed it) keeps it closed.
  const saved = localStorage.getItem('lime-left-panel-open') !== 'false';
  applyExpanded(saved);
  wireHoverPreviewToggle(toggle, saved, paintIcon, applyExpanded);
})();

// ── Right profile panel toggle ──────────────────────────
// #right-panel-toggle has moved between .lime-center-top (a full
// open/close toggle) and inside #right-panel (close-only) repeatedly
// across recent briefs — LIME-03l in, LIME-03n out, LIME-03p in,
// LIME-03t out, LIME-03z in again. Currently: close-only, no
// icon-swap, since there's nothing to preview toward.
(function () {
  const layout = document.getElementById('layout');
  const toggle = document.getElementById('right-panel-toggle');
  if (!layout || !toggle) return;

  // Default flipped true -> false (LIME-10-fix9) — only changes first-ever
  // load with no saved preference; setRightPanelOpen always persists
  // whatever it's given, so anyone who already has a saved value (true or
  // false) from before this brief keeps seeing that, not this new default.
  const saved = localStorage.getItem('lime-right-panel-open');
  setRightPanelOpen(saved === null ? false : saved === 'true');

  toggle.addEventListener('click', () => setRightPanelOpen(false));

  // Second trigger: the participant avatar in the center top row opens
  // the panel (never closes it — closing is the dedicated button's job
  // now). The breadcrumb's "Jean Chung" segment (#crumb-thread) used to
  // double as this same trigger, but LIME-03g redefined it to mean "go
  // to thread" instead — it no longer opens the profile panel.
  const openProfileAvatars = document.getElementById('open-profile-avatars');
  if (openProfileAvatars) {
    openProfileAvatars.addEventListener('click', () => {
      if (layout.classList.contains('seed-layout--right-hidden')) setRightPanelOpen(true);
    });
  }
})();

// ── Profile panel opens from any message's sender name/avatar ──
// LIME-03n: clicking a sender name or avatar anywhere in the thread
// (not just the topbar avatar-group/breadcrumb) opens the profile view
// specifically (not replies). Uses setRightPanelOpen directly rather
// than simulating a click on #right-panel-toggle, since that button's
// own semantics have changed more than once across recent briefs.
(function () {
  const layout     = document.getElementById('layout');
  const rightPanel = document.getElementById('right-panel');
  if (!layout || !rightPanel) return;

  document.querySelectorAll('.lime-message__sender, .lime-message .lime-avatar').forEach((el) => {
    el.style.cursor = 'pointer';
    el.addEventListener('click', () => {
      if (layout.classList.contains('seed-layout--right-hidden')) setRightPanelOpen(true);
      rightPanel.setAttribute('data-panel', 'profile');
      layout.setAttribute('data-mobile-view', 'panel');
    });
  });
})();

// ── Reply thread panel ────────────────────────────────────
// #open-replies (the old trigger this listened for) was deleted from the
// markup back in LIME-06, when the hardcoded thread messages it lived on
// were removed — this whole handler, including the back button, has
// been dead code ever since (its early-return guard always fired since
// that id no longer existed). Rebuilt for LIME-11 as a delegated click
// on any thread message's real "Reply" action instead of a one-time
// forEach, so it keeps working after switching conversations replaces
// #thread-messages's content entirely. LIME-11-fix2 removed the back
// button from the markup entirely (no JS reference needed any more) and
// added reactions to the quote/replies, reusing .lime-message__actions/
// .lime-reaction-picker — see the generalized delegate further down.
(function () {
  const layout      = document.getElementById('layout');
  const rightPanel  = document.getElementById('right-panel');
  const quoteEl     = document.getElementById('replies-quote');
  const metaEl      = document.getElementById('replies-meta');
  const listEl      = document.getElementById('replies-list');
  const replyInput  = document.getElementById('replies-composer-input');
  const replySend   = document.getElementById('replies-composer-send');
  if (!layout || !rightPanel || !quoteEl || !listEl) return;

  let currentReplyParentId = null;

  function replyHtml(message, sender) {
    return '<div class="lime-reply" data-message-id="' + message.id + '">'
      + '<span class="seed-avatar seed-avatar--sm lime-avatar" data-name="' + escapeHtml(sender.display_name) + '"></span>'
      + '<div class="lime-reply__col">'
      + '<div class="lime-reply__meta">'
      + '<span class="lime-reply__sender">' + escapeHtml(shortName(sender.display_name)) + '</span>'
      + '<span class="lime-reply__time">' + formatTime(message.created_at) + '</span>'
      + '</div>'
      + '<p class="lime-reply__text">' + escapeHtml(plainPreviewFor(message)) + '</p>'
      + '<div class="lime-message__reactions">' + reactionsHtml(message.id) + '</div>'
      + '</div>'
      + '<div class="lime-message__actions">'
      + '<button title="React"><span>🙂</span></button>'
      + '</div>'
      + REACTION_PICKER_HTML
      + '</div>';
  }

  function renderQuote(message, sender) {
    quoteEl.dataset.messageId = message.id;
    quoteEl.innerHTML = '<span class="seed-avatar seed-avatar--sm lime-avatar" data-name="' + escapeHtml(sender.display_name) + '"></span>'
      + '<div class="lime-replies-panel__quote-body">'
      + '<span class="lime-replies-panel__quote-sender">' + escapeHtml(shortName(sender.display_name)) + '</span>'
      + '<p class="lime-replies-panel__quote-text">' + escapeHtml(plainPreviewFor(message)) + '</p>'
      + '<div class="lime-message__reactions">' + reactionsHtml(message.id) + '</div>'
      + '</div>'
      + '<div class="lime-message__actions">'
      + '<button title="React"><span>🙂</span></button>'
      + '</div>'
      + REACTION_PICKER_HTML;
    const avatar = quoteEl.querySelector('.lime-avatar[data-name]');
    if (avatar) paintAvatar(avatar);
  }

  // reply_count/last_reply_at on the parent message are stale seed
  // metadata (see data.js) — this always computes the real, live count.
  function renderMeta(replies) {
    if (!metaEl) return;
    if (replies.length === 0) {
      metaEl.textContent = '';
      return;
    }
    const last = replies[replies.length - 1];
    metaEl.textContent = replies.length + (replies.length === 1 ? ' reply' : ' replies')
      + ' · last reply ' + formatLastReply(last.created_at);
  }

  function renderReplies(parentId) {
    const replies = LimeStore.listReplies(parentId);
    renderMeta(replies);
    listEl.innerHTML = '';
    if (replies.length === 0) {
      listEl.innerHTML = '<p class="lime-replies-panel__empty">No replies yet.</p>';
      return;
    }
    replies.forEach((reply) => {
      const sender = LimeStore.getProfile(reply.sender_id);
      if (!sender) return;
      listEl.insertAdjacentHTML('beforeend', replyHtml(reply, sender));
    });
    listEl.querySelectorAll('.lime-avatar[data-name]').forEach(paintAvatar);
  }

  function openReplies(messageId) {
    const message = LimeStore.getMessage(messageId);
    if (!message) return;
    const sender = LimeStore.getProfile(message.sender_id);
    if (!sender) return;
    currentReplyParentId = messageId;
    renderQuote(message, sender);
    renderReplies(messageId);
    if (layout.classList.contains('seed-layout--right-hidden')) setRightPanelOpen(true);
    rightPanel.setAttribute('data-panel', 'replies');
    layout.setAttribute('data-mobile-view', 'panel');
  }

  document.addEventListener('click', (e) => {
    const replyBtn = e.target.closest('#thread-messages .lime-message__actions [title="Reply"]');
    if (replyBtn) {
      const msg = replyBtn.closest('.lime-message');
      const messageId = msg && msg.dataset.messageId;
      if (messageId) openReplies(messageId);
      return;
    }

    // LIME-11-fix5, renamed by LIME-18: the reply summary under a
    // message is a second trigger for the exact same panel — carries
    // its own data-message-id directly (see replyIndicatorHtml in
    // messageHtml), so no .closest('.lime-message') lookup needed here.
    const indicator = e.target.closest('#thread-messages .lime-message__replies');
    if (indicator) openReplies(indicator.dataset.messageId);
  });

  function submitReply() {
    if (!replyInput || !currentReplyParentId) return;
    const content = replyInput.value.trim();
    if (!content) return;
    const parentId = currentReplyParentId;
    const parent = LimeStore.getMessage(parentId);
    if (!parent) return;

    // sendMessage with replyTo covers replies too (LIME-24b's contract has
    // no separate sendReply) — it already emits lime:messages-changed,
    // which the main list's own listener picks up to re-sort; no manual
    // event dispatch needed here the way the old lime:activity one was.
    LimeStore.sendMessage(parent.conversation_id, { content, replyTo: parentId }).then(() => {
      refreshReplyIndicator(parentId);
      renderReplies(parentId);
      listEl.scrollTop = listEl.scrollHeight;
    }).catch(console.error);

    replyInput.value = '';
    replyInput.style.height = '';
    if (replySend) replySend.classList.remove('is-active');
  }

  // Reply composer: same expand/collapse + auto-grow + is-active pattern
  // as the main composer (LIME-10 through LIME-10-fix14). Duplicated
  // rather than shared — this brief's scope explicitly excludes touching
  // the main composer, and merging the two into one shared function
  // would mean editing that already-working code too.
  const repliesComposer = document.getElementById('replies-composer');
  if (repliesComposer && replyInput) {
    repliesComposer.addEventListener('focusin', () => repliesComposer.classList.add('is-expanded'));
    repliesComposer.addEventListener('focusout', (e) => {
      if (repliesComposer.contains(e.relatedTarget)) return;
      if (!replyInput.value.trim()) repliesComposer.classList.remove('is-expanded');
    });
    replyInput.addEventListener('input', () => {
      replyInput.style.height = 'auto';
      replyInput.style.height = replyInput.scrollHeight + 'px';
      if (replySend) replySend.classList.toggle('is-active', replyInput.value.trim().length > 0);
    });
    replyInput.addEventListener('keydown', (e) => {
      if (e.key === 'Enter' && !e.shiftKey) {
        e.preventDefault();
        submitReply();
      }
    });
  }

  if (replySend) replySend.addEventListener('click', submitReply);

  // Decorative placeholder, not real navigator.mediaDevices (LIME-10 gate)
  // — a second instance for the reply composer, own unique ids since the
  // main composer's voice-mode-toggle/-dropdown ids are already taken.
  wireDropdownToggle('replies-voice-mode-toggle', 'replies-voice-mode-dropdown', { fixed: true });
  // Same reasoning as the main composer's toolbar overflow menu (LIME-12-fix4).
  wireDropdownToggle('replies-composer-toolbar-overflow', 'replies-composer-toolbar-overflow-dropdown', { fixed: true });
})();

// ── Dropdown toggles (more menu, notifications, user menu) ──
// Same shape three times now (LIME-03r's more-menu, LIME-03u's
// notif/user menus) — one toggle button opens one dropdown, closes on
// any outside click. Generalized rather than copy-pasted a third time.
// `fixed: true` (notif/user menus) computes the dropdown's on-screen
// position from the trigger's own rect before opening it — required
// now that .lime-menu is position:fixed (LIME-03w's original reasoning
// for the old .lime-nav-dropdown, carried over by LIME-21's shared
// class), which has no relative-to-trigger anchor of its own the way
// position:absolute did. LIME-20: every registered dropdown now shares
// one Set (declared
// near the top of this file — see the comment there for why) so
// opening any of them closes whichever other one was open — the old
// per-call document listener alone couldn't do this, since each
// trigger's own stopPropagation() kept that click from ever reaching
// document when switching between two open menus. Fixed-mode menus
// also flip to whichever side of the trigger actually has room instead
// of always opening upward, and Escape closes whichever is open.
function wireDropdownToggle(toggleId, dropdownId, { fixed = false, placement = 'vertical' } = {}) {
  const toggle = document.getElementById(toggleId);
  const dropdown = document.getElementById(dropdownId);
  if (!toggle || !dropdown) return;
  registeredDropdowns.add(dropdown);

  toggle.addEventListener('click', (e) => {
    e.stopPropagation();
    const opening = !dropdown.classList.contains('is-open');
    if (opening) {
      registeredDropdowns.forEach((d) => { if (d !== dropdown) d.classList.remove('is-open'); });
    }
    dropdown.classList.toggle('is-open');
    // Position after opening, not before — offsetHeight/offsetWidth are
    // 0 until the dropdown is actually visible (LIME-18-fix4 already
    // established this for the horizontal clamp; the same now applies
    // to the vertical flip added here).
    if (fixed && opening) {
      const rect = toggle.getBoundingClientRect();
      const gap = 8;
      const h = dropdown.offsetHeight;
      const w = dropdown.offsetWidth;

      // LIME-20-fix: notifications opens beside the bell instead of
      // covering the nav items below it — only when there's actually
      // room on the right (a narrow mobile drawer falls back to the
      // same vertical flip-and-clamp every other fixed menu uses).
      const fitsRight = placement === 'right' && rect.right + gap + w <= window.innerWidth - 8;
      if (fitsRight) {
        dropdown.style.left = (rect.right + gap) + 'px';
        dropdown.style.top = Math.max(8, Math.min(rect.top, window.innerHeight - h - 8)) + 'px';
        dropdown.style.bottom = '';
        return;
      }

      const fitsBelow = rect.bottom + gap + h <= window.innerHeight - 8;
      const fitsAbove = rect.top - gap - h >= 8;
      // Neither fits (a very short viewport): use whichever side has
      // more room rather than picking one arbitrarily.
      const openBelow = fitsBelow ? true : fitsAbove ? false : (window.innerHeight - rect.bottom) >= rect.top;
      // Clear the opposite property explicitly — a stale value from a
      // previous opening (when this same menu flipped the other way)
      // would otherwise still apply alongside the new one.
      dropdown.style.top = openBelow ? (rect.bottom + gap) + 'px' : '';
      dropdown.style.bottom = openBelow ? '' : (window.innerHeight - rect.top + gap) + 'px';
      const maxLeft = window.innerWidth - w - 8;
      dropdown.style.left = Math.max(8, Math.min(rect.left, maxLeft)) + 'px';
    }
  });
  document.addEventListener('click', () => dropdown.classList.remove('is-open'));
}

// One shared listener — Escape closes whichever registered dropdown is
// currently open (at most one, per the close-others logic above).
document.addEventListener('keydown', (e) => {
  if (e.key === 'Escape') {
    registeredDropdowns.forEach((d) => d.classList.remove('is-open'));
  }
});

// LIME-20 tried this in fixed mode but had to revert — its CSS was
// still position:absolute then. Now on the shared .lime-menu (LIME-21),
// position:fixed, so it finally shares the same positioning path as
// every other menu.
wireDropdownToggle('more-menu-toggle', 'more-menu', { fixed: true });
// Opens beside the bell, not below it, so the nav items under it (Link,
// Jam) stay visible instead of getting covered (LIME-20-fix).
wireDropdownToggle('notif-btn', 'notif-dropdown', { fixed: true, placement: 'right' });
wireDropdownToggle('user-btn', 'user-dropdown', { fixed: true });
// Decorative placeholder, not a real navigator.mediaDevices list — per
// the LIME-10 gate, real device enumeration needs a live mic-permission
// prompt for a feature that still can't record anything.
wireDropdownToggle('voice-mode-toggle', 'voice-mode-dropdown', { fixed: true });
// Decorative relisting of the toolbar tools .lime-composer__tool--overflow
// hides at narrow widths (LIME-12-fix4) — none of those tools have any
// real formatting behavior wired regardless of width, so this dropdown
// doesn't need to either.
wireDropdownToggle('composer-toolbar-overflow', 'composer-toolbar-overflow-dropdown', { fixed: true });

// ── Expandable composer (LIME-10) ────────────────────────
// Toolbar shows only while #composer.is-expanded; textarea grows with
// content up to the CSS max-height (then scrolls). focusin/focusout
// (not focus/blur) because they bubble — needed to tell "focus moved to
// a toolbar button inside #composer" (stay expanded) apart from "focus
// left the composer entirely" (collapse, but only if it's empty).
(function () {
  const composer = document.getElementById('composer');
  const input = document.getElementById('composer-input');
  const thread = document.getElementById('thread-messages');
  const sendBtn = document.getElementById('composer-send');
  if (!composer || !input) return;

  composer.addEventListener('focusin', () => composer.classList.add('is-expanded'));
  composer.addEventListener('focusout', (e) => {
    if (composer.contains(e.relatedTarget)) return;
    if (!input.value.trim()) composer.classList.remove('is-expanded');
  });
  input.addEventListener('input', () => {
    input.style.height = 'auto';
    input.style.height = input.scrollHeight + 'px';
    // As the textarea grows taller (LIME-10-fix13), it eats into
    // .lime-messages's vertical space from the bottom — rescrolling to
    // the thread's own bottom keeps the latest message in view instead
    // of it sliding out from under the now-taller composer.
    if (thread) thread.scrollTop = thread.scrollHeight;
    // LIME-10-fix14: Send visually greys out when there's nothing to send.
    if (sendBtn) sendBtn.classList.toggle('is-active', input.value.trim().length > 0);
  });
})();

// ── Shorter composer placeholder on narrow screens (LIME-12-fix4) ──
// A <textarea> placeholder has no native ellipsis truncation the way
// a single-line <input>'s does — "Say something meaningful..." simply
// wraps onto a second line in a narrow mobile viewport, which the
// fixed single-line collapsed height (LIME-10-fix9) then crudely
// clips. A CSS font-size tweak wouldn't have helped: the placeholder
// already inherits --seed-text-sm (14px), the exact value this
// brief's own literal CSS asked for — so this brief's other offered
// option (shorter text via JS) is the one that actually does
// something. Runs once at load, not on resize — the placeholder is
// only ever visible while the textarea is empty and unfocused, a
// state a live-resizing viewport doesn't really encounter.
(function () {
  if (window.innerWidth > 480) return;
  // Only the main composer's placeholder ("Say something meaningful...")
  // is long enough to wrap — the reply composer's ("Reply...") is
  // already short, nothing to shorten there.
  const input = document.getElementById('composer-input');
  if (input) input.placeholder = 'Message...';
})();

// ── Shorter reply-composer privacy text ─────────────────────
// Not width-gated like the placeholder fix above: the reply composer's
// own column is always narrow (the desktop right panel, or the full
// mobile "panel" view, itself no wider than that same panel), so its
// disclaimer text overflows regardless of the overall window width.
// A <span> does support CSS ellipsis (unlike the placeholder's
// <textarea>), so this was already truncating cleanly — shortened the
// actual text instead, so more of it stays legible in the space it has.
(function () {
  const privacy = document.querySelector('#replies-composer .lime-composer__privacy');
  if (privacy) privacy.innerHTML = '<span class="dew dew-shield-check"></span> Secure &amp; encrypted';
})();

// ── Reset demo data (LIME-24b) ──────────────────────────────
// A native confirm() for now — LIME-26 brings the app's own confirm
// dialog once one exists. Clears the persisted snapshot and reloads, so
// the next LimeStore.init() normalizes fresh from the embedded seed
// again, exactly like a first-ever visit.
document.getElementById('reset-demo-data-btn')?.addEventListener('click', () => {
  if (!window.confirm('Reset demo data? Anything you’ve sent, replied, or reacted with will be cleared, and the original seed data comes back.')) return;
  LimeStore.reset().then(() => window.location.reload());
});

// ── Sign out ───────────────────────────────────────────────
// Clears the mock session login.html stores on a successful sign-in
// and sends the user back there. index.html has no auth-gate check on
// load (a deliberate LIME-05a decision — a real gate would redirect
// here on every direct open, breaking this whole workflow without a
// real backend), so this only ends the *current* session; nothing
// stops opening index.html directly again afterward.
document.getElementById('sign-out-btn')?.addEventListener('click', () => {
  localStorage.removeItem('lime-demo-session');
  window.location.href = 'login.html';
});

// ── Notification click ───────────────────────────────────
// Closes the dropdown. "select that contact" (per the brief's prose)
// isn't actually implemented beyond that — the given behavior only
// closes the dropdown, and the thread has no real per-contact
// switching to hook into (it's a static Shem↔Jean 1:1 throughout).
document.querySelectorAll('.lime-notif').forEach((n) => {
  n.addEventListener('click', (e) => {
    e.preventDefault();
    document.getElementById('notif-dropdown')?.classList.remove('is-open');
  });
});

// ── Nav search → global modal ────────────────────────────
// Distinct from the center panel's local filter: this searches everywhere
// (people, messages, jams), opens as a dialog, traps focus, and closes on
// Esc or a backdrop click.
(function () {
  const trigger  = document.getElementById('nav-search-trigger');
  const backdrop = document.getElementById('search-modal-backdrop');
  const modal    = document.getElementById('search-modal');
  const input    = document.getElementById('search-modal-input');
  const closeBtn = document.getElementById('search-modal-close');
  if (!trigger || !modal) return;

  let lastFocused = null;

  function focusable() {
    return [...modal.querySelectorAll('button, [href], input, [tabindex]:not([tabindex="-1"])')]
      .filter((el) => !el.disabled && el.offsetParent !== null);
  }

  function onKeydown(e) {
    if (e.key === 'Escape') {
      close();
      return;
    }
    if (e.key !== 'Tab') return;
    const items = focusable();
    if (items.length === 0) return;
    const first = items[0];
    const last  = items[items.length - 1];
    if (e.shiftKey && document.activeElement === first) {
      e.preventDefault();
      last.focus();
    } else if (!e.shiftKey && document.activeElement === last) {
      e.preventDefault();
      first.focus();
    }
  }

  function open() {
    lastFocused = document.activeElement;
    backdrop.classList.add('is-open');
    modal.classList.add('is-open');
    input.value = '';
    input.focus();
    document.addEventListener('keydown', onKeydown);
  }

  function close() {
    backdrop.classList.remove('is-open');
    modal.classList.remove('is-open');
    document.removeEventListener('keydown', onKeydown);
    if (lastFocused) lastFocused.focus();
  }

  trigger.addEventListener('click', open);
  backdrop.addEventListener('click', close);
  if (closeBtn) closeBtn.addEventListener('click', close);
  // .lime-menu__item, not the old .lime-search-modal__item (LIME-21b
  // unified them) — scoped to modal's own children, so this still only
  // ever matches these 4 result buttons, nothing from any other menu.
  modal.querySelectorAll('.lime-menu__item').forEach((item) => {
    item.addEventListener('click', close);
  });
})();

// ── Group toggle (Teachers / Groups / Communities) + local search ──
// Switching segments re-scopes both the visible list and what the local
// search field filters — it never touches message content, unlike the
// nav search modal above.
(function () {
  const tablist = document.getElementById('scope-tablist');
  const input   = document.getElementById('local-search-input');
  if (!tablist) return;

  const tabs = [...tablist.querySelectorAll('[role="tab"]')];

  function filter() {
    const query = (input.value || '').trim().toLowerCase();
    const panel = document.querySelector('[data-scope-panel]:not([hidden])');
    if (!panel) return;
    panel.querySelectorAll('[data-search-text]').forEach((item) => {
      item.style.display = (!query || item.dataset.searchText.includes(query)) ? '' : 'none';
    });
  }

  const crumbTeachers = document.getElementById('crumb-teachers');

  function setScope(scope) {
    let activeLabel = null;
    tabs.forEach((tab, index) => {
      const active = tab.dataset.scope === scope;
      tab.classList.toggle('seed-tab--active', active);
      tab.setAttribute('aria-selected', String(active));
      if (active) {
        tablist.style.setProperty('--active-index', index);
        activeLabel = tab.textContent.trim();
      }
    });
    document.querySelectorAll('[data-scope-panel]').forEach((panel) => {
      panel.hidden = panel.dataset.scopePanel !== scope;
    });
    // The mobile breadcrumb's first segment tracks whichever scope tab
    // is active ("Messages"/"Communities") rather than
    // always reading "Teachers" — id stays #crumb-teachers regardless
    // of the label it's currently showing.
    if (crumbTeachers && activeLabel) crumbTeachers.textContent = activeLabel;
    filter();
  }

  tabs.forEach((tab) => tab.addEventListener('click', () => setScope(tab.dataset.scope)));
  if (input) input.addEventListener('input', filter);
})();

// ── Collapsible sections (Recent / Starred / All Teachers, etc.) ───
(function () {
  document.querySelectorAll('.lime-section[data-section-id]').forEach((section) => {
    const toggle = section.querySelector('.lime-section__toggle');
    const key    = 'lime-section-' + section.dataset.sectionId;

    function setCollapsed(collapsed) {
      section.dataset.collapsed = String(collapsed);
      toggle.setAttribute('aria-expanded', String(!collapsed));
      localStorage.setItem(key, String(collapsed));
    }

    setCollapsed(localStorage.getItem(key) === 'true');
    toggle.addEventListener('click', () => setCollapsed(section.dataset.collapsed !== 'true'));
  });
})();

// Contact selection (Recent row) — delegated (LIME-24b): the Messages
// list's own rows now render asynchronously (after LimeStore.init()) and
// can be added or removed later too, so a one-time forEach bound at parse
// time would miss anything that doesn't exist yet at that moment.
document.addEventListener('click', (e) => {
  const contact = e.target.closest('.lime-contact, .lime-recent__item');
  if (!contact) return;
  document.querySelectorAll('.lime-recent__item').forEach((c) => c.classList.remove('lime-recent__item--active'));
  contact.classList.add('lime-recent__item--active');
});

// ── Mobile nav drawer ─────────────────────────────────────
// Push model, no Seed overlay and no backdrop: the drawer just pushes
// the center panel narrower while staying fully visible and
// interactive next to it. The trigger is styled and wired like the
// existing left/right panel toggles (icon swaps open/closed, hover
// previews the alternate) rather than a plain hamburger with its own
// bespoke click handler. It closes via the hamburger, Escape, or
// widening past the mobile breakpoint.
(function () {
  const layout = document.getElementById('layout');
  const toggle = document.getElementById('mobile-nav-toggle');
  if (!layout || !toggle) return;

  const icon = toggle.querySelector('.dew');

  function paintIcon(isOpen) {
    icon.classList.toggle('dew-sidebar-left-open',   !isOpen);
    icon.classList.toggle('dew-sidebar-left-closed',  isOpen);
  }

  function applyOpen(isOpen) {
    layout.classList.toggle('seed-layout--mobile-open', isOpen);
    toggle.setAttribute('aria-expanded', String(isOpen));
  }

  applyOpen(false);
  const nav = wireHoverPreviewToggle(toggle, false, paintIcon, applyOpen);

  document.addEventListener('keydown', (e) => {
    if (e.key === 'Escape' && layout.classList.contains('seed-layout--mobile-open')) {
      nav.set(false);
    }
  });

  const mobileQuery = window.matchMedia('(max-width: 767px)');
  mobileQuery.addEventListener('change', (e) => {
    if (!e.matches) nav.set(false);
  });
})();

// ── Mobile view router (contacts / thread / panel) ───────
// #layout's data-mobile-view is the single source of truth for which
// full-width view shows below 768px (see the [data-mobile-view] rules
// in lime.css); above that breakpoint the attribute is simply inert.
// Triggers here layer onto elements that already have their own
// desktop-oriented click handlers (open-profile-avatars, open-replies)
// rather than replacing them. #crumb-thread ("Jean Chung" in the
// breadcrumb) now opens the panel too, matching "clicking Jean's name,
// photo, or right toggle should show panel" — this supersedes the
// prior LIME-03g pass, which had it navigate to the thread instead.
(function () {
  const layout = document.getElementById('layout');
  if (!layout) return;

  function setView(view) {
    layout.setAttribute('data-mobile-view', view);
  }

  // Delegated (LIME-24b), same reasoning as the Recent-row highlight above.
  document.addEventListener('click', (e) => {
    if (e.target.closest('.lime-contact, .lime-recent__item')) setView('thread');
  });

  [document.getElementById('open-profile-avatars'), document.getElementById('open-replies'), document.getElementById('crumb-thread')]
    .filter(Boolean)
    .forEach((btn) => btn.addEventListener('click', () => setView('panel')));

  // right-panel-toggle is excluded from the "go to panel" list above —
  // LIME-03z made it close-only again (it lives inside #right-panel
  // once more), so on mobile it should only ever step back to
  // "thread", never open "panel" itself.
  const rightToggle = document.getElementById('right-panel-toggle');
  if (rightToggle) rightToggle.addEventListener('click', () => setView('thread'));

  const crumbTeachers = document.getElementById('crumb-teachers');
  if (crumbTeachers) crumbTeachers.addEventListener('click', () => setView('contacts'));
})();

// ── Auto-collapse on shrink ────────────────────────────────
// One-shot nudges fired only on the downward crossing of a breakpoint —
// not a persistently forced state. The user's own toggle stays
// authoritative afterward; resizing back up never re-expands
// automatically. Scoped to the 1024px crossing only (desktop → tablet
// or steeper); this doesn't attempt to cover every possible resize
// path (e.g. mobile growing back into tablet range).
(function () {
  const rightToggle = document.getElementById('right-panel-toggle');
  const leftToggle   = document.getElementById('left-panel-toggle');
  let prevWidth = window.innerWidth;

  window.addEventListener('resize', () => {
    const width = window.innerWidth;
    const crossedDownInto1024 = width <= 1024 && prevWidth > 1024;

    if (crossedDownInto1024) {
      if (rightToggle && rightToggle.getAttribute('aria-expanded') === 'true') rightToggle.click();
      if (leftToggle && leftToggle.getAttribute('aria-expanded') === 'true') leftToggle.click();
    }

    prevWidth = width;
  });
})();

// ── Scroll-edge fades ─────────────────────────────────────
// A fade should only be visible when there's actually hidden content
// past that edge — not a permanent overlay that dims content even at
// rest. Toggles is-scrolled-* classes (read by gradients.css's
// .has-fade-y/.has-fade-x system) on `fadeHost`, which may be a
// different element than the one that actually scrolls: the chat fade
// lives on .lime-chat-body (the non-scrolling parent), not
// .lime-messages (the scroller) itself, because .lime-messages is
// already position:absolute for other reasons and can't also host its
// own positioned children — see gradients.css.
function wireScrollFades(scrollEl, fadeHost, { horizontal = false } = {}) {
  if (!scrollEl || !fadeHost) return;

  function update() {
    if (horizontal) {
      const atStart = scrollEl.scrollLeft <= 0;
      const atEnd = scrollEl.scrollLeft + scrollEl.clientWidth >= scrollEl.scrollWidth - 1;
      fadeHost.classList.toggle('is-scrolled-start', !atStart);
      fadeHost.classList.toggle('is-scrolled-end', !atEnd);
    } else {
      const atTop = scrollEl.scrollTop <= 0;
      const atBottom = scrollEl.scrollTop + scrollEl.clientHeight >= scrollEl.scrollHeight - 1;
      fadeHost.classList.toggle('is-scrolled-top', !atTop);
      fadeHost.classList.toggle('is-scrolled-bottom', !atBottom);
    }
  }

  scrollEl.addEventListener('scroll', update);
  // ResizeObserver (not just window resize) matters here: on mobile,
  // .lime-messages/.lime-profile start hidden (display:none) behind
  // whichever view isn't active, so scrollHeight/clientHeight read as
  // 0 at page load. Switching mobile views doesn't fire a window
  // resize, but it does change these elements' box from 0×0 to real
  // dimensions, which ResizeObserver does catch — keeping the fade
  // state from going stale after a view switch.
  if (window.ResizeObserver) {
    new ResizeObserver(update).observe(scrollEl);
  } else {
    window.addEventListener('resize', update);
  }
  update();
}

wireScrollFades(document.querySelector('.lime-list-col'), document.querySelector('.lime-list-col'));
wireScrollFades(document.querySelector('.lime-messages'), document.querySelector('.lime-chat-body'));
wireScrollFades(document.querySelector('.lime-profile'), document.querySelector('.lime-profile'));
wireScrollFades(document.querySelector('.lime-recent'), document.querySelector('.lime-recent'), { horizontal: true });
