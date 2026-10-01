// node run.mjs [suite ...]   (default: all). Exit code 1 if anything fails.
import { startServer, recorder } from './lib/harness.mjs';

const ALL = ['smoke', 'css', 'auth', 'sync', 'toasts'];
const wanted = process.argv.slice(2).length ? process.argv.slice(2) : ALL;
const unknown = wanted.filter((s) => !ALL.includes(s));
if (unknown.length) { console.error('Unknown suite(s): ' + unknown.join(', ') + '. Available: ' + ALL.join(', ')); process.exit(2); }

const server = await startServer();
let failed = 0;
const summary = [];
try {
  for (const name of wanted) {
    const rec = recorder();
    const t0 = Date.now();
    console.log(`\n== ${name}`);
    try {
      const mod = await import(`./suites/${name}.mjs`);
      await mod.run({ base: server.base, ...rec });
    } catch (e) {
      rec.check('suite ran without crashing', false, e.stack || e);
    }
    for (const r of rec.results) console.log(`${r.pass ? 'PASS' : 'FAIL'}  ${r.name}${r.detail ? '  (' + r.detail + ')' : ''}`);
    const bad = rec.results.filter((r) => !r.pass).length;
    failed += bad;
    summary.push({ name, pass: rec.results.length - bad, fail: bad, secs: ((Date.now() - t0) / 1000).toFixed(1) });
  }
} finally {
  server.stop();
}
console.log('\n== summary');
for (const s of summary) console.log(`${s.fail ? 'FAIL' : 'ok  '}  ${s.name.padEnd(7)} ${s.pass} passed, ${s.fail} failed, ${s.secs}s`);
process.exit(failed ? 1 : 0);
