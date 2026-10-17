# Runs ledger (copy to .claude/team/state/runs.md)
# Append-only: one line per expensive run (build, full tests, deploy, paid generation, long scan). Lines starting with # are comments.
# Line format:  date | action | tree=<HEAD short>+<hash8> | result | agent | evidence path
# Tree key: powershell -NoProfile -File .claude/team/tree-state.ps1   (nogit+unknown proves nothing)
# result: success | failed. Same action + same tree key + success = do not run it again, cite the line.
# Example (a comment, not a record):
# 2026-10-17 14:05 | build: npm run build | tree=428ebc9+9f8e7d6c | success | devops-engineer | .claude/team/state/progress/T-7.md
