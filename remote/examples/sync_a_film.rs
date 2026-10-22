//! Sync one film from a command line, and say what it holds afterwards.
//!
//! ```text
//! cargo run --example sync_a_film -- --path "…/Daybreak.shotlist" --project <id>
//! cargo run --example sync_a_film -- --clone "…/somewhere new" --project <id>
//! ```
//!
//! The relay and the token come from `RELAY` and `RELAY_TOKEN`. This is the
//! headless door — for a checking run, for anything that has to sync without a
//! window open, and for the day something has gone wrong and the answer is to
//! watch it happen a step at a time.

use std::path::PathBuf;

use shotlister_engine::DeviceId;
use shotlister_remote::courier::{self, Relay};
use shotlister_storage as storage;

fn argument(name: &str) -> Option<String> {
    let args: Vec<String> = std::env::args().collect();
    let at = args.iter().position(|a| a == name)?;
    args.get(at + 1).cloned()
}

fn main() {
    let base = std::env::var("RELAY").unwrap_or_else(|_| "http://127.0.0.1:8799".to_string());
    let token = std::env::var("RELAY_TOKEN").unwrap_or_default();
    let Some(project) = argument("--project") else {
        eprintln!("--project <id> is needed: which film on the relay this is.");
        std::process::exit(2);
    };
    let device = DeviceId(
        argument("--device")
            .and_then(|d| u64::from_str_radix(&d, 16).ok())
            .unwrap_or(0x5171),
    );
    let relay = Relay::new(&base, &token, &project);

    let mut film = if let Some(into) = argument("--clone") {
        match courier::clone_project(&relay, &PathBuf::from(&into), device, 0) {
            Ok(film) => {
                println!("Brought it down to {into}");
                film
            }
            Err(error) => {
                eprintln!("Could not bring it down: {error}");
                std::process::exit(1);
            }
        }
    } else {
        let Some(path) = argument("--path") else {
            eprintln!("Give it --path <a .shotlist folder> or --clone <somewhere new>.");
            std::process::exit(2);
        };
        let mut film = match storage::open_as(&PathBuf::from(&path), device, 0) {
            Ok(film) => film,
            Err(error) => {
                eprintln!("Could not open it: {}", error.message());
                std::process::exit(1);
            }
        };
        match courier::sync(&mut film, &relay) {
            Ok(report) => println!(
                "sent {} log(s) and {} picture(s); took in {} log(s), {} picture(s), \
                 {} change(s), {} disagreement(s)",
                report.sent_logs,
                report.sent_media,
                report.received_logs,
                report.received_media,
                report.merged,
                report.clashes
            ),
            Err(error) => {
                eprintln!("Sync failed: {error}");
                std::process::exit(1);
            }
        }
        film
    };

    // The summary both sides get compared on. Deliberately things a person
    // would recognise rather than internal counts.
    let doc = film.doc_mut();
    let scenes = doc.scenes_in_order();
    let shots = doc.all_placements();
    println!(
        "holds: {} scene(s), {} shot(s), {} change(s), {} picture(s) still to arrive",
        scenes.len(),
        shots.len(),
        doc.changes().len(),
        film.missing_media().len(),
    );
}
