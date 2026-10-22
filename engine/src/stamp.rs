//! Hybrid logical clock.
//!
//! Every write carries a stamp. Stamps totally order writes across devices even
//! when the wall clocks disagree, which is what makes merges deterministic: two
//! devices that receive the same changes in different orders end up identical.

use std::collections::BTreeMap;

use crate::id::now_millis;

#[derive(Clone, Copy, PartialEq, Eq, PartialOrd, Ord, Hash, Debug)]
pub struct DeviceId(pub u64);

/// Ordering is (millis, counter, device). The device tiebreak is arbitrary but
/// consistent, which is all that's needed to make last-writer-wins total.
#[derive(Clone, Copy, PartialEq, Eq, PartialOrd, Ord, Hash, Debug)]
pub struct Stamp {
    pub millis: u64,
    pub counter: u32,
    pub device: DeviceId,
}

/// How far a device had caught up when it wrote something.
///
/// Last-writer-wins settles every disagreement, but it cannot on its own tell
/// the difference between the two cases that matter to a person: *I changed this
/// after seeing your value* — ordinary work — and *we both changed it, neither
/// knowing about the other* — which is the one worth mentioning. The watermark
/// is what separates them. A device stamps each write with the high-water mark
/// of everything it had seen at that moment, so a later reader can ask whether
/// the winner had actually seen what it beat.
///
/// It has to be kept per device rather than as a single number. Two devices
/// writing in the same millisecond produce stamps whose ordering is a tiebreak,
/// not knowledge — so "I had reached this point in the total order" would let a
/// device claim to have seen a write it had never heard of, purely because its
/// own counter happened to be higher. Per device, the claim is exact: a device
/// either had heard from that one or it had not.
#[derive(Clone, Copy, PartialEq, Eq, PartialOrd, Ord, Debug)]
pub struct Seen {
    pub device: DeviceId,
    pub millis: u64,
    pub counter: u32,
}

#[derive(Clone, PartialEq, Eq, Debug, Default)]
pub enum Watermark {
    /// Written by a build from before any of this was recorded. It makes no
    /// claim in either direction, and nothing is inferred on its behalf.
    #[default]
    Unknown,
    /// What had been heard from every *other* device. The writing device is
    /// left out on purpose: it has obviously seen its own earlier writes, and
    /// leaving it in would mean a new watermark on every single keystroke.
    Heard(Vec<Seen>),
}

impl Watermark {
    pub fn is_known(&self) -> bool {
        matches!(self, Watermark::Heard(_))
    }

    /// Whether a device at this watermark had already seen `stamp`, given that
    /// the change carrying the watermark was written by `writer`.
    pub fn covers(&self, stamp: &Stamp, writer: DeviceId) -> bool {
        // Nobody is out of touch with themselves.
        if stamp.device == writer {
            return true;
        }
        match self {
            Watermark::Unknown => false,
            Watermark::Heard(heard) => heard
                .iter()
                .find(|seen| seen.device == stamp.device)
                .map(|seen| (seen.millis, seen.counter) >= (stamp.millis, stamp.counter))
                .unwrap_or(false),
        }
    }

    pub fn heard(&self) -> &[Seen] {
        match self {
            Watermark::Unknown => &[],
            Watermark::Heard(heard) => heard,
        }
    }
}

pub struct Clock {
    device: DeviceId,
    last_millis: u64,
    counter: u32,
    /// The furthest point heard from each other device.
    heard: BTreeMap<DeviceId, (u64, u32)>,
}

impl Clock {
    pub fn new(device: DeviceId) -> Clock {
        Clock {
            device,
            last_millis: 0,
            counter: 0,
            heard: BTreeMap::new(),
        }
    }

    pub fn device(&self) -> DeviceId {
        self.device
    }

    /// What this device has heard from the others. Stamped onto each write, so
    /// a later reader can tell an overrule from a coincidence.
    pub fn watermark(&self) -> Watermark {
        Watermark::Heard(
            self.heard
                .iter()
                .map(|(device, (millis, counter))| Seen {
                    device: *device,
                    millis: *millis,
                    counter: *counter,
                })
                .collect(),
        )
    }

    /// Issue the next stamp. Strictly increasing on this device even if the
    /// system clock jumps backwards.
    pub fn tick(&mut self) -> Stamp {
        let wall = now_millis();
        if wall > self.last_millis {
            self.last_millis = wall;
            self.counter = 0;
        } else {
            self.counter = self.counter.saturating_add(1);
        }
        Stamp {
            millis: self.last_millis,
            counter: self.counter,
            device: self.device,
        }
    }

    /// Absorb a stamp seen from another device, so our next write sorts after
    /// anything we have already observed.
    pub fn observe(&mut self, other: &Stamp) {
        if other.device != self.device {
            let entry = self.heard.entry(other.device).or_insert((0, 0));
            if (other.millis, other.counter) > *entry {
                *entry = (other.millis, other.counter);
            }
        }
        if other.millis > self.last_millis {
            self.last_millis = other.millis;
            self.counter = other.counter;
        } else if other.millis == self.last_millis && other.counter > self.counter {
            self.counter = other.counter;
        }
    }
}
