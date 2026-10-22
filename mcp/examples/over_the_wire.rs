//! Drive the MCP the way Claude would, against a real script.
//!
//!   swift tools/pdftext.swift <a.pdf> \
//!     | cargo run --manifest-path mcp/Cargo.toml --example over_the_wire
use shotlister_mcp::json::Json;
use shotlister_mcp::server::Server;
use std::io::Read;

/// Cut to roughly this many characters without splitting one in half.
fn snippet(text: &str, most: usize) -> String {
    text.chars().take(most).collect()
}

fn args(pairs: &[(&str, &str)]) -> Json {
    Json::object(pairs.iter().map(|(k, v)| (*k, Json::text(*v))).collect())
}

fn main() {
    // The Mac's half: positioned text off a PDF, read into a screenplay.
    let mut pages = String::new();
    std::io::stdin().read_to_string(&mut pages).unwrap();
    let script = shotlister_engine::printed::as_script(&parse_pages(&pages));

    let dir = std::env::temp_dir().join("shotlister-mcp-demo");
    let _ = std::fs::remove_dir_all(&dir);
    std::fs::create_dir_all(&dir).unwrap();
    let project =
        shotlister_storage::create(&dir, "Call Her Back", shotlister_engine::DeviceId(9001)).unwrap();
    let path = project.path().to_path_buf();
    drop(project);

    let mut server = Server::new(shotlister_engine::DeviceId(9001));
    server
        .call("open_project", &args(&[("path", &path.to_string_lossy())]))
        .unwrap();

    println!("── read_draft — reports, changes nothing ──");
    let said = server
        .call("read_draft", &args(&[("text", &script), ("at_least", "2")]))
        .unwrap();
    println!("{}\n", snippet(&said, 620));

    println!("── cast ──");
    println!(
        "{}\n",
        server
            .call("cast", &args(&[("text", &script), ("at_least", "2")]))
            .unwrap()
    );

    println!("── script_pages, scene 2 ──");
    let page = server
        .call("script_pages", &args(&[("text", &script), ("scene", "2")]))
        .unwrap();
    println!("{}\n", snippet(&page, 520));

    println!("── apply_draft ──");
    println!(
        "{}\n",
        server
            .call(
                "apply_draft",
                &args(&[
                    ("text", &script),
                    ("revision_name", "First white"),
                    ("came_from", "DRAFTJP.pdf"),
                    ("dated", "2026-08-20T11:56:00Z"),
                    ("at_least", "2"),
                ])
            )
            .unwrap()
    );

    println!("── scenes afterwards ──");
    let scenes = server.call("scenes", &args(&[])).unwrap();
    println!("{}", snippet(&scenes, 620));
}

fn parse_pages(input: &str) -> Vec<shotlister_engine::printed::Page> {
    let mut pages: Vec<shotlister_engine::printed::Page> = Vec::new();
    for line in input.lines() {
        let mut parts = line.split('\t');
        match parts.next() {
            Some("page") => pages.push(shotlister_engine::printed::Page {
                width: parts.next().and_then(|n| n.parse().ok()).unwrap_or(612.0),
                height: parts.next().and_then(|n| n.parse().ok()).unwrap_or(792.0),
                runs: Vec::new(),
            }),
            Some("run") => {
                if let Some(page) = pages.last_mut() {
                    let x = parts.next().and_then(|n| n.parse().ok()).unwrap_or(0.0);
                    let y = parts.next().and_then(|n| n.parse().ok()).unwrap_or(0.0);
                    page.runs.push(shotlister_engine::printed::Run::new(
                        x,
                        y,
                        parts.collect::<Vec<_>>().join("\t"),
                    ));
                }
            }
            _ => {}
        }
    }
    pages
}
