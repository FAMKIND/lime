#!/usr/bin/env python3
"""Makes the link-preview images (LIME-291) from the brand SVGs: site/landing/og.png (1200x630), apple-touch-icon.png (180x180),
favicon-32.png and favicon.ico (32 + 48). Run it again after a brand change; deploy.sh copies them to the site root.
usage: python3 tools/make-link-previews.py     (needs `pip install playwright` + `playwright install chromium`; Chromium draws the SVGs and the Figtree font)"""
import struct, tempfile
from pathlib import Path
from playwright.sync_api import sync_playwright

root = Path(__file__).resolve().parent.parent
out = root / "site/landing"
brand = (root / "design/brand").as_uri()
font = (root / "site/com/fonts/figtree-var.woff2").as_uri()
PALE, INK = "#e4f9be", "#131b17"

CARD = f"""<style>
@font-face {{ font-family: Figtree; src: url({font}); font-weight: 300 900; }}
html, body {{ margin: 0; width: 1200px; height: 630px; background: {PALE}; }}
/* the important part sits inside the centre 1000x520: some apps crop the card */
.row {{ position: absolute; left: 100px; top: 55px; width: 1000px; height: 520px; display: flex; align-items: center; gap: 70px; }}
.row img {{ height: 400px; }}
.row p {{ margin: 0; font: 800 92px/1.04 Figtree, sans-serif; letter-spacing: -2px; color: {INK}; }}
</style><div class="row"><img src="{brand}/lime-Logo.svg" alt=""><p>Where<br>teachers<br>connect.</p></div>"""
ICON = f"""<style>html, body {{ margin: 0; width: 180px; height: 180px; background: {PALE}; display: grid; place-items: center; }} img {{ width: 112px; height: 112px; }}</style>
<img src="{brand}/lime-Logomark.svg" alt="">"""
FAVICON = f"""<style>html, body {{ margin: 0; width: SIZEpx; height: SIZEpx; background: transparent; display: grid; place-items: center; }} img {{ width: SIZEpx; height: SIZEpx; }}</style>
<img src="{brand}/lime-Logomark.svg" alt="">"""

def shoot(page, html, w, h, path, transparent=False):
    f = Path(tempfile.mkdtemp()) / "p.html"; f.write_text(html)
    page.set_viewport_size({"width": w, "height": h}); page.goto(f.as_uri()); page.wait_for_timeout(400)
    page.screenshot(path=str(path), omit_background=transparent)

with sync_playwright() as p:
    b = p.chromium.launch(); page = b.new_page()
    shoot(page, CARD, 1200, 630, out / "og.png")
    shoot(page, ICON, 180, 180, out / "apple-touch-icon.png")
    for s in (32, 48): shoot(page, FAVICON.replace("SIZE", str(s)), s, s, Path(tempfile.gettempdir()) / f"favicon-{s}.png", transparent=True)
    b.close()
tmp = Path(tempfile.gettempdir())
(out / "favicon-32.png").write_bytes((tmp / "favicon-32.png").read_bytes())
# favicon.ico: PNG-compressed 32 and 48 entries
images = [(32, (tmp / "favicon-32.png").read_bytes()), (48, (tmp / "favicon-48.png").read_bytes())]
ico = struct.pack("<HHH", 0, 1, len(images)); offset = 6 + 16 * len(images)
for size, data in images:
    ico += struct.pack("<BBBBHHII", size, size, 0, 0, 1, 32, len(data), offset); offset += len(data)
(out / "favicon.ico").write_bytes(ico + b"".join(d for _, d in images))
for n in ("og.png", "apple-touch-icon.png", "favicon-32.png", "favicon.ico"): print(n, (out / n).stat().st_size, "bytes")
