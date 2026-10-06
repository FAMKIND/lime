# Third-party licences (LimeCore)

Checked 2026-10-06 (updated for LIME-90 and LIME-93) against the crates in `Cargo.lock` (`cargo metadata`). Lime's own code is MIT.

## Direct dependencies

| Crate | Version | Licence | Use |
|---|---|---|---|
| [vodozemac](https://crates.io/crates/vodozemac) | 0.11.1 | Apache-2.0 | Olm and Megolm encryption (Matrix's reference implementation; audited by Least Authority in 2022). Linked into the app. |
| [rusqlite](https://crates.io/crates/rusqlite) | 0.40.2 | MIT | The Rust SQLite API for the local store. |
| [libsqlite3-sys](https://crates.io/crates/libsqlite3-sys) | 0.38.2 | MIT | Compiles the bundled **SQLCipher** (feature `bundled-sqlcipher`); see below. |
| [uuid](https://crates.io/crates/uuid) | 1.27.0 | Apache-2.0 or MIT | UUIDv7 message and op ids, and random device ids (`v7` and `v4`). |
| [serde](https://crates.io/crates/serde), [serde_json](https://crates.io/crates/serde_json) | 1.0.229, 1.0.151 | MIT or Apache-2.0 | The op and envelope JSON (LIME-93). |
| [hkdf](https://crates.io/crates/hkdf), [sha2](https://crates.io/crates/sha2) | 0.13.0, 0.11.0 | MIT or Apache-2.0 | Derives the pickle key from the store key (HKDF-SHA256). The same versions vodozemac already uses. |
| [ureq](https://crates.io/crates/ureq) | 2.12.1 | MIT or Apache-2.0 | **Tests only** (a dev-dependency): the HTTP client of the integration tests. With its TLS stack (`rustls`, `ring` Apache-2.0 AND ISC, `rustls-webpki` ISC, `webpki-roots` CDLA-Permissive-2.0) it is not linked into the app. |
| [tempfile](https://crates.io/crates/tempfile) | 3.27.0 | MIT or Apache-2.0 | Tests only (a dev-dependency); not linked into the app. |
| [uniffi](https://crates.io/crates/uniffi) | 0.32.2 | MPL-2.0 | Generates the Swift bindings (build tool, `cargo run --features cli --bin uniffi-bindgen`) and provides the small runtime (`uniffi_core` and the macros) linked into the library. |

## SQLCipher and SQLite (the encrypted local store)

`libsqlite3-sys` vendors the **SQLCipher Community Edition** source (an amalgamation of SQLite 3.51.3 plus Zetetic's encryption layer). SQLCipher Community is licensed **BSD-3-Clause-style** (Zetetic LLC; the licence text ships in `libsqlite3-sys/sqlcipher/LICENSE`); the SQLite code inside it is in the public domain. Both are permissive and compatible with an MIT app. Binary redistribution must reproduce Zetetic's copyright notice and disclaimer, so the app's acknowledgements screen will need to list it (a later brief).

**Crypto provider: Apple's CommonCrypto, not OpenSSL.** On an Apple target `libsqlite3-sys` compiles SQLCipher with `-DSQLCIPHER_CRYPTO_CC` and links the system `Security` and `CoreFoundation` frameworks, so no OpenSSL is vendored or linked (`OPENSSL_DIR` must stay unset, or the build would pick OpenSSL instead). The app target links `Security.framework`. The size cost is in the LIME-90 entry in `TEND.md`.

## UniFFI and MIT (MPL-2.0)

MPL-2.0 is a file-level ("weak") copyleft licence, not a project-wide one. Using UniFFI unmodified as a build tool and runtime, and linking it statically into an app, does not put Lime's own MIT-licensed code under MPL. The obligations are:

- if we **modify an MPL-licensed file** from UniFFI, we publish those modifications under MPL-2.0;
- we keep UniFFI's licence notices, which this file and `Cargo.lock` record.

The generated Swift (`ios/Lime/Core/Generated/`) contains UniFFI template code, so those files stay under UniFFI's terms. They are gitignored and rebuilt from source, and nothing in them is edited by hand. This is a reading of the licence, not legal advice; it is worth a lawyer's glance before the first public release.

## Transitive crates (202 packages in the resolved graph, including build-time, test-only and other-platform crates)

`cargo metadata` shows only permissive licences, plus UniFFI's own MPL-2.0 crates (`uniffi`, `uniffi_bindgen`, `uniffi_core`, `uniffi_internal_macros`, `uniffi_macros`, `uniffi_meta`, `uniffi_pipeline`, `uniffi_udl`). No GPL or AGPL licence applies to anything linked.

| Licence | Packages |
|---|---|
| MIT or Apache-2.0 (dual), and Apache-2.0 | most of them |
| MIT | 12 |
| BSD-3-Clause | 4: `curve25519-dalek`, `ed25519-dalek`, `x25519-dalek`, `subtle` (the cryptographic primitives vodozemac uses) |
| Unlicense or MIT | 1 |
| MIT or Apache-2.0 or BSD-1-Clause | 1: `fiat-crypto` |
| (MIT or Apache-2.0) and Unicode-3.0 | 1: `unicode-ident` |
| MIT or Apache-2.0 or **LGPL-2.1-or-later** | 1: `r-efi` (UEFI bindings; not compiled for iOS, and the licence is a choice, so MIT or Apache-2.0 applies) |

Re-check this list when dependencies change (`cargo metadata --format-version 1`).
