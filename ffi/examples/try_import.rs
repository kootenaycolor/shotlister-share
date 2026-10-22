//! Runs an import against a project and prints what came back, for checking the
//! reply the app has to decode.
use std::ffi::CString;

fn main() {
    let args: Vec<String> = std::env::args().collect();
    unsafe {
        let path = CString::new(args[1].as_str()).unwrap();
        let h = shotlister_ffi::sl_open(path.as_ptr());
        assert!(!h.is_null());
        let line = CString::new(format!("import\t{}", args[2])).unwrap();
        let out = shotlister_ffi::sl_call(h, line.as_ptr());
        let s = std::ffi::CStr::from_ptr(out).to_string_lossy().into_owned();
        println!("{}", &s[..s.len().min(600)]);
        shotlister_ffi::sl_free(out);
        shotlister_ffi::sl_close(h);
    }
}
