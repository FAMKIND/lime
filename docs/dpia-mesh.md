# Data protection input: the offline mesh and emergency mode (LIME-144, 2026-10-16)

An input to the data protection impact assessment, not the assessment itself. What lime processes when phones pass sealed messages to each other, the risks that creates, and what limits them. Facts are as built and proven on devices (`docs/architecture.md` §7).

## What is processed

| Data | Where | Who can read it |
|---|---|---|
| The message (or emergency status) | sealed (end-to-end encrypted) before it leaves the sender's phone | only the recipient's devices |
| The packet's routing header (recipient device, a signed proof) | sealed to the server's mesh public key | only `mesh-drop` on the server |
| A recipient tag (16 bytes, new every UTC day, per device) | in clear on the packet | a phone that already holds that person's delivery key (an accepted contact) can recognise its own contact's packets; nobody else |
| Packet size | in clear, padded to 256, 512, 1024, 2048 bytes, then 4 KiB steps | anyone who sees the packet |
| A random link id | advertised to a connecting phone, new every launch and every 15 minutes | a phone that connected |
| The Bluetooth service UUID | in the advertisement | anyone nearby: it says "a phone running lime is here" |
| What a phone carries for others | an encrypted local store, at most 48 hours | nobody (it is sealed; the carrier cannot read it) |
| Upload logs on the server | function logs: a reason code, no ids, no keys, no tokens | the operators |

## Uploading a carried packet (LIME-157): what each party learns

`mesh-drop` needs no session. **The relay** (the phone that uploads) learns nothing: the header is sealed. **The server** learns that a packet for device D arrived at time t from a network address; it does **not** learn which account carried it (the request carries no token, and a token sent anyway is never read). Only a keyed hash of the address is rate-limited, for a day; nothing identifying is logged. The sender's signed proof, not the relay's account, authorises the store.

## Copies for offline neighbours (LIME-156): what each party learns

When a phone with internet sends a message, and a linked neighbour has said (the online bit of LIME-155) that it is offline, the sender also hands that neighbour a copy of the sealed packet over Bluetooth, valid 6 hours. Online neighbours are never given copies, so they do not upload duplicates; the sender never uploads its own copy. **Relays and bystanders** see the same sealed packets as any mesh message (a rotating tag, padded sizes). **One new observable: a phone sends more packets when offline phones are near.** **The server** learns nothing new: copies are not uploaded by the sender, and an offline carrier's later upload looks like any relay upload (a phone remembers for 48 hours which packets it uploaded and does not take or upload them twice). Nothing on the air marks a packet as a copy.

## Relay download (LIME-155)

An offline phone can ask a nearby online lime phone to fetch its sealed mail. The neighbour sees an opaque request and an opaque, padded reply (not whose mail, not how many items beyond a 4 KiB size bucket) and cannot read either. The server sees that a device's mail was fetched at a time from an address, as when the device fetches for itself, and **not which account relayed** (the request needs no session; the device's own signature authorises it). The relay's network address is the honest remaining limit: only a keyed hash of it is rate-limited, for a day. The request's single-use nonce is kept until it expires (at most 10 minutes) and then forgotten.

## The proximity risk

Advertising the service UUID tells anyone with a Bluetooth scanner that a lime phone is nearby. That can reveal that someone uses lime (a teacher in a place where that matters) and, over time, patterns of presence. It does not reveal who, nor what is sent.

## Mitigations

- **Rotating ids:** the link id changes every launch and every 15 minutes (and not while a link is live), so a phone cannot be followed by it for long.
- **No name, account or device id in the advertisement.** The service UUID is the only fixed value.
- **Padding:** packet sizes are bucketed so a message's length is not readable.
- **Tags:** daily, per recipient device, derived from a key only contacts hold; a stranger cannot link two packets for the same person across days or learn the recipient.
- **Sealed header:** a carrier cannot read where a packet goes; it cannot redirect or alter it (the signature binds the device and the ciphertext).
- **No location:** lime never uses GPS; the emergency "Where" is free text typed by the person.
- **48 hours:** a packet expires 48 hours after it was made; a refused upload is dropped after three tries.
- **Off switches:** "Help pass on nearby messages" (on by default, one tap to turn off) and Nearby mode (off by default, turns itself off after 2 hours).
- **An explainer** before iOS asks for Bluetooth, in plain words.

## Retention

- On a carrier's phone: until delivered, uploaded or 48 hours, whichever is first.
- Incoming items a phone cannot read (waiting for a session, undecryptable, or invalid) are **kept at most 30 days on the phone**, then deleted (LIME-159); nothing is sent anywhere when that happens.
- On the server: a mailbox item until the recipient acknowledges it or it expires (see `api-v2.md`); the mesh adds no new retention, and the upload logs hold reason codes only.

## Open points for the assessment

- Whether the proximity signal (the service UUID) is acceptable for every audience, or Nearby mode should ask again each time.
- Retention of function logs.
- The emergency status carries a count of students and a free-text place: free text could hold personal data; it is limited to 60 and 200 characters and goes only to the group the sender chose.
