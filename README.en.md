[Русский](README.md) | **English**

# Karkas — a ready-made AI team for any project

Install Karkas into a project folder, and Claude Code in that folder becomes the **Chief Orchestrator**. It works out the task, plans it, hands the work to 22 specialists, checks the results and reports back to you.

It suits:
- websites;
- AI content, video and music;
- marketing and promotion;
- web, mobile and desktop apps;
- bots and AI products.

It works both in new projects and in existing ones.

## How to use

**Get the kit** (once):

```powershell
git clone https://github.com/BobJustFry/agents-skeleton.git P:\Projects\Karkas
```

**New project.** Double-click `install.cmd` and enter the path to a new folder, for example `P:\Projects\MySite`. The folder is created together with the team.

**Existing project.** Do the same, but point to the project folder. Your files are never deleted or overwritten.
- If the project already has a `CLAUDE.md`, one line is appended to it to connect the orchestrator.
- If it has a `.claude/settings.json`, two hooks are added to it. Your settings are kept, and a backup copy is saved.

**Update the team in a project** after the kit has changed:

```powershell
P:\Projects\Karkas\install.cmd "P:\Projects\MyProject" -Update
```

Previous versions of the files are saved to `.claude\team\backup\` inside the project.

After installing, open the project folder in Claude Code and describe what you need.

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
| `researcher` | technology and market research (read-only) | sonnet / medium |
| `tech-writer` | documentation and guides | sonnet / medium |

## Team rules

- **Language.** Agents talk to each other and to the orchestrator in English, the native language of Claude models, where they work most precisely. The orchestrator talks to the owner in Russian only, and everything meant for the owner is written in Russian. You can change this in section 1.1 of `ORCHESTRATOR.md`.
- **Fresh data.** Before each task, every specialist checks the official documentation. Findings are kept in the project's `docs/knowledge/` and refreshed when they are more than 7 days old.
- **Brief, no fluff.** Everyone answers to the point.
- **When something is unknown:** official documentation first, then practical experience from the internet, and only then a question to you.
- **Money** is spent only within a budget you have approved, for the whole task or for a stage.
- **They argue with you.** If you are wrong, neither the orchestrator nor the agents will agree. A disputed decision is carried out only after you confirm you accept the risks with your personal code word. The code word lives only in your private settings in `~/.claude/CLAUDE.md`; it is not part of the kit.
- **Work does not stall.** While the session is open, the orchestrator checks every 5 minutes whether there is work to do. When there is none, the check replies with a single `·` (the app does not allow a fully empty reply). If the orchestrator tries to stop while tasks are still unfinished, a hook sends it back to work.
- **Protection against context loss.** When the context overflows it is compacted and details are lost. So the orchestrator keeps a state file on disk (tasks, decisions, budgets, next step), and each agent keeps its brief and progress files. After compaction a hook restores the rules and the state, every summary is archived, and agents have persistent per-project memory.
- **Nobody works blind.** A result is accepted only after it has been checked as it actually is:
  - UI and images: screenshots the agent opened and described;
  - video: frames and file parameters;
  - audio: loudness measurements and a spectrogram the agent opened; the final listen is yours;
  - code: an actual run.

  If something cannot be checked, the task is marked unverified, not done.
- **Professional tools only.** In production, tools that distort video, images, audio, UI, text or code are forbidden. The result of every processing step is compared with the source.

The models in the tables are defaults. For each task the orchestrator picks the model and effort level itself, following section 13 of its prompt.

## What's inside

| Path | What it is |
|---|---|
| `template/CLAUDE.md` | project entry point; connects the orchestrator |
| `template/.claude/team/ORCHESTRATOR.md` | orchestrator prompt: role, team, rules, model policy (section 13) |
| `template/.claude/agents/` | 22 agent prompts |
| `template/.claude/team/templates/` | templates for project documents and the knowledge base |
| `template/.claude/team/hooks/`, `template/.claude/settings.json` | continuous work and context-loss protection |
| `install.cmd`, `install.ps1` | installation and updates |
| `tests/hooks_test.py` | hook tests: Cyrillic paths, worktrees, stop guard, restore after compaction |

## Model review

Every day at 12:00 and 18:00, a scheduled task on the maintainer's machine compares section 13 of the orchestrator prompt with Claude's current model lineup and updates the section when something has changed. The task runs only while the Claude app is open.
