//! Read the `page`/`run` lines a shell produced from a PDF, and say what the
//! engine made of them.
//!
//!   swift tools/pdftext.swift <file.pdf> | cargo run --example read_a_pdf
use shotlister_engine::cast::{self, Merging, Options};
use shotlister_engine::pages::lay_out;
use shotlister_engine::printed::{self, Page, Run};
use shotlister_engine::screenplay::{Detection, Status};
use std::io::Read;

fn main() {
    let mut input = String::new();
    std::io::stdin().read_to_string(&mut input).unwrap();

    let mut pages: Vec<Page> = Vec::new();
    for line in input.lines() {
        let mut parts = line.split('\t');
        match parts.next() {
            Some("page") => {
                let width = parts.next().and_then(|n| n.parse().ok()).unwrap_or(612.0);
                let height = parts.next().and_then(|n| n.parse().ok()).unwrap_or(792.0);
                pages.push(Page { width, height, runs: Vec::new() });
            }
            Some("run") => {
                let Some(page) = pages.last_mut() else { continue };
                let x = parts.next().and_then(|n| n.parse().ok()).unwrap_or(0.0);
                let y = parts.next().and_then(|n| n.parse().ok()).unwrap_or(0.0);
                let text: String = parts.collect::<Vec<_>>().join("\t");
                page.runs.push(Run::new(x, y, text));
            }
            _ => {}
        }
    }
    println!("{} pages, {} lines of text", pages.len(),
             pages.iter().map(|p| p.runs.len()).sum::<usize>());

    let screenplay = printed::read(&pages, &Detection::printed());
    let laid = lay_out(&screenplay);

    let taken = screenplay.scenes.iter().filter(|s| s.accepted).count();
    println!(
        "\nscenes detected: {}   taken: {}   set aside as rooms: {}   repeated headings ignored: {}",
        screenplay.scenes.len(),
        taken,
        screenplay.scenes.len() - taken,
        screenplay.duplicates_ignored,
    );

    println!("\n{:<6} {:<52} {:>7} {:>6}", "#", "heading", "length", "page");
    for scene in &screenplay.scenes {
        let mark = if scene.accepted { " " } else { "·" };
        let at = laid.extent_of(
            screenplay.scenes.iter().position(|s| std::ptr::eq(s, scene)).unwrap(),
        );
        let (length, page) = match at {
            Some(e) => (e.length(), e.starts_on),
            None => ("—".to_string(), 0),
        };
        let under = match scene.status {
            Status::SubSlug { under } => format!(" (in {})", screenplay.scenes[under].label),
            Status::Scene => String::new(),
        };
        let heading: String = scene.script.heading.chars().take(46).collect();
        println!("{mark}{:<5} {:<52} {:>7} {:>6}", scene.label, format!("{heading}{under}"), length, page);
    }

    println!("\nthe script is {} pages laid out", laid.pages_long());

    for (label, options) in [
        ("as found", Options::default()),
        ("merged hard", Options::merging(Merging::Aggressive)),
        ("speaking at least twice", Options::default().at_least(2)),
    ] {
        let found = cast::read(&screenplay, options);
        println!("\ncast — {label} ({} found):", found.len());
        for member in found.iter().take(15) {
            println!("  {:<16} {}x", member.display, member.speeches);
        }
    }
}
