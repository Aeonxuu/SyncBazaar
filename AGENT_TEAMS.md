# Agent Teams — Setup & Usage

How to run multiple Claude Code sessions as a coordinated team on this project.

Agent teams are **experimental**. Behavior changes between Claude Code versions — when this file
and [the official docs](https://code.claude.com/docs/en/agent-teams) disagree, the docs are right
and this file is stale.

---

## 1. What it is (and when not to use it)

One session is the **lead**. It spawns **teammates** — full, separate Claude Code sessions, each
with its own context window. They share a task list and can message each other directly.

Not the same as subagents:

|               | Subagents   | Agent teams       |
| ------------- | ----------- | ----------------- |
| Communication | Report back | Teammates message |
| Coordination  | Main agent  | Shared task list  |
| Token cost    | Lower       | **Much higher**   |

**Use a team for:** parallel review, research, competing debugging hypotheses, or separate modules
where each teammate owns different files.

**Don't use a team for:** sequential work, anything where two teammates would edit the same file, or
routine tasks. A single session or a subagent is cheaper and usually better.

---

## 2. Enable it

Add the env var to a `settings.json`. On this machine it's already done, in
`.claude/settings.local.json` at the repo root:

```json
{
  "permissions": { "allow": ["..."] },
  "env": {
    "CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS": "1"
  }
}
```

Which file to use:

| File                          | Scope                                                                |
| ----------------------------- | -------------------------------------------------------------------- |
| `.claude/settings.local.json` | This project only, gitignored. **What we use.**                      |
| `~/.claude/settings.json`     | Every project on this machine                                        |
| `.claude/settings.json`       | This project, committed — turns it on for anyone who clones the repo |

**Restart Claude Code after editing.** Env vars are applied at process start; until you restart, no
team is set up and Claude won't spawn teammates.

### Verify it took

```bash
echo $CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS   # want: 1
```

Run it through Claude's Bash tool, not a bare terminal — it reads Claude Code's own process
environment, which is what actually matters.

---

## 3. Before the first spawn

### CLAUDE.md must exist

Teammates load `CLAUDE.md`, MCP servers, and skills from the working directory, plus the lead's
spawn prompt. **They do not inherit the lead's conversation history.** Without `CLAUDE.md`, every
teammate rediscovers the project from scratch and burns context doing it.

This repo's `CLAUDE.md` is at the root and covers the `syncbazaar/` subfolder gotcha, the commands,
and the no-backend / landscape-tablet constraints. Keep it current.

### Pre-approve common commands

Teammate permission prompts **all surface in the lead session**. A team doing Flutter work will
interrupt you on every `flutter test` and `flutter analyze` unless those are allowlisted first:

```json
"permissions": {
  "allow": [
    "Bash(cd syncbazaar && flutter test:*)",
    "Bash(cd syncbazaar && flutter analyze)",
    "Bash(git status:*)",
    "Bash(git diff:*)"
  ]
}
```

A teammate cannot approve a prompt on your behalf, and a teammate that was denied an action can't
route around it by asking another teammate. That's by design.

### Display mode

Two modes. `in-process` is the default and the right one on this machine.

- **in-process** — everyone runs in your one terminal, listed in the agent panel below the prompt.
  Works anywhere, no setup.
- **split panes** — one pane per teammate. Needs `tmux` or iTerm2 + the `it2` CLI.

**Split panes do not work in the VS Code integrated terminal**, and `tmux` isn't installed here, so
leave `teammateMode` unset. Only change it if you move to iTerm2 and install one of those:

```json
{ "teammateMode": "auto" }
```

---

## 4. Spawn a team

Plain English to the lead. Be explicit that you want a _team_ — Claude sometimes uses subagents
instead, and both show up in the same agent panel, so the panel alone doesn't prove a team formed.

```text
Spawn three teammates to review the uncommitted changes on this branch:
- one on Cubit/repository correctness
- one checking design-token compliance against DESIGN_GUIDELINES.md
- one on test coverage gaps
Have each report findings. Name them correctness, design, and tests.
```

Useful extras:

- **Name them** in the prompt — you need stable names to message them later.
- **Pick models**: "Use Sonnet for each teammate." Teammates don't inherit the lead's `/model`;
  change the fallback under **Default teammate model** in `/config`. They _do_ inherit effort level.
- **Reuse a role**: reference a subagent definition by name — "spawn a teammate using the
  security-reviewer agent type". Its `tools` allowlist and `model` are honored; its `skills` and
  `mcpServers` frontmatter are not.
- **Gate risky work**: "Require plan approval before they make any changes." The teammate stays
  read-only until the lead approves. Give the lead criteria ("only approve plans with test
  coverage") or it decides alone.

---

## 5. Drive it

In-process agent panel, below the prompt input:

| Key    | Does                                           |
| ------ | ---------------------------------------------- |
| ↑ / ↓  | Select a teammate                              |
| Enter  | Open its transcript; typing sends it a message |
| Esc    | Interrupt its current turn                     |
| `x`    | Stop the selected teammate                     |
| Ctrl+T | Toggle the task list                           |

While viewing a teammate, plain text and skills go to _that teammate_, but built-in commands still
run in the lead's session. `/model` and `/fast` only ever affect the lead — a teammate's model is
fixed at spawn.

Idle rows hide ~30s after the whole panel goes idle and come back on the teammate's next turn. A
vanished row means hidden, not dead. More than three idle teammates collapse into one `N idle
agents` row; Enter expands it.

To end one: _"Ask the researcher teammate to shut down."_ It can accept or refuse with a reason.
Shared directories are cleaned up automatically when the session ends.

---

## 6. Working practices

- **3-5 teammates.** Token cost scales linearly and coordination overhead grows. Three focused
  teammates beat five scattered ones. 15 independent tasks is still a 3-teammate job.
- **Split by file ownership.** Two teammates editing the same file overwrite each other. This is the
  main way teams go wrong.
- **Front-load context in the spawn prompt.** They have `CLAUDE.md` and nothing from your session.
  Name the paths, the constraints, and the deliverable.
- **Size tasks to a clear deliverable** — a function, a test file, a review. 5-6 tasks per teammate.
- **Start with read-only work.** Review, research, investigation. Parallel implementation is the
  hard mode.
- **Monitor.** Unattended teams waste effort at 3-5x the token burn.

Good first runs on this repo:

- Parallel review of the uncommitted diff (correctness / design tokens / test coverage).
- Competing hypotheses on a POS or sync bug — teammates argue and try to disprove each other.
- `BACKEND_READINESS.md` gap analysis, one teammate per layer (models, repositories, services).

---

## 7. Troubleshooting

| Symptom                               | Fix                                                                                                         |
| ------------------------------------- | ----------------------------------------------------------------------------------------------------------- |
| No teammates appear                   | Check the agent panel with ↑/↓. Confirm the task was big enough. Ask again and say "agent team" explicitly. |
| A teammate row vanished               | Idle, not stopped. Message it by name to bring it back.                                                     |
| Flooded with permission prompts       | Pre-approve the commands (§3).                                                                              |
| Teammate stopped early after an error | Open it and give instructions, or spawn a replacement.                                                      |
| Lead quits before tasks are done      | Tell it to keep going.                                                                                      |
| Task stuck, dependents blocked        | Teammates sometimes forget to mark complete. Update the status or nudge the lead.                           |
| Orphaned tmux session                 | `tmux ls`, then `tmux kill-session -t <name>`                                                               |

---

## 8. Limitations

- **`/resume` and `/rewind` do not restore in-process teammates.** The lead may try to message
  teammates that no longer exist. Tell it to spawn new ones.
- **One team per session**, scoped to that session. No named teams, no sharing across sessions.
- **No nested teams** — only the lead spawns teammates.
- **Lead is fixed** for the session's lifetime; no promoting a teammate.
- **Permissions are set at spawn** from the lead's mode; no per-teammate modes at spawn time.
- **Shutdown is slow** — a teammate finishes its current tool call first.
- Team config lives at `~/.claude/teams/{team-name}/config.json` and holds live runtime state.
  **Don't hand-edit or pre-author it**; it's overwritten on the next state update. A
  `.claude/teams/teams.json` inside the project is not config — it's just a file.
