//! The worker's half, run on the Mac against a real film.
//!
//! `cargo run --example on_a_real_film -- "<film>.shotlist/changes"`
//!
//! Same `Bucket` and same `Server` the worker drives — the only difference is
//! that here the logs are handed over by the file system rather than fetched
//! out of the relay's bucket. If the tools answer here they answer there.
//!
//! **It writes nothing.** The change log a write produces is printed, not saved.

use std::env;
use std::fs;

use shotlister_engine::DeviceId;
use shotlister_mcp::Server;
use shotlister_mcpweb::Bucket;

fn main() {
    let folder = env::args().nth(1).expect("give me a folder of .log files");

    shotlister_engine::id::set_now_millis(1_756_700_000_000);
    shotlister_engine::id::set_seed(0x5eed_1234_abcd_ef01);

    let mut names: Vec<_> = fs::read_dir(&folder)
        .expect("that folder could not be read")
        .filter_map(|e| e.ok())
        .map(|e| e.path())
        .filter(|p| p.extension().map(|e| e == "log").unwrap_or(false))
        .collect();
    names.sort();

    let mut bucket = Bucket::new("deadbeefcafe", "checking", false, DeviceId(0x00b0_0b1e_5000_0001));
    for name in &names {
        bucket.take(&fs::read_to_string(name).expect("a log could not be read"));
    }
    bucket.settle();
    let mut server = Server::with(bucket);

    let ask = |server: &mut Server<Bucket>, line: &str| {
        let reply = server.handle(line).unwrap_or_default();
        // Just the readable part, so the output is worth looking at.
        let shown: String = reply.chars().take(360).collect();
        println!("{shown}\n");
    };

    println!("logs\t{}\n", names.len());
    ask(&mut server, r#"{"jsonrpc":"2.0","id":1,"method":"initialize"}"#);
    ask(&mut server, r#"{"jsonrpc":"2.0","id":2,"method":"tools/call","params":{"name":"summary"}}"#);
    ask(&mut server, r#"{"jsonrpc":"2.0","id":3,"method":"tools/call","params":{"name":"scenes"}}"#);
    ask(
        &mut server,
        r#"{"jsonrpc":"2.0","id":4,"method":"tools/call","params":{"name":"add_shot","arguments":{"scene":"1","description":"Checking that a worker can write","size":"CU"}}}"#,
    );
    ask(&mut server, r#"{"jsonrpc":"2.0","id":5,"method":"tools/call","params":{"name":"attach","arguments":{"path":"/tmp/x.png","scene":"1"}}}"#);

    let log = server.films().pending();
    println!("--- the change log a worker would put in the bucket ---");
    println!("{} bytes, {} lines", log.len(), log.lines().count());
    for line in log.lines().take(4) {
        println!("{}", &line.chars().take(200).collect::<String>());
    }
}
