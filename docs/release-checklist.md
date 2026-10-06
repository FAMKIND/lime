# Pre-release checklist

Things that must be done before Lime goes to testers or the App Store. Later briefs append to this list.

- [ ] **Acknowledgements screen.** List third-party notices in the app, including the **SQLCipher Community Edition** notice (Zetetic LLC's BSD-style copyright and disclaimer, which binary distribution must reproduce) and the rest of [`core/THIRD_PARTY.md`](../core/THIRD_PARTY.md).
- [ ] **A lawyer's glance at UniFFI's MPL-2.0 use** (a file-level copyleft build tool and runtime, statically linked; see `core/THIRD_PARTY.md`). Also covers the open MIT-or-AGPL decision ([`architecture.md`](./architecture.md), section 11).
- [ ] **Production email.** A custom SMTP sender with a verified domain (for example Resend) in the production Supabase project; the code email template, the 10-character minimum password and a 30-second (or shorter) email interval set there too; the hourly email limit sized for real use. Staging needs the same before anyone but the team can sign up.
- [ ] **Terms and Privacy.** The welcome screen links `https://famkind.com` as a placeholder for both; point them at the real pages.
- [ ] **The welcome illustration.** A placeholder (the logo) until the artwork exists.
