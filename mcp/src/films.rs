//! Where the films are, as far as the tools are concerned.
//!
//! **Why this exists.** The tool layer used to hold a `storage::Project` — a
//! folder on a disk — and so the whole MCP could only ever run on a Mac with
//! that folder mounted. His ask, 2026-09-01: the MCP should run somewhere any
//! AI can reach it, not just on the machine he happens to be sitting at.
//!
//! A Cloudflare Worker has no disk. It has the relay's bucket, which holds the
//! same change logs the folder does, because **a browser is not a new kind of
//! thing — it is another device** (`web/src/lib.rs`). So the difference between
//! the two homes is small and it is exactly this trait: how a film is fetched,
//! how it is written back, and whether there is a filesystem at all.
//!
//! Everything above this line — all twenty-two tools, every rule, every
//! sentence the AI reads — is shared. That is the point. Two copies of the tool
//! layer would drift within a week, and the one nobody was sitting in front of
//! would be the one that drifted.

use shotlister_engine::Doc;

/// One open film, and the world around it.
///
/// Implementations: `Disk` below (a `.shotlist` folder on a Mac) and
/// `mcpweb::Bucket` (change logs in and out of the relay's bucket).
pub trait Films {
    /// Open a film. On a Mac this is a path; in the worker it is a film's id,
    /// and the logs are already in hand by the time this is called.
    fn open(&mut self, reference: &str) -> Result<(), String>;

    fn doc(&self) -> Result<&Doc, String>;
    fn doc_mut(&mut self) -> Result<&mut Doc, String>;

    /// What the film is called.
    fn title(&self) -> String;

    /// Where it is, said the way that home says it: a path, or an id.
    fn whereabouts(&self) -> String;

    /// Whether this film may be changed at all — a locked package on a Mac, a
    /// viewer rather than an editor on the web.
    fn read_only(&self) -> bool;

    /// Write out whatever has been changed since the last call.
    fn save(&mut self) -> Result<(), String>;

    /// Read a file the person named. **A worker has no filesystem**, and says
    /// so in one line rather than pretending.
    fn read_bytes(&self, path: &str) -> Result<Vec<u8>, String>;

    /// Write a file where the person said. Same caveat.
    fn write_bytes(&mut self, path: &str, bytes: &[u8]) -> Result<(), String>;

    /// Keep a picture's bytes under its own hash, where the film keeps them.
    fn keep_media(&mut self, hash: &str, extension: &str, bytes: &[u8]) -> Result<(), String>;

    /// A file the film already keeps, by the name a plan gives it —
    /// `<hash>.<ext>`. The worker holds logs, not files, and says so; the
    /// portal fetches what it needs itself.
    fn media_bytes(&self, _name: &str) -> Result<Vec<u8>, String> {
        Err(no_filesystem("Reading the project's own files"))
    }

    /// **Delete pictures for real** (the Media window's Delete, SL-1687):
    /// every use goes, the record stays as a name, and the bytes go — from
    /// this host now where it has files, and from every device and the relay
    /// at their next sync. Answers how many and the bytes freed here.
    fn delete_media(&mut self, media: &[shotlister_engine::Id]) -> Result<(usize, u64), String> {
        let gone = self.doc_mut()?.delete_media(media).len();
        self.save()?;
        Ok((gone, 0))
    }

    /// An SVG made into a PNG, where this host can draw one. None: hand the
    /// SVG on and let whoever is asking draw it.
    fn rasterize(&self, _svg: &str, _width: u32) -> Option<Vec<u8>> {
        None
    }
}

/// The message every host gives when asked for something only a Mac has.
pub fn no_filesystem(what: &str) -> String {
    format!("{what} needs Shotlister on your Mac. This one has no files.")
}

// ------------------------------------------------------------------ on a Mac

#[cfg(feature = "disk")]
mod disk {
    use super::Films;
    use shotlister_engine::{DeviceId, Doc};
    use shotlister_storage::{self as storage, Project};
    use std::path::{Path, PathBuf};

    /// A film in a folder — the only home there was until 2026-09-01.
    pub struct Disk {
        device: DeviceId,
        /// Which machine this is, as opposed to which name it writes under.
        /// Ref 186. Zero means it did not say, and then nothing is claimed.
        installation: u64,
        project: Option<Project>,
    }

    impl Disk {
        pub fn new(device: DeviceId, installation: u64) -> Disk {
            Disk {
                device,
                installation,
                project: None,
            }
        }

        fn project(&self) -> Result<&Project, String> {
            self.project
                .as_ref()
                .ok_or_else(|| "No project is open. Use open_project first.".to_string())
        }

        fn project_mut(&mut self) -> Result<&mut Project, String> {
            self.project
                .as_mut()
                .ok_or_else(|| "No project is open. Use open_project first.".to_string())
        }
    }

    impl Films for Disk {
        fn open(&mut self, reference: &str) -> Result<(), String> {
            let path = PathBuf::from(reference);
            let project = storage::open_as(&path, self.device, self.installation)
                .map_err(|e| e.message())?;
            self.project = Some(project);
            Ok(())
        }

        fn doc(&self) -> Result<&Doc, String> {
            Ok(self.project()?.doc())
        }

        fn doc_mut(&mut self) -> Result<&mut Doc, String> {
            Ok(self.project_mut()?.doc_mut())
        }

        fn title(&self) -> String {
            self.project
                .as_ref()
                .map(|p| p.manifest().title.clone())
                .unwrap_or_default()
        }

        fn whereabouts(&self) -> String {
            self.project
                .as_ref()
                .map(|p| p.path().display().to_string())
                .unwrap_or_default()
        }

        fn read_only(&self) -> bool {
            self.project.as_ref().map(|p| p.is_read_only()).unwrap_or(true)
        }

        fn save(&mut self) -> Result<(), String> {
            self.project_mut()?.save().map_err(|e| e.message())
        }

        fn delete_media(&mut self, media: &[shotlister_engine::Id]) -> Result<(usize, u64), String> {
            let (freed, _) = self.project_mut()?.delete_media(media).map_err(|e| e.message())?;
            Ok((freed.pictures, freed.bytes))
        }

        fn read_bytes(&self, path: &str) -> Result<Vec<u8>, String> {
            std::fs::read(path).map_err(|e| format!("Could not read {path}: {e}"))
        }

        fn write_bytes(&mut self, path: &str, bytes: &[u8]) -> Result<(), String> {
            std::fs::write(Path::new(path), bytes).map_err(|e| e.to_string())
        }

        fn keep_media(&mut self, hash: &str, extension: &str, bytes: &[u8]) -> Result<(), String> {
            self.project_mut()?
                .write_proxy(hash, extension, bytes)
                .map_err(|e| e.message())
        }

        fn media_bytes(&self, name: &str) -> Result<Vec<u8>, String> {
            let (stem, ext) = name.rsplit_once('.').unwrap_or((name, "png"));
            let project = self.project()?;
            // A clip's poster is `.jpg`, or `.png` in a film written before
            // 2026-09-15 — every reader takes either.
            for ext in [ext, if ext == "jpg" { "png" } else { ext }] {
                if let Ok(Some(bytes)) = project.read_proxy(stem, ext) {
                    return Ok(bytes);
                }
            }
            Err(format!("The film has no file {name}."))
        }

        /// **QuickLook draws the SVG** — WebKit's own renderer, already on
        /// every Mac, so the picture needs nothing added to the build. It
        /// draws a square; the square is cut back to the picture's own shape.
        fn rasterize(&self, svg: &str, width: u32) -> Option<Vec<u8>> {
            use std::process::Command;
            // One folder a picture: two drawn at once (two chats, two
            // checks) must not clear each other's away.
            static NEXT: std::sync::atomic::AtomicUsize = std::sync::atomic::AtomicUsize::new(0);
            let n = NEXT.fetch_add(1, std::sync::atomic::Ordering::Relaxed);
            let dir = std::env::temp_dir().join(format!("shotlister-mcp-picture-{}-{n}", std::process::id()));
            let _ = std::fs::remove_dir_all(&dir);
            std::fs::create_dir_all(&dir).ok()?;
            let file = dir.join("plan.svg");
            let size = svg_size(svg);
            // **Said at half its size, in a square, drawn at twice that.**
            // QuickLook draws an SVG at two pixels a point into a square;
            // asked for one already as wide as the square, it zoomed in and
            // cut the plan off (2026-09-30, seen). So the picture is centred
            // in a square said at half the size, and `sips`, which only ever
            // cuts from the middle, cuts it back out exactly.
            // Whatever the picture's own units — the plan's pixels, or the
            // sheet's points drawn at a width (Back to Paper, Batch 2) — its
            // viewBox is squared in those units and its size said in pixels.
            let squared = match (size, view_box(svg)) {
                (Some((w, h)), Some((vx, vy, vw, vh))) => {
                    let (side, vside) = (w.max(h), vw.max(vh));
                    let head_end = svg.find('>').unwrap_or(0);
                    let head = &svg[..head_end];
                    let head = replace_attr(head, "viewBox", &format!("{} {} {vside} {vside}", vx - (vside - vw) / 2.0, vy - (vside - vh) / 2.0));
                    let head = replace_attr(&head, "width", &format!("{}", side / 2.0));
                    let head = replace_attr(&head, "height", &format!("{}", side / 2.0));
                    format!("{head}{}", &svg[head_end..])
                }
                _ => svg.to_string(),
            };
            std::fs::write(&file, squared).ok()?;
            let side = size.map(|(w, h)| w.max(h)).unwrap_or(width as f64).round().max(1.0) as u32;
            let ok = Command::new("/usr/bin/qlmanage")
                .args(["-t", "-s", &side.to_string(), "-o"])
                .arg(&dir)
                .arg(&file)
                .output()
                .map(|o| o.status.success())
                .unwrap_or(false);
            let png = dir.join("plan.svg.png");
            if ok {
                if let Some((w, h)) = size {
                    let _ = Command::new("/usr/bin/sips")
                        .args(["-c", &(h.round() as u32).to_string(), &(w.round() as u32).to_string()])
                        .arg(&png)
                        .output();
                }
            }
            let bytes = std::fs::read(&png).ok().filter(|b| b.len() > 100);
            let _ = std::fs::remove_dir_all(&dir);
            bytes
        }
    }

    /// The picture's viewBox, in its own units.
    fn view_box(svg: &str) -> Option<(f64, f64, f64, f64)> {
        let head = &svg[..svg.find('>')?];
        let at = head.find(" viewBox=\"")? + 10;
        let n: Vec<f64> = head[at..].split('"').next()?.split_whitespace().filter_map(|v| v.parse().ok()).collect();
        (n.len() == 4 && n[2] > 0.0 && n[3] > 0.0).then(|| (n[0], n[1], n[2], n[3]))
    }

    /// The tag with one attribute's value replaced.
    fn replace_attr(head: &str, name: &str, value: &str) -> String {
        let key = format!(" {name}=\"");
        let Some(at) = head.find(&key) else { return head.to_string() };
        let from = at + key.len();
        let Some(len) = head[from..].find('"') else { return head.to_string() };
        format!("{}{value}{}", &head[..from], &head[from + len..])
    }

    /// The `width` and `height` an SVG's root says it is.
    fn svg_size(svg: &str) -> Option<(f64, f64)> {
        let head = &svg[..svg.find('>')?];
        let attr = |name: &str| -> Option<f64> {
            let at = head.find(&format!(" {name}=\""))? + name.len() + 3;
            head[at..].split('"').next()?.trim_end_matches("px").parse().ok()
        };
        Some((attr("width")?, attr("height")?))
    }
}

#[cfg(feature = "disk")]
pub use disk::Disk;
