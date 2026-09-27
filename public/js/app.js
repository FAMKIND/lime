'use strict';

// Theme
const theme = localStorage.getItem('lime-theme');
if (theme) document.documentElement.setAttribute('data-theme', theme);

// ── Seed data: contacts list + thread (LIME-06) ──────────
// Runs first, before every other top-level binding below — several of
// them (avatar identity system, contact-preview truncation, message
// avatar-click, contact click, mobile view router) scan the DOM once
// with querySelectorAll rather than delegating, so the elements this
// renders have to exist before those run or they'd be missed on their
// only pass.
// Promoted to top-level (LIME-11), not IIFE-private — the new replies
// panel needs these same pure helpers and can't reach inside the LIME-06
// closure's scope. None of them depend on that closure's own state
// (list/thread/me/etc.), so hoisting changes nothing about how the
// contacts/thread code below already uses them.
const PRESENCE = { online: 'active', busy: 'busy', offline: 'away' };
const PRESENCE_LABEL = { active: 'Active', busy: 'Busy', away: 'Away' };

function presenceFor(status) {
  return PRESENCE[status] || 'away';
}

function shortName(name) {
  const parts = name.trim().split(/\s+/);
  return parts.length < 2 ? name : parts[0] + ' ' + parts[parts.length - 1][0];
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

function reactionsHtml(messageId, reactions) {
  if (!reactions || reactions.length === 0) return '';
  return reactions
    .map((r) => {
      const active = hasUserReacted(messageId, r.emoji) ? ' lime-reaction--active' : '';
      return '<button type="button" class="lime-reaction' + active + '" data-emoji="' + r.emoji + '">' + r.emoji + ' <span class="lime-reaction__count">' + r.count + '</span></button>';
    })
    .join('');
}

// Re-renders one message's reaction pills in place (LIME-08) — messageEl
// needs data-message-id since active-state depends on which
// message/emoji pair this is.
function renderReactions(messageEl, reactions) {
  const container = messageEl.querySelector('.lime-message__reactions');
  if (container) container.innerHTML = reactionsHtml(messageEl.dataset.messageId, reactions);
}

// LIME-11-fix5: "X replies" under any main-thread message that has
// real replies — like reactions, the count is computed live from
// getRepliesForMessage rather than trusted from the seed message's
// own stale reply_count field. Click reuses the exact same
// openReplies() the "Reply" action button already calls (see the
// "Reply thread panel" closure further down) via a second delegated
// listener on this button's own class.
function replyIndicatorHtml(messageId) {
  const count = getRepliesForMessage(messageId).length;
  if (count === 0) return '';
  return '<button type="button" class="lime-message__reply-indicator" data-message-id="' + messageId + '">'
    + '<span class="dew dew-chat"></span>'
    + count + (count === 1 ? ' reply' : ' replies')
    + '</button>';
}

// Keeps the main thread's "N replies" indicator correct after a reply
// is sent anywhere (the thread panel), without a full re-render (LIME-17).
function refreshReplyIndicator(messageId) {
  const messageEl = document.querySelector('#thread-messages .lime-message[data-message-id="' + messageId + '"]');
  if (!messageEl) return;
  const existing = messageEl.querySelector('.lime-message__reply-indicator');
  if (existing) existing.remove();
  const reactionsEl = messageEl.querySelector('.lime-message__reactions');
  if (reactionsEl) reactionsEl.insertAdjacentHTML('afterend', replyIndicatorHtml(messageId));
}

(function () {
  const list = document.getElementById('contacts-list');
  const thread = document.getElementById('thread-messages');
  if (!list || !thread) return;

  const me = getTeacherById(CURRENT_USER_ID);
  const crumbThread = document.getElementById('crumb-thread');
  const composerInput = document.getElementById('composer-input');
  const composerSend = document.getElementById('composer-send');

  let currentConversationId = null;
  let lastRenderedDay = null;

  function otherParticipant(conversation) {
    const otherId = conversation.participants.find((id) => id !== CURRENT_USER_ID);
    return getTeacherById(otherId);
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
  function renderReactionsEverywhere(messageId, reactions) {
    document.querySelectorAll(REACTABLE).forEach((el) => {
      if (el.dataset.messageId === messageId) renderReactions(el, reactions);
    });
  }

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
      const picker = btn.closest(REACTABLE).querySelector('.lime-reaction-picker');
      picker?.classList.toggle('is-open');
      return;
    }

    const pickerEmoji = e.target.closest('.lime-reaction-picker [data-emoji]');
    if (pickerEmoji) {
      const msg = pickerEmoji.closest(REACTABLE);
      const messageId = msg.dataset.messageId;
      if (messageId) {
        const reactions = addReaction(messageId, pickerEmoji.dataset.emoji);
        renderReactionsEverywhere(messageId, reactions);
      }
      pickerEmoji.closest('.lime-reaction-picker').classList.remove('is-open');
      return;
    }

    const pill = e.target.closest('.lime-message__reactions .lime-reaction');
    if (pill) {
      const msg = pill.closest(REACTABLE);
      const messageId = msg.dataset.messageId;
      if (!messageId) return;
      const reactions = toggleReaction(messageId, pill.dataset.emoji);
      renderReactionsEverywhere(messageId, reactions);
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
      + '<div class="lime-message__reactions">' + reactionsHtml(message.id, message.reactions) + '</div>'
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

  function renderThread(conversationId, teacher) {
    currentConversationId = conversationId;
    lastRenderedDay = null;
    const msgs = getThreadMessages(conversationId);
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
      const isSent = m.sender_id === CURRENT_USER_ID;
      const sender = isSent ? me : teacher;
      thread.insertAdjacentHTML('beforeend', messageHtml(m, sender, isSent));
    });
    // LIME-11-fix3: covers both the initial page-load render (default
    // conversation) and every subsequent conversation switch, since both
    // paths call this same function — renderThread never scrolled at all
    // before this, always leaving the view at the top of the thread.
    thread.scrollTop = thread.scrollHeight;
  }

  function selectConversation(conversation, teacher) {
    list.querySelectorAll('.lime-contact').forEach((el) => el.classList.remove('lime-contact--active'));
    const li = list.querySelector('[data-conversation-id="' + conversation.id + '"]');
    if (li) li.classList.add('lime-contact--active');
    if (crumbThread) crumbThread.textContent = teacher.display_name;
    renderThread(conversation.id, teacher);
  }

  // ── Send message (LIME-07) ─────────────────────────────
  function handleSend() {
    if (!composerInput || !currentConversationId) return;
    const content = composerInput.value.trim();
    if (!content) return;

    const message = sendMessage(currentConversationId, content);
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

    composerInput.value = '';
    composerInput.style.height = ''; // drop the auto-grow inline height (LIME-10)
    // Setting .value directly doesn't fire an 'input' event, so the
    // is-active toggle (LIME-10-fix14, wired to that event elsewhere)
    // never sees this clear on its own — reset it here explicitly,
    // otherwise Send stays looking "active" after a message is sent.
    if (composerSend) composerSend.classList.remove('is-active');
    thread.scrollTop = thread.scrollHeight;
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

  const directConversations = getDirectConversations();
  list.innerHTML = '';
  directConversations.forEach((conversation) => {
    const teacher = otherParticipant(conversation);
    if (!teacher) return;
    const msgs = getMessagesByConversation(conversation.id);
    const last = msgs[msgs.length - 1];
    const presence = presenceFor(teacher.status);

    const li = document.createElement('li');
    li.className = 'lime-contact';
    li.dataset.conversationId = conversation.id;
    li.dataset.searchText = teacher.display_name.toLowerCase();
    li.innerHTML = '<span class="lime-avatar-frame lime-avatar-frame--lg">'
      + '<span class="seed-avatar seed-avatar--lg lime-avatar" data-name="' + escapeHtml(teacher.display_name) + '"></span>'
      + '<span class="lime-presence" data-presence="' + presence + '" role="img" aria-label="' + PRESENCE_LABEL[presence] + '"></span>'
      + '</span>'
      + '<div class="lime-contact__body">'
      + '<span class="lime-contact__name">' + escapeHtml(teacher.display_name) + '</span>'
      + '<span class="lime-contact__preview">' + previewFor(last) + '</span>'
      + '</div>'
      + '<div class="lime-contact__meta">'
      + '<span class="lime-contact__time">' + (last ? formatTime(last.created_at) : '') + '</span>'
      + '</div>';
    li.addEventListener('click', () => selectConversation(conversation, teacher));
    list.appendChild(li);
  });

  if (directConversations.length > 0) {
    const first = directConversations[0];
    selectConversation(first, otherParticipant(first));
  }
})();

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

// ── Avatar identity system ──────────────────────────────
// Every .lime-avatar[data-name] gets initials + a color deterministically
// derived from the name (same input always yields the same output, so a
// person's color is stable across the whole app and across reloads).
// paintAvatar is a top-level function, not IIFE-private (LIME-11) — the
// forEach below only ever runs once, at parse time, so it only reached
// elements that already existed by then (the initial contacts list +
// default thread, both rendered earlier in this same script). Any
// .lime-avatar added afterward — a sent message (LIME-07) or a reply
// (LIME-11) — never got painted at all: a real, pre-existing gap this
// brief's own "replies show avatars" requirement forced into the open.
// Anything that appends a new .lime-avatar[data-name] now has to call
// this itself.
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
      + '<div class="lime-message__reactions">' + reactionsHtml(message.id, message.reactions) + '</div>'
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
      + '<div class="lime-message__reactions">' + reactionsHtml(message.id, message.reactions) + '</div>'
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
      + ' · last reply ' + formatTime(last.created_at);
  }

  function renderReplies(parentId) {
    const replies = getRepliesForMessage(parentId);
    renderMeta(replies);
    listEl.innerHTML = '';
    if (replies.length === 0) {
      listEl.innerHTML = '<p class="lime-replies-panel__empty">No replies yet.</p>';
      return;
    }
    replies.forEach((reply) => {
      const sender = getTeacherById(reply.sender_id);
      if (!sender) return;
      listEl.insertAdjacentHTML('beforeend', replyHtml(reply, sender));
    });
    listEl.querySelectorAll('.lime-avatar[data-name]').forEach(paintAvatar);
  }

  function openReplies(messageId) {
    const message = findMessageById(messageId);
    if (!message) return;
    const sender = getTeacherById(message.sender_id);
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

    // LIME-11-fix5: the "X replies" indicator under a message is a
    // second trigger for the exact same panel — carries its own
    // data-message-id directly (see replyIndicatorHtml in messageHtml),
    // so no .closest('.lime-message') lookup needed here.
    const indicator = e.target.closest('#thread-messages .lime-message__reply-indicator');
    if (indicator) openReplies(indicator.dataset.messageId);
  });

  function submitReply() {
    if (!replyInput || !currentReplyParentId) return;
    const content = replyInput.value.trim();
    if (!content) return;
    sendReply(currentReplyParentId, content);
    refreshReplyIndicator(currentReplyParentId);
    renderReplies(currentReplyParentId);
    listEl.scrollTop = listEl.scrollHeight;
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
// now that .lime-nav-dropdown is position:fixed (LIME-03w), which has
// no relative-to-trigger anchor of its own the way position:absolute
// did. Opens upward, left-aligned with the trigger, matching the
// dropdown's old bottom:100%/left:0 behavior.
function wireDropdownToggle(toggleId, dropdownId, { fixed = false } = {}) {
  const toggle = document.getElementById(toggleId);
  const dropdown = document.getElementById(dropdownId);
  if (!toggle || !dropdown) return;
  toggle.addEventListener('click', (e) => {
    e.stopPropagation();
    if (fixed && !dropdown.classList.contains('is-open')) {
      const rect = toggle.getBoundingClientRect();
      dropdown.style.left = rect.left + 'px';
      dropdown.style.bottom = (window.innerHeight - rect.top + 8) + 'px';
    }
    dropdown.classList.toggle('is-open');
  });
  document.addEventListener('click', () => dropdown.classList.remove('is-open'));
}

wireDropdownToggle('more-menu-toggle', 'more-menu');
wireDropdownToggle('notif-btn', 'notif-dropdown', { fixed: true });
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
  modal.querySelectorAll('.lime-search-modal__item').forEach((item) => {
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
    // is active ("Teachers"/"Group Chat"/"Community") rather than
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

// Contact selection (Recent row)
document.querySelectorAll('.lime-contact, .lime-recent__item').forEach((contact) => {
  contact.addEventListener('click', () => {
    document.querySelectorAll('.lime-recent__item').forEach((c) => c.classList.remove('lime-recent__item--active'));
    contact.classList.add('lime-recent__item--active');
  });
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

  document.querySelectorAll('.lime-contact, .lime-recent__item').forEach((el) => {
    el.addEventListener('click', () => setView('thread'));
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
