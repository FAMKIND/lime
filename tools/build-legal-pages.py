#!/usr/bin/env python3
"""Builds invite-site/{privacy,terms,guidelines,safety,security}/index.html and
invite-site/.well-known/security.txt from docs/legal/*.md (LIME-282a).
Handles the small Markdown subset the drafts use; drops everything from "## Sources" on, every [bracketed note] that is not a link,
and every block between <!-- public:hide --> and <!-- /public:hide --> (LIME-290: the drafts keep their notes for the team, the public pages never show them).
Fails if a built page still has a bracketed note, "LAWYER", "placeholder" or "Lime Messenger".
LEGAL_SRC and LEGAL_OUT override the folders (to test the check on a dummy page)."""
import html, os, re, shutil, sys
from pathlib import Path

root = Path(__file__).resolve().parent.parent
src, out = Path(os.environ.get("LEGAL_SRC", root / "docs/legal")), Path(os.environ.get("LEGAL_OUT", root / "invite-site"))
pages = {"privacy": "Privacy", "terms": "Terms of use", "guidelines": "Community guidelines", "safety": "Safety and abuse", "security": "Security"}

def inline(t):
    t = html.escape(t, quote=False)
    t = re.sub(r"\*\*(.+?)\*\*", r"<strong>\1</strong>", t)
    t = re.sub(r"\*(.+?)\*", r"<em>\1</em>", t)
    t = re.sub(r"\[([^\]]+)\]\((/[^)]*|https?://[^)]*)\)", r'<a href="\2">\1</a>', t)
    return re.sub(r"(?<![\w>])([\w.]+@limemessenger\.com)", r'<a href="mailto:\1">\1</a>', t)

NOTE = re.compile(r"[ \t]*\[[^\]]*\](?!\()")   # a [ ... ] that is not a Markdown link (not followed by "(")
HIDDEN = re.compile(r"<!-- public:hide -->.*?<!-- /public:hide -->\n?", re.S)
FORBIDDEN = re.compile(r"LAWYER|placeholder|Lime Messenger", re.I)

def body(md):
    md = md.split("\n---\n\n## Sources")[0]
    md = HIDDEN.sub("", md)
    md = NOTE.sub("", md)
    o, para, lst, tbl, quote = [], [], False, [], False
    def flush():
        nonlocal para
        if para: o.append("<p>" + inline(" ".join(para)) + "</p>"); para = []
    def endlist():
        nonlocal lst
        if lst: o.append("</ul>"); lst = False
    def endtbl():
        nonlocal tbl
        if tbl:
            rows = [[c.strip() for c in r.strip("|").split("|")] for r in tbl if not re.match(r"^\|[\s:|-]+\|$", r)]
            h = "".join(f"<th>{inline(c)}</th>" for c in rows[0])
            b = "".join("<tr>" + "".join(f"<td>{inline(c)}</td>" for c in r) + "</tr>" for r in rows[1:])
            o.append(f'<div class="t"><table><thead><tr>{h}</tr></thead><tbody>{b}</tbody></table></div>'); tbl = []
    for line in md.splitlines()[1:]:
        if line.startswith("|"): flush(); endlist(); tbl.append(line); continue
        endtbl()
        if line.startswith("> "): flush(); o.append(f'<p class="draft">{inline(line[2:].replace("**", ""))}</p>'); continue
        if line.startswith("## "): flush(); endlist(); o.append(f"<h2>{inline(line[3:])}</h2>"); continue
        if line.startswith("- "):
            flush()
            if not lst: o.append("<ul>"); lst = True
            o.append(f"<li>{inline(line[2:])}</li>"); continue
        if re.match(r"^\d+\. ", line): flush(); endlist(); o.append(f"<p>{inline(line)}</p>"); continue
        if not line.strip(): flush(); endlist(); continue
        para.append(line)
    flush(); endlist(); endtbl()
    return "\n".join(o)

PAGE = """<!doctype html>
<html lang="en">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<link rel="icon" type="image/svg+xml" href="/brand/lime-Logomark.svg">
<link rel="apple-touch-icon" href="/apple-touch-icon.png">
<link rel="icon" type="image/png" sizes="32x32" href="/favicon-32.png">
<meta property="og:type" content="website">
<meta property="og:site_name" content="lime">
<meta property="og:title" content="{title} · lime">
<meta property="og:description" content="A private space where teachers connect. Free, encrypted, no ads.">
<meta property="og:url" content="https://limemessenger.com/{slug}/">
<meta property="og:image" content="https://limemessenger.com/og.png">
<meta property="og:image:width" content="1200">
<meta property="og:image:height" content="630">
<meta property="og:image:alt" content="lime: Where teachers connect.">
<meta name="twitter:card" content="summary_large_image">
<meta name="twitter:title" content="{title} · lime">
<meta name="twitter:description" content="A private space where teachers connect. Free, encrypted, no ads.">
<meta name="twitter:image" content="https://limemessenger.com/og.png">
<title>{title} · lime</title>
<style>
  :root {{ --bg: #fbfaf5; --text: #1d2a14; --muted: #5d6b50; --line: #dfe3d3; }}
  @media (prefers-color-scheme: dark) {{ :root {{ --bg: #11160d; --text: #f1f5e8; --muted: #a8b59a; --line: #2c3523; }} }}
  body {{ margin: 0; padding: 24px 16px 64px; background: var(--bg); color: var(--text); font: 17px/1.55 -apple-system, BlinkMacSystemFont, "SF Pro Text", "Segoe UI", Roboto, sans-serif; }}
  main {{ max-width: 680px; margin: 0 auto; }} h1 {{ font-size: 30px; margin: 8px 0 12px; }} h2 {{ font-size: 21px; margin: 32px 0 8px; }}
  p, li {{ color: var(--text); }} .draft {{ color: var(--muted); font-size: 14px; }} a {{ color: inherit; }}
  .t {{ overflow-x: auto; }} table {{ border-collapse: collapse; width: 100%; font-size: 15px; }} th, td {{ text-align: left; vertical-align: top; padding: 8px 10px; border-bottom: 1px solid var(--line); }}
  nav {{ font-size: 15px; color: var(--muted); }} nav a {{ margin-right: 14px; }}
</style>
</head>
<body>
<main>
<nav><a href="/" aria-label="lime"><img src="/brand/lime-Logomark.svg" width="32" height="32" alt="" style="vertical-align:middle;border-radius:8px"></a><a href="/privacy">Privacy</a><a href="/terms">Terms</a><a href="/guidelines">Guidelines</a><a href="/safety">Safety</a><a href="/security">Security</a></nav>
<h1>{title}</h1>
{body}
</main>
</body>
</html>
"""

for slug, title in pages.items():
    d = out / slug
    d.mkdir(exist_ok=True)
    (d / "index.html").write_text(PAGE.format(title=title, slug=slug, body=body((src / f"{slug}.md").read_text())))
bad = []
for slug in pages:
    text = (out / slug / "index.html").read_text()
    for m in re.finditer(r"\[[^\]]*\](?!\()|LAWYER|placeholder|Lime Messenger", text, re.I):
        bad.append(f"{slug}: {m.group(0)!r}")
if bad:
    sys.exit("A public page still has a team note or a company name (LIME-290):\n  " + "\n  ".join(bad))
(out / ".well-known").mkdir(exist_ok=True)
shutil.copy(src / "security.txt", out / ".well-known/security.txt")
print("built", ", ".join(pages), "+ .well-known/security.txt")
