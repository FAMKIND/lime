// LIME-292c, 292d: packages the icons as appiconsets (Any, Dark, Tinted): the seven alternates AppIcon-<Name>, the primary AppIcon (lime), and the 384 px previews
// the picker shows.
//   node design/app-icons/package.mjs     (after render.mjs)
import fs from 'node:fs';
import path from 'node:path';
import { execFileSync } from 'node:child_process';
import { root, here } from './build.mjs';

const res = path.join(root, 'ios', 'Lime', 'Resources');
const alternates = { dark: 'Dark', sticker: 'Sticker', notebook: 'Notebook', chalkboard: 'Chalkboard', pixel: 'Pixel', rainbow: 'Rainbow', apple: 'Apple' };
const appiconset = (dir, key) => {
  fs.rmSync(dir, { recursive: true, force: true });
  fs.mkdirSync(dir, { recursive: true });
  fs.copyFileSync(path.join(here, 'png', `${key}.png`), path.join(dir, 'icon-1024.png'));
  fs.copyFileSync(path.join(here, 'png', `${key}-dark.png`), path.join(dir, 'icon-1024-dark.png'));
  fs.copyFileSync(path.join(here, 'png', `${key}-tinted.png`), path.join(dir, 'icon-1024-tinted.png'));
  fs.writeFileSync(path.join(dir, 'Contents.json'), JSON.stringify({
    images: [
      { filename: 'icon-1024.png', idiom: 'universal', platform: 'ios', size: '1024x1024' },
      { appearances: [{ appearance: 'luminosity', value: 'dark' }], filename: 'icon-1024-dark.png', idiom: 'universal', platform: 'ios', size: '1024x1024' },
      { appearances: [{ appearance: 'luminosity', value: 'tinted' }], filename: 'icon-1024-tinted.png', idiom: 'universal', platform: 'ios', size: '1024x1024' },
    ],
    info: { author: 'xcode', version: 1 },
  }, null, 2) + '\n');
};

// 292d: the alternates are plain appiconsets (Any, Dark, Tinted 1024 PNGs): the Icon Composer bundles of 292c added 14 MB to the app thinned for an iPhone 13 mini
// (32.5 -> 46.9 MB compressed), over the 8 MB allowed. iOS makes Clear from the flat art. The layer PNGs stay in <name>/layers/ if the bundles are wanted again.
fs.rmSync(path.join(res, 'Icons'), { recursive: true, force: true });
for (const [key, title] of Object.entries(alternates)) appiconset(path.join(res, 'Assets.xcassets', `AppIcon-${title}.appiconset`), key);

// the primary icon (lime): the shipped art as before, plus Dark and Tinted
appiconset(path.join(res, 'Assets.xcassets', 'AppIcon.appiconset'), 'lime');

// the previews in the picker (384 px of the flattened default art)
const previews = { lime: 'Lime', ...Object.fromEntries(Object.entries(alternates).map(([k, t]) => [k, t])) };
for (const [key, title] of Object.entries(previews)) {
  const set = path.join(res, 'Assets.xcassets', `IconPreview-${title}.imageset`);
  fs.rmSync(set, { recursive: true, force: true });
  fs.mkdirSync(set, { recursive: true });
  const target = path.join(set, 'preview.png');
  execFileSync('sips', ['-Z', '384', path.join(here, 'png', `${key}.png`), '--out', target], { stdio: 'ignore' });
  fs.writeFileSync(path.join(set, 'Contents.json'), JSON.stringify({ images: [{ filename: 'preview.png', idiom: 'universal' }], info: { author: 'xcode', version: 1 } }, null, 2) + '\n');
}
console.log('packaged');
