/**
 * **The switches that chose which copy runs are fixed** (stage 5 step 9,
 * 2026-10-18). Each stage 5 group went live behind a switch, so it could be
 * put back on the Mac's own copy during its three-day trial. The trials ran
 * clean and the Mac's copies were removed, so there is nothing left to switch
 * back to: the owner switches always say "hub", and an on/off switch can be
 * turned on but no longer off.
 */

export const FIXED_ON = "This switch is fixed on since 2026-10-18: the Mac's own copy it switched back to was removed.";

/** `{on: true, problem}` when asked to turn a fixed switch off, else null. */
export function refuseOff(said) {
  return said && said.on === true ? null : { on: true, problem: FIXED_ON };
}

/** An owner switch's answer: always the server, with when it moved there. */
export function hubOwner(said) {
  return { owner: "hub", at: (said && said.at) || null, by: (said && said.by) || null };
}
