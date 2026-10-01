// CSS guard: (1) static: no stray `*/` outside a comment (a `*/` written inside comment text closes it early and
// silently drops the rest of the file); (2) in the real browser: each stylesheet parsed at least a minimum number of rules.
import fs from 'node:fs';
import path from 'node:path';
import { REPO_ROOT, launch, browserAvailable } from '../lib/harness.mjs';

// Minimums sit a little under today's counts, so a truncated stylesheet fails but normal edits don't.
const MIN_RULES = { 'lime.css': 660, 'gradients.css': 22, 'auth.css': 35 };

function strayCloser(css) {
  // Walk the file: outside a comment, `*/` is a stray closer (so an earlier comment ended too soon).
  let i = 0, line = 1;
  while (i < css.length) {
    if (css[i] === '\n') line++;
    if (css.startsWith('/*', i)) {
      const end = css.indexOf('*/', i + 2);
      if (end === -1) return { line, why: 'unterminated comment' };
      line += (css.slice(i, end).match(/\n/g) || []).length;
      i = end + 2;
      continue;
    }
    if (css.startsWith('*/', i)) return { line, why: 'stray */ outside a comment' };
    i++;
  }
  return null;
}

export async function run({ base, check }) {
  check('self-test: the detector flags a comment closed early', !!strayCloser('a{} /* see --x-*/ more text */ b{}') && !strayCloser('/* fine */ a{}'));
  const dir = path.join(REPO_ROOT, 'public', 'css');
  for (const file of fs.readdirSync(dir).filter((f) => f.endsWith('.css'))) {
    const bad = strayCloser(fs.readFileSync(path.join(dir, file), 'utf8'));
    check(`${file}: no stray */ outside a comment`, !bad, bad ? `line ${bad.line}: ${bad.why}` : '');
  }

  const name = browserAvailable('firefox') ? 'firefox' : 'chrome';
  const browser = await launch(name);
  try {
    for (const pageName of ['index.html', 'auth.html']) {
      const page = await browser.newPage();
      await page.evaluateOnNewDocument(() => sessionStorage.setItem('lime-demo-session', JSON.stringify({ userId: 'teacher-002', email: 'shem.robinson@ps113.edu' })));
      await page.goto(base + pageName, { waitUntil: 'load' });
      const counts = await page.evaluate(() => [...document.styleSheets].filter((s) => s.href).map((s) => {
        let n = -1; try { n = s.cssRules.length; } catch (e) { /* cross-origin (fonts) */ }
        return { file: s.href.split('/').pop().split('?')[0], n };
      }));
      for (const { file, n } of counts) {
        if (!(file in MIN_RULES)) continue;
        check(`${pageName}: ${file} parsed ${n} rules in ${name} (min ${MIN_RULES[file]})`, n >= MIN_RULES[file], n);
      }
      await page.close();
    }
  } finally {
    await browser.close();
  }
}
