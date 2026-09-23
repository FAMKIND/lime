'use strict';

// Theme
const theme = localStorage.getItem('lime-theme');
if (theme) document.documentElement.setAttribute('data-theme', theme);

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
(function () {
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

  document.querySelectorAll('.lime-avatar[data-name]').forEach((el) => {
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
  });
})();

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

  const saved = localStorage.getItem('lime-right-panel-open');
  setRightPanelOpen(saved === null ? true : saved === 'true');

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
// #right-panel's data-panel attribute ("profile" | "replies") is the
// single source of truth for which view shows — CSS reads it, this just
// flips it. Opening replies reuses the same "force the right panel open"
// step as the profile triggers above.
(function () {
  const layout       = document.getElementById('layout');
  const rightPanel    = document.getElementById('right-panel');
  const openReplies   = document.getElementById('open-replies');
  const backBtn       = document.getElementById('replies-back');
  if (!layout || !rightPanel || !openReplies || !backBtn) return;

  openReplies.addEventListener('click', () => {
    if (layout.classList.contains('seed-layout--right-hidden')) setRightPanelOpen(true);
    rightPanel.setAttribute('data-panel', 'replies');
  });

  backBtn.addEventListener('click', () => {
    rightPanel.setAttribute('data-panel', 'profile');
  });
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

// ── Reaction picker ────────────────────────────────────────
// Each .lime-message has its own local .lime-reaction-picker (a
// shared single-instance picker wouldn't work with the closest()/
// querySelector() lookup below, and a shared id would also be invalid
// HTML repeated across every message — the markup only carries the
// class, not an id).
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
    const picker = btn.closest('.lime-message').querySelector('.lime-reaction-picker');
    picker?.classList.toggle('is-open');
    return;
  }

  const emoji = e.target.closest('.lime-reaction-picker [data-emoji]');
  if (emoji) {
    const msg = emoji.closest('.lime-message');
    const container = msg.querySelector('.lime-message__reactions');
    // <button>, not <span> — matches the static reaction markup
    // (LIME-04a made .lime-reaction a real clickable button) rather
    // than the plain non-interactive span this used to create.
    const reaction = document.createElement('button');
    reaction.type = 'button';
    reaction.className = 'lime-reaction';
    reaction.innerHTML = emoji.dataset.emoji + ' <span class="lime-reaction__count">1</span>';
    container.appendChild(reaction);
    emoji.closest('.lime-reaction-picker').classList.remove('is-open');
  }
});
document.addEventListener('click', () => document.querySelectorAll('.lime-reaction-picker.is-open').forEach((p) => p.classList.remove('is-open')));

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
// Reuses Seed's own .seed-layout--mobile-open overlay for
// .seed-layout__left (already fully styled in layout.css) — this just
// adds the trigger and a click-outside/Esc-to-close backdrop, which
// Seed's mechanism doesn't itself provide. The trigger is now styled
// and wired like the existing left/right panel toggles (icon swaps
// open/closed, hover previews the alternate) rather than a plain
// hamburger with its own bespoke click handler.
(function () {
  const layout   = document.getElementById('layout');
  const toggle   = document.getElementById('mobile-nav-toggle');
  const backdrop = document.getElementById('mobile-nav-backdrop');
  if (!layout || !toggle || !backdrop) return;

  const icon = toggle.querySelector('.dew');

  function paintIcon(isOpen) {
    icon.classList.toggle('dew-sidebar-left-open',   !isOpen);
    icon.classList.toggle('dew-sidebar-left-closed',  isOpen);
  }

  function applyOpen(isOpen) {
    layout.classList.toggle('seed-layout--mobile-open', isOpen);
    backdrop.classList.toggle('is-open', isOpen);
    toggle.setAttribute('aria-expanded', String(isOpen));
  }

  applyOpen(false);
  wireHoverPreviewToggle(toggle, false, paintIcon, applyOpen);

  backdrop.addEventListener('click', () => { applyOpen(false); paintIcon(false); });
  document.addEventListener('keydown', (e) => {
    if (e.key === 'Escape' && layout.classList.contains('seed-layout--mobile-open')) {
      applyOpen(false);
      paintIcon(false);
    }
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
