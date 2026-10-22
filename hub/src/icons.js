/**
 * **The sidebar's and the Library's icons, one set.** A page's icon is chosen
 * by what it is (`defaultIcon`) unless he has picked one (`front.icons`). The
 * browser's copy is `public/icons.js`, written from the same table; `checks.sh`
 * fails if the two ever differ. Paths are on a 16 by 16 grid, drawn with the
 * app's own line weight (`mark` in `pages.js`).
 */
export const ROW_ICONS = {
 "library": "<path d=\"M3 2.8h2.6v8.8H3Z\"/><path d=\"M6.9 2.8h2.6v8.8H6.9Z\"/><path d=\"m10.6 3.6 2.5-.7 2 8.6-2.5.7Z\"/><path d=\"M1.8 14h12.4\"/>",
 "shotlist": "<rect x=\"2.5\" y=\"3\" width=\"11\" height=\"10\" rx=\"1.6\"/><path d=\"M5.4 6.6h5.2M5.4 9.4h3.2\"/>",
 "script": "<path d=\"M4 2.2h5l3 3v8.6H4Z\"/><path d=\"M9 2.2v3h3\"/><path d=\"M6.2 8.4h3.6M6.2 10.8h3.6\"/>",
 "diagrams": "<path d=\"M2.5 2.5h11v11h-11Z\"/><path d=\"M2.5 8h5v5.5M7.5 8V2.5M10 8h3.5\"/>",
 "locations": "<path d=\"M8 14s4.5-3.9 4.5-7.5a4.5 4.5 0 0 0-9 0C3.5 10.1 8 14 8 14Z\"/><circle cx=\"8\" cy=\"6.5\" r=\"1.6\"/>",
 "schedule": "<rect x=\"2.5\" y=\"3.5\" width=\"11\" height=\"10\" rx=\"1.6\"/><path d=\"M2.5 6.8h11M5.6 2v2.8M10.4 2v2.8\"/>",
 "boards": "<rect x=\"2.5\" y=\"2.5\" width=\"4.6\" height=\"4.6\" rx=\"1\"/><rect x=\"8.9\" y=\"2.5\" width=\"4.6\" height=\"4.6\" rx=\"1\"/><rect x=\"2.5\" y=\"8.9\" width=\"4.6\" height=\"4.6\" rx=\"1\"/><rect x=\"8.9\" y=\"8.9\" width=\"4.6\" height=\"4.6\" rx=\"1\"/>",
 "bible": "<path d=\"M3.6 2.5h8.8v11H3.6Z\"/><path d=\"M6.2 2.5v11\"/>",
 "camera": "<path d=\"M2.5 5.6h2.2l1-1.6h4.6l1 1.6h2.2v7.4h-11Z\"/><circle cx=\"8\" cy=\"9.2\" r=\"2.2\"/>",
 "people": "<circle cx=\"6\" cy=\"6\" r=\"2\"/><path d=\"M2.4 13c0-2.1 1.6-3.5 3.6-3.5s3.6 1.4 3.6 3.5\"/><circle cx=\"11.4\" cy=\"6.6\" r=\"1.5\"/><path d=\"M11.6 9.8c1.5.2 2.4 1.4 2.4 3.2\"/>",
 "documents": "<path d=\"M2 4.6a1 1 0 0 1 1-1h3.2l1.4 1.6H13a1 1 0 0 1 1 1V12a1 1 0 0 1-1 1H3a1 1 0 0 1-1-1Z\"/>",
 "deck": "<rect x=\"2.5\" y=\"3.2\" width=\"11\" height=\"7.6\" rx=\"1.4\"/><path d=\"M8 10.8v2.6M5.6 13.4h4.8\"/>",
 "page": "<rect x=\"3.5\" y=\"2.5\" width=\"9\" height=\"11\" rx=\"1.6\"/><path d=\"M6 6h4M6 8.6h4M6 11h2.2\"/>",
 "file": "<path d=\"M4 2.2h5l3 3v8.6H4Z\"/><path d=\"M9 2.2v3h3\"/>",
 "link": "<path d=\"M6.6 9.4a2.6 2.6 0 0 0 3.7 0l2-2a2.6 2.6 0 0 0-3.7-3.7l-.7.7\"/><path d=\"M9.4 6.6a2.6 2.6 0 0 0-3.7 0l-2 2a2.6 2.6 0 0 0 3.7 3.7l.7-.7\"/>",
 "list": "<path d=\"M5.5 4.5h8M5.5 8h8M5.5 11.5h8M2.8 4.5h.1M2.8 8h.1M2.8 11.5h.1\"/>",
 "film": "<rect x=\"2.5\" y=\"6.2\" width=\"11\" height=\"7.3\" rx=\"1\"/><path d=\"M2.6 6.2 2.2 3.8l11.2-1.6.4 2.4M5.2 3.5l1 2.5M8.5 3l1 2.6\"/>",
 "lens": "<circle cx=\"8\" cy=\"8\" r=\"5.4\"/><circle cx=\"8\" cy=\"8\" r=\"2.3\"/>",
 "image": "<rect x=\"2.5\" y=\"3\" width=\"11\" height=\"10\" rx=\"1.6\"/><circle cx=\"6\" cy=\"6.4\" r=\"1\"/><path d=\"M2.8 12l3.4-3.4 2.4 2.4 1.8-1.8 2.8 2.8\"/>",
 "palette": "<path d=\"M8 2.5a5.5 5.5 0 1 0 0 11c.9 0 1.3-.7 1-1.4-.3-.7 0-1.4.8-1.4h1.3A2.4 2.4 0 0 0 13.5 8 5.5 5.5 0 0 0 8 2.5Z\"/><circle cx=\"5.2\" cy=\"7.4\" r=\".5\"/><circle cx=\"7.8\" cy=\"5.2\" r=\".5\"/><circle cx=\"10.6\" cy=\"6.4\" r=\".5\"/>",
 "eye": "<path d=\"M1.8 8S4 3.8 8 3.8 14.2 8 14.2 8 12 12.2 8 12.2 1.8 8 1.8 8Z\"/><circle cx=\"8\" cy=\"8\" r=\"1.8\"/>",
 "bulb": "<path d=\"M8 2.2a4.2 4.2 0 0 0-2.4 7.6c.4.4.6.8.6 1.3v.4h3.6v-.4c0-.5.2-.9.6-1.3A4.2 4.2 0 0 0 8 2.2Z\"/><path d=\"M6.4 13.4h3.2\"/>",
 "clock": "<circle cx=\"8\" cy=\"8\" r=\"5.4\"/><path d=\"M8 4.8V8l2.2 1.4\"/>",
 "user": "<circle cx=\"8\" cy=\"5.6\" r=\"2.4\"/><path d=\"M3.2 13.5c.3-2.5 2.3-4 4.8-4s4.5 1.5 4.8 4\"/>",
 "star": "<path d=\"m8 2.2 1.8 3.7 4 .6-2.9 2.8.7 4L8 11.4l-3.6 1.9.7-4L2.2 6.5l4-.6Z\"/>",
 "heart": "<path d=\"M8 13.4S2.5 10.2 2.5 6.4A2.9 2.9 0 0 1 8 5.1a2.9 2.9 0 0 1 5.5 1.3c0 3.8-5.5 7-5.5 7Z\"/>",
 "flag": "<path d=\"M3.5 14V2.5M3.5 3h8l-1.6 2.6 1.6 2.6h-8\"/>",
 "bookmark": "<path d=\"M4.2 2.5h7.6V14L8 11.2 4.2 14Z\"/>",
 "tag": "<path d=\"M2.5 8.4V3.2a.7.7 0 0 1 .7-.7h5.2l5.1 5.1-5.7 5.7Z\"/><circle cx=\"5.4\" cy=\"5.4\" r=\".8\"/>",
 "pencil": "<path d=\"M3 13l.6-2.8 7.2-7.2 2.2 2.2-7.2 7.2Z\"/><path d=\"M9.6 4.2l2.2 2.2\"/>",
 "mail": "<rect x=\"2.2\" y=\"3.8\" width=\"11.6\" height=\"8.4\" rx=\"1.4\"/><path d=\"M2.6 5 8 9l5.4-4\"/>",
 "mic": "<rect x=\"6.2\" y=\"2.2\" width=\"3.6\" height=\"7\" rx=\"1.8\"/><path d=\"M3.8 7.6a4.2 4.2 0 0 0 8.4 0M8 11.8v2\"/>",
 "music": "<path d=\"M6 12.2V3.8l7-1.4v8.4\"/><circle cx=\"4.4\" cy=\"12.2\" r=\"1.6\"/><circle cx=\"11.4\" cy=\"10.8\" r=\"1.6\"/>",
 "car": "<path d=\"M2.5 10.5V8l1.4-3h8.2l1.4 3v2.5h-11Z\"/><path d=\"M2.5 8h11M4.8 10.5v1.5M11.2 10.5v1.5\"/>",
 "home": "<path d=\"M2.5 7.5 8 2.8l5.5 4.7M4 6.6v6.9h8V6.6M6.8 13.5v-3.4h2.4v3.4\"/>",
 "sun": "<circle cx=\"8\" cy=\"8\" r=\"2.6\"/><path d=\"M8 1.8v1.4M8 12.8v1.4M1.8 8h1.4M12.8 8h1.4M3.6 3.6l1 1M11.4 11.4l1 1M12.4 3.6l-1 1M4.6 11.4l-1 1\"/>",
 "moon": "<path d=\"M12.6 9.6A5.2 5.2 0 0 1 6.4 3.4a5.2 5.2 0 1 0 6.2 6.2Z\"/>",
 "bolt": "<path d=\"M8.8 1.8 3.8 9h3.6l-.8 5.2 5.6-7.6H8.4Z\"/>",
 "check": "<path d=\"M3 8.5 6.5 12 13 4.5\"/>",
 "shots": "<rect x=\"2.5\" y=\"3\" width=\"11\" height=\"10\" rx=\"1.6\"/><path d=\"M5.4 6.6h5.2M5.4 9.4h3.2\"/>",
 "board": "<rect x=\"2.5\" y=\"2.5\" width=\"4.6\" height=\"4.6\" rx=\"1\"/><rect x=\"8.9\" y=\"2.5\" width=\"4.6\" height=\"4.6\" rx=\"1\"/><rect x=\"2.5\" y=\"8.9\" width=\"4.6\" height=\"4.6\" rx=\"1\"/><rect x=\"8.9\" y=\"8.9\" width=\"4.6\" height=\"4.6\" rx=\"1\"/>"
};

/** What the right-click picker offers, in order. Every name is a key of `ROW_ICONS`. */
export const ICON_CHOICES = [
 "script",
 "page",
 "file",
 "link",
 "documents",
 "list",
 "shotlist",
 "film",
 "camera",
 "lens",
 "image",
 "boards",
 "palette",
 "eye",
 "bulb",
 "diagrams",
 "locations",
 "schedule",
 "clock",
 "people",
 "user",
 "bible",
 "deck",
 "star",
 "heart",
 "flag",
 "bookmark",
 "tag",
 "pencil",
 "mail",
 "mic",
 "music",
 "car",
 "home",
 "sun",
 "moon",
 "bolt",
 "check"
];

/** The Library's shelves, and the small icon each wears. */
export const SHELF_ICONS = {
 "Creative": "palette",
 "Technical": "camera",
 "Logistical": "schedule",
 "Other": "pencil",
 "Recently Opened": "clock"
};

/** The icon a page or document wears until he picks another. */
export function defaultIcon({ at = "", type = "", doc = false, file = false } = {}) {
  if (doc) return file ? "file" : "link";
  return ROW_ICONS[at] ? at : ROW_ICONS[type] ? type : "page";
}

/** His pick for `key` if he has made one and it is still a real icon, else `fallback`. */
export function iconName(icons, key, fallback) {
  const pick = icons && icons[key];
  return pick && ICON_CHOICES.includes(pick) ? pick : fallback;
}
