// LIME-292c: a contact sheet: rows Default, Dark, Tinted; four columns; the name under each icon (the Signal-style grid).
//   node design/app-icons/sheet.mjs <out.png> [names...]
import fs from 'node:fs';
import path from 'node:path';
import { root, here } from './build.mjs';
const { launch } = await import(path.join(root, 'tests', 'lib', 'harness.mjs'));
const [outFile, ...pick] = process.argv.slice(2);
const names = pick.length ? pick : ['lime', 'dark', 'sticker', 'notebook', 'chalkboard', 'pixel', 'rainbow', 'apple'];
const title = { lime: 'lime', dark: 'Dark', sticker: 'Sticker', notebook: 'Notebook', chalkboard: 'Chalkboard', pixel: 'Pixel', rainbow: 'Rainbow', apple: 'Apple' };
const data = (n, v) => { const f = path.join(here, 'png', `${n}${v}.png`); return fs.existsSync(f) ? 'data:image/png;base64,' + fs.readFileSync(f).toString('base64') : ''; };
const row = (label, suffix, bg) => `<h3>${label}</h3><div class="grid" style="background:${bg}">${names.map((n) => `<div class="cell"><img src="${data(n, suffix)}"><span>${title[n]}</span></div>`).join('')}</div>`;
const html = `<html><body style="margin:0;font-family:-apple-system,Helvetica;background:#f0eee6;padding:24px;width:1136px">
<style>.grid{display:grid;grid-template-columns:repeat(4,256px);gap:20px 24px;padding:18px;border-radius:24px}.cell{text-align:center}.cell img{width:256px;height:256px;border-radius:57px;display:block}.cell span{font-size:20px;color:#4a4540;display:block;margin-top:8px}h3{margin:14px 0 8px;color:#131b17}</style>
<h3>At 60 pt (the Home Screen size, 1x)</h3><div class="grid" style="background:#7d8a96;grid-template-columns:repeat(8,60px);gap:18px;padding:18px">${names.map((n) => `<img src="${data(n, '')}" style="width:60px;height:60px;border-radius:13.4px">`).join('')}</div>${row('Default', '', '#fff')}${row('Dark', '-dark', '#1c1f1d')}${row('Tinted', '-tinted', '#5a6b8c')}</body></html>`;
const browser = await launch('chrome');
const page = await browser.newPage();
await page.setViewport({ width: 1184, height: 900, deviceScaleFactor: 1 });
await page.setContent(html);
const h = await page.evaluate(() => document.body.scrollHeight);
await page.setViewport({ width: 1184, height: h, deviceScaleFactor: 1 });
await page.screenshot({ path: outFile, fullPage: true });
await browser.close();
