//! DEFLATE decompression.
//!
//! Needed because a spreadsheet is a compressed archive, and the ones people
//! send back come from Google Sheets and Excel rather than from us — so they are
//! compressed, whatever we chose to write.
//!
//! Written out rather than pulled in, for the same reason as the hash: the core
//! stays dependency-free and behaves identically on macOS, iOS and in
//! WebAssembly. It follows the structure of the reference implementation, which
//! is the one everybody checks against.

#[derive(Debug, PartialEq)]
pub enum InflateError {
    Truncated,
    BadBlockType,
    BadLength,
    BadCode,
    BadDistance,
}

struct Bits<'a> {
    data: &'a [u8],
    position: usize,
    bit: u32,
    accumulator: u32,
}

impl<'a> Bits<'a> {
    fn new(data: &'a [u8]) -> Bits<'a> {
        Bits {
            data,
            position: 0,
            bit: 0,
            accumulator: 0,
        }
    }

    /// DEFLATE packs bits least-significant first within each byte.
    fn take(&mut self, count: u32) -> Result<u32, InflateError> {
        while self.bit < count {
            let byte = *self.data.get(self.position).ok_or(InflateError::Truncated)?;
            self.accumulator |= (byte as u32) << self.bit;
            self.position += 1;
            self.bit += 8;
        }
        let value = self.accumulator & ((1u32 << count) - 1);
        self.accumulator >>= count;
        self.bit -= count;
        Ok(value)
    }

    fn align(&mut self) {
        self.accumulator = 0;
        self.bit = 0;
    }
}

/// A canonical Huffman table, held as symbol counts per code length plus the
/// symbols in order — which is all decoding needs, and avoids building a tree.
struct Huffman {
    counts: [u16; 16],
    symbols: Vec<u16>,
}

impl Huffman {
    fn new(lengths: &[u8]) -> Huffman {
        let mut counts = [0u16; 16];
        for length in lengths {
            counts[*length as usize] += 1;
        }
        counts[0] = 0;

        let mut offsets = [0u16; 16];
        for length in 1..16 {
            offsets[length] = offsets[length - 1] + counts[length - 1];
        }

        let mut symbols = vec![0u16; lengths.len()];
        for (symbol, length) in lengths.iter().enumerate() {
            if *length != 0 {
                symbols[offsets[*length as usize] as usize] = symbol as u16;
                offsets[*length as usize] += 1;
            }
        }

        Huffman { counts, symbols }
    }

    fn decode(&self, bits: &mut Bits) -> Result<u16, InflateError> {
        let mut code = 0i32;
        let mut first = 0i32;
        let mut index = 0i32;
        for length in 1..16 {
            code |= bits.take(1)? as i32;
            let count = self.counts[length] as i32;
            if code - first < count {
                return Ok(self.symbols[(index + (code - first)) as usize]);
            }
            index += count;
            first = (first + count) << 1;
            code <<= 1;
        }
        Err(InflateError::BadCode)
    }
}

const LENGTH_BASE: [u16; 29] = [
    3, 4, 5, 6, 7, 8, 9, 10, 11, 13, 15, 17, 19, 23, 27, 31, 35, 43, 51, 59, 67, 83, 99, 115, 131,
    163, 195, 227, 258,
];
const LENGTH_EXTRA: [u32; 29] = [
    0, 0, 0, 0, 0, 0, 0, 0, 1, 1, 1, 1, 2, 2, 2, 2, 3, 3, 3, 3, 4, 4, 4, 4, 5, 5, 5, 5, 0,
];
const DISTANCE_BASE: [u16; 30] = [
    1, 2, 3, 4, 5, 7, 9, 13, 17, 25, 33, 49, 65, 97, 129, 193, 257, 385, 513, 769, 1025, 1537,
    2049, 3073, 4097, 6145, 8193, 12289, 16385, 24577,
];
const DISTANCE_EXTRA: [u32; 30] = [
    0, 0, 0, 0, 1, 1, 2, 2, 3, 3, 4, 4, 5, 5, 6, 6, 7, 7, 8, 8, 9, 9, 10, 10, 11, 11, 12, 12, 13,
    13,
];
/// The order code-length codes are themselves written in.
const LENGTH_ORDER: [usize; 19] = [
    16, 17, 18, 0, 8, 7, 9, 6, 10, 5, 11, 4, 12, 3, 13, 2, 14, 1, 15,
];

fn fixed_tables() -> (Huffman, Huffman) {
    let mut literal = vec![8u8; 288];
    literal[144..256].iter_mut().for_each(|l| *l = 9);
    literal[256..280].iter_mut().for_each(|l| *l = 7);
    (Huffman::new(&literal), Huffman::new(&[5u8; 30]))
}

fn dynamic_tables(bits: &mut Bits) -> Result<(Huffman, Huffman), InflateError> {
    let literals = bits.take(5)? as usize + 257;
    let distances = bits.take(5)? as usize + 1;
    let code_lengths = bits.take(4)? as usize + 4;

    let mut lengths = [0u8; 19];
    for slot in LENGTH_ORDER.iter().take(code_lengths) {
        lengths[*slot] = bits.take(3)? as u8;
    }
    let code_table = Huffman::new(&lengths);

    // The code lengths are themselves compressed, with runs of repeats.
    let mut all = Vec::with_capacity(literals + distances);
    while all.len() < literals + distances {
        let symbol = code_table.decode(bits)?;
        match symbol {
            0..=15 => all.push(symbol as u8),
            16 => {
                let previous = *all.last().ok_or(InflateError::BadCode)?;
                let repeat = 3 + bits.take(2)?;
                for _ in 0..repeat {
                    all.push(previous);
                }
            }
            17 => {
                let repeat = 3 + bits.take(3)?;
                for _ in 0..repeat {
                    all.push(0);
                }
            }
            18 => {
                let repeat = 11 + bits.take(7)?;
                for _ in 0..repeat {
                    all.push(0);
                }
            }
            _ => return Err(InflateError::BadCode),
        }
    }
    if all.len() > literals + distances {
        return Err(InflateError::BadCode);
    }

    Ok((
        Huffman::new(&all[..literals]),
        Huffman::new(&all[literals..]),
    ))
}

/// Decompress a raw DEFLATE stream — no zlib or gzip wrapper.
pub fn inflate(data: &[u8]) -> Result<Vec<u8>, InflateError> {
    let mut bits = Bits::new(data);
    let mut out: Vec<u8> = Vec::new();

    loop {
        let last = bits.take(1)?;
        let kind = bits.take(2)?;

        match kind {
            0 => {
                // Stored: the rest of this byte is padding.
                bits.align();
                let start = bits.position;
                let length = u16::from_le_bytes([
                    *data.get(start).ok_or(InflateError::Truncated)?,
                    *data.get(start + 1).ok_or(InflateError::Truncated)?,
                ]) as usize;
                let complement = u16::from_le_bytes([
                    *data.get(start + 2).ok_or(InflateError::Truncated)?,
                    *data.get(start + 3).ok_or(InflateError::Truncated)?,
                ]);
                if length as u16 != !complement {
                    return Err(InflateError::BadLength);
                }
                let from = start + 4;
                let slice = data
                    .get(from..from + length)
                    .ok_or(InflateError::Truncated)?;
                out.extend_from_slice(slice);
                bits.position = from + length;
            }
            1 | 2 => {
                let (literal_table, distance_table) = if kind == 1 {
                    fixed_tables()
                } else {
                    dynamic_tables(&mut bits)?
                };

                loop {
                    let symbol = literal_table.decode(&mut bits)?;
                    match symbol {
                        0..=255 => out.push(symbol as u8),
                        256 => break,
                        257..=285 => {
                            let index = symbol as usize - 257;
                            let length = LENGTH_BASE[index] as usize
                                + bits.take(LENGTH_EXTRA[index])? as usize;

                            let code = distance_table.decode(&mut bits)? as usize;
                            if code >= DISTANCE_BASE.len() {
                                return Err(InflateError::BadDistance);
                            }
                            let distance = DISTANCE_BASE[code] as usize
                                + bits.take(DISTANCE_EXTRA[code])? as usize;
                            if distance > out.len() {
                                return Err(InflateError::BadDistance);
                            }

                            // Copies may overlap themselves — that is how runs
                            // are encoded — so this goes one byte at a time.
                            let start = out.len() - distance;
                            for offset in 0..length {
                                let byte = out[start + offset];
                                out.push(byte);
                            }
                        }
                        _ => return Err(InflateError::BadCode),
                    }
                }
            }
            _ => return Err(InflateError::BadBlockType),
        }

        if last == 1 {
            break;
        }
    }

    Ok(out)
}

/// Decompress a zlib stream — a two-byte header, DEFLATE, then a checksum.
pub fn zlib_inflate(data: &[u8]) -> Result<Vec<u8>, InflateError> {
    if data.len() < 2 {
        return Err(InflateError::Truncated);
    }
    inflate(&data[2..])
}
