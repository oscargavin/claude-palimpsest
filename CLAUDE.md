# claude-palimpsest

This repo contains a learning system for Claude Code. It captures mistakes during sessions and turns them into persistent knowledge.

## Installing

**Plugin (recommended):** `/plugin install https://github.com/oscargavin/claude-palimpsest`

**Shell script (fallback):** `./install.sh` from the repo root. Use `--all` for the full set including enforce-tools and task-verify.

### Manual install (fallback)

If neither method works:

1. Copy `hooks/scripts/` to `~/.claude/hooks/` and `chmod +x` each file
2. Copy `sounds/` to `~/.claude/sounds/`
3. Create dirs: `~/.claude/scratch/`, `~/.claude/knowledge/fw/`, `~/.claude/knowledge/ref/`
4. Copy `templates/*.md` to `~/.claude/rules/` (skip files that already exist)
5. Merge hook entries into `~/.claude/settings.json` — see `install.sh` for the exact JSON structure

## Uninstalling

**Plugin:** Disable or remove in Claude Code settings.

**Shell:** `./uninstall.sh` — removes hooks and sounds but preserves learnings and knowledge.

## Structure

- `.claude-plugin/` — plugin metadata for Claude Code's plugin system
- `hooks/hooks.json` — hook registrations (auto-loaded by plugin system)
- `hooks/scripts/` — shell scripts registered as Claude Code hooks
- `rules/` — optional workflow rules (01-sail.md)
- `sounds/` — notification sounds
- `templates/` — starter files for learnings, handoff, codebase, learned
- `skills/` — optional skills (palimpsest-setup)

## Development

Hooks receive JSON on stdin from Claude Code. Each hook type gets different fields — see [Claude Code hooks docs](https://docs.anthropic.com/en/docs/claude-code/hooks).

Key hook events:
- `PostToolUse` → friction-capture.sh (receives tool_name, tool_input, tool_response)
- `SessionStart` → session-start.sh (receives cwd)
- `SessionEnd` → session-learnings.sh (receives transcript_path, cwd, reason)
- `Notification` → notify-voice.sh
- `PreToolUse` → enforce-tools.sh (receives tool_input.command)
- `TaskCompleted` → task-verify.sh (receives task_subject, task_description, cwd)

Scripts derive their own location via `BASH_SOURCE[0]` and `PLUGIN_ROOT` for cross-references (sibling scripts, sounds, templates). No hardcoded `~/.claude/` paths for plugin resources.
