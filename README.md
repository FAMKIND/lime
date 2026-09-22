# Lime

Secure, open-source communication for teachers.

## Preview

```bash
git clone https://github.com/FAMKIND/lime.git
cd lime
git submodule update --init --recursive
open public/index.html
```

## Constraints

1. Use seed (`vendor/seed/`), `seed-*` classes, token grammar
2. `data-theme` on every `<html>`
3. Prototype: HTML/CSS/vanilla JS only
4. Local-first future: design for P2P/offline

## Decisions (2026-09-21)

- Prototype: mocked auth, 1:1 DM, group chat, community
- Stack: HTML/CSS/vanilla JS
- Consume seed: submodule

## Open

- [ ] Icon gaps in dew (send, mic, paperclip)
