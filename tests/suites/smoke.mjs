// The real index.html and auth.html load in jsdom, with their real scripts, and report zero errors.
import { JSDOM, VirtualConsole } from 'jsdom';
import { sleep } from '../lib/harness.mjs';

const IGNORE = [/demo-config\.local/, /Could not load (link|img|script).*(404|demo-config)/i, /Not implemented/, /404/];

async function load(url, signedIn) {
  const errors = [];
  const vc = new VirtualConsole();
  vc.on('jsdomError', (e) => errors.push(String(e.message)));
  vc.on('error', (e) => errors.push(String(e)));
  const dom = await JSDOM.fromURL(url, {
    runScripts: 'dangerously', resources: 'usable', pretendToBeVisual: true, virtualConsole: vc,
    beforeParse(w) {
      if (signedIn) w.sessionStorage.setItem('lime-demo-session', JSON.stringify({ userId: 'teacher-002', email: 'shem.robinson@ps113.edu' }));
      w.matchMedia = w.matchMedia || (() => ({ matches: false, addEventListener() {}, removeEventListener() {}, addListener() {} }));
      w.ResizeObserver = w.ResizeObserver || class { observe() {} unobserve() {} disconnect() {} };
      w.IntersectionObserver = w.IntersectionObserver || class { observe() {} unobserve() {} disconnect() {} };
    },
  });
  await sleep(2000);
  return { dom, errors: errors.filter((e) => !IGNORE.some((re) => re.test(e))) };
}

export async function run({ base, check }) {
  const app = await load(base + 'index.html', true);
  const w = app.dom.window;
  check('index.html: zero script errors', app.errors.length === 0, app.errors.join(' | '));
  check('index.html: store loaded as the signed-in teacher', w.LimeStore && w.LimeStore.getCurrentUserId() === 'teacher-002');
  check('index.html: conversation list rendered', w.document.querySelectorAll('.lime-contact').length > 0, w.document.querySelectorAll('.lime-contact').length + ' rows');
  check('index.html: thread rendered', w.document.querySelectorAll('#thread-messages .lime-message').length > 0);
  w.close();

  const auth = await load(base + 'auth.html', false);
  check('auth.html: zero script errors', auth.errors.length === 0, auth.errors.join(' | '));
  check('auth.html: email form present', !!auth.dom.window.document.getElementById('auth-email-form'));
  auth.dom.window.close();
}
