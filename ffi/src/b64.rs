//! Base64, because image bytes have to cross a text boundary.
//!
//! Hand-written for the same reason the JSON is: it is a small, closed job and
//! the engine's dependency-free promise is worth more than the twenty lines.

const ALPHABET: &[u8; 64] = b"ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/";

pub fn encode(data: &[u8]) -> String {
    let mut out = String::with_capacity(data.len().div_ceil(3) * 4);
    for chunk in data.chunks(3) {
        let b = [
            chunk[0],
            *chunk.get(1).unwrap_or(&0),
            *chunk.get(2).unwrap_or(&0),
        ];
        let n = ((b[0] as u32) << 16) | ((b[1] as u32) << 8) | b[2] as u32;
        out.push(ALPHABET[(n >> 18) as usize & 63] as char);
        out.push(ALPHABET[(n >> 12) as usize & 63] as char);
        out.push(if chunk.len() > 1 {
            ALPHABET[(n >> 6) as usize & 63] as char
        } else {
            '='
        });
        out.push(if chunk.len() > 2 {
            ALPHABET[n as usize & 63] as char
        } else {
            '='
        });
    }
    out
}

pub fn decode(s: &str) -> Option<Vec<u8>> {
    fn value(c: u8) -> Option<u32> {
        match c {
            b'A'..=b'Z' => Some((c - b'A') as u32),
            b'a'..=b'z' => Some((c - b'a') as u32 + 26),
            b'0'..=b'9' => Some((c - b'0') as u32 + 52),
            b'+' => Some(62),
            b'/' => Some(63),
            _ => None,
        }
    }
    let clean: Vec<u8> = s.bytes().filter(|c| !c.is_ascii_whitespace()).collect();
    let mut out = Vec::with_capacity(clean.len() / 4 * 3);
    for group in clean.chunks(4) {
        if group.len() < 2 {
            return None;
        }
        let pad = group.iter().filter(|c| **c == b'=').count();
        let mut n = 0u32;
        for (i, c) in group.iter().enumerate() {
            let v = if *c == b'=' { 0 } else { value(*c)? };
            n |= v << (18 - 6 * i);
        }
        out.push((n >> 16) as u8);
        if pad < 2 {
            out.push((n >> 8) as u8);
        }
        if pad < 1 {
            out.push(n as u8);
        }
    }
    Some(out)
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn round_trips_every_length_of_tail() {
        for n in 0..32usize {
            let data: Vec<u8> = (0..n).map(|i| (i * 7 % 251) as u8).collect();
            let encoded = encode(&data);
            assert_eq!(decode(&encoded).unwrap(), data, "failed at length {n}");
        }
    }

    #[test]
    fn matches_the_known_answer() {
        assert_eq!(encode(b"Daybreak"), "RGF5YnJlYWs=");
        assert_eq!(decode("RGF5YnJlYWs=").unwrap(), b"Daybreak");
    }

    #[test]
    fn survives_bytes_that_are_not_text() {
        let data: Vec<u8> = (0..=255u8).collect();
        assert_eq!(decode(&encode(&data)).unwrap(), data);
    }
}
