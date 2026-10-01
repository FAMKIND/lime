// Builds the six tables from the app's own seed, by running the app's own seed code in a sandbox, so the
// server and the browser can never disagree about what the seed is.
import fs from 'node:fs';
import path from 'node:path';
import vm from 'node:vm';
import crypto from 'node:crypto';

export function loadSeed(repoRoot) {
  const js = (f) => fs.readFileSync(path.join(repoRoot, 'public', 'js', f), 'utf8');
  const storage = { getItem: () => null, setItem() {}, removeItem() {} };
  const window = { dispatchEvent() {} };
  const sandbox = {
    window, localStorage: storage, sessionStorage: storage, crypto,
    document: { dispatchEvent() {} }, CustomEvent: class { constructor(n, d) { this.type = n; this.detail = d && d.detail; } },
    indexedDB: {}, URL, console, setTimeout, clearTimeout, Promise,
  };
  sandbox.window = Object.assign(window, sandbox, { window });
  vm.createContext(sandbox);
  vm.runInContext(js('seed-data.js'), sandbox, { filename: 'seed-data.js' });
  vm.runInContext(js('local-adapter.js') + '\n;globalThis.__LocalAdapter = LocalAdapter;', sandbox, { filename: 'local-adapter.js' });
  const state = sandbox.__LocalAdapter.load(); // no snapshot in the sandbox, so this is a fresh normalize of the seed
  return {
    profiles: state.profiles, conversations: state.conversations, conversation_members: state.conversation_members,
    messages: state.messages, message_reactions: state.message_reactions, message_attachments: state.message_attachments || [],
    linkPreview: (url) => sandbox.__LocalAdapter.getLinkPreview(url),
  };
}

// The shared demo password from the gitignored local file, if it exists (same file the browser demo sign-in reads).
export function loadDemoPassword(repoRoot) {
  try {
    const src = fs.readFileSync(path.join(repoRoot, 'public', 'js', 'demo-config.local.js'), 'utf8');
    const sandbox = { window: {} };
    vm.createContext(sandbox);
    vm.runInContext(src, sandbox);
    const pw = sandbox.window.LIME_DEMO_CREDENTIALS && sandbox.window.LIME_DEMO_CREDENTIALS.password;
    return typeof pw === 'string' && pw ? pw : null;
  } catch (e) {
    return null;
  }
}

// Private overrides for two seed teachers (gitignored seed-data/test-accounts.local.json, never committed): the one thing about the
// demo Shem and Jean that must stay private, their phone numbers, and a password of their own instead of the shared demo password.
// Keyed by email (the seed's emails are public @famkind.com addresses). Returns null when the file is absent. Only the server reads it.
export function loadTestAccounts(repoRoot) {
  try {
    const j = JSON.parse(fs.readFileSync(path.join(repoRoot, 'seed-data', 'test-accounts.local.json'), 'utf8'));
    if (typeof j.password !== 'string' || j.password.length < 8 || !Array.isArray(j.accounts)) return null;
    const accounts = j.accounts.filter((a) => a && typeof a.email === 'string').map((a) => ({ email: a.email.trim().toLowerCase(), phone: typeof a.phone === 'string' ? a.phone : null }));
    return accounts.length ? { password: j.password, accounts } : null;
  } catch (e) {
    return null;
  }
}
