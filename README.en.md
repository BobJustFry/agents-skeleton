[Русский](README.md) | **English**

# Karkas — a ready-made AI team for any project

**Version 0.1.20** · build number = commit count (`VERSION` file)

Install Karkas into a project folder, and Claude Code in that folder becomes the **Chief Orchestrator**. It works out the task, plans it, hands the work to 22 specialists, checks the results and reports back to you.

It suits:
- websites;
- AI content, video and music;
- marketing and promotion;
- web, mobile and desktop apps;
- bots and AI products.

It works both in new projects and in existing ones.

## One-phrase install

Open the target project in Claude Code and write:

> Установи каркас: https://github.com/BobJustFry/agents-skeleton

Claude downloads the kit, analyzes the project, shows the plan and installs after your "да". Then open a **new** session in that folder and write "Проведи онбординг Каркаса".

### Instructions for Claude Code (follow step by step; talk to the owner in Russian)

1. **Kit location.** If `P:\Projects\Каркас` or `%USERPROFILE%\.claude\karkas` already holds this repo (`git remote get-url origin`), run `git pull --ff-only`. Otherwise clone it into `%USERPROFILE%\.claude\karkas`. Never clone the kit inside the project.
2. **Project** is the session's folder. If you are in a worktree (`.claude\worktrees\…`), the target is the repository's main folder. Ask the owner if unsure.
3. **Git.** Run `git status --porcelain`. If there are uncommitted changes, show them and ask whether to commit them (propose a message). Do not commit or continue without "да".
4. **Analysis:**
   ```
   powershell -NoProfile -ExecutionPolicy Bypass -File "<kit>\install.ps1" -Target "<project>" -Analyze
   ```
   Summarize the plan briefly in Russian:
   - what will be added;
   - what will be appended (`CLAUDE.md`, settings, `.gitignore`);
   - conflicts;
   - the project's own agents, hooks and rules.

   Then ask "Устанавливаю?".
5. **Install** only after "да":
   ```
   powershell -NoProfile -ExecutionPolicy Bypass -File "<kit>\install.ps1" -Target "<project>" -Yes
   ```
   Then summarize `.claude\team\install-report.md`.
6. **Do not commit the installation yourself.** Offer the owner to commit it.
7. **Tell the owner:** new agents and hooks are not loaded in this session. Open a new session in this folder and write "Проведи онбординг Каркаса".
8. **Update** ("обнови каркас"): steps 1, 3 and 4, then run with `-Update -Yes`.

## How to use

**1. Get the kit** (once):

```powershell
git clone https://github.com/BobJustFry/agents-skeleton.git P:\Projects\Karkas
```

**2. New project.** Double-click `install.cmd`, enter a new folder path (e.g. `P:\Projects\MySite`) and confirm the plan.

**3. Existing project.** Installation has three steps: analysis, install, onboarding.

1. **Commit your current changes.** The installer refuses to run on uncommitted git changes, so any install can be undone with git.
2. **Review the plan** (changes nothing):
   ```powershell
   P:\Projects\Karkas\install.cmd "P:\Projects\MyProject" -Analyze
   ```
3. **Install:** run it without `-Analyze` and answer "да". What the installer does:
   - your files are never deleted or overwritten;
   - if you have your own agent with the same name, it stays, and the kit's version goes to `.claude\team\incoming\`;
   - `CLAUDE.md` (root or `.claude\`), `.claude\settings.json` and `.gitignore` are only appended to, with backups in `.claude\team\backup\`;
   - an install report is written to `.claude\team\install-report.md`.
4. **Onboarding:** open the project in Claude Code and write **"Проведи онбординг Каркаса"**. The orchestrator then:
   - studies the project and records the current test baseline;
   - compares the project's rules with the kit's rules;
   - proposes how to merge conflicts.

   Product code is not changed during onboarding, and you make the disputed decisions.

**Rollback right after installing, before any other changes:** `git checkout -- .` and `git clean -fd .claude docs`. The project was committed before the install, so these remove only the kit's files. Without git, restore the files from `.claude\team\backup\`.

**4. Update the team** after the kit changes:

```powershell
P:\Projects\Karkas\install.cmd "P:\Projects\MyProject" -Update
```

Only files installed by the kit that you have not modified are updated. If you edited a kit file, your version stays and the new one goes to `.claude\team\incoming\`.

## The team

**Product and architecture**

| Agent | Role | Model |
|---|---|---|
| `product-analyst` | requirements, user scenarios, MVP, acceptance criteria | sonnet / high |
| `software-architect` | architecture, stack, contracts, architecture decisions | opus / high |

**Creative and growth**

| Agent | Role | Model |
|---|---|---|
| `creative-director` | ideas for videos, music, apps and campaigns | opus / medium |
| `growth-marketer` | promotion of websites and apps: SEO, ASO, ads, analytics | sonnet / high |

**Design and content**

| Agent | Role | Model |
|---|---|---|
| `ui-ux-designer` | UX, design system, mockups, accessibility | sonnet / high |
| `copywriter` | copy, scripts, SEO texts, localization | sonnet / medium |

**Media production**

| Agent | Role | Model |
|---|---|---|
| `ai-media-producer` | AI generation of images, video, voice and music | sonnet / medium |
| `video-editor` | video assembly and editing | sonnet / high |
| `sound-engineer` | audio: cleanup, mixing, mastering | sonnet / high |

**Development**

| Agent | Role | Model |
|---|---|---|
| `frontend-developer` | websites, landing pages, web interfaces | sonnet / high |
| `backend-developer` | servers, APIs, integrations, bots, payments | sonnet / high |
| `database-engineer` | databases, migrations | opus / high |
| `mobile-developer` | iOS, Android, React Native, Flutter | sonnet / high |
| `desktop-developer` | Windows/macOS/Linux, browser extensions, CLI | sonnet / high |
| `ai-engineer` | AI/LLM features inside the product | sonnet / high |

**Quality**

| Agent | Role | Model |
|---|---|---|
| `qa-engineer` | testing, bug hunting | sonnet / high |
| `code-reviewer` | independent code review (read-only) | opus / high |

**Infrastructure and security**

| Agent | Role | Model |
|---|---|---|
| `devops-engineer` | hosting, deployment, CI/CD, domains, releases | sonnet / high |
| `security-auditor` | independent security audit (read-only) | opus / high |

**Legal and compliance**

| Agent | Role | Model |
|---|---|---|
| `legal-advisor` | legal documents, laws, licenses; not a substitute for a licensed lawyer | opus / high |

**Research and documentation**

| Agent | Role | Model |
|---|---|---|
| `researcher` | technology and market research (read-only) | haiku / medium |
| `tech-writer` | documentation and guides | haiku / medium |

## Team rules

- **Language.** Agents talk to each other and to the orchestrator in English, the native language of Claude models, where they work most precisely. The orchestrator talks to the owner in Russian only, and everything meant for the owner is written in Russian. You can change this in section 1.1 of `ORCHESTRATOR.md`.
- **Fresh data.** Before each task, every specialist checks the official documentation. Findings are kept in the project's `docs/knowledge/` and refreshed when they are more than 7 days old.
- **Brief, no fluff.** Everyone answers to the point.
- **When something is unknown:** official documentation first, then practical experience from the internet, and only then a question to you.
- **Money** is spent only within a budget you have approved, for the whole task or for a stage.
- **They argue with you.** If you are wrong, neither the orchestrator nor the agents will agree. A disputed decision is carried out only after you confirm you accept the risks with your personal code word. The code word lives only in your private settings in `~/.claude/CLAUDE.md`; it is not part of the kit.
- **Updates arrive by themselves.** At session start and on your messages the project silently compares its version with GitHub, at most every 15 minutes. When a new version is out, the orchestrator offers the update once. It updates only after your "да", and your edits are preserved.
- **Work does not stall.** While there are unfinished tasks, the orchestrator checks every 5 minutes whether they can move forward. When no work is left, the heartbeat removes itself, so the chat stays clean. If the orchestrator tries to stop with unfinished tasks, a hook sends it back to work.
- **Protection against context loss.** When the context overflows it is compacted and details are lost. So the orchestrator keeps a state file on disk (tasks, decisions, budgets, next step), and each agent keeps its brief and progress files. After compaction a hook restores the rules and the state, every summary is archived, and agents have persistent per-project memory.
- **Nobody works blind.** A result is accepted only after it has been checked as it actually is:
  - UI and images: screenshots the agent opened and described;
  - video: frames and file parameters;
  - audio: loudness measurements and a spectrogram the agent opened; the final listen is yours;
  - code: an actual run.

  If something cannot be checked, the task is marked unverified, not done.
- **Paid calls only after studying the docs.** Before spending money on a generation (images, video, voice, etc.), an agent must study the official documentation of that exact model and record it in the project's knowledge base. Without a fresh record a hook blocks the paid call, and every allowed call is logged to `.claude\team\state\paid-calls.log`. Free actions (balance, model list, cost estimate) are never blocked. Project-specific paid tools can be added in `.claude\team\paid-tools.local.json`.
- **Final actions only on your command, after a report on open tasks.** The coordinator runs the build, packaging, release, deploy and the full tests only when you explicitly ask, and first tells you what is finished, what is still open, what will run and what it risks. The approval covers one batch of tasks.
- **No redundant work.** Expensive actions (build, packaging, deploy, a full test run, dependency install) run once per batch of tasks, not after every task. The coordinator groups tasks into a batch and opens a "gate" (the file `.claude\team\state\integration-gate`) only after all tasks of the batch are accepted and you have said yes (the file records your approval), then closes it. While the gate is closed, the `integration-guard` hook blocks such commands for everyone, and agents cannot open the gate themselves. A runs ledger `.claude\team\state\runs.md` (with a working-tree state key) prevents repeating what already succeeded on the same state. Project-specific command patterns go to `.claude\team\integration-commands.local.json`; the hook is switched off with the file `.claude\team\state\integration-guard-off`.
- **Professional tools only.** In production, tools that distort video, images, audio, UI, text or code are forbidden. The result of every processing step is compared with the source.

The models in the tables are defaults. For each task the orchestrator picks the model and effort level itself, following section 13 of its prompt (`.claude/team/reference/MODEL_POLICY.md`).

## Token economy

Every request re-reads the whole session context, so a long session burns through the 5-hour plan limit quickly.

- **One task, one session.** Start a new session for a new, unrelated task: the project state is saved on disk. The orchestrator suggests this itself.
- **`/compact`** compacts the conversation manually when it has grown. The orchestrator suggests it when the context is more than ~60% full.
- **Auto-compaction at ~250,000 tokens.** The kit sets `CLAUDE_CODE_AUTO_COMPACT_WINDOW=250000` in `.claude/settings.json` (by default compaction triggers close to the 1M-token window limit). For a different personal value, use `env` in `.claude/settings.local.json`.
- **Orchestrator on Sonnet.** By default the main session runs on Sonnet 5.5 (`"model": "sonnet"` in `.claude/settings.json`). For heavy architecture or hard debugging, switch to Opus in the model picker (`/model`); a new session starts on Sonnet again.
- **Short prompt, short reports.** Each session loads only the orchestrator's core rules; it reads the reference sections on demand. Agents do not load the orchestrator prompt and keep reports to ~40 lines.

## What's inside

| Path | What it is |
|---|---|
| `template/CLAUDE.md` | project entry point; connects the orchestrator |
| `template/.claude/team/ORCHESTRATOR.md` | orchestrator core prompt: role, rules, delegation, acceptance, token economy |
| `template/.claude/team/reference/` | orchestrator reference sections, read on demand: team (`TEAM.md`), model policy, section 13 (`MODEL_POLICY.md`), continuous work (`CONTINUOUS.md`), documents (`DOCS.md`), onboarding (`ONBOARDING.md`), task batches, gate and runs ledger (`INTEGRATION.md`) |
| `template/.claude/agents/` | 22 agent prompts |
| `template/.claude/team/templates/` | templates for project documents and the knowledge base |
| `template/.claude/team/hooks/`, `template/.claude/settings.json` | continuous work, context-loss protection, paid-call and redundant-build guards |
| `template/.claude/team/integration-commands.json`, `template/.claude/team/tree-state.ps1` | command patterns for the `integration-guard` hook and the working-tree state key for the runs ledger |
| `install.cmd`, `install.ps1` | analysis, installation and updates |
| `tests/hooks_test.py`, `tests/install_test.py`, `tests/paid_guard_test.py`, `tests/integration_guard_test.py` | tests for the hooks, the installer, the paid-call guard and the redundant-build guard |

## Model review

Every day at 12:00 and 18:00, a scheduled task on the maintainer's machine compares section 13 of the orchestrator prompt (`template/.claude/team/reference/MODEL_POLICY.md`) with Claude's current model lineup. When nothing changed it touches nothing. When something changed it updates the section, bumps the version and publishes it to GitHub, and every project then gets the update notice. The task runs only while the Claude app is open.
