#!/bin/bash
# Checking the Drive bridge.
#
# Runs the real worker against scratch folders — never his own projects and
# never his Drive. Nothing here opens a window or takes the front, so it is safe
# to run whatever he is doing.
#
# **It builds its own copy of the worker** and leaves the installed one alone.
# The automatic agent runs that bundle every fifteen seconds, so rebuilding it
# underneath itself is a race — and replacing it would cost the Full Disk Access
# grant, which is given to a particular signed program.

set -euo pipefail
cd "$(dirname "$0")"

ROOT="$(cd .. && pwd)"
export PATH="$HOME/.cargo/bin:$PATH"

( cd "$ROOT/ffi" && cargo build --release --offline --quiet )
LIB="$ROOT/ffi/target/release/libshotlister_ffi.a"
[ -f "$LIB" ] || { echo "the engine did not build"; exit 1; }

BUILD="$(mktemp -d)"
trap 'rm -rf "$BUILD"' EXIT

# The worker as it stands, and the checks that drive it. Always both, from
# source: checking whether a binary merely exists is how you spend twenty
# minutes reading failures from the code as it was before your change.
swiftc -O -target arm64-apple-macos14.0 \
  -import-objc-header "$ROOT/ffi/include/shotlister.h" \
  Sources/main.swift "$ROOT/shared/FileNames.swift" "$ROOT/shared/DeviceIdentity.swift" "$LIB" -o "$BUILD/drivesync"

swiftc -O -target arm64-apple-macos14.0 \
  -import-objc-header "$ROOT/ffi/include/shotlister.h" \
  Checks/main.swift "$LIB" -o "$BUILD/checks"

"$BUILD/checks" "$BUILD/drivesync"
