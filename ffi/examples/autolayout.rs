//! **Auto layout on a real film, for looking at.**
//!
//! Prints what Auto measured and chose for the table, then writes two pages
//! beside each other — today's default and Auto's — so both can be rendered
//! and compared sheet by sheet.
//!
//! ```text
//! cargo build --release --example autolayout --manifest-path ffi/Cargo.toml
//! ./ffi/target/release/examples/autolayout ~/copy-of/Film.shotlist /tmp/out
//! ```
//!
//! Writes `/tmp/out-default.html`, `/tmp/out-auto.html` and
//! `/tmp/out-auto.json`. **Open a copy**, never a film in use.

use std::ffi::{CStr, CString};

fn call(handle: *mut shotlister_ffi::Handle, line: &str) -> String {
    let c = CString::new(line).unwrap();
    unsafe {
        let out = shotlister_ffi::sl_call(handle, c.as_ptr());
        let said = CStr::from_ptr(out).to_string_lossy().into_owned();
        shotlister_ffi::sl_free(out);
        said
    }
}

fn main() {
    let args: Vec<String> = std::env::args().collect();
    if args.len() < 3 {
        eprintln!("autolayout <project.shotlist> <out-stem> [extra tab-separated options]");
        std::process::exit(2);
    }
    let extra = args.get(3).cloned().unwrap_or_default();
    let tail = if extra.is_empty() { String::new() } else { format!("\t{extra}") };
    let project = CString::new(args[1].clone()).unwrap();
    let handle = unsafe { shotlister_ffi::sl_open(project.as_ptr()) };
    assert!(!handle.is_null(), "could not open that project");

    let started = std::time::Instant::now();
    let said = call(handle, &format!("tablelayout\texplain=1{tail}"));
    let took = started.elapsed();
    let (columns, json) = said.rsplit_once('\n').unwrap_or(("", &said));
    println!("{columns}\n{json}\ntablelayout took {:.1} ms", took.as_secs_f64() * 1000.0);
    std::fs::write(format!("{}-auto.json", args[2]), json).unwrap();

    // The shares, as the shell sends them back.
    let shares = json
        .split("\"shares\":{")
        .nth(1)
        .and_then(|rest| rest.split('}').next())
        .unwrap_or("")
        .replace('"', "");
    let fitted = if json.contains("\"cut\":0,") { "\tfitted=1" } else { "" };
    let scale = json
        .split("\"scale\":")
        .nth(1)
        .and_then(|rest| rest.split(',').next())
        .unwrap_or("1");
    println!(
        "{}",
        call(handle, &format!("print\ttable\t{}-default.html{tail}", args[2]))
    );
    println!(
        "{}",
        call(
            handle,
            &format!("print\ttable\t{}-auto.html\tscale={scale}\tshares={shares}{fitted}{tail}", args[2])
        )
    );
    unsafe { shotlister_ffi::sl_close(handle) };
}
