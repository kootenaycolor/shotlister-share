//! The record-facts door, run on a real film — and writing nothing.
//!
//! `cargo run --example mirror_on_real_films -- "<film>.shotlist/changes" '<json>'`
//!
//! `<json>` is what the hub hands the door: `{"link": "<page id>", "facts":
//! {…}}`. Prints the door's answer, then what it would have kept and whether
//! the film shows the facts afterwards. The film's own files are only read.

use std::env;
use std::fs;

use shotlister_engine::DeviceId;
use shotlister_mcpweb::{mirror_into_film, Bucket};

fn main() {
    let folder = env::args().nth(1).expect("give me a folder of .log files");
    let asked = env::args().nth(2).expect("give me the json the hub sends");
    shotlister_engine::id::set_now_millis(1_760_000_000_000);
    shotlister_engine::id::set_seed(0x5eed_1234_abcd_ef01);

    let mut names: Vec<_> = fs::read_dir(&folder)
        .expect("that folder could not be read")
        .filter_map(|e| e.ok())
        .map(|e| e.path())
        .filter(|p| p.extension().map(|e| e == "log").unwrap_or(false))
        .collect();
    names.sort();
    let mut bucket = Bucket::new("deadbeefcafe", "checking", false, DeviceId(0x00b0_0b1e_5000_0002));
    for name in &names {
        bucket.take(&fs::read_to_string(name).expect("a log could not be read"));
    }
    bucket.settle();
    let said = match mirror_into_film(&mut bucket, &asked) {
        Ok(text) => text,
        Err(why) => format!("{{\"error\":{:?}}}", why),
    };
    println!("{said}");
    println!("pending\t{}", bucket.pending().lines().count());
    // Ask again: a film that took them must now take nothing.
    let again = match mirror_into_film(&mut bucket, &asked) {
        Ok(text) => text,
        Err(why) => format!("{{\"error\":{:?}}}", why),
    };
    println!("again\t{again}");
}
