# Security

> **Draft, pending legal review.**

**Found a security problem in lime? Email security@limemessenger.com. We'll answer and we'll never take legal action against good-faith research.**

*Last updated: 1 November 2026 (draft).*

## How to report

Email **security@limemessenger.com**. Tell us what you found, how to reproduce it, and what you think the impact is. Please don't include other people's personal data.

We will reply within 3 working days, keep you updated, and credit you if you wish.

## In scope

- The lime app (iOS), its encryption, and its handling of keys.
- lime's server functions and storage.
- limemessenger.com.

## Out of scope

- Denial-of-service and volume testing.
- Social engineering of lime's people or users.
- Physical attacks.
- Issues in other companies' services (Supabase, Resend, Hetzner), unless lime configures them badly.

## Good-faith research

If you act in good faith, stay inside this scope, don't read or change other people's data beyond what's needed to show the problem, and give us a reasonable time to fix it before you publish, we will not take legal action against you.

## Reporting machine-readably

See [/.well-known/security.txt](/.well-known/security.txt).

---

## Sources (remove before publishing)

- RFC 9116 (security.txt); `docs/security-review-2026-10.md`; `docs/audit-scope.md`.

## Questions for the lawyer

1. Is the safe-harbour sentence acceptable?
2. A bug bounty: not offered; is "we credit you" enough?
