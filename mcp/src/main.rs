//! Line-delimited JSON-RPC over standard input and output.

use std::io::{self, BufRead, Write};

use shotlister_engine::DeviceId;
use shotlister_mcp::Server;

/// **This machine, as the operating system will say it.** Ref 186.
///
/// Not remembered anywhere on purpose: a name kept in preferences is the one
/// thing Migration Assistant copies onto a new Mac, and two machines insisting
/// they are one device is how edits get thrown away as duplicates of each
/// other. The platform UUID is a fact about the hardware and travels nowhere.
fn machine() -> String {
    let found = std::process::Command::new("/usr/sbin/ioreg")
        .args(["-rd1", "-c", "IOPlatformExpertDevice"])
        .output()
        .ok()
        .and_then(|out| String::from_utf8(out.stdout).ok())
        .and_then(|text| {
            let at = text.find("\"IOPlatformUUID\"")?;
            let rest = text[at..].split_once('=')?.1.trim_start();
            let inside = rest.strip_prefix('"')?;
            let end = inside.find('"')?;
            Some(inside[..end].to_string())
        });
    match found {
        Some(uuid) => format!("mac:{uuid}"),
        // Only reached where there is no I/O registry to ask. Weak — two
        // machines can share a host name — but still a fact about the machine,
        // where the old answer was the same everywhere by construction.
        None => format!(
            "host:{}",
            std::env::var("HOSTNAME").unwrap_or_else(|_| "unknown".to_string())
        ),
    }
}

/// FNV-1a, 64 bits. The same function `shared/DeviceIdentity.swift` uses, so
/// the Mac app, the phone, the bridge and this server all work a machine out
/// to the same number. Stability across builds is the whole requirement; this
/// is not a security choice and nothing here is a secret.
fn number(text: &str) -> u64 {
    let mut hash: u64 = 0xCBF2_9CE4_8422_2325;
    for byte in text.as_bytes() {
        hash ^= *byte as u64;
        hash = hash.wrapping_mul(0x0000_0100_0000_01B3);
    }
    hash
}

/// **What this server calls itself when it writes.**
///
/// It used to be the hash of the word `mcp`, which is the same number on every
/// machine in the world — so two Macs both talking to Claude about one film
/// were, to the sync log, a single device, and changes they made in the same
/// moment were dropped as duplicates. It is now worked out from the machine.
/// `SHOTLISTER_DEVICE` still overrides it, for a shell that knows better.
fn device() -> DeviceId {
    let name = match std::env::var("SHOTLISTER_DEVICE") {
        Ok(named) => named,
        Err(_) => format!("{}/mcp", machine()),
    };
    DeviceId(number(&name))
}

/// Which machine this is, told to the engine so it can notice when two of them
/// end up writing under one name.
fn installation() -> u64 {
    number(&machine())
}

fn main() {
    let mut server = Server::new_on(device(), installation());
    let stdin = io::stdin();
    let mut stdout = io::stdout();

    for line in stdin.lock().lines() {
        let line = match line {
            Ok(line) => line,
            Err(_) => break,
        };
        if line.trim().is_empty() {
            continue;
        }
        if let Some(reply) = server.handle(&line) {
            let _ = writeln!(stdout, "{reply}");
            let _ = stdout.flush();
        }
    }
}
