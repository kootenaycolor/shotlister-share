//! Print a film's whole description, as the Mac app receives it.
//!
//! `cargo run --example dump_view -- <film.shotlist> [command …]`
//!
//! Exists so that a change to how that description is built can be proved to
//! have changed nothing: capture it before, capture it after, compare. **Open a
//! copy, never a film he is working in** — opening one leaves a mark in it.
use std::ffi::{CStr, CString};

fn main() {
    let mut args = std::env::args().skip(1);
    let path = args.next().expect("give me a .shotlist folder");
    let command = args.next().unwrap_or_else(|| "view".to_string());
    let path = CString::new(path).unwrap();
    let command = CString::new(command).unwrap();
    unsafe {
        let handle = shotlister_ffi::sl_open(path.as_ptr());
        if handle.is_null() {
            let problem = shotlister_ffi::sl_problem();
            eprintln!("could not open it: {}", CStr::from_ptr(problem).to_string_lossy());
            shotlister_ffi::sl_free(problem);
            std::process::exit(1);
        }
        let answer = shotlister_ffi::sl_call(handle, command.as_ptr());
        println!("{}", CStr::from_ptr(answer).to_string_lossy());
        shotlister_ffi::sl_free(answer);
        shotlister_ffi::sl_close(handle);
    }
}
