'use strict';

// LimeAuth (LIME-31, real accounts LIME-33) — the write half of the auth
// seam docs/data-model.md describes (getCurrentUserId() is the read
// half). Shaped like Supabase's own auth client (signUp/signInWithPassword/
// signOut/getSession, all Promises) so the switch checklist in
// docs/data-model.md can swap each function's body for its Supabase
// equivalent later without changing a single call site.
//
// Local demo only; Supabase auth replaces this entirely.
const LimeAuth = (function () {
  const CREDENTIALS_KEY = 'lime-auth-v1';
  const SESSION_KEY = 'lime-demo-session';
  const PBKDF2_ITERATIONS = 100000;

  function isValidEmail(email) {
    return /^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(email);
  }

  // LIME-33-fix: a write-then-read-back probe, not just a try/catch
  // around a single call — some failure modes (a full quota, certain
  // "block all site data" configurations) let setItem succeed but never
  // actually persist the value, which a bare try/catch around setItem
  // alone wouldn't catch.
  function checkStorageWorks() {
    const probeKey = '__lime_storage_probe__';
    try {
      localStorage.setItem(probeKey, '1');
      const ok = localStorage.getItem(probeKey) === '1';
      localStorage.removeItem(probeKey);
      return ok;
    } catch (e) {
      return false;
    }
  }

  // ── Credential storage: { [email]: { userId, salt, hash } } ──
  // salt/hash are stored as base64 (JSON has no binary type). Never the
  // plain password, in any form, anywhere.
  function loadCredentials() {
    try {
      return JSON.parse(localStorage.getItem(CREDENTIALS_KEY) || '{}');
    } catch (e) {
      return {};
    }
  }

  function saveCredentials(creds) {
    localStorage.setItem(CREDENTIALS_KEY, JSON.stringify(creds));
  }

  // LIME-48: the email-first flow's own "does this email already have an
  // account" check, read before deciding whether to show the password
  // step or the create step. Same definition of "taken" signUp's own
  // uniqueness check already uses — a local credential OR a seed profile
  // with no local credential yet both count as an existing account.
  function accountExists(email) {
    const normalized = (email || '').trim().toLowerCase();
    const credentials = loadCredentials();
    return !!(credentials[normalized] || LimeStore.findProfileByEmail(normalized));
  }

  function bufToBase64(buf) {
    return btoa(String.fromCharCode(...new Uint8Array(buf)));
  }

  function base64ToBuf(b64) {
    return Uint8Array.from(atob(b64), (c) => c.charCodeAt(0));
  }

  // PBKDF2-SHA256, a random 16-byte salt, 100,000 iterations — every
  // stored credential goes through this, never a plain or reversibly-
  // encoded password.
  function derivePasswordHash(password, saltBytes) {
    return crypto.subtle.importKey('raw', new TextEncoder().encode(password), 'PBKDF2', false, ['deriveBits'])
      .then((keyMaterial) => crypto.subtle.deriveBits(
        { name: 'PBKDF2', salt: saltBytes, iterations: PBKDF2_ITERATIONS, hash: 'SHA-256' },
        keyMaterial,
        256
      ))
      .then((bits) => bufToBase64(bits));
  }

  // A fresh salt each time — resolves { salt, hash }, both base64.
  function hashNewPassword(password) {
    const saltBytes = crypto.getRandomValues(new Uint8Array(16));
    return derivePasswordHash(password, saltBytes).then((hash) => ({ salt: bufToBase64(saltBytes), hash }));
  }

  // Re-derives against a STORED salt and compares to the stored hash —
  // never decrypts anything (PBKDF2 isn't reversible), just recomputes
  // and checks for a match.
  function verifyPassword(password, storedSalt, storedHash) {
    return derivePasswordHash(password, base64ToBuf(storedSalt)).then((hash) => hash === storedHash);
  }

  function readSession() {
    try {
      return JSON.parse(localStorage.getItem(SESSION_KEY) || 'null');
    } catch (e) {
      return null;
    }
  }

  function writeSession(userId, email) {
    localStorage.setItem(SESSION_KEY, JSON.stringify({ userId, email }));
  }

  // LIME-33: creates a real local account — a credential (never the
  // plain password) plus a real profile row, so the new teacher shows
  // up in the directory exactly like a seeded one.
  function signUp(options) {
    const opts = options || {};
    const email = (opts.email || '').trim().toLowerCase();
    const password = opts.password || '';
    const displayName = (opts.displayName || '').trim();

    if (!isValidEmail(email)) return Promise.reject(new Error('Enter a valid email address.'));
    if (password.length < 8) return Promise.reject(new Error('Password must be at least 8 characters.'));
    if (!displayName) return Promise.reject(new Error('Display name is required.'));
    // LIME-33-fix: fail with a clear reason up front, rather than
    // completing sign-up only to have the redirect that follows bounce
    // back to login.html with no session and no explanation.
    if (!checkStorageWorks()) {
      return Promise.reject(new Error('Your browser isn\'t letting Lime save data on this computer right now — private browsing or blocked cookies/site data are the most common causes.'));
    }

    const credentials = loadCredentials();
    // Unique across BOTH credentials and profiles — a seed teacher's
    // email (no local credential yet) is still taken; signing up with
    // it would otherwise silently create a second, disconnected
    // identity for the same person.
    if (credentials[email] || LimeStore.findProfileByEmail(email)) {
      return Promise.reject(new Error('That email is already in use.'));
    }

    const userId = crypto.randomUUID();
    return hashNewPassword(password).then(({ salt, hash }) => {
      credentials[email] = { userId, salt, hash };
      saveCredentials(credentials);
      return LimeStore.createProfile({ id: userId, email, display_name: displayName });
    }).then(() => {
      writeSession(userId, email);
      return { userId, email };
    });
  }

  // Two paths: a local credential (signed up locally, or a seed teacher
  // who's since set their own password via changePassword), or a seed
  // teacher with no local credential yet, accepted against the shared
  // demo password — the existing login.html behavior, moved here.
  function signInWithPassword(options) {
    const opts = options || {};
    const email = (opts.email || '').trim().toLowerCase();
    const password = opts.password || '';

    if (!isValidEmail(email)) return Promise.reject(new Error('Enter a valid email address.'));
    if (!checkStorageWorks()) {
      return Promise.reject(new Error('Your browser isn\'t letting Lime save data on this computer right now — private browsing or blocked cookies/site data are the most common causes.'));
    }

    const credentials = loadCredentials();
    const credential = credentials[email];
    if (credential) {
      return verifyPassword(password, credential.salt, credential.hash).then((matches) => {
        if (!matches) throw new Error('Incorrect email or password.');
        writeSession(credential.userId, email);
        return { userId: credential.userId, email };
      });
    }

    // No local credential — only a seed teacher can sign in this way.
    const seedProfile = LimeStore.findProfileByEmail(email);
    if (!seedProfile) return Promise.reject(new Error('Incorrect email or password.'));
    const demo = window.LIME_DEMO_CREDENTIALS;
    if (!demo) {
      return Promise.reject(new Error('Demo credentials aren\'t configured locally (public/js/demo-config.local.js is gitignored and missing).'));
    }
    if (password !== demo.password) {
      // LIME-33-fix: distinct from the generic "Incorrect email or
      // password" above — a seed teacher's own real gate check surfaced
      // this as confusing (they tried a password they made up, not
      // realizing seed teachers share one demo password until they've
      // changed it themselves via Settings).
      return Promise.reject(new Error('Incorrect password. Demo teachers use the shared demo password unless you\'ve changed it in Settings.'));
    }
    writeSession(seedProfile.id, email);
    return Promise.resolve({ userId: seedProfile.id, email });
  }

  function getSession() {
    return Promise.resolve(readSession());
  }

  function changeEmail(newEmail) {
    const email = (newEmail || '').trim().toLowerCase();
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
      // by email on a session written before this brief's own userId-based
      // lookup existed. Also renames the credential's own key (LIME-33):
      // signInWithPassword looks credentials up BY email, so a stale key
      // would make this person permanently unable to sign back in with
      // their new address using the password they just set.
      const session = readSession();
      if (session) writeSession(session.userId || currentId, email);
      const credentials = loadCredentials();
      const oldEmail = Object.keys(credentials).find((e) => credentials[e].userId === currentId);
      if (oldEmail && oldEmail !== email) {
        credentials[email] = credentials[oldEmail];
        delete credentials[oldEmail];
        saveCredentials(credentials);
      }
      return profile;
    });
  }

  // LIME-33: really works now for local accounts — verifies `current`
  // against the stored credential (or, for a seed teacher who's never
  // set their own password, against the shared demo password — that's
  // what they signed in with), then stores a real new credential.
  // Claims the account: a seed teacher who changes their password gets
  // a real local credential from then on, no longer the shared demo one.
  function changePassword(options) {
    const opts = options || {};
    const current = opts.current || '';
    const next = opts.next || '';
    const confirm = opts.confirm || '';
    if (next.length < 8) {
      return Promise.reject(new Error('New password must be at least 8 characters.'));
    }
    if (next === current) {
      return Promise.reject(new Error('New password must be different from your current password.'));
    }
    if (next !== confirm) {
      return Promise.reject(new Error('New password and confirmation do not match.'));
    }
    const currentId = LimeStore.getCurrentUserId();
    const user = LimeStore.getCurrentUser();
    if (!user || !user.email) {
      return Promise.reject(new Error('No current account to change the password for.'));
    }
    const email = user.email.toLowerCase();
    const credentials = loadCredentials();
    const credential = credentials[email];

    const verifyCurrent = credential
      ? verifyPassword(current, credential.salt, credential.hash)
      : Promise.resolve(!!(window.LIME_DEMO_CREDENTIALS && current === window.LIME_DEMO_CREDENTIALS.password));

    return verifyCurrent.then((matches) => {
      if (!matches) throw new Error('Current password is incorrect.');
      return hashNewPassword(next);
    }).then(({ salt, hash }) => {
      credentials[email] = { userId: currentId, salt, hash };
      saveCredentials(credentials);
      return { message: 'Your password has been changed.' };
    });
  }

  function signOut() {
    localStorage.removeItem(SESSION_KEY);
    window.location.href = 'login.html';
  }

  // LIME-33: "Reset demo data" wipes accounts too, not just messages —
  // called alongside LimeStore.reset(), not folded into it (accounts are
  // this module's own concern, per the same reasoning email/password
  // never go through LimeStore.updateProfile either).
  function resetCredentials() {
    localStorage.removeItem(CREDENTIALS_KEY);
  }

  return { signUp, signInWithPassword, signOut, getSession, changeEmail, changePassword, resetCredentials, checkStorageWorks, accountExists };
})();

window.LimeAuth = LimeAuth;
