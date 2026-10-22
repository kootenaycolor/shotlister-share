//! The protocol, and what it does to a project.

use std::fs;
use std::path::PathBuf;

use shotlister_engine::DeviceId;
use shotlister_mcp::json::{self, Json};
use shotlister_mcp::Server;

struct Scratch(PathBuf);

impl Scratch {
    fn new(name: &str) -> Scratch {
        let path = std::env::temp_dir().join(format!("shotlister-mcp-{name}-{}", std::process::id()));
        let _ = fs::remove_dir_all(&path);
        fs::create_dir_all(&path).expect("scratch");
        Scratch(path)
    }
}

impl Drop for Scratch {
    fn drop(&mut self) {
        let _ = fs::remove_dir_all(&self.0);
    }
}

fn args(pairs: &[(&str, &str)]) -> Json {
    Json::Object(
        pairs
            .iter()
            .map(|(k, v)| (k.to_string(), Json::text(*v)))
            .collect(),
    )
}

/// A server with a real project open.
/// A commercial, as its Type would make it: kind is no longer a tool.
fn make_commercial(server: &mut Server<shotlister_mcp::films::Disk>) {
    use shotlister_mcp::films::Films;
    server.films_mut().doc_mut().expect("open").transact("Set kind", |doc: &mut shotlister_engine::Doc| -> Result<String, String> {
        doc.set_kind(shotlister_engine::FilmKind::Commercial);
        Ok(String::new())
    }).expect("sets");
    server.films_mut().save().expect("saves");
}

fn opened(name: &str) -> (Scratch, Server<shotlister_mcp::films::Disk>, PathBuf) {
    let scratch = Scratch::new(name);
    let path = {
        let project = shotlister_storage::create(&scratch.0, "Daybreak", DeviceId(1)).expect("creates");
        project.path().to_path_buf()
    };
    let mut server = Server::new(DeviceId(2));
    server
        .call("open_project", &args(&[("path", path.to_str().unwrap())]))
        .expect("opens");
    (scratch, server, path)
}

// ---- json --------------------------------------------------------------

#[test]
fn json_survives_a_round_trip() {
    let text = r#"{"a":1,"b":[true,false,null],"c":{"d":"say \"go\"\n"},"e":-2.5}"#;
    let parsed = json::parse(text).expect("parses");
    assert_eq!(parsed.get("a").unwrap().as_f64(), Some(1.0));
    assert_eq!(parsed.get("b").unwrap().as_array().unwrap().len(), 3);
    assert_eq!(
        parsed.get("c").unwrap().get("d").unwrap().as_str(),
        Some("say \"go\"\n")
    );
    // And it comes back out the same, so what we send is what we meant.
    assert_eq!(json::parse(&parsed.encode()).unwrap(), parsed);
}

#[test]
fn nonsense_is_refused_rather_than_half_read() {
    assert!(json::parse("{not json").is_none());
    assert!(json::parse("").is_none());
    assert!(json::parse("{} trailing").is_none());
}

// ---- the protocol ------------------------------------------------------

#[test]
fn it_introduces_itself() {
    let mut server = Server::new(DeviceId(1));
    let reply = server
        .handle(r#"{"jsonrpc":"2.0","id":1,"method":"initialize"}"#)
        .expect("replies");
    let parsed = json::parse(&reply).unwrap();

    assert!(parsed.get("result").unwrap().get("protocolVersion").is_some());
    assert_eq!(
        parsed.get("result").unwrap().get("serverInfo").unwrap().get("name").unwrap().as_str(),
        Some("shotlister")
    );
}

#[test]
fn a_notification_gets_no_answer() {
    let mut server = Server::new(DeviceId(1));
    // No id, so by definition nothing is expected back.
    assert!(server
        .handle(r#"{"jsonrpc":"2.0","method":"notifications/initialized"}"#)
        .is_none());
}

#[test]
fn every_tool_is_listed_with_a_schema() {
    let mut server = Server::new(DeviceId(1));
    let reply = server
        .handle(r#"{"jsonrpc":"2.0","id":2,"method":"tools/list"}"#)
        .expect("replies");
    let parsed = json::parse(&reply).unwrap();
    let tools = parsed.get("result").unwrap().get("tools").unwrap().as_array().unwrap();

    assert!(tools.len() >= 10);
    // Two tools under one name: a client sees one of them, and a call meant
    // for the other lands in the first — which is how a scene's text once
    // could replace a commercial's whole script.
    let mut names: Vec<&str> = tools.iter().map(|t| t.get("name").unwrap().as_str().unwrap()).collect();
    names.sort();
    for pair in names.windows(2) {
        assert_ne!(pair[0], pair[1], "two tools are called {}", pair[0]);
    }
    for tool in tools {
        assert!(!tool.get("name").unwrap().as_str().unwrap().is_empty());
        assert!(!tool.get("description").unwrap().as_str().unwrap().is_empty());
        assert!(tool.get("inputSchema").unwrap().get("properties").is_some());
    }
}

#[test]
fn an_unknown_method_is_an_error_not_a_crash() {
    let mut server = Server::new(DeviceId(1));
    let reply = server
        .handle(r#"{"jsonrpc":"2.0","id":3,"method":"nonsense"}"#)
        .expect("replies");
    assert!(json::parse(&reply).unwrap().get("error").is_some());
}

// ---- working on a project ----------------------------------------------

#[test]
fn nothing_works_until_a_project_is_open() {
    let mut server = Server::new(DeviceId(1));
    let error = server.call("scenes", &Json::Null).unwrap_err();
    assert!(error.contains("open_project"), "{error}");
}

#[test]
fn things_are_named_the_way_you_say_them() {
    let (_scratch, mut server, _) = opened("naming");
    server
        .call("add_scene", &args(&[("number", "34"), ("location", "car")]))
        .expect("adds");
    let added = server
        .call("add_shot", &args(&[("scene", "34"), ("description", "Wide of the car")]))
        .expect("adds");

    // A scene is 34 and a shot is 34A. Nobody should have to use an internal id.
    assert!(added.contains("34A"), "{added}");

    let updated = server
        .call("update_shot", &args(&[("shot", "34A"), ("lens", "37mm")]))
        .expect("updates");
    assert!(updated.contains("34A"));
}

#[test]
fn a_wrong_number_is_a_sentence_rather_than_a_crash() {
    let (_scratch, mut server, _) = opened("wrongnumber");
    let error = server
        .call("add_shot", &args(&[("scene", "99")]))
        .unwrap_err();
    assert_eq!(error, "There is no scene 99 in this project.");
}

#[test]
fn a_change_is_on_disk_before_the_reply_comes_back() {
    let (_scratch, mut server, path) = opened("autosave");
    server.call("add_scene", &args(&[("number", "34")])).expect("adds");
    server
        .call("add_shot", &args(&[("scene", "34"), ("description", "Wide")]))
        .expect("adds");

    // There is no window open here, so an unsaved edit would simply be lost.
    let reopened = shotlister_storage::open(&path, DeviceId(9)).expect("opens");
    let scene = reopened.doc().scenes_in_order()[0];
    assert_eq!(reopened.doc().placements_in_scene(scene).len(), 1);
}

#[test]
fn a_new_value_joins_the_project_list() {
    let (_scratch, mut server, _) = opened("vocab");
    server.call("add_scene", &args(&[("number", "34")])).expect("adds");
    server
        .call("add_shot", &args(&[("scene", "34"), ("lens", "20.7mm"), ("angle", "Front On, Eye Level")]))
        .expect("adds");

    let shots = server.call("shots", &args(&[("scene", "34")])).expect("lists");
    assert!(shots.contains("20.7mm"));
    // A multi-value field is written the way the sheets write it.
    assert!(shots.contains("Front On, Eye Level"), "{shots}");
}

#[test]
fn a_change_can_be_taken_back() {
    let (_scratch, mut server, _) = opened("undo");
    server.call("add_scene", &args(&[("number", "34")])).expect("adds");
    server.call("add_shot", &args(&[("scene", "34")])).expect("adds");

    let undone = server.call("undo", &Json::Null).expect("undoes");
    assert!(undone.contains("Add shot"), "{undone}");

    let shots = server.call("shots", &args(&[("scene", "34")])).expect("lists");
    assert_eq!(shots, "[]");
}

#[test]
fn moving_a_shot_says_what_it_is_called_now() {
    let (_scratch, mut server, _) = opened("move");
    server.call("add_scene", &args(&[("number", "34")])).expect("adds");
    server.call("add_scene", &args(&[("number", "40")])).expect("adds");
    server.call("add_shot", &args(&[("scene", "34")])).expect("adds");

    let moved = server
        .call("move_shot", &args(&[("shot", "34A"), ("scene", "40")]))
        .expect("moves");
    assert!(moved.contains("40A"), "{moved}");
}

#[test]
fn the_summary_says_whether_letters_can_still_move() {
    let (_scratch, mut server, _) = opened("summary");
    let summary = server.call("summary", &Json::Null).expect("summarises");
    assert!(summary.contains("Daybreak"));
    // Worth knowing before reordering anything.
    assert!(summary.contains("prep"), "{summary}");
}

#[test]
fn it_can_write_the_list_out() {
    let scratch = Scratch::new("export");
    let path = {
        let project = shotlister_storage::create(&scratch.0, "Daybreak", DeviceId(1)).expect("creates");
        project.path().to_path_buf()
    };
    let mut server = Server::new(DeviceId(2));
    server
        .call("open_project", &args(&[("path", path.to_str().unwrap())]))
        .expect("opens");
    server.call("add_scene", &args(&[("number", "34")])).expect("adds");
    server
        .call("add_shot", &args(&[("scene", "34"), ("description", "Wide of the car")]))
        .expect("adds");

    let out = scratch.0.join("list.csv");
    server
        .call(
            "export",
            &args(&[("format", "csv"), ("path", out.to_str().unwrap())]),
        )
        .expect("exports");

    let written = fs::read_to_string(&out).expect("reads");
    assert!(written.contains("Wide of the car"));
    assert!(written.starts_with("Day,Scene #,Shot #"));
}

#[test]
fn an_unknown_format_says_what_it_does_know() {
    let (_scratch, mut server, _) = opened("badformat");
    let error = server
        .call("export", &args(&[("format", "pdf"), ("path", "/tmp/x")]))
        .unwrap_err();
    assert!(error.contains("csv"), "{error}");
}

// ---- a new draft arrives -------------------------------------------------

const DRAFT: &str = "\
34    INT. JAIL CORRIDOR - DAY                34

Sunlight through the high window.

35    EXT. PRISON YARD - NIGHT                35

Floodlights.
";

#[test]
fn a_draft_can_be_read_without_changing_anything() {
    let (_scratch, mut server, _) = opened("draft-read");
    server.call("add_scene", &args(&[("number", "34")])).expect("adds");
    server
        .call("add_shot", &args(&[("scene", "34"), ("description", "Wide")]))
        .expect("adds");

    let said = server
        .call("read_draft", &args(&[("text", DRAFT)]))
        .expect("reads");

    assert!(said.contains("\"new_to_the_project\":1"), "{said}");
    assert!(said.contains("\"already_in_the_project\":1"), "{said}");
    assert!(said.contains("35"), "{said}");
    // The things the old reading could not say at all.
    assert!(said.contains("\"length\""), "how long each scene is: {said}");
    assert!(said.contains("\"starts_on_page\""), "{said}");

    // Nothing happened.
    let scenes = server.call("scenes", &args(&[])).expect("lists");
    assert!(!scenes.contains("35"), "reading a draft must not create it: {scenes}");
}

#[test]
fn a_draft_that_drops_a_scene_says_how_much_work_is_on_it() {
    let (_scratch, mut server, _) = opened("draft-gone");
    server.call("add_scene", &args(&[("number", "34")])).expect("adds");
    for shot in ["Wide", "Tighter", "Insert"] {
        server
            .call("add_shot", &args(&[("scene", "34"), ("description", shot)]))
            .expect("adds");
    }

    let said = server
        .call("read_draft", &args(&[("text", "35  EXT. PRISON YARD - NIGHT  35\n")]))
        .expect("reads");

    assert!(said.contains("in_the_project_but_not_in_this_draft"), "{said}");
    assert!(said.contains("\"number\":\"34\""), "{said}");
    assert!(
        said.contains("\"shots_that_would_go_with_it\":3"),
        "the number somebody needs in order to decide: {said}"
    );
    assert!(said.contains("never removed"), "{said}");
}

#[test]
fn applying_a_draft_creates_and_updates_but_never_deletes() {
    let (_scratch, mut server, _) = opened("draft-apply");
    server.call("add_scene", &args(&[("number", "34")])).expect("adds");
    server
        .call("add_shot", &args(&[("scene", "34"), ("description", "Wide")]))
        .expect("adds");
    server
        .call("add_scene", &args(&[("number", "99")]))
        .expect("adds");

    let said = server
        .call("apply_draft", &args(&[("text", DRAFT)]))
        .expect("applies");

    assert!(said.contains("Left exactly where they are"), "{said}");
    assert!(
        said.contains("99 (0 shots)"),
        "it has to name which scene, since there is no list on screen here: {said}"
    );

    let scenes = server.call("scenes", &args(&[])).expect("lists");
    assert!(scenes.contains("35"), "the new scene was made: {scenes}");
    assert!(scenes.contains("99"), "and the dropped one is still there: {scenes}");
    assert!(scenes.contains("PRISON YARD"), "{scenes}");
}

#[test]
fn a_whole_draft_is_one_undo() {
    let (_scratch, mut server, _) = opened("draft-undo");
    server.call("apply_draft", &args(&[("text", DRAFT)])).expect("applies");
    assert!(server.call("scenes", &args(&[])).unwrap().contains("34"));

    server.call("undo", &args(&[])).expect("undoes");

    let scenes = server.call("scenes", &args(&[])).expect("lists");
    assert!(!scenes.contains("PRISON YARD"), "one draft, one undo: {scenes}");
}

#[test]
fn a_reference_can_be_filed_against_a_scene_and_found_again() {
    let (scratch, mut server, _path) = opened("attach");

    // Something an agent has already fetched — a lookbook page pulled out of
    // Notion, say. The MCP does no network on purpose: whoever is doing the
    // thinking fetches, and this files.
    let file = scratch.0.join("overhead.png");
    fs::write(&file, b"pretend this is a lighting overhead").expect("write");

    server
        .call("add_scene", &args(&[("number", "34"), ("location", "CAR")]))
        .expect("scene");
    let said = server
        .call(
            "attach",
            &args(&[
                ("scene", "34"),
                ("path", file.to_str().unwrap()),
                ("caption", "Overhead — 4pm"),
            ]),
        )
        .expect("attach");
    assert!(said.contains("overhead.png"), "it says what it filed");
    assert!(said.contains("scene 34"));

    // And an agent can see what is already there before filing more, which is
    // what keeps an automatic import from pinning the same page four times.
    let listed = server.call("attachments", &args(&[("scene", "34")])).expect("list");
    assert!(listed.contains("overhead.png"));
    assert!(listed.contains("Overhead — 4pm"), "the caption rides with it");

    // A scene that does not exist is refused rather than half-filed.
    assert!(server
        .call("attach", &args(&[("scene", "99"), ("path", file.to_str().unwrap())]))
        .is_err());
    // …and so is a file that is not there.
    assert!(server
        .call("attach", &args(&[("scene", "34"), ("path", "/nowhere/at/all.png")]))
        .is_err());
}

// ---- Claude's door catches up with the app's ----------------------------
//
// Everything built on 2026-08-20 went onto the ffi, which is the app's door.
// These pin that the same readings are reachable from here, because "Claude
// builds shot lists from his notes and scripts" is one of the three reasons
// this app exists.

const SPOKEN: &str = "\
34  INT. JAIL CORRIDOR - DAY                34

Sunlight through the high window.

                    FRANK
          It never gets shorter.

                    GUARD (O.S.)
                (bored)
          Keep moving.

                    FRANK (CONT'D)
          It never does.

                    THE END
          Fade.
";

#[test]
fn a_column_on_the_page_tells_a_cue_from_a_shout() {
    let (_scratch, mut server, _) = opened("mcp-cast");
    let said = server
        .call("cast", &args(&[("text", SPOKEN)]))
        .expect("reads the cast");

    // FRANK twice, under one name despite the (CONT'D).
    assert!(said.contains("\"name\":\"FRANK\""), "{said}");
    assert!(said.contains("\"speeches\":2"), "{said}");
    assert!(said.contains("\"reads_as\":\"Frank\""), "a list is read at rest: {said}");
    assert!(said.contains("FRANK (CONT'D)"), "and it shows its working: {said}");
}

#[test]
fn a_title_card_can_be_filtered_out_rather_than_guessed_at() {
    let (_scratch, mut server, _) = opened("mcp-floor");

    let everyone = server.call("cast", &args(&[("text", SPOKEN)])).expect("reads");
    assert!(
        everyone.contains("THE END"),
        "it is found, and saying so is the honest part: {everyone}"
    );

    let real = server
        .call("cast", &args(&[("text", SPOKEN), ("at_least", "2")]))
        .expect("reads");
    assert!(!real.contains("THE END"), "{real}");
    assert!(real.contains("FRANK"), "{real}");
}

#[test]
fn a_scene_can_be_read_as_it_sits_on_the_page() {
    let (_scratch, mut server, _) = opened("mcp-pages");
    let said = server
        .call("script_pages", &args(&[("text", SPOKEN), ("scene", "34")]))
        .expect("lays it out");

    assert!(said.contains("--- page 1 ---"), "{said}");
    assert!(said.contains("It never gets shorter."), "{said}");
    // Laid out, not just dumped: a cue sits well in from the margin.
    assert!(said.contains("                      FRANK"), "{said}");
    assert!(said.contains("of a page, starting on page 1"), "{said}");
}

#[test]
fn asking_for_a_scene_the_draft_has_not_got_is_a_sentence() {
    let (_scratch, mut server, _) = opened("mcp-noscene");
    let said = server.call("script_pages", &args(&[("text", SPOKEN), ("scene", "99")]));
    assert!(said.is_err(), "{said:?}");
}

#[test]
fn a_film_that_prints_oddly_only_has_to_be_explained_once() {
    let (_scratch, mut server, _) = opened("mcp-detection");

    // Untouched, it reads a script the way a printed one wants reading.
    let now = server.call("detection", &args(&[])).expect("reports");
    assert!(now.contains("\"must_have_a_number\":true"), "{now}");

    server
        .call("detection", &args(&[("find_rooms", "false")]))
        .expect("sets");

    // And it is remembered, rather than being explained again next draft.
    let after = server.call("detection", &args(&[])).expect("reports");
    assert!(after.contains("\"find_rooms\":false"), "{after}");
}

#[test]
fn taking_a_draft_leaves_the_scene_knowing_its_length_and_who_is_in_it() {
    let (_scratch, mut server, _) = opened("mcp-remembers");
    server
        .call("apply_draft", &args(&[("text", SPOKEN), ("at_least", "2")]))
        .expect("applies");

    let scenes = server.call("scenes", &args(&[])).expect("lists");
    // Both of these used to be worked out and thrown away.
    assert!(scenes.contains("\"length\":\"2/8\""), "{scenes}");
    assert!(scenes.contains("\"cast\":[\"FRANK\"]"), "who speaks in it: {scenes}");
    assert!(
        !scenes.contains("THE END"),
        "and only the people who survived the floor — a title card is not cast: {scenes}"
    );
    assert!(
        !scenes.contains("GUARD"),
        "the guard speaks once, and the floor was two: {scenes}"
    );
}

#[test]
fn the_project_keeps_the_draft_it_was_given() {
    let (_scratch, mut server, _) = opened("mcp-revisions");
    server
        .call(
            "apply_draft",
            &args(&[
                ("text", SPOKEN),
                ("revision_name", "First white"),
                ("came_from", "DRAFTJP.pdf"),
                ("dated", "2026-08-20T11:56:00Z"),
            ]),
        )
        .expect("applies");

    let kept = server.call("revisions", &args(&[])).expect("lists");
    assert!(kept.contains("First white"), "{kept}");
    assert!(kept.contains("DRAFTJP.pdf"), "{kept}");
    assert!(kept.contains("\"latest\":true"), "{kept}");
}

#[test]
fn only_the_scenes_asked_for_are_taken() {
    let (_scratch, mut server, _) = opened("mcp-only");
    let two = "34  INT. A - DAY  34\n\nShe waits.\n\n35  INT. B - DAY  35\n\nHe leaves.\n";
    server
        .call("apply_draft", &args(&[("text", two), ("only_scenes", "[\"34\"]")]))
        .expect("applies");

    let scenes = server.call("scenes", &args(&[])).expect("lists");
    assert!(scenes.contains("\"number\":\"34\""), "{scenes}");
    assert!(!scenes.contains("\"number\":\"35\""), "{scenes}");
}

// ---- a commercial ---------------------------------------------------------

/// **How Claude builds a commercial's list from his notes**: say it is a
/// commercial, then add scenes by title with what we see and what we hear.
/// The app numbers them; nothing asks for a number.
#[test]
fn a_commercial_is_built_from_titles() {
    let (_scratch, mut server, _) = opened("commercial");

    // A film insists on a number, and says what to do instead.
    let refused = server
        .call("add_scene", &args(&[("title", "Party Montage")]))
        .unwrap_err();
    assert!(refused.contains("commercial"), "{refused}");

    // Kind follows the project's Type (stage 5 step 5): no tool sets it.
    assert!(server.call("set_kind", &args(&[("kind", "commercial")])).unwrap_err().contains("Unknown tool"));
    make_commercial(&mut server);
    let summary = server.call("summary", &Json::Null).expect("summarises");
    assert!(summary.contains("\"kind\":\"commercial\""), "{summary}");

    let added = server
        .call(
            "add_scene",
            &args(&[
                ("title", "Party Montage"),
                ("video", "Quick cuts — the photo passed hand to hand."),
                ("audio", "Music up. No VO."),
            ]),
        )
        .expect("adds");
    assert!(added.contains("Added scene 1 — Party Montage"), "{added}");
    let again = server
        .call("add_scene", &args(&[("title", "End Card"), ("audio", "Sting.")]))
        .expect("adds");
    assert!(again.contains("Added scene 2 — End Card"), "{again}");

    // A shot on a titled scene is still 1A — the scene's number, the letter.
    let shot = server
        .call("add_shot", &args(&[("scene", "1"), ("description", "Hands passing the print")]))
        .expect("adds");
    assert!(shot.contains("1A"), "{shot}");

    let scenes = server.call("scenes", &Json::Null).expect("lists");
    assert!(scenes.contains("\"title\":\"Party Montage\""), "{scenes}");
    assert!(scenes.contains("\"audio\":\"Music up. No VO.\""), "{scenes}");
    assert!(scenes.contains("\"slug\":\"\""), "an untouched slug reads empty: {scenes}");

    let changed = server
        .call("update_scene", &args(&[("scene", "2"), ("title", "Logo Sting"), ("video", "Logo.")]))
        .expect("updates");
    assert!(changed.contains("Logo Sting"), "{changed}");

    // A number given on a commercial is kept — the AV script may have one.
    let numbered = server
        .call("add_scene", &args(&[("number", "10"), ("title", "Tag")]))
        .expect("adds");
    assert!(numbered.contains("Added scene 10 — Tag"), "{numbered}");
}

/// **Three spots on one job.** Each script is pasted into its own section,
/// so B's OPEN is a new scene and not an update to A's; a scene can be
/// moved between sections by title; and `scenes` says which section each
/// scene is in.
#[test]
fn several_scripts_keep_to_their_sections() {
    let (_scratch, mut server, _) = opened("sections");
    make_commercial(&mut server);

    // **The script is text, quoted by shots** (2026-09-19 night): set per
    // section, nothing parsed; a shot ties by quoting words; overlaps and
    // shared stretches are fine; an edit keeps the ties whose words remain.
    let said = server
        .call("set_script", &args(&[("text", "The kitchen at dawn. Music in.\n\nLogo. Sting."), ("section", "Spot A")]))
        .expect("sets");
    assert!(said.contains("Script set for Spot A"), "{said}");
    server
        .call("set_script", &args(&[("text", "The garage, rain outside.\n\nLogo. Sting."), ("section", "Spot B")]))
        .expect("sets");
    let script = server.call("script", &Json::Null).expect("lists");
    assert!(script.contains("\"section\":\"Spot A\"") && script.contains("\"section\":\"Spot B\""), "{script}");
    let scenes = server.call("scenes", &Json::Null).expect("lists");
    assert_eq!(scenes, "[]", "no scene was made");

    for (title, section) in [("Kitchen", "Spot A"), ("Logo Wall", "Spot A"), ("Garage", "Spot B"), ("Logo Wall", "Spot B")] {
        server.call("add_scene", &args(&[("title", title), ("section", section)])).expect("adds");
    }
    let said = server
        .call("add_shot", &args(&[("scene", "1"), ("description", "Wide, the kitchen"), ("script", "The kitchen at dawn.")]))
        .expect("adds");
    assert!(said.contains("1A"), "{said}");
    let shots = server.call("shots", &args(&[("scene", "1")])).expect("lists");
    assert!(shots.contains("\"script\":\"The kitchen at dawn.\""), "{shots}");
    // Overlapping stretch on another shot; the same stretch on a third.
    server.call("add_shot", &args(&[("scene", "1"), ("description", "Closer")])).expect("adds");
    let said = server.call("tie_shot", &args(&[("shot", "1B"), ("text", "dawn. Music in."), ("section", "Spot A")])).expect("ties");
    assert!(said.contains("1B quotes: dawn. Music in."), "{said}");
    let refused = server.call("tie_shot", &args(&[("shot", "1B"), ("text", "not in any script")])).unwrap_err();
    assert!(refused.contains("not in the script"), "{refused}");
    // "Logo. Sting." is in both scripts; with no section named the first
    // script holding it wins — say the section to be sure.
    let said = server.call("tie_shot", &args(&[("shot", "1B"), ("text", "Logo. Sting."), ("section", "Spot B")])).expect("ties");
    assert!(said.contains("1B quotes: Logo. Sting."), "{said}");
    let script = server.call("script", &Json::Null).expect("lists");
    assert!(script.contains("\"shot\":\"1B\",\"text\":\"Logo. Sting.\""), "{script}");

    // An edit above the words keeps the tie; striking them loses it.
    let said = server.call("set_script", &args(&[("text", "OPEN\n\nThe kitchen at dawn. Music in.\n\nLogo. Sting."), ("section", "Spot A")])).expect("edits");
    assert!(said.contains("1 tie kept"), "{said}");
    let said = server.call("set_script", &args(&[("text", "Nothing of the old."), ("section", "Spot A")])).expect("edits");
    assert!(said.contains("1 lost"), "{said}");
    let shots = server.call("shots", &args(&[("scene", "1")])).expect("lists");
    assert!(shots.contains("\"number\":\"1A\"") && shots.contains("\"script\":\"\""), "{shots}");
    server.call("tie_shot", &args(&[("shot", "1B"), ("text", "")])).expect("unties");

    let sections = server.call("sections", &Json::Null).expect("lists");
    assert!(sections.contains("\"title\":\"Spot A\",\"scenes\":2"), "{sections}");
    assert!(sections.contains("\"title\":\"Spot B\",\"scenes\":2"), "{sections}");

    let scenes = server.call("scenes", &Json::Null).expect("lists");
    assert_eq!(scenes.matches("\"section\":\"Spot A\"").count(), 2, "{scenes}");
    assert_eq!(scenes.matches("\"section\":\"Spot B\"").count(), 2, "{scenes}");

    // A scene added by hand into a section that does not exist yet makes it.
    server
        .call("add_scene", &args(&[("title", "Button"), ("section", "Spot C")]))
        .expect("adds");
    let refused = server.call("add_section", &args(&[("title", "spot c")])).unwrap_err();
    assert!(refused.contains("already"), "{refused}");
    // …and moved by title.
    server
        .call("update_scene", &args(&[("scene", "5"), ("section", "Spot B")]))
        .expect("moves");
    let sections = server.call("sections", &Json::Null).expect("lists");
    assert!(sections.contains("\"title\":\"Spot B\",\"scenes\":3"), "{sections}");
    assert!(sections.contains("\"title\":\"Spot C\",\"scenes\":0"), "{sections}");

    // Every control the Mac has, and the two it does not yet.
    let said = server
        .call("rename_section", &args(&[("section", "Spot C"), ("title", "Spot C — Alt")]))
        .expect("renames");
    assert!(said.contains("Spot C — Alt"), "{said}");
    let said = server.call("delete_section", &args(&[("section", "spot c — alt")])).expect("removes");
    assert!(said.contains("0 scenes left it"), "{said}");
    let missing = server.call("delete_section", &args(&[("section", "Spot Z")])).unwrap_err();
    assert!(missing.contains("no section"), "{missing}");

    // Scene 5 (Button) to the top, then after scene 1; numbers stay put.
    server.call("move_scene", &args(&[("scene", "5"), ("after", "start")])).expect("moves");
    let scenes = server.call("scenes", &Json::Null).expect("lists");
    assert!(scenes.starts_with("[{\"number\":\"5\""), "{scenes}");
    server.call("move_scene", &args(&[("scene", "5"), ("after", "1")])).expect("moves");
    let scenes = server.call("scenes", &Json::Null).expect("lists");
    assert!(scenes.starts_with("[{\"number\":\"1\""), "{scenes}");
    assert!(scenes.contains("\"number\":\"1\"") && scenes.find("\"number\":\"5\"") < scenes.find("\"number\":\"2\""), "{scenes}");
    let refused = server.call("move_scene", &args(&[("scene", "5"), ("after", "5")])).unwrap_err();
    assert!(refused.contains("itself"), "{refused}");

    // Renumbering is a commercial's, and follows the list: 1, 2(was 5), 3…
    let said = server.call("renumber", &Json::Null).expect("renumbers");
    assert!(said.contains("changed"), "{said}");
    let scenes = server.call("scenes", &Json::Null).expect("lists");
    assert!(scenes.contains("\"number\":\"2\",\"heading\":\"Button\""), "{scenes}");

    // Delete wants archive first.
    let refused = server.call("delete_scene", &args(&[("scene", "2")])).unwrap_err();
    assert!(refused.contains("archived"), "{refused}");
    server.call("archive_scene", &args(&[("scene", "2")])).expect("archives");
    let said = server.call("delete_scene", &args(&[("scene", "2")])).expect("deletes");
    assert!(said.contains("Deleted scene 2"), "{said}");
    let scenes = server.call("scenes", &Json::Null).expect("lists");
    assert!(!scenes.contains("Button"), "{scenes}");
}

#[test]
fn a_film_keeps_its_numbers_and_sorts_by_them() {
    let (_scratch, mut server, _) = opened("film-order");
    server.call("add_scene", &args(&[("number", "3"), ("location", "Kitchen")])).expect("adds");
    server.call("add_scene", &args(&[("number", "1"), ("location", "Porch")])).expect("adds");
    let refused = server.call("renumber", &Json::Null).unwrap_err();
    assert!(refused.contains("script"), "{refused}");
    server.call("sort_scenes", &Json::Null).expect("sorts");
    let scenes = server.call("scenes", &Json::Null).expect("lists");
    assert!(scenes.starts_with("[{\"number\":\"1\""), "{scenes}");
}

/// **Claude can draw a scene's plan** — walls, a camera that brings its shot,
/// and blocking at a later beat — and read it back.
#[test]
fn a_diagram_is_drawn_and_read_back_through_the_tools() {
    let (_scratch, mut server, _path) = opened("diagram");
    server.call("add_scene", &args(&[("number", "1"), ("int_ext", "INT"), ("location", "BEDROOM")])).expect("scene");
    let op = json::parse(r#"{"op":"add","els":[
        {"kind":"wall","x":0,"y":0,"x2":4,"y2":0},
        {"kind":"camera","x":2,"y":3,"rot":270,"new_shot":true},
        {"kind":"cast","x":2,"y":1,"label":"Anya"},
        {"kind":"light","sym":"fresnel","x":0.5,"y":0.5,"rot":45}]}"#).unwrap();
    let said = server
        .call("edit_diagram", &Json::Object(vec![("scene".into(), Json::text("1")), ("op".into(), op)]))
        .expect("draws");
    assert!(said.contains("holds 4"), "{said}");

    let plan = json::parse(&server.call("diagram", &args(&[("scene", "1")])).expect("reads")).unwrap();
    let els = plan.get("els").unwrap().as_array().unwrap();
    assert_eq!(els.len(), 4);
    let cam = els.iter().find(|e| e.str_field("kind") == "camera").unwrap();
    assert!(!cam.str_field("shot").is_empty(), "the camera made its shot");
    assert_eq!(cam.str_field("name"), "1A");
    let anya = els.iter().find(|e| e.str_field("label") == "Anya").unwrap().str_field("id");

    // Blocking: where Anya is at beat 2, given as a string the way a model
    // sometimes sends an object.
    let op = format!(r#"{{"op":"beat","id":"{anya}","beat":2,"x":3,"y":2}}"#);
    server
        .call("edit_diagram", &Json::Object(vec![("scene".into(), Json::text("1")), ("op".into(), Json::text(op))]))
        .expect("blocks");
    let plan = json::parse(&server.call("diagram", &args(&[("scene", "1")])).unwrap()).unwrap();
    let anya = plan.get("els").unwrap().as_array().unwrap().iter().find(|e| e.str_field("label") == "Anya").unwrap().clone();
    assert_eq!(anya.get("steps").unwrap().as_array().unwrap().len(), 1);
    let id = anya.str_field("id");

    // Steps (his ruling, 2026-10-01): as many as he likes, lettered, each on
    // a beat — added, turned and put on another beat through the same tool.
    for op in [
        format!(r#"{{"op":"step_add","id":"{id}","x":5,"y":2}}"#),
        format!(r#"{{"op":"step_add","id":"{id}","turn":true}}"#),
        format!(r#"{{"op":"step_set","id":"{id}","step":3,"beat":7}}"#),
    ] {
        server.call("edit_diagram", &args(&[("scene", "1"), ("op", &op)])).expect("a step");
    }
    let plan = json::parse(&server.call("diagram", &args(&[("scene", "1")])).unwrap()).unwrap();
    let anya = plan.get("els").unwrap().as_array().unwrap().iter().find(|e| e.str_field("id") == id).unwrap().clone();
    let seq: Vec<String> = anya
        .get("seq")
        .unwrap()
        .as_array()
        .unwrap()
        .iter()
        .map(|t| format!("{}{}{}", t.str_field("letter"), t.get("beat").and_then(|b| b.as_f64()).unwrap_or(-1.0), if t.get("turn").and_then(|b| b.as_bool()) == Some(true) { "t" } else { "" }))
        .collect();
    assert_eq!(seq, ["A1", "B2", "C3", "D7t"]);

    let bad = server.call("edit_diagram", &Json::Object(vec![("scene".into(), Json::text("1")), ("op".into(), Json::text("{\"op\":\"explode\"}"))]));
    assert!(bad.is_err());
    let lib = json::parse(&server.call("diagram_library", &Json::Object(vec![])).unwrap()).unwrap();
    assert!(lib.get("symbols").unwrap().as_array().unwrap().len() > 60);
}

// ---- master lists ------------------------------------------------------

/// A lens list with glass on it and one shot using some of it.
fn with_lenses(name: &str) -> (Scratch, Server<shotlister_mcp::films::Disk>) {
    let (scratch, mut server, _) = opened(name);
    server.call("add_scene", &args(&[("number", "5")])).expect("adds");
    server.call("add_shot", &args(&[("scene", "5"), ("lens", "18mm")])).expect("adds");
    server
        .call("add_to_list", &args(&[("list", "lenses"), ("terms", "35mm, 85mm")]))
        .expect("adds");
    (scratch, server)
}

#[test]
fn a_list_reads_in_order_with_what_uses_it() {
    let (_scratch, mut server) = with_lenses("lists-read");
    let said = server.call("lists", &args(&[("list", "lens")])).expect("reads");
    let list = json::parse(&said).unwrap();
    let terms: Vec<String> = list.get("terms").unwrap().as_array().unwrap().iter()
        .map(|t| t.get("term").unwrap().as_str().unwrap().to_string()).collect();
    assert_eq!(terms, vec!["18mm", "35mm", "85mm"]);
    assert!(said.contains(r#""used":1"#), "18mm is on a shot: {said}");
    assert!(said.contains(r#""locked":false"#));

    let all = server.call("lists", &Json::Null).expect("reads all");
    for name in ["size", "angle", "movement", "lens", "modifiers", "lens_filters", "support", "priority", "pov", "tags"] {
        assert!(all.contains(&format!(r#""list":"{name}""#)), "{name} missing");
    }
    // "filters" is the built-in Filters list now; a word nothing names is not.
    assert!(server.call("lists", &args(&[("list", "filters")])).unwrap().contains(r#""list":"lens_filters""#));
    assert!(server.call("lists", &args(&[("list", "diffusion")])).unwrap_err().contains("lens"));
}

#[test]
fn several_lenses_go_on_by_focal_length_in_one_undo() {
    let (_scratch, mut server) = with_lenses("lists-add");
    let said = server
        .call("add_to_list", &args(&[("list", "lens"), ("terms", r#"["50mm","25mm","35MM","135mm"]"#), ("by_number", "true")]))
        .expect("adds");
    assert!(said.contains("Added to the lens list: 50mm, 25mm, 135mm"), "{said}");
    assert!(said.contains("Already on it: 35MM"), "{said}");
    assert!(said.contains("18mm, 25mm, 35mm, 50mm, 85mm, 135mm"), "{said}");

    let undone = server.call("undo", &Json::Null).expect("undoes");
    assert!(undone.contains("Add to list"), "{undone}");
    let list = server.call("lists", &args(&[("list", "lens")])).unwrap();
    assert!(!list.contains("25mm") && !list.contains("135mm"), "one undo took all of it: {list}");
}

#[test]
fn a_locked_list_says_no_through_every_door() {
    let (_scratch, mut server) = with_lenses("lists-locked");
    server.call("lock_list", &args(&[("list", "lens")])).expect("locks");

    let refused = server
        .call("add_to_list", &args(&[("list", "lens"), ("terms", "40mm")]))
        .unwrap_err();
    assert!(refused.contains("locked"), "{refused}");

    // A shot's own door used to answer "Updated" over a lens that never landed.
    let said = server.call("update_shot", &args(&[("shot", "5A"), ("lens", "40mm")])).expect("answers");
    assert!(said.contains("40mm was not set"), "{said}");
    let shots = server.call("shots", &args(&[("scene", "5")])).unwrap();
    assert!(shots.contains("18mm") && !shots.contains("40mm"), "{shots}");

    server.call("lock_list", &args(&[("list", "lens"), ("locked", "false")])).expect("unlocks");
    server.call("add_to_list", &args(&[("list", "lens"), ("terms", "40mm")])).expect("adds once open");
}

#[test]
fn taking_a_term_in_use_off_a_list_asks_first() {
    let (_scratch, mut server) = with_lenses("lists-remove");
    let refused = server
        .call("remove_from_list", &args(&[("list", "lens"), ("terms", "18mm, 85mm")]))
        .unwrap_err();
    assert!(refused.contains("18mm is on 1 shot (5A)"), "{refused}");
    assert!(refused.contains("Nothing was removed"), "{refused}");
    assert!(server.call("lists", &args(&[("list", "lens")])).unwrap().contains("85mm"));

    let said = server
        .call("remove_from_list", &args(&[("list", "lens"), ("terms", "18mm, 85mm"), ("clear_from_shots", "true")]))
        .expect("removes");
    assert!(said.contains("Cleared from 1 shot (5A)"), "{said}");
    assert!(!server.call("shots", &args(&[("scene", "5")])).unwrap().contains("18mm"));

    // Unused terms go without asking.
    server.call("remove_from_list", &args(&[("list", "lens"), ("terms", "35mm")])).expect("removes");
}

#[test]
fn a_rename_reaches_every_shot_and_order_is_only_order() {
    let (_scratch, mut server) = with_lenses("lists-rename");
    let said = server
        .call("rename_in_list", &args(&[("list", "lens"), ("from", "18mm"), ("to", "Cooke 18mm")]))
        .expect("renames");
    assert!(said.contains("on 1 shot (5A)"), "{said}");
    assert!(server.call("shots", &args(&[("scene", "5")])).unwrap().contains("Cooke 18mm"));

    server.call("rename_in_list", &args(&[("list", "lens"), ("from", "85mm"), ("to", "85MM")])).expect("recases");
    assert!(server.call("lists", &args(&[("list", "lens")])).unwrap().contains("85MM"));

    let ordered = server
        .call("order_list", &args(&[("list", "lens"), ("terms", "85MM, 35mm")]))
        .expect("orders");
    assert!(ordered.contains("85MM, 35mm, Cooke 18mm"), "{ordered}");
    let sorted = server.call("order_list", &args(&[("list", "lens"), ("sort", "number")])).expect("sorts");
    assert!(sorted.contains("Cooke 18mm, 35mm, 85MM"), "{sorted}");

    let coloured = server
        .call("colour_term", &args(&[("list", "lens"), ("term", "35MM"), ("colour", "#2b6cb0")]))
        .expect("colours");
    assert!(coloured.contains("35mm is 2B6CB0"), "{coloured}");
    assert!(server.call("lists", &args(&[("list", "lens")])).unwrap().contains(r#""colour":"2B6CB0""#));
}

/// **Plain or AV** (2026-09-30): an AV script arrives as rows, reads back
/// as rows, a shot ties to words in either column, and a layout alone lays
/// the script's own words out the other way.
#[test]
fn an_av_script_is_rows_video_beside_audio() {
    let (_scratch, mut server, _) = opened("avrows");
    make_commercial(&mut server);
    let rows = Json::Array(vec![
        Json::Object(vec![
            ("video".to_string(), Json::text("Open on a Polaroid.")),
            ("audio".to_string(), Json::text("VO: You remember your first.")),
        ]),
        Json::Object(vec![
            ("video".to_string(), Json::text("The flash fires.")),
            ("audio".to_string(), Json::text("SFX: A shutter.")),
        ]),
    ]);
    let said = server
        .call("set_script", &Json::Object(vec![("rows".to_string(), rows), ("section".to_string(), Json::text("Spot A"))]))
        .expect("sets");
    assert!(said.contains("Script set for Spot A"), "{said}");
    let script = server.call("script", &Json::Null).expect("lists");
    assert!(script.contains("\"layout\":\"av\""), "{script}");
    assert!(script.contains("\"video\":\"The flash fires.\",\"audio\":\"SFX: A shutter.\""), "{script}");
    assert!(!script.contains("\\u001d") && !script.contains("\\u001e"), "the marks never leave: {script}");

    server.call("add_scene", &args(&[("title", "Kitchen"), ("section", "Spot A")])).expect("adds");
    server.call("add_shot", &args(&[("scene", "1"), ("description", "Insert")])).expect("adds");
    let said = server.call("tie_shot", &args(&[("shot", "1A"), ("text", "The flash fires."), ("section", "Spot A")])).expect("ties");
    assert!(said.contains("1A quotes: The flash fires."), "{said}");

    // Plain and back: the words and the tie stay.
    let said = server.call("set_script", &args(&[("layout", "plain"), ("section", "Spot A")])).expect("lays out");
    assert!(said.contains("1 tie kept"), "{said}");
    let script = server.call("script", &Json::Null).expect("lists");
    assert!(script.contains("\"layout\":\"plain\""), "{script}");
    server.call("set_script", &args(&[("layout", "av"), ("section", "Spot A")])).expect("lays out");
    let script = server.call("script", &Json::Null).expect("lists");
    assert!(script.contains("\"layout\":\"av\"") && script.contains("\"shot\":\"1A\",\"text\":\"The flash fires.\""), "{script}");
    assert!(server.call("set_script", &args(&[("layout", "sideways")])).is_err());
}
