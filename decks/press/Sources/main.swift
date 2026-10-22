// The press, as a program macOS can be told about.
//
// **Why a bundle and not the script.** The press reads a deck folder in
// `Library/CloudStorage` — his Google Drive — and macOS will not let a plain
// background program do that. Run by hand from a terminal it borrows the
// terminal's permission; run by launchd it has none, and the first automatic
// run on 2026-09-07 died on `Operation not permitted` reading `bible.json`.
// Full Disk Access is granted to a thing you can point at in System Settings,
// and this is that thing: it does nothing but run `tools/press.py` once, the
// way the Drive bridge's bundle does nothing but run the syncer. The grant is
// to this one program — never to `python3`, which would hand the same key to
// every script on the machine.
import Foundation

let me = URL(fileURLWithPath: CommandLine.arguments[0]).resolvingSymlinksInPath()
// …/decks/Shotlister Deck Press.app/Contents/MacOS/deckpress → …/decks
let decks = me.deletingLastPathComponent().deletingLastPathComponent()
    .deletingLastPathComponent().deletingLastPathComponent()
let script = decks.appendingPathComponent("tools/press.py").path

let run = Process()
run.executableURL = URL(fileURLWithPath: "/usr/bin/python3")
run.arguments = [script] + CommandLine.arguments.dropFirst()
run.standardOutput = FileHandle.standardOutput
run.standardError = FileHandle.standardError
do {
    try run.run()
} catch {
    FileHandle.standardError.write("the press could not start python: \(error)\n".data(using: .utf8)!)
    exit(2)
}
run.waitUntilExit()
exit(run.terminationStatus)
