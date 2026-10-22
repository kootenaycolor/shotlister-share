//! A minimal ZIP writer.
//!
//! A spreadsheet file is a zip archive of XML, so writing one means writing this
//! first. Entries are stored rather than compressed: a shot list's XML is small,
//! and stored entries keep this to something that can be read and checked by eye
//! rather than a compressor nobody will audit.
//!
//! Output is deterministic — no timestamps — so the same list exports to
//! byte-identical files, which makes it testable.

pub struct ZipWriter {
    buffer: Vec<u8>,
    entries: Vec<Entry>,
}

struct Entry {
    name: String,
    crc: u32,
    size: u32,
    offset: u32,
}

const LOCAL_HEADER: u32 = 0x0403_4b50;
const CENTRAL_HEADER: u32 = 0x0201_4b50;
const END_OF_CENTRAL: u32 = 0x0605_4b50;
/// 1980-01-01. Fixed so exports are reproducible.
const DOS_DATE: u16 = 0x0021;
const DOS_TIME: u16 = 0x0000;

fn crc32_table() -> [u32; 256] {
    let mut table = [0u32; 256];
    let mut i = 0usize;
    while i < 256 {
        let mut value = i as u32;
        let mut bit = 0;
        while bit < 8 {
            value = if value & 1 == 1 {
                0xEDB8_8320 ^ (value >> 1)
            } else {
                value >> 1
            };
            bit += 1;
        }
        table[i] = value;
        i += 1;
    }
    table
}

pub fn crc32(data: &[u8]) -> u32 {
    let table = crc32_table();
    let mut crc = 0xFFFF_FFFFu32;
    for byte in data {
        crc = table[((crc ^ *byte as u32) & 0xFF) as usize] ^ (crc >> 8);
    }
    crc ^ 0xFFFF_FFFF
}

impl Default for ZipWriter {
    fn default() -> Self {
        ZipWriter::new()
    }
}

impl ZipWriter {
    pub fn new() -> ZipWriter {
        ZipWriter {
            buffer: Vec::new(),
            entries: Vec::new(),
        }
    }

    fn u16(&mut self, value: u16) {
        self.buffer.extend_from_slice(&value.to_le_bytes());
    }

    fn u32(&mut self, value: u32) {
        self.buffer.extend_from_slice(&value.to_le_bytes());
    }

    pub fn add(&mut self, name: &str, data: &[u8]) {
        let offset = self.buffer.len() as u32;
        let crc = crc32(data);
        let size = data.len() as u32;

        self.u32(LOCAL_HEADER);
        self.u16(20); // version needed
        self.u16(0); // flags
        self.u16(0); // stored
        self.u16(DOS_TIME);
        self.u16(DOS_DATE);
        self.u32(crc);
        self.u32(size); // compressed
        self.u32(size); // uncompressed
        self.u16(name.len() as u16);
        self.u16(0); // extra
        self.buffer.extend_from_slice(name.as_bytes());
        self.buffer.extend_from_slice(data);

        self.entries.push(Entry {
            name: name.to_string(),
            crc,
            size,
            offset,
        });
    }

    pub fn finish(mut self) -> Vec<u8> {
        let central_start = self.buffer.len() as u32;
        let entries = std::mem::take(&mut self.entries);

        for entry in &entries {
            self.u32(CENTRAL_HEADER);
            self.u16(20); // version made by
            self.u16(20); // version needed
            self.u16(0); // flags
            self.u16(0); // stored
            self.u16(DOS_TIME);
            self.u16(DOS_DATE);
            self.u32(entry.crc);
            self.u32(entry.size);
            self.u32(entry.size);
            self.u16(entry.name.len() as u16);
            self.u16(0); // extra
            self.u16(0); // comment
            self.u16(0); // disk
            self.u16(0); // internal attrs
            self.u32(0); // external attrs
            self.u32(entry.offset);
            self.buffer.extend_from_slice(entry.name.as_bytes());
        }

        let central_size = self.buffer.len() as u32 - central_start;

        self.u32(END_OF_CENTRAL);
        self.u16(0); // disk
        self.u16(0); // disk with central directory
        self.u16(entries.len() as u16);
        self.u16(entries.len() as u16);
        self.u32(central_size);
        self.u32(central_start);
        self.u16(0); // comment

        self.buffer
    }
}
