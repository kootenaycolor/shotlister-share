/**
 * **A film's mark, as a pair: the outline of its Notion icon and its colour**
 * (2026-10-11, Projects Console without the Mac, stage 3 step 2) — `mark_of`
 * in `hub/refresh.py`, rule for rule, in one place the hub can reuse.
 *
 * His projects carry Notion's built-in icons (a broken heart in red for one of them) and the colour beside them. Both become the film's identity on
 * the portal: the outline is kept rather than the address, so a page a
 * director opens never goes to notion.so for a picture, and as an outline it
 * takes the film's colour by being told to.
 *
 * Exported for the next step (`mirror_mark`: the same pair written into the
 * Shotlister film, which the Mac's console still does), and used by the
 * portal's refresh (`refreshhub.js`) and Refresh button (`notion.js`).
 * Pure: the one outside call is passed in, so it can be checked in plain node.
 */

/**
 * Where a row's icon lives, or "" — only a Notion icon (`notion.so/icons/`)
 * counts. **A built-in icon arrives as a name and a colour, not an address**
 * (`{"type": "icon", "icon": {"name": "heartbroken", "color": "red"}}`); the
 * address is the two parts joined, held to plain words so nothing else can
 * be asked for.
 */
export function notionIconAddress(icon) {
  icon = icon || {};
  let address = "";
  if (icon.type === "external") address = (icon.external || {}).url || "";
  else if (icon.type === "file") address = (icon.file || {}).url || "";
  else if (icon.type === "icon") {
    const named = icon.icon || {};
    const who = String(named.name || "");
    const hue = String(named.color || "gray");
    if (/^[a-z0-9-]+$/.test(who) && /^[a-z_]+$/.test(hue)) address = `https://www.notion.so/icons/${who}_${hue}.svg`;
  }
  return String(address).includes("notion.so/icons/") ? address : "";
}

/**
 * The pair out of the icon's SVG: the first path's outline and the first
 * six-digit fill, upper-cased — `{}` when there is no outline. The same two
 * patterns as `mark_of` (`re.findall`, first match each).
 */
export function markFromSvg(drawing) {
  const text = String(drawing || "");
  const outline = /<path[^>]*\sd="([^"]+)"/.exec(text);
  const colour = /fill="(#[0-9A-Fa-f]{6})"/.exec(text);
  if (!outline) return {};
  return { path: outline[1], colour: (colour ? colour[1] : "").toUpperCase() };
}

/**
 * A Notion row's mark: `{path, colour}`, or `{}` when it has no Notion icon
 * or the icon will not come. `fetchText(address)` fetches the SVG and
 * answers its text, or "" (a refusal is no mark, as `curl -f` was).
 */
export async function markOfRow(row, fetchText) {
  const address = notionIconAddress((row || {}).icon);
  if (!address) return {};
  const drawing = await fetchText(address);
  return drawing ? markFromSvg(drawing) : {};
}
