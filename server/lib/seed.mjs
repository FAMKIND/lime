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

// The two dedicated test accounts (gitignored seed-data/test-accounts.local.json, never committed: real emails, phones and
// a real password). Returns null when the file is absent. Only the server reads it.
export function loadTestAccounts(repoRoot) {
  try {
    const j = JSON.parse(fs.readFileSync(path.join(repoRoot, 'seed-data', 'test-accounts.local.json'), 'utf8'));
    if (typeof j.password !== 'string' || j.password.length < 8 || !Array.isArray(j.accounts)) return null;
    const accounts = j.accounts.filter((a) => a && typeof a.id === 'string' && typeof a.email === 'string' && typeof a.display_name === 'string');
    return accounts.length ? { password: j.password, accounts } : null;
  } catch (e) {
    return null;
  }
}

// Plausible, teacher-like profile details for the test accounts (made up, safe to commit). Anything not listed is null.
const TEST_DETAILS = {
  'test-shem-rajoon': { role: 'Math Teacher', pronouns: 'he/him/his', school: 'PS 113', grade_levels: ['7', '8'], subjects: ['Algebra', 'Geometry'], bio: 'Math teacher at PS 113. I like turning word problems into puzzles.' },
  'test-jean-chung': { role: 'Head of FAM', pronouns: 'she/her/hers', school: 'PS 113', grade_levels: ['6', '7', '8'], subjects: ['Life Skills'], bio: 'Head of FAM at PS 113. Life skills, family partnerships and a lot of coffee.' },
};
export function testAccountDetails(id) { return TEST_DETAILS[id] || {}; }
