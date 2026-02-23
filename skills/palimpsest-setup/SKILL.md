---
name: palimpsest-setup
description: Set up or repair the palimpsest learning system hooks
user-invocable: true
---

# Palimpsest Setup

You are fixing the palimpsest plugin's SessionStart and SessionEnd hooks, which don't fire due to a known Claude Code bug where `${CLAUDE_PLUGIN_ROOT}` isn't resolved for these hook events.

The fix: write absolute-path hook entries into `~/.claude/settings.json` so these two hooks bypass the plugin system entirely.

## Step 1: Find the plugin root

Run this to find where the plugin is installed:

```bash
find ~/.claude -name "plugin.json" -path "*claude-palimpsest*" 2>/dev/null | head -1
```

The plugin root is the **grandparent** of the directory containing `plugin.json` (i.e., strip `/.claude-plugin/plugin.json` from the path).

Verify the root is correct by checking that `hooks/scripts/session-start.sh` exists there.

## Step 2: Check current state

Read `~/.claude/settings.json`. Look for existing hook entries under `.hooks.SessionStart` and `.hooks.SessionEnd`.

**If entries already exist** pointing to the palimpsest plugin scripts with absolute paths, the fix is already applied. Tell the user and stop.

**If entries exist** using `${CLAUDE_PLUGIN_ROOT}`, those are broken. They need replacing.

## Step 3: Patch settings.json

Read the current `~/.claude/settings.json`, then write back with SessionStart and SessionEnd entries added/replaced. Use the absolute plugin root path found in Step 1.

The entries to add under `.hooks`:

```json
{
  "SessionStart": [
    {
      "hooks": [
        {
          "type": "command",
          "command": "bash '<PLUGIN_ROOT>/hooks/scripts/session-start.sh'",
          "timeout": 5000
        }
      ]
    }
  ],
  "SessionEnd": [
    {
      "hooks": [
        {
          "type": "command",
          "command": "bash '<PLUGIN_ROOT>/hooks/scripts/session-learnings.sh'",
          "timeout": 10000
        }
      ]
    }
  ]
}
```

Replace `<PLUGIN_ROOT>` with the actual absolute path from Step 1.

**Important**: Preserve all existing entries in settings.json. Only add/replace the SessionStart and SessionEnd hook arrays. If other hooks exist under those events (from other plugins or user config), keep them — only replace entries whose command contains `claude-palimpsest` or `session-start.sh` / `session-learnings.sh`.

## Step 4: Create directories and copy templates

```bash
mkdir -p ~/.claude/scratch ~/.claude/knowledge/fw ~/.claude/knowledge/ref ~/.claude/rules
```

For each template file (learnings.md, handoff.md, learned.md, codebase.md): if it doesn't already exist in `~/.claude/rules/`, copy it from `<PLUGIN_ROOT>/templates/`.

## Step 5: Verify

1. Read back `~/.claude/settings.json` and confirm the hooks point to real files
2. Run `bash '<PLUGIN_ROOT>/hooks/scripts/session-start.sh' <<< '{"cwd":"'$PWD'"}'` and verify it outputs a knowledge manifest
3. Tell the user: "Setup complete. Start a new session to activate SessionStart and SessionEnd hooks."

## Troubleshooting

If the plugin can't be found in Step 1:
- The plugin may not be installed yet. Tell the user to run `/plugin install https://github.com/oscargavin/claude-palimpsest` first.
- Or it may be installed via `install.sh` (scripts at `~/.claude/hooks/`). In that case, check if `~/.claude/hooks/session-start.sh` exists — if so, the shell install is active and this fix isn't needed.

If learnings aren't being captured after setup:
- Check `/tmp/claude-hooks/session-end-debug.log` for skip reasons
- Common causes: session too short (<10 transcript lines), no corrections or errors detected, `claude` CLI not available for background haiku
