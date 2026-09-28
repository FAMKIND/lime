'use strict';

// LimeAuth (LIME-31) — the write half of the auth seam docs/data-model.md
// describes (getCurrentUserId() is the read half). Email and password
// changes go through here, never through LimeStore.updateProfile — they
// belong to the auth provider, not the profiles table, per this project's
// production-ready rules. Local behavior today; the switch checklist in
// docs/data-model.md describes swapping each function's body for its
// Supabase equivalent without changing its name or signature.
const LimeAuth = (function () {
  function isValidEmail(email) {
    return /^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(email);
  }

  function changeEmail(newEmail) {
    const email = (newEmail || '').trim();
    if (!isValidEmail(email)) {
      return Promise.reject(new Error('Enter a valid email address.'));
    }
    const currentId = LimeStore.getCurrentUserId();
    const existing = LimeStore.findProfileByEmail(email);
    if (existing && existing.id !== currentId) {
      return Promise.reject(new Error('That email is already in use.'));
    }
    return LimeStore.setProfileEmail(currentId, email).then((profile) => {
      // Keeps lime-demo-session in sync with the new email — without
      // this, getCurrentUserId() would no longer find a matching profile
      // on the next LimeStore.init() (e.g. after a reload), and silently
      // fall back to teacher-002 instead of staying signed in as this
      // person.
      try {
        const raw = localStorage.getItem('lime-demo-session');
        if (raw) {
          const session = JSON.parse(raw);
          session.email = email;
          localStorage.setItem('lime-demo-session', JSON.stringify(session));
        }
      } catch (e) {
        // Malformed or absent session — nothing to keep in sync.
      }
      return profile;
    });
  }

  function changePassword(options) {
    const opts = options || {};
    const current = opts.current || '';
    const next = opts.next || '';
    const confirm = opts.confirm || '';
    // Local behavior validates shape only — passwords are never stored
    // locally, in any form, so there's no real `current` to check this
    // against here (the demo login's one hardcoded credential lives in
    // the gitignored demo-config.local.js, which this module never
    // reads). A real backend is what actually authenticates it.
    if (next.length < 8) {
      return Promise.reject(new Error('New password must be at least 8 characters.'));
    }
    if (next === current) {
      return Promise.reject(new Error('New password must be different from your current password.'));
    }
    if (next !== confirm) {
      return Promise.reject(new Error('New password and confirmation do not match.'));
    }
    return Promise.resolve({ message: 'Password changes take effect once connected to the real account system.' });
  }

  function signOut() {
    localStorage.removeItem('lime-demo-session');
    window.location.href = 'login.html';
  }

  return { changeEmail, changePassword, signOut };
})();

window.LimeAuth = LimeAuth;
