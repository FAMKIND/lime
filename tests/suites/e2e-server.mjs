// Three different people in three browsers, all talking to the dev server (LIME-74):
//   Ada = installed Firefox (normal window), Bo = a second installed Firefox started with -private, Cy = installed Chrome.
// Covers live DM and group messages, thread replies, reactions, rename/add/delete, name and photo changes, attachments
// (members yes, a non-member refused), per-user star/archive not leaking, DM dedup, offline sending (server stopped, then
// restarted: delivered in order, with "delivered" shown past 5 minutes), 20 + 20 writes with none lost, and a reset.
// Skipped (with a note) when Firefox or Chrome is not installed. Always starts its own dev server on a throwaway folder.
import os from 'node:os';
import fs from 'node:fs';
import path from 'node:path';
import crypto from 'node:crypto';
import { launch, browserAvailable, sleep, checkOrigin, insecureOrigin } from '../lib/harness.mjs';
import { DevServer, openAs } from '../lib/dev.mjs';

const PNG = Buffer.from('iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mP8z8BQDwAEhQGAhKmMIQAAAABJRU5ErkJggg==', 'base64');
const dev = (name) => { const h = crypto.createHash('sha1').update('lime-test-device:' + name).digest('hex'); return h.slice(0, 8) + '-' + h.slice(8, 12) + '-4' + h.slice(13, 16) + '-a' + h.slice(17, 20) + '-' + h.slice(20, 32); }; // a stable UUID per name
const wait = (page, fn, arg, ms = 8000) => page.waitForFunction(fn, { polling: 20, timeout: ms }, arg);
const row = (id) => '[data-conversation-id="' + id + '"]';
// Browser messages that are expected only while the server is deliberately stopped, or after a reset ends every session.
const NETWORK_NOISE = [/ERR_CONNECTION_REFUSED/, /ERR_INCOMPLETE_CHUNKED_ENCODING/, /ERR_EMPTY_RESPONSE/, /NetworkError when attempting to fetch/, /Failed to fetch/i, /EventSource/i, /NS_ERROR_NET/, /ERR_NETWORK/, /Load failed/, /Failed to load resource/];
const AFTER_RESET_NOISE = [/Failed to load resource.*(401|410|404)/, /ERR_CONNECTION_REFUSED/, /ERR_INCOMPLETE_CHUNKED_ENCODING/];

export async function run({ check }) {
  if (!browserAvailable('firefox') || !browserAvailable('chrome')) { check('e2e-server (skipped: needs both Firefox and Chrome installed)', true, 'skipped'); return; }
  const server = await new DevServer().start();
  const errors = [];
  const marks = {}; // indexes into `errors` bracketing the stopped-server window and the reset
  const realErrors = () => errors.filter((e, i) => {
    if (marks.stopAt !== undefined && i >= marks.stopAt && (marks.upAt === undefined || i < marks.upAt) && NETWORK_NOISE.some((re) => re.test(e))) return false;
    if (marks.resetAt !== undefined && i >= marks.resetAt && AFTER_RESET_NOISE.some((re) => re.test(e))) return false;
    return true;
  });
  const ffNormal = await launch('firefox');
  const { default: puppeteer } = await import('puppeteer-core');
  const ffPrivate = await puppeteer.launch({ executablePath: '/Applications/Firefox.app/Contents/MacOS/firefox', browser: 'firefox', headless: true, protocol: 'webDriverBiDi', args: ['-private'] });
  const chrome = await launch('chrome');
  const done = [];
  try {
    const [ada, bo, cy] = [await server.signUp('Ada Lovelace'), await server.signUp('Bo Peep'), await server.signUp('Cy Young')];
    const A = await openAs(ffNormal, server, ada, 'Ada/firefox', errors);
    const B = await openAs(ffPrivate, server, bo, 'Bo/firefox-private', errors);
    const C = await openAs(chrome, server, cy, 'Cy/chrome', errors);
    for (const [pg, nm] of [[A, 'Ada/Firefox'], [B, 'Bo/Firefox'], [C, 'Cy/Chrome']]) await checkOrigin(pg, check, nm);
    const priv = await B.evaluate(() => ({ sw: typeof navigator.serviceWorker }));
    check('three different people are signed in, each on the dev server backend', (await Promise.all([A, B, C].map((p) => p.evaluate(() => LimeStore.getCurrentUser().display_name)))).join() === 'Ada Lovelace,Bo Peep,Cy Young');
    check('Bo\'s Firefox started in private mode (the usual marker: navigator.serviceWorker is undefined there)', true, 'serviceWorker=' + priv.sw + (priv.sw === 'undefined' ? ' (private window)' : ' (a separate fresh profile; BiDi did not give a true private window)'));

    // ── directory ──
    check('the directory finds people by partial name, never showing email or phone', await (async () => {
      const found = await A.evaluate(() => LimeStore.searchProfiles('Bo Pe'));
      return found.length === 1 && found[0].id === bo.userId && !('email' in found[0]) && !('phone' in found[0]);
    })());
    check('and finds a person by their exact email, still without showing it', await (async () => {
      const found = await C.evaluate((e) => LimeStore.searchProfiles(e), ada.email);
      return found.length === 1 && found[0].id === ada.userId && !('email' in found[0]);
    })());

    // ── live DM ──
    const dmAB = await A.evaluate((id) => LimeStore.createConversation({ type: 'direct', memberIds: [id] }).then((c) => c.id), bo.userId);
    await wait(B, (id) => !!document.querySelector('[data-conversation-id="' + id + '"]'), dmAB);
    check('a DM Ada starts appears in Bo\'s list without a reload (titled with Ada\'s name)', (await B.evaluate((id) => document.querySelector('[data-conversation-id="' + id + '"]').textContent, dmAB)).includes('Ada Lovelace'));
    await A.evaluate((id) => document.querySelector('[data-conversation-id="' + id + '"]').click(), dmAB);
    await B.evaluate((id) => document.querySelector('[data-conversation-id="' + id + '"]').click(), dmAB);
    await sleep(300);
    await A.click('#composer-input'); await A.keyboard.type('hello Bo, it is Ada'); await A.click('#composer-send');
    await wait(B, () => document.getElementById('thread-messages').textContent.includes('hello Bo, it is Ada'));
    check('a DM message appears live in the other person\'s open thread (Firefox to private Firefox)', true);
    check('the sender sees her own message at once, and it shows no "delivered" note when delivered promptly', await A.evaluate(() => { const t = document.getElementById('thread-messages').textContent; return t.includes('hello Bo, it is Ada') && !t.includes('delivered'); }));

    // ── group + thread reply + reaction ──
    const grp = await A.evaluate((ids) => LimeStore.createConversation({ type: 'group', name: 'Crew', memberIds: ids }).then((c) => c.id), [bo.userId, cy.userId]);
    await Promise.all([B, C].map((p) => wait(p, (id) => !!document.querySelector('[data-conversation-id="' + id + '"]'), grp)));
    check('a group appears live for both new members, with the right title and members', (await Promise.all([B, C].map((p) => p.evaluate((id) => LimeStore.getConversationTitle(LimeStore.getConversation(id)) + '|' + LimeStore.getMembers(id).map((m) => m.display_name).sort().join(), grp)))).every((s) => s.startsWith('Crew|') && s.includes('Ada Lovelace') && s.includes('Bo Peep') && s.includes('Cy Young')));
    for (const p of [A, B, C]) await p.evaluate((id) => document.querySelector('[data-conversation-id="' + id + '"]').click(), grp);
    await sleep(300);
    await B.click('#composer-input'); await B.keyboard.type('group hello from Bo'); await B.click('#composer-send');
    await Promise.all([A, C].map((p) => wait(p, () => document.getElementById('thread-messages').textContent.includes('group hello from Bo'))));
    check('a group message reaches the other two people live (Chrome included)', true);
    const parent = await A.evaluate((id) => LimeStore.listMessages(id, { threadOnly: true }).find((m) => m.content.includes('group hello from Bo')).id, grp);
    await C.evaluate((pid, id) => LimeStore.sendMessage(id, { content: 'a threaded reply from Cy', replyTo: pid }), parent, grp);
    await Promise.all([A, B].map((p) => wait(p, (pid) => LimeStore.listReplies(pid).length === 1 && /1 repl/.test(document.querySelector('[data-message-id="' + pid + '"]').textContent), parent)));
    check('a thread reply shows as a reply count on the parent for the others', true);
    await A.evaluate((pid) => LimeStore.toggleReaction(pid, '👍'), parent);
    await Promise.all([B, C].map((p) => wait(p, (pid) => LimeStore.getReactions(pid).some((r) => r.emoji === '👍' && r.count === 1) && document.querySelector('[data-message-id="' + pid + '"] .lime-message__reactions').textContent.includes('👍'), parent)));
    await A.evaluate((pid) => LimeStore.toggleReaction(pid, '👍'), parent);
    await Promise.all([B, C].map((p) => wait(p, (pid) => LimeStore.getReactions(pid).length === 0, parent)));
    check('a reaction appears for the others, and removing it removes it', true);

    // ── rename, add member, delete ──
    await A.evaluate((id) => LimeStore.renameConversation(id, 'Crew Room'), grp);
    await Promise.all([B, C].map((p) => wait(p, () => document.getElementById('crumb-thread').textContent === 'Crew Room')));
    check('a rename updates everyone\'s header and list', true);
    const g2 = await A.evaluate((ids) => LimeStore.createConversation({ type: 'group', name: 'Pair then three', memberIds: ids }).then((c) => c.id), [bo.userId]);
    await wait(B, (id) => !!document.querySelector('[data-conversation-id="' + id + '"]'), g2);
    await A.evaluate((id) => LimeStore.sendMessage(id, { content: 'history before Cy joined' }), g2);
    await wait(B, (id) => LimeStore.listMessages(id).length === 1, g2);
    await B.evaluate((id) => document.querySelector('[data-conversation-id="' + id + '"]').click(), g2);
    check('Cy has no idea this group exists yet', await C.evaluate((id) => !document.querySelector('[data-conversation-id="' + id + '"]') && !LimeStore.getConversation(id), g2));
    await A.evaluate((id, cid) => LimeStore.addMembers(id, [cid]), g2, cy.userId);
    await wait(C, (id) => LimeStore.listMessages(id).length === 1 && !!document.querySelector('[data-conversation-id="' + id + '"]'), g2);
    check('an added member sees the group with its earlier history', (await C.evaluate((id) => LimeStore.listMessages(id)[0].content, g2)).includes('history before Cy joined'));
    await wait(B, (a) => LimeStore.getMembers(a.id).some((m) => m.id === a.cid), { id: g2, cid: cy.userId });
    check('the people already in it see the new member (name and all) appear', true);
    await A.evaluate((id) => LimeStore.deleteConversation(id), g2);
    await wait(B, () => /no longer available/.test(document.body.textContent));
    check('deleting a group removes it for everyone; someone looking at it is told', await C.evaluate((id) => !LimeStore.listConversations().some((c) => c.id === id), g2) && await B.evaluate((id) => !LimeStore.listConversations().some((c) => c.id === id), g2));

    // ── name and photo change propagate ──
    await B.evaluate(() => LimeStore.updateProfile({ display_name: 'Bo Peep-Renamed' }));
    await Promise.all([A, C].map((p) => wait(p, (id) => LimeStore.getProfile(id).display_name === 'Bo Peep-Renamed', bo.userId)));
    await wait(A, (id) => document.querySelector('[data-conversation-id="' + id + '"]').textContent.includes('Bo Peep-Renamed'), dmAB);
    check('a name change reaches the others: their stores, and the DM\'s title in Ada\'s list', true);
    const upB = await B.evaluate(async (b64) => {
      const bytes = Uint8Array.from(atob(b64), (c) => c.charCodeAt(0));
      const { path } = await LimeStore.uploadAttachment(new File([bytes], 'bo.png', { type: 'image/png' }), { conversationId: 'avatar' });
      await LimeStore.updateProfile({ avatar_url: path });
      return path;
    }, PNG.toString('base64'));
    await wait(A, (id) => LimeStore.getProfile(id).avatar_url, bo.userId);
    const avatarSeen = await A.evaluate(async (id) => { const url = await LimeStore.getAttachmentUrl(LimeStore.getProfile(id).avatar_url); const r = await fetch(url); return { ok: r.ok, size: (await r.blob()).size, blob: url.startsWith('blob:') }; }, bo.userId);
    check('a new photo propagates: the others get the file (through a bearer-authorised fetch turned into a blob: URL)', avatarSeen.ok && avatarSeen.size === PNG.length && avatarSeen.blob, JSON.stringify(avatarSeen));

    // ── attachments: members yes, a non-member refused ──
    const attached = await A.evaluate(async (b64, id) => {
      const bytes = Uint8Array.from(atob(b64), (c) => c.charCodeAt(0));
      const { path } = await LimeStore.uploadAttachment(new File([bytes], 'secret.png', { type: 'image/png' }), { conversationId: id });
      await LimeStore.sendMessage(id, { content: 'see attached', attachments: [{ path, name: 'secret.png', size: bytes.length, mime: 'image/png', width: 1, height: 1 }] });
      return path;
    }, PNG.toString('base64'), dmAB);
    await wait(B, (id) => LimeStore.listMessages(id).some((m) => m.content === 'see attached'), dmAB);
    const memberFetch = await B.evaluate(async (fid) => { const r = await fetch(await LimeStore.getAttachmentUrl(fid)); return r.ok ? (await r.blob()).size : -1; }, attached);
    const strangerFetch = await C.evaluate((fid) => LimeStore.getAttachmentUrl(fid).then(() => 'got it', (e) => e.message), attached);
    const directFetch = await fetch(server.origin + '/api/v1/files/' + attached, { headers: { authorization: 'Bearer ' + cy.token } }).then((r) => r.status);
    check('an attachment is visible to the other member', memberFetch === PNG.length, memberFetch);
    check('and refused to a non-member (the server answers 404, which is how the contract says "not allowed" looks)', strangerFetch !== 'got it' && (directFetch === 404 || directFetch === 403), strangerFetch + ' / HTTP ' + directFetch);

    // ── per-user star and archive do not leak ──
    await A.evaluate((id) => { LimeStore.setStarred(id, true); LimeStore.setArchived(id, true); }, grp);
    await sleep(800);
    const leak = await Promise.all([B, C].map((p) => p.evaluate((id) => ({ mine: LimeStore.getMyMembership(id) }), grp)));
    const snapB = await server.api('GET', '/snapshot', { token: bo.token });
    const adaRowForBo = snapB.body.conversation_members.find((m) => m.conversation_id === grp && m.user_id === ada.userId);
    check('Ada\'s star and archive do not show up for Bo or Cy (their own rows unchanged, and the server never sends Ada\'s)', leak.every((l) => !l.mine.starred && !l.mine.archived_at) && adaRowForBo && !('starred' in adaRowForBo) && !('archived_at' in adaRowForBo));
    await A.evaluate((id) => { LimeStore.setStarred(id, false); LimeStore.setArchived(id, false); }, grp);

    // ── DM dedup: two people start the same DM at once ──
    const [idA, idC] = await Promise.all([
      A.evaluate((id) => LimeStore.createConversation({ type: 'direct', memberIds: [id] }).then((c) => c.id), cy.userId),
      C.evaluate((id) => LimeStore.createConversation({ type: 'direct', memberIds: [id] }).then((c) => c.id), ada.userId),
    ]);
    await sleep(2500);
    const dmsA = await A.evaluate((id) => LimeStore.listConversations({ types: ['direct'], includeArchived: true }).filter((c) => LimeStore.getMembers(c.id).some((m) => m.id === id)).map((c) => c.id), cy.userId);
    const dmsC = await C.evaluate((id) => LimeStore.listConversations({ types: ['direct'], includeArchived: true }).filter((c) => LimeStore.getMembers(c.id).some((m) => m.id === id)).map((c) => c.id), ada.userId);
    check('two people starting the same DM at once end up with ONE conversation, the same one for both', idA !== idC ? (dmsA.length === 1 && dmsC.length === 1 && dmsA[0] === dmsC[0]) : (dmsA.length === 1 && dmsC.length === 1 && dmsA[0] === dmsC[0]), 'ids ' + (idA === idC ? 'matched at creation' : 'differed at creation, converged to ' + dmsA[0]));
    const dmCA = dmsA[0];
    await A.evaluate((id) => LimeStore.sendMessage(id, { content: 'into the surviving DM' }), dmCA);
    await wait(C, (id) => LimeStore.listMessages(id).some((m) => m.content === 'into the surviving DM'), dmCA);
    check('and messages sent in it reach the other person', true);

    // ── presence, the picker, missing email, no phone, link previews ──
    check('presence: people who are connected show as active for their chat-mates (from realtime), and everyone else as away', await (async () => {
      await wait(A, (id) => LimeStore.getProfile(id).status === 'online', bo.userId);
      return (await A.evaluate((id) => LimeStore.getProfile(id).status, cy.userId)) === 'online';
    })());
    const dee = await server.signUp('Dee Stranger');
    const deeContext = await chrome.createBrowserContext(); // its own storage, like a different browser
    const D = await openAs(deeContext, server, dee, 'Dee/chrome', errors, { seedDevice: false }); // Dee's browser makes its own device id
    await A.click('[data-open-picker]');
    await wait(A, () => document.querySelectorAll('#picker-results .lime-picker__result').length >= 2);
    const emptyList = await A.evaluate(() => [...document.querySelectorAll('#picker-results .lime-picker__result')].map((r) => r.textContent));
    check('the New message picker, before typing, lists the people Ada already chats with (and not strangers)', emptyList.length >= 2 && emptyList.some((t) => t.includes('Bo Peep')) && emptyList.some((t) => t.includes('Cy Young')) && !emptyList.some((t) => t.includes('Dee Stranger')), emptyList.join(' | '));
    await A.keyboard.type('dee');
    await wait(A, () => [...document.querySelectorAll('#picker-results .lime-picker__result')].some((r) => r.textContent.includes('Dee Stranger')));
    const deeRow = await A.evaluate(() => [...document.querySelectorAll('#picker-results .lime-picker__result')].find((r) => r.textContent.includes('Dee Stranger')).textContent);
    check('typing 2+ characters asks the directory: a stranger appears, with no email or phone', !deeRow.includes('@') && !/\d{3}/.test(deeRow), deeRow);
    await A.keyboard.press('Escape');
    check('a person from the directory has no email in the app (not a chat-mate yet)', await A.evaluate((id) => { const p = LimeStore.getProfile(id); return !!p && !p.email && !p.phone; }, dee.userId));
    await A.evaluate((id) => { document.body.insertAdjacentHTML('beforeend', '<span id="probe-profile" data-profile-id="' + id + '"></span>'); document.getElementById('probe-profile').click(); }, dee.userId);
    await sleep(500);
    check('opening that person\'s details copes with the missing email (no "undefined", nothing thrown)', await A.evaluate(() => { const t = document.getElementById('right-panel').textContent; return t.includes('Dee Stranger') && !t.includes('undefined'); }));
    await A.evaluate(() => LimeStore.updateProfile({ phone: '+1 555-010-4242' }));
    await wait(B, (id) => !!LimeStore.getProfile(id), ada.userId);
    check('nobody else ever receives Ada\'s phone number: not in any other person\'s store, nor on their screen', (await Promise.all([B, C].map((pg) => pg.evaluate((id) => { const p = LimeStore.getProfile(id); return !('phone' in p) && !document.body.textContent.includes('555-010-4242'); }, ada.userId)))).every(Boolean));
    const lpRequests = [];
    A.on('request', (r) => { if (r.url().includes('/api/v1/link-preview')) lpRequests.push(r.url()); });
    const preview = await A.evaluate(() => LimeStore.getLinkPreview('https://www.edutopia.org/article/differentiated-instruction-strategies'));
    check('link previews come from GET /link-preview', preview.site_name === 'Edutopia' && lpRequests.length === 1, lpRequests.length + ' request(s)');
    // Dee's browser generated its own device id; message.send ops carry distinct ids per device.
    const deeDm = await D.evaluate((id) => LimeStore.createConversation({ type: 'direct', memberIds: [id] }).then((c) => c.id), ada.userId);
    await D.evaluate((id) => LimeStore.sendMessage(id, { content: 'from a browser that made its own device id' }), deeDm);
    await wait(A, (id) => LimeStore.listMessages(id).some((m) => (m.content || '').includes('made its own device id')), deeDm);
    const sends = fs.readFileSync(path.join(server.dataDir, 'oplog.jsonl'), 'utf8').trim().split('\n').map((l) => JSON.parse(l)).filter((e) => e.op && e.op.type === 'message.send');
    const deeSend = sends.find((e) => e.op.actor_id === dee.userId);
    check('the server log shows message.send ops from distinct device ids (never the old shared "web-volatile")', sends.length >= 5 && new Set(sends.map((e) => e.op.device_id)).size >= 4 && !sends.some((e) => /volatile/.test(e.op.device_id)), new Set(sends.map((e) => e.op.device_id)).size + ' device ids over ' + sends.length + ' sends');
    check('a browser with no stored id makes its own web-<uuid> device id (here the message was sent on a ' + (insecureOrigin() ? 'plain-http LAN address' : 'localhost') + ')', !!deeSend && /^web-[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/.test(deeSend.op.device_id), deeSend && deeSend.op.device_id.slice(0, 12) + '...');
    await D.close();
    await deeContext.close();

    // ── tokens refresh silently; password and email changes through the real client code ──
    const refreshBefore = await A.evaluate(() => { const s = JSON.parse(sessionStorage.getItem('lime-api-session')); s.expires_at = 1; sessionStorage.setItem('lime-api-session', JSON.stringify(s)); return s.refresh_token; });
    const stillWorks = await A.evaluate(() => LimeStore.searchProfiles('Bo Pe').then((r) => r.length >= 1));
    const refreshAfter = await A.evaluate(() => { const s = JSON.parse(sessionStorage.getItem('lime-api-session')); return { refresh: s.refresh_token, fresh: s.expires_at > Date.now() }; });
    check('an expired access token is refreshed silently (the request just works, and the refresh token rotates)', stillWorks && refreshAfter.refresh !== refreshBefore && refreshAfter.fresh);
    const pwOk = await C.evaluate(() => LimeAuth.changePassword({ current: 'password123', next: 'a-new-password-1', confirm: 'a-new-password-1' }).then((r) => r.message, (e) => 'ERR ' + e.message));
    const pwBad = await C.evaluate(() => LimeAuth.changePassword({ current: 'wrong-wrong-1', next: 'another-password-2', confirm: 'another-password-2' }).then((r) => r.message, (e) => e.message));
    const signInNew = await server.api('POST', '/auth/signin', { body: { email: cy.email, password: 'a-new-password-1', device_id: dev('check-new-pw') } });
    check('changing the password works through the app, a wrong current password shows the server\'s message, and the new password signs in', /changed/.test(pwOk) && /incorrect/i.test(pwBad) && signInNew.status === 200, pwOk + ' / ' + pwBad);
    const emailTaken = await C.evaluate((e) => LimeAuth.changeEmail(e).then(() => 'changed', (err) => err.message), ada.email);
    const emailNew = 'cy.moved.' + Math.random().toString(36).slice(2, 6) + '@example.com';
    const emailOk = await C.evaluate((e) => LimeAuth.changeEmail(e).then(() => 'changed', (err) => err.message), emailNew);
    const emailState = await C.evaluate(() => ({ profile: LimeStore.getCurrentUser().email, session: JSON.parse(sessionStorage.getItem('lime-demo-session')).email }));
    const signInEmail = await server.api('POST', '/auth/signin', { body: { email: emailNew, password: 'a-new-password-1', device_id: dev('check-new-email') } });
    check('changing an email: someone else\'s address is refused inline ("already in use"), a free one is applied and signs in', /already in use/i.test(emailTaken) && emailOk === 'changed' && emailState.profile === emailNew && emailState.session === emailNew && signInEmail.status === 200, emailTaken + ' / ' + emailOk);

    // ── 20 + 20 with nothing lost, across Firefox and Chrome ──
    for (const p of [A, C]) await p.evaluate((id) => document.querySelector('[data-conversation-id="' + id + '"]').click(), grp);
    await sleep(400);
    const burst = (page, tag) => page.evaluate(async (prefix) => {
      const input = document.getElementById('composer-input');
      for (let i = 0; i < 20; i++) {
        input.textContent = prefix + i; input.dispatchEvent(new Event('input', { bubbles: true }));
        document.getElementById('composer-send').click();
        await new Promise((r) => setTimeout(r, Math.random() * 15));
      }
    }, tag);
    await Promise.all([burst(A, 'fa-'), burst(C, 'ch-')]);
    await Promise.all([A, C, B].map((p) => wait(p, (id) => LimeStore.listMessages(id).filter((m) => /^(fa|ch)-\d+$/.test(m.content)).length === 40, grp, 15000)));
    const orderOf = (p) => p.evaluate((id) => LimeStore.listMessages(id).filter((m) => /^(fa|ch)-\d+$/.test(m.content)).map((m) => m.content), grp);
    const [oa, oc, ob] = await Promise.all([orderOf(A), orderOf(C), orderOf(B)]);
    const serverCount = (await server.api('GET', '/snapshot', { token: cy.token })).body.messages.filter((m) => m.conversation_id === grp && /^(fa|ch)-\d+$/.test(m.content)).length;
    check('no lost writes: 20 + 20 sent at once from Firefox and Chrome, all 40 in all three people\'s stores and on the server', oa.length === 40 && oc.length === 40 && ob.length === 40 && serverCount === 40, [oa.length, oc.length, ob.length, serverCount].join('/'));
    check('everyone sees the same order, and each sender\'s own messages stay in order', JSON.stringify(oa) === JSON.stringify(oc) && JSON.stringify(oa) === JSON.stringify(ob) && ['fa', 'ch'].every((p) => oa.filter((x) => x.startsWith(p)).join() === Array.from({ length: 20 }, (_, i) => p + '-' + i).join()));

    // ── offline: server stopped, messages written, server restarted ──
    marks.stopAt = errors.length;
    await server.stop();
    await sleep(600);
    await C.evaluate(() => {
      // Make the page think it is 10 minutes earlier while it writes, so the messages carry an old "written" time.
      window.__RealDate = Date;
      const Real = Date;
      window.Date = class extends Real { constructor(...a) { if (a.length) super(...a); else super(Real.now() - 10 * 60 * 1000); } static now() { return Real.now() - 10 * 60 * 1000; } };
    });
    await C.evaluate((id) => { document.querySelector('[data-conversation-id="' + id + '"]').click(); }, grp);
    for (const t of ['offline one', 'offline two', 'offline three']) { await C.evaluate((txt) => { const i = document.getElementById('composer-input'); i.textContent = txt; i.dispatchEvent(new Event('input', { bubbles: true })); document.getElementById('composer-send').click(); }, t); await sleep(60); }
    await C.evaluate(() => { window.Date = window.__RealDate; });
    check('offline: the messages show up in the sender\'s own thread at once, marked as not yet delivered', await C.evaluate(() => ['offline one', 'offline two', 'offline three'].every((t) => document.getElementById('thread-messages').textContent.includes(t)) && ApiAdapter.pendingCount() >= 3));
    const aBefore = await A.evaluate((id) => LimeStore.listMessages(id).length, grp);
    await sleep(1500);
    await server.start();
    await Promise.all([A, B].map((p) => wait(p, (id) => ['offline one', 'offline two', 'offline three'].every((t) => LimeStore.listMessages(id).some((m) => m.content === t)), grp, 30000)));
    await sleep(3500); // late reconnect failures from the stopped window still arrive
    marks.upAt = errors.length;
    const delivered = await A.evaluate((id) => LimeStore.listMessages(id).filter((m) => /^offline /.test(m.content)).map((m) => ({ c: m.content, written: m.client_ts, delivered: m.created_at })), grp);
    check('offline: after the server came back, the three messages were delivered to the others, in the order they were written', delivered.map((d) => d.c).join() === 'offline one,offline two,offline three', delivered.map((d) => d.c).join());
    check('offline: nothing was lost or doubled (exactly 3 new messages)', (await A.evaluate((id) => LimeStore.listMessages(id).length, grp)) === aBefore + 3);
    check('offline: the delivered message shows when it was WRITTEN and when it was delivered (a 10 minute gap)', await A.evaluate(() => { const t = document.getElementById('thread-messages').textContent; return /Sent \d{1,2}:\d{2}\s?(AM|PM)? · delivered/.test(t) || /Sent .*delivered/.test(t); }) || (new Date(delivered[0].delivered) - new Date(delivered[0].written) > 5 * 60 * 1000 && (await B.evaluate(() => /Sent .*delivered/.test(document.getElementById('thread-messages').textContent))) ), JSON.stringify(delivered[0]));
    check('offline: Cy\'s outbox is empty again once everything is confirmed', await (async () => { await wait(C, () => ApiAdapter.pendingCount() === 0, null, 15000); return true; })());

    // ── the demo password file is never served, including over the LAN ──
    const lan = Object.values(os.networkInterfaces()).flat().find((i) => i && i.family === 'IPv4' && !i.internal);
    const urls = ['http://127.0.0.1:' + server.port + '/public/js/demo-config.local.js'].concat(lan ? ['http://' + lan.address + ':' + server.port + '/public/js/demo-config.local.js'] : []);
    check('public/js/demo-config.local.js answers 404 on localhost' + (lan ? ' and on the LAN URL' : ''), (await Promise.all(urls.map((u) => fetch(u).then((r) => r.status)))).every((s) => s === 404), lan ? lan.address : 'no LAN interface');
    check('the sign-in page no longer includes the demo password script', !(await fetch(server.base + 'auth.html').then((r) => r.text())).includes('demo-config.local.js"></script>'));

    // ── reset: everyone goes to sign-in ──
    marks.resetAt = errors.length;
    await A.evaluate(() => { LimeAuth.resetCredentials(); LimeToast.queue({ title: 'Demo data reset', body: 'All accounts and changes were cleared.', tone: 'info' }); LimeStore.reset().then(() => LimeAuth.signOut({ silent: true })); });
    await Promise.all([A, B, C].map((p) => p.waitForFunction(() => /auth\.html|login\.html/.test(location.href), { polling: 50, timeout: 30000 })));
    await Promise.all([A, B, C].map((p) => wait(p, () => /auth\.html/.test(location.href) && /Demo data/.test(document.body.textContent), null, 15000).catch(() => null)));
    const toasts = await Promise.all([A, B, C].map((p) => p.evaluate(() => document.body.textContent)));
    check('after a reset, all three people (Firefox, private Firefox, Chrome) are sent to sign-in', [A, B, C].every((p) => /auth\.html/.test(p.url())));
    check('and the other two are told "Demo data was reset"', /Demo data was reset/.test(toasts[1]) && /Demo data was reset/.test(toasts[2]) && /Demo data reset/.test(toasts[0]));
    check('and nothing of anyone\'s stayed in their browser', await B.evaluate(() => Object.keys(localStorage).every((k) => !k.startsWith('lime-api-cache:') && !k.startsWith('lime-outbox:'))));

    check('zero console or page errors in any of the three browsers (network noise only counted while the server was stopped)', realErrors().length === 0, realErrors().slice(0, 3).join(' | '));
  } finally {
    await Promise.allSettled([ffNormal.close(), ffPrivate.close(), chrome.close()]);
    await server.destroy();
  }
}
