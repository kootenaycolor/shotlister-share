//! Draw a scanned room from a `.json` the phone wrote, and print the result.
//!
//!     cargo run --example plan --manifest-path web/Cargo.toml -- <scan.json> [out.svg]
//!
//! Reads only. Here so a floor plan can be looked at without a browser.
fn main() {
    let mut args = std::env::args().skip(1);
    let path = args.next().expect("a scan .json to read");
    let text = std::fs::read_to_string(&path).expect("that file");
    let drawn = shotlister_web::room_drawing(&text, 520.0, 360.0);
    if drawn == "{}" {
        eprintln!("{path}: not a room this can read");
        std::process::exit(1);
    }
    if let Some(out) = args.next() {
        let svg = drawn
            .split("\"svg\":\"").nth(1).unwrap()
            .rsplit_once("\",\"across\"").unwrap().0
            .replace("\\\"", "\"");
        std::fs::write(&out, svg).expect("write the svg");
        eprintln!("wrote {out}");
    }
    println!("{drawn}");
}
