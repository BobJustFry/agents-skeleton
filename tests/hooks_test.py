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

for name, ok in results.items():
    print(("PASS " if ok else "FAIL ") + name)
failed = [n for n, ok in results.items() if not ok]
print(f"\n{len(results) - len(failed)}/{len(results)} passed")
sys.exit(1 if failed else 0)
