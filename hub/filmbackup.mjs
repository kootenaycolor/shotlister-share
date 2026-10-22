#!/usr/bin/env node
/**
 * **Film backups: the server's zip against the Mac's own `backup.sh`, and the
 * tidy-up rule** (2026-10-13, stage 4 part C).
 *
 * For every film on this Mac (read only): its manifest, change files and
 * `remote.json` are copied into a throwaway folder, and the real
 * `~/Developer/shotlister/backup/backup.sh` is run on that copy with its
 * backups sent to another throwaway folder. The server's `makeZip` packs the
 * same files. Then, film by film:
 *
 * - the two zips hold the same entries (the Mac's `__MACOSX/` Finder labels
 *   aside), each with the same size, CRC and Unix mode, folders as folders;
 * - unpacked with `ditto -x -k` (what `restore.sh` does), the two trees are
 *   the same bytes (`diff -r`);
 * - the server's `remote.json` is the film's own, byte for byte where the
 *   film's keys happen to be in Shotlister's usual order, else the same JSON;
 * - the server's fingerprint is the `.seen-<stamp>` `backup.sh` wrote;
 * - the real `restore.sh`, pointed at a folder holding only the server's
 *   zip, lists it and restores it to a throwaway Desktop, and the restored
 *   film is the copied film, byte for byte.
 *
 * Then the tidy-up (`retention`) over made-up lists of dates.
 *
 * Nothing real is written: every folder is under the system's temp folder,
 * the real films are only read, and `backup.sh` is given a film name, so its
 * portal step never runs.
 *
 *     node hub/filmbackup.mjs            (FILMS="Let's Bake,ZED" for fewer)
 */
import { spawnSync } from "node:child_process";
import { mkdtempSync, mkdirSync, readdirSync, readFileSync, writeFileSync, existsSync, cpSync, statSync } from "node:fs";
import { tmpdir, homedir } from "node:os";
import { join, dirname } from "node:path";
import { fileURLToPath } from "node:url";
import { makeZip, remoteJson, fingerprint, retention, stampOf, KEEP, DAY_MS, folderName, CHANGE_NAME } from "./src/filmbackup.js";

const HERE = dirname(fileURLToPath(import.meta.url));
const SHOTLISTER = join(HERE, "..");
// The Mac's scripts: this checkout's, which are the same files as main's.
const BACKUP_SH = join(SHOTLISTER, "backup/backup.sh");
const RESTORE_SH = join(SHOTLISTER, "backup/restore.sh");
const FILMS = join(homedir(), "Documents/Shotlister");
let pass = 0, fail = 0;
const check = (what, good, why = "") => {
  if (good) pass += 1; else fail += 1;
  console.log(`  ${what.padEnd(92)} ${good ? "PASS" : `FAIL — ${String(why).slice(0, 600)}`}`);
};

/** The central directory of a zip: name → {size, crc, mode, method}. */
function entriesOf(bytes) {
  const v = new DataView(bytes.buffer, bytes.byteOffset, bytes.byteLength);
  let end = bytes.length - 22;
  while (end >= 0 && v.getUint32(end, true) !== 0x06054b50) end -= 1;
  const count = v.getUint16(end + 10, true);
  let at = v.getUint32(end + 16, true);
  const out = new Map();
  for (let i = 0; i < count; i++) {
    const nameLen = v.getUint16(at + 28, true), extraLen = v.getUint16(at + 30, true), commentLen = v.getUint16(at + 32, true);
    const name = new TextDecoder().decode(bytes.subarray(at + 46, at + 46 + nameLen));
    out.set(name, {
      method: v.getUint16(at + 10, true), crc: v.getUint32(at + 16, true), size: v.getUint32(at + 24, true),
      mode: (v.getUint32(at + 38, true) >>> 16) & 0o177777,
    });
    at += 46 + nameLen + extraLen + commentLen;
  }
  return out;
}

const run = (cmd, args, env = {}) => spawnSync(cmd, args, { encoding: "utf8", env: { ...process.env, ...env } });

const scratch = mkdtempSync(join(tmpdir(), "filmbackup-check-"));
const only = (process.env.FILMS || "").split(",").map((s) => s.trim()).filter(Boolean);
const films = readdirSync(FILMS).filter((n) => n.endsWith(".shotlist")).map((n) => n.slice(0, -9))
  .filter((n) => !only.length || only.includes(n));
check(`films on this Mac to compare (${films.join(", ")})`, films.length > 0);

for (const film of films) {
  console.log(`\n${film}`);
  const real = join(FILMS, `${film}.shotlist`);
  if (!existsSync(join(real, "changes"))) { check(`${film}: has change files`, false, "none"); continue; }
  // The copy backup.sh works on: exactly what it packs, nothing else.
  const work = join(scratch, film.replace(/[^A-Za-z0-9]/g, "_"));
  const filmsDir = join(work, "films"), macInto = join(work, "mac"), srvInto = join(work, "srv"), desk = join(work, "desk"), none = join(work, "nofilms");
  for (const d of [filmsDir, macInto, srvInto, desk, none]) mkdirSync(d, { recursive: true });
  const copy = join(filmsDir, `${film}.shotlist`);
  mkdirSync(copy);
  cpSync(join(real, "changes"), join(copy, "changes"), { recursive: true });
  cpSync(join(real, "manifest.json"), join(copy, "manifest.json"));
  if (existsSync(join(real, "remote.json"))) cpSync(join(real, "remote.json"), join(copy, "remote.json"));

  const mac = run("bash", [BACKUP_SH, film], { SHOTLISTER_FILMS: filmsDir, SHOTLISTER_BACKUPS: macInto });
  const line = (mac.stdout.split("\n").find((l) => l.startsWith("backed up:")) || "");
  const macZipPath = (/at "(.+)"$/.exec(line) || [])[1];
  check(`${film}: backup.sh made its zip in the throwaway folder`, mac.status === 0 && macZipPath && macZipPath.startsWith(macInto), mac.stdout + mac.stderr);
  if (!macZipPath) continue;
  const macZip = new Uint8Array(readFileSync(macZipPath));

  // What the relay holds of this film: only names the engine writes. A file
  // under any other name (Call Her Back has iCloud's "<log> 2.log" duplicates)
  // never reaches the relay, so the server's copy cannot have it.
  const all = readdirSync(join(copy, "changes")).filter((n) => !n.startsWith("."));
  const names = all.filter((n) => CHANGE_NAME.test(n));
  const macOnly = all.filter((n) => !CHANGE_NAME.test(n));
  check(`${film}: ${names.length} change files the relay keeps${macOnly.length ? `; ${macOnly.length} on this Mac only (${macOnly.slice(0, 2).join(", ")}…)` : ""}`, names.length > 0);
  const sized = (n) => ({ name: n, size: statSync(join(copy, "changes", n)).size });
  const changes = names.map((name) => ({ name, bytes: new Uint8Array(readFileSync(join(copy, "changes", name))), size: statSync(join(copy, "changes", name)).size }));
  const remoteFile = existsSync(join(copy, "remote.json")) ? readFileSync(join(copy, "remote.json"), "utf8") : "";
  const relay = remoteFile ? JSON.parse(remoteFile).project : "";
  const remote = remoteJson(relay);
  const when = Date.now();
  const srvZip = await makeZip({ title: film, relay, manifest: new Uint8Array(readFileSync(join(copy, "manifest.json"))), changes, remote }, when);

  // entries
  const a = entriesOf(macZip), b = entriesOf(srvZip);
  const macNames = [...a.keys()].filter((n) => !n.startsWith("__MACOSX/") && !macOnly.some((m) => n.endsWith(`/changes/${m}`)));
  const srvNames = [...b.keys()];
  const missing = macNames.filter((n) => !b.has(n)), extra = srvNames.filter((n) => !a.has(n));
  check(`${film}: same entries (${macNames.length}; the Mac's __MACOSX labels${macOnly.length ? " and Mac-only files" : ""} aside)`, !missing.length && !extra.length, `missing ${missing.slice(0, 5)} extra ${extra.slice(0, 5)}`);
  const differ = macNames.filter((n) => b.has(n) && !n.endsWith("remote.json") && (a.get(n).size !== b.get(n).size || a.get(n).crc !== b.get(n).crc || a.get(n).method !== b.get(n).method));
  check(`${film}: each entry the same size, CRC and packing (remote.json below)`, !differ.length, differ.slice(0, 5).map((n) => `${n} mac ${JSON.stringify(a.get(n))} srv ${JSON.stringify(b.get(n))}`).join("; "));
  // Modes: the relay keeps none, so the server writes the Mac's usual ones
  // (rw-r--r--, rwxr-xr-x); a film whose files are rw------- on disk (ZED)
  // comes back from a server copy readable as the others are.
  const usual = srvNames.every((n) => b.get(n).mode === (n.endsWith("/") ? 0o40755 : 0o100644));
  const otherModes = macNames.filter((n) => b.has(n) && a.get(n).mode !== b.get(n).mode);
  check(`${film}: the server's modes are rw-r--r-- / rwxr-xr-x${otherModes.length ? ` (${otherModes.length} are ${(a.get(otherModes[0]).mode & 0o777).toString(8)} on this Mac)` : ", as the Mac's"}`, usual);
  const dirsA = macNames.filter((n) => n.endsWith("/")), dirsB = srvNames.filter((n) => n.endsWith("/"));
  check(`${film}: the same two folder entries, first`, JSON.stringify(dirsA) === JSON.stringify(dirsB) && srvNames[0] === `${film}.shotlist/`, `${dirsA} vs ${dirsB}`);
  const sameRemote = remote === remoteFile;
  check(`${film}: remote.json ${sameRemote ? "byte for byte" : "the same JSON (the film's keys are in another order)"}`,
    sameRemote || JSON.stringify(Object.entries(JSON.parse(remote)).sort()) === JSON.stringify(Object.entries(JSON.parse(remoteFile)).sort()), `${remote} vs ${remoteFile}`);

  // unpacked as restore.sh unpacks
  const unA = join(work, "unpackedMac"), unB = join(work, "unpackedSrv");
  writeFileSync(join(work, "srv.zip"), srvZip);
  const xa = run("ditto", ["-x", "-k", macZipPath, unA]), xb = run("ditto", ["-x", "-k", join(work, "srv.zip"), unB]);
  check(`${film}: ditto -x -k opens both`, xa.status === 0 && xb.status === 0, xa.stderr + xb.stderr);
  const skip = [...(sameRemote ? [] : ["remote.json"]), ...macOnly].flatMap((n) => ["-x", n]);
  const diff = run("diff", ["-r", ...skip, unA, unB]);
  check(`${film}: unpacked, the two trees are the same bytes`, diff.status === 0, diff.stdout.slice(0, 400));

  // the fingerprint
  const seen = readdirSync(join(macInto, film)).filter((n) => n.startsWith(".seen-"));
  const macPrint = seen.length ? readFileSync(join(macInto, film, seen[0]), "utf8").trim() : "";
  // The same rule over the same files (all of them, as backup.sh counts).
  const srvPrint = await fingerprint(all.map(sized));
  check(`${film}: the server's fingerprint rule gives backup.sh's .seen (${srvPrint.slice(0, 10)}…)`, macPrint === srvPrint, `${macPrint} vs ${srvPrint}`);

  // restore.sh on the server's zip, in the layout the Drive folder has
  const stamp = stampOf(when);
  mkdirSync(join(srvInto, folderName(film)), { recursive: true });
  writeFileSync(join(srvInto, folderName(film), `${stamp}.zip`), srvZip);
  const env = { SHOTLISTER_BACKUPS: srvInto, SHOTLISTER_DESKTOP: desk, SHOTLISTER_FILMS: none };
  const listed = run("bash", [RESTORE_SH, "--list", film], env);
  check(`${film}: restore.sh --list names the server's copy`, listed.status === 0 && listed.stdout.trim() === `backup: "${film}"  ${stamp}  "${join(srvInto, film, `${stamp}.zip`)}"`, listed.stdout + listed.stderr);
  const back = run("bash", [RESTORE_SH, film], env);
  const to = (/to "(.+)"$/.exec(back.stdout.trim()) || [])[1];
  check(`${film}: restore.sh restores it to the throwaway Desktop`, back.status === 0 && /^restored: /.test(back.stdout) && to && to.startsWith(desk), back.stdout + back.stderr);
  if (to) {
    const same = run("diff", ["-r", ...skip, copy, to]);
    check(`${film}: the restored film is the film, byte for byte`, same.status === 0, same.stdout.slice(0, 400));
  }
}

// ── the tidy-up, over made-up dates ──────────────────────────────────────────
console.log("\nThe tidy-up");
const NOW = Date.UTC(2027, 5, 1, 12, 0);
const ago = (days) => NOW - days * DAY_MS;
const copy = (days) => ({ stamp: stampOf(ago(days)), at: ago(days) });
const same = (a, b) => JSON.stringify([...a].sort()) === JSON.stringify([...b].sort());

{
  // a daily copy for 200 days
  const list = Array.from({ length: 200 }, (_, i) => copy(i));
  const r = retention(list, NOW);
  check("a copy a day for 200 days: the 92 youngest (90 days + a day's grace) stay", r.keep.length === 92 && r.prune.length === 108, `${r.keep.length} kept, ${r.prune.length} pruned`);
  check("…the newest stays and nothing is put in forever/ (it is a day old)", r.keep.includes(list[0].stamp) && r.forever === null, JSON.stringify(r.forever));
  check("…nothing younger than 91 days goes", r.prune.every((s) => list.find((c) => c.stamp === s).at < ago(91)), r.prune[0]);
}
{
  // a film that went quiet: last copy 120 days ago
  const list = [copy(120), copy(130), copy(140), copy(300)];
  const r = retention(list, NOW);
  check("a quiet film: its newest copy stays, however old", same(r.keep, [list[0].stamp]) && same(r.prune, list.slice(1).map((c) => c.stamp)), JSON.stringify(r));
  check("…and is the one put in forever/", r.forever === list[0].stamp, String(r.forever));
  const again = retention(list, NOW, { forever: [list[0].stamp] });
  check("…once only: already in forever/, it is not put there again", again.forever === null && same(again.keep, [list[0].stamp]), JSON.stringify(again));
}
{
  // one copy, ever, a year old
  const list = [copy(365)];
  const r = retention(list, NOW);
  check("a film's only copy, a year old: kept, and put in forever/", same(r.keep, [list[0].stamp]) && !r.prune.length && r.forever === list[0].stamp, JSON.stringify(r));
}
{
  // exactly at the edge
  const list = [copy(0), copy(90), copy(91), { stamp: stampOf(ago(91) - 60000), at: ago(91) - 60000 }];
  const r = retention(list, NOW);
  check("at the edge: 90 and 91 days stay, a minute past 91 goes", same(r.keep, list.slice(0, 3).map((c) => c.stamp)) && same(r.prune, [list[3].stamp]), JSON.stringify(r));
}
{
  // two copies on the same day both stay when young; stamps that are not stamps are ignored
  const list = [{ stamp: "2027-05-30-0900", at: ago(2) }, { stamp: "2027-05-30-1400", at: ago(2) }, { stamp: "notes", at: ago(400) }];
  const r = retention(list, NOW);
  check("two copies on one day both stay; a name that is not a stamp is never touched", same(r.keep, ["2027-05-30-0900", "2027-05-30-1400"]) && !r.prune.length, JSON.stringify(r));
}
{
  // the rule is the one in KEEP: change it and the answer follows
  const list = Array.from({ length: 40 }, (_, i) => copy(i));
  const r = retention(list, NOW, {}, { ...KEEP, days: 30 });
  check("KEEP is the one place: 30 days instead of 90 keeps 32", r.keep.length === 32 && r.prune.length === 8, `${r.keep.length}/${r.prune.length}`);
  const noNewest = retention([copy(200)], NOW, {}, { ...KEEP, newest: false });
  check("…and without `newest`, an old only copy would go", noNewest.prune.length === 1, JSON.stringify(noNewest));
}
{
  // the stamp is his clock
  check("a stamp is his clock (America/Vancouver): 2026-10-14 11:05Z is 04:05 there", stampOf(Date.UTC(2026, 9, 14, 11, 5)) === "2026-10-14-0405", stampOf(Date.UTC(2026, 9, 14, 11, 5)));
  check("a folder name keeps his title and drops what a folder cannot hold", folderName("Let's Bake") === "Let's Bake" && folderName("A/B: C") === "A-B- C" && folderName("", "abc") === "abc");
}

console.log(`\n${pass} passed, ${fail} failed`);
process.exit(fail ? 1 : 0);
