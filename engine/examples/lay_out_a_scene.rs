//! Print a screenplay as it would be printed, so a person can look at it.
use shotlister_engine::pages::{lay_out, LINES_PER_PAGE};
use shotlister_engine::screenplay::read;

const SCRIPT: &str = "\
34  INT. JAIL CORRIDOR - DAY  34

Sunlight through the high window. FRANK walks the length of it, past
doors that do not open, counting them the way he has counted them every
morning for eleven years.

FRANK
It never gets shorter.

GUARD (O.S.)
(bored)
Keep moving.

FRANK
I have been thinking about this for a very long time and I am not going to change my mind now, whatever you or anybody else has to say about it, and I would like that noted.

CUT TO:

35  EXT. PRISON YARD - NIGHT  35

Floodlights. Nobody moves.
";

fn main() {
    // A speech long enough to run over the foot of a page, so the break, the
    // `(MORE)` and the carried cue can all be looked at rather than trusted.
    let mut script = String::from(SCRIPT);
    script.push_str("\nFRANK\n");
    for at in 0..30 {
        script.push_str(&format!("Line {at} of a speech that will not stop. "));
    }
    script.push('\n');
    let screenplay = read(&script);
    let laid = lay_out(&screenplay);

    for page in &laid.pages {
        println!("\n┌─ page {} {}", page.number, "─".repeat(62));
        let mut row = 0;
        for line in &page.lines {
            while row < line.row {
                println!("│");
                row += 1;
            }
            let mark = if line.added { "+" } else { "│" };
            println!("{mark}{}{}", " ".repeat(line.indent), line.text);
            row += 1;
        }
        println!("└{}  ({row} of {LINES_PER_PAGE} rows used)", "─".repeat(68));
    }

    println!("\nscene lengths:");
    for extent in &laid.scenes {
        println!(
            "  scene {:<4} starts on page {}   {} ({} rows)",
            extent.label, extent.starts_on, extent.length(), extent.lines
        );
    }
    println!("\n{} pages in all", laid.pages_long());
}
