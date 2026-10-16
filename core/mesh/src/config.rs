//! Every parameter of the mesh, in one place (DESIGN-06/13). The defaults are the decided numbers; tests turn single knobs.

#[derive(Clone, Debug, PartialEq, Eq)]
pub struct MeshConfig {
    /// Hops a packet may travel from its author (the TTL).
    pub ttl: u8,
    /// A node with at least `many_links` links caps the TTL it hands out at `ttl_cap_many_links` (a crowd needs fewer hops).
    pub many_links: usize,
    pub ttl_cap_many_links: u8,
    /// The seen-set: digests remembered this many seconds, at most this many (LRU).
    pub seen_window_secs: u64,
    pub seen_capacity: usize,
    /// Spray and wait: copies a packet starts with (8: the simulator showed 4 reaches only two relays on a chain), the most it may ever hold,
    /// and (implicit) half is handed to each courier met.
    pub copies_initial: u8,
    pub copies_cap: u8,
    /// A packet lives at most this long from when its author made it.
    pub max_lifetime_secs: u64,
    /// Budgets: the whole store, packets per recipient tag, and the share of the store strangers' mail may use (percent).
    pub store_cap_bytes: usize,
    pub per_tag_cap: usize,
    pub stranger_share_percent: usize,
    /// The largest packet accepted (a bucketed wire size).
    pub max_packet_bytes: usize,
    /// Relay jitter hint, milliseconds (the platform delays, the core never sleeps).
    pub jitter_min_ms: u32,
    pub jitter_max_ms: u32,
    /// Per link: packets accepted per minute (a flooding neighbour is ignored beyond this).
    pub link_packets_per_minute: u32,
    /// At most this many digests in the summary a node sends when a link comes up, and asks for per meeting.
    pub summary_max: usize,
    pub want_max: usize,
    /// Seeds the jitter (deterministic simulations; a phone seeds it from something unpredictable).
    pub seed: u64,
}

impl Default for MeshConfig {
    fn default() -> Self {
        MeshConfig {
            ttl: 7,
            many_links: 6,
            ttl_cap_many_links: 5,
            seen_window_secs: 300,
            seen_capacity: 1000,
            copies_initial: 8,
            copies_cap: 8,
            max_lifetime_secs: 48 * 3600,
            store_cap_bytes: 5 * 1024 * 1024,
            per_tag_cap: 100,
            stranger_share_percent: 40,
            max_packet_bytes: 70 * 1024,
            jitter_min_ms: 10,
            jitter_max_ms: 220,
            link_packets_per_minute: 120,
            summary_max: 2000,
            want_max: 200,
            seed: 1,
        }
    }
}
