# claude-palimpsest

A learning system for [Claude Code](https://docs.anthropic.com/en/docs/claude-code) that captures mistakes during coding sessions and turns them into persistent knowledge that loads automatically in future sessions.

## Why

Claude Code loses context between sessions. You correct the same mistakes, re-explain the same conventions, and watch it explore files it already mapped yesterday. Palimpsest fixes this by recording friction as it happens and distilling it into knowledge files that load automatically next time.

## What it does

- **Friction capture** — records bash failures, repeated edits, and search patterns in real-time (~5ms per tool use)
- **Automatic learning extraction** — background Haiku analyzes session transcripts at end, routing insights to project, framework, or global scopes
- **Knowledge lifecycle** — learnings accumulate hit counters, graduate to permanent rules at (3x)+, and auto-prune when stale
- **Session handoff** — writes a terse context summary so the next session picks up where you left off

## Install

### Plugin (recommended)

```
/plugin install https://github.com/oscargavin/claude-palimpsest
```

All hooks register automatically. Start a new session to activate.

### Shell script (fallback)

```bash
git clone https://github.com/oscargavin/claude-palimpsest.git
cd claude-palimpsest && ./install.sh
```

`--all` adds enforce-tools, task-verify, and SAIL workflow rules. `--dry-run` to preview.

### Prerequisites

- [jq](https://jqlang.github.io/jq/) — `brew install jq` or `apt install jq`
- [Claude Code](https://docs.anthropic.com/en/docs/claude-code) CLI

## What you'll see

**Session start** outputs a knowledge manifest:

```
Relevant framework knowledge detected for this project:
  - ~/.claude/knowledge/fw/nextjs.md
  - ~/.claude/knowledge/fw/typescript.md

Other knowledge available on request: docker, python, swiftui
```

**Between sessions**, Haiku writes learnings like:

```
- [2026-02-09] (1x) vitest hangs without --run flag in CI
- [2026-02-09] (2x) !! migrations: always IF EXISTS — drops are irreversible
```

The `!!` prefix pins critical entries so they never auto-prune. Hit counters track how often a lesson recurs — at `(3x)+`, project learnings graduate to permanent rules.

**Handoff** gives the next session full context:

```markdown
# Last Session Handoff

## Done
- Auth middleware: src/middleware/auth.ts — JWT validation + refresh

## Decisions
- httpOnly cookies over localStorage — XSS protection

## Next
- Add rate limiting to /api/auth/refresh
```

## How it works

```
 You code in Claude Code
         |
         v
+-----------------+    PostToolUse hooks fire on every
| Friction Capture |<-- Bash, Edit, Write, Grep, Glob
|  (real-time)     |
+--------+--------+
         | writes to ~/.claude/scratch/friction-*.log
         v
+-----------------+    SessionEnd hook fires once
| Session Analyst  |<-- when you close the session
| (background)     |
+--------+--------+
         | reads transcript + friction logs
         v
+-----------------+    Haiku extracts learnings, writes
| Knowledge Files  |<-- handoff, updates codebase map
|  (persistent)    |
+--------+--------+
         | auto-loaded via .claude/rules/
         v
   Next session starts with full context
```

### Scopes

Learnings route to the right scope automatically:

| Scope | Example | Destination |
|-------|---------|-------------|
| **Project** | "webhook only accepts POST" | `<project>/.claude/rules/learnings.md` |
| **Framework** | "vitest needs --run flag" | `~/.claude/knowledge/fw/vitest.md` |
| **Workflow** | "Claude Code hook timeout is 10s" | `~/.claude/rules/learnings.md` |

### Lifecycle

1. **Capture** — friction hooks record mistakes in real-time (bash failures, repeated edits, search chains)
2. **Extract** — session-end Haiku reads transcript + friction logs, writes learnings to the right scope
3. **Accumulate** — duplicate learnings get their counter bumped: `(1x)` > `(2x)` > `(3x)`
4. **Graduate** — at `(3x)+` project learnings become permanent rules; at `(5x)+` framework learnings go global
5. **Prune** — `(1x)` entries decay after 14-30 days; `(2x)` consolidate after 60 days; `(3x)+` and `!!` pinned entries never prune

### Budgets

The system is self-regulating. When files exceed their budget, a consolidation pass merges, graduates, and prunes entries automatically.

| File | Budget | Scope |
|------|--------|-------|
| `learnings.md` | 30 lines | Per-project or global |
| `codebase.md` | 60 lines | Per-project |
| `learned.md` | 20 lines | Per-project or global |
| `handoff.md` | 40 lines | Per-project or global |
| `knowledge/fw/*.md` | 20 entries each | Cross-project |

## Hooks reference

All hooks register automatically with the plugin. With `install.sh`, the first five are core and the last two require `--all`.

| Hook | Event | What it does |
|------|-------|-------------|
| `friction-capture.sh` | PostToolUse | Records bash fail/fix pairs, edit events, search patterns |
| `session-start.sh` | SessionStart | Clears scratch, detects frameworks, runs health checks |
| `session-learnings.sh` | SessionEnd | Spawns background Haiku to extract learnings + handoff |
| `notify-voice.sh` | Notification | Cross-platform sound alert (macOS/Linux) |
| `lib-project-root.sh` | — | Shared utility: walks up to find project root |
| `enforce-tools.sh` | PreToolUse | Blocks `cat`/`grep`/`find`/`sed`, redirects to proper tools |
| `task-verify.sh` | TaskCompleted | Auto-runs tests before task completion (vitest/jest/pytest/cargo) |

## Uninstall

**Plugin**: Disable or remove in Claude Code settings.

**Shell**: `./uninstall.sh`

Both preserve all your learnings, knowledge, and rules.

## Contributing

Issues and PRs welcome. Hooks receive JSON on stdin from Claude Code — see the [hooks docs](https://docs.anthropic.com/en/docs/claude-code/hooks) for the event schema.

## License

MIT
