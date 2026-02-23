# claude-palimpsest

A learning system for [Claude Code](https://docs.anthropic.com/en/docs/claude-code) that captures mistakes during coding sessions and turns them into persistent knowledge that loads automatically in future sessions.

- **Friction capture** — records bash failures, repeated edits, and search patterns in real-time
- **Automatic learning extraction** — background Haiku analyzes session transcripts at session end, routing insights to project, framework, or global scopes
- **Knowledge lifecycle** — learnings accumulate hit counters, graduate to permanent rules at (3x)+, and auto-prune when stale

## Install

```bash
git clone https://github.com/OscarGavin/claude-palimpsest.git
cd claude-palimpsest && ./install.sh
```

Start a new Claude Code session to activate.

### Options

```
./install.sh              # Core hooks only
./install.sh --all        # Core + enforce-tools, task-verify, SAIL workflow
./install.sh --dry-run    # Preview without changes
```

### Prerequisites

- [jq](https://jqlang.github.io/jq/) — `brew install jq` or `apt install jq`
- [Claude Code](https://docs.anthropic.com/en/docs/claude-code) CLI

## How it works

```
 You code in Claude Code
         │
         ▼
┌─────────────────┐    PostToolUse hooks fire on every
│ Friction Capture │◄── Bash, Edit, Write, Grep, Glob
│  (real-time)     │
└────────┬────────┘
         │ writes to ~/.claude/scratch/friction-*.log
         ▼
┌─────────────────┐    SessionEnd hook fires once
│ Session Analyst  │◄── when you close the session
│ (background)     │
└────────┬────────┘
         │ reads transcript + friction logs
         ▼
┌─────────────────┐    Haiku extracts learnings, writes
│ Knowledge Files  │◄── handoff, updates codebase map
│  (persistent)    │
└────────┬────────┘
         │ auto-loaded via .claude/rules/
         ▼
   Next session starts with full context
```

## What gets installed

```
~/.claude/
  hooks/
    friction-capture.sh     # PostToolUse: bash fail→fix pairs, edit events, searches
    session-start.sh        # SessionStart: clear scratch, detect frameworks, health checks
    session-learnings.sh    # SessionEnd: transcript → haiku → learnings + handoff
    lib-project-root.sh     # Shared: walk up to find .git/package.json/CLAUDE.md
    notify-voice.sh         # Notification: sound alert (cross-platform)
  sounds/
    tap_01.wav              # Notification sound
    tap_02.wav              # Session-end sound
  rules/
    learnings.md            # Global learnings (auto-populated)
    handoff.md              # Last session context (auto-populated)
    learned.md              # Graduated permanent rules
    codebase.md             # Semantic codebase map (per-project)
  knowledge/
    fw/                     # Framework-specific learnings (auto-created)
    ref/                    # Reference docs (user-managed)
  scratch/                  # Ephemeral friction logs (cleared each session)
  settings.json             # Hook registrations merged in
```

## Configuration

The system is self-regulating with built-in budgets:

| File | Budget | Scope |
|------|--------|-------|
| `learnings.md` | 30 lines | Per-project or global |
| `codebase.md` | 60 lines | Per-project |
| `learned.md` | 20 lines | Per-project or global |
| `handoff.md` | 40 lines | Per-project or global |
| `knowledge/fw/*.md` | 20 entries each | Cross-project |

When files exceed their budget, a Tier 2 consolidation pass automatically merges, graduates, and prunes entries.

### Health checks

Session start runs silent health checks and only warns when something needs attention:
- Learnings file over 30 entries
- Framework knowledge files over 25-line budget
- Handoff file older than 7 days

## The `--all` extras

These are opinionated additions — useful but not required:

| Hook | What it does |
|------|-------------|
| `enforce-tools.sh` | Blocks `cat`, `grep`, `find`, `sed` in Bash — redirects to Read, Grep, Glob, Edit tools |
| `task-verify.sh` | Auto-runs tests on task completion (auto-detects vitest/jest/pytest/cargo) |
| `01-sail.md` | SAIL workflow phases: Scout → Architect → Implement → Launch |

## Uninstall

```bash
./uninstall.sh
```

Removes hooks, sounds, and settings entries. Preserves all your learnings, knowledge, and rules.

## How learnings work

### Lifecycle

1. **Capture** — friction hooks record mistakes in real-time (bash failures, repeated edits, search chains)
2. **Extract** — session-end Haiku reads transcript + friction logs, writes learnings to the right scope
3. **Accumulate** — duplicate learnings get their counter bumped: `(1x)` → `(2x)` → `(3x)`
4. **Graduate** — at `(3x)+` project learnings become permanent rules in `learned.md`; at `(5x)+` framework learnings graduate to global rules
5. **Prune** — `(1x)` entries decay after 14-30 days; `(2x)` consolidate after 60 days; `(3x)+` and `!!` pinned entries never prune

### Scopes

| Scope | Example | Destination |
|-------|---------|-------------|
| **Project** | "webhook only accepts POST" | `<project>/.claude/rules/learnings.md` |
| **Framework** | "vitest needs --run flag" | `~/.claude/knowledge/fw/vitest.md` |
| **Workflow** | "Claude Code hook timeout is 10s" | `~/.claude/rules/learnings.md` |

### Entry format

```
- [2026-02-09] (1x) vitest hangs without --run flag in CI
- [2026-02-09] (2x) !! migrations: always IF EXISTS — drops are irreversible
```

The `!!` prefix pins critical entries (data loss, security, broken deploys) so they never auto-prune.

## License

MIT
