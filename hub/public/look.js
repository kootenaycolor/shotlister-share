// A picture on the portal, opened.
//
// **Why it exists.** His rule, 2026-09-05: *"have a media preview when
// clicking"*. On a record page every still is cropped to the film's aspect
// ratio, which is what makes a bible a set of comparisons rather than a
// scrapbook — but a crop is a layout, not the frame. So a click shows the
// picture whole. Whole is enough: his ruling, 2026-09-10, when asked whether
// the lightbox should get in closer than that. It does not.
//
// **One lightbox for every picture, not one per page.** Until 2026-09-10 this
// knew only the pictures of a Notion-fed page; a photograph on a location, a
// still on a reference board and a picture in a published deck could not be
// opened at all. Now anything wearing `data-look` opens here, and the value of
// that attribute is the gallery it belongs to — so ‹ › walk the wall you
// clicked, not every picture on the page.
//
// **The app's shot pop-out is deliberately not this.** That one lives inside
// `film.js`, knows about shots, carries the filmstrip and the storyboard
// arrows, and is drawn from a model these pages have never read. His ruling,
// 2026-09-10: keep it. The two share a look, not a body.
//
// **Delegated from the document, because the page is swapped under it.**
// `deep.js` replaces `.fh2` in place when you move along the rail, so anything
// bound to a picture at load would be bound to a picture that no longer exists
// three clicks later. Nothing here holds a reference to the page.
//
// **A published deck is looked into, not bound to.** `made.js` seals a deck's
// markup inside a shadow root so the portal's stylesheets cannot reach it, and
// the seal hides the picture from `e.target` too — a click arrives retargeted
// to the host. `composedPath()` sees through it, and every picture in the deck
// is one gallery.

const LOOKERS = "[data-look], .notion .nfig img";

let shown = null; // { list, at, box }

/** What has to hold still while a picture is open. */
function holds() {
  return [document.documentElement, ...document.querySelectorAll(".fh-pane")];
}

/** The element the click landed on, seen through any shadow root. */
function hit(e) {
  const path = e.composedPath ? e.composedPath() : [e.target];
  const first = path[0];
  return first && first.nodeType === 1 ? first : e.target;
}

/** Is this node inside a published deck's sealed box? */
function madeRootOf(node) {
  const root = node.getRootNode && node.getRootNode();
  return root && root.host && root.host.classList && root.host.classList.contains("madepage") ? root : null;
}

/** The picture a looker holds — itself, or the one inside it. */
function mediaOf(looker) {
  if (looker.matches("img, video")) return looker;
  return looker.querySelector("video, img");
}

/**
 * The gallery a picture belongs to, in page order.
 *
 * A `data-look` value names the set; the record page's pictures are one set;
 * a published deck's pictures are one set. Anything with nothing to show — an
 * empty frame — is left out, so the count is a count of pictures.
 */
function galleryOf(looker) {
  const made = madeRootOf(looker);
  // A tool's own frames (a slider, the ratio viewer) are marked `data-nolook`:
  // they are copies of pictures the page shows elsewhere, and stepping through
  // them would show each frame three times. Oddity's camera tests, 2026-09-22.
  if (made) return [...made.querySelectorAll("img")].filter((i) => i.src && !i.closest("[data-nolook]"));
  const set = looker.dataset ? looker.dataset.look : "";
  const all = set
    ? [...document.querySelectorAll(`[data-look="${CSS.escape(set)}"]`)]
    : [...document.querySelectorAll(".notion .nfig img")];
  return all.filter((l) => mediaOf(l));
}

/** Keep a clip inside its trim — the same rule `film.js` holds a list clip to. */
function holdTrim(video, from, to) {
  if (!from && !to) return;
  video.addEventListener("loadedmetadata", () => { video.currentTime = from; });
  video.addEventListener("timeupdate", () => {
    if (to > from && video.currentTime >= to) video.currentTime = from;
    else if (video.currentTime < from - 0.05) video.currentTime = from;
  });
}

function draw() {
  if (!shown) return;
  const looker = shown.list[shown.at];
  const one = mediaOf(looker);
  const stage = shown.box.querySelector(".fh-lookstage");
  stage.replaceChildren();
  // **A clip opens playing, whole, inside its trim.** In a list a clip is its
  // poster until it is looked at (`film.js` swaps a few near the middle into
  // real players), so the thing clicked may be an `<img>` carrying the clip's
  // address or a `<video>` already playing it. Either way the lightbox plays
  // it — and mutes it, because nothing on this site plays sound uninvited.
  const clip = one.dataset && one.dataset.clip ? one.dataset.clip : one.tagName === "VIDEO" ? one.currentSrc || one.src : "";
  if (clip) {
    const video = document.createElement("video");
    video.src = clip;
    if (one.dataset.poster) video.poster = one.dataset.poster;
    else if (one.poster) video.poster = one.poster;
    video.muted = true;
    video.defaultMuted = true;
    video.setAttribute("muted", "");
    video.setAttribute("playsinline", "");
    video.setAttribute("autoplay", "");
    video.setAttribute("loop", "");
    video.loop = true;
    video.playsInline = true;
    video.preload = "auto";
    holdTrim(video, Number(one.dataset.in) || 0, Number(one.dataset.out) || 0);
    stage.append(video);
    video.play().catch(() => {});
  } else {
    const img = document.createElement("img");
    img.src = one.currentSrc || one.src;
    img.alt = one.alt || "";
    stage.append(img);
  }
  const count = shown.box.querySelector(".fh-lookcount");
  count.textContent = shown.list.length > 1 ? `${shown.at + 1} of ${shown.list.length}` : (one.alt || "");
  for (const step of shown.box.querySelectorAll(".fh-lookstep")) {
    step.hidden = shown.list.length < 2;
  }
}

function shut() {
  if (!shown) return;
  const video = shown.box.querySelector("video");
  if (video) { video.pause(); video.removeAttribute("src"); video.load(); }
  shown.box.remove();
  shown = null;
  for (const held of holds()) held.style.removeProperty("overflow");
}

function step(by) {
  if (!shown || shown.list.length < 2) return;
  shown.at = (shown.at + by + shown.list.length) % shown.list.length;
  draw();
}

function open(looker) {
  const list = galleryOf(looker);
  const at = list.indexOf(looker);
  if (at < 0) return;
  shut();
  const box = document.createElement("div");
  box.className = "fh-look";
  box.innerHTML = `<button class="fh-lookstep back" type="button" aria-label="Previous">‹</button>
    <span class="fh-lookstage"></span>
    <button class="fh-lookstep on" type="button" aria-label="Next">›</button>
    <button class="fh-lookshut" type="button" aria-label="Close">✕</button>
    <div class="fh-lookcount"></div>`;
  // **The ground closes it and the picture does not.** Clicking the picture
  // itself to close is the fault every one of these has: you go to look closer
  // and it vanishes.
  box.addEventListener("click", (e) => {
    const on = e.target;
    if (on.closest(".fh-lookstep")) {
      e.stopPropagation();
      step(on.closest(".fh-lookstep").classList.contains("back") ? -1 : 1);
      return;
    }
    if (on.tagName === "IMG" || on.tagName === "VIDEO") return;
    shut();
  });
  // **A swipe steps, on a phone.** Sideways past a thumb's width and it is a
  // swipe; anything shorter is a tap, and the click above has that.
  let touch = null;
  box.addEventListener("touchstart", (e) => {
    touch = e.touches.length === 1 ? { x: e.touches[0].clientX, y: e.touches[0].clientY } : null;
  }, { passive: true });
  box.addEventListener("touchend", (e) => {
    if (!touch || !e.changedTouches.length) return;
    const dx = e.changedTouches[0].clientX - touch.x;
    const dy = e.changedTouches[0].clientY - touch.y;
    touch = null;
    if (Math.abs(dx) > 48 && Math.abs(dx) > Math.abs(dy) * 1.5) step(dx < 0 ? 1 : -1);
  }, { passive: true });
  document.body.append(box);
  // The page behind must not scroll while this is over it — on a phone that
  // reads as the picture drifting. **The record scrolls inside `.fh-pane`**, so
  // that is the element to hold still; the document is held too, for the pages
  // that do scroll themselves.
  for (const held of holds()) held.style.overflow = "hidden";
  shown = { list, at, box };
  draw();
}

document.addEventListener("click", (e) => {
  const on = hit(e);
  if (!on.closest) return;
  // **Inside the app, a frame that opens the shot pop-out is not ours.** A
  // shot's frame wears `data-open`; the pop-out has it. The lightbox takes
  // only what is marked for it.
  if (on.closest("[data-open], [data-nolook], .popout, .fh-look")) return;
  let looker = on.closest(LOOKERS);
  if (!looker && madeRootOf(on)) {
    const img = on.closest("img");
    if (img && img.src) looker = img;
  }
  if (!looker) return;
  if (!mediaOf(looker)) return;
  e.preventDefault();
  open(looker);
});

document.addEventListener("keydown", (e) => {
  if (!shown) return;
  if (e.key === "Escape") { e.preventDefault(); shut(); }
  else if (e.key === "ArrowLeft") { e.preventDefault(); step(-1); }
  else if (e.key === "ArrowRight") { e.preventDefault(); step(1); }
});

// **Moving along the rail takes the picture with it.** `deep.js` swaps the page
// without a navigation, so nothing else would ever close this.
window.addEventListener("popstate", shut);
document.addEventListener("swapped", shut);
document.addEventListener("click", (e) => {
  if (shown && e.target.closest("a[data-deep]")) shut();
}, true);
