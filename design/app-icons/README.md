# lime app icons (LIME-292c)

Eight icons, all built around the lime slice (its shape and place never change; only its treatment does): **lime** (the shipped icon), **Dark**, **Sticker**,
**Notebook**, **Chalkboard**, **Pixel**, **Rainbow**, **Apple**.

- `source/slice-paths.svg`: the slice's paths (from the shipped icon); `source/lime-shipped.svg`: the shipped icon as it was.
- `build.mjs`, `icons2.mjs`: each icon as code (SVG layers: `background`, `mark`; Dark has its own background). `render.mjs`: writes `<name>/{background,mark}.svg`, the
  flattened `<name>/<name>{,-dark,-tinted}.svg`, `png/<name>{,-dark,-tinted}.png` (1024) and `<name>/layers/*.png` (for Icon Composer). `sheet.mjs`: a contact sheet.
  `package.mjs`: the `.icon` bundles (`ios/Lime/Resources/Icons/AppIcon-<Name>.icon`), the lime icon's Dark and Tinted looks, and the 384 px picker previews.
- `node design/app-icons/render.mjs && node design/app-icons/package.mjs` (headless Chrome from `tests/node_modules/puppeteer-core`; nothing to install).
- A redrawn icon dropped in as `layers/background.png` + `layers/mark.png` (and `background-dark.png`) of the same name goes through `package.mjs` the same way.
