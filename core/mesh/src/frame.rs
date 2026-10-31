//! What two phones say to each other when they meet (LIME-140). The platform fragments frames to the link's size; the core sees whole ones.
//!
//! ```text
//! Hello  (9)  16-byte link nonce, u16 n, n * 8-byte short digests (what I hold and have seen), u8 m, m * 16-byte BLINDED tags (mail I am the recipient of)
//! Want   (2)  u16 n, n * 8-byte short digests (send me these)
//! Packet (3)  u8 copies handed over, u32 length, the encoded packet
//! Ack    (4)  8-byte short digest (I have it: you may count it as handed over)
//! ```
//! The tags in a Hello are what lets a node holding the last copy of a packet (spray-and-wait's wait phase) hand it straight to its
//! recipient when they meet. They are the recipient's day-scoped pseudonyms, **blinded** (LIME-167, F-04): each is `H(tag, nonce)` for a nonce that is
//! fresh in every Hello, so a stranger on a link sees values that never repeat, and only a phone holding a packet for that tag can recognise it.
//! Hello v1 (frame kind 1: the raw tags) is refused: a phone on the old protocol cannot mesh with this one.

use crate::packet::{blind, Nonce, Short, Tag};

#[derive(Clone, Debug, PartialEq, Eq)]
pub enum Frame {
    /// `tags` are blinded with `nonce` (see [`Frame::hello`]).
    Hello { summary: Vec<Short>, nonce: Nonce, tags: Vec<Tag> },
    Want { digests: Vec<Short> },
    Packet { copies: u8, bytes: Vec<u8> },
    Ack { digest: Short },
}

/// The frame kind of the first Hello, with raw tags: no longer understood.
pub const LEGACY_HELLO: u8 = 1;
/// Hello v2. Kinds 5 to 8 are the relay download's (the core's own frames), so the next free kind is 9.
const HELLO: u8 = 9;

impl Frame {
    /// A Hello for this phone's own (raw) `tags`, blinded with `nonce`.
    pub fn hello(summary: Vec<Short>, nonce: Nonce, raw_tags: &[Tag]) -> Frame {
        Frame::Hello { summary, nonce, tags: raw_tags.iter().take(255).map(|t| blind(t, &nonce)).collect() }
    }

    pub fn encode(&self) -> Vec<u8> {
        let mut out = Vec::new();
        match self {
            Frame::Hello { summary, nonce, tags } => {
                out.push(HELLO);
                out.extend_from_slice(nonce);
                out.extend_from_slice(&(summary.len() as u16).to_be_bytes());
                for s in summary {
                    out.extend_from_slice(s);
                }
                out.push(tags.len().min(255) as u8);
                for t in tags.iter().take(255) {
                    out.extend_from_slice(t);
                }
            }
            Frame::Want { digests } => {
                out.push(2);
                out.extend_from_slice(&(digests.len() as u16).to_be_bytes());
                for s in digests {
                    out.extend_from_slice(s);
                }
            }
            Frame::Packet { copies, bytes } => {
                out.push(3);
                out.push(*copies);
                out.extend_from_slice(&(bytes.len() as u32).to_be_bytes());
                out.extend_from_slice(bytes);
            }
            Frame::Ack { digest } => {
                out.push(4);
                out.extend_from_slice(digest);
            }
        }
        out
    }

    /// `None` for anything that is not exactly one well-formed frame.
    pub fn decode(bytes: &[u8]) -> Option<Frame> {
        let (kind, rest) = bytes.split_first()?;
        match kind {
            &HELLO => {
                let nonce: Nonce = rest.get(..16)?.try_into().ok()?;
                let rest = &rest[16..];
                let n = u16::from_be_bytes(rest.get(..2)?.try_into().ok()?) as usize;
                let mut at = 2;
                let mut summary = Vec::with_capacity(n);
                for _ in 0..n {
                    summary.push(rest.get(at..at + 8)?.try_into().ok()?);
                    at += 8;
                }
                let m = *rest.get(at)? as usize;
                at += 1;
                let mut tags = Vec::with_capacity(m);
                for _ in 0..m {
                    tags.push(rest.get(at..at + 16)?.try_into().ok()?);
                    at += 16;
                }
                (at == rest.len()).then_some(Frame::Hello { summary, nonce, tags })
            }
            2 => {
                let n = u16::from_be_bytes(rest.get(..2)?.try_into().ok()?) as usize;
                let mut at = 2;
                let mut digests = Vec::with_capacity(n);
                for _ in 0..n {
                    digests.push(rest.get(at..at + 8)?.try_into().ok()?);
                    at += 8;
                }
                (at == rest.len()).then_some(Frame::Want { digests })
            }
            3 => {
                let copies = *rest.first()?;
                let len = u32::from_be_bytes(rest.get(1..5)?.try_into().ok()?) as usize;
                let body = rest.get(5..)?;
                (body.len() == len).then(|| Frame::Packet { copies, bytes: body.to_vec() })
            }
            4 => (rest.len() == 8).then(|| Frame::Ack { digest: rest.try_into().ok().unwrap() }),
            _ => None,
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn every_frame_round_trips_and_garbage_is_refused() {
        let frames = [
            Frame::Hello { summary: vec![[1; 8], [2; 8]], nonce: [6; 16], tags: vec![[3; 16]] },
            Frame::Hello { summary: vec![], nonce: [0; 16], tags: vec![] },
            Frame::Want { digests: vec![[4; 8]] },
            Frame::Packet { copies: 2, bytes: vec![7; 300] },
            Frame::Ack { digest: [5; 8] },
        ];
        for frame in frames {
            assert_eq!(Frame::decode(&frame.encode()).as_ref(), Some(&frame));
            let mut longer = frame.encode();
            longer.push(0);
            assert_eq!(Frame::decode(&longer), None, "trailing bytes: {frame:?}");
            let shorter = &frame.encode()[..frame.encode().len() - 1];
            assert_eq!(Frame::decode(shorter), None, "cut short: {frame:?}");
        }
        assert_eq!(Frame::decode(&[]), None);
        assert_eq!(Frame::decode(&[0, 1, 2, 3]), None);
    }

    #[test]
    fn a_v1_hello_with_raw_tags_is_refused() {
        // kind 1, u16 n = 0, u8 m = 1, one 16-byte raw tag: what the first protocol sent.
        let mut v1 = vec![LEGACY_HELLO, 0, 0, 1];
        v1.extend_from_slice(&[3; 16]);
        assert_eq!(Frame::decode(&v1), None);
    }

    #[test]
    fn blinding_depends_on_the_nonce_and_a_holder_can_recompute_it() {
        let tag = [3u8; 16];
        let a = Frame::hello(vec![], [1; 16], &[tag]);
        let b = Frame::hello(vec![], [2; 16], &[tag]);
        let (Frame::Hello { tags: ta, nonce: na, .. }, Frame::Hello { tags: tb, .. }) = (&a, &b) else { panic!() };
        assert_ne!(ta, tb, "the same tag looks different in every Hello");
        assert_ne!(ta[0], tag, "and never as itself");
        assert_eq!(ta[0], blind(&tag, na), "a holder of the tag gets the same value");
        assert_ne!(ta[0], blind(&[4u8; 16], na), "another tag does not match");
    }
}
