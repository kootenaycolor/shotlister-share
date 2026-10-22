#!/bin/bash
# Put the engine in the hub's pockets. **Two of them.**
#
#  - `public/shotlister_web.wasm` — the engine for a *browser*, from `web/`.
#    The page fetches it and draws the film.
#  - `src/mcp.wasm` — the engine *and the MCP's tools*, from
#    `mcpweb/`. The worker imports this one; it is deliberately not in `public/`,
#    because nothing should be able to fetch it.
#
# Both are built here and never edited here.
set -e
HERE="$(cd "$(dirname "$0")/.." && pwd)"

# **A double-clicked app does not get his shell's path.** Terminal opened from
# an applet has neither Rust nor Homebrew on it, so `cargo` is simply not a
# command — which is exactly how this failed on his machine the first time it
# was run.
export PATH="$HOME/.cargo/bin:/opt/homebrew/bin:$PATH"
rustup target add wasm32-unknown-unknown >/dev/null 2>&1 || true

cargo build --quiet --manifest-path "$HERE/web/Cargo.toml" --target wasm32-unknown-unknown --release
cp "$HERE/web/target/wasm32-unknown-unknown/release/shotlister_web.wasm" "$HERE/hub/public/"
echo "✓ hub/public/shotlister_web.wasm  ($(du -h "$HERE/hub/public/shotlister_web.wasm" | cut -f1))"

cargo build --quiet --manifest-path "$HERE/mcpweb/Cargo.toml" --target wasm32-unknown-unknown --release
cp "$HERE/mcpweb/target/wasm32-unknown-unknown/release/shotlister_mcpweb.wasm" "$HERE/hub/src/mcp.wasm"
echo "✓ hub/src/mcp.wasm                ($(du -h "$HERE/hub/src/mcp.wasm" | cut -f1))"
