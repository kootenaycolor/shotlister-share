//! The names Room from Scan would give the rooms already scanned in a film,
//! beside what they are called now — a preview, nothing is renamed:
//!
//!     cargo run --example scan_names --manifest-path storage/Cargo.toml -- "<film>.shotlist"
//!
//! `--apply` renames them (both halves of each room, one undo step per
//! room); their files and every plan laid from them stay as they are.
fn main() {
    use shotlister_engine::doc::f;
    let path = std::path::PathBuf::from(std::env::args().nth(1).expect("a .shotlist folder"));
    let apply = std::env::args().any(|a| a == "--apply");
    let device = shotlister_engine::DeviceId(0x5CA5);
    let mut project = shotlister_storage::open(&path, device).expect("open that film");
    let places = project.doc().locations_in_order();
    let mut renames = Vec::new();
    for place in places {
        let folder = {
            let r = project.doc().get(place).unwrap();
            let folder = r.text(f::FOLDER).unwrap_or("").trim().to_string();
            if folder.is_empty() { place.0.to_string() } else { folder }
        };
        let dir = path.join("locations").join(&folder).join("scans");
        let seen = |scan: &shotlister_engine::media::Scan| -> Vec<String> {
            std::fs::read_to_string(dir.join(format!("{}.json", scan.file)))
                .ok()
                .and_then(|t| shotlister_engine::room::read(&t))
                .map(|p| p.rooms.into_iter().map(|(n, _)| n).collect())
                .unwrap_or_default()
        };
        for (scan, name) in project.doc().suggested_scan_names(place, &seen) {
            println!(
                "{}\t{}\t{}\t{}",
                project.doc().location_full_name(place),
                scan.name,
                name,
                shotlister_engine::media::scan_date_text(&scan.file)
            );
            renames.push((place, scan.name, name));
        }
    }
    if apply {
        for (place, from, to) in renames {
            project.doc_mut().rename_scan(place, &from, &to);
        }
        project.save().expect("write the change log");
        println!("renamed");
    }
}
