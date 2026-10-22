import Foundation

/// **Words both apps say, written once.**
///
/// Ref 181, and the same shape of problem as Ref 143: the Mac and the phone
/// each held their own copy of what to say about a scan that has shape but no
/// measurements, so the two would drift the moment either was edited. There is
/// no reason for a sentence to exist twice.
///
/// What belongs here is narrow. **Labels do not:** a label names the thing in
/// front of it and the two apps are not obliged to name it the same way — the
/// Mac has a menu bar and the phone has a thumb. What belongs here is the
/// short list of sentences that survived the copy pass on purpose, because
/// each carries something a label cannot: what a delete will cost, why
/// something cannot work here, a warning.
///
/// **This file is compiled into both apps.** The Mac picks it up through
/// `studio/build.sh`; the phone needs one line in `phone/project.yml` adding
/// `../shared` to its sources, which is written up in `handoff/from-studio.md`.
enum Words {
    // ---- a scan with shape but no measurements ---------------------------
    //
    // RoomPlan sometimes returns a room it could see but could not measure.
    // The `.usdz` is fine to look at and the floor plan cannot be drawn, which
    // looks exactly like the app being broken unless it says so.

    /// The title. A label: it names what is missing and stops.
    static let noMeasurements = "No measurements in this scan"

    /// The one sentence, and the reason it is allowed to be a sentence: it
    /// says why the feature cannot work here, and what to do about it. His
    /// ruling of 2026-08-21 kept exactly this kind and deleted the rest.
    static let noMeasurementsWhy =
        "This scan has its shape but not its dimensions, so a floor plan "
        + "can’t be drawn from it. Scanning the room again fixes it."
}
