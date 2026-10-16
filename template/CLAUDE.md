# Проект

<!-- Здесь можно описать правила конкретного проекта: стек, команды запуска и тестов, соглашения. -->

# AI-команда (Каркас)
@.claude/team/ORCHESTRATOR.md

# Karkas: compaction instructions
When compacting the conversation, always preserve: the current goal and stage; every active task ID with its agent, status, brief and checkpoint paths; decisions made and approved budgets; any OWNER OVERRIDE; open questions to the owner; files changed in this session; the next concrete step. After compaction, the core orchestrator rules are in .claude/team/ORCHESTRATOR.md (reference files in .claude/team/reference/, read on demand as its last section says) and the saved working state is in .claude/team/state/STATE.md.
