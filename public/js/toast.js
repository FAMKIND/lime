'use strict';

// LimeToast (LIME-67) — Lime's toast notifications: an icon, a title, an
// optional body and action, a dismiss ×. Loaded by index.html and
// auth.html, each with its own #toast-container (created here if absent).
//
// WHEN TO TOAST (LIME-68's rules)
//   Toast when an outcome happened somewhere you're not looking, can't
//   otherwise be seen, is irreversible, can be undone, or failed.
//   Don't toast what the screen already shows clearly: sending a message,
//   reactions, opening panels, live appearance changes, typing, selecting
//   chats. Form validation errors stay inline. Copy is short, plain, and
//   has no exclamation marks.
//
// API
//   LimeToast.show({ title, body, tone: 'info'|'success'|'warning'|'error',
//                    action: { label, onClick }, duration })
//     duration (ms): default 5000, 8000 with an action, error toasts stay
//     until dismissed. Pass 0 to make any toast sticky.
//   LimeToast.queue({ title, body, tone, action: { label, name }, duration })
//     stores a toast in sessionStorage before a navigation; the next page
//     shows and clears it on load. An action can't cross a page load as a
//     function, so it carries a `name` that the receiving page registers
//     with LimeToast.registerAction(name, fn) (dropped if unregistered).

const LimeToast = (function () {
  const FLASH_KEY = 'lime-flash-toasts';
  const MAX_VISIBLE = 3;
  const EXIT_MS = 150;
  const ICONS = {
    info: 'dew-information-circle',
    success: 'dew-check',
    warning: 'dew-alert-triangle',
    error: 'dew-negative',
  };
  const namedActions = {};

  function esc(str) {
    return String(str).replace(/[&<>"']/g, (c) => ({
      '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;',
    }[c]));
  }

  function getContainer() {
    let container = document.getElementById('toast-container');
    if (!container) {
      container = document.createElement('div');
      container.id = 'toast-container';
      container.className = 'seed-toast-container seed-toast-container--bottom-right';
      document.body.appendChild(container);
    }
    container.setAttribute('role', 'region');
    container.setAttribute('aria-label', 'Notifications');
    return container;
  }

  function reducedMotion() {
    return window.matchMedia && window.matchMedia('(prefers-reduced-motion: reduce)').matches;
  }

  function show(options) {
    const opts = options || {};
    const tone = ICONS[opts.tone] ? opts.tone : 'info';
    const action = opts.action && opts.action.label ? opts.action : null;
    let duration = opts.duration;
    if (duration == null) duration = tone === 'error' ? 0 : (action ? 8000 : 5000);

    const container = getContainer();
    const toast = document.createElement('div');
    toast.className = 'seed-toast lime-toast lime-toast--' + tone;
    toast.setAttribute('role', tone === 'error' ? 'alert' : 'status');
    toast.innerHTML = '<span class="seed-toast__icon dew ' + ICONS[tone] + '" aria-hidden="true"></span>'
      + '<div class="seed-toast__content">'
      + '<span class="seed-toast__title">' + esc(opts.title || '') + '</span>'
      + (opts.body ? '<span class="seed-toast__message">' + esc(opts.body) + '</span>' : '')
      + (action ? '<button type="button" class="seed-button seed-button--secondary seed-button--sm lime-toast__action">' + esc(action.label) + '</button>' : '')
      + '</div>'
      + '<button type="button" class="seed-toast__dismiss dew dew-close" aria-label="Dismiss notification"></button>';

    // Newest first in the DOM: the container stacks so the first child
    // sits nearest the corner (column-reverse at the bottom, column at
    // the top on mobile).
    container.insertBefore(toast, container.firstChild);

    // At most MAX_VISIBLE: the oldest (last in the DOM) leave first.
    const live = Array.from(container.querySelectorAll('.lime-toast:not(.seed-toast--exiting)'));
    live.slice(MAX_VISIBLE).forEach((old) => old.limeDismiss && old.limeDismiss());

    let timer = null;
    let remaining = duration;
    let startedAt = 0;
    let dismissed = false;

    function dismiss() {
      if (dismissed) return;
      dismissed = true;
      clearTimeout(timer);
      toast.classList.add('seed-toast--exiting');
      setTimeout(() => toast.remove(), reducedMotion() ? 0 : EXIT_MS);
    }
    toast.limeDismiss = dismiss;

    function startTimer() {
      if (!(duration > 0) || dismissed) return;
      clearTimeout(timer);
      startedAt = Date.now();
      timer = setTimeout(dismiss, remaining);
    }
    function pauseTimer() {
      if (!(duration > 0) || !timer) return;
      clearTimeout(timer);
      timer = null;
      remaining = Math.max(0, remaining - (Date.now() - startedAt));
    }

    toast.querySelector('.seed-toast__dismiss').addEventListener('click', dismiss);
    if (action) {
      toast.querySelector('.lime-toast__action').addEventListener('click', () => {
        dismiss();
        if (typeof action.onClick === 'function') action.onClick();
      });
    }

    // Hover or keyboard focus inside pauses; leaving resumes the
    // remaining time, not a fresh one.
    toast.addEventListener('mouseenter', pauseTimer);
    toast.addEventListener('mouseleave', () => { if (!toast.contains(document.activeElement)) startTimer(); });
    toast.addEventListener('focusin', pauseTimer);
    toast.addEventListener('focusout', () => {
      // relatedTarget is null when focus leaves the document entirely.
      if (!toast.contains(document.activeElement) && !toast.matches(':hover')) startTimer();
    });
    toast.addEventListener('keydown', (e) => { if (e.key === 'Escape') dismiss(); });

    startTimer();
    return { dismiss };
  }

  function registerAction(name, fn) {
    namedActions[name] = fn;
  }

  function queue(options) {
    try {
      const pending = JSON.parse(sessionStorage.getItem(FLASH_KEY) || '[]');
      pending.push(options);
      sessionStorage.setItem(FLASH_KEY, JSON.stringify(pending));
    } catch (e) { /* sessionStorage unavailable — the toast is just lost */ }
  }

  // Shows and clears whatever a previous page queued. Runs on
  // DOMContentLoaded: every classic script at the end of <body> (the one
  // that registerAction()s included) has run by then.
  function flushQueue() {
    let pending = [];
    try {
      pending = JSON.parse(sessionStorage.getItem(FLASH_KEY) || '[]');
      sessionStorage.removeItem(FLASH_KEY);
    } catch (e) { return; }
    pending.forEach((item) => {
      const opts = Object.assign({}, item);
      if (item.action && item.action.name) {
        const handler = namedActions[item.action.name];
        opts.action = handler ? { label: item.action.label, onClick: handler } : null;
      }
      show(opts);
    });
  }

  document.addEventListener('DOMContentLoaded', flushQueue);

  return { show, queue, registerAction, flushQueue };
})();

window.LimeToast = LimeToast;
