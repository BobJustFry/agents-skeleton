"""Regression tests for the Karkas hooks (Windows, PowerShell 5.1).

Run:  python tests/hooks_test.py
Feeds raw UTF-8 JSON on stdin (exactly as Claude Code does) with a Cyrillic project path
and a worktree-style layout where CLAUDE_PROJECT_DIR points elsewhere.
"""
import json, os, subprocess, pathlib, sys, tempfile

ROOT = pathlib.Path(__file__).resolve().parent.parent
H = ROOT / "template" / ".claude" / "team" / "hooks"
T = pathlib.Path(tempfile.mkdtemp(prefix="karkas-hooks-")) / "Каркас-тест"
(T / ".claude/team/state").mkdir(parents=True)
(T / "docs/project").mkdir(parents=True)
(T / ".claude/team/ORCHESTRATOR.md").write_text("# o", encoding="utf-8")
(T / "docs/project/TASKS.md").write_text("| T-1 | тест | x | - | - | Готова к выполнению | ok |\n", encoding="utf-8")
(T / ".claude/team/state/STATE.md").write_text("- next: КИРИЛЛИЦА-STATE\n", encoding="utf-8")
ENV = dict(os.environ, CLAUDE_PROJECT_DIR=r"C:\nonexistent")  # like a worktree session: env points to another checkout


def run(script, payload, bom=False):
    data = json.dumps(payload, ensure_ascii=False).encode("utf-8")
    if bom:
        data = b"\xef\xbb\xbf" + data
    r = subprocess.run(["powershell.exe", "-NoProfile", "-ExecutionPolicy", "Bypass", "-File", str(H / script)],
                       input=data, capture_output=True, env=ENV)
    return r.stdout.decode("utf-8", "replace").strip()


stop = {"stop_hook_active": False, "cwd": str(T), "background_tasks": []}
results = {}
results["stop: sees unblocked task (Cyrillic path)"] = "T-1" in run("stop-guard.ps1", stop)
results["stop: UTF-8 BOM on stdin"] = "T-1" in run("stop-guard.ps1", stop, bom=True)
results["stop: no loop when stop_hook_active"] = run("stop-guard.ps1", dict(stop, stop_hook_active=True)) == ""
results["stop: does not ask to create a heartbeat (even without crons)"] = "HEARTBEAT" not in run("stop-guard.ps1", dict(stop, session_crons=[])).upper() and "CronCreate" not in run("stop-guard.ps1", dict(stop, session_crons=[]))
results["stop: shell bg task does not suspend"] = "T-1" in run("stop-guard.ps1", dict(stop, background_tasks=[{"type": "local_bash", "description": "npm run dev"}]))
results["stop: agent bg task suspends"] = run("stop-guard.ps1", dict(stop, background_tasks=[{"type": "local_agent", "description": "qa"}])) == ""
results["session-start: restores STATE after compact"] = "КИРИЛЛИЦА-STATE" in run("session-start.ps1", {"source": "compact", "cwd": str(T)})
_ss_start = run("session-start.ps1", {"source": "startup", "cwd": str(T)})
results["session-start: startup does not mention or create a heartbeat"] = "HEARTBEAT" not in _ss_start.upper() and "CronCreate" not in _ss_start and "T-1" in _ss_start
_ss_resume = run("session-start.ps1", {"source": "resume", "cwd": str(T)})
results["session-start: resume tells to delete an obsolete heartbeat, never to create one"] = "delete it (obsolete since 0.1.21)" in _ss_resume and "CronCreate" not in _ss_resume and "needs to be created" not in _ss_resume
run("post-compact.ps1", {"trigger": "auto", "cwd": str(T), "compact_summary": "пересказ на русском"})
run("post-compact.ps1", {"trigger": "auto", "cwd": str(T), "agent_type": "plugin:agent", "compact_summary": "x"})
arch = list((T / ".claude/team/state/compactions").glob("*.md"))
results["post-compact: archive in session folder, Cyrillic intact"] = any("пересказ на русском" in f.read_text(encoding="utf-8") for f in arch)
results["post-compact: plugin:agent name sanitized"] = any("plugin_agent" in f.name for f in arch)
out = run("subagent-start.ps1", {"agent_type": "qa-engineer", "cwd": str(T)})
results["subagent-start: valid JSON"] = json.loads(out)["hookSpecificOutput"]["hookEventName"] == "SubagentStart"

# no active tasks: nothing to continue, stop is silent; no heartbeat text anywhere
(T / "docs/project/TASKS.md").write_text("| T-1 | тест | x | - | - | Принята | ok |" + chr(10), encoding="utf-8")
results["quiet: no active tasks -> stop is silent"] = run("stop-guard.ps1", dict(stop)) == ""
results["quiet: no active tasks -> session-start has no heartbeat text"] = "HEARTBEAT" not in run("session-start.ps1", {"source": "startup", "cwd": str(T)}).upper()
(T / "docs/project/TASKS.md").write_text("| T-1 | тест | x | - | - | Готова к выполнению | ok |" + chr(10), encoding="utf-8")

# shipped template must not tell the coordinator to poll
_tpl = H.parent
_hook_text = "".join((H / f).read_text(encoding="utf-8-sig") for f in ("session-start.ps1", "stop-guard.ps1", "update-check.ps1", "post-compact.ps1", "subagent-start.ps1"))
results["hooks: no CronCreate / recurring heartbeat instruction in hook sources"] = "CronCreate" not in _hook_text and "2-59/5" not in _hook_text and "heartbeat-off" not in _hook_text
_cont = (_tpl / "reference" / "CONTINUOUS.md").read_text(encoding="utf-8")
results["rules: CONTINUOUS.md has no 5-minute heartbeat recipe, keeps one-shot wake-up rule"] = "2-59/5" not in _cont and "recurring: true" not in _cont and "20 минут" in _cont and "150" in _cont

# update-check: newer version on "GitHub" (local file URL), 15-minute cache, notify once
vfile = T.parent / "VERSION"; vfile.write_text("9.9.9" + chr(10), encoding="utf-8")
(T / ".claude/team/kit-manifest.json").write_text(json.dumps({"version": "0.1.0", "repo": "https://github.com/x/y", "files": {}}), encoding="utf-8")
uenv = dict(ENV, KARKAS_VERSION_URL=vfile.as_uri())
def upd(args, payload=None):
    data = json.dumps(payload or {"cwd": str(T)}, ensure_ascii=False).encode("utf-8")
    r = subprocess.run(["powershell.exe", "-NoProfile", "-ExecutionPolicy", "Bypass", "-File", str(H / "update-check.ps1"), *args], input=data, capture_output=True, env=uenv, cwd=str(T))
    return r.stdout.decode("utf-8", "replace").strip()
first = upd(["-Hook", "-Event", "UserPromptSubmit"])
results["update-check: newer version reported"] = "KARKAS UPDATE" in first and "9.9.9" in first
results["update-check: same version not repeated on next prompt"] = upd(["-Hook", "-Event", "UserPromptSubmit"]) == ""
results["update-check: SessionStart repeats the notice"] = "KARKAS UPDATE" in upd(["-Hook", "-Event", "SessionStart"])
vfile.write_text("9.9.10" + chr(10), encoding="utf-8")
results["update-check: cache prevents refetch within 15 min"] = upd([]) == ""
cache = json.loads((T / ".claude/team/state/update-check.json").read_text(encoding="utf-8")); cache["checked"] = "2000-01-01T00:00:00"
(T / ".claude/team/state/update-check.json").write_text(json.dumps(cache), encoding="utf-8")
results["update-check: after 15 min refetch, plain mode prints notice"] = "9.9.10" in upd([])
(T / ".claude/team/kit-manifest.json").write_text(json.dumps({"version": "9.9.10", "repo": "https://github.com/x/y", "files": {}}), encoding="utf-8")
results["update-check: up to date -> silent"] = upd(["-Hook", "-Event", "SessionStart"]) == ""

for name, ok in results.items():
    print(("PASS " if ok else "FAIL ") + name)
failed = [n for n, ok in results.items() if not ok]
print(f"\n{len(results) - len(failed)}/{len(results)} passed")
sys.exit(1 if failed else 0)
