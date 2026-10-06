# Pre-release checklist

Things that must be done before Lime goes to testers or the App Store. Later briefs append to this list.

- [ ] **Acknowledgements screen.** List third-party notices in the app, including the **SQLCipher Community Edition** notice (Zetetic LLC's BSD-style copyright and disclaimer, which binary distribution must reproduce) and the rest of [`core/THIRD_PARTY.md`](../core/THIRD_PARTY.md).
- [ ] **A lawyer's glance at UniFFI's MPL-2.0 use** (a file-level copyleft build tool and runtime, statically linked; see `core/THIRD_PARTY.md`). Also covers the open MIT-or-AGPL decision ([`architecture.md`](./architecture.md), section 11).
