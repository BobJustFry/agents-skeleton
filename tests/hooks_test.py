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


stop = {"stop_hook_active": False, "cwd": str(T), "background_tasks": [],
        "session_crons": [{"prompt": "KARKAS HEARTBEAT"}]}
results = {}
results["stop: sees unblocked task (Cyrillic path)"] = "T-1" in run("stop-guard.ps1", stop)
results["stop: UTF-8 BOM on stdin"] = "T-1" in run("stop-guard.ps1", stop, bom=True)
results["stop: no loop when stop_hook_active"] = run("stop-guard.ps1", dict(stop, stop_hook_active=True)) == ""
results["stop: missing heartbeat is reported"] = "HEARTBEAT" in run("stop-guard.ps1", dict(stop, session_crons=[]))
results["stop: shell bg task does not suspend"] = "T-1" in run("stop-guard.ps1", dict(stop, background_tasks=[{"type": "local_bash", "description": "npm run dev"}]))
results["stop: agent bg task suspends"] = run("stop-guard.ps1", dict(stop, background_tasks=[{"type": "local_agent", "description": "qa"}])) == ""
results["session-start: restores STATE after compact"] = "КИРИЛЛИЦА-STATE" in run("session-start.ps1", {"source": "compact", "cwd": str(T)})
results["session-start: startup has heartbeat reminder"] = "KARKAS HEARTBEAT" in run("session-start.ps1", {"source": "startup", "cwd": str(T)})
run("post-compact.ps1", {"trigger": "auto", "cwd": str(T), "compact_summary": "пересказ на русском"})
run("post-compact.ps1", {"trigger": "auto", "cwd": str(T), "agent_type": "plugin:agent", "compact_summary": "x"})
arch = list((T / ".claude/team/state/compactions").glob("*.md"))
results["post-compact: archive in session folder, Cyrillic intact"] = any("пересказ на русском" in f.read_text(encoding="utf-8") for f in arch)
results["post-compact: plugin:agent name sanitized"] = any("plugin_agent" in f.name for f in arch)
out = run("subagent-start.ps1", {"agent_type": "qa-engineer", "cwd": str(T)})
results["subagent-start: valid JSON"] = json.loads(out)["hookSpecificOutput"]["hookEventName"] == "SubagentStart"

(T / ".claude/team/state/heartbeat-off").write_text("", encoding="utf-8")
results["heartbeat-off: stop does not demand heartbeat"] = "HEARTBEAT" not in run("stop-guard.ps1", dict(stop, session_crons=[], cwd=str(T)))
results["heartbeat-off: session-start says switched off"] = "switched off" in run("session-start.ps1", {"source": "startup", "cwd": str(T)})
(T / ".claude/team/state/heartbeat-off").unlink()

# quiet heartbeat: without active tasks no heartbeat is demanded and none is suggested
(T / "docs/project/TASKS.md").write_text("| T-1 | тест | x | - | - | Принята | ok |" + chr(10), encoding="utf-8")
results["quiet: no active tasks -> stop does not demand heartbeat"] = run("stop-guard.ps1", dict(stop, session_crons=[])) == ""
results["quiet: no active tasks -> session-start says not needed"] = "no heartbeat is needed" in run("session-start.ps1", {"source": "startup", "cwd": str(T)})
(T / "docs/project/TASKS.md").write_text("| T-1 | тест | x | - | - | Готова к выполнению | ok |" + chr(10), encoding="utf-8")
results["quiet: active tasks -> session-start asks for heartbeat"] = "needs to be created" in run("session-start.ps1", {"source": "startup", "cwd": str(T)})

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
