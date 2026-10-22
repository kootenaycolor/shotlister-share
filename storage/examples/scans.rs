//! Register the rooms the phone scanned into a film, and say what it found.
//!
//!     cargo run --example scans --manifest-path storage/Cargo.toml -- "<film>.shotlist"
//!
//! **Additive and safe to repeat.** It reads `locations/<folder>/scans/`, copies
//! each file into the media store under its own hash and attaches it to the
//! location — the same thing a sync does now, on its own, before it decides
//! what to carry. Here so it can be run and looked at without syncing.
//!
//! Nothing in the scans folder is moved, renamed or deleted. The phone owns it.
//!
//! `--read` looks and changes nothing — which is what you want when a scan has
//! gone missing and the question is whether the film ever held it.
fn main() {
    let path = std::env::args().nth(1).expect("a .shotlist folder");
    let looking = std::env::args().any(|a| a == "--read");
    let path = std::path::PathBuf::from(path);
    // A device of our own, so a run of this never wears somebody else's name
    // in the change log.
    let device = shotlister_engine::DeviceId(0x5CA4);
    let mut project = shotlister_storage::open(&path, device).expect("open that film");
    if looking {
        use shotlister_engine::doc::f;
        use shotlister_engine::store::Kind;
        let held = project.doc().store().of_kind(&Kind::Media).iter()
            .filter(|r| matches!(r.text(f::MEDIA_KIND), Some("scan") | Some("scan_shape")))
            .count();
        // **The two numbers that matter are different numbers.** A film can
        // hold every scan it has ever been given and have none of them on a
        // location — which is exactly what a program reading an older engine
        // does to them, and it is invisible if you only count one.
        println!("{held} scan file(s) known to the film, {} attached to a location",
            project.doc().locations_in_order().iter()
                .map(|id| project.doc().scans_of(*id).len()).sum::<usize>());
    } else {
        let added = project.register_scans().expect("read the scans");
        if added > 0 {
            project.save().expect("write the change log");
        }
        println!("{added} file(s) newly registered");
    }
    for id in project.doc().locations_in_order() {
        let scans = project.doc().scans_of(id);
        if scans.is_empty() {
            continue;
        }
        let name = project
            .doc()
            .get(id)
            .and_then(|r| r.text(shotlister_engine::doc::f::LABEL).map(str::to_string))
            .unwrap_or_default();
        println!("  {name}: {} scan(s)", scans.len());
        for scan in scans {
            println!(
                "    {} — shape {} · measurements {}",
                scan.name,
                if scan.shape.is_some() { "yes" } else { "no" },
                if scan.plan.is_some() { "yes" } else { "no" }
            );
        }
    }
}
