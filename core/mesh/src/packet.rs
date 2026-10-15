//! The mesh packet: versioned, length-prefixed binary, padded to a bucket so sizes do not leak (LIME-140).
//!
//! ```text
//! version        1 byte   (1)
//! tag           16 bytes  the recipient tag: opaque here (lime_core makes it from the delivery key and the day)
//! hops_left      1 byte
//! expires_at     8 bytes  big-endian Unix seconds
//! header_len     2 bytes  big-endian
//! header         n bytes  the sealed routing header: opaque here (only the server can open it)
//! payload_len    4 bytes  big-endian
//! payload        n bytes  exactly the bytes the server's `send` stores for that recipient device
//! zero padding   to the bucket: 256, 512, 1024, 2048, then multiples of 4096
//! ```
//! The **digest** names a packet (dedupe, summaries): SHA-256 over everything that does not change on the way (the version, tag,
//! `expires_at`, header and payload, each variable field with its length), so it is the same at every hop; `hops_left` and the padding are
//! not in it.

use sha2::{Digest as _, Sha256};

pub type Tag = [u8; 16];
pub type Digest = [u8; 32];
/// The first 8 bytes of a digest: what two phones exchange in summaries (a false "you have it" costs one missed forward, never a loss).
pub type Short = [u8; 8];

pub const VERSION: u8 = 1;
/// Version, tag, hops, expiry, header length, payload length.
pub const OVERHEAD: usize = 1 + 16 + 1 + 8 + 2 + 4;

#[derive(Clone, Debug, PartialEq, Eq)]
pub struct Packet {
    pub tag: Tag,
    /// The sealed routing header (opaque).
    pub header: Vec<u8>,
    /// What the server stores for the recipient device (opaque).
    pub payload: Vec<u8>,
    pub hops_left: u8,
    pub expires_at: u64,
}

#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum PacketError {
    Truncated,
    Version,
    Size,
    NotBucketSized,
    BadPadding,
}

/// The wire size for `content` bytes of packet: the smallest bucket that holds it.
pub fn bucket_size(content: usize) -> usize {
    match content {
        0..=256 => 256,
        257..=512 => 512,
        513..=1024 => 1024,
        1025..=2048 => 2048,
        n => n.div_ceil(4096) * 4096,
    }
}

impl Packet {
    /// The encoded packet, padded to its bucket.
    pub fn encode(&self) -> Vec<u8> {
        let content = OVERHEAD + self.header.len() + self.payload.len();
        let mut out = Vec::with_capacity(bucket_size(content));
        out.push(VERSION);
        out.extend_from_slice(&self.tag);
        out.push(self.hops_left);
        out.extend_from_slice(&self.expires_at.to_be_bytes());
        out.extend_from_slice(&(self.header.len() as u16).to_be_bytes());
        out.extend_from_slice(&self.header);
        out.extend_from_slice(&(self.payload.len() as u32).to_be_bytes());
        out.extend_from_slice(&self.payload);
        out.resize(bucket_size(content), 0);
        out
    }

    /// Reads a packet; the wire size must be a bucket size and the padding all zero (so a packet has exactly one encoding).
    pub fn decode(bytes: &[u8]) -> Result<Packet, PacketError> {
        if bytes.len() < OVERHEAD {
            return Err(PacketError::Truncated);
        }
        if bytes[0] != VERSION {
            return Err(PacketError::Version);
        }
        let mut tag = [0u8; 16];
        tag.copy_from_slice(&bytes[1..17]);
        let hops_left = bytes[17];
        let expires_at = u64::from_be_bytes(bytes[18..26].try_into().unwrap());
        let header_len = u16::from_be_bytes(bytes[26..28].try_into().unwrap()) as usize;
        let header_end = 28 + header_len;
        if bytes.len() < header_end + 4 {
            return Err(PacketError::Truncated);
        }
        let payload_len = u32::from_be_bytes(bytes[header_end..header_end + 4].try_into().unwrap()) as usize;
        let payload_end = header_end + 4 + payload_len;
        if bytes.len() < payload_end {
            return Err(PacketError::Truncated);
        }
        if bytes.len() != bucket_size(payload_end) {
            return Err(PacketError::NotBucketSized);
        }
        if bytes[payload_end..].iter().any(|b| *b != 0) {
            return Err(PacketError::BadPadding);
        }
        Ok(Packet { tag, header: bytes[28..header_end].to_vec(), payload: bytes[header_end + 4..payload_end].to_vec(), hops_left, expires_at })
    }

    /// The packet's name: the same at every hop (see the module notes).
    pub fn digest(&self) -> Digest {
        let mut hasher = Sha256::new();
        hasher.update([VERSION]);
        hasher.update(self.tag);
        hasher.update(self.expires_at.to_be_bytes());
        hasher.update((self.header.len() as u16).to_be_bytes());
        hasher.update(&self.header);
        hasher.update((self.payload.len() as u32).to_be_bytes());
        hasher.update(&self.payload);
        hasher.finalize().into()
    }

    pub fn short(&self) -> Short {
        short(&self.digest())
    }

    /// Bytes on the wire (and in the store).
    pub fn wire_len(&self) -> usize {
        bucket_size(OVERHEAD + self.header.len() + self.payload.len())
    }
}

pub fn short(digest: &Digest) -> Short {
    digest[..8].try_into().unwrap()
}

#[cfg(test)]
mod tests {
    use super::*;

    fn sample() -> Packet {
        Packet { tag: [1; 16], header: b"hdr".to_vec(), payload: b"payload".to_vec(), hops_left: 7, expires_at: 1_800_000_000 }
    }

    #[test]
    fn buckets_are_256_512_1024_2048_then_four_kib_steps() {
        for (content, bucket) in [(0, 256), (256, 256), (257, 512), (512, 512), (513, 1024), (1024, 1024), (1025, 2048), (2048, 2048), (2049, 4096), (4096, 4096), (4097, 8192), (9000, 12288)] {
            assert_eq!(bucket_size(content), bucket, "{content}");
        }
    }

    #[test]
    fn a_packet_round_trips_and_every_size_on_the_wire_is_a_bucket() {
        for payload in [0usize, 1, 100, 223, 224, 225, 600, 2000, 5000, 70_000] {
            let packet = Packet { payload: vec![9; payload], ..sample() };
            let bytes = packet.encode();
            assert_eq!(bytes.len(), bucket_size(OVERHEAD + 3 + payload));
            assert!(bytes.len() == 256 || bytes.len() == 512 || bytes.len() == 1024 || bytes.len() == 2048 || bytes.len() % 4096 == 0);
            assert_eq!(Packet::decode(&bytes).unwrap(), packet);
        }
    }

    #[test]
    fn the_wire_format_is_pinned_so_every_platform_reads_the_same_bytes() {
        // Never change (another platform checks the same vector). The digest was also computed independently with Python's hashlib.
        let bytes = sample().encode();
        assert_eq!(bytes.len(), 256);
        let hex = |b: &[u8]| b.iter().map(|x| format!("{x:02x}")).collect::<String>();
        assert_eq!(hex(&bytes[..42]), "010101010101010101010101010101010107000000006b49d2000003686472000000077061796c6f6164");
        assert!(bytes[42..].iter().all(|b| *b == 0), "zero padding to the bucket");
        assert_eq!(hex(&sample().digest()), "0fe15013e9e4457dea7e9dad3390c873168b2831b87b92586112d032fb9678d6");
    }

    #[test]
    fn the_digest_ignores_hops_and_padding_but_not_the_content() {
        let a = sample();
        let b = Packet { hops_left: 2, ..sample() };
        assert_eq!(a.digest(), b.digest(), "the same packet at another hop");
        assert_ne!(a.digest(), Packet { payload: b"payloae".to_vec(), ..sample() }.digest());
        assert_ne!(a.digest(), Packet { header: b"hdq".to_vec(), ..sample() }.digest());
        assert_ne!(a.digest(), Packet { tag: [2; 16], ..sample() }.digest());
        assert_ne!(a.digest(), Packet { expires_at: 1_800_000_001, ..sample() }.digest());
        // The boundary between the header and the payload matters (each carries its length).
        let c = Packet { header: b"ab".to_vec(), payload: b"c".to_vec(), ..sample() };
        let d = Packet { header: b"a".to_vec(), payload: b"bc".to_vec(), ..sample() };
        assert_ne!(c.digest(), d.digest());
    }

    #[test]
    fn a_packet_that_is_not_exactly_one_encoding_is_refused() {
        let good = sample().encode();
        assert_eq!(Packet::decode(&good[..100]), Err(PacketError::NotBucketSized), "cut short");
        let mut wrong_version = good.clone();
        wrong_version[0] = 2;
        assert_eq!(Packet::decode(&wrong_version), Err(PacketError::Version));
        let mut dirty = good.clone();
        let last = dirty.len() - 1;
        dirty[last] = 1;
        assert_eq!(Packet::decode(&dirty), Err(PacketError::BadPadding));
        let mut long = good.clone();
        long.push(0);
        assert_eq!(Packet::decode(&long), Err(PacketError::NotBucketSized));
        assert_eq!(Packet::decode(&[1u8; 10]), Err(PacketError::Truncated));
    }
}
