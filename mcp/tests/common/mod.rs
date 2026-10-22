//! What every area's checks need: a real project on disk, opened.
#![allow(dead_code)]

use std::fs;
use std::path::PathBuf;

use shotlister_engine::DeviceId;
pub use shotlister_mcp::json::{self, Json};
use shotlister_mcp::Server;

pub struct Scratch(pub PathBuf);

impl Scratch {
    pub fn new(name: &str) -> Scratch {
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

/// Arguments as strings — the tools read numbers, flags and lists out of
/// strings too, which is how a chat often sends them.
pub fn args(pairs: &[(&str, &str)]) -> Json {
    Json::Object(pairs.iter().map(|(k, v)| (k.to_string(), Json::text(*v))).collect())
}

pub type Open = Server<shotlister_mcp::films::Disk>;

/// A server with a real project open.
pub fn opened(name: &str) -> (Scratch, Open) {
    let scratch = Scratch::new(name);
    let path = {
        let project = shotlister_storage::create(&scratch.0, "Daybreak", DeviceId(1)).expect("creates");
        project.path().to_path_buf()
    };
    let mut server = Server::new(DeviceId(2));
    server.call("open_project", &args(&[("path", path.to_str().unwrap())])).expect("opens");
    (scratch, server)
}

/// Call, and panic with the refusal if it is refused.
pub fn ok(server: &mut Open, tool: &str, pairs: &[(&str, &str)]) -> String {
    server.call(tool, &args(pairs)).unwrap_or_else(|e| panic!("{tool} refused: {e}"))
}

/// Call, and panic if it is not refused.
pub fn no(server: &mut Open, tool: &str, pairs: &[(&str, &str)]) -> String {
    match server.call(tool, &args(pairs)) {
        Ok(said) => panic!("{tool} should have refused, said: {said}"),
        Err(e) => e,
    }
}
