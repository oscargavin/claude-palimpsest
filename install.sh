#!/bin/bash
set -euo pipefail

# claude-palimpsest installer
# Usage: ./install.sh [--all] [--dry-run]

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
CLAUDE_DIR="$HOME/.claude"
DRY_RUN=false
INSTALL_ALL=false

for arg in "$@"; do
  case "$arg" in
    --all) INSTALL_ALL=true ;;
    --dry-run) DRY_RUN=true ;;
    --help|-h)
      echo "Usage: ./install.sh [--all] [--dry-run]"
      echo ""
      echo "Default (core):  friction-capture, session-start, session-learnings,"
      echo "                 lib-project-root, notify-voice"
      echo "--all adds:      enforce-tools, task-verify, 01-sail.md"
      echo "--dry-run:       show what would be installed without making changes"
      exit 0
      ;;
    *)
      echo "Unknown option: $arg"
      echo "Usage: ./install.sh [--all] [--dry-run]"
      exit 1
      ;;
  esac
done

# --- Colors ---
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
BLUE='\033[0;34m'
NC='\033[0m'

info() { echo -e "${BLUE}→${NC} $1"; }
ok() { echo -e "${GREEN}✓${NC} $1"; }
warn() { echo -e "${YELLOW}!${NC} $1"; }
err() { echo -e "${RED}✗${NC} $1"; }

if $DRY_RUN; then
  info "Dry run — no changes will be made"
  echo ""
fi

# --- Check prerequisites ---
info "Checking prerequisites..."

if ! command -v jq >/dev/null 2>&1; then
  err "jq is required but not installed"
  echo "  Install: brew install jq (macOS) or apt install jq (Linux)"
  exit 1
fi

if ! command -v claude >/dev/null 2>&1; then
  warn "claude CLI not found — hooks will be installed but won't run until claude is available"
fi

ok "Prerequisites OK"

# --- Define hook sets ---
CORE_HOOKS=(
  "friction-capture.sh"
  "session-start.sh"
  "session-learnings.sh"
  "lib-project-root.sh"
  "notify-voice.sh"
)

ALL_HOOKS=(
  "enforce-tools.sh"
  "task-verify.sh"
)

# --- Copy hooks ---
info "Installing hooks..."

HOOKS_DIR="$CLAUDE_DIR/hooks"
if ! $DRY_RUN; then
  mkdir -p "$HOOKS_DIR"
fi

install_hook() {
  local hook="$1"
  if $DRY_RUN; then
    echo "  Would copy: hooks/$hook → $HOOKS_DIR/$hook"
  else
    cp "$SCRIPT_DIR/hooks/$hook" "$HOOKS_DIR/$hook"
    chmod +x "$HOOKS_DIR/$hook"
    ok "  $hook"
  fi
}

for hook in "${CORE_HOOKS[@]}"; do
  install_hook "$hook"
done

if $INSTALL_ALL; then
  for hook in "${ALL_HOOKS[@]}"; do
    install_hook "$hook"
  done
fi

# --- Copy sounds ---
info "Installing sounds..."

SOUNDS_DIR="$CLAUDE_DIR/sounds"
if $DRY_RUN; then
  echo "  Would copy: sounds/ → $SOUNDS_DIR/"
else
  mkdir -p "$SOUNDS_DIR"
  cp "$SCRIPT_DIR/sounds/"*.wav "$SOUNDS_DIR/"
  ok "  tap_01.wav, tap_02.wav"
fi

# --- Create directories ---
info "Creating directories..."

DIRS=(
  "$CLAUDE_DIR/scratch"
  "$CLAUDE_DIR/knowledge/fw"
  "$CLAUDE_DIR/knowledge/ref"
  "$CLAUDE_DIR/rules"
)

for dir in "${DIRS[@]}"; do
  if $DRY_RUN; then
    [ ! -d "$dir" ] && echo "  Would create: $dir"
  else
    mkdir -p "$dir"
  fi
done

if ! $DRY_RUN; then
  ok "  Directories ready"
fi

# --- Merge settings.json ---
info "Merging settings.json..."

SETTINGS_FILE="$CLAUDE_DIR/settings.json"
HOOKS_PATH="$HOME/.claude/hooks"

# Build the hooks JSON
# Core hooks — always installed
HOOKS_JSON=$(jq -n \
  --arg hooks_path "$HOOKS_PATH" \
'{
  SessionStart: [
    {
      hooks: [
        {
          type: "command",
          command: ("bash " + $hooks_path + "/session-start.sh"),
          timeout: 5000
        }
      ]
    }
  ],
  SessionEnd: [
    {
      hooks: [
        {
          type: "command",
          command: ("bash " + $hooks_path + "/session-learnings.sh"),
          timeout: 10000
        }
      ]
    }
  ],
  PostToolUse: [
    {
      matcher: "Bash",
      hooks: [
        {
          type: "command",
          command: ("bash " + $hooks_path + "/friction-capture.sh"),
          timeout: 1000
        }
      ]
    },
    {
      matcher: "Edit",
      hooks: [
        {
          type: "command",
          command: ("bash " + $hooks_path + "/friction-capture.sh"),
          timeout: 1000
        }
      ]
    },
    {
      matcher: "Write",
      hooks: [
        {
          type: "command",
          command: ("bash " + $hooks_path + "/friction-capture.sh"),
          timeout: 1000
        }
      ]
    },
    {
      matcher: "Grep",
      hooks: [
        {
          type: "command",
          command: ("bash " + $hooks_path + "/friction-capture.sh"),
          timeout: 1000
        }
      ]
    },
    {
      matcher: "Glob",
      hooks: [
        {
          type: "command",
          command: ("bash " + $hooks_path + "/friction-capture.sh"),
          timeout: 1000
        }
      ]
    }
  ],
  Notification: [
    {
      matcher: "",
      hooks: [
        {
          type: "command",
          command: ("bash " + $hooks_path + "/notify-voice.sh"),
          timeout: 10000
        }
      ]
    }
  ]
}')

# Add --all hooks if requested
if $INSTALL_ALL; then
  HOOKS_JSON=$(echo "$HOOKS_JSON" | jq \
    --arg hooks_path "$HOOKS_PATH" \
  '. + {
    PreToolUse: [
      {
        matcher: "Bash",
        hooks: [
          {
            type: "command",
            command: ("bash " + $hooks_path + "/enforce-tools.sh"),
            timeout: 5000
          }
        ]
      }
    ],
    TaskCompleted: [
      {
        hooks: [
          {
            type: "command",
            command: ("bash " + $hooks_path + "/task-verify.sh"),
            timeout: 120000
          }
        ]
      }
    ]
  }')
fi

if $DRY_RUN; then
  echo "  Would merge hook entries into $SETTINGS_FILE"
  echo "  Hook events: $(echo "$HOOKS_JSON" | jq -r 'keys | join(", ")')"
else
  # Read existing settings or start fresh
  if [ -f "$SETTINGS_FILE" ]; then
    EXISTING=$(cat "$SETTINGS_FILE")
  else
    EXISTING='{}'
  fi

  # For each hook event in our config:
  # 1. Filter out any existing entries whose command contains ~/.claude/hooks/ (our hooks)
  # 2. Append our fresh entries
  # This makes re-install idempotent
  MERGED=$(echo "$EXISTING" | jq --argjson new_hooks "$HOOKS_JSON" '
    # Ensure .hooks exists
    .hooks //= {} |

    # For each event in new_hooks, merge with existing
    reduce ($new_hooks | to_entries[]) as $event (
      .;
      .hooks[$event.key] = (
        # Keep existing entries that are NOT our hooks (dont contain ~/.claude/hooks/)
        [(.hooks[$event.key] // [])[] | select(
          (.hooks // []) | all(.command | tostring | contains("/.claude/hooks/") | not)
        )] +
        # Add our fresh entries
        $event.value
      )
    )
  ')

  echo "$MERGED" | jq '.' > "$SETTINGS_FILE"
  ok "  Settings merged (idempotent)"
fi

# --- Copy templates (only if file doesn't exist) ---
info "Installing templates..."

TEMPLATES=(
  "learnings.md"
  "handoff.md"
  "learned.md"
  "codebase.md"
)

for tmpl in "${TEMPLATES[@]}"; do
  DEST="$CLAUDE_DIR/rules/$tmpl"
  if [ -f "$DEST" ]; then
    if $DRY_RUN; then
      echo "  Skip (exists): $tmpl"
    else
      warn "  $tmpl (exists, skipped)"
    fi
  else
    if $DRY_RUN; then
      echo "  Would copy: templates/$tmpl → $DEST"
    else
      cp "$SCRIPT_DIR/templates/$tmpl" "$DEST"
      ok "  $tmpl"
    fi
  fi
done

# --- Install --all extras ---
if $INSTALL_ALL; then
  info "Installing --all extras..."

  SAIL_DEST="$CLAUDE_DIR/rules/01-sail.md"
  if $DRY_RUN; then
    echo "  Would copy: rules/01-sail.md → $SAIL_DEST"
  else
    cp "$SCRIPT_DIR/rules/01-sail.md" "$SAIL_DEST"
    ok "  01-sail.md (SAIL workflow)"
  fi
fi

# --- Summary ---
echo ""
echo -e "${GREEN}━━━ Installation complete ━━━${NC}"
echo ""
echo "Installed:"
echo "  Hooks:     $HOOKS_DIR/"
echo "  Sounds:    $SOUNDS_DIR/"
echo "  Templates: $CLAUDE_DIR/rules/ (new files only)"
if $INSTALL_ALL; then
  echo "  Extras:    enforce-tools, task-verify, 01-sail.md"
fi
echo ""
echo "How it works:"
echo "  1. Friction capture records mistakes as you code"
echo "  2. Session end extracts learnings via background Haiku"
echo "  3. Learnings auto-load into your next session"
echo ""
echo "Start a new Claude Code session to activate."
