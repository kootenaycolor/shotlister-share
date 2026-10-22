//! Read a printed-format draft the way an import would: what each line is,
//! what became a scene, what was set aside, and who is in it.
use shotlister_engine::cast::{self, Merging, Options};
use shotlister_engine::screenplay::{read_with, Detection, Status};

const DRAFT: &str = "\
1     INT. REMOTE MANSION (BEDROOM) - MORNING                    1

A rotary phone rings and rings.

                    HUSBAND
          Don't answer it.

                    ANYA
          It's my mother.

2     EXT. BALCONY - CONTINUOUS                                  2

Anya steps out into the cold.

3     EXT./ INT. MANSION - AFTERNOON - MONTAGE                   3

He moves through the house.

BATHROOM.

Steam on the mirror.

BEDROOM.

The bed is made.

HALLWAY.

                                        CONTINUED:

3     EXT./ INT. MANSION - AFTERNOON - MONTAGE                   3

                    HUSBAND (CONT'D)
          Anya?

4     INT. KITCHEN - NIGHT                                       4

                    RYAN
          Nobody's coming.

                    THE END
          Fade.
";

fn main() {
    let screenplay = read_with(DRAFT, &Detection::printed());

    println!("scenes found: {}", screenplay.scenes.len());
    for scene in &screenplay.scenes {
        let mark = if scene.accepted { "[x]" } else { "[ ]" };
        let note = match scene.status {
            Status::Scene => String::new(),
            Status::SubSlug { under } => {
                format!("  (a room inside {})", screenplay.scenes[under].label)
            }
        };
        println!("  {mark} {:<4} {}{note}", scene.label, scene.script.heading);
    }
    println!(
        "\ntaken: {} · set aside: {} · repeated headings ignored: {}",
        screenplay.accepted().len(),
        screenplay.scenes.len() - screenplay.accepted().len(),
        screenplay.duplicates_ignored
    );

    for (label, options) in [
        ("as found", Options::default()),
        ("speaking at least twice", Options::default().at_least(2)),
        ("merged hard", Options::merging(Merging::Aggressive)),
    ] {
        println!("\ncast — {label}:");
        for member in cast::read(&screenplay, options) {
            println!("  {:<10} {}x", member.display, member.speeches);
        }
    }
}
