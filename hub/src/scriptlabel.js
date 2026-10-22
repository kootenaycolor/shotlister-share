/**
 * **What a draft of the script is called, everywhere** (stage 5 step 4,
 * piece C, 2026-10-14). His ask: the console, Studio, the iPhone and the
 * portal show the same current draft, with the same name and date. This is
 * the one rule; Studio and the iPhone carry it in `shared/DraftLabel.swift`,
 * the console in `projects-console/scriptlabel.py`, and `hub/scriptdrive.mjs`
 * holds all three to the same cases (`hub/scriptlabel-cases.json`).
 *
 * The rule is the portal's Script page's own, from SL-1338:
 *
 * - **The name** is his own name for the draft when he gave it one. The
 *   Mac's stand-in, *Revision (9/27/26, 9:46 PM)*, gives way to the file's
 *   name without `.pdf`: the name the writer sent, the one the crew will say.
 * - **The date** is the day it came in, on his clock (Vancouver), as a person
 *   writes it: *Oct 12, 2026*.
 * - **The label** is the two joined: *Halcyon Pink · Oct 12, 2026*.
 */

const STAND_IN = /^Revision \(.*\)$/;

/** `{name, came_from}` → what the draft is called. */
export function draftName(d) {
  const own = String((d && d.name) || "").trim();
  if (own && !STAND_IN.test(own)) return own;
  return String((d && d.came_from) || "").split(/[\\/]/).pop().replace(/\.pdf$/i, "").trim() || own || "Script";
}

/** The file it came from, unless that is already the draft's name. */
export function draftAlso(d) {
  const file = String((d && d.came_from) || "").split(/[\\/]/).pop().trim();
  return file && file.replace(/\.pdf$/i, "") !== draftName(d) ? [file] : [];
}

/** The day a draft came in, as a person writes it — on his clock, not the server's. */
export function draftDate(stamp) {
  const when = new Date(String(stamp || ""));
  if (Number.isNaN(when.getTime())) return "";
  try {
    return new Intl.DateTimeFormat("en-US", {
      timeZone: "America/Vancouver", month: "short", day: "numeric", year: "numeric",
    }).format(when);
  } catch {
    return when.toISOString().slice(0, 10);
  }
}

/** `Halcyon Pink · Oct 12, 2026` — the name, and the date when there is one. */
export function draftLabel(d) {
  return [draftName(d), draftDate(d && d.dated)].filter(Boolean).join(" · ");
}
