//! Walk an import the way the app will — weigh it, take it, then ask for the
//! script laid out to draw — through the real C boundary.
//!
//! Usage: cargo run --example an_import -- <path to a project folder>
use std::ffi::{CStr, CString};

fn call(h: *mut shotlister_ffi::Handle, line: &str) -> String {
    unsafe {
        let c = CString::new(line).unwrap();
        let out = shotlister_ffi::sl_call(h, c.as_ptr());
        let s = CStr::from_ptr(out).to_string_lossy().into_owned();
        shotlister_ffi::sl_free(out);
        s
    }
}

const DRAFT: &str = "\
33   INT. COUNTY JAIL - DAY

Sunlight through the high window.

                    FRANK
          It never gets shorter.

40   INT. NEW ROOM - NIGHT

The kettle.
";

fn main() {
    let args: Vec<String> = std::env::args().collect();
    let inside = std::path::Path::new(&args[1]);
    std::fs::create_dir_all(inside).unwrap();

    // A real project on disk, so this goes through the same doors the app does.
    let mut project =
        shotlister_storage::create(inside, "Call Her Back", shotlister_engine::DeviceId(9001))
            .unwrap();
    let scene = project.doc_mut().create_scene("33");
    project
        .doc_mut()
        .set(scene, shotlister_engine::doc::f::LOCATION, shotlister_engine::Value::text("COUNTY JAIL"));
    let orphan = project.doc_mut().create_scene("99");
    let (_, _) = project.doc_mut().add_shot_to_scene(orphan);
    project.save().unwrap();
    let where_it_is = project.path().to_path_buf();
    drop(project);

    let path = CString::new(where_it_is.to_string_lossy().as_ref()).unwrap();
    let h = unsafe { shotlister_ffi::sl_open(path.as_ptr()) };
    assert!(!h.is_null(), "that project would not open");

    let ask = |name: &str| {
        format!("takescript\t{name}\tDRAFTJP.pdf\t2026-08-20T11:56:00Z\t0,1\tFRANK\t1\n{DRAFT}")
    };

    println!("── weighing (nothing is written) ──");
    println!("{}", call(h, &ask("weigh")));

    println!("\n── taking it in ──");
    let done = call(h, &ask("Revision (8/20/26, 11:56 AM)"));
    println!("{}", &done[..done.find(",\"view\"").unwrap_or(done.len())]);

    println!("\n── the drafts the project keeps ──");
    println!("{}", call(h, "revisions"));

    println!("\n── laid out to draw ──");
    let pages = call(h, "scriptpages");
    println!("{}", &pages[..pages.len().min(700)]);

    unsafe { shotlister_ffi::sl_close(h) };
}
