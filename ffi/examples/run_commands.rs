//! Run engine commands, one a line from stdin, against a film — then save it.
//!
//! `cargo run --example run_commands -- <copy.shotlist> < commands.txt`
//!
//! For checks that need a film shaped a particular way (the export's sixty
//! days, `studio/quick.sh`). **Only ever on a copy**: it saves what it did.
use std::ffi::{CStr, CString};
use std::io::BufRead;
fn main() {
    let path = CString::new(std::env::args().nth(1).unwrap()).unwrap();
    unsafe {
        let h = shotlister_ffi::sl_open(path.as_ptr());
        assert!(!h.is_null());
        for line in std::io::stdin().lock().lines() {
            let line = line.unwrap();
            let c = CString::new(line).unwrap();
            let a = shotlister_ffi::sl_call(h, c.as_ptr());
            println!("{}", CStr::from_ptr(a).to_string_lossy());
            shotlister_ffi::sl_free(a);
        }
        let c = CString::new("save").unwrap();
        let a = shotlister_ffi::sl_call(h, c.as_ptr());
        eprintln!("save: {}", CStr::from_ptr(a).to_string_lossy());
        shotlister_ffi::sl_close(h);
    }
}
