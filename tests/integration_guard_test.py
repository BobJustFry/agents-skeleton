"""Tests for the integration-guard PreToolUse hook (Windows, PowerShell 5.1). Run: python tests/integration_guard_test.py"""
import json, os, subprocess, pathlib, sys, tempfile, shutil, time
from concurrent.futures import ThreadPoolExecutor

ROOT = pathlib.Path(__file__).resolve().parent.parent
HOOK = ROOT / "template" / ".claude" / "team" / "hooks" / "integration-guard.ps1"
CFG = ROOT / "template" / ".claude" / "team" / "integration-commands.json"
BASE = pathlib.Path(tempfile.mkdtemp(prefix="karkas-intg-"))
P = BASE / "Проект Vupen"                       # Cyrillic project path
(P / ".claude/team/state").mkdir(parents=True)
(P / ".claude/team/ORCHESTRATOR.md").write_text("# o", encoding="utf-8")
shutil.copy(CFG, P / ".claude/team/integration-commands.json")
STATE = P / ".claude/team/state"
GATE = STATE / "integration-gate"
ENV = dict(os.environ, CLAUDE_PROJECT_DIR=r"C:\nonexistent")
results = {}


def run_raw(data: bytes):
    r = subprocess.run(["powershell.exe", "-NoProfile", "-ExecutionPolicy", "Bypass", "-File", str(HOOK)],
                       input=data, capture_output=True, env=ENV)
    return r.stdout.decode("utf-8", "replace").strip(), r.returncode


def run(command=None, tool="Bash", cwd=None, agent=None, tool_input=None):
    ti = tool_input if tool_input is not None else {"command": command}
    payload = {"hook_event_name": "PreToolUse", "tool_name": tool, "tool_input": ti, "cwd": str(cwd or P)}
    if agent:
        payload["agent_id"] = "a1b2c3"; payload["agent_type"] = agent
    return run_raw(json.dumps(payload, ensure_ascii=False).encode("utf-8"))


def denied(out):
    try: return json.loads(out)["hookSpecificOutput"]["permissionDecision"] == "deny"
    except Exception: return False


def reason(out):
    try: return json.loads(out)["hookSpecificOutput"]["permissionDecisionReason"]
    except Exception: return ""


def many(commands, **kw):
    with ThreadPoolExecutor(max_workers=6) as ex:
        return list(ex.map(lambda c: run(c, **kw)[0], commands))


APPROVAL = 'owner-approved: 2026-10-17 "да, запускай build, test и deploy"\nopen-tasks-reported: none\n'   # the quote names classes on purpose: it must not open them
log = STATE / "integration-guard.log"


def log_text():
    return log.read_text(encoding="utf-8") if log.exists() else ""


def gate(text, hours_old=0, approved=True):
    GATE.write_text(text.rstrip() + "\n" + (APPROVAL if approved else ""), encoding="utf-8")
    if hours_old:
        t = time.time() - hours_old * 3600
        os.utime(GATE, (t, t))


def close():
    if GATE.exists(): GATE.unlink()


# ---- gate closed (default) ----
out, code = run("npm run build")
results["gate closed: npm run build denied, exit 0"] = denied(out) and code == 0
results["deny reason: deferred / gate closed / coordinator / class"] = all(s in reason(out) for s in ["deferred", "gate is closed", "integration deferred to coordinator", "(build)"])

must_deny = {
    "pnpm build": "build", "yarn build:prod": "build", "npm run build --if-present": "build", "pnpm --filter app build": "build", "pnpm -r run build": "build",
    "npx vite build": "build", "cd app && npm run build 2>&1 | tail -5": "build", "next build": "build", "ng build --configuration production": "build",
    "dotnet build": "build", "dotnet build App.sln -c Release": "build", "dotnet publish -c Release": "build",
    '"C:\\Program Files\\dotnet\\dotnet.exe" build': "build", "& 'C:\\x\\MSBuild.exe' App.sln /p:Configuration=Release": "build", "msbuild App.sln": "build",
    "./gradlew assembleDebug": "build", "gradlew.bat bundleRelease": "build", "gradlew :app:assembleRelease": "build",
    "flutter build apk --release": "build", "xcodebuild archive -scheme App": "build", "cargo build --release": "build", "go build ./...": "build",
    "docker build -t app .": "build", "docker compose build": "build", "docker-compose up --build": "build",
    "pyinstaller app.spec": "build", "python -m build": "build", "uv run python -m build": "build", "electron-builder --win": "build", "tauri build": "build",
    'bash -c "npm run build"': "build", "powershell -NoProfile -Command \"dotnet publish\"": "build", "cmd /c npm run build": "build",
    "FOO=1 npm run build": "build", "time npm run build": "build", "echo start; npm run build": "build",
    "mvn clean package": "build", "mvn -q install -DskipTests": "build",
    "npm test": "test", "pnpm test": "test", "npm run test:unit": "test", "pytest": "test", "pytest -q": "test", "python -m pytest -x -q": "test",
    "dotnet test": "test", "dotnet test App.sln": "test", "go test ./...": "test", "cargo test": "test", "cargo test --workspace": "test", "npx vitest run": "test",
    "flutter test": "test", "gradlew test": "test", "mvn test": "test",
    "npm publish": "deploy", "npm run deploy": "deploy", "twine upload dist/*": "deploy", "docker push registry/app:1": "deploy", "gh release create v1": "deploy", "firebase deploy": "deploy",
    "npm update": "install", "cargo update": "install",
}
outs = many(list(must_deny))
for (cmd, cls), o in zip(must_deny.items(), outs):
    results[f"closed gate denies [{cls}]: {cmd}"] = denied(o) and f"({cls})" in reason(o)

must_pass = [
    "npm test -- src/a.test.ts", "npx tsc --noEmit", "tsc --noEmit -p tsconfig.json", "pytest tests/test_a.py", "pytest -k foo", "python -m pytest tests/x.py -q",
    "npm run dev", "npm run lint", "eslint src/a.ts", "prettier --check src/a.ts", "git status", "git push origin main", "git commit -m \"fix: npm run build\"",
    "git commit -m \"a; npm run build\"", "echo \"npm run build\"", "grep -rn 'dotnet build' docs", "dotnet build App/App.csproj", "dotnet test --filter Foo", "dotnet test Tests/A.Tests.csproj",
    "cargo build", "cargo check", "cargo test my_test", "go build", "go test ./pkg/foo", "go vet ./...", "npm install", "npm ci", "pnpm install", "pip install -r requirements.txt",
    "vite", "vite dev", "vitest run src/a.test.ts", "npx jest src/a.test.ts", "npm publish --dry-run", "docker run --rm img echo build", "docker ps", "ls -la", "cat package.json",
    "npm run typecheck", "gradlew test --tests Foo", "mvn -q dependency:tree",
    "node scripts/build-docs.js", "python tools/make_build_report.py", "yarn workspace app test src/a.test.ts", "flutter test test/a_test.dart", "npm --version", "dotnet build --help",
]
outs = many(must_pass)
for cmd, o in zip(must_pass, outs):
    results[f"narrow/other command allowed: {cmd}"] = (o == "")

# ---- gate open ----
gate("B-1 build")
results["gate 'build': build allowed"] = run("npm run build")[0] == ""
results["gate 'build': test denied (wrong class)"] = denied(run("npm test")[0])
results["gate 'build': mixed build+test chain denied"] = denied(run("npm run build && npm test")[0])
gate("B-1\nclasses: build, test\n")
results["gate 'build,test': build and test allowed"] = run("npm run build")[0] == "" and run("pytest")[0] == ""
results["gate 'build,test': deploy still denied"] = denied(run("npm publish")[0]) and "open only for" in reason(run("npm publish")[0])
results["gate 'build,test': mixed chain allowed"] = run("npm run build && npm test")[0] == ""
gate("B-2 *")
results["gate '*': everything allowed"] = run("npm publish")[0] == "" and run("npm update")[0] == ""
gate("B-3 all")
results["gate 'all': everything allowed"] = run("docker push x")[0] == ""
gate("B-1 build")
results["owner quote naming other classes does not open them"] = run("npm run build")[0] == "" and denied(run("npm test")[0]) and denied(run("npm publish")[0])
gate("B-1 build", hours_old=13)
out, _ = run("npm run build")
results["stale gate (older than TTL) is treated as closed"] = denied(out) and "stale" in reason(out)

# ---- owner approval is mandatory ----
gate("B-1 build,test", approved=False)
out, _ = run("npm run build")
results["gate WITHOUT owner-approved line: treated as closed"] = denied(out) and "gate without owner approval" in reason(out)
results["deny message asks the coordinator to get the owner's approval"] = "get the owner's approval" in reason(out)
results["gate without approval: reason logged"] = "gate without owner approval" in log_text()
for label, line in [("no quote", "owner-approved: 2026-10-17"), ("bad date", 'owner-approved: yesterday "да"'), ("empty quote", 'owner-approved: 2026-10-17 ""'), ("commented out", '# owner-approved: 2026-10-17 "да"')]:
    GATE.write_text("B-1 build,test\n" + line + "\n", encoding="utf-8")
    results[f"gate with invalid owner-approved ({label}): closed"] = denied(run("npm run build")[0])
GATE.write_text('B-1 build\nowner-approved: 2026-10-17 "chat"\n', encoding="utf-8")
results['gate with owner-approved "chat" (no open-tasks line): build allowed'] = run("npm run build")[0] == ""
GATE.write_text('owner-approved: 2026-10-17 "да"\nB-1 build\nopen-tasks-reported: yes\n', encoding="utf-8")
results["owner-approved line may come first; classes still read from the batch line"] = run("npm run build")[0] == "" and denied(run("npm test")[0])
close()
results["gate closed again after delete: denied"] = denied(run("npm run build")[0])

# ---- log ----
txt = log_text()
results["log has DENY and allow lines with class, agent, command"] = "DENY" in txt and "\tallow\t" in txt and "build" in txt and "main" in txt
out, _ = run("npm run build", agent="devops-engineer")
results["log records agent type"] = "devops-engineer" in log.read_text(encoding="utf-8")

# ---- subagent identity does not matter for the decision; PowerShell tool is covered ----
results["subagent: build denied when gate closed"] = denied(run("npm run build", agent="backend-developer")[0])
results["PowerShell tool: build denied"] = denied(run("dotnet publish -c Release", tool="PowerShell")[0])
results["PowerShell tool: narrow command allowed"] = run("dotnet build App/App.csproj", tool="PowerShell")[0] == ""

# ---- config: local file, local allow, broken config ----
(P / ".claude/team/integration-commands.local.json").write_text(json.dumps({"patterns": [{"class": "lint", "pattern": r"^eslint\s+\.\s*$"}], "allow": [r"my-safe-build"]}), encoding="utf-8")
out, _ = run("eslint .")
results["local config: project pattern (class lint) denied"] = denied(out) and "(lint)" in reason(out)
results["local config: narrow lint still allowed"] = run("eslint src/a.ts")[0] == ""
results["local config: base patterns still active"] = denied(run("npm run build")[0])
results["local config: allow exempts a segment"] = run("npm run build my-safe-build")[0] == ""
gate("B-9 lint")
results["local config: gate with class lint opens it"] = run("eslint .")[0] == ""
close()
(P / ".claude/team/integration-commands.local.json").unlink()

shutil.copy(CFG, P / ".claude/team/integration-commands.json")
(P / ".claude/team/integration-commands.json").write_text("{ broken", encoding="utf-8")
out, code = run("npm run build")
results["broken config: fail open with a warning, no deny"] = (not denied(out)) and "systemMessage" in out and code == 0
(P / ".claude/team/integration-commands.json").unlink()
out, code = run("npm run build")
results["missing config: nothing to guard, allowed"] = out == "" and code == 0
shutil.copy(CFG, P / ".claude/team/integration-commands.json")

# ---- off switch ----
(STATE / "integration-guard-off").write_text("", encoding="utf-8")
results["off-switch file: build allowed"] = run("npm run build")[0] == ""
(STATE / "integration-guard-off").unlink()
results["off-switch removed: build denied again"] = denied(run("npm run build")[0])

# ---- fail open on bad input; other tools ignored ----
for name, data in [("malformed JSON", b"{ not json"), ("empty stdin", b""), ("JSON null", b"null"), ("UTF-8 BOM + bad", b"\xef\xbb\xbf<<<")]:
    out, code = run_raw(data)
    results[f"fail open: {name}"] = out == "" and code == 0
out, code = run_raw(b"\xef\xbb\xbf" + json.dumps({"tool_name": "Bash", "tool_input": {"command": "npm run build"}, "cwd": str(P)}, ensure_ascii=False).encode("utf-8"))
results["UTF-8 BOM on stdin is accepted"] = denied(out)
results["fail open: Bash without command"] = run(tool_input={})[0] == ""
results["fail open: command is not a string (null)"] = run(tool_input={"command": None})[0] == ""
results["non-Bash tool ignored (Read)"] = run(tool="Read", tool_input={"file_path": "npm run build"})[0] == ""
results["MCP tool ignored"] = run(tool="mcp__x__build", tool_input={"command": "npm run build"})[0] == ""

# ---- project root lookup: nested cwd, worktree layout, Cyrillic path ----
deep = P / "src" / "Модуль" / "ui"
deep.mkdir(parents=True)
results["Cyrillic cwd nested in project: root found, build denied"] = denied(run("npm run build", cwd=deep)[0])
wt = P / ".claude/worktrees/wt1"
(wt / ".claude/team").mkdir(parents=True)
(wt / ".claude/team/ORCHESTRATOR.md").write_text("# o", encoding="utf-8")
shutil.copy(CFG, wt / ".claude/team/integration-commands.json")
results["worktree with its own team folder: build denied"] = denied(run("npm run build", cwd=wt)[0])
gate("B-1 build")
results["worktree uses ITS OWN state (project gate does not open it)"] = denied(run("npm run build", cwd=wt)[0])
results["worktree: project gate still opens the project"] = run("npm run build")[0] == ""
close()

# ---- subagents cannot open the gate or switch the guard off ----
tamper = [
    "echo B-1 build > .claude/team/state/integration-gate",
    "Set-Content .claude/team/state/integration-gate 'B-1 build,test'",
    "New-Item .claude/team/state/integration-guard-off",
    "printf 'x' | tee .claude/team/state/integration-gate",
    "cp /tmp/g .claude/team/state/integration-gate",
]
outs = many(tamper, agent="devops-engineer")
for cmd, o in zip(tamper, outs):
    results[f"subagent cannot tamper: {cmd[:50]}"] = denied(o) and "coordinator" in reason(o)
results["subagent Write tool on the gate denied"] = denied(run(tool="Write", tool_input={"file_path": str(GATE), "content": "B-1 build"}, agent="devops-engineer")[0])
results["subagent Edit tool on the guard-off file denied"] = denied(run(tool="Edit", tool_input={"file_path": str(STATE / "integration-guard-off")}, agent="qa-engineer")[0])
results["subagent may READ the gate (cat / Test-Path)"] = run("cat .claude/team/state/integration-gate", agent="qa-engineer")[0] == "" and run("Test-Path .claude/team/state/integration-gate", tool="PowerShell", agent="qa-engineer")[0] == ""
results["subagent Write tool on a normal file allowed"] = run(tool="Write", tool_input={"file_path": str(P / "src/a.ts")}, agent="backend-developer")[0] == ""
results["coordinator (no agent_id) may write the gate by shell"] = run("echo B-1 build > .claude/team/state/integration-gate")[0] == ""
results["coordinator Write tool ignored by the guard"] = run(tool="Write", tool_input={"file_path": str(GATE)})[0] == ""

# ---- cost ----
t0 = time.time()
for _ in range(3): run("ls")
per = (time.time() - t0) / 3
results["cost: a non-integration command is handled in < 5 s"] = per < 5
print(f"(average hook run: {per:.2f} s including PowerShell start-up)")

for k, v in results.items():
    print(("PASS " if v else "FAIL ") + k)
failed = [k for k, v in results.items() if not v]
print(f"\n{len(results) - len(failed)}/{len(results)} passed")
shutil.rmtree(BASE, ignore_errors=True)
sys.exit(1 if failed else 0)
