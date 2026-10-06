//! A hybrid logical clock: wall-clock milliseconds plus a counter, so ops made in the same
//! millisecond, or by a device whose clock went backwards, still increase. Written as
//! `"<wall ms, 13 digits>.<counter, 4 digits>"`, which sorts as text.

#[derive(Debug, Clone, Copy, PartialEq, Eq, PartialOrd, Ord, Default)]
pub(crate) struct Hlc {
    pub wall: i64,
    pub counter: i64,
}

impl Hlc {
    /// The next value for an op made now.
    pub(crate) fn tick(self, now_ms: i64) -> Hlc {
        if now_ms > self.wall {
            Hlc {
                wall: now_ms,
                counter: 0,
            }
        } else {
            Hlc {
                wall: self.wall,
                counter: self.counter + 1,
            }
        }
    }

    /// Fold in the clock of an op received from another device.
    pub(crate) fn observe(self, remote: Hlc, now_ms: i64) -> Hlc {
        let wall = self.wall.max(remote.wall).max(now_ms);
        let counter = if wall == self.wall && wall == remote.wall {
            self.counter.max(remote.counter) + 1
        } else if wall == self.wall {
            self.counter + 1
        } else if wall == remote.wall {
            remote.counter + 1
        } else {
            0
        };
        Hlc { wall, counter }
    }

    pub(crate) fn render(self) -> String {
        format!("{:013}.{:04}", self.wall, self.counter)
    }

    pub(crate) fn parse(text: &str) -> Option<Hlc> {
        let (wall, counter) = text.split_once('.')?;
        Some(Hlc {
            wall: wall.parse().ok()?,
            counter: counter.parse().ok()?,
        })
    }
}
