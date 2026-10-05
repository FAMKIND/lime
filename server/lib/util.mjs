// Small shared helpers. Node built-ins only.
import fs from 'node:fs';
import path from 'node:path';
import crypto from 'node:crypto';

export class ApiError extends Error {
  constructor(status, code, message) { super(message); this.status = status; this.code = code; }
}
export const E = {
  badRequest: (m) => new ApiError(400, 'bad_request', m),
  invalidOp: (m) => new ApiError(400, 'invalid_op', m),
  unauthenticated: (m = 'Sign in to continue.') => new ApiError(401, 'unauthenticated', m),
  invalidCredentials: () => new ApiError(401, 'invalid_credentials', 'Incorrect email or password.'),
  forbidden: (m = 'You’re not allowed to do that.') => new ApiError(403, 'forbidden', m),
  notFound: (m = 'Not found.') => new ApiError(404, 'not_found', m),
  conflict: (m) => new ApiError(409, 'conflict', m),
  expired: () => new ApiError(410, 'cursor_expired', 'That cursor is no longer valid; fetch /snapshot and start again.'),
  tooLarge: () => new ApiError(413, 'file_too_large', 'Files can be at most 10 MB.'),
  unsupportedOp: (t) => new ApiError(422, 'unsupported_op', 'This server does not know the op type ' + JSON.stringify(t) + '.'),
  rateLimited: (secs) => Object.assign(new ApiError(429, 'rate_limited', 'Too many attempts. Try again shortly.'), { retryAfter: secs }),
};

// Write to a temp file in the same folder, then rename: a crash leaves the old file or the new one, never half of one.
export function writeFileAtomic(file, data) {
  const tmp = file + '.' + process.pid + '.tmp';
  const fd = fs.openSync(tmp, 'w');
  try { fs.writeSync(fd, data); fs.fsyncSync(fd); } finally { fs.closeSync(fd); }
  fs.renameSync(tmp, file);
}
export function writeJsonAtomic(file, value) { writeFileAtomic(file, JSON.stringify(value)); }
export function readJson(file, fallback) {
  try { return JSON.parse(fs.readFileSync(file, 'utf8')); } catch (e) { return fallback; }
}
export function ensureDir(dir) { fs.mkdirSync(dir, { recursive: true }); }

export const uuid = () => crypto.randomUUID();
export const sha256 = (s) => crypto.createHash('sha256').update(s).digest('hex');
export const b64url = (buf) => Buffer.from(buf).toString('base64url');
export const nowIso = () => new Date().toISOString();

export const isStr = (v, max = 100000) => typeof v === 'string' && v.length <= max;
export const isId = (v) => typeof v === 'string' && /^[A-Za-z0-9._:-]{1,80}$/.test(v);
// A device id is a UUID, optionally with a short lowercase prefix ("web-<uuid>"). Anything else (a shared constant such as
// "web-volatile", an empty string) is refused, because two devices sharing an id would share one session.
export const isDeviceId = (v) => typeof v === 'string' && /^([a-z]{1,12}-)?[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i.test(v);
export const isObj = (v) => v !== null && typeof v === 'object' && !Array.isArray(v);
export const isEmail = (v) => typeof v === 'string' && v.length <= 254 && /^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(v);

export const MIME = {
  '.html': 'text/html; charset=utf-8', '.js': 'text/javascript; charset=utf-8', '.mjs': 'text/javascript; charset=utf-8',
  '.css': 'text/css; charset=utf-8', '.json': 'application/json; charset=utf-8', '.svg': 'image/svg+xml',
  '.png': 'image/png', '.jpg': 'image/jpeg', '.jpeg': 'image/jpeg', '.gif': 'image/gif', '.webp': 'image/webp',
  '.ico': 'image/x-icon', '.mp4': 'video/mp4', '.webm': 'video/webm', '.mp3': 'audio/mpeg', '.m4a': 'audio/mp4',
  '.wav': 'audio/wav', '.ogg': 'audio/ogg', '.woff': 'font/woff', '.woff2': 'font/woff2', '.ttf': 'font/ttf',
  '.txt': 'text/plain; charset=utf-8', '.md': 'text/plain; charset=utf-8', '.map': 'application/json',
};
export const mimeFor = (file) => MIME[path.extname(file).toLowerCase()] || 'application/octet-stream';

// ── usernames (LIME-84) ──
// Optional, unique (case-insensitively), 3 to 20 characters: letters, numbers, "." and "_", not starting or ending with a dot. A few
// words are reserved so nobody can pass for the app or its staff. The same rules live in public/js/store.js for the browser.
export const USERNAME_RESERVED = new Set(['admin', 'administrator', 'lime', 'support', 'help', 'root', 'system', 'moderator', 'mod',
  'staff', 'team', 'official', 'security', 'abuse', 'postmaster', 'webmaster', 'null', 'undefined', 'api', 'www', 'mail', 'info',
  'contact', 'billing', 'settings', 'account', 'me', 'you', 'everyone', 'all', 'here', 'famkind']);
// Returns an error message, or null when `value` is a valid username (a leading "@" is not part of it and must be removed first).
export function usernameError(value) {
  if (typeof value !== 'string') return 'Username must be text.';
  if (value.length < 3 || value.length > 20) return 'Use 3 to 20 characters.';
  if (!/^[A-Za-z0-9._]+$/.test(value)) return 'Use only letters, numbers, dots and underscores.';
  if (value.startsWith('.') || value.endsWith('.')) return 'A username can\u2019t start or end with a dot.';
  if (USERNAME_RESERVED.has(value.toLowerCase())) return 'That username is reserved. Try another.';
  return null;
}

// A friendly label for a device from its browser's User-Agent text: "iPhone \u00b7 Safari", "Mac \u00b7 Chrome". Best effort, never exact.
export function deviceLabel(ua) {
  const s = String(ua || '');
  if (!s) return 'Unknown device';
  const os = /iPhone/i.test(s) ? 'iPhone' : /iPad/i.test(s) ? 'iPad' : /Android/i.test(s) ? 'Android' : /Macintosh|Mac OS X/i.test(s) ? 'Mac'
    : /Windows/i.test(s) ? 'Windows' : /CrOS/i.test(s) ? 'Chromebook' : /Linux|X11/i.test(s) ? 'Linux' : 'Device';
  const browser = /Edg\//i.test(s) ? 'Edge' : /OPR\/|Opera/i.test(s) ? 'Opera' : /(Firefox|FxiOS)\//i.test(s) ? 'Firefox' : /(Chrome|CriOS|HeadlessChrome)\//i.test(s) ? 'Chrome'
    : /Safari\//i.test(s) ? 'Safari' : /node|undici|curl/i.test(s) ? 'App' : 'Browser';
  return os + ' \u00b7 ' + browser;
}
