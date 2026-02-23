# claude-palimpsest

This repo contains a learning system for Claude Code. It captures mistakes during sessions and turns them into persistent knowledge.

## Installing

Run `./install.sh` from the repo root. Use `--all` for the full set including enforce-tools and task-verify.

### Manual install (fallback)

If `install.sh` doesn't work:

1. Copy `hooks/` to `~/.claude/hooks/` and `chmod +x` each file
2. Copy `sounds/` to `~/.claude/sounds/`
3. Create dirs: `~/.claude/scratch/`, `~/.claude/knowledge/fw/`, `~/.claude/knowledge/ref/`
4. Copy `templates/*.md` to `~/.claude/rules/` (skip files that already exist)
5. Merge hook entries into `~/.claude/settings.json` — see `install.sh` for the exact JSON structure

## Uninstalling

Run `./uninstall.sh` — removes hooks and sounds but preserves learnings and knowledge.

## Structure

- `hooks/` — shell scripts registered as Claude Code hooks
- `rules/` — optional workflow rules (01-sail.md)
- `sounds/` — notification sounds
- `templates/` — starter files for learnings, handoff, codebase, learned

## Development

Hooks receive JSON on stdin from Claude Code. Each hook type gets different fields — see [Claude Code hooks docs](https://docs.anthropic.com/en/docs/claude-code/hooks).

Key hook events:
- `PostToolUse` → friction-capture.sh (receives tool_name, tool_input, tool_response)
- `SessionStart` → session-start.sh (receives cwd)
- `SessionEnd` → session-learnings.sh (receives transcript_path, cwd, reason)
- `Notification` → notify-voice.sh
- `PreToolUse` → enforce-tools.sh (receives tool_input.command)
- `TaskCompleted` → task-verify.sh (receives task_subject, task_description, cwd)
