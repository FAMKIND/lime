#!/usr/bin/env python3
"""Screenshots a local site preview (desktop + phone, light + dark) for the user's look.
usage: python3 tools/shoot-site.py http://localhost:8284/ docs/qa-shots/284a   (needs `pip install playwright` + `playwright install chromium`)"""
import sys
from playwright.sync_api import sync_playwright
url, out = sys.argv[1], sys.argv[2]
with sync_playwright() as p:
    b = p.chromium.launch()
    for name, size in (("desktop", {"width": 1280, "height": 900}), ("phone", {"width": 390, "height": 844})):
        for scheme in ("light", "dark"):
            ctx = b.new_context(viewport=size, color_scheme=scheme, device_scale_factor=1 if name == "desktop" else 2)
            pg = ctx.new_page()
            pg.goto(url, wait_until="networkidle")
            h = pg.evaluate("document.documentElement.scrollHeight")
            for y in range(0, h, 500):   # scroll through so lazy images load
                pg.evaluate(f"window.scrollTo(0,{y})"); pg.wait_for_timeout(60)
            pg.evaluate("window.scrollTo(0,0)"); pg.wait_for_timeout(500)
            over = pg.evaluate("document.documentElement.scrollWidth - window.innerWidth")
            print(name, scheme, "horizontal overflow px:", over)
            pg.screenshot(path=f"{out}/{name}-{scheme}.png", full_page=True)
            pg.wait_for_timeout(1500); pg.screenshot(path=f"{out}/{name}-{scheme}-top.png")   # the first screen, video playing
            if name == "desktop" and scheme == "light":
                print("first-load bytes (excluding lazy images):")
            ctx.close()
    b.close()
