"""Installer tests (Windows). Run: python tests/install_test.py"""
import json, os, subprocess, pathlib, sys, tempfile, shutil

ROOT = pathlib.Path(__file__).resolve().parent.parent
INSTALL = ROOT / "install.ps1"
BASE = pathlib.Path(tempfile.mkdtemp(prefix="karkas-install-"))
results = {}


def inst(target, *args, stdin=b""):
    r = subprocess.run(["powershell.exe", "-NoProfile", "-ExecutionPolicy", "Bypass", "-File", str(INSTALL), "-Target", str(target), *args],
                       input=stdin, capture_output=True)
    return r.returncode, r.stdout.decode("utf-8", "replace") + r.stderr.decode("utf-8", "replace")


def git(repo, *args):
    return subprocess.run(["git", "-C", str(repo), *args], capture_output=True, text=True, encoding="utf-8")


def tree(p):
    return sorted(str(x.relative_to(p)) for x in p.rglob("*") if x.is_file() and ".git" not in x.parts)


# 1. analyze on a new folder: nothing created
new = BASE / "Новый проект"
code, out = inst(new, "-Analyze")
results["analyze: new folder not created"] = code == 0 and not new.exists() and "ПЛАН" in out

# 2. non-interactive without -Yes: cancelled, nothing created
code, out = inst(new)
results["no -Yes, no answer: cancelled, nothing created"] = code == 1 and not new.exists()

# 3. new folder install
code, out = inst(new, "-Yes")
agents = list((new / ".claude/agents").glob("*.md"))
results["new: 22 agents installed"] = code == 0 and len(agents) == 22
results["new: manifest + report + gitignore"] = all((new / p).exists() for p in [".claude/team/kit-manifest.json", ".claude/team/install-report.md", ".gitignore", "CLAUDE.md", ".claude/settings.json"])

# 4. existing git project, dirty -> stop, nothing changed
ex = BASE / "Старый проект"
(ex / ".claude/agents").mkdir(parents=True)
(ex / "src").mkdir()
(ex / "src/app.py").write_text("print('hi')\n", encoding="utf-8")
(ex / ".claude/CLAUDE.md").write_text("# Project rules\nUse pnpm.\n", encoding="utf-8")
(ex / ".claude/agents/code-reviewer.md").write_text("---\nname: code-reviewer\ndescription: my own reviewer\n---\nmine\n", encoding="utf-8")
(ex / ".claude/agents/my-helper.md").write_text("---\nname: my-helper\ndescription: x\n---\nx\n", encoding="utf-8")
(ex / ".claude/settings.json").write_text(json.dumps({"permissions": {"allow": ["Bash(pnpm test)"]}, "hooks": {"Stop": [{"hooks": [{"type": "command", "command": "echo mine"}]}]}}), encoding="utf-8")
(ex / ".gitignore").write_text("node_modules/\n", encoding="utf-8")
(ex / "AGENTS.md").write_text("Use English.\n", encoding="utf-8")
git(ex, "init", "-q"); git(ex, "add", "-A"); git(ex, "-c", "user.name=t", "-c", "user.email=t@t", "commit", "-qm", "init")
(ex / "src/app.py").write_text("print('changed')\n", encoding="utf-8")
before = tree(ex)
code, out = inst(ex, "-Yes")
results["dirty git: stop with exit 2, nothing changed"] = code == 2 and tree(ex) == before
git(ex, "checkout", "--", "src/app.py")

# 5. clean existing project install
code, out = inst(ex, "-Yes")
own = (ex / ".claude/agents/code-reviewer.md").read_text(encoding="utf-8")
results["existing: own agent with same name kept"] = code == 0 and "mine" in own
results["existing: kit version of conflicting agent in incoming"] = (ex / ".claude/team/incoming/agents/code-reviewer.md").exists()
results["existing: own extra agent kept"] = (ex / ".claude/agents/my-helper.md").exists()
cm = (ex / ".claude/CLAUDE.md").read_text(encoding="utf-8")
results["existing: .claude/CLAUDE.md appended with @team import, root not created"] = "@team/ORCHESTRATOR.md" in cm and "Use pnpm." in cm and not (ex / "CLAUDE.md").exists()
st = json.loads((ex / ".claude/settings.json").read_text(encoding="utf-8"))
results["existing: settings merged, own permission and hook kept"] = st["permissions"]["allow"] == ["Bash(pnpm test)"] and len(st["hooks"]["Stop"]) == 2 and "PostCompact" in st["hooks"]
gi = (ex / ".gitignore").read_text(encoding="utf-8")
results["existing: .gitignore appended, original kept"] = "node_modules/" in gi and ".claude/team/backup/" in gi
rep = (ex / ".claude/team/install-report.md").read_text(encoding="utf-8")
results["existing: report lists conflict, own agent, hooks, AGENTS.md"] = all(s in rep for s in ["code-reviewer.md", "my-helper.md", "AGENTS.md", "Stop"])
results["existing: product code untouched"] = (ex / "src/app.py").read_text(encoding="utf-8") == "print('hi')\n"

# 6. re-run: nothing changes
git(ex, "add", "-A"); git(ex, "-c", "user.name=t", "-c", "user.email=t@t", "commit", "-qm", "karkas")
code, out = inst(ex, "-Yes")
results["re-run: no changes in git"] = code == 0 and git(ex, "status", "--porcelain").stdout.strip() in ("", " M .claude/team/install-report.md", "M  .claude/team/install-report.md") or all(l.endswith("install-report.md") or l.endswith("kit-manifest.json") for l in git(ex, "status", "--porcelain").stdout.splitlines())
git(ex, "add", "-A"); git(ex, "-c", "user.name=t", "-c", "user.email=t@t", "commit", "-qm", "rerun")

# 7. -Update: user-modified kit file is NOT overwritten; outdated untouched kit file IS updated
orch = ex / ".claude/team/ORCHESTRATOR.md"
orch.write_text(orch.read_text(encoding="utf-8") + "\nMY LOCAL RULE\n", encoding="utf-8")   # user edit
qa = ex / ".claude/agents/qa-engineer.md"
qa.write_text("old kit version\n", encoding="utf-8")                                            # simulate old kit version
man = json.loads((ex / ".claude/team/kit-manifest.json").read_text(encoding="utf-8"))
import hashlib
man["files"][".claude/agents/qa-engineer.md"] = hashlib.sha256(qa.read_bytes()).hexdigest().upper()
(ex / ".claude/team/kit-manifest.json").write_text(json.dumps(man), encoding="utf-8")
git(ex, "add", "-A"); git(ex, "-c", "user.name=t", "-c", "user.email=t@t", "commit", "-qm", "edits")
code, out = inst(ex, "-Update", "-Yes")
results["update: user-modified kit file kept"] = "MY LOCAL RULE" in orch.read_text(encoding="utf-8")
results["update: user-modified kit file -> incoming"] = (ex / ".claude/team/incoming/team/ORCHESTRATOR.md").exists()
results["update: untouched old kit file updated"] = "old kit version" not in qa.read_text(encoding="utf-8")
results["update: backup of updated file"] = any(p.name == "qa-engineer.md" for p in (ex / ".claude/team/backup").rglob("*.md"))

for k, v in results.items():
    print(("PASS " if v else "FAIL ") + k)
failed = [k for k, v in results.items() if not v]
print(f"\n{len(results) - len(failed)}/{len(results)} passed")
shutil.rmtree(BASE, ignore_errors=True)
sys.exit(1 if failed else 0)
