# Config examples

Example config fragments and full configs for OpenClaw.

## Cursor CLI as sub-agent

Use the **Cursor CLI** as a sub-agent so the main agent can hand off IDE-style coding tasks to Cursor.

### Files

- **`cursor-subagent.json5`** — Fragment: only adds the `cursor` agent. Use via `$include` from your main config（不要单独作为 OPENCLAW_CONFIG_PATH）.
- **`cursor-subagent-full.json5`** — 完整示例：main + cursor，可直接用 `OPENCLAW_CONFIG_PATH` 指向此文件做测试。
- **`openclaw-with-cursor-subagent.json5`** — 可直接复制到 `~/.openclaw/openclaw.json` 的模板（含 `$include` + main 且 `allowAgents: ["cursor"]`）；使用前把其中的 `$include` 路径改成你本机仓库的绝对路径。

### Prerequisites

- Cursor installed; `cursor` on PATH (or set `agents.defaults.cliBackends["cursor-cli"].command` to the full path).
- Cursor CLI docs: https://cursor.com/docs/cli/overview

### Option A — 复制模板到主配置（推荐）

把 **`openclaw-with-cursor-subagent.json5`** 复制到 `~/.openclaw/openclaw.json`，并把文件里的 **`$include` 路径** 改成你本机 openclaw 仓库下 `config-examples` 的绝对路径，例如：

```bash
cp /Users/mac/Desktop/openclaw/openclaw/config-examples/openclaw-with-cursor-subagent.json5 ~/.openclaw/openclaw.json
# 然后编辑 ~/.openclaw/openclaw.json，把 $include 的路径改成你机器上的实际路径
```

这样配置里会有：main agent（default） + 通过 include 加入的 cursor agent，且 main 的 `subagents.allowAgents: ["cursor"]`，检查时就能正确看到并拉起 cursor sub-agent。

### Option A2 — 在现有配置里手动加 include

在你的 `~/.openclaw/openclaw.json` 里：

1. 顶层加上 `$include`（路径改为本机绝对路径）：

```json5
{
  $include: "/Users/mac/Desktop/openclaw/openclaw/config-examples/cursor-subagent.json5",
  // ... 你原有的 agents、channels 等
}
```

2. 保证你的 **默认 agent** 允许拉起 cursor，例如：

```json5
agents: {
  list: [
    {
      id: "main",
      default: true,
      subagents: { allowAgents: ["cursor"] },
      // ... 其他字段
    },
  ],
}
```

`$include` 会把 fragment 的 `agents.list` 与你的 list 合并（多出 cursor 一项），所以必须在你自己的 list 里给主 agent 配上 `subagents.allowAgents: ["cursor"]`。

### Option B — Merge manually

1. Append to your `agents.list` the entry from `cursor-subagent.json5` (the object with `id: "cursor"`).
2. On the agent that may call `sessions_spawn` for Cursor, set `subagents.allowAgents: ["cursor"]` (or `["*"]` to allow any configured agent).

### Handoff context (skill)

The skill **cursor-subagent** (`skills/cursor-subagent/SKILL.md`) is bundled so the main agent gets handoff guidance: when to use `sessions_spawn` with `agentId: "cursor"` and when not to. Ensure the skill is available (e.g. workspace skills or bundled allowlist) so the model sees it.

### Test with full example

To try without touching your main config:

```bash
OPENCLAW_CONFIG_PATH=/Users/mac/Desktop/openclaw/openclaw/config-examples/cursor-subagent-full.json5 openclaw gateway run
```

Then use `agents_list` and `sessions_spawn` with `agentId: "cursor"` from the main agent.
