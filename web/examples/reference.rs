//! The same reading, run on the Mac.
//!
//! `cargo run --example reference -- <folder of .log files>`
//!
//! This exists to be compared against a browser. It calls exactly the same
//! `Film` the browser calls — the only difference is that here the logs are
//! handed over by the file system and there they arrive over the network. If
//! the two fingerprints match, the engine read the film the same way in both
//! places, which is the whole question.

use std::env;
use std::fs;

use shotlister_web::Film;

fn main() {
    let folder = match env::args().nth(1) {
        Some(path) => path,
        None => {
            eprintln!("give me a folder of .log files");
            std::process::exit(2);
        }
    };

    let mut names: Vec<_> = fs::read_dir(&folder)
        .expect("that folder could not be read")
        .filter_map(|entry| entry.ok())
        .map(|entry| entry.path())
        .filter(|path| path.extension().map(|e| e == "log").unwrap_or(false))
        .collect();
    // Same order both sides, so a difference means a real difference rather
    // than the file system and the network disagreeing about alphabetical.
    names.sort();

    let mut film = Film::new();
    for name in &names {
        let text = fs::read_to_string(name).expect("a log could not be read");
        film.take(&text);
    }
    film.settle();

    println!("logs\t{}", names.len());
    println!("summary\t{}", film.summary());
    println!("fingerprint-bytes\t{}", film.fingerprint().len());
    println!("fingerprint-sha\t{}", sha_hex(film.fingerprint().as_bytes()));
    // Nothing asked for: the whole film, which is what the Mac dumps too.
    let described = film.describe(false, "");
    println!("view-bytes\t{}", described.len());
    println!("view-sha\t{}", sha_hex(described.as_bytes()));
}

fn sha_hex(bytes: &[u8]) -> String {
    let digest = shotlister_engine::sha256(bytes);
    digest.to_hex()
}
