"""The Mac's side of the shared activity log, run against a LOCAL worker
(step6history-live.mjs starts it): Projects Console's own s6_history and its
own router (hubbackend.HubBackend), on a scratch copy of the real log.

    python3 hub/step6history-mac.py <base> <token> <scratch> <what> [json]
      what = ship   : ship the copy, then read the merged list
             list   : the merged list only (no shipping)
             undo   : one activity_undo through the router (json = the entry)
             line   : write one line through engine.record_activity, wait for it to ship
Prints one JSON object.
"""
import json, os, pathlib, shutil, sys, time

base, token, scratch, what = sys.argv[1:5]
arg = json.loads(sys.argv[5]) if len(sys.argv) > 5 else None
CONSOLE = os.environ.get("CONSOLE", str(pathlib.Path.home() / ".worktrees/projects-console-step6-history"))
sys.path.insert(0, CONSOLE)
os.environ["PC_STATE_DIR"] = scratch
os.environ.pop("PC_ROUTER", None)
import engine  # noqa: E402
import hubbackend  # noqa: E402
import s6_history  # noqa: E402

if os.environ.get("MACHINE"):
    engine.machine_label = lambda: os.environ["MACHINE"]
REAL = pathlib.Path.home() / "Developer/.projects-console-state/activity.jsonl"
if not engine.activity_file().exists() and os.environ.get("SEED", "1") == "1":
    shutil.copy(REAL, engine.activity_file())
link = hubbackend.HubLink(base=base, token=token)
s6_history._hub = lambda: link


class Mac:
    """This Mac's own backend for the router: the real undo, a recorder around it."""
    def __init__(self):
        self.asked = []
        self._projects_cache = None

    def activity_undo(self, entry):
        self.asked.append(entry)
        return engine.undo_activity(entry)

    def _forget_page(self, *a, **k):
        pass


out = {}
router = hubbackend.HubBackend(Mac(), hub=link)
router.cloud()                                       # reads the server's list, as the app does
out["switch_seen"] = s6_history.on()
if what == "ship":
    out["shipped"] = s6_history.ship()
    out["mac_list"] = engine.activity_list()
    out["merged"] = s6_history.activity(engine.activity_list())
elif what == "list":
    out["mac_list"] = engine.activity_list()
    out["merged"] = s6_history.activity(engine.activity_list())
elif what == "undo":
    try:
        out["result"] = router.call("activity_undo", [arg], None, router.local.activity_undo)
    except Exception as e:
        out["error"] = str(e)
    out["mac_asked"] = len(router.local.asked)
elif what == "line":
    engine.record_activity(arg["kind"], arg["desc"], arg.get("undo"))     # ships by itself (switch on)
    out["shipped_by_itself"] = False
    for _ in range(100):
        time.sleep(0.1)
        got = link("studio/step6history/log?limit=10")
        if any(e.get("desc") == arg["desc"] for e in got.get("entries") or []):
            out["shipped_by_itself"] = True
            break
    out["merged"] = s6_history.activity(engine.activity_list())
print(json.dumps(out, ensure_ascii=False))
