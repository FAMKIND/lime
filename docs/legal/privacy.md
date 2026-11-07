# Privacy

> **Draft, pending legal review.**

**lime keeps your messages private. We can't read them. We don't show ads, track you or sell anything.**

*Last updated: 7 November 2026 (draft).*

## The short version

- Your messages, calls, files and group chats are end-to-end encrypted. Only the people in them can read them.
- lime's servers hold the minimum needed to deliver them: your sign-in email, your devices' public keys, and sealed mail waiting for a phone to pick it up.
- lime is for people who teach, 18 or older. It is free, always. Donations and grants pay for it.

## What lime stores, and who can see it

| What | Who can read it |
| --- | --- |
| Messages, photos, files, voice messages, calls, reactions, group chats | Only the people in the chat. Not lime. Not our providers. |
| Members-only band and jam posts | Only the subscribers and members you allow. They are encrypted too. |
| Your sign-in email address | lime's servers and our email provider (below). |
| Your devices' public keys and your username | lime's servers. These are what let phones find each other. |
| Profile items you set to "Everyone on lime" (photo, background, links) | Any signed-in lime user. With "Only my contacts", the server holds only encrypted bytes it cannot read. |
| A band's public page and open posts | Anyone you or your band make them visible to. |
| Sealed mail waiting for a phone | Nobody on the server. It is deleted when the phone collects it, or after 30 days. |
| Reports you send | lime's moderators see exactly what you chose to include (see *Reports*). |
| Network addresses (IP addresses) | Our servers see them while you are connected, as every internet service does. We keep no access logs on the call and invite servers. |

lime has no ads, no analytics, no tracking and no data sales. Nothing about you is used to profile you.

## What each side learns

- **When you send a message:** the server learns that a sealed envelope went to a device, and when. It does not learn what is in it, or who is in the group.
- **When you call:** the call is end-to-end encrypted. The relay server sees network addresses and timing, not the call.
- **When you look at a link preview:** your phone visits the site, not the person you are chatting with. You can turn previews off in Settings, Privacy.
- **When you publish a public post or page:** anyone who can open it can read it, and lime's servers store it.
- **When you report something:** your phone seals the report to lime's moderation key. Moderators read what you chose to include. The person you reported is never told who reported.

## Who helps us run lime

These companies process data for us. None may use it for their own purposes.

| Provider | What for | What it sees |
| --- | --- | --- |
| Supabase | Our database and file storage | Everything in the table above that "lime's servers" can see, plus sealed bytes it cannot open. |
| Resend | Sign-in codes, account emails and the launch list's emails | Your email address and the email it sends (a code, or the link to confirm the launch list). |
| Hetzner | The servers for calls and the invite page | Network addresses while a call is connected. No access logs are kept. |
| Apple | Notifications, later | A device token and a content-free ping. No message content. |

## The launch list

If you ask limemessenger.com to tell you when lime is ready, we keep your email address, the date, and, only if you tap it, which kind of place you teach in (K-12, higher ed, a studio or community, or somewhere else). We use them for one thing: to email you once, when lime is ready. If you asked about Android, we email you once more, when lime is on Android. We don't track you on the website: no cookies, no analytics. We don't sell or share the list, and Resend (above) only sends the emails.

You confirm your address with a link we email you. If you don't, we delete it after 7 days. To leave, use the link on the page after you confirm, the link in any email we send, or write to support@limemessenger.com, and we delete your address at once. After the launch email we delete the list; people who asked about Android stay on a separate list until we send the Android email, then we delete it too.

## Nearby phones (the mesh)

When there is no internet, lime can pass sealed messages phone to phone by Bluetooth. A phone that helps carry a message cannot read it, and it forgets it after 48 hours. Bluetooth announces only that "a phone running lime is nearby". It never includes your name or account. lime does not use your location. You can turn this off in Settings, Privacy.

## Teachers and students

lime is for teachers. Students must not have accounts. Before you post a photo, video or recording publicly, lime asks you to confirm that no student can be identified in it. Please never share students' personal details in public posts.

## How long we keep things

- **Sealed mail:** until the phone collects it, or 30 days.
- **The launch list:** an unconfirmed address, 7 days. A confirmed one, until we send the launch email (an Android sign-up, until the Android email), or until you leave.
- **Files you send:** about an hour after the last recipient fetched it, or 30 days at most.
- **Reports:** 180 days after a moderator has handled them, then deleted. If the law requires us to keep something, for example a report to the National Center for Missing & Exploited Children, we keep only what it requires.
- **Delete for everyone** is best effort. If someone already saw or saved a message, lime cannot take it back.
- **Messages on your phone** stay there until you delete them. Deleting a chat for yourself does not delete the other person's copy.

## Deleting your account

In the app: Settings, Account, Delete Account. We ask for your password and an emailed code, so nobody else can do it for you.

We delete right away: your profile, your public pages and posts, the files we hold for you, your devices and keys, mail waiting for you, your reports, and your sign-in account. Your email address is not kept, and you can sign up again straight away.

We keep: a one-way code that records an account was deleted; your username for 30 days so nobody can impersonate you; and reports other people made about you, for up to 180 days.

Your messages sit on other people's phones, so we cannot delete them there. Your app sends your contacts, group members and subscribers one private note, and their apps quietly remove your picture, details and pages. A phone that never reconnects keeps what it has.

## Your rights

You can ask us what we hold about you, ask us to correct or delete it, or ask for a copy. Email **privacy@limemessenger.com**. Because lime holds so little, the answer is usually short.

## Children

lime is for adults. If you believe a child has an account, write to **abuse@limemessenger.com**.

## Changes and contact

If we change this page we will say so in the app before the change applies. Questions: **privacy@limemessenger.com**.

lime is made by Lime Messenger LLC. [legal line: to be confirmed once the companies exist]

---

## Sources (for the team; remove before publishing)

- Messages, files and groups: `docs/architecture.md`; `docs/api-v2.md` (mailbox, sealed sends, expiry).
- Server-visible items and "everyone" profile items: `docs/api-v2.md`, `docs/release-checklist.md` (LIME-98b).
- Mesh: `docs/dpia-mesh.md` (48 hours, rotating ids, no location).
- Reports and 180 days: `docs/moderation.md`.
- Deletion: `docs/privacy-deletion-draft.md`, `docs/api-v2.md` section 15.
- Resend as the email processor: PLOT.md 1e484.
- Link previews, delete-for-everyone, file lifetime, status: `docs/release-checklist.md` (LIME-105, 106, 107, 108).
- Student attestation: `docs/jam.md` (the student-privacy check).

## Questions for the lawyer

1. Is a US-only privacy statement enough for TestFlight, or do we need GDPR/UK wording (a legal basis, a representative)?
2. Are Supabase, Resend and Hetzner "processors" and do we need data processing agreements in place before launch?
3. Retention of reports (180 days) and the NCMEC reporting process (18 U.S.C. § 2258A).
4. Database backup retention after account deletion.
5. Children: lime is 18+ but no age gate is built yet (the sign-up confirmation is missing). What wording do we need until it is?
6. The legal line: which company is the "controller" until the nonprofit exists?
7. GIFs are sent byte for byte; embedded comment blocks are not stripped (PLOT.md 1e533). Is a sentence needed?
8. Orphaned profile blobs of a reset account stay on the server (PLOT.md 1e496); is that acceptable until the cleanup exists?
