---
name: palimpsest-setup
description: Set up or troubleshoot the palimpsest learning system
user-invocable: true
---

# Palimpsest Setup

Check and repair the palimpsest learning system installation.

## Diagnostics

Run these checks in order:

1. **Directories exist:**
   - `~/.claude/scratch/`
   - `~/.claude/knowledge/fw/`
   - `~/.claude/knowledge/ref/`
   - `~/.claude/rules/`

2. **Template files present** (in `~/.claude/rules/`):
   - `learnings.md`
   - `handoff.md`
   - `learned.md`
   - `codebase.md`

3. **Hook registration** — check if hooks are registered:
   - Plugin install: `hooks/hooks.json` should exist in the plugin directory
   - Manual install: check `~/.claude/settings.json` for hook entries pointing to `~/.claude/hooks/`

4. **Prerequisites:**
   - `jq` installed: `command -v jq`
   - `claude` CLI installed: `command -v claude`

## Repair

If directories or templates are missing, the `session-start.sh` hook auto-creates them on next session start. To force immediate setup:

```bash
mkdir -p ~/.claude/scratch ~/.claude/knowledge/fw ~/.claude/knowledge/ref ~/.claude/rules
```

For missing templates, copy from the plugin's `templates/` directory.

## Troubleshooting

- **No learnings after session**: Check `/tmp/claude-hooks/session-end-debug.log` for skip reasons
- **No sounds**: Verify sound files exist in the plugin's `sounds/` directory and `afplay`/`paplay`/`aplay` is available
- **Friction not captured**: Ensure PostToolUse hooks are registered for Bash, Edit, Write, Grep, Glob
