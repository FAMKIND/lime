// File storage under data/files/ plus a metadata file; multipart parsing; download authorisation lives in the engine.
import fs from 'node:fs';
import path from 'node:path';
import { E, ensureDir, writeJsonAtomic, readJson, uuid, nowIso } from './util.mjs';

export const MAX_FILE_BYTES = 10 * 1024 * 1024;
const UNATTACHED_TTL_MS = 24 * 60 * 60 * 1000;

export class Files {
  constructor(dataDir) {
    this.dir = path.join(dataDir, 'files');
    this.metaFile = path.join(dataDir, 'files.json');
    ensureDir(this.dir);
    this.meta = readJson(this.metaFile, {});
  }
  save() { writeJsonAtomic(this.metaFile, this.meta); }
  get(id) { return this.meta[id] || null; }
  pathFor(id) { return path.join(this.dir, path.basename(id)); }
  create({ uploader, name, mime, bytes }) {
    const file_id = uuid();
    fs.writeFileSync(this.pathFor(file_id), bytes);
    this.meta[file_id] = { file_id, uploader, name, mime, size: bytes.length, created_at: nowIso(), attached_to: null, conversation_id: null, kind: 'attachment' };
    this.save();
    return this.meta[file_id];
  }
  attach(id, messageId, conversationId) {
    const m = this.meta[id];
    if (m) { m.attached_to = messageId; m.conversation_id = conversationId; this.save(); }
  }
  markAvatar(id, userId) {
    const m = this.meta[id];
    if (m) { m.kind = 'avatar'; m.avatar_of = userId; this.save(); }
  }
  // Files nobody referenced within 24 hours.
  sweep() {
    const cutoff = Date.now() - UNATTACHED_TTL_MS;
    let removed = 0;
    for (const [id, m] of Object.entries(this.meta)) {
      if (!m.attached_to && m.kind !== 'avatar' && Date.parse(m.created_at) < cutoff) {
        try { fs.unlinkSync(this.pathFor(id)); } catch (e) { /* already gone */ }
        delete this.meta[id];
        removed++;
      }
    }
    if (removed) this.save();
    return removed;
  }
  reset() {
    fs.rmSync(this.dir, { recursive: true, force: true });
    ensureDir(this.dir);
    this.meta = {};
    this.save();
  }
}

// Reads a request body up to `limit` bytes; rejects with 413 as soon as it is exceeded.
export function readBody(req, limit) {
  return new Promise((resolve, reject) => {
    const declared = Number(req.headers['content-length']);
    if (declared && declared > limit) { req.resume(); reject(E.tooLarge()); return; }
    const chunks = [];
    let total = 0;
    req.on('data', (c) => {
      total += c.length;
      if (total > limit) { reject(E.tooLarge()); req.destroy(); return; }
      chunks.push(c);
    });
    req.on('end', () => resolve(Buffer.concat(chunks)));
    req.on('error', reject);
  });
}

// Minimal multipart/form-data: returns the part named "file" as { name, mime, bytes }.
export function parseMultipartFile(body, contentType) {
  const m = /boundary=(?:"([^"]+)"|([^;]+))/i.exec(contentType || '');
  if (!m) throw E.badRequest('Expected multipart/form-data with a boundary.');
  const boundary = Buffer.from('--' + (m[1] || m[2]).trim());
  let pos = body.indexOf(boundary);
  while (pos !== -1) {
    const start = pos + boundary.length;
    if (body.slice(start, start + 2).toString() === '--') break; // closing boundary
    const headerEnd = body.indexOf('\r\n\r\n', start);
    if (headerEnd === -1) break;
    const headers = body.slice(start, headerEnd).toString('utf8');
    const next = body.indexOf(boundary, headerEnd + 4);
    if (next === -1) break;
    const content = body.slice(headerEnd + 4, next - 2); // drop the CRLF before the next boundary
    const disp = /name="([^"]*)"/i.exec(headers);
    if (disp && disp[1] === 'file') {
      const fn = /filename="([^"]*)"/i.exec(headers);
      const ct = /content-type:\s*([^\r\n]+)/i.exec(headers);
      const name = fn ? fn[1].replace(/[\\/\0]/g, '_').slice(0, 200) : 'file';
      return { name: name || 'file', mime: ct ? ct[1].trim().slice(0, 100) : 'application/octet-stream', bytes: content };
    }
    pos = next;
  }
  throw E.badRequest('The upload needs a "file" field.');
}
