# lime app icons (LIME-292c)

Eight icons, all built around the lime slice (its shape and place never change; only its treatment does): **lime** (the shipped icon), **Dark**, **Sticker**,
**Notebook**, **Chalkboard**, **Pixel**, **Rainbow**, **Apple**.

- `source/slice-paths.svg`: the slice's paths (from the shipped icon); `source/lime-shipped.svg`: the shipped icon as it was.
- `build.mjs`, `icons2.mjs`: each icon as code (SVG layers: `background`, `mark`; Dark has its own background). `render.mjs`: writes `<name>/{background,mark}.svg`, the
  flattened `<name>/<name>{,-dark,-tinted}.svg`, `png/<name>{,-dark,-tinted}.png` (1024) and `<name>/layers/*.png` (for Icon Composer). `sheet.mjs`: a contact sheet.
  `package.mjs`: the appiconsets (`AppIcon-<Name>` with Any, Dark and Tinted 1024 PNGs, and the primary `AppIcon`) and the 384 px picker previews. (292c used Icon Composer
  bundles from `<name>/layers/*.png`; they added 14 MB to the thinned app, so 292d went back to appiconsets. The layers are still rendered if the bundles are wanted again.)
- `node design/app-icons/render.mjs && node design/app-icons/package.mjs` (headless Chrome from `tests/node_modules/puppeteer-core`; nothing to install).
- A redrawn icon: put its flat 1024 PNGs in `png/<name>.png`, `png/<name>-dark.png`, `png/<name>-tinted.png` (tinted: a greyscale mark on transparent) and run `package.mjs`.
