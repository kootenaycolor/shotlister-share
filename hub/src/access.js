/**
 * **Who may open a film, changed on his behalf** — one set of rules for the two
 * doors that change the list of people without a browser: the connector's
 * `set_access` (`mcp.js`) and the Projects Console's `/console/<film>/access`
 * (`consoleDoor` in `worker.js`, 2026-10-05).
 *
 * The Share popover (`public/share.js`) makes these same moves in the browser
 * and sends the whole list to `putPeople`. What it does is the specification:
 *
 * - **Add people by email** puts the address straight on the list with the
 *   role picked, Viewer or Editor — no invite, no message sent. An address
 *   already on it is refused.
 * - **A role is changed, or Remove takes them off.** He is the Owner, by
 *   either address: always an editor, never removed (`owners`).
 * - **General Access** turns the film's one link on and off. Off keeps the
 *   address, so a link already sent works again when it is turned back on.
 * - **A password** is made where the link is chosen: a random salt, and the
 *   hash of salt + word. The hub keeps the two hashes and never the word.
 * - **A new link replaces the old one** whole — the list's links become just
 *   that one, on, a viewer, no password — exactly what Copy Link does when
 *   there is nothing it can copy (`makeLink`). The key is made by whoever
 *   asks and checked against its hash here.
 *
 * Every function here changes the list it is given, in place; saving it, and
 * under which compare-and-set, is the caller's.
 */
import { EMAIL, owners, sha256Hex } from "./films.js";

/**
 * What a link's key looks like. Made by whoever asks and never by the hub,
 * which matches a presented key only by its hash — so this says what shape a
 * key may be, not what any key is.
 */
export const LINK_KEY = /^[A-Za-z0-9_-]{20,120}$/;
const HASH = /^[0-9a-f]{64}$/;
const SALT = /^[0-9a-f]{16,64}$/;

/**
 * **A refusal, with the words for it.** `said` is what the MCP's own refusals
 * carry, so the connector reports one of these as it reports its own; `code`
 * lets a door add its own hint; `status` is what an HTTP door answers.
 */
export class Refusal extends Error {
  constructor(said, code = "bad", status = 400) {
    super(said);
    this.said = said;
    this.code = code;
    this.status = status;
  }
}

/** The film's general link: the first that holds its key (`general()` in share.js). */
export function generalLink(list) {
  return list.links.find((l) => l && l.key) || null;
}

/** A link as the Share popover makes one: on, a viewer, no note, no end date, no password. */
export function freshLink(key, hash) {
  return { hash, key, role: "viewer", note: "", off: false, expires: null, salt: null, pass: null };
}

/**
 * Apply one ask to the list and answer what was done, in words.
 *
 *   add       [{ email, role }]   role `viewer` (the default) or `editor`
 *   role      [{ email, role }]   people already on the list
 *   remove    [email]
 *   replace   { key, hash, was }  a new general link; `was` is the hash of the
 *                                 link it replaces, null when there is none
 *   link      "anyone" | "restricted"
 *   password  null or "" clears it; { salt, pass } sets it; a plain string is
 *             hashed here (the connector's way — refused by the console door)
 *
 * In that order, so one ask can make a link and put a password on it.
 * `mint` makes a key when `link: "anyone"` finds no link; without it that is
 * refused, and the asker sends `replace` instead.
 */
export async function changeAccess(env, list, ask, { mint = null } = {}) {
  const said = [];
  const isOwner = (email) => owners(env).includes(email);
  const clean = (raw) => String(raw || "").toLowerCase().trim();
  const roleOf = (raw) => {
    const r = String(raw || "viewer").toLowerCase();
    if (r !== "viewer" && r !== "editor") throw new Refusal("A role is `viewer` or `editor`.");
    return r;
  };

  for (const one of Array.isArray(ask.add) ? ask.add : []) {
    const email = clean(one && one.email);
    if (!EMAIL.test(email)) throw new Refusal(`${one && one.email} is not an email address.`);
    if (list.people.some((p) => p.email === email)) throw new Refusal(`${email} is already on the list.`, "already", 409);
    list.people.push({ email, role: roleOf(one.role) });
    said.push(`added ${email}`);
  }
  for (const one of Array.isArray(ask.role) ? ask.role : []) {
    const email = clean(one && one.email);
    const person = list.people.find((p) => p.email === email);
    if (!person) throw new Refusal(`${email} is not on the list.`, "absent", 404);
    if (isOwner(email)) throw new Refusal(`${email} is him; he is always an editor.`, "owner", 403);
    person.role = roleOf(one.role);
    said.push(`${email} is ${person.role === "editor" ? "an editor" : "a viewer"}`);
  }
  for (const raw of Array.isArray(ask.remove) ? ask.remove : []) {
    const email = clean(raw);
    if (isOwner(email)) throw new Refusal(`${email} is him; he cannot be removed.`, "owner", 403);
    const at = list.people.findIndex((p) => p.email === email);
    if (at < 0) throw new Refusal(`${email} is not on the list.`, "absent", 404);
    list.people.splice(at, 1);
    said.push(`removed ${email}`);
  }

  if (ask.replace !== undefined) {
    const r = ask.replace;
    if (!r || typeof r !== "object" || Array.isArray(r)) throw new Refusal("`replace` is { key, hash, was }.");
    const key = String(r.key || "");
    const hash = String(r.hash || "");
    if (!LINK_KEY.test(key)) throw new Refusal("That is not a link's key.");
    if (!HASH.test(hash) || (await sha256Hex(key)) !== hash) throw new Refusal("That hash is not the key's.");
    // **Said, not assumed.** Replacing a link stops every address made from it
    // working, so the asker names the link it means to replace — and if that
    // is no longer the film's link, somebody else got there first.
    if (!("was" in r)) throw new Refusal("Say which link this replaces: `was`, its hash, or null when there is none.");
    const now = generalLink(list);
    if ((now ? now.hash : null) !== (r.was || null)) {
      throw new Refusal("The film's link is not the one named. Read it again.", "moved", 409);
    }
    const replacing = list.links.length > 0;
    list.links = [freshLink(key, hash)];
    said.push(replacing ? "a new link replaces the old one" : "anyone with the link can read it");
  }

  if (ask.link !== undefined) {
    if (ask.link !== "anyone" && ask.link !== "restricted") throw new Refusal("`link` is `anyone` or `restricted`.");
    const link = generalLink(list);
    if (ask.link === "anyone") {
      if (link) link.off = false;
      else if (mint) {
        const key = mint();
        list.links = [freshLink(key, await sha256Hex(key))];
      } else throw new Refusal("There is no link to turn on.", "nolink", 409);
      said.push("anyone with the link can read it");
    } else {
      if (link) link.off = true;
      said.push("only the people on the list can open it");
    }
  }

  if (ask.password !== undefined) {
    const link = list.links.find((l) => l && l.key && !l.off);
    if (!link) throw new Refusal("There is no link to put a password on.", "nolink", 409);
    const word = ask.password;
    if (word === null || word === "") {
      link.salt = null;
      link.pass = null;
      said.push("the link asks for no password");
    } else if (typeof word === "object" && !Array.isArray(word)) {
      const salt = String(word.salt || "");
      const pass = String(word.pass || "");
      if (!SALT.test(salt) || !HASH.test(pass)) throw new Refusal("A password is sent as { salt, pass }: hex, and the hash of salt + word.");
      link.salt = salt;
      link.pass = pass;
      said.push("the link asks for that password");
    } else {
      link.salt = randomHex(32);
      link.pass = await sha256Hex(link.salt + String(word));
      said.push("the link asks for that password");
    }
  }

  // He is on the list whatever was sent (`putPeople` keeps the same rule).
  for (const owner of owners(env).slice().reverse()) {
    if (!list.people.some((p) => p.email === owner)) list.people.unshift({ email: owner, role: "editor" });
  }
  return said;
}

function randomHex(chars) {
  const bytes = new Uint8Array(chars / 2);
  crypto.getRandomValues(bytes);
  return [...bytes].map((b) => b.toString(16).padStart(2, "0")).join("");
}
