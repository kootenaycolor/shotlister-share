//! Identifiers.
//!
//! Ids are 128-bit and roughly time-ordered, so a debug dump of the log reads in
//! creation order without needing a separate timestamp. No external crates: the
//! layout is millis | process seed | counter.
//!
//! **The clock is the one thing this crate cannot get for itself everywhere.**
//! A Mac and a phone have `SystemTime`; a browser does not — asking for it there
//! does not fail politely, it panics. So the wall clock and the process seed can
//! both be *given* by the shell, and are only fetched from the system when they
//! have not been. Nothing outside a browser needs to set either one.

use std::fmt;
use std::sync::atomic::{AtomicU64, Ordering};
#[cfg(not(target_arch = "wasm32"))]
use std::time::{SystemTime, UNIX_EPOCH};

#[derive(Clone, Copy, PartialEq, Eq, Hash, PartialOrd, Ord)]
pub struct Id(pub u128);

const MASK_48: u128 = (1 << 48) - 1;
const MASK_32: u128 = (1 << 32) - 1;

static COUNTER: AtomicU64 = AtomicU64::new(0);
static SEED: AtomicU64 = AtomicU64::new(0);
/// Nought means "nobody has told us"; the system clock answers instead.
static GIVEN_MILLIS: AtomicU64 = AtomicU64::new(0);

/// Tell the engine what time it is. For shells with no system clock of their
/// own — the browser — called before each piece of work. Everywhere else this
/// is never called and the system clock answers.
pub fn set_now_millis(millis: u64) {
    GIVEN_MILLIS.store(millis, Ordering::Relaxed);
}

/// Seed the id generator by hand. A browser must, because the jitter used
/// below does not exist there: without this every session would start from the
/// same seed and two of them could mint the same id.
pub fn set_seed(seed: u64) {
    SEED.store(seed | 1, Ordering::Relaxed);
}

#[cfg(not(target_arch = "wasm32"))]
fn system_millis() -> u64 {
    SystemTime::now()
        .duration_since(UNIX_EPOCH)
        .map(|d| d.as_millis() as u64)
        .unwrap_or(0)
}

#[cfg(target_arch = "wasm32")]
fn system_millis() -> u64 {
    0
}

#[cfg(not(target_arch = "wasm32"))]
fn system_jitter() -> u64 {
    SystemTime::now()
        .duration_since(UNIX_EPOCH)
        .map(|d| d.subsec_nanos() as u64)
        .unwrap_or(0)
}

#[cfg(target_arch = "wasm32")]
fn system_jitter() -> u64 {
    0
}

fn process_seed() -> u64 {
    let existing = SEED.load(Ordering::Relaxed);
    if existing != 0 {
        return existing;
    }
    // Nanosecond jitter is enough to separate two processes started in the same
    // millisecond. Ids only need to be unique, not unguessable.
    let nanos = system_jitter();
    let addr = &COUNTER as *const AtomicU64 as u64;
    let seed = (nanos ^ addr.rotate_left(17)) | 1;
    SEED.store(seed, Ordering::Relaxed);
    seed
}

pub fn now_millis() -> u64 {
    let given = GIVEN_MILLIS.load(Ordering::Relaxed);
    if given != 0 {
        return given;
    }
    system_millis()
}

impl Id {
    pub fn new() -> Id {
        let millis = now_millis() as u128;
        let seed = process_seed() as u128;
        let count = COUNTER.fetch_add(1, Ordering::Relaxed) as u128;
        Id(((millis & MASK_48) << 80) | ((seed & MASK_48) << 32) | (count & MASK_32))
    }

    pub fn from_hex(s: &str) -> Option<Id> {
        u128::from_str_radix(s, 16).ok().map(Id)
    }

    pub fn to_hex(self) -> String {
        format!("{:032x}", self.0)
    }
}

impl Default for Id {
    fn default() -> Self {
        Id::new()
    }
}

impl fmt::Display for Id {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        write!(f, "{}", self.to_hex())
    }
}

impl fmt::Debug for Id {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        // Short form keeps test failures readable.
        write!(f, "Id({}…)", &self.to_hex()[..8])
    }
}
