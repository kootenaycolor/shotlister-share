//! Puts a picture on a shot in a project on disk, without the app.
//!
//! Exists so the drawing half of the media path can be checked on its own:
//! the app's job is to encode and hand over bytes, and this does that part
//! from the command line so the rendering can be looked at.
//!
//! Run with: cargo run --example seed_frame -- <project> <shot-number> <png>

use std::ffi::CString;

fn main() {
    let args: Vec<String> = std::env::args().collect();
    if args.len() < 4 {
        eprintln!("usage: seed_frame <project.shotlist> <shot number, e.g. 34C> <picture.png>");
        std::process::exit(2);
    }
    let (project, wanted, picture) = (&args[1], &args[2], &args[3]);

    let bytes = std::fs::read(picture).expect("could not read that picture");
    let encoded = shotlister_ffi::encode_for_test(&bytes);

    unsafe {
        let path = CString::new(project.as_str()).unwrap();
        let handle = shotlister_ffi::sl_open(path.as_ptr());
        assert!(!handle.is_null(), "could not open {project}");

        let view = call(handle, "view");
        // find the shot behind that number, the way a person would name it
        let needle = format!("\"number\":\"{wanted}\"");
        let at = view.find(&needle).unwrap_or_else(|| {
            panic!("there is no shot {wanted} in this project");
        });
        let before = &view[..at];
        let shot = before
            .rsplit("\"shot\":\"")
            .next()
            .unwrap()
            .split('"')
            .next()
            .unwrap();

        let reply = call(handle, &format!("paste\t{shot}\t1280\t535\tpng\t{encoded}"));
        if reply.contains("\"error\"") {
            eprintln!("{reply}");
            std::process::exit(1);
        }
        call(handle, "save");
        shotlister_ffi::sl_close(handle);
    }
    println!("put {picture} on {wanted}");
}

unsafe fn call(handle: *mut shotlister_ffi::Handle, line: &str) -> String {
    let c = CString::new(line).unwrap();
    let out = shotlister_ffi::sl_call(handle, c.as_ptr());
    let s = std::ffi::CStr::from_ptr(out).to_string_lossy().into_owned();
    shotlister_ffi::sl_free(out);
    s
}
