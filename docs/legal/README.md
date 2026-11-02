# Legal drafts (LIME-282a)

**Draft, pending legal review.** Not legal advice. Plain-language drafts grounded in how lime works; each page ends with sources and a list of questions for a lawyer.

| File | Becomes | Notes |
| --- | --- | --- |
| `privacy.md` | `/privacy` | |
| `terms.md` | `/terms` | legal line is a placeholder |
| `guidelines.md` | `/guidelines` | |
| `safety.md` | `/safety` | |
| `security.md`, `security.txt` | `/security`, `/.well-known/security.txt` | |
| `app-store-privacy.md` | not published | paste into App Store Connect |

The static pages live in `invite-site/` (generated, **not deployed** until LIME-282b). Rebuild them with `python3 tools/build-legal-pages.py` after editing the Markdown here. The generator drops everything from the `## Sources` heading on, so sources and lawyer questions never reach the public page.
