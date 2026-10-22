//! Projects on disk.
//!
//! The engine deliberately never touches a file. This is the layer that does,
//! and it is kept deliberately thin: open, save, and put media where the engine
//! says it goes. Every decision about *what* goes where already lives in
//! `shotlister_engine::package`, so a second shell cannot disagree with this one.
//!
//! Saving appends. A session writes to its own log and never rewrites a line
//! anybody else wrote, which is what makes two devices on one synced folder safe
//! without any locking.

use std::collections::{HashMap, HashSet};
use std::fs;
use std::io;
use std::path::{Path, PathBuf};
use std::time::{SystemTime, UNIX_EPOCH};

use shotlister_engine::format::{decode_log, encode_changes, encode_log};
use shotlister_engine::package::{self, Access, Manifest, Problem};
use shotlister_engine::media::{plan_cache, CacheEntry, MediaKind};
use shotlister_engine::{Change, Clash, DeviceId, Doc, Id, Stamp, FORMAT_VERSION};

/// What a pull brought in.
///
/// `merged` is a count rather than a list because nobody wants to read a list of
/// changes; what matters on screen is that something arrived, roughly how much,
/// and — only if there is one — a disagreement.
#[derive(Clone, Debug, Default)]
pub struct Pull {
    pub merged: usize,
    /// Which devices the changes came from.
    pub devices: Vec<DeviceId>,
    /// Fields this pull put in disagreement. Empty is the normal case and
    /// deserves no words at all.
    pub clashes: Vec<Clash>,
}

impl Pull {
    /// Whether anything arrived at all.
    pub fn is_empty(&self) -> bool {
        self.merged == 0
    }

    /// Whether it needs saying out loud. Changes arriving is the system working;
    /// only a disagreement is an exception.
    pub fn needs_attention(&self) -> bool {
        !self.clashes.is_empty()
    }
}

/// **Two installations writing under one device name.** Ref 186.
///
/// This is the one failure the sync design cannot survive quietly. Every device
/// is supposed to have a name of its own; when two share one, a change each of
/// them makes in the same millisecond produces the same stamp, and the second
/// is thrown away as a duplicate of the first. No warning, no trace, and the
/// disagreement detector can no longer tell the two apart either.
///
/// Found by looking at the marks in `changes/` rather than by watching writes
/// happen — because two diaries being written under one name *at once* is also
/// what happens when he opens a second window with ⌘N, which is perfectly
/// ordinary. A mark names the hardware, so two marks claiming one device id is
/// two machines and nothing else.
#[derive(Clone, Debug, PartialEq, Eq)]
pub struct IdentityClash {
    /// The name more than one machine is writing under.
    pub device: DeviceId,
    /// How many machines are wearing it.
    pub machines: usize,
    /// Whether this one is among them. Either way it is worth saying: a clash
    /// between the phone and a second Mac loses his edits just as thoroughly
    /// when neither is the machine noticing it.
    pub ours: bool,
}

impl IdentityClash {
    /// What to put on screen. A warning earns a sentence — see *How the app
    /// talks* in `CLAUDE.md` — because there is nothing a label could say that
    /// would carry the consequence.
    ///
    /// **It stops at what is true and does not offer a cure**, because there
    /// is not one yet: giving a device a new name is its own decision, filed
    /// separately. Telling him to do something the app cannot do would be
    /// worse than saying nothing.
    pub fn message(&self) -> String {
        let who = if self.ours && self.machines == 2 {
            "This device and another are".to_string()
        } else if self.machines == 2 {
            "Two other devices are".to_string()
        } else {
            format!("{} devices are", self.machines)
        };
        format!(
            "{who} using the same name in this project. Edits made on two of them at the same \
             moment can be lost."
        )
    }
}

#[derive(Debug)]
pub enum Error {
    Io(io::Error),
    /// The project cannot be opened, or cannot be written to.
    Project(Problem),
    /// Somebody asked to write to a project this build may only read.
    ReadOnly,
}

impl From<io::Error> for Error {
    fn from(error: io::Error) -> Error {
        Error::Io(error)
    }
}

impl From<Problem> for Error {
    fn from(problem: Problem) -> Error {
        Error::Project(problem)
    }
}

impl Error {
    /// What to put on screen.
    pub fn message(&self) -> String {
        match self {
            Error::Io(error) => format!("Could not reach the project: {error}"),
            Error::Project(problem) => problem.message(),
            Error::ReadOnly => {
                "This project is open for reading only, so changes cannot be saved.".to_string()
            }
        }
    }
}

pub type Result<T> = std::result::Result<T, Error>;

/// An open project: the list, where it lives, and what may be done to it.
pub struct Project {
    path: PathBuf,
    doc: Doc,
    manifest: Manifest,
    access: Access,
    device: DeviceId,
    /// Which *machine* this is, as opposed to which name it writes under. Zero
    /// when the shell has not said — an older app, or a checking harness — and
    /// then no mark is left and nothing is claimed.
    installation: u64,
    /// Set when the marks in `changes/` show one name worn by two machines.
    clash: Option<IdentityClash>,
    /// Lines the logs held that this build could not read, counted so the app
    /// can say so. They are not carried anywhere: logs are only ever appended
    /// to, so a line nobody rewrites is already safe where it is.
    unreadable: usize,
    /// How many of *our own* changes are already on disk. Saving appends what is
    /// past this. Counted per device rather than as a position in the log,
    /// because pulling from another device puts changes in the log that are not
    /// ours to write.
    persisted: usize,
    log: PathBuf,
    /// Size and date of every log we have already taken in, so checking for new
    /// work costs a look at the file system rather than a full read.
    seen: HashMap<PathBuf, LogState>,
}

/// Enough of a file to tell whether it has moved. Not a hash: a change log is
/// only ever appended to, so a size and a date that both match mean the same
/// bytes.
type LogState = (u64, Option<std::time::SystemTime>);

fn state_of(path: &Path) -> LogState {
    match fs::metadata(path) {
        Ok(meta) => (meta.len(), meta.modified().ok()),
        Err(_) => (0, None),
    }
}

fn now_millis() -> u64 {
    SystemTime::now()
        .duration_since(UNIX_EPOCH)
        .map(|d| d.as_millis() as u64)
        .unwrap_or(0)
}

impl Project {
    /// Which machine this open project believes it is. Needed wherever a
    /// device has to be named in words — "This Mac" against "another
    /// machine" — rather than as a number nobody can read.
    pub fn device(&self) -> DeviceId {
        self.device
    }

    /// Which machine this is. Zero when the shell did not say.
    pub fn installation(&self) -> u64 {
        self.installation
    }

    /// Set when two machines are writing under one device name — the one
    /// failure that loses his work without saying so. Ref 186.
    pub fn identity_clash(&self) -> Option<&IdentityClash> {
        self.clash.as_ref()
    }

    pub fn path(&self) -> &Path {
        &self.path
    }

    pub fn doc(&self) -> &Doc {
        &self.doc
    }

    pub fn doc_mut(&mut self) -> &mut Doc {
        &mut self.doc
    }

    pub fn manifest(&self) -> &Manifest {
        &self.manifest
    }

    pub fn is_read_only(&self) -> bool {
        self.access == Access::ReadOnly
    }

    /// Our own changes, in the order we made them. Another device's changes sit
    /// in the same log but are not ours to write out.
    fn ours(&self) -> Vec<&Change> {
        self.doc
            .changes()
            .iter()
            .filter(|change| change.stamp.device == self.device)
            .collect()
    }

    /// Changes made since the last save.
    pub fn unsaved(&self) -> usize {
        self.ours().len().saturating_sub(self.persisted)
    }

    pub fn has_unsaved(&self) -> bool {
        self.unsaved() > 0
    }

    /// How many lines in this project were written by a build we do not fully
    /// understand. They are untouched where they are; this is only so the app
    /// can say that something here was written by a newer version.
    pub fn unreadable_lines(&self) -> usize {
        self.unreadable
    }

    /// **Leave this machine's mark beside its diaries.** Ref 186.
    ///
    /// Created once and never touched again — the name carries everything, the
    /// file is empty. Failure is deliberately ignored: a project on a
    /// read-only volume, or one we may only read, should still open.
    fn leave_mark(&self) {
        if self.installation == 0 || self.is_read_only() {
            return;
        }
        let mark = self
            .path
            .join(package::CHANGES_DIR)
            .join(package::device_mark_name(self.device, self.installation));
        if mark.exists() {
            return;
        }
        let _ = fs::create_dir_all(self.path.join(package::CHANGES_DIR));
        let _ = fs::write(&mark, b"");
    }

    /// **Read every machine's mark and look for one name worn by two.**
    ///
    /// Ours first when there is a choice, because the machine in front of him
    /// is the one he can do something about.
    fn identity_clash_now(&self) -> Option<IdentityClash> {
        let mut claims: HashMap<DeviceId, HashSet<u64>> = HashMap::new();
        let dir = self.path.join(package::CHANGES_DIR);
        let entries = fs::read_dir(&dir).ok()?;
        for entry in entries.filter_map(|e| e.ok()) {
            let name = entry.file_name();
            let Some(name) = name.to_str() else { continue };
            if let Some((device, installation)) = package::device_mark_parts(name) {
                claims.entry(device).or_default().insert(installation);
            }
        }

        let mut clashes: Vec<IdentityClash> = claims
            .into_iter()
            .filter(|(_, machines)| machines.len() > 1)
            .map(|(device, machines)| IdentityClash {
                device,
                machines: machines.len(),
                ours: device == self.device && machines.contains(&self.installation),
            })
            .collect();
        // Ours first, then by name, so the answer does not depend on the order
        // the file system happened to hand the marks over.
        clashes.sort_by_key(|clash| (!clash.ours, clash.device.0));
        clashes.into_iter().next()
    }
}

// ---- opening and creating ----------------------------------------------

/// Start a new project at a folder of its own.
pub fn create(inside: &Path, title: &str, device: DeviceId) -> Result<Project> {
    create_as(inside, title, device, 0)
}

/// Start a new project, saying **which machine** is doing it as well as which
/// name it writes under. Ref 186. `installation` of zero means the shell has
/// no opinion, and then nothing is claimed and nothing is checked.
pub fn create_as(
    inside: &Path,
    title: &str,
    device: DeviceId,
    installation: u64,
) -> Result<Project> {
    let path = inside.join(package::package_name(title));
    fs::create_dir_all(path.join(package::CHANGES_DIR))?;
    fs::create_dir_all(path.join(package::PROXY_DIR))?;
    fs::create_dir_all(path.join(package::ORIGINALS_DIR))?;

    let mut doc = Doc::new(device);
    let project = doc.create_project(title);
    // **The lists he works from**, before anybody sees the file — his ask of
    // 2026-08-22. A new film should not start by retyping sixteen shot sizes.
    doc.seed_standing_vocabularies();
    // Opening a fresh project with an undo step waiting is not what anybody
    // means by new.
    doc.clear_history();

    let manifest = Manifest::new(title, Some(project));
    write_whole(&path.join(package::MANIFEST), manifest.encode().as_bytes())?;

    let session = now_millis();
    let log = path
        .join(package::CHANGES_DIR)
        .join(package::log_name(device, session));

    let mut opened = Project {
        path,
        doc,
        manifest,
        access: Access::ReadWrite,
        device,
        installation,
        clash: None,
        unreadable: 0,
        persisted: 0,
        log,
        seen: HashMap::new(),
    };
    // A brand new folder cannot hold a clash, but it should still carry this
    // machine's mark from the start — otherwise the machine that *made* the
    // film is the one device a later collision cannot be pinned on.
    opened.leave_mark();
    opened.save()?;
    Ok(opened)
}

/// Open an existing project. Every log in it is merged, in whatever order the
/// file system hands them over — which does not matter, and there is a test for
/// that in the engine.
pub fn open(path: &Path, device: DeviceId) -> Result<Project> {
    open_as(path, device, 0)
}

/// Open a project, saying **which machine** is opening it as well as which name
/// it writes under. Ref 186.
///
/// The machine leaves a mark in `changes/` and reads everybody else's. Two
/// marks claiming one name is a collision, and it is reported rather than
/// fixed: renaming a device here would orphan every change it had already
/// written, and which of the two should give way is not this layer's to decide.
pub fn open_as(path: &Path, device: DeviceId, installation: u64) -> Result<Project> {
    let manifest_text = fs::read_to_string(path.join(package::MANIFEST))
        .map_err(|error| Error::Project(Problem::Unreadable(error.to_string())))?;
    let manifest = Manifest::parse(&manifest_text)?;
    let access = package::access(manifest.format)?;

    let mut doc = Doc::new(device);
    let changes_dir = path.join(package::CHANGES_DIR);
    let mut unreadable = 0;
    let mut seen = HashMap::new();

    for log in logs_in(&changes_dir)? {
        // Recorded before reading, not after: a log that grows while we are
        // reading it should look new next time rather than already taken in.
        seen.insert(log.clone(), state_of(&log));
        let text = fs::read_to_string(&log)?;
        let parsed = decode_log(&text)
            .map_err(|_| Error::Project(Problem::Unreadable(format!("{}", log.display()))))?;
        doc.merge(parsed.changes);
        unreadable += parsed.preserved.len();
    }

    // History belongs to a session. You cannot undo what happened last week.
    doc.clear_history();

    let session = now_millis();
    let log = changes_dir.join(package::log_name(device, session));
    let persisted = doc
        .changes()
        .iter()
        .filter(|change| change.stamp.device == device)
        .count();

    let mut opened = Project {
        path: path.to_path_buf(),
        doc,
        manifest,
        access,
        device,
        installation,
        clash: None,
        unreadable,
        persisted,
        log,
        seen,
    };

    // **Say who we are before asking who else is here** — Ref 186. A machine
    // that read the marks before leaving its own would never be part of the
    // collision it is looking for, so the first of two clashing machines to
    // open the project would see nothing wrong.
    opened.leave_mark();
    opened.clash = opened.identity_clash_now();

    // **And the films he already has get the standing lists too**, once each.
    // A project made before 2026-08-22 has none, and seeding only new projects
    // would mean the two films he is actually shooting never see them. Nothing
    // is taken away: whatever the project had already learned is kept, after
    // the standing terms.
    //
    // **After `persisted` is counted, deliberately.** Seeding above that line
    // marks the new changes as already written and they are then never saved —
    // the list would appear this session and be gone the next.
    // **And a film the gear-column merge reached gets it taken back off** —
    // Ref 326, undone. Same reasoning and the same place in the order: after
    // `persisted`, or the repair would show this session and be gone the next.
    // A film it never reached carries no mark and this does nothing at all.
    let mut changed = false;
    if !opened.is_read_only() {
        changed |= opened.doc.seed_standing_vocabularies();
        changed |= opened.doc.unmerge_gear_columns();
        // **A section made before sections were born coloured gets one**
        // (2026-09-19) — the spine down the table and the tinted head need
        // an ink, and grey is every section's.
        changed |= opened.doc.colour_bare_sequences();
        // **A commercial's scene-level Video / Audio becomes beats**, once
        // (2026-09-19). Shots are tied to their scene's beat; nothing is lost.
        changed |= opened.doc.adopt_scene_beats() > 0;
        // **…and tonight's beats become the script as text**, once
        // (2026-09-19, later): a shot tied to a beat quotes its words.
        changed |= opened.doc.adopt_beats_as_script() > 0;
    }
    if changed {
        opened.doc.clear_history();
        opened.save()?;
    }

    // **A script written before scripts travelled joins the proxies**, so the
    // relay carries it from now on (2026-09-15).
    let _ = opened.adopt_scripts();

    // **Pictures nothing points at any more give their room back** — Ref
    // 192. Here and nowhere else: the history was cleared two dozen lines
    // above, so there is nothing an undo could bring back to point at them.
    let _ = opened.reclaim_orphans();

    // **And files no record names any more go too.** A clip replaced by a
    // smaller copy of itself leaves its old self behind under the old name;
    // this is what takes it away, on every device, once the log that renamed
    // it has arrived.
    let _ = opened.reclaim_strays();

    // **And this device's old diaries become one file** — Ref 192. Last,
    // deliberately: a fold rewrites files on disk and touches nothing in the
    // list, so it must not be able to affect what was just read. A failure
    // here is not a failure to open — the project is already in hand and the
    // files it was going to tidy are all still there.
    let _ = opened.fold_logs();

    Ok(opened)
}

// ---- folding old logs together -----------------------------------------

/// **How old a log has to be before it may be folded into another.** Ref 192.
///
/// Not a guess at how fast iCloud is, and not a bet: the changes in a folded
/// log are not thrown away, they are rewritten byte for byte into the file
/// beside them. A week is a margin on the one thing that could bite — a device
/// that reads the delete before it reads the file the delete was safe because
/// of.
const SETTLED_AFTER_MILLIS: u64 = 7 * 24 * 60 * 60 * 1000;

/// **How many of our own settled logs it takes to bother.** Below this the
/// folding costs more than the clutter does, and every launch would pay it.
const FOLD_ABOVE: usize = 8;

/// What a fold did, so the app can say so and a check can assert it.
#[derive(Clone, Debug, Default, PartialEq)]
pub struct Fold {
    /// How many files went away. Zero is the ordinary answer.
    pub folded: usize,
    /// What they held between them, and now hold in one file.
    pub changes: usize,
}

impl Fold {
    pub fn is_empty(&self) -> bool {
        self.folded == 0
    }
}

impl Project {
    /// **Fold this device's own old diaries into one file.** Ref 192.
    ///
    /// Every launch of every app starts a diary of its own. Nothing was ever
    /// wrong with that — a session only ever appends to its own file, and that
    /// is exactly why two devices on one synced folder need no locking — but a
    /// year of daily use across three machines is a thousand small files, and
    /// iCloud moves a thousand small files far worse than it moves a few big
    /// ones. Opening the project reads every one of them.
    ///
    /// **Nothing is thrown away, so no watermark is needed.** This is the part
    /// worth understanding: the changes in the folded files are written out
    /// again, unaltered, into one of the files they came from. A device that
    /// has already read them learns nothing new — a change is known by its
    /// stamp, and merging one twice does nothing. A device that has never read
    /// them gets all of them from the one file. There is no moment at which a
    /// change exists nowhere, which is the whole reason the append-only log
    /// cannot resurrect a deletion, and folding must not become the exception.
    ///
    /// Four rules keep it safe, and each one is load-bearing:
    ///
    /// - **Only our own logs.** A device owns its diary; nobody else may
    ///   rewrite it. Two devices folding at once touch different files.
    /// - **Never this session's.** It is still being appended to.
    /// - **Only ones a week old**, so every device has long since read them.
    /// - **Only ones we can read whole.** A log holding a line written by a
    ///   newer build is left exactly where it is, rather than rewritten under
    ///   a version header that would be a lie about who wrote it.
    ///
    /// The new file takes the name of the newest log in the set, so no name is
    /// invented and the write is a rename over a file that is about to be
    /// deleted anyway. If the machine goes down between the rename and the
    /// deletes, what is left is the folded file beside the originals it was
    /// made from — duplicates, and duplicates are free.
    pub fn fold_logs(&mut self) -> Result<Fold> {
        if self.is_read_only() {
            return Ok(Fold::default());
        }
        let dir = self.path.join(package::CHANGES_DIR);

        // Ours, settled, and not the one we are writing to.
        let cutoff = now_millis().saturating_sub(SETTLED_AFTER_MILLIS);
        let mut ours: Vec<(u64, PathBuf)> = Vec::new();
        for log in logs_in(&dir)? {
            if log == self.log {
                continue;
            }
            let Some(name) = log.file_name().and_then(|n| n.to_str()) else {
                continue;
            };
            let Some((device, session)) = package::log_parts(name) else {
                continue;
            };
            if device != self.device || session > cutoff {
                continue;
            }
            ours.push((session, log));
        }
        if ours.len() <= FOLD_ABOVE {
            return Ok(Fold::default());
        }
        ours.sort();

        // Read them all before writing anything. A log we cannot read whole
        // drops out of the set here rather than being rewritten badly.
        let mut changes: Vec<Change> = Vec::new();
        let mut folding: Vec<PathBuf> = Vec::new();
        for (_, log) in &ours {
            let Ok(text) = fs::read_to_string(log) else {
                continue;
            };
            let Ok(parsed) = decode_log(&text) else {
                continue;
            };
            if !parsed.preserved.is_empty() {
                continue;
            }
            changes.extend(parsed.changes);
            folding.push(log.clone());
        }
        if folding.len() <= FOLD_ABOVE {
            return Ok(Fold::default());
        }

        // Written in the order they were made, which is the order a log has
        // always been in. Merging does not care, but a person reading one does.
        //
        // **The order is total and the set has no repeats, so folding twice
        // gives the same bytes twice.** Not tidiness: a fold that is not
        // idempotent grows without bound. The retired logs live on at the relay
        // and one that came back would be folded in a second time, then a
        // third, each round carrying every earlier round's copy with it. Sorting
        // by the whole stamp rather than its clock alone is what makes the
        // result independent of the order the files happened to be read in.
        changes.sort_by_key(|change| {
            (
                change.stamp.millis,
                change.stamp.counter,
                change.stamp.device.0,
            )
        });
        changes.dedup();

        // The newest of the set takes them all, so no new name enters the
        // folder and the last step is a delete rather than a write.
        let target = folding.last().expect("checked above").clone();
        write_whole(&target, encode_log(FORMAT_VERSION, &changes, &[]).as_bytes())?;

        let mut folded = 0;
        for log in &folding {
            if *log == target {
                continue;
            }
            if fs::remove_file(log).is_ok() {
                folded += 1;
                self.seen.remove(log);
            }
        }
        self.seen.insert(target.clone(), state_of(&target));

        // **Say what was done, where sync can see it.** Ref 192 tidies the
        // folder; without this it also jams the relay. A rewritten log is
        // refused by a server whose one rule is that a log may only grow, and
        // the deleted ones are fetched straight back on the next sync and
        // folded again on the launch after that. Neither half can be worked out
        // from the files that are left, so the fold is the only thing that can
        // ever say it. 2026-09-04, after a jam that held a day's work on his
        // Mac while the web showed the film as it stood that afternoon.
        let retired = folding
            .iter()
            .filter(|log| **log != target)
            .filter_map(|log| log.file_name()?.to_str().map(str::to_string))
            .collect::<Vec<_>>();
        if let Some(name) = target.file_name().and_then(|n| n.to_str()) {
            let _ = self.write_fold_record(&retired, name);
        }

        Ok(Fold {
            folded,
            changes: changes.len(),
        })
    }

    /// Add to this device's fold record, keeping whatever is already in it.
    ///
    /// **Read, add, write whole.** A fold is rare and the file is a list of
    /// names, so there is nothing to gain by being cleverer, and one file per
    /// device means nobody else is ever writing to it.
    fn write_fold_record(&self, retired: &[String], rewritten: &str) -> io::Result<()> {
        let path = self
            .path
            .join(package::CHANGES_DIR)
            .join(package::fold_record_name(self.device));
        let mut record = fs::read_to_string(&path)
            .map(|text| package::decode_fold_record(&text))
            .unwrap_or_default();
        record.retired.extend(retired.iter().cloned());
        record.rewritten.push(rewritten.to_string());

        // A log that was rewritten and has since been folded away itself is
        // retired, not rewritten. Saying both would send it up and then refuse
        // to fetch it, which is a plan that argues with itself.
        record.rewritten.retain(|name| !record.retired.contains(name));
        record.retired.sort();
        record.retired.dedup();
        record.rewritten.sort();
        record.rewritten.dedup();

        write_whole(&path, package::encode_fold_record(&record).as_bytes())
    }
}

// ---- reclaiming the bytes behind deleted pictures -----------------------

/// What a reclaim did.
#[derive(Clone, Debug, Default, PartialEq)]
pub struct Reclaim {
    /// How many pictures nothing pointed at any more.
    pub pictures: usize,
    /// How much room they were taking.
    pub bytes: u64,
}

impl Reclaim {
    pub fn is_empty(&self) -> bool {
        self.pictures == 0
    }
}

/// Every file in a folder filed under one name, whatever it was stored as. A
/// clip keeps two — the movie and the still that stands for it wherever a
/// picture is drawn — so this is deliberately not "the file".
fn remove_by_stem(dir: &Path, stem: &str) -> u64 {
    let Ok(listing) = fs::read_dir(dir) else {
        return 0;
    };
    let mut freed = 0;
    for entry in listing.flatten() {
        let path = entry.path();
        if path.file_stem().and_then(|s| s.to_str()) != Some(stem) {
            continue;
        }
        let size = entry.metadata().map(|m| m.len()).unwrap_or(0);
        if fs::remove_file(&path).is_ok() {
            freed += size;
        }
    }
    freed
}

impl Project {
    /// **Give back the room a deleted picture was taking.** Ref 192.
    ///
    /// Removing a frame takes away the *use* of a picture; the bytes stay,
    /// because until now nothing ever reclaimed them. They then sync to every
    /// device, for ever, and a year of second thoughts is a folder full of
    /// pictures no shot has pointed at since March.
    ///
    /// Two things had to be true before this could be written at all, and both
    /// are worth stating because either one alone would have made it a bug:
    ///
    /// - **Undo must not be able to reach it.** Removing a frame is one
    ///   undoable step, so deleting the bytes the moment nothing points at
    ///   them would make the app manufacture a hollow frame on purpose — press
    ///   undo and the record comes back with no picture behind it. This runs
    ///   only at open, where the history has just been cleared and there is
    ///   nothing to undo. Nothing calls it mid-session on purpose.
    /// - **Every device must know.** The folder is shared, and a machine that
    ///   has not merged the deletion yet still has records pointing at the
    ///   file. `settled_orphans` is the engine's answer to that, out of the
    ///   watermark each change already carries, so nothing extra is exchanged.
    ///
    /// The record goes with the bytes. Left behind, it would be a picture the
    /// folder has not got, which is exactly what `missing_media` reports as a
    /// hollow frame — a real alarm, raised about nothing.
    pub fn reclaim_orphans(&mut self) -> Result<Reclaim> {
        if self.is_read_only() {
            return Ok(Reclaim::default());
        }
        use shotlister_engine::doc::f;

        let orphans = self.doc.settled_orphans();
        if orphans.is_empty() {
            return Ok(Reclaim::default());
        }

        let stems: Vec<(Id, String)> = orphans
            .iter()
            .filter_map(|id| {
                let hash = self.doc.get(*id)?.text(f::HASH)?;
                Some((*id, hash.chars().take(32).collect()))
            })
            .collect();

        let proxies = self.path.join(package::PROXY_DIR);
        let originals = self.path.join(package::ORIGINALS_DIR);
        let mut bytes = 0;
        for (_, stem) in &stems {
            bytes += remove_by_stem(&proxies, stem);
            bytes += remove_by_stem(&originals, stem);
        }
        for (id, _) in &stems {
            self.doc.delete(*id);
        }
        self.doc.clear_history();
        self.save()?;

        Ok(Reclaim {
            pictures: stems.len(),
            bytes,
        })
    }

    /// **Take away the stored files this film no longer names.** 2026-09-15.
    ///
    /// `Doc::stray_media_names` is the judge — a file is a stray when no
    /// record's hash is its stem and it is not a strip of a clip the film
    /// holds — and this is the hand. Two things it will not do:
    ///
    /// - **Touch anything written in the last hour.** A file lands a moment
    ///   before the log that names it is saved, on every device; a sweep that
    ///   ran between the two would take a brand-new picture. An hour is far
    ///   longer than that gap and far shorter than a stray's life.
    /// - **Judge a file not named like a stored one.** Those are somebody
    ///   else's.
    ///
    /// Proxies only. Originals are the cache with its own policy.
    pub fn reclaim_strays(&mut self) -> Result<Reclaim> {
        if self.is_read_only() {
            return Ok(Reclaim::default());
        }
        let proxies = self.path.join(package::PROXY_DIR);
        let Ok(listing) = fs::read_dir(&proxies) else {
            return Ok(Reclaim::default());
        };
        let mut names: Vec<(String, PathBuf, u64)> = Vec::new();
        let settled = std::time::SystemTime::now() - std::time::Duration::from_secs(60 * 60);
        for entry in listing.flatten() {
            let path = entry.path();
            let Some(name) = path.file_name().and_then(|n| n.to_str()) else { continue };
            let Ok(meta) = entry.metadata() else { continue };
            if !meta.is_file() {
                continue;
            }
            if meta.modified().map(|at| at > settled).unwrap_or(true) {
                continue;
            }
            names.push((name.to_string(), path.clone(), meta.len()));
        }
        let strays = self.doc.stray_media_names(names.iter().map(|(n, _, _)| n.as_str()));
        let mut freed = Reclaim::default();
        for (name, path, size) in names {
            if strays.iter().any(|s| s == &name) && fs::remove_file(&path).is_ok() {
                freed.pictures += 1;
                freed.bytes += size;
            }
        }
        Ok(freed)
    }

    /// **How much room each picture takes on this device**, keyed by the
    /// first eighteen characters of its hash: its stored copy, its poster,
    /// every strip cut from it and its full-size original. What the Media
    /// window shows, because it is what deleting gives back.
    pub fn stored_sizes(&self) -> HashMap<String, u64> {
        let mut sizes: HashMap<String, u64> = HashMap::new();
        for dir in [package::PROXY_DIR, package::ORIGINALS_DIR] {
            let Ok(listing) = fs::read_dir(self.path.join(dir)) else { continue };
            for entry in listing.flatten() {
                let Some(name) = entry.file_name().to_str().map(str::to_string) else { continue };
                if name.len() < 18 || !name[..18].chars().all(|c| c.is_ascii_hexdigit()) {
                    continue;
                }
                let size = entry.metadata().map(|m| if m.is_file() { m.len() } else { 0 }).unwrap_or(0);
                *sizes.entry(name[..18].to_string()).or_insert(0) += size;
            }
        }
        sizes
    }

    /// **Delete pictures for real** — the Media window's Delete and Delete
    /// Unused. His ask, 2026-10-10 (`engine::shelf`). Every use goes, the
    /// record stays as a name, and the files go from this device now rather
    /// than waiting for the sweep. Returns what was freed and the names the
    /// relay should drop too.
    pub fn delete_media(&mut self, media: &[Id]) -> Result<(Reclaim, Vec<String>)> {
        if self.is_read_only() {
            return Ok((Reclaim::default(), Vec::new()));
        }
        let hashes = self.doc.delete_media(media);
        let proxies = self.path.join(package::PROXY_DIR);
        let originals = self.path.join(package::ORIGINALS_DIR);
        let mut freed = Reclaim { pictures: hashes.len(), bytes: 0 };
        let mut names = Vec::new();
        for hash in &hashes {
            let head: String = hash.chars().take(18).collect();
            let stem: String = hash.chars().take(32).collect();
            if let Ok(listing) = fs::read_dir(&proxies) {
                for entry in listing.flatten() {
                    let path = entry.path();
                    let Some(name) = path.file_name().and_then(|n| n.to_str()).map(str::to_string) else {
                        continue;
                    };
                    let Some((file_stem, ext)) = name.rsplit_once('.') else { continue };
                    let strip = ext.eq_ignore_ascii_case("strip") && file_stem.starts_with(head.as_str());
                    if file_stem != stem && !strip {
                        continue;
                    }
                    let size = entry.metadata().map(|m| m.len()).unwrap_or(0);
                    if fs::remove_file(&path).is_ok() {
                        freed.bytes += size;
                        names.push(name);
                    }
                }
            }
            freed.bytes += remove_by_stem(&originals, &stem);
        }
        self.save()?;
        Ok((freed, names))
    }

    /// **Every stored file filed under a name, gone.** For the shell that has
    /// just replaced a clip's bytes (`Doc::replace_media_bytes`) and holds
    /// the old hash in its hand: the old movie, its poster, and every strip
    /// cut from it — a trimmed strip's name begins with the first eighteen
    /// characters of the hash rather than the whole stem, which is why this
    /// matches on a prefix. Returns the names it removed, so the same list
    /// can be sent to the relay.
    pub fn remove_stored(&self, hash: &str) -> Vec<String> {
        let head: String = hash.chars().take(18).collect();
        let stem: String = hash.chars().take(32).collect();
        let proxies = self.path.join(package::PROXY_DIR);
        let Ok(listing) = fs::read_dir(&proxies) else {
            return Vec::new();
        };
        let mut gone = Vec::new();
        for entry in listing.flatten() {
            let path = entry.path();
            let Some(name) = path.file_name().and_then(|n| n.to_str()).map(str::to_string) else {
                continue;
            };
            let Some((file_stem, ext)) = name.rsplit_once('.') else { continue };
            let strip = ext.eq_ignore_ascii_case("strip") && file_stem.starts_with(head.as_str());
            if file_stem != stem && !strip {
                continue;
            }
            if fs::remove_file(&path).is_ok() {
                gone.push(name);
            }
        }
        gone
    }
}

/// Every log in a project, in a stable order. The order does not affect the
/// result — there is a test for that in the engine — but a stable one makes a
/// problem reproducible.
fn logs_in(changes_dir: &Path) -> Result<Vec<PathBuf>> {
    let mut logs: Vec<PathBuf> = match fs::read_dir(changes_dir) {
        Ok(entries) => entries
            .filter_map(|entry| entry.ok())
            .map(|entry| entry.path())
            .filter(|path| {
                path.file_name()
                    .and_then(|name| name.to_str())
                    .map(package::is_log_name)
                    .unwrap_or(false)
            })
            .collect(),
        Err(error) if error.kind() == io::ErrorKind::NotFound => Vec::new(),
        Err(error) => return Err(Error::Io(error)),
    };
    logs.sort();
    Ok(logs)
}

// ---- saving ------------------------------------------------------------

impl Project {
    /// Append everything since the last save to this session's log.
    ///
    /// Nothing already written is rewritten, so an interrupted save can lose at
    /// most what it was in the middle of adding — never what was already there.
    pub fn save(&mut self) -> Result<()> {
        if self.is_read_only() {
            return Err(Error::ReadOnly);
        }

        let ours: Vec<Change> = self.ours().into_iter().cloned().collect();
        // **Nothing new means nothing written — not even an empty file.**
        // Every launch starts a diary of its own, and this used to create it
        // whether or not anything was edited. Open a project to look something
        // up and close it again and you left a file behind; a year of that
        // across three devices is thousands of them, and iCloud moves a
        // thousand small files far worse than it moves a few big ones.
        //
        // The bound is checked rather than assumed: `persisted` counting past
        // the end would have panicked here, which is a crash on save.
        let fresh: &[Change] = if self.persisted < ours.len() {
            &ours[self.persisted..]
        } else {
            &[]
        };
        if fresh.is_empty() {
            return Ok(());
        }
        if self.log.exists() {
            append(&self.log, &encode_changes(fresh))?;
        } else {
            // Nothing unreadable is carried in here. Those lines are in logs of
            // their own that nobody rewrites, so they are already safe; copying
            // them would put a second copy in every project that was ever
            // opened by this build.
            let text = encode_log(FORMAT_VERSION, fresh, &[]);
            if let Some(parent) = self.log.parent() {
                fs::create_dir_all(parent)?;
            }
            fs::write(&self.log, text)?;
        }

        self.persisted = ours.len();

        // **The manifest follows the title.** It was written once, when the
        // project was made, and never again — so a film renamed afterwards kept
        // `Untitled 2` inside it for ever while its folder said `Call Her Back`.
        // His report, 2026-08-22, found through the MCP, which reads the
        // manifest rather than the list.
        //
        // `refresh_manifest` has existed and been tested since the package was
        // written; **nothing ever called it.** Only called when it has actually
        // fallen behind, so an ordinary save still writes one file.
        if self.manifest_lags() {
            self.refresh_manifest()?;
        }
        Ok(())
    }

    /// The project's title as the list holds it — the one a person sees.
    fn titled(&self) -> String {
        self.doc
            .project_id()
            .and_then(|id| self.doc.get(id))
            .and_then(|record| record.text(shotlister_engine::f::TITLE))
            .unwrap_or_default()
            .to_string()
    }

    /// Whether what is written inside the package still describes it.
    fn manifest_lags(&self) -> bool {
        let title = self.titled();
        let mark = self.doc.mark().unwrap_or_default();
        (!title.is_empty() && title != self.manifest.title)
            || self.manifest.project != self.doc.project_id()
            // **And the mark follows it too**, for the same reason the title
            // does: the switcher and the relay read the manifest and never open
            // the film, so a mark only written inside the document would be
            // invisible in exactly the two places a film is picked from.
            || mark.path != self.manifest.mark_path
            || mark.colour != self.manifest.mark_colour
    }

    /// Take in whatever the other devices have written since we last looked.
    ///
    /// This is the whole of sync on the reading side. A transport — a synced
    /// folder, a server, a cable — only has to make change files appear in the
    /// project; noticing them and folding them in is this, and it is the same
    /// on every platform because merging is the engine's.
    ///
    /// Safe to call at any time, including with unsaved work in hand: a change
    /// already known is skipped, and merging cannot reorder or discard anything.
    /// Whether anything has landed since the last look, without reading a
    /// single change.
    ///
    /// This is what makes checking often affordable: it asks the file system for
    /// sizes and dates, which is cheap enough to do on every window focus, and
    /// only a `pull` after a `true` does any real work.
    pub fn has_incoming(&self) -> bool {
        let Ok(logs) = logs_in(&self.path.join(package::CHANGES_DIR)) else {
            return false;
        };
        logs.iter()
            .filter(|log| **log != self.log)
            .any(|log| self.seen.get(log) != Some(&state_of(log)))
    }

    pub fn pull(&mut self) -> Result<Pull> {
        // Only the logs that have actually moved. Our own session log is skipped
        // outright: whatever is in it is already in hand.
        let mut changed = Vec::new();
        for log in logs_in(&self.path.join(package::CHANGES_DIR))? {
            if log == self.log {
                continue;
            }
            let state = state_of(&log);
            if self.seen.get(&log) != Some(&state) {
                changed.push((log, state));
            }
        }
        if changed.is_empty() {
            return Ok(Pull::default());
        }

        let before: HashSet<Stamp> = self.doc.changes().iter().map(|c| c.stamp).collect();
        let settled = self.doc.clashes();

        let mut fresh = Vec::new();
        let mut unreadable = 0;
        for (log, state) in changed {
            let text = match fs::read_to_string(&log) {
                Ok(text) => text,
                // A log being written by another device at this instant is not
                // an error, and is deliberately *not* recorded as seen. We will
                // get it next time.
                Err(_) => continue,
            };
            let Ok(parsed) = decode_log(&text) else {
                continue;
            };
            self.seen.insert(log, state);
            unreadable += parsed.preserved.len();
            fresh.extend(
                parsed
                    .changes
                    .into_iter()
                    .filter(|change| !before.contains(&change.stamp)),
            );
        }

        self.unreadable = unreadable;
        if fresh.is_empty() {
            return Ok(Pull::default());
        }

        let mut devices: Vec<DeviceId> = fresh.iter().map(|c| c.stamp.device).collect();
        devices.sort();
        devices.dedup();

        let merged = fresh.len();
        self.doc.merge(fresh);

        // Only what this pull actually brought about. A disagreement already on
        // screen should not be announced a second time.
        let clashes = self
            .doc
            .clashes()
            .into_iter()
            .filter(|clash| !settled.contains(clash))
            .collect();

        Ok(Pull {
            merged,
            devices,
            clashes,
        })
    }

    /// Bring the manifest up to date with the list — the title shown in a Finder
    /// window should not lag behind the one in the app.
    pub fn refresh_manifest(&mut self) -> Result<()> {
        if self.is_read_only() {
            return Err(Error::ReadOnly);
        }
        let title = self.titled();
        if !title.is_empty() {
            self.manifest.title = title;
        }
        self.manifest.project = self.doc.project_id();
        let mark = self.doc.mark().unwrap_or_default();
        self.manifest.mark_path = mark.path;
        self.manifest.mark_colour = mark.colour;
        write_whole(
            &self.path.join(package::MANIFEST),
            self.manifest.encode().as_bytes(),
        )?;
        Ok(())
    }
}

/// **Write a whole file the safe way: beside, then swap.** Ref 187.
///
/// Two files here were written straight over the top of themselves, and both
/// have the same failure: the machine goes down mid-write and what is left is
/// half a file.
///
/// - **The manifest** is a project's birth certificate. Truncated, the project
///   will not open at all, anywhere.
/// - **A picture** is written once and then guarded by "does this path already
///   exist?", so a half-written one is treated as correct *forever* and never
///   rewritten. One silently broken photograph, on every device it syncs to.
///
/// Writing to a temporary name in the same folder and renaming over the target
/// makes the swap atomic on macOS — the reader sees either the old whole file
/// or the new whole file, never half of one. Same folder matters: a rename
/// across filesystems is a copy, and a copy is exactly what this avoids.
///
/// The temporary carries the process id so two writers cannot collide on the
/// scratch name, and it is removed if the rename fails, rather than left as
/// litter beside the real file.
pub fn write_whole(path: &Path, bytes: &[u8]) -> io::Result<()> {
    let scratch = match path.file_name() {
        Some(name) => path.with_file_name(format!(
            ".{}.{}.writing",
            name.to_string_lossy(),
            std::process::id()
        )),
        None => return fs::write(path, bytes),
    };
    if let Err(e) = fs::write(&scratch, bytes) {
        let _ = fs::remove_file(&scratch);
        return Err(e);
    }
    if let Err(e) = fs::rename(&scratch, path) {
        let _ = fs::remove_file(&scratch);
        return Err(e);
    }
    Ok(())
}

/// Whether a stored file is whole — used before trusting one that is already
/// there.
///
/// Media here is addressed by the hash of its contents, which means the file
/// can check itself: if what is on disk hashes to the name it is filed under,
/// it is the file. **Only its length is checked**, not the hash — hashing every
/// picture on every write would read the whole media folder to save a case that
/// happens once in a thousand crashes. A torn write is nearly always short, and
/// a length that matches is enough to keep the common path fast.
fn already_whole(path: &Path, bytes: &[u8]) -> bool {
    fs::metadata(path).map(|m| m.len() as usize).ok() == Some(bytes.len())
}

fn append(path: &Path, text: &str) -> io::Result<()> {
    use std::io::Write;
    let mut file = fs::OpenOptions::new().append(true).create(true).open(path)?;
    file.write_all(text.as_bytes())
}

// ---- media -------------------------------------------------------------

impl Project {
    fn media_path(&self, relative: String) -> PathBuf {
        self.path.join(relative)
    }

    pub fn write_proxy(&self, hash: &str, extension: &str, bytes: &[u8]) -> Result<()> {
        let path = self.media_path(package::proxy_name(hash, extension));
        if let Some(parent) = path.parent() {
            fs::create_dir_all(parent)?;
        }
        // Content-addressed, so a file already there under this name is the
        // right file — **unless it is short**, which means a write was torn
        // half-way. That case used to be permanent: the existence check said
        // yes and nothing ever rewrote it.
        if !path.exists() || !already_whole(&path, bytes) {
            write_whole(&path, bytes)?;
        }
        Ok(())
    }

    /// One stored file under one name, gone. Absent is not an error.
    pub fn remove_proxy(&self, hash: &str, extension: &str) -> Result<()> {
        match fs::remove_file(self.media_path(package::proxy_name(hash, extension))) {
            Ok(()) => Ok(()),
            Err(error) if error.kind() == io::ErrorKind::NotFound => Ok(()),
            Err(error) => Err(Error::Io(error)),
        }
    }

    pub fn read_proxy(&self, hash: &str, extension: &str) -> Result<Option<Vec<u8>>> {
        read_if_present(&self.media_path(package::proxy_name(hash, extension)))
    }

    /// The stored file for a hash, **whatever extension it was written under**,
    /// with that extension.
    ///
    /// Readers used to ask by the name a person gave the file — and a picture
    /// re-encoded on the way in is stored as `.png` while still called
    /// `photo.jpeg`, so the ask missed. Worse, a shell that once wrote a PDF's
    /// first page as a picture left `deck.pdf` stored as `.png`: asking for
    /// `.pdf` returned nothing, and a viewer drew an empty black page. A file
    /// is named by its contents here; what it is called is a label. So: find
    /// the file, then say what it turned out to be.
    ///
    /// **One name can hold two files.** A clip is stored twice under one hash:
    /// the movie, and the still that stands for it wherever a picture is drawn.
    /// `read_dir` hands entries back in no defined order, so asking for a clip
    /// used to return the poster about half the time and a player handed a
    /// poster draws a black rectangle. `prefer` settles it: the extension the
    /// caller asked for wins; failing that a moving picture beats a still,
    /// because the still is only ever the stand-in for one; failing that the
    /// order is alphabetical, so a project answers the same way twice.
    pub fn find_proxy(
        &self,
        hash: &str,
        prefer: Option<&str>,
    ) -> Result<Option<(String, Vec<u8>)>> {
        // The stored name is the hash's first 32 characters (package::short).
        let stem_wanted: String = hash.chars().take(32).collect();
        let dir = self.media_path(shotlister_engine::package::PROXY_DIR.to_string());
        let entries = match fs::read_dir(&dir) {
            Ok(entries) => entries,
            Err(_) => return Ok(None),
        };
        let mut candidates: Vec<(String, PathBuf)> = Vec::new();
        for entry in entries.flatten() {
            let path = entry.path();
            let stem = path.file_stem().map(|s| s.to_string_lossy().to_string());
            if stem.as_deref() == Some(stem_wanted.as_str()) {
                let ext = path
                    .extension()
                    .map(|e| e.to_string_lossy().to_string())
                    .unwrap_or_default();
                candidates.push((ext, path));
            }
        }
        // Alphabetical first so the tie-break is settled, then by preference —
        // `sort_by_key` is stable, so the alphabetical order survives inside a
        // rank.
        candidates.sort_by(|a, b| a.0.to_lowercase().cmp(&b.0.to_lowercase()));
        let asked = prefer
            .map(|e| e.trim().trim_start_matches('.').to_lowercase())
            .filter(|e| !e.is_empty());
        // **A poster is a still, whichever still it is.** Posters were PNG
        // until 2026-09-15 and are JPEG since, and every reader that asks for
        // a clip's still by name asks for one or the other — so a still
        // format asked for by the other still format's name ranks above the
        // movie, or a reader wanting the poster of a clip stored the other
        // way would be handed the movie and draw a black rectangle.
        let still = |ext: &str| matches!(ext, "png" | "jpg" | "jpeg");
        let asked_still = asked.as_deref().map(still).unwrap_or(false);
        candidates.sort_by_key(|(ext, _)| {
            let lower = ext.to_lowercase();
            if asked.as_deref() == Some(lower.as_str()) {
                0
            } else if asked_still && still(&lower) {
                1
            } else if MediaKind::guess_from_name(&lower).is_moving() {
                2
            } else {
                3
            }
        });
        for (ext, path) in candidates {
            if let Some(bytes) = read_if_present(&path)? {
                return Ok(Some((ext, bytes)));
            }
        }
        Ok(None)
    }

    pub fn write_original(&self, hash: &str, extension: &str, bytes: &[u8]) -> Result<()> {
        let path = self.media_path(package::original_name(hash, extension));
        if let Some(parent) = path.parent() {
            fs::create_dir_all(parent)?;
        }
        if !path.exists() || !already_whole(&path, bytes) {
            write_whole(&path, bytes)?;
        }
        Ok(())
    }

    pub fn read_original(&self, hash: &str, extension: &str) -> Result<Option<Vec<u8>>> {
        read_if_present(&self.media_path(package::original_name(hash, extension)))
    }

    // ---- the script ----------------------------------------------------
    //
    // **A script travels.** Until 2026-09-15 a revision's text and its PDF
    // were written to `originals/`, which the relay never carries — and
    // nobody noticed, because iCloud carried the whole folder. The morning
    // the films became relay-only, the script stopped reaching his laptop
    // (his report, that evening). It is filed with the proxies now: the
    // sync plan sends what is here and fetches what a revision names
    // (`missing_scripts`), and the engine counts a revision's hash as a name
    // so a sweep never takes it.

    pub fn write_script(&self, hash: &str, extension: &str, bytes: &[u8]) -> Result<()> {
        self.write_proxy(hash, extension, bytes)
    }

    /// The proxies first; then `originals/`, for a film written before the
    /// script travelled, and the copy is adopted into the proxies on the way
    /// past so it travels from now on.
    pub fn read_script(&self, hash: &str, extension: &str) -> Result<Option<Vec<u8>>> {
        if let Some(bytes) = self.read_proxy(hash, extension)? {
            return Ok(Some(bytes));
        }
        let Some(bytes) = self.read_original(hash, extension)? else {
            return Ok(None);
        };
        if !self.is_read_only() {
            let _ = self.write_proxy(hash, extension, &bytes);
        }
        Ok(Some(bytes))
    }

    /// Every revision's text and PDF still sitting only in `originals/`,
    /// copied into the proxies. Run at open; nothing to do the second time.
    pub fn adopt_scripts(&self) -> Result<usize> {
        if self.is_read_only() {
            return Ok(0);
        }
        let mut moved = 0;
        for revision in self.doc.revisions() {
            for ext in ["txt", "pdf"] {
                if self.read_proxy(&revision.hash, ext)?.is_some() {
                    continue;
                }
                if let Some(bytes) = self.read_original(&revision.hash, ext)? {
                    self.write_proxy(&revision.hash, ext, &bytes)?;
                    moved += 1;
                }
            }
        }
        Ok(moved)
    }

    /// The stems of revisions whose text or PDF this device does not hold.
    /// What the sync plan asks the relay for, beside `missing_media`. A
    /// revision that never had a PDF is asked for on every sync and costs
    /// nothing: the plan only fetches names the relay has.
    pub fn missing_scripts(&self) -> Vec<String> {
        self.doc
            .revisions()
            .into_iter()
            .filter(|r| {
                !(matches!(self.read_proxy(&r.hash, "txt"), Ok(Some(_)))
                    && matches!(self.read_proxy(&r.hash, "pdf"), Ok(Some(_))))
            })
            .map(|r| r.hash.chars().take(32).collect())
            .collect()
    }

    /// **The stems of current Print Frames this device does not hold.** What
    /// the sync plan asks the relay for, beside `missing_media` (2026-10-16).
    ///
    /// A bake is a picture no media record names, so `missing_media` never
    /// asked for one: the Mac sent every bake to the relay and the phone
    /// never brought one down, which is why the iPhone drew no Print Frames
    /// for a real synced film (Call Her Back: 38 bakes on the relay, none on
    /// the phone). Only current bakes — a stale one is never drawn.
    pub fn missing_print_frames(&self) -> Vec<String> {
        use shotlister_engine::store::Kind;
        self.doc
            .store()
            .of_kind(&Kind::Shot)
            .iter()
            .filter_map(|shot| self.doc.print_frame_picture(shot.id))
            .filter(|b| !self.media_path(package::proxy_name(&b.hash, &b.ext)).is_file())
            .map(|b| b.stem())
            .collect()
    }

    /// Keep the originals inside a budget, dropping the least recently used.
    ///
    /// Proxies are never touched — every device keeps all of them, permanently,
    /// which is what makes the app work with no signal. This is only the
    /// full-resolution copies, which are a cache and are always re-fetchable
    /// from wherever they came from.
    ///
    /// The rule about *what* to drop is the engine's, so every platform makes
    /// the same call; this is the part that has to touch a disk. Returns how
    /// many bytes went.
    pub fn prune_originals(&self, budget_bytes: u64) -> Result<u64> {
        let dir = self.path.join(package::ORIGINALS_DIR);
        let mut entries = Vec::new();
        let mut files: HashMap<Id, PathBuf> = HashMap::new();

        let listing = match fs::read_dir(&dir) {
            Ok(listing) => listing,
            Err(error) if error.kind() == io::ErrorKind::NotFound => return Ok(0),
            Err(error) => return Err(Error::Io(error)),
        };

        for entry in listing.flatten() {
            let path = entry.path();
            let Ok(meta) = entry.metadata() else { continue };
            if !meta.is_file() {
                continue;
            }
            // Originals are named by their contents, so the file name is the
            // identity — no need to ask the document about any of them.
            let Some(stem) = path.file_stem().and_then(|s| s.to_str()) else {
                continue;
            };
            let Some(id) = Id::from_hex(&format!("{stem:0<32}")) else {
                continue;
            };
            let used = meta
                .accessed()
                .or_else(|_| meta.modified())
                .ok()
                .and_then(|when| when.duration_since(UNIX_EPOCH).ok())
                .map(|d| d.as_secs())
                .unwrap_or(0);
            entries.push(CacheEntry {
                media: id,
                bytes: meta.len(),
                last_used: used,
                pinned: false,
            });
            files.insert(id, path);
        }

        let plan = plan_cache(&entries, budget_bytes);
        let mut freed = 0;
        for id in plan.evict {
            let Some(path) = files.get(&id) else { continue };
            let size = fs::metadata(path).map(|m| m.len()).unwrap_or(0);
            if fs::remove_file(path).is_ok() {
                freed += size;
            }
        }
        Ok(freed)
    }

    /// Frames whose picture is not here — a record pointing at bytes the
    /// folder has not got.
    ///
    /// The record for a picture and the picture itself are two different files
    /// in a project, and they travel separately: a change log is a few hundred
    /// bytes and a photograph is a few hundred thousand, so the record
    /// routinely lands on the second device first. Usually the picture follows
    /// a moment later. Sometimes it never does — a folder copied without its
    /// media, a device that went offline mid-sync, or (in Daybreak's case) an
    /// early build that wrote records this one cannot account for.
    ///
    /// So the app can say *which* frames are hollow rather than drawing a grey
    /// box and leaving somebody to guess. It is deliberately a question about
    /// this folder at this moment: a frame listed here may well fill itself in
    /// on the next sync, and nothing here deletes anything.
    pub fn missing_media(&self) -> Vec<Id> {
        use shotlister_engine::doc::f;
        use shotlister_engine::store::Kind;
        self.doc
            .store()
            .of_kind(&Kind::Media)
            .iter()
            // Deleted from the Media window: nothing is missing, it is gone,
            // and no device should go looking for it. (`engine::shelf`)
            .filter(|record| !self.doc.media_is_gone(record.id))
            .filter(|record| {
                let Some(hash) = record.text(f::HASH) else {
                    // A record with no hash at all cannot name a file, so it
                    // can never be satisfied.
                    return true;
                };
                let wanted = record
                    .text(f::FILENAME)
                    .and_then(|name| name.rsplit('.').next())
                    .filter(|ext| !ext.is_empty());
                !matches!(self.find_proxy(hash, wanted), Ok(Some(_)))
            })
            .map(|record| record.id)
            .collect()
    }

    /// How much room the full-resolution copies are taking.
    pub fn originals_bytes(&self) -> u64 {
        let dir = self.path.join(package::ORIGINALS_DIR);
        let Ok(listing) = fs::read_dir(dir) else { return 0 };
        listing
            .flatten()
            .filter_map(|entry| entry.metadata().ok())
            .filter(|meta| meta.is_file())
            .map(|meta| meta.len())
            .sum()
    }

    /// **Register the scanned rooms the phone left in the project folder.**
    ///
    /// The phone writes a scan as two files sharing a name into
    /// `locations/<folder>/scans/` — the `.usdz` you turn over and the `.json`
    /// a floor plan is built from — and until this existed nothing else knew
    /// they were there. The Mac found them by listing that folder, which is why
    /// a scan was only ever visible on a machine holding the folder: the phone
    /// that made it could not show it back, and the web could not know the room
    /// had been scanned at all.
    ///
    /// **This does not move the files and does not touch that folder.** The
    /// phone owns it and one writer per path is the rule. What happens is that
    /// the bytes are copied into the media store under their own hash, exactly
    /// as a photograph is, and the document gains a reference — so sync carries
    /// them without being taught anything new. The cost is a second copy of
    /// each scan; on his own film that is 873 KB against 599 MB of photographs.
    ///
    /// **Safe to call as often as you like.** A file already registered is
    /// recognised by its contents, so nothing is added twice and a scan that
    /// has been deleted from the document does not come back — the attachment
    /// is what is checked, not the file.
    ///
    /// Returns how many scans were newly registered.
    pub fn register_scans(&mut self) -> Result<usize> {
        self.register_beside_locations("scans", &|ext| match ext {
            "usdz" => Some(MediaKind::Scan),
            "json" => Some(MediaKind::ScanShape),
            _ => None,
        })
    }

    /// **And the papers pinned to a location on the phone.** 2026-09-15.
    ///
    /// The phone drops a permit or a floor plan into
    /// `locations/<folder>/attachments/`, and until this existed that folder
    /// was the only place it lived — the Mac listed it, the phone listed it,
    /// and neither device could see what the other had pinned once the films
    /// left iCloud. The same bargain as the scans: the bytes are filed under
    /// their hash and the location gains a use of them, so sync carries them
    /// without being taught anything. Every file counts, whatever it is
    /// called, and it is an attachment (`MediaKind::Other`) rather than a
    /// picture, so the photo wall never draws a PDF as a grey rectangle.
    pub fn register_attachments(&mut self) -> Result<usize> {
        self.register_beside_locations("attachments", &|_| Some(MediaKind::Other))
    }

    /// One folder beside each location, its files registered as media of the
    /// kind `kind_for` says — or skipped, when it says none.
    fn register_beside_locations(
        &mut self,
        sub: &str,
        kind_for: &dyn Fn(&str) -> Option<MediaKind>,
    ) -> Result<usize> {
        use shotlister_engine::doc::f;
        use shotlister_engine::hash::sha256;

        let mut added = 0;
        // Names given to rooms in this run, by place and file, so the second
        // half of a room takes the first half's.
        let mut fresh: HashMap<(Id, String), String> = HashMap::new();
        let places: Vec<(Id, String)> = self
            .doc
            .locations_in_order()
            .into_iter()
            .filter_map(|id| {
                let record = self.doc.get(id)?;
                // **The folder when it has one, its own id when it has not** —
                // Ref 305's rule, and `shared/FileNames.swift` is the copy the
                // two apps compile. A location made on the Mac has no folder
                // and its scans still land under its id.
                let folder = record.text(f::FOLDER).unwrap_or("").trim().to_string();
                let named = if folder.is_empty() { id.0.to_string() } else { folder };
                Some((id, named))
            })
            .collect();

        for (place, named) in places {
            let dir = self.path.join("locations").join(&named).join(sub);
            let Ok(listing) = fs::read_dir(&dir) else { continue };
            let mut files: Vec<(PathBuf, MediaKind, String)> = listing
                .flatten()
                .map(|entry| entry.path())
                .filter(|path| path.is_file())
                .filter_map(|path| {
                    let name = path.file_name()?.to_str()?;
                    if name.starts_with('.') {
                        return None;
                    }
                    let ext = path
                        .extension()
                        .and_then(|e| e.to_str())
                        .map(str::to_lowercase)
                        .unwrap_or_default();
                    let kind = kind_for(&ext)?;
                    Some((path.clone(), kind, ext))
                })
                .collect();
            // Read in a settled order so two runs on one folder produce the
            // same document rather than the same files in a different order.
            files.sort_by(|a, b| a.0.cmp(&b.0));

            for (path, kind, ext) in files {
                let Ok(bytes) = fs::read(&path) else { continue };
                let Some(name) = path.file_name().and_then(|n| n.to_str()) else { continue };
                let hash = sha256(&bytes);

                // **Already on this location? Then there is nothing to do** —
                // including when he has deleted it, which is a decision and not
                // a gap to fill. Checked before anything is written.
                let known = self.doc.media_with_hash(hash);
                if let Some(media) = known {
                    if self.doc.media_of(place).contains(&media) {
                        continue;
                    }
                }

                let extension = if ext.is_empty() { "bin" } else { ext.as_str() };
                self.write_proxy(&hash.to_hex(), extension, &bytes)?;
                let media = self.doc.add_media(hash, kind, 0, 0, bytes.len() as u64, name);
                // `add_media` recognises the file by its contents and may hand
                // back one that arrived as something else — a `.json` dropped
                // on a scene, say. The room's own kind is the truer answer, and
                // saying it again costs one field.
                self.doc.set(media, f::MEDIA_KIND, shotlister_engine::Value::text(kind.as_str()));
                // This use wears the file's own name, which is what a list of
                // papers shows — except **a room the phone named for the
                // moment it was taken**, which is named for where it was
                // taken (`scan_name`): the house, the room, which scan. Both
                // halves wear the one name, and a half arriving after the
                // other takes the name the first was given.
                let named = match (sub, path.file_stem().and_then(|s| s.to_str())) {
                    ("scans", Some(stem)) if stem.starts_with("RoomScan_") => {
                        let known = self.doc.scans_of(place).into_iter().find(|s| s.file == stem).map(|s| s.name);
                        let base = match known.or_else(|| fresh.get(&(place, stem.to_string())).cloned()) {
                            Some(base) => base,
                            None => {
                                let seen = rooms_seen(&path.with_extension("json"));
                                let number = self.doc.scans_of(place).len() + 1;
                                let base = self.doc.scan_name_at(place, number, &seen);
                                fresh.insert((place, stem.to_string()), base.clone());
                                base
                            }
                        };
                        format!("{base}.{extension}")
                    }
                    _ => name.to_string(),
                };
                let held = self.doc.attach_media(place, media, "");
                self.doc.set_media_ref_name(held, &named);
                added += 1;
            }
        }
        Ok(added)
    }

    /// Drop an original to reclaim space. The proxy stays, so the shot still
    /// shows something — losing the picture entirely would be worse than losing
    /// the resolution.
    pub fn evict_original(&self, hash: &str, extension: &str) -> Result<()> {
        let path = self.media_path(package::original_name(hash, extension));
        match fs::remove_file(path) {
            Ok(()) => Ok(()),
            Err(error) if error.kind() == io::ErrorKind::NotFound => Ok(()),
            Err(error) => Err(Error::Io(error)),
        }
    }
}

fn read_if_present(path: &Path) -> Result<Option<Vec<u8>>> {
    match fs::read(path) {
        Ok(bytes) => Ok(Some(bytes)),
        Err(error) if error.kind() == io::ErrorKind::NotFound => Ok(None),
        Err(error) => Err(Error::Io(error)),
    }
}

/// The rooms RoomPlan named inside a scan (`sections`), read from its
/// measurements: `kitchen`, `livingRoom`. Empty when there are none.
fn rooms_seen(json: &Path) -> Vec<String> {
    fs::read_to_string(json)
        .ok()
        .and_then(|text| shotlister_engine::room::read(&text))
        .map(|plan| plan.rooms.into_iter().map(|(name, _)| name).collect())
        .unwrap_or_default()
}
