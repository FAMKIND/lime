// Accounts, tokens and sessions. Passwords: PBKDF2-SHA256, >= 600,000 iterations, per-user salt. Access tokens are
// short-lived HMAC-signed; refresh tokens are random, rotate on every use, and are stored only as hashes.
import crypto from 'node:crypto';
import path from 'node:path';
import fs from 'node:fs';
import { E, ApiError, ensureDir, writeJsonAtomic, readJson, sha256, b64url, isEmail, isId, isDeviceId, uuid, nowIso, deviceLabel } from './util.mjs';

export const PBKDF2_ITERATIONS = 600000;
const ACCESS_TTL_SECS = 15 * 60;
const REFRESH_TTL_MS = 30 * 24 * 60 * 60 * 1000;
const TICKET_TTL_MS = 60 * 1000;

const pbkdf2 = (password, salt, iterations) => new Promise((resolve, reject) => {
  crypto.pbkdf2(password, salt, iterations, 32, 'sha256', (err, key) => (err ? reject(err) : resolve(key.toString('base64'))));
});

export class Auth {
  constructor(dataDir, demoPassword) {
    ensureDir(dataDir);
    this.file = path.join(dataDir, 'auth.json');
    this.secretFile = path.join(dataDir, 'secret.key');
    this.demoPassword = demoPassword;
    this.data = readJson(this.file, { credentials: {}, sessions: {}, demo: null });
    if (!fs.existsSync(this.secretFile)) fs.writeFileSync(this.secretFile, crypto.randomBytes(32).toString('hex'), { mode: 0o600 });
    this.secret = fs.readFileSync(this.secretFile, 'utf8').trim();
    this.tickets = new Map(); // single-use realtime tickets, in memory only
    this.failures = new Map(); // email -> [timestamps]
    this.lookups = new Map(); // remote address -> [timestamps]
  }
  save() { writeJsonAtomic(this.file, this.data); }

  // Seed teachers share the demo password until they set their own (as in the browser demo). One salted hash serves all.
  async ensureSeedCredentials(seedProfiles) {
    let changed = false;
    if (this.demoPassword && !this.data.demo) {
      const salt = crypto.randomBytes(16).toString('base64');
      this.data.demo = { salt, iterations: PBKDF2_ITERATIONS, hash: await pbkdf2(this.demoPassword, Buffer.from(salt, 'base64'), PBKDF2_ITERATIONS) };
      changed = true;
    }
    for (const p of seedProfiles) {
      const email = (p.email || '').toLowerCase();
      if (email && !this.data.credentials[email]) { this.data.credentials[email] = { user_id: p.id, shared_demo: true }; changed = true; }
    }
    if (changed) this.save();
  }

  // Seed teachers with a private password of their own (the test accounts): their credential replaces the shared demo one.
  // Only sets it when the person still has the shared one or none, so a password changed in the app is never overwritten.
  async ensureOwnPasswords(profiles, password) {
    for (const p of profiles) {
      const email = (p.email || '').toLowerCase();
      const cred = this.data.credentials[email];
      if (!cred || cred.shared_demo) await this.createAccount(email, password, p.id);
    }
  }

  hasEmailLookup(address) {
    const now = Date.now();
    const recent = (this.lookups.get(address) || []).filter((t) => now - t < 60000);
    recent.push(now);
    this.lookups.set(address, recent);
    if (recent.length > 60) throw E.rateLimited(30);
  }

  // Change a password: verify the current one, store a new own credential, end every OTHER device's session.
  async changePassword(userId, deviceId, current, next) {
    if (typeof current !== 'string' || typeof next !== 'string') throw E.badRequest('current_password and new_password are required.');
    if (next.length < 8 || next.length > 200) throw E.badRequest('New password must be at least 8 characters.');
    if (next === current) throw E.badRequest('New password must be different from your current password.');
    const email = Object.keys(this.data.credentials).find((e) => this.data.credentials[e].user_id === userId);
    if (!email) throw E.notFound('No account to change the password for.');
    this.checkRate(email);
    const cred = this.data.credentials[email];
    let ok;
    if (cred.shared_demo) ok = !!this.data.demo && (await pbkdf2(current, Buffer.from(this.data.demo.salt, 'base64'), this.data.demo.iterations)) === this.data.demo.hash;
    else ok = (await pbkdf2(current, Buffer.from(cred.salt, 'base64'), cred.iterations)) === cred.hash;
    if (!ok) { this.recordFailure(email); throw E.forbidden('Current password is incorrect.'); }
    const salt = crypto.randomBytes(16);
    this.data.credentials[email] = { user_id: userId, salt: salt.toString('base64'), iterations: PBKDF2_ITERATIONS, hash: await pbkdf2(next, salt, PBKDF2_ITERATIONS) };
    for (const s of Object.values(this.data.sessions)) if (s.user_id === userId && s.device_id !== deviceId) s.revoked = true;
    this.save();
  }

  renameEmail(userId, oldEmail, newEmail) {
    const o = (oldEmail || '').toLowerCase();
    if (this.data.credentials[o] && this.data.credentials[o].user_id === userId) {
      this.data.credentials[newEmail] = this.data.credentials[o];
      delete this.data.credentials[o];
      this.save();
    }
  }

  checkRate(email) {
    const now = Date.now();
    const recent = (this.failures.get(email) || []).filter((t) => now - t < 60000);
    this.failures.set(email, recent);
    if (recent.length >= 10) throw E.rateLimited(Math.ceil((60000 - (now - recent[0])) / 1000));
  }
  recordFailure(email) { const list = this.failures.get(email) || []; list.push(Date.now()); this.failures.set(email, list); }

  async createAccount(email, password, userId) {
    const salt = crypto.randomBytes(16);
    this.data.credentials[email] = { user_id: userId, salt: salt.toString('base64'), iterations: PBKDF2_ITERATIONS, hash: await pbkdf2(password, salt, PBKDF2_ITERATIONS) };
    this.save();
  }
  hasEmail(email) { return !!this.data.credentials[email]; }

  async verify(email, password) {
    this.checkRate(email);
    const cred = this.data.credentials[email];
    let ok = false;
    if (cred && cred.shared_demo) {
      const demo = this.data.demo;
      if (!demo) throw new ApiError(401, 'invalid_credentials', 'Demo teachers can\u2019t sign in: this server has no demo password configured (public/js/demo-config.local.js).');
      ok = (await pbkdf2(password, Buffer.from(demo.salt, 'base64'), demo.iterations)) === demo.hash;
      if (!ok) { this.recordFailure(email); throw new ApiError(401, 'invalid_credentials', 'Incorrect password. Demo teachers use the shared demo password unless you\u2019ve changed it in Settings.'); }
    } else if (cred) {
      ok = (await pbkdf2(password, Buffer.from(cred.salt, 'base64'), cred.iterations)) === cred.hash;
    } else {
      await pbkdf2(password, Buffer.from('lime-no-such-user'), PBKDF2_ITERATIONS); // same cost whether or not the email exists
    }
    if (!ok) { this.recordFailure(email); throw E.invalidCredentials(); }
    return cred.user_id;
  }

  // ── tokens ──
  signAccess(userId, deviceId) {
    const body = b64url(JSON.stringify({ sub: userId, dev: deviceId, exp: Math.floor(Date.now() / 1000) + ACCESS_TTL_SECS }));
    const sig = b64url(crypto.createHmac('sha256', this.secret).update(body).digest());
    return body + '.' + sig;
  }
  verifyAccess(token) {
    const [body, sig] = String(token || '').split('.');
    if (!body || !sig) throw E.unauthenticated();
    const want = crypto.createHmac('sha256', this.secret).update(body).digest();
    const got = Buffer.from(sig, 'base64url');
    if (got.length !== want.length || !crypto.timingSafeEqual(got, want)) throw E.unauthenticated();
    let claims;
    try { claims = JSON.parse(Buffer.from(body, 'base64url').toString('utf8')); } catch (e) { throw E.unauthenticated(); }
    if (!claims.sub || claims.exp < Date.now() / 1000) throw E.unauthenticated('Your session expired. Refresh and try again.');
    // A signed-out or revoked device stops working at once, not when its token expires.
    const s = this.data.sessions[claims.sub + '|' + claims.dev];
    if (!s || s.revoked) throw E.unauthenticated('This device is signed out.');
    s.last_active_at = nowIso(); // in memory; reaches the disk with the next save
    return { userId: claims.sub, deviceId: claims.dev };
  }

  // LIME-84: a session also remembers the browser's own description (the User-Agent) and when it was last used, for the Linked Devices list.
  newRefresh(userId, deviceId, previousHash, userAgent) {
    const token = crypto.randomBytes(32).toString('base64url');
    const old = this.data.sessions[userId + '|' + deviceId];
    this.data.sessions[userId + '|' + deviceId] = {
      user_id: userId, device_id: deviceId, token_hash: sha256(token), prev_hash: previousHash || null,
      created_at: old && previousHash ? old.created_at : nowIso(), expires_at: new Date(Date.now() + REFRESH_TTL_MS).toISOString(), revoked: false,
      user_agent: userAgent || (old && old.user_agent) || '', last_active_at: nowIso(),
    };
    this.save();
    return token;
  }
  tokensFor(userId, deviceId, previousHash, userAgent) {
    return { access_token: this.signAccess(userId, deviceId), expires_in: ACCESS_TTL_SECS, refresh_token: this.newRefresh(userId, deviceId, previousHash, userAgent) };
  }

  // The caller's signed-in devices (not signed out), newest activity first.
  devicesFor(userId, currentDeviceId) {
    return Object.values(this.data.sessions)
      .filter((s) => s.user_id === userId && !s.revoked && s.expires_at > nowIso())
      .map((s) => ({ device_id: s.device_id, label: deviceLabel(s.user_agent), last_active_at: s.last_active_at || s.created_at, current: s.device_id === currentDeviceId }))
      .sort((a, b) => (b.last_active_at > a.last_active_at ? 1 : -1));
  }
  // Sign one of the caller's OTHER devices out: its refresh token stops working and so does its access token, at once.
  revokeDevice(userId, deviceId, currentDeviceId) {
    if (deviceId === currentDeviceId) throw E.badRequest('That is this device. Use Sign out to leave it.');
    const s = this.data.sessions[userId + '|' + deviceId];
    if (!s || s.revoked) throw E.notFound('No such device.');
    s.revoked = true;
    this.save();
  }
  refresh(refreshToken, deviceId, userAgent) {
    const hash = sha256(String(refreshToken || ''));
    const session = Object.values(this.data.sessions).find((s) => s.device_id === deviceId && (s.token_hash === hash || s.prev_hash === hash));
    if (!session) throw E.unauthenticated('Sign in again.');
    if (session.prev_hash === hash && session.token_hash !== hash) {
      // An already-rotated token was used again: someone has a copy. End that device's session.
      session.revoked = true; this.save();
      throw E.unauthenticated('Sign in again.');
    }
    if (session.revoked || session.expires_at < nowIso()) throw E.unauthenticated('Sign in again.');
    return { userId: session.user_id, tokens: this.tokensFor(session.user_id, deviceId, session.token_hash, userAgent) };
  }
  signOut(userId, deviceId) {
    const s = this.data.sessions[userId + '|' + deviceId];
    if (s) { s.revoked = true; this.save(); }
  }

  issueTicket(userId, deviceId) {
    const ticket = crypto.randomBytes(24).toString('base64url');
    this.tickets.set(ticket, { userId, deviceId, expires: Date.now() + TICKET_TTL_MS });
    for (const [t, v] of this.tickets) if (v.expires < Date.now()) this.tickets.delete(t);
    return ticket;
  }
  redeemTicket(ticket) {
    const t = this.tickets.get(ticket);
    this.tickets.delete(ticket); // single use
    if (!t || t.expires < Date.now()) throw E.unauthenticated('That realtime ticket is not valid.');
    return t;
  }

  reset() {
    this.data = { credentials: {}, sessions: {}, demo: null };
    this.secret = crypto.randomBytes(32).toString('hex'); // every outstanding token stops working
    fs.writeFileSync(this.secretFile, this.secret, { mode: 0o600 });
    this.tickets.clear(); this.failures.clear();
    this.save();
  }
}

export const checkSignup = ({ email, password, display_name, device_id }) => {
  if (!isEmail(email)) throw E.badRequest('Enter a valid email address.');
  if (typeof password !== 'string' || password.length < 8 || password.length > 200) throw E.badRequest('Password must be at least 8 characters.');
  if (typeof display_name !== 'string' || !display_name.trim() || display_name.length > 200) throw E.badRequest('Display name is required.');
  if (!isDeviceId(device_id)) throw E.badRequest('device_id must be a UUID (optionally with a prefix like web-).');
};
export { uuid };
