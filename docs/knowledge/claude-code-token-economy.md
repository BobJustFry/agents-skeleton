# Claude Code token economy: auto-compact window, default model/effort, subagent CLAUDE.md

Sources:
- https://code.claude.com/docs/en/env-vars (CLAUDE_CODE_AUTO_COMPACT_WINDOW, CLAUDE_AUTOCOMPACT_PCT_OVERRIDE, CLAUDE_CODE_EFFORT_LEVEL, ANTHROPIC_MODEL)
- https://code.claude.com/docs/en/settings (scopes and precedence; env values wait for workspace trust)
- https://code.claude.com/docs/en/settings-reference (model, effortLevel, autoCompactWindow, env: scope "Any file")
- https://code.claude.com/docs/en/model-config (model key, aliases, effort levels and defaults, auto-compact window)
- https://code.claude.com/docs/en/sub-agents (frontmatter fields, omitClaudeMd, what subagents load)
Verified: 2026-10-17
Versions: Claude Code v2.1.271+ (omitClaudeMd); models Sonnet 5.5 / Opus 5.5 / Haiku 5.5 / Fable 5.1
Covers: autoCompactWindow|CLAUDE_CODE_AUTO_COMPACT_WINDOW|omitClaudeMd|effortLevel|model
Verified by: coordinator (WebFetch of official docs)

## a) Auto-compact threshold per project
- Env var `CLAUDE_CODE_AUTO_COMPACT_WINDOW`: window in tokens, 100000..1000000, plain integer only (`500k` is read as 500 and clamped to 100K). Capped at the model's context window. Takes precedence over `/autocompact`, `--autocompact` and the `autoCompactWindow` setting.
- Setting `autoCompactWindow` (scope: any settings file): accepts plain count, `k`/`M` suffix, or a bare 100..1000 meaning thousands. Also per-model via `modelSettings`.
- Per-subagent frontmatter `autoCompactWindow` can only lower the window.
- `CLAUDE_AUTOCOMPACT_PCT_OVERRIDE` (1-100) can only lower the trigger percentage; applies to main conversation and subagents.
- Status line `used_percentage` is measured against the full context window, not the auto-compact window.
- Project `env` values apply only after the folder is trusted (workspace trust).
- Kit choice: `"env": {"CLAUDE_CODE_AUTO_COMPACT_WINDOW": "250000"}` in `.claude/settings.json`. Because the env var beats `/autocompact`, a user who wants another value sets it in `env` of `.claude/settings.local.json` (local outranks shared project file).

## b) Default model and effort
- `"model": "sonnet"` (scope: any file). Precedence: `/model` (session) > `--model` > `ANTHROPIC_MODEL` > `model` setting. Settings precedence: managed > `--settings` > local > project > user. `/model` persists by writing user settings, so a project `model` value wins again in the next session.
- Aliases: `default`, `sonnet`, `opus`, `haiku`, `opusplan`, `best`, `fable`, `sonnet[1m]`, `opus[1m]`.
- Effort: setting `effortLevel` (`low|medium|high|xhigh`; `max` not accepted in settings), env `CLAUDE_CODE_EFFORT_LEVEL` (adds `max`, `auto`). In project/local/managed settings `effortLevel` applies to every model. Defaults in Claude Code: `medium` for Opus 5.5, Sonnet 5.5, Haiku 5.5; `xhigh` for Opus 4.7; `high` for other effort-capable models.
- Kit choice: only `model: sonnet`; no `effortLevel`, because Sonnet 5.5 already defaults to `medium` and a project `effortLevel` would also force the level after a switch to Opus. Subagent `effort` frontmatter overrides the session effort (but not `CLAUDE_CODE_EFFORT_LEVEL`).

## c) Subagents and CLAUDE.md
- By default custom and built-in subagents (except Explore and Plan) load the full CLAUDE.md hierarchy of the main conversation (user, project, local, rules, managed) plus git status. Auto memory of the main conversation is not loaded.
- Frontmatter `omitClaudeMd: true`: start the subagent without user, project and local CLAUDE.md files; managed policy files still load. Ignored when the agent runs as the main session agent (`--agent` / `agent` setting). Requires Claude Code v2.1.271+; unknown fields are ignored silently on older versions.
- Kit choice: `omitClaudeMd: true` on all 22 agents; the shared block tells agents to read the top of `CLAUDE.md` (before "AI-команда") when project conventions matter.
