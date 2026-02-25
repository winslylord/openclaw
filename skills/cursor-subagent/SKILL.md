---
name: cursor-subagent
description: "Hand off to the Cursor CLI sub-agent for IDE-style coding: multi-file refactors, codebase exploration, and tasks that benefit from Cursor's native tools. Use sessions_spawn with agentId 'cursor' when the user asks for Cursor, IDE workflows, or heavy code edits. Not for simple single-file edits (use read/edit tools) or when the user did not ask for Cursor."
metadata: { "openclaw": { "emoji": "⌨️" } }
---

# Cursor CLI sub-agent handoff

Use the **Cursor CLI** as a sub-agent when the task fits IDE-style, Cursor-native work. Spawn with `sessions_spawn` and `agentId: "cursor"`.

## When to hand off to Cursor (`agentId: "cursor"`)

- User explicitly asks to use **Cursor** or **Cursor agent**.
- **Multi-file refactors** or codebase-wide changes that benefit from Cursor’s context and tools.
- **Exploration + edit** flows: “look at this repo and fix/improve X” where Cursor’s IDE integration helps.
- **Heavy coding sessions** that are easier as a dedicated Cursor run (e.g. “implement feature X in this project”).
- User says they want “IDE” or “Cursor CLI” to do the work.

## When not to hand off

- **Simple single-file edits** (use `read` + `edit` / `apply_patch`).
- **Read-only** tasks (reading files, explaining code) — use normal tools.
- User did **not** ask for Cursor or IDE; keep the task in the main agent.

## How to spawn

1. Call **`agents_list`** to confirm `cursor` is in the allowed list.
2. Call **`sessions_spawn`** with:
   - `task`: clear description of what the Cursor agent should do (same workspace context).
   - `agentId`: `"cursor"`.
   - Optional: `label` (e.g. `"Cursor refactor"`), `model` (e.g. `"cursor-cli/default"`), `thinking` if needed.

Example:

```json
{
  "task": "Refactor the auth module to use JWT and add unit tests. Workspace is the current repo.",
  "agentId": "cursor",
  "label": "Cursor JWT refactor"
}
```

## After spawn

- The sub-agent runs in isolation; completion is **push-based**: it will **announce** back to this chat when done.
- Do **not** poll `subagents list` in a loop; check only when the user asks or you need to intervene.
- Use **`subagents`** (list/steer/kill) only for status or to steer/kill the run.

## Context for the Cursor run

- Cursor CLI uses the **workspace** configured for the `cursor` agent (e.g. `~/.openclaw/workspace-cursor` or the same as main). For “current repo” work, ensure the task description states the repo path or that the workspace is already set to that repo.
- The sub-agent gets only the **task** text; include any critical paths, file names, or constraints in the task.
