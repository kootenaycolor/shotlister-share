#!/usr/bin/env python3
"""
Make the trimmed clips the Drive copier is waiting for (2026-10-15, his rule: video goes to
Drive as the clip trimmed the way Studio plays it, beside the shot's Print Frame).

Studio keeps a clip whole and remembers its in and out points as numbers, and the server
cannot cut video, so the cut is made here on the Mac with ffmpeg:

  1. ask the hub which trimmed clips are owed   GET  /console/studio/drivecopies/trims?id=<project>
  2. fetch the whole clip from the sync server  GET  /v1/p/<film>/media/<file>
  3. cut it (H.264, in to out, sound kept)
  4. put it on the hub's shelf                  PUT  /console/studio/drivecopies/trim?film=&name=

The copier then files it as <shot>.mp4 on its next sweep. Only reads from the server and adds
to the shelf: nothing is deleted, no source clip is touched. Safe to run again any time: it
makes only what is still owed.

    python3 hub/trimclips.py            all projects
    python3 hub/trimclips.py <id> ...   only these project ids
    python3 hub/trimclips.py --dry      list what is owed, make nothing
"""
import json, os, subprocess, sys, tempfile

sys.path.insert(0, os.path.expanduser("~/Developer/projects-console"))
import keystore  # noqa: E402

TOKEN = keystore.get("relay")
HUB = "https://mcp.your-domain.example/console/studio/drivecopies"
RELAY = "https://sync.your-domain.example/v1/p"
FFMPEG = next((p for p in ("/opt/homebrew/bin/ffmpeg", "/usr/local/bin/ffmpeg") if os.path.exists(p)), "ffmpeg")
AUTH = ["-H", f"authorization: Bearer {TOKEN}"]


def curl(args, out=None):
    r = subprocess.run(["curl", "-sS", "-m", "300", *AUTH, *args] + (["-o", out] if out else []), capture_output=True)
    if r.returncode:
        raise RuntimeError(r.stderr.decode()[:300])
    return r.stdout


def projects():
    """Every project ID the hub knows (/studio/ids: the film-to-project aliases, and the Notion-page IDs)."""
    got = json.loads(curl(["https://mcp.your-domain.example/console/studio/ids"]) or b"{}")
    return sorted(set(got.get("alias", {}).values()) | set(got.get("notion", {}).keys()))


def main(argv):
    dry = "--dry" in argv
    ids = [a for a in argv if not a.startswith("--")] or projects()
    made = total = 0
    for pid in ids:
        try:
            owed = json.loads(curl([f"{HUB}/trims?id={pid}"]))
        except Exception:  # not a project the hub can read
            continue
        if not owed.get("ok") or not (owed.get("owed") or owed.get("posters")):
            continue
        film = owed["film"]
        print(f"{owed['name']}: {len(owed['owed'])} trimmed clips and {len(owed.get('posters') or [])} posters owed ({owed.get('have', 0)} on the shelf)")
        for o in owed.get("posters") or []:
            if dry:
                print(f"  would grab a poster for {o['label']}: {o['src']}")
                continue
            with tempfile.TemporaryDirectory() as tmp:
                src, dst = os.path.join(tmp, "in" + os.path.splitext(o["src"])[1]), os.path.join(tmp, "poster.jpg")
                curl([f"{HUB}/clipfile?id={pid}&src={o['src']}"], out=src)
                for at in ("0.5", "0"):  # half a second in; the first frame if the clip is shorter
                    subprocess.run([FFMPEG, "-v", "error", "-y", "-ss", at, "-i", src, "-frames:v", "1", "-vf", "scale='min(1280,iw)':-2", "-q:v", "3", dst], capture_output=True)
                    if os.path.exists(dst) and os.path.getsize(dst) > 1000:
                        break
                if not (os.path.exists(dst) and os.path.getsize(dst) > 1000):
                    print(f"  FAILED poster {o['label']} {o['src']}")
                    continue
                res = json.loads(curl(["-X", "PUT", "--data-binary", f"@{dst}", f"{HUB}/trim?film={film}&name={o['name']}"]))
                if res.get("ok"):
                    made += 1
                    total += res["bytes"]
                    print(f"  poster {o['label']}: {o['name']}  {res['bytes'] / 1e3:.0f} KB")
                else:
                    print(f"  FAILED poster {o['label']}: {res}")
        seen = set()
        for o in owed["owed"]:
            if o["name"] in seen:
                continue
            seen.add(o["name"])
            if dry:
                print(f"  would cut {o['label']}: {o['media']}  {o['start']} -> {o['end']}")
                continue
            with tempfile.TemporaryDirectory() as tmp:
                src, dst = os.path.join(tmp, "in" + os.path.splitext(o["media"])[1]), os.path.join(tmp, "out.mp4")
                curl([f"{RELAY}/{film}/media/{o['media']}"], out=src)
                # -ss before -i seeks fast; the length is given as a duration
                cmd = [FFMPEG, "-v", "error", "-y", "-ss", str(o["start"]), "-i", src]
                if o["end"] is not None:
                    cmd += ["-t", str(round(o["end"] - o["start"], 3))]
                cmd += ["-c:v", "libx264", "-preset", "medium", "-crf", "21", "-maxrate", "4M", "-bufsize", "8M", "-pix_fmt", "yuv420p",
                        "-c:a", "aac", "-b:a", "96k", "-movflags", "+faststart", dst]
                r = subprocess.run(cmd, capture_output=True)
                if r.returncode or not os.path.exists(dst) or os.path.getsize(dst) < 1000:
                    print(f"  FAILED {o['label']} {o['name']}: {r.stderr.decode()[-200:]}")
                    continue
                res = json.loads(curl(["-X", "PUT", "--data-binary", f"@{dst}", f"{HUB}/trim?film={film}&name={o['name']}"]))
                if res.get("ok"):
                    made += 1
                    total += res["bytes"]
                    print(f"  {o['label']}: {o['name']}  {res['bytes'] / 1e6:.1f} MB")
                else:
                    print(f"  FAILED {o['label']}: {res}")
    print(f"made {made} clips, {total / 1e6:.1f} MB")


if __name__ == "__main__":
    main(sys.argv[1:])
