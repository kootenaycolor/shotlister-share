//! **An exported page, written out so somebody can look at it.**
//!
//! `STATUS.md`'s standing rule about exports: a file that contains the right
//! substrings can still look wrong. Both Excel bugs and three of the first PDF
//! export's faults passed every unit test and were found only by rendering the
//! page — and on 2026-08-31 the storyboard arrows added a fourth, a wrapper
//! that made a card print completely empty while the polygon it wrapped was
//! present and correct in the HTML.
//!
//! So: this renders a real page from a real project, with the real pictures in
//! it, and nothing else. Serve the result and photograph it.
//!
//! ```text
//! cargo build --example page --manifest-path ffi/Cargo.toml
//! ./ffi/target/debug/examples/page ~/Some.shotlist \
//!     "$(printf 'print\tstoryboard\t/tmp/board.html')"
//! (cd /tmp && python3 -m http.server 8731)
//! ```
//!
//! **Commands are tab-separated**, which is what the boundary itself splits on
//! — a space between the words is why the first attempt at this said "no
//! command called print storyboard".

use std::ffi::{CStr, CString};

fn main() {
    let args: Vec<String> = std::env::args().collect();
    if args.len() < 3 {
        eprintln!("page <project.shotlist> <tab-separated command>…");
        std::process::exit(2);
    }
    let project = CString::new(args[1].clone()).unwrap();
    unsafe {
        let handle = shotlister_ffi::sl_open(project.as_ptr());
        assert!(!handle.is_null(), "could not open that project");
        for line in args[2..].iter() {
            let call = CString::new(line.clone()).unwrap();
            let out = shotlister_ffi::sl_call(handle, call.as_ptr());
            // Only the head of it: a page's own answer is short, but a view
            // is a megabyte of JSON nobody wants in a terminal.
            let said = CStr::from_ptr(out).to_string_lossy();
            println!("{}", said.chars().take(400).collect::<String>());
            shotlister_ffi::sl_free(out);
        }
        shotlister_ffi::sl_close(handle);
    }
}
