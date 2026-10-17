# Claude Code PreToolUse hook

Sources:
- https://code.claude.com/docs/en/hooks (common input fields; PreToolUse decision control; matchers; subagents; timeouts and exit codes)
- https://code.claude.com/docs/en/permissions ("Extend permissions with hooks"; Edit/Read path rules)
Verified: 2026-10-17
Versions: Claude Code 2.1.295
Covers: PreToolUse|paid-guard|integration-guard
Verified by: coordinator (via claude-code-guide); 2026-10-17 re-check of Bash/PowerShell input, matchers and `if` by WebFetch of the hooks and permissions pages

## Key facts for this project
- stdin: session_id, transcript_path, cwd, permission_mode, hook_event_name, agent_id, agent_type; PreToolUse adds tool_name, tool_input, tool_use_id.
- MCP tool names: `mcp__<server>__<tool>` (plugin servers: `mcp__plugin_<plugin>_<server>__<tool>`). A matcher with any regex character is an unanchored JS regex, so `mcp__.*` matches every MCP tool.
- Hooks from settings also run inside subagents; input then carries agent_id and agent_type.
- Deny: `{"hookSpecificOutput":{"hookEventName":"PreToolUse","permissionDecision":"deny","permissionDecisionReason":"..."}}` (reason is shown to Claude). Exit 2 also blocks and takes precedence. Across hooks: deny > defer > ask > allow.
- Exit 0 with no output = no decision, the call continues through the normal permission flow.
- Failure: crash, non-2 exit or timeout is NON-blocking by default (default timeout 600 s for command hooks). Since v2.1.295 `"onFailure": "block"` makes failure block. The paid guard therefore fails closed internally for matched paid tools; integration-guard deliberately fails open (a redundant build is cheaper than a blocked agent).
- `systemMessage` = warning shown to the user (not to Claude); `additionalContext` = text for Claude.
- Shell tools: `tool_name` is `Bash` or `PowerShell`; the command is `tool_input.command`. Write/Edit tools carry `tool_input.file_path`.
- Matcher of only letters, digits, `_`, `-`, spaces, `,` and `|` is an EXACT list: `Bash|PowerShell` matches those two tool names exactly and nothing else. Any other character makes it an unanchored JS regex (`mcp__.*`).
- Optional hook field `if` (permission-rule syntax, one rule per handler, e.g. `Bash(npm run build*)`) filters tool events before the process starts; best effort, the hook runs anyway when the command cannot be analysed. Not used by Karkas (patterns need a regex list and the rule syntax for Write/Edit paths was not verified live).
- `agent_id` / `agent_type` are present in the input when the call comes from a subagent (docs: "so you can tell which agent triggered the hook"); integration-guard treats a non-empty `agent_id` as a subagent and its absence as the main session. Live behaviour not yet confirmed.
- Hooks do not replace permission rules: the docs call the `if` filter best effort and point to the permission system for hard allow/deny.

## Open questions / unconfirmed
- Whether a PreToolUse deny is enforced in bypassPermissions / auto mode is not documented explicitly (no exception is documented either). Verify live.
