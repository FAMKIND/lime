'use strict';

// LimeIds (LIME-76) — ids that work on every page address. The browser's randomUUID() and crypto.subtle exist only in "secure contexts"
// (https and http://localhost); a phone opening the dev server at http://192.168.x.x is NOT one, and there randomUUID() throws, which
// silently stopped every message from being sent. crypto.getRandomValues is available everywhere, so ids are built from it.
//
//   newId()       a random UUIDv4 (messages, conversations, attachments, accounts, files)
//   newOpId()     a UUIDv7 (time-ordered; the idempotency key of an op, docs/api.md section 2)
//   newDeviceId() 'web-' + a UUIDv4, one per browser (stored by api-adapter.js)
const LimeIds = (function () {
  function randomBytes(n) {
    const b = new Uint8Array(n);
    if (typeof crypto !== 'undefined' && typeof crypto.getRandomValues === 'function') crypto.getRandomValues(b);
    else for (let i = 0; i < n; i++) b[i] = Math.floor(Math.random() * 256); // no Web Crypto at all: still unique enough, never throws
    return b;
  }
  function format(b) {
    const h = Array.from(b, (x) => x.toString(16).padStart(2, '0')).join('');
    return h.slice(0, 8) + '-' + h.slice(8, 12) + '-' + h.slice(12, 16) + '-' + h.slice(16, 20) + '-' + h.slice(20);
  }
  function newId() {
    const b = randomBytes(16);
    b[6] = (b[6] & 0x0f) | 0x40; // version 4
    b[8] = (b[8] & 0x3f) | 0x80; // variant
    return format(b);
  }
  function newOpId() {
    const b = randomBytes(16);
    let ts = Date.now();
    for (let i = 5; i >= 0; i--) { b[i] = ts % 256; ts = Math.floor(ts / 256); } // 48-bit millisecond timestamp first, so ids sort by time
    b[6] = (b[6] & 0x0f) | 0x70; // version 7
    b[8] = (b[8] & 0x3f) | 0x80;
    return format(b);
  }
  const newDeviceId = () => 'web-' + newId();
  return { newId, newOpId, newDeviceId };
})();
window.LimeIds = LimeIds;
