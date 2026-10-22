/**
 * The bucket's layout, for anything written in JavaScript.
 *
 * **`layout.json` beside this file is the one source**; this only turns it into
 * keys so a reader writes `keys.manifest(project)` rather than spelling
 * `p/<project>/manifest.json` for the sixty-fifth time. The relay's worker and
 * every file under `hub/src/` import this. Nothing here decides anything —
 * change a name in the JSON and every reader follows.
 *
 * The bucket is not the package. On disk a film keeps `changes/` and
 * `media/proxies/`; on the relay those are `logs/` and `media/` under
 * `p/<project>/`. The names *inside* — a log's, a mark's, a picture's — are
 * the engine's, and the patterns here repeat them so a made-up path can be
 * refused at the door.
 */
import LAYOUT from "./layout.json";

export { LAYOUT };

const film = (project) => `${LAYOUT.prefix}${project}/`;
const hub = LAYOUT.hub;

export const keys = {
  /** Everything a film holds, as a prefix to list. */
  film,
  manifest: (project) => `${film(project)}${LAYOUT.manifest}`,
  logs: (project) => `${film(project)}${LAYOUT.logs}`,
  log: (project, name) => `${film(project)}${LAYOUT.logs}${name}`,
  media: (project) => `${film(project)}${LAYOUT.media}`,
  medium: (project, name) => `${film(project)}${LAYOUT.media}${name}`,
  /** A device's record, beside the films and not inside any — the relay's own. */
  device: (id) => `${LAYOUT.devices}${id}.json`,
  devices: () => LAYOUT.devices,
  /**
   * A film's fate once it has been taken off — `archived` or `deleted` —
   * beside the films and not inside one, so the hub's listing never takes
   * the note for a film. Cleared the moment a log is put under the name
   * again, which is what putting a film back is. 2026-09-16.
   */
  gone: (project) => `${LAYOUT.gone}${project}.json`,
  /**
   * **Where a film's portal is set aside before the film is taken off**
   * (2026-10-04). `removeProject` deletes everything under the film's name,
   * and the portal's own files — who is invited, the links, What Viewers See,
   * the pages, documents and boards — live there and nowhere else. They are
   * copied here first, one folder per removal, beside the films and not inside
   * any, so nothing that lists `p/` ever sees them.
   */
  kept: (project, stamp) => `${LAYOUT.kept}${project}/${stamp}/`,
  /** `folder` is `media` or `docs` — the two the hub serves a file out of by name. */
  folder: (project, folder) => `${film(project)}${folder}/`,
  inFolder: (project, folder, name) => `${film(project)}${folder}/${name}`,

  // The hub's own records, beside the film's.
  people: (project) => `${film(project)}${hub.people}`,
  front: (project) => `${film(project)}${hub.front}`,
  visible: (project) => `${film(project)}${hub.visible}`,
  down: (project) => `${film(project)}${hub.down}`,
  /** A film's view links: one filtered shot list each (`hub/src/views.js`). */
  views: (project) => `${film(project)}${hub.views}`,
  /**
   * The mark that says this project is a portal with no film behind it —
   * the console's ask, 2026-09-16. Under the project's Notion page id, which
   * is the address that stands for a project from birth. The relay leaves a
   * prefix carrying this out of its film listing.
   */
  portal: (project) => `${film(project)}${hub.portal}`,
  pages: (project) => `${film(project)}${hub.pages}`,
  page: (project, slug) => `${film(project)}${hub.pages}${slug}.json`,
  pageHtml: (project, slug) => `${film(project)}${hub.pages}${slug}.html`,
  docs: (project) => `${film(project)}${hub.docs}`,
  doc: (project, file) => `${film(project)}${hub.docs}${file}`,
  decks: (project) => `${film(project)}${hub.decks}`,
  deck: (project, slug) => `${film(project)}${hub.decks}${slug}.json`,
  paper: (project, slug) => `${film(project)}${hub.decks}${slug}.paper.json`,
  paperHtml: (project, slug) => `${film(project)}${hub.decks}${slug}.paper.html`,
  press: (project, key) => `${film(project)}${hub.press}${key}.json`,
  cover: (project) => `${film(project)}${LAYOUT.cover}`,
  coverFor: (project, slug) => `${film(project)}${LAYOUT.coverFor.replace("{slug}", slug)}`,
  // The film's mark as a PNG — Safari's tab and the iPhone's home screen.
  icon: (project) => `${film(project)}${LAYOUT.icon}`,
};

/** The shapes a name may take. Anything else is refused at the door. */
export const names = {
  log: new RegExp(LAYOUT.names.log),
  mark: new RegExp(LAYOUT.names.mark),
  fold: new RegExp(LAYOUT.names.fold),
  medium: new RegExp(LAYOUT.names.medium),
  picture: new RegExp(LAYOUT.names.picture, "i"),
  project: new RegExp(LAYOUT.names.project),
};

/**
 * A clip is drawn by its poster, `<hash>.jpg` since 2026-09-15; an older film
 * holds the same under `.png`, and a reader that asks for the first takes the
 * second when that is what is there.
 */
export const poster = LAYOUT.poster;
