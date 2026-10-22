//! Actually carrying it, on a Mac.
//!
//! The deciding is next door in `lib.rs` and has no idea a network exists. This
//! is the other half: it talks to the relay over `curl`, which every Mac has
//! and which is therefore one fewer dependency to audit, keep current, and
//! cross-compile.
//!
//! **This is not what the apps will use.** The Mac and the phone hand transfers
//! to `URLSession`, because that is the only way to get one that survives the
//! app going to the background or the signal dropping halfway up a logging
//! road. This exists for the checking runs, for anything headless — Claude's
//! own server opening a project — and because being able to sync a film from a
//! command line is worth having when something has gone wrong.
//!
//! Nothing here decides anything. If it did, there would be two answers to
//! "what should move" and they would drift.

use std::io;
use std::path::{Path, PathBuf};
use std::process::Command;

use shotlister_engine::package;
use shotlister_storage::{write_whole, Project};

use crate::local::{local_inventory, wanted_stems};
use crate::{plan, Inventory, Plan};

/// Where the films are kept, and the word that gets us in.
pub struct Relay {
    base: String,
    token: String,
    project: String,
}

/// What a run of it did, in the terms the app puts on screen.
#[derive(Clone, Debug, Default)]
pub struct Report {
    pub sent_logs: usize,
    pub received_logs: usize,
    pub sent_media: usize,
    pub received_media: usize,
    /// What the merge made of what arrived. Empty until something did.
    pub merged: usize,
    pub clashes: usize,
}

impl Report {
    pub fn is_empty(&self) -> bool {
        self.sent_logs == 0
            && self.received_logs == 0
            && self.sent_media == 0
            && self.received_media == 0
    }
}

impl Relay {
    /// `base` is the address up to but not including `/v1`.
    pub fn new(base: &str, token: &str, project: &str) -> Relay {
        Relay {
            base: base.trim_end_matches('/').to_string(),
            token: token.to_string(),
            project: project.to_string(),
        }
    }

    fn url(&self, tail: &str) -> String {
        format!("{}/v1/p/{}/{}", self.base, self.project, tail)
    }

    /// One call, with the body written to a file so binary survives it and the
    /// status code read separately. Anything but a 2xx is an error here rather
    /// than a body that happens to be an apology in JSON.
    fn call(&self, args: &[&str], into: &Path) -> io::Result<()> {
        let output = Command::new("/usr/bin/curl")
            .args(["-s", "-S", "--fail-with-body"])
            .args(["-H", &format!("Authorization: Bearer {}", self.token)])
            .args(["-o", &into.to_string_lossy()])
            .args(["-w", "%{http_code}"])
            .args(args)
            .output()?;
        let code = String::from_utf8_lossy(&output.stdout).trim().to_string();
        if code.starts_with('2') {
            return Ok(());
        }
        let said = std::fs::read_to_string(into).unwrap_or_default();
        Err(io::Error::other(format!(
            "the relay said {code}: {}",
            said.trim().chars().take(200).collect::<String>()
        )))
    }

    fn get(&self, tail: &str, into: &Path) -> io::Result<()> {
        self.call(&[&self.url(tail)], into)
    }

    /// A log a fold wrote over, sent with the relay's own exception to the
    /// rule that a log may only ever grow. Ref 192.
    fn put_rewriting(&self, tail: &str, from: &Path, into: &Path) -> io::Result<()> {
        self.put(&format!("{tail}?rewrite=1"), from, into)
    }

    fn put(&self, tail: &str, from: &Path, into: &Path) -> io::Result<()> {
        self.call(
            &[
                "-X",
                "PUT",
                "--data-binary",
                &format!("@{}", from.to_string_lossy()),
                &self.url(tail),
            ],
            into,
        )
    }

    /// Everything the relay holds for this film.
    pub fn inventory(&self, scratch: &Path) -> io::Result<Inventory> {
        let state = scratch.join("state.json");
        let media = scratch.join("media.json");
        self.get("state", &state)?;
        self.get("media", &media)?;
        Ok(crate::parse_state(
            &std::fs::read_to_string(&state)?,
            &std::fs::read_to_string(&media)?,
        ))
    }
}

// ---- doing it ----------------------------------------------------------

/// Send what is ours, take what is theirs, then merge.
///
/// The order matters and is the same order the apps will use: **logs first,
/// then merge, then pictures.** The list is a megabyte and the pictures are a
/// hundred, so putting the merge in between is the difference between seeing
/// today's shots straight away and waiting for a film's worth of photographs
/// on a bad connection.
pub fn sync(project: &mut Project, relay: &Relay) -> io::Result<Report> {
    let scratch = std::env::temp_dir().join(format!(
        "shotlister-relay-{}",
        std::process::id()
    ));
    std::fs::create_dir_all(&scratch)?;
    let bin = scratch.join("reply");

    // **Before anything is weighed up, the rooms the phone scanned are made
    // part of the film.**
    //
    // A scan arrives as two files in `locations/<folder>/scans/` and nothing
    // used to put them in the document, so nothing carried them: a room was
    // visible only on a machine holding that folder. Registering them here
    // means the ordinary sync takes them — they become media like a
    // photograph, and every rule below already knows how to move a photograph.
    //
    // **It has to happen before the folder is listed**, or the log naming the
    // new rooms is written after the inventory that decides what to send and
    // sits on this device until the next run.
    //
    // Failure is not fatal on purpose. A folder that cannot be read is a
    // reason to carry the day's work anyway, not to refuse it.
    if !project.is_read_only() {
        let papers = project.register_attachments().unwrap_or(0);
        match project.register_scans().map(|n| n + papers) {
            Ok(0) => {}
            Ok(_) => {
                project.save().map_err(|e| io::Error::other(e.message()))?;
            }
            Err(trouble) => {
                eprintln!("the scans could not be read: {}", trouble.message());
            }
        }
    }

    let path = project.path().to_path_buf();
    let here = local_inventory(&path);
    let there = relay.inventory(&scratch)?;
    let wanted = wanted_stems(project);
    let folded = crate::local::folded(&path);
    let mut plan: Plan = plan(&here, &there, &wanted, &folded);
    // Never send a file the film no longer names — the same rule the ffi's
    // `syncplan` applies for the apps (2026-09-15).
    let strays = project
        .doc()
        .stray_media_names(here.media.iter().map(|e| e.name.as_str()));
    plan.upload_media.retain(|name| !strays.contains(name));

    let mut report = Report::default();

    // **One file that will not move does not stop the rest.** A run used to
    // give up at the first refusal, so a single log the relay would not take
    // held back every log behind it — and the newest, which is the day's work,
    // is always behind. 2026-09-04, when exactly that kept an afternoon of
    // changes on his Mac. The trouble is still reported; it is just reported
    // after everything that *could* travel has.
    let mut refused: Vec<String> = Vec::new();

    // ---- logs, both ways ------------------------------------------------
    let changes = path.join(package::CHANGES_DIR);
    for name in &plan.upload_logs {
        let sent = if plan.rewrite_logs.contains(name) {
            relay.put_rewriting(&format!("log/{name}"), &changes.join(name), &bin)
        } else {
            relay.put(&format!("log/{name}"), &changes.join(name), &bin)
        };
        match sent {
            Ok(()) => report.sent_logs += 1,
            Err(trouble) => refused.push(format!("{name}: {trouble}")),
        }
    }
    for name in &plan.download_logs {
        let into = scratch.join(name);
        if let Err(trouble) = relay.get(&format!("log/{name}"), &into) {
            refused.push(format!("{name}: {trouble}"));
            continue;
        }
        // Written whole, then swapped into place, so a reader on this machine
        // never sees half a log — the same rule saving already follows.
        write_whole(&changes.join(name), &std::fs::read(&into)?)?;
        report.received_logs += 1;
    }

    // ---- and then it is the engine's again ------------------------------
    if report.received_logs > 0 {
        let pulled = project.pull().map_err(|e| io::Error::other(e.message()))?;
        report.merged = pulled.merged;
        report.clashes = pulled.clashes.len();
    }

    // ---- pictures -------------------------------------------------------
    let proxies = path.join(package::PROXY_DIR);
    for name in &plan.upload_media {
        relay.put(&format!("media/{name}"), &proxies.join(name), &bin)?;
        report.sent_media += 1;
    }
    if !plan.download_media.is_empty() {
        std::fs::create_dir_all(&proxies)?;
    }
    for name in &plan.download_media {
        let into = scratch.join(name);
        relay.get(&format!("media/{name}"), &into)?;
        write_whole(&proxies.join(name), &std::fs::read(&into)?)?;
        report.received_media += 1;
    }

    // **The manifest goes last and only when it has to.** It is the one file
    // here that is rewritten rather than appended to, so it is also the one
    // that could lose something — and it lags behind the title anyway until
    // somebody saves. Sending it after the logs means the relay's copy is never
    // newer than the changes that explain it.
    let manifest = path.join(package::MANIFEST);
    if manifest.exists() {
        relay.put("manifest", &manifest, &bin)?;
    }

    let _ = std::fs::remove_dir_all(&scratch);
    if let Some(first) = refused.first() {
        return Err(io::Error::other(format!(
            "{} of {} files would not move — {first}",
            refused.len(),
            plan.upload_logs.len() + plan.download_logs.len()
        )));
    }
    Ok(report)
}

/// **Bring down a film this device has never had.**
///
/// The case iCloud handles by making you wait and hope: a second Mac, a new
/// phone, or his own machine after a reinstall. Everything needed to open a
/// project is here — the manifest that says what it is, and every log — so this
/// builds the folder from nothing and hands back an open project.
///
/// It refuses to write over a folder that already exists. Cloning on top of a
/// film somebody has been working in is not a thing anybody means to do, and
/// the local copy may hold changes the relay has never seen.
pub fn clone_project(
    relay: &Relay,
    into: &Path,
    device: shotlister_engine::DeviceId,
    installation: u64,
) -> io::Result<Project> {
    if into.exists() {
        return Err(io::Error::other(format!(
            "{} is already here. Open it and sync instead.",
            into.display()
        )));
    }

    let scratch = std::env::temp_dir().join(format!("shotlister-clone-{}", std::process::id()));
    std::fs::create_dir_all(&scratch)?;

    // Built beside and moved into place, so an interrupted clone leaves no
    // half a film behind for somebody to open next week.
    let building = scratch.join("building");
    let changes = building.join(package::CHANGES_DIR);
    std::fs::create_dir_all(&changes)?;

    relay.get("manifest", &building.join(package::MANIFEST))?;

    let there = relay.inventory(&scratch)?;
    for entry in &there.logs {
        let into_file = scratch.join(&entry.name);
        relay.get(&format!("log/{}", entry.name), &into_file)?;
        write_whole(&changes.join(&entry.name), &std::fs::read(&into_file)?)?;
    }

    if let Some(parent) = into.parent() {
        std::fs::create_dir_all(parent)?;
    }
    std::fs::rename(&building, into)?;
    let _ = std::fs::remove_dir_all(&scratch);

    shotlister_storage::open_as(into, device, installation)
        .map_err(|error| io::Error::other(error.message()))
}

/// Where a project remembers which relay it belongs to.
///
/// **Written once and never rewritten**, which is what makes it safe to keep
/// inside the package: it travels to every device over whatever is already
/// syncing the folder, so a film started on the Mac is already pointed at the
/// right relay by the time the phone opens it — and there is nothing for two
/// devices to disagree about, the way there would be if each rewrote it.
///
/// The same reasoning as the identity mark beside the logs (Ref 186).
pub const LINK_FILE: &str = "remote.json";

pub fn link_path(project: &Path) -> PathBuf {
    project.join(LINK_FILE)
}

/// Read the link, if this project has been pointed at a relay.
pub fn read_link(project: &Path) -> Option<(String, String)> {
    let text = std::fs::read_to_string(link_path(project)).ok()?;
    let json = shotlister_engine::json::parse(&text)?;
    let base = json.get("relay")?.as_str()?.to_string();
    let id = json.get("project")?.as_str()?.to_string();
    Some((base, id))
}

pub fn write_link(project: &Path, base: &str, id: &str) -> io::Result<()> {
    let body = shotlister_engine::json::Json::object(vec![
        ("relay", shotlister_engine::json::Json::text(base)),
        ("project", shotlister_engine::json::Json::text(id)),
    ])
    .encode();
    write_whole(&link_path(project), body.as_bytes())
}
