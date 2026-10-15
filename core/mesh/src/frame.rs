//! What two phones say to each other when they meet (LIME-140). The platform fragments frames to the link's size; the core sees whole ones.
//!
//! ```text
//! Hello  (1)  u16 n, n * 8-byte short digests (what I hold and have seen), u8 m, m * 16-byte tags (mail I am the recipient of)
//! Want   (2)  u16 n, n * 8-byte short digests (send me these)
//! Packet (3)  u8 copies handed over, u32 length, the encoded packet
//! Ack    (4)  8-byte short digest (I have it: you may count it as handed over)
//! ```
//! The tags in a Hello are what lets a node holding the last copy of a packet (spray-and-wait's wait phase) hand it straight to its
//! recipient when they meet. They are the recipient's day-scoped pseudonyms, shown only to a phone it actually meets.

use crate::packet::{Short, Tag};

#[derive(Clone, Debug, PartialEq, Eq)]
pub enum Frame {
    Hello { summary: Vec<Short>, tags: Vec<Tag> },
    Want { digests: Vec<Short> },
    Packet { copies: u8, bytes: Vec<u8> },
    Ack { digest: Short },
}

impl Frame {
    pub fn encode(&self) -> Vec<u8> {
        let mut out = Vec::new();
        match self {
            Frame::Hello { summary, tags } => {
                out.push(1);
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
            1 => {
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
                (at == rest.len()).then_some(Frame::Hello { summary, tags })
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
            Frame::Hello { summary: vec![[1; 8], [2; 8]], tags: vec![[3; 16]] },
            Frame::Hello { summary: vec![], tags: vec![] },
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
        assert_eq!(Frame::decode(&[9, 1, 2, 3]), None);
    }
}
