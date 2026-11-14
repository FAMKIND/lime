// LIME-292c: packages the layer PNGs as Icon Composer bundles (ios/Lime/Resources/Icons/AppIcon-<Name>.icon) for the seven alternate icons, the lime icon's
// Dark and Tinted looks into the primary AppIcon set, and the 384 px previews the picker shows.
//   node design/app-icons/package.mjs     (after render.mjs)
import fs from 'node:fs';
import path from 'node:path';
import { execFileSync } from 'node:child_process';
import { root, here } from './build.mjs';

const res = path.join(root, 'ios', 'Lime', 'Resources');
const alternates = { dark: 'Dark', sticker: 'Sticker', notebook: 'Notebook', chalkboard: 'Chalkboard', pixel: 'Pixel', rainbow: 'Rainbow', apple: 'Apple' };
const flat = { specular: false, shadow: { kind: 'none', opacity: 0 } };   // the art carries its own light and shadow; iOS adds the glass edge itself

for (const [key, title] of Object.entries(alternates)) {
  const dir = path.join(res, 'Icons', `AppIcon-${title}.icon`);
  fs.rmSync(dir, { recursive: true, force: true });
  fs.mkdirSync(path.join(dir, 'Assets'), { recursive: true });
  const layers = path.join(here, key, 'layers');
  const hasDark = fs.existsSync(path.join(here, key, 'background-dark.svg'));
  fs.copyFileSync(path.join(layers, 'background.png'), path.join(dir, 'Assets', 'background.png'));
  fs.copyFileSync(path.join(layers, 'mark.png'), path.join(dir, 'Assets', 'mark.png'));
  const background = { 'image-name': 'background.png', name: 'background', glass: false };
  if (hasDark) {
    fs.copyFileSync(path.join(layers, 'background-dark.png'), path.join(dir, 'Assets', 'background-dark.png'));
    background['image-name-specializations'] = [{ value: 'background.png' }, { appearance: 'dark', value: 'background-dark.png' }];
  }
  // groups run front to back: the mark in front, the background behind it
  const json = { groups: [{ ...flat, layers: [{ 'image-name': 'mark.png', name: 'mark', glass: false }] }, { ...flat, layers: [background] }], 'supported-platforms': { squares: 'shared' } };
  fs.writeFileSync(path.join(dir, 'icon.json'), JSON.stringify(json, null, 2) + '\n');
}

// the primary icon (lime): the shipped art as before, plus Dark and Tinted
const primary = path.join(res, 'Assets.xcassets', 'AppIcon.appiconset');
fs.copyFileSync(path.join(here, 'png', 'lime-dark.png'), path.join(primary, 'icon-1024-dark.png'));
fs.copyFileSync(path.join(here, 'png', 'lime-tinted.png'), path.join(primary, 'icon-1024-tinted.png'));
fs.writeFileSync(path.join(primary, 'Contents.json'), JSON.stringify({
  images: [
    { filename: 'icon-1024.png', idiom: 'universal', platform: 'ios', size: '1024x1024' },
    { appearances: [{ appearance: 'luminosity', value: 'dark' }], filename: 'icon-1024-dark.png', idiom: 'universal', platform: 'ios', size: '1024x1024' },
    { appearances: [{ appearance: 'luminosity', value: 'tinted' }], filename: 'icon-1024-tinted.png', idiom: 'universal', platform: 'ios', size: '1024x1024' },
  ],
  info: { author: 'xcode', version: 1 },
}, null, 2) + '\n');

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
