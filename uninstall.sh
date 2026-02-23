#!/bin/bash
set -euo pipefail

# claude-palimpsest uninstaller
# Removes hooks and sounds, preserves user content (rules/, knowledge/)

CLAUDE_DIR="$HOME/.claude"

# --- Colors ---
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
BLUE='\033[0;34m'
NC='\033[0m'

info() { echo -e "${BLUE}→${NC} $1"; }
ok() { echo -e "${GREEN}✓${NC} $1"; }
warn() { echo -e "${YELLOW}!${NC} $1"; }

# --- Remove hook entries from settings.json ---
info "Cleaning settings.json..."

SETTINGS_FILE="$CLAUDE_DIR/settings.json"

if [ -f "$SETTINGS_FILE" ]; then
  CLEANED=$(jq '
    if .hooks then
      .hooks |= with_entries(
        .value |= [.[] | select(
          (.hooks // []) | all(.command | tostring | contains("/.claude/hooks/") | not)
        )]
      ) |
      .hooks |= with_entries(select(.value | length > 0)) |
      if .hooks == {} then del(.hooks) else . end
    else . end
  ' "$SETTINGS_FILE")

  echo "$CLEANED" | jq '.' > "$SETTINGS_FILE"
  ok "  Hook entries removed from settings.json"
else
  warn "  No settings.json found"
fi

# --- Remove hook scripts ---
info "Removing hook scripts..."

HOOKS=(
  "friction-capture.sh"
  "session-start.sh"
  "session-learnings.sh"
  "lib-project-root.sh"
  "notify-voice.sh"
  "enforce-tools.sh"
  "task-verify.sh"
)

HOOKS_DIR="$CLAUDE_DIR/hooks"
for hook in "${HOOKS[@]}"; do
  if [ -f "$HOOKS_DIR/$hook" ]; then
    rm -f "$HOOKS_DIR/$hook"
    ok "  Removed $hook"
  fi
done

# Remove hooks dir if empty
rmdir "$HOOKS_DIR" 2>/dev/null && ok "  Removed empty hooks/" || true

# --- Remove sounds ---
info "Removing sounds..."

SOUNDS_DIR="$CLAUDE_DIR/sounds"
if [ -d "$SOUNDS_DIR" ]; then
  rm -f "$SOUNDS_DIR/tap_01.wav" "$SOUNDS_DIR/tap_02.wav"
  rmdir "$SOUNDS_DIR" 2>/dev/null && ok "  Removed sounds/" || warn "  sounds/ has other files, kept directory"
else
  warn "  No sounds directory found"
fi

# --- Clean scratch ---
info "Cleaning scratch files..."
rm -f "$CLAUDE_DIR/scratch"/friction-* 2>/dev/null
ok "  Friction scratch cleaned"

# --- Preserved ---
echo ""
echo -e "${GREEN}━━━ Uninstall complete ━━━${NC}"
echo ""
echo "Preserved (your content):"
echo "  ~/.claude/rules/       (learnings, handoff, codebase, learned)"
echo "  ~/.claude/knowledge/   (framework knowledge, reference docs)"
echo ""
echo "To fully remove all generated content:"
echo "  rm -rf ~/.claude/rules/ ~/.claude/knowledge/"
