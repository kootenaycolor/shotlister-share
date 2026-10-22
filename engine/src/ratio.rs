//! A frame ratio as a person types it.
//!
//! `2.39`, `2.39:1`, `1.85 : 1`, `9:16`, `4096x1716`, `16/9` all mean a width
//! over a height, and all come back as that one number. The Mac's Custom field,
//! the connector's `aspect_ratio` and the file's own setter read through here,
//! so a ratio one of them accepts is a ratio all of them accept.

/// The ratio a person typed, as width over height — or `None` when it is not
/// one, or is one no frame is (thinner than 1:5, wider than 10:1).
pub fn parse(said: &str) -> Option<f64> {
    let said = said.trim().to_lowercase();
    let parts: Vec<&str> = said
        .split(|c| c == ':' || c == 'x' || c == '×' || c == '/')
        .map(str::trim)
        .collect();
    let number = |s: &str| -> Option<f64> {
        let s = s.trim_end_matches(|c: char| c.is_alphabetic() || c.is_whitespace());
        s.parse::<f64>().ok().filter(|n| n.is_finite() && *n > 0.0)
    };
    let r = match parts.as_slice() {
        [one] => number(one)?,
        [wide, tall] => number(wide)? / number(tall)?,
        _ => return None,
    };
    (r > 0.2 && r < 10.0).then_some(r)
}

#[cfg(test)]
mod tests {
    use super::parse;

    #[test]
    fn every_way_of_saying_a_ratio() {
        let near = |said: &str, want: f64| {
            let got = parse(said).unwrap_or_else(|| panic!("{said} refused"));
            assert!((got - want).abs() < 1e-4, "{said} read as {got}");
        };
        near("2.39", 2.39);
        near("2.39:1", 2.39);
        near(" 1.85 : 1 ", 1.85);
        near("9:16", 0.5625);
        near("16x9", 16.0 / 9.0);
        near("4096 × 1716", 4096.0 / 1716.0);
        near("4/5", 0.8);
        near(".75", 0.75);
        for no in ["", "wide", "0", "1:0", "50", "1:20", "2:3:4", "-2"] {
            assert!(parse(no).is_none(), "{no} accepted");
        }
    }
}
