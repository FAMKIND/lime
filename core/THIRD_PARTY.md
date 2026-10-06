# Third-party licences (LimeCore)

Checked 2026-10-06 against the crates in `Cargo.lock` (`cargo metadata`). Lime's own code is MIT.

## Direct dependencies

| Crate | Version | Licence | Use |
|---|---|---|---|
| [vodozemac](https://crates.io/crates/vodozemac) | 0.11.1 | Apache-2.0 | Olm and Megolm encryption (Matrix's reference implementation; audited by Least Authority in 2022). Linked into the app. |
| [uniffi](https://crates.io/crates/uniffi) | 0.32.2 | MPL-2.0 | Generates the Swift bindings (build tool, `cargo run --features cli --bin uniffi-bindgen`) and provides the small runtime (`uniffi_core` and the macros) linked into the library. |

## UniFFI and MIT (MPL-2.0)

MPL-2.0 is a file-level ("weak") copyleft licence, not a project-wide one. Using UniFFI unmodified as a build tool and runtime, and linking it statically into an app, does not put Lime's own MIT-licensed code under MPL. The obligations are:

- if we **modify an MPL-licensed file** from UniFFI, we publish those modifications under MPL-2.0;
- we keep UniFFI's licence notices, which this file and `Cargo.lock` record.

The generated Swift (`ios/Lime/Core/Generated/`) contains UniFFI template code, so those files stay under UniFFI's terms. They are gitignored and rebuilt from source, and nothing in them is edited by hand. This is a reading of the licence, not legal advice; it is worth a lawyer's glance before the first public release.

## Transitive crates (127 packages in the resolved graph, including build-time and other-platform crates)

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
