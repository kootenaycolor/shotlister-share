//! The last few things the app does that a chat could not: redo, naming a
//! script draft, and tying a shot to lines of a film's screenplay. The
//! Diagram's tools are in `diagram.rs`.

use super::{Server, Tool};
use crate::films::Films;
use crate::json::Json;
use crate::tools;
use shotlister_engine::playties::Draft;
use shotlister_engine::{Doc, Id};

pub(super) const TOOLS: &[Tool] = &[
    Tool {
        name: "redo",
        description: "Put back what undo just took back. Like undo, only within this connector's own session — the web connector has neither yet.",
        arguments: &[],
    },
    Tool {
        name: "rename_draft",
        description: "Rename a script draft the project has taken in — `draft` as revisions names it, or `latest`.",
        arguments: &[("draft", "string", true), ("name", "string", true)],
    },
    Tool {
        name: "tie_lines",
        description: "On a film (a screenplay taken in as a draft): tie a shot to lines of the script by quoting the words, so the script shows the shot's mark beside them. The words are looked for in the shot's own scene first, then anywhere; blank space and line breaks match loosely. A shot can hold several stretches: mode=add adds these words, mode=remove lets just these go, the default replace makes them all it holds; an empty text lets every line go. The tie keeps its words, so a new draft finds them again where they moved, and one that cuts them reports them (script_lines) rather than moving the tie. For a commercial's own script use tie_shot. On the web connector, which has no files, give the draft as `script` text to check the words are there; without it the words are kept and found when the script is next read.",
        arguments: &[
            ("shot", "string", true),
            ("text", "string", true),
            ("mode", "string", false),
            ("script", "string", false),
        ],
    },
    Tool {
        name: "script_lines",
        description: "Which lines of the screenplay each shot holds, read against the latest draft (or `draft`, as revisions names it): the words, the scene and page they are on, and any words a shot holds that this draft no longer has. On the web connector give the draft as `script` text.",
        arguments: &[("draft", "string", false), ("script", "string", false)],
    },
];

/// A draft as text a tie points into, read with the film's own rules.
fn draft_of(doc: &Doc, text: &str) -> (Draft, shotlister_engine::Paginated) {
    let screenplay = shotlister_engine::screenplay::read_with(text, &doc.detection());
    let laid = shotlister_engine::lay_out(&screenplay);
    (Draft::of(&screenplay, &laid), laid)
}

/// The page a place in a draft is printed on.
fn page_of(draft: &Draft, laid: &shotlister_engine::Paginated, at: usize) -> usize {
    for (page, lines) in laid.pages.iter().zip(&draft.lines) {
        if lines.iter().flatten().any(|(a, b)| *a <= at && at <= *b) {
            return page.number;
        }
    }
    0
}

impl<F: Films> Server<F> {
    pub(super) fn misc_tools(&mut self, name: &str, arguments: &Json) -> Option<Result<String, String>> {
        Some(match name {
            "redo" => (|| {
                self.films.doc()?;
                if self.films.read_only() {
                    return Err("This project is open for reading only.".to_string());
                }
                let outcome = self.films.doc_mut()?.redo();
                self.films.save()?;
                Ok(match outcome {
                    None => "There is nothing to redo.".to_string(),
                    Some(outcome) if outcome.complete() => format!("Redid {}.", outcome.label),
                    Some(outcome) => format!(
                        "Redid {}. {} field(s) were left alone because they had changed since.",
                        outcome.label, outcome.skipped
                    ),
                })
            })(),
            "rename_draft" => {
                let wanted = arguments.str_field("draft").trim().to_string();
                let name = arguments.str_field("name").trim().to_string();
                if name.is_empty() {
                    return Some(Err("A draft needs a name.".to_string()));
                }
                self.change("Rename revision", move |doc| {
                    let drafts = doc.revisions();
                    let found = if wanted.eq_ignore_ascii_case("latest") {
                        doc.latest_revision()
                    } else {
                        drafts.iter().find(|r| r.name.eq_ignore_ascii_case(&wanted)).cloned()
                    };
                    let draft = found.ok_or_else(|| {
                        if drafts.is_empty() {
                            "This project has taken in no script drafts.".to_string()
                        } else {
                            format!("There is no draft {wanted}. The drafts are {}.", drafts.iter().map(|r| r.name.clone()).collect::<Vec<_>>().join(", "))
                        }
                    })?;
                    doc.rename_revision(draft.id, &name);
                    Ok(format!("{} is {name} now.", draft.name))
                })
            }
            "tie_lines" => self.tie_lines(arguments),
            "script_lines" => self.script_lines(arguments),
            _ => return None,
        })
    }

    /// The draft wanted (by name, else the latest) and its text: given as
    /// `script`, else read off the film's own files. None for the text when
    /// this host has no files and none was given.
    fn draft_text(&self, wanted: &str, given: &str) -> Result<(Option<Id>, Option<String>), String> {
        let doc = self.films.doc()?;
        let revision = if wanted.trim().is_empty() || wanted.eq_ignore_ascii_case("latest") {
            doc.latest_revision()
        } else {
            let found = doc.revisions().into_iter().find(|r| r.name.eq_ignore_ascii_case(wanted.trim()));
            Some(found.ok_or(format!("There is no draft {}.", wanted.trim()))?)
        };
        if !given.trim().is_empty() {
            return Ok((revision.map(|r| r.id), Some(given.to_string())));
        }
        let Some(revision) = revision else {
            return Err("This project has taken in no script drafts. A commercial's script is tied with tie_shot.".to_string());
        };
        let text = self
            .films
            .media_bytes(&format!("{}.txt", revision.hash))
            .ok()
            .map(|bytes| String::from_utf8_lossy(&bytes).to_string());
        Ok((Some(revision.id), text))
    }

    fn tie_lines(&mut self, arguments: &Json) -> Result<String, String> {
        let reference = arguments.str_field("shot");
        let words = arguments.str_field("text");
        let mode = arguments.str_field("mode").trim().to_ascii_lowercase();
        let (revision, text) = if words.trim().is_empty() {
            (None, None)
        } else {
            self.draft_text("", &arguments.str_field("script"))?
        };
        self.change("Tie shot", move |doc| {
            let placement = tools::find_placement(doc, &reference).ok_or(format!("There is no shot {reference}."))?;
            let shot = tools::shot_of(doc, placement).ok_or(format!("There is no shot {reference}."))?;
            if words.trim().is_empty() {
                if mode == "remove" {
                    return Err("Say which words to let go.".to_string());
                }
                doc.untie_play(shot);
                return Ok(format!("{reference} holds no lines."));
            }
            let read = text.as_deref().map(|t| draft_of(doc, t));
            let draft = read.as_ref().map(|(d, _)| d);
            if mode == "remove" {
                if !doc.untie_play_words(shot, revision, draft, &words) {
                    return Err(format!("{reference} does not hold those words: {}", words.trim()));
                }
            } else if !doc.tie_play_words(shot, revision, draft, &words, mode == "add") {
                return Err(format!("Those words are not in the script: {}", words.trim()));
            }
            let held = doc.play_excerpt(shot);
            Ok(match (held.is_empty(), &read) {
                (true, _) => format!("{reference} holds no lines."),
                (false, Some((draft, laid))) => {
                    let reading = doc.play_reading(shot, draft);
                    let mut pages: Vec<String> = Vec::new();
                    for (a, _) in &reading.found {
                        let page = page_of(draft, laid, *a).to_string();
                        if !pages.contains(&page) {
                            pages.push(page);
                        }
                    }
                    format!("{reference} holds: {held} (p. {}).", pages.join(", "))
                }
                (false, None) => format!("{reference} holds: {held} (placed when the script is next read)."),
            })
        })
    }

    fn script_lines(&mut self, arguments: &Json) -> Result<String, String> {
        let (_, text) = self.draft_text(&arguments.str_field("draft"), &arguments.str_field("script"))?;
        let doc = self.films.doc()?;
        let Some(text) = text else {
            // No files here: the words each shot keeps, without their pages.
            let shots: Vec<Json> = doc
                .shots_holding_lines()
                .into_iter()
                .map(|shot| {
                    let number = doc.placements_of_shot(shot).first().and_then(|p| doc.display_number(*p)).unwrap_or_default();
                    Json::object(vec![
                        ("shot", Json::text(number)),
                        ("lines", Json::Array(doc.play_stretches(shot).into_iter().map(|s| Json::text(s.words)).collect())),
                    ])
                })
                .collect();
            return Ok(Json::object(vec![("shots", Json::Array(shots))]).encode());
        };
        let (draft, laid) = draft_of(doc, &text);
        let shots: Vec<Json> = doc
            .play_ties_in(&draft)
            .into_iter()
            .map(|(shot, reading)| {
                let number = doc.placements_of_shot(shot).first().and_then(|p| doc.display_number(*p)).unwrap_or_default();
                let lines: Vec<Json> = reading
                    .found
                    .iter()
                    .map(|(a, b)| {
                        Json::object(vec![
                            ("words", Json::text(draft.slice(*a, *b).split_whitespace().collect::<Vec<_>>().join(" "))),
                            ("scene", Json::text(draft.scene_at(*a).unwrap_or_default())),
                            ("page", Json::Number(page_of(&draft, &laid, *a) as f64)),
                        ])
                    })
                    .collect();
                Json::object(vec![
                    ("shot", Json::text(number)),
                    ("lines", Json::Array(lines)),
                    ("not_in_this_draft", Json::Array(reading.lost.into_iter().map(Json::text).collect())),
                ])
            })
            .collect();
        Ok(Json::object(vec![("shots", Json::Array(shots))]).encode())
    }
}
