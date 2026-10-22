//! Media identity, ordering, framing and cache policy.

use shotlister_engine::doc::f;
use shotlister_engine::hash::{sha256, Hash256, Sha256};
use shotlister_engine::media::{
    crop_to_ratio, plan_cache, proxy_for, Arrow, CacheEntry, MediaKind, ProxyFormat, Rect,
    STILL_MAX_EDGE, VIDEO_PROXY_HEIGHT,
};
use shotlister_engine::{DeviceId, Doc};

fn doc() -> Doc {
    let mut d = Doc::new(DeviceId(1));
    d.create_project("Daybreak");
    d
}

fn still(bytes: &[u8]) -> Hash256 {
    sha256(bytes)
}

// ---- hashing -----------------------------------------------------------

#[test]
fn sha256_matches_the_published_vectors() {
    assert_eq!(
        sha256(b"").to_hex(),
        "e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855"
    );
    assert_eq!(
        sha256(b"abc").to_hex(),
        "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad"
    );
    assert_eq!(
        sha256(b"abcdbcdecdefdefgefghfghighijhijkijkljklmklmnlmnomnopnopq").to_hex(),
        "248d6a61d20638b8e5c026930c3e6039a33ce45964ff2167f6ecedd419db06c1"
    );
}

#[test]
fn hashing_in_pieces_matches_hashing_at_once() {
    // A large video is fed in chunks rather than held in memory.
    let data: Vec<u8> = (0..10_000u32).map(|i| (i % 251) as u8).collect();

    let mut streaming = Sha256::new();
    for chunk in data.chunks(97) {
        streaming.update(chunk);
    }

    assert_eq!(streaming.finish(), sha256(&data));
}

#[test]
fn hashes_survive_a_round_trip_through_text() {
    let hash = sha256(b"a frame");
    assert_eq!(Hash256::from_hex(&hash.to_hex()), Some(hash));
    assert_eq!(hash.short().len(), 16);
    assert_eq!(Hash256::from_hex("not a hash"), None);
}

// ---- identity ----------------------------------------------------------

#[test]
fn the_same_frame_imported_twice_is_stored_once() {
    let mut d = doc();
    let hash = still(b"one frame");

    let first = d.add_media(hash, MediaKind::Image, 3840, 2160, 900_000, "still-01.jpg");
    // Same bytes, different name, dragged in from somewhere else entirely.
    let second = d.add_media(hash, MediaKind::Image, 3840, 2160, 900_000, "copy of still.jpg");

    assert_eq!(first, second);
}

#[test]
fn one_frame_can_be_used_by_several_shots_with_different_captions() {
    let mut d = doc();
    let scene = d.create_scene("34");
    let (a, _) = d.add_shot_to_scene(scene);
    let (b, _) = d.add_shot_to_scene(scene);
    let frame = d.add_media(still(b"ref"), MediaKind::Image, 1920, 1080, 400_000, "ref.jpg");

    d.attach_media(a, frame, "the look we want");
    d.attach_media(b, frame, "same light, tighter");

    // One file, two uses, two captions.
    assert_eq!(d.media_of(a), vec![frame]);
    assert_eq!(d.media_of(b), vec![frame]);
    let caption = d.get(d.media_refs(a)[0]).unwrap().text(f::CAPTION);
    assert_eq!(caption, Some("the look we want"));
}

#[test]
fn one_file_can_be_called_two_things_in_two_places() {
    // His two rules, which were in direct conflict until the name moved onto
    // the use: *"Photos in mood boards should keep their own names. Photos in
    // locations should be renamed based on the location and area"* (Ref 273),
    // and *"rather than duplicating it, they should share the same photo"*.
    //
    // One file wearing one name cannot do both — a photograph scouted at a
    // house and later hung on a wall of references came out on that wall
    // called `hillcrest-house-01.jpg`.
    let mut d = doc();
    let place = d.create_location("Hillcrest House");
    let board = d.create_board("Night Exteriors");
    let file = d.add_media(
        still(b"one photograph"),
        MediaKind::Image,
        3000,
        2000,
        800_000,
        "mountain-road.jpg",
    );

    let on_location = d.attach_media(place, file, "");
    let on_board = d.attach_media(board, file, "");
    d.set_media_ref_name(on_location, "hillcrest-house-01.jpg");
    d.set_media_ref_name(on_board, "mountain-road.jpg");

    // One stored file...
    assert_eq!(d.media_of(place), vec![file]);
    assert_eq!(d.media_of(board), vec![file]);
    // ...wearing the name each place has for it.
    assert_eq!(d.media_ref_name(on_location), "hillcrest-house-01.jpg");
    assert_eq!(d.media_ref_name(on_board), "mountain-road.jpg");
}

#[test]
fn a_use_with_no_name_of_its_own_wears_the_files() {
    // Every picture in every project written before this existed, and every
    // one attached by a command that says nothing about a name.
    let mut d = doc();
    let scene = d.create_scene("34");
    let file = d.add_media(still(b"ref"), MediaKind::Image, 1920, 1080, 400_000, "ref.jpg");
    let use_of_it = d.attach_media(scene, file, "");

    assert_eq!(d.media_ref_name(use_of_it), "ref.jpg");

    // And naming it nothing puts it back to the file's own name rather than
    // leaving it wearing an empty string.
    d.set_media_ref_name(use_of_it, "scouting-01.jpg");
    assert_eq!(d.media_ref_name(use_of_it), "scouting-01.jpg");
    d.set_media_ref_name(use_of_it, "");
    assert_eq!(d.media_ref_name(use_of_it), "ref.jpg");
}

// ---- ordering and the key frame ---------------------------------------

#[test]
fn a_shot_holds_several_frames_in_order() {
    let mut d = doc();
    let scene = d.create_scene("34");
    let (shot, _) = d.add_shot_to_scene(scene);

    // A move you have no video for, described as four panels.
    let panels: Vec<_> = (0..4)
        .map(|i| {
            let bytes = format!("panel {i}");
            d.add_media(
                still(bytes.as_bytes()),
                MediaKind::Image,
                1600,
                900,
                200_000,
                &format!("panel-{i}.png"),
            )
        })
        .collect();
    for panel in &panels {
        d.attach_media(shot, *panel, "");
    }

    assert_eq!(d.media_of(shot), panels);
}

#[test]
fn reordering_frames_writes_one_change() {
    let mut d = doc();
    let scene = d.create_scene("34");
    let (shot, _) = d.add_shot_to_scene(scene);
    let one = d.add_media(still(b"1"), MediaKind::Image, 100, 100, 10, "1.png");
    let two = d.add_media(still(b"2"), MediaKind::Image, 100, 100, 10, "2.png");
    let three = d.add_media(still(b"3"), MediaKind::Image, 100, 100, 10, "3.png");
    d.attach_media(shot, one, "");
    let r2 = d.attach_media(shot, two, "");
    let r3 = d.attach_media(shot, three, "");

    let before = d.changes().len();
    d.move_media_to(r3, 0);

    assert_eq!(d.changes().len() - before, 1);
    assert_eq!(d.media_of(shot), vec![three, one, two]);

    // And into the middle.
    d.move_media_to(r2, 1);
    assert_eq!(d.media_of(shot), vec![three, two, one]);
}

#[test]
fn the_first_frame_attached_becomes_the_key_frame() {
    let mut d = doc();
    let scene = d.create_scene("34");
    let (shot, _) = d.add_shot_to_scene(scene);
    let first = d.add_media(still(b"a"), MediaKind::Image, 100, 100, 10, "a.png");
    let second = d.add_media(still(b"b"), MediaKind::Image, 100, 100, 10, "b.png");

    d.attach_media(shot, first, "");
    d.attach_media(shot, second, "");

    assert_eq!(d.key_frame(shot), Some(first));
}

#[test]
fn the_key_frame_can_be_chosen_and_recovers_if_it_is_removed() {
    let mut d = doc();
    let scene = d.create_scene("34");
    let (shot, _) = d.add_shot_to_scene(scene);
    let first = d.add_media(still(b"a"), MediaKind::Image, 100, 100, 10, "a.png");
    let second = d.add_media(still(b"b"), MediaKind::Image, 100, 100, 10, "b.png");
    d.attach_media(shot, first, "");
    let ref_second = d.attach_media(shot, second, "");

    d.set_key_frame(shot, ref_second);
    assert_eq!(d.key_frame(shot), Some(second));

    // Removing the chosen one must not leave the shot blank in the table.
    d.detach_media(ref_second);
    assert_eq!(d.key_frame(shot), Some(first));
}

/// **The last use takes the record with it.** His ruling, 2026-09-19. A
/// file still used elsewhere keeps its record; a shot deleted takes its
/// frames' records the same way; and undo brings the lot back.
#[test]
fn a_file_whose_last_use_goes_is_gone_and_a_shared_one_stays() {
    let mut d = doc();
    let scene = d.create_scene("34");
    let (shot, _) = d.add_shot_to_scene(scene);
    let (other, _) = d.add_shot_to_scene(scene);
    let used = d.add_media(still(b"used"), MediaKind::Image, 100, 100, 10, "used.png");
    let dropped = d.add_media(still(b"dropped"), MediaKind::Image, 100, 100, 10, "old.png");
    d.attach_media(shot, used, "");
    d.attach_media(other, used, "");
    let stale = d.attach_media(shot, dropped, "");

    d.detach_media(stale);
    assert!(d.get(dropped).is_none(), "nothing points at it: gone");
    assert!(d.orphaned_media().is_empty());
    d.undo();
    assert!(d.get(dropped).is_some(), "and back with the use");
    d.detach_media(stale);

    // The shot goes; `used` is on the other shot too, so it stays.
    let placement = d.placements_in_scene(scene)[0];
    d.delete_placement(placement);
    assert!(d.get(used).is_some());
    let placement = d.placements_in_scene(scene)[0];
    d.delete_placement(placement);
    assert!(d.get(used).is_none(), "its last use went with the second shot");
}

// ---- proxies -----------------------------------------------------------

#[test]
fn a_big_still_gets_a_smaller_proxy_and_a_small_one_is_left_alone() {
    let big = proxy_for(MediaKind::Image, 6000, 4000);
    assert_eq!(big.format, ProxyFormat::Still);
    assert_eq!(big.target, STILL_MAX_EDGE);

    // Re-encoding something already small costs quality and saves nothing.
    let small = proxy_for(MediaKind::Image, 1200, 800);
    assert_eq!(small.target, 0);
}

#[test]
fn video_is_proxied_to_roughly_720p() {
    let clip = proxy_for(MediaKind::Video, 3840, 2160);
    assert_eq!(clip.format, ProxyFormat::Video);
    assert_eq!(clip.target, VIDEO_PROXY_HEIGHT);

    let already_small = proxy_for(MediaKind::Video, 1280, 720);
    assert_eq!(already_small.target, 0);
}

#[test]
fn a_gif_stays_animated() {
    let gif = proxy_for(MediaKind::Gif, 1200, 900);
    assert_eq!(gif.format, ProxyFormat::Animation);
}

#[test]
fn file_kinds_are_guessed_only_as_a_fallback() {
    assert_eq!(MediaKind::guess_from_name("frame.JPG"), MediaKind::Image);
    assert_eq!(MediaKind::guess_from_name("clip.mov"), MediaKind::Video);
    assert_eq!(MediaKind::guess_from_name("loop.gif"), MediaKind::Gif);
    // The prototype sniffed extensions and mislabelled anything without one.
    assert_eq!(
        MediaKind::guess_from_name("https://example.com/asset"),
        MediaKind::Other
    );
    assert!(MediaKind::Video.is_moving());
    assert!(MediaKind::Gif.is_moving());
    assert!(!MediaKind::Image.is_moving());
}

// ---- aspect masking ----------------------------------------------------

#[test]
fn a_wide_frame_crops_the_sides_and_a_tall_one_crops_top_and_bottom() {
    // 16:9 still shown at 2.39 — take a band out of the middle.
    let scope = crop_to_ratio(1920, 1080, 2.39);
    assert_eq!(scope.width, 1920);
    assert!(scope.height < 1080);
    assert_eq!(scope.x, 0);
    assert_eq!(scope.y, (1080 - scope.height) / 2, "must be centred");

    // A phone photo shown at 16:9 — take a slice out of the middle.
    let upright = crop_to_ratio(1080, 1920, 1.78);
    assert_eq!(upright.width, 1080);
    assert!(upright.height < 1920);
}

#[test]
fn a_frame_already_at_the_ratio_is_untouched() {
    let exact = crop_to_ratio(1920, 1080, 1920.0 / 1080.0);
    assert_eq!(
        exact,
        Rect {
            x: 0,
            y: 0,
            width: 1920,
            height: 1080
        }
    );
}

#[test]
fn crop_maths_does_not_fall_over_on_nonsense() {
    assert_eq!(crop_to_ratio(0, 0, 2.39).width, 0);
    assert_eq!(crop_to_ratio(100, 100, 0.0).width, 100);
}

// ---- cache -------------------------------------------------------------

fn entry(doc: &mut Doc, name: &str, bytes: u64, last_used: u64, pinned: bool) -> CacheEntry {
    let media = doc.add_media(
        still(name.as_bytes()),
        MediaKind::Image,
        100,
        100,
        bytes,
        name,
    );
    CacheEntry {
        media,
        bytes,
        last_used,
        pinned,
    }
}

#[test]
fn the_cache_keeps_what_was_used_most_recently() {
    let mut d = doc();
    let old = entry(&mut d, "old", 100, 1, false);
    let recent = entry(&mut d, "recent", 100, 9, false);
    let middling = entry(&mut d, "middling", 100, 5, false);

    let plan = plan_cache(&[old, recent, middling], 200);

    assert_eq!(plan.keep, vec![recent.media, middling.media]);
    assert_eq!(plan.evict, vec![old.media]);
    assert_eq!(plan.kept_bytes, 200);
    assert!(!plan.over_budget);
}

#[test]
fn pinned_files_are_never_dropped() {
    let mut d = doc();
    // A shoot day pinned for somewhere with no signal.
    let pinned = entry(&mut d, "day-3", 500, 1, true);
    let recent = entry(&mut d, "recent", 100, 9, false);

    let plan = plan_cache(&[pinned, recent], 200);

    assert!(plan.keep.contains(&pinned.media));
    assert!(plan.evict.contains(&recent.media));
    // Saying the budget is too small beats quietly discarding what was asked for.
    assert!(plan.over_budget);
}

#[test]
fn an_empty_cache_plans_nothing() {
    let plan = plan_cache(&[], 1000);
    assert!(plan.keep.is_empty());
    assert!(plan.evict.is_empty());
    assert!(!plan.over_budget);
}

// ---- media survives the log --------------------------------------------

#[test]
fn media_comes_back_after_a_save_and_reopen() {
    use shotlister_engine::format::{decode_log, encode_log};
    use shotlister_engine::FORMAT_VERSION;

    let mut d = doc();
    let scene = d.create_scene("34");
    let (shot, _) = d.add_shot_to_scene(scene);
    let frame = d.add_media(still(b"panel"), MediaKind::Image, 1600, 900, 200_000, "p.png");
    d.attach_media(shot, frame, "storyboard panel 1");

    let text = encode_log(FORMAT_VERSION, d.changes(), &[]);
    let log = decode_log(&text).unwrap();
    let mut reopened = Doc::new(DeviceId(2));
    reopened.merge(log.changes);

    assert_eq!(reopened.media_of(shot), vec![frame]);
    assert_eq!(reopened.key_frame(shot), Some(frame));
    assert_eq!(reopened.media_kind(frame), Some(MediaKind::Image));
}

// ---- filmstrip for the outline ----------------------------------------

#[test]
fn a_scene_offers_its_first_frames_in_story_order() {
    let mut d = doc();
    let scene = d.create_scene("34");

    let mut expected = Vec::new();
    for index in 0..7 {
        let (shot, _) = d.add_shot_to_scene(scene);
        let bytes = format!("frame {index}");
        let media = d.add_media(
            still(bytes.as_bytes()),
            MediaKind::Image,
            1600,
            900,
            1000,
            "f.png",
        );
        d.attach_media(shot, media, "");
        expected.push(media);
    }

    assert_eq!(d.scene_key_frames(scene, 5), expected[..5].to_vec());
}

#[test]
fn shots_without_a_frame_are_skipped_rather_than_leaving_gaps() {
    let mut d = doc();
    let scene = d.create_scene("34");

    d.add_shot_to_scene(scene); // no frame
    let (has_one, _) = d.add_shot_to_scene(scene);
    d.add_shot_to_scene(scene); // no frame
    let frame = d.add_media(still(b"only"), MediaKind::Image, 1600, 900, 10, "f.png");
    d.attach_media(has_one, frame, "");

    assert_eq!(d.scene_key_frames(scene, 5), vec![frame]);
}

#[test]
fn a_scene_carries_attachments_but_never_a_lead_frame() {
    let mut d = Doc::new(DeviceId(1));
    d.create_project("Daybreak");
    let scene = d.create_scene("34");
    let (shot, _) = d.add_shot_to_scene(scene);

    // A shot's first frame becomes its lead — the table draws it.
    let frame = d.add_media(sha256(b"a frame"), MediaKind::Image, 100, 42, 9, "f.png");
    d.attach_media(shot, frame, "");
    assert!(d.key_frame(shot).is_some(), "a shot's first frame leads");

    // A scene's first attachment does not: a scene owns papers, not frames,
    // and its standing picture is read from its shots.
    let plan = d.add_media(sha256(b"a plan"), MediaKind::Image, 900, 600, 12, "plan.png");
    let pinned = d.attach_media(scene, plan, "");
    // Nothing is *crowned*: the scene's record carries no `key_media`. (Asking
    // `key_frame` would still answer, because it falls back to the first file
    // — which is right for a shot and is why the stamp is the honest test.)
    assert!(
        d.get(scene).and_then(|r| r.ref_id(f::KEY_MEDIA)).is_none(),
        "a scene wears no lead frame"
    );
    assert_eq!(d.media_refs(scene), vec![pinned], "but it does carry the file");
}

// ---- a name that tells the truth about its bytes ------------------------
//
// Ref 193. A photograph off an iPhone arrives called `IMG_4523.HEIC` and is
// re-encoded to JPEG on the way in, because HEIC is a format half the world
// cannot open. Its name was kept exactly as it came — his rule, and the right
// one — but the extension is part of the name, so the project held JPEG bytes
// promising HEIC, and the Drive bridge wrote that promise into Google Drive.

#[test]
fn a_re_encoded_photograph_stops_claiming_to_be_heic() {
    assert_eq!(
        shotlister_engine::name_with_extension("IMG_4523.HEIC", "jpg"),
        "IMG_4523.jpg"
    );
    // The stem is the part his rule is about, and it survives untouched —
    // this must never collapse to `pasted.jpg`.
    assert_eq!(
        shotlister_engine::name_with_extension("Kitchen — north wall.heif", "jpg"),
        "Kitchen — north wall.jpg"
    );
    // A clip shrunk on the way in, same story.
    assert_eq!(
        shotlister_engine::name_with_extension("IMG_0912.MOV", "mp4"),
        "IMG_0912.mp4"
    );
}

#[test]
fn a_name_that_is_already_honest_is_left_exactly_alone() {
    // Including its capitals. Somebody's file is not ours to tidy.
    assert_eq!(
        shotlister_engine::name_with_extension("IMG_4523.JPG", "jpg"),
        "IMG_4523.JPG"
    );
    // Two spellings of one format are one format.
    assert_eq!(
        shotlister_engine::name_with_extension("scan.jpeg", "jpg"),
        "scan.jpeg"
    );
    assert_eq!(
        shotlister_engine::name_with_extension("plate.tiff", "tif"),
        "plate.tiff"
    );
    assert_eq!(
        shotlister_engine::name_with_extension("permit.pdf", "pdf"),
        "permit.pdf"
    );
}

#[test]
fn an_extension_is_never_replaced_across_a_format_family() {
    // The guard rail. A permit dropped on a scene arrives as `permit.pdf` from
    // a shell whose `ext` argument is still its default of `png`; renaming it
    // to `permit.png` would be a worse lie than the one being fixed.
    assert_eq!(
        shotlister_engine::name_with_extension("permit.pdf", "png"),
        "permit.pdf"
    );
    // A picture is never talked into being a clip, or the other way round.
    assert_eq!(
        shotlister_engine::name_with_extension("board.png", "mp4"),
        "board.png"
    );
    assert_eq!(
        shotlister_engine::name_with_extension("take.mov", "jpg"),
        "take.mov"
    );
}

#[test]
fn a_name_with_no_extension_gains_one() {
    assert_eq!(
        shotlister_engine::name_with_extension("permit", "pdf"),
        "permit.pdf"
    );
    // A dotfile is left exactly alone: `.hidden` is a name, and there is no
    // stem in front of the dot to keep.
    assert_eq!(
        shotlister_engine::name_with_extension(".hidden", "jpg"),
        ".hidden"
    );
    // Nothing said about the bytes means nothing to correct.
    assert_eq!(
        shotlister_engine::name_with_extension("IMG_4523.HEIC", ""),
        "IMG_4523.HEIC"
    );
}

// ---- non-destructive trim ------------------------------------------------

#[test]
fn a_clip_plays_whole_until_somebody_trims_it() {
    let mut d = doc();
    let scene = d.create_scene("34");
    let (shot, _) = d.add_shot_to_scene(scene);
    let clip = d.add_media(still(b"a take"), MediaKind::Video, 1920, 1080, 4_000_000, "take.mov");
    let use_of_it = d.attach_media(shot, clip, "");

    assert_eq!(d.media_trim(use_of_it), None);

    d.set_media_trim(use_of_it, 2.0, 9.5);
    assert_eq!(d.media_trim(use_of_it), Some((2.0, 9.5)));

    d.clear_media_trim(use_of_it);
    assert_eq!(d.media_trim(use_of_it), None);
}

#[test]
fn trimming_never_touches_the_file_itself() {
    // The whole point: two attachments of the same clip can be trimmed
    // differently, exactly like two captions of the same photograph — the
    // range lives on the use, not on the file.
    let mut d = doc();
    let scene = d.create_scene("34");
    let (a, _) = d.add_shot_to_scene(scene);
    let (b, _) = d.add_shot_to_scene(scene);
    let clip = d.add_media(still(b"b-roll"), MediaKind::Video, 1920, 1080, 4_000_000, "broll.mov");
    let use_a = d.attach_media(a, clip, "");
    let use_b = d.attach_media(b, clip, "");

    d.set_media_trim(use_a, 0.0, 3.0);

    assert_eq!(d.media_trim(use_a), Some((0.0, 3.0)));
    assert_eq!(d.media_trim(use_b), None);
    // The underlying file is the same record throughout.
    assert_eq!(d.media_of(use_a), d.media_of(use_b));
}

#[test]
fn a_backwards_or_empty_range_cannot_be_saved() {
    let mut d = doc();
    let scene = d.create_scene("34");
    let (shot, _) = d.add_shot_to_scene(scene);
    let clip = d.add_media(still(b"take two"), MediaKind::Video, 1920, 1080, 2_000_000, "t2.mov");
    let use_of_it = d.attach_media(shot, clip, "");

    // A drag that lands the out handle on or before the in handle is held to
    // a tenth of a second past it, rather than saving a range that plays
    // nothing at all.
    d.set_media_trim(use_of_it, 5.0, 5.0);
    assert_eq!(d.media_trim(use_of_it), Some((5.0, 5.1)));

    d.set_media_trim(use_of_it, 5.0, 1.0);
    assert_eq!(d.media_trim(use_of_it), Some((5.0, 5.1)));
}

// ---- storyboard arrows -------------------------------------------------

/// A picture, and a use of it to draw arrows on.
fn a_use_of_a_picture(d: &mut Doc) -> shotlister_engine::id::Id {
    let scene = d.create_scene("34");
    let file = d.add_media(
        still(b"a frame to mark up"),
        MediaKind::Image,
        1920,
        1080,
        400_000,
        "frame.jpg",
    );
    d.attach_media(scene, file, "")
}

#[test]
fn a_picture_carries_no_arrows_until_somebody_draws_one() {
    let mut d = doc();
    let use_of_it = a_use_of_a_picture(&mut d);
    assert!(d.media_arrows(use_of_it).is_empty());
}

#[test]
fn arrows_survive_the_round_trip_through_the_record() {
    let mut d = doc();
    let use_of_it = a_use_of_a_picture(&mut d);

    let drawn = vec![
        Arrow::bent(0.2, 0.8, 0.4, 0.5, 0.75, 0.35, 1),
        Arrow::straight(0.1, 0.1, 0.9, 0.1),
    ];
    d.set_media_arrows(use_of_it, &drawn);

    let read = d.media_arrows(use_of_it);
    assert_eq!(read.len(), 2);
    assert!((read[0].x1 - 0.2).abs() < 0.001);
    assert!((read[0].bend().1 - 0.5).abs() < 0.001);
    assert!((read[0].y2 - 0.35).abs() < 0.001);
    assert_eq!(read[0].heads, 1);
    // A straight arrow's bend sits on the middle of its own line.
    assert!((read[1].bend().0 - 0.5).abs() < 0.001);
    assert!((read[1].bend().1 - 0.1).abs() < 0.001);
    assert!(read[1].pins.is_empty());
}

#[test]
fn an_arrow_cannot_be_drawn_off_the_edge_of_the_picture() {
    // The engine holds the bounds so three shells do not each have to agree
    // about them by accident — the same bargain the crop strikes.
    let mut d = doc();
    let use_of_it = a_use_of_a_picture(&mut d);

    d.set_media_arrows(
        use_of_it,
        &[Arrow::bent(-3.0, 0.5, 0.5, 9.0, 2.0, 0.5, 7)],
    );

    let read = d.media_arrows(use_of_it);
    assert_eq!(read[0].x1, 0.0);
    assert_eq!(read[0].pins[0].1, 1.0);
    assert_eq!(read[0].x2, 1.0);
    assert_eq!(read[0].heads, 2);
}

#[test]
fn clearing_the_arrows_leaves_the_picture_bare() {
    let mut d = doc();
    let use_of_it = a_use_of_a_picture(&mut d);
    d.set_media_arrows(use_of_it, &[Arrow::straight(0.1, 0.1, 0.9, 0.9)]);
    assert_eq!(d.media_arrows(use_of_it).len(), 1);

    d.clear_media_arrows(use_of_it);
    assert!(d.media_arrows(use_of_it).is_empty());

    // And so does saving an empty set — absent and "no arrows" are one fact.
    d.set_media_arrows(use_of_it, &[Arrow::straight(0.1, 0.1, 0.9, 0.9)]);
    d.set_media_arrows(use_of_it, &[]);
    assert!(d.media_arrows(use_of_it).is_empty());
}

#[test]
fn one_unreadable_arrow_costs_one_arrow_and_not_the_picture() {
    // A field half-written by a version of the app this one has never met.
    let read = Arrow::parse("0.1,0.1,0.5,0.5,0.9,0.9,1;nonsense;0.2,0.2,0.3,0.3,0.4,0.4");
    assert_eq!(read.len(), 2);
    // Six numbers and no count is the ordinary one-headed arrow.
    assert_eq!(read[1].heads, 1);
}

#[test]
fn the_same_photograph_carries_different_arrows_on_two_shots() {
    // The arrows belong to the *use*, exactly like the crop and the trim.
    let mut d = doc();
    let scene = d.create_scene("34");
    let (a, _) = d.add_shot_to_scene(scene);
    let (b, _) = d.add_shot_to_scene(scene);
    let file = d.add_media(
        still(b"one photograph"),
        MediaKind::Image,
        1920,
        1080,
        400_000,
        "frame.jpg",
    );
    let on_a = d.attach_media(a, file, "");
    let on_b = d.attach_media(b, file, "");

    d.set_media_arrows(on_a, &[Arrow::straight(0.1, 0.5, 0.9, 0.5)]);
    assert_eq!(d.media_arrows(on_a).len(), 1);
    assert!(d.media_arrows(on_b).is_empty());
}

#[test]
fn drawing_arrows_can_be_undone() {
    let mut d = doc();
    let use_of_it = a_use_of_a_picture(&mut d);
    d.set_media_arrows(use_of_it, &[Arrow::straight(0.1, 0.5, 0.9, 0.5)]);
    assert_eq!(d.media_arrows(use_of_it).len(), 1);
    d.undo();
    assert!(d.media_arrows(use_of_it).is_empty());
}

// ---- a clip made smaller after the fact --------------------------------

#[test]
fn replacing_a_clips_bytes_keeps_every_use_and_answers_the_old_name() {
    let mut d = doc();
    let scene = d.create_scene("1");
    let (shot, _) = d.add_shot_to_scene(scene);
    let old = still(b"a fat clip");
    let media = d.add_media(old, MediaKind::Video, 1280, 720, 30_000_000, "take.mov");
    d.remember_media_source(media, still(b"the original off the phone"));
    let mref = d.attach_media(shot, media, "");
    d.set_media_trim(mref, 1.0, 3.0);

    let new = still(b"the same clip, quieter");
    let before = d.replace_media_bytes(media, new, 1280, 720, 8_000_000);
    assert_eq!(before.as_deref(), Some(old.to_hex().as_str()));

    // The record is the same record: the shot still holds it, at its trim.
    assert_eq!(d.media_refs(shot), vec![mref]);
    assert_eq!(d.media_trim(mref), Some((1.0, 3.0)));
    assert_eq!(d.key_frame(shot), Some(media));
    // It is now known by its new bytes, and no longer by its old.
    assert_eq!(d.media_with_hash(new), Some(media));
    assert_eq!(d.media_with_hash(old), None);
    // And the original it was made from still finds it.
    assert_eq!(
        d.media_already_here(still(b"the original off the phone")),
        Some(media)
    );
    assert_eq!(d.get(media).and_then(|r| r.get(f::BYTES)).and_then(|v| v.as_int()), Some(8_000_000));
}

#[test]
fn stray_files_are_the_ones_no_record_names() {
    let mut d = doc();
    let scene = d.create_scene("1");
    let (shot, _) = d.add_shot_to_scene(scene);
    let clip = still(b"clip");
    let photo = still(b"photo");
    let clip_id = d.add_media(clip, MediaKind::Video, 1280, 720, 1, "take.mov");
    let photo_id = d.add_media(photo, MediaKind::Image, 1600, 900, 1, "wall.jpg");
    d.attach_media(shot, clip_id, "");
    d.attach_media(shot, photo_id, "");

    let short = |h: Hash256| h.to_hex().chars().take(32).collect::<String>();
    let head = |h: Hash256| h.to_hex().chars().take(18).collect::<String>();
    let gone = still(b"a clip replaced last week");

    let names = vec![
        format!("{}.mp4", short(clip)),
        format!("{}.jpg", short(clip)),   // its poster
        format!("{}.png", short(clip)),   // its poster from before, retired
        format!("{}.strip", short(clip)), // its whole-clip strip
        format!("{}00003e800000bb8.strip", head(clip)), // a trimmed strip
        format!("{}.jpg", short(photo)),
        format!("{}.mov", short(gone)),
        format!("{}.png", short(gone)),
        format!("{}.strip", short(gone)),
        "cover.png".to_string(),
        "cover-kitchen.png".to_string(),
        "people.json".to_string(),
    ];
    let mut strays = d.stray_media_names(names.iter().map(String::as_str));
    strays.sort();
    let mut expected = vec![
        format!("{}.png", short(clip)),
        format!("{}.mov", short(gone)),
        format!("{}.png", short(gone)),
        format!("{}.strip", short(gone)),
    ];
    expected.sort();
    assert_eq!(strays, expected);
}
