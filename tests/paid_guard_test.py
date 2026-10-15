"""Tests for the paid-guard PreToolUse hook (Windows, PowerShell 5.1). Run: python tests/paid_guard_test.py"""
import json, os, subprocess, pathlib, sys, tempfile, datetime, shutil

ROOT = pathlib.Path(__file__).resolve().parent.parent
HOOK = ROOT / "template" / ".claude" / "team" / "hooks" / "paid-guard.ps1"
CFG = ROOT / "template" / ".claude" / "team" / "paid-tools.json"
BASE = pathlib.Path(tempfile.mkdtemp(prefix="karkas-paid-"))
P = BASE / "Проект Vupen"                       # Cyrillic project path
(P / ".claude/team").mkdir(parents=True)
(P / ".claude/team/ORCHESTRATOR.md").write_text("# o", encoding="utf-8")
shutil.copy(CFG, P / ".claude/team/paid-tools.json")
K = P / "docs/knowledge"
ENV = dict(os.environ, CLAUDE_PROJECT_DIR=r"C:\nonexistent")
TOOL = "mcp__higgsfield__generate_image"
results = {}


def run(tool=TOOL, tool_input=None, cwd=None, agent=None):
    payload = {"hook_event_name": "PreToolUse", "tool_name": tool, "tool_input": tool_input or {}, "cwd": str(cwd or P)}
    if agent: payload["agent_type"] = agent
    r = subprocess.run(["powershell.exe", "-NoProfile", "-ExecutionPolicy", "Bypass", "-File", str(HOOK)],
                       input=json.dumps(payload, ensure_ascii=False).encode("utf-8"), capture_output=True, env=ENV)
    out = r.stdout.decode("utf-8", "replace").strip()
    return out, r.returncode


def denied(out):
    try: return json.loads(out)["hookSpecificOutput"]["permissionDecision"] == "deny"
    except Exception: return False


def knowledge(name, covers, days_ago=0):
    K.mkdir(parents=True, exist_ok=True)
    d = (datetime.date.today() - datetime.timedelta(days=days_ago)).isoformat()
    (K / name).write_text(f"# t\n\nSources:\n- https://example.com\nVerified: {d}\nVersions: x\nCovers: {covers}\n", encoding="utf-8")


out, code = run(tool_input={"model": "nano_banana_pro"})
results["denies paid call without knowledge file"] = denied(out) and code == 0
results["deny reason tells to study docs"] = "official documentation" in out and "Covers" in out

knowledge("higgsfield.md", "generate_image|nano_banana", days_ago=8)
out, _ = run(tool_input={"model": "nano_banana_pro"})
results["denies when Verified older than 7 days"] = denied(out) and "outdated" in out

knowledge("higgsfield.md", "generate_image|soul", days_ago=1)
out, _ = run(tool_input={"model": "nano_banana_pro"})
results["denies when Covers does not match the model"] = denied(out)

knowledge("higgsfield.md", "generate_image|nano_banana", days_ago=1)
out, code = run(tool_input={"model": "nano_banana_pro"}, agent="ai-media-producer")
results["allows with fresh matching file"] = out == "" and code == 0
log = P / ".claude/team/state/paid-calls.log"
results["allowed paid call logged with tool, model, agent"] = log.exists() and all(s in log.read_text(encoding="utf-8") for s in ["generate_image", "nano_banana_pro", "ai-media-producer", "higgsfield.md"])

for free in ["mcp__higgsfield__balance", "mcp__higgsfield__models_explore", "mcp__higgsfield__show_generations", "mcp__higgsfield__list_projects", "mcp__higgsfield__get_preset_instructions", "mcp__higgsfield__tiktok_publish_status"]:
    shutil.rmtree(K, ignore_errors=True)
    out, _ = run(tool=free)
    results[f"free call allowed: {free.split('__')[-1]}"] = not denied(out)

out, _ = run(tool="Bash", tool_input={"command": "echo hi"})
results["non-MCP tool ignored"] = out == ""
out, _ = run(tool="mcp__higgsfield__upscale_image")
results["paid without model arg still guarded"] = denied(out)

(P / ".claude/team/paid-tools.json").write_text("{ broken", encoding="utf-8")
out, _ = run(tool="mcp__higgsfield__balance")
results["broken config: free call allowed with warning"] = (not denied(out)) and "systemMessage" in out
out, _ = run(tool_input={"model": "nano_banana_pro"})
results["broken config: paid call still blocked (defaults)"] = denied(out)
shutil.copy(CFG, P / ".claude/team/paid-tools.json")

(P / ".claude/team/paid-tools.local.json").write_text(json.dumps({"paid": ["my_render"]}), encoding="utf-8")
out, _ = run(tool="mcp__studio__my_render")
results["project-specific paid pattern from local file"] = denied(out)

wt = P / ".claude/worktrees/wt1"
(wt / ".claude/team").mkdir(parents=True)
(wt / ".claude/team/ORCHESTRATOR.md").write_text("# o", encoding="utf-8")
(wt / "docs/knowledge").mkdir(parents=True)
d = datetime.date.today().isoformat()
(wt / "docs/knowledge/h.md").write_text(f"Verified: {d}\nCovers: generate_image|nano\n", encoding="utf-8")
out, _ = run(tool_input={"model": "nano_banana_pro"}, cwd=wt)
results["worktree with Cyrillic parent path: uses session folder knowledge"] = out == ""

for k, v in results.items():
    print(("PASS " if v else "FAIL ") + k)
failed = [k for k, v in results.items() if not v]
print(f"\n{len(results) - len(failed)}/{len(results)} passed")
shutil.rmtree(BASE, ignore_errors=True)
sys.exit(1 if failed else 0)
