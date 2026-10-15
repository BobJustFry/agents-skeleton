# Claude Code PreToolUse hook

Sources:
- https://code.claude.com/docs/en/hooks (common input fields; PreToolUse decision control; matchers; subagents; timeouts and exit codes)
- https://code.claude.com/docs/en/permissions ("Extend permissions with hooks")
Verified: 2026-10-15
Versions: Claude Code 2.1.295
Covers: PreToolUse|paid-guard
Verified by: coordinator (via claude-code-guide)

## Key facts for this project
- stdin: session_id, transcript_path, cwd, permission_mode, hook_event_name, agent_id, agent_type; PreToolUse adds tool_name, tool_input, tool_use_id.
- MCP tool names: `mcp__<server>__<tool>` (plugin servers: `mcp__plugin_<plugin>_<server>__<tool>`). A matcher with any regex character is an unanchored JS regex, so `mcp__.*` matches every MCP tool.
- Hooks from settings also run inside subagents; input then carries agent_id and agent_type.
- Deny: `{"hookSpecificOutput":{"hookEventName":"PreToolUse","permissionDecision":"deny","permissionDecisionReason":"..."}}` (reason is shown to Claude). Exit 2 also blocks and takes precedence. Across hooks: deny > defer > ask > allow.
- Exit 0 with no output = no decision, the call continues through the normal permission flow.
- Failure: crash, non-2 exit or timeout is NON-blocking by default (default timeout 600 s for command hooks). Since v2.1.295 `"onFailure": "block"` makes failure block. The paid guard therefore fails closed internally for matched paid tools.
- `systemMessage` = warning shown to the user (not to Claude); `additionalContext` = text for Claude.

## Open questions / unconfirmed
- Whether a PreToolUse deny is enforced in bypassPermissions / auto mode is not documented explicitly (no exception is documented either). Verify live.
