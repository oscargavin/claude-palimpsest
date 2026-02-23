#!/bin/bash
# Blocks bash commands that should use dedicated tools instead
# PreToolUse hook — returns deny with guidance on which tool to use

INPUT=$(cat)
COMMAND=$(echo "$INPUT" | jq -r '.tool_input.command // empty')

[ -z "$COMMAND" ] && exit 0

# Extract the first command (before pipes, &&, ;)
FIRST_CMD=$(echo "$COMMAND" | sed 's/[|;&].*//' | awk '{print $1}' | xargs basename 2>/dev/null)

case "$FIRST_CMD" in
  cat|head|tail)
    MSG="Use the Read tool instead of $FIRST_CMD. It supports line offsets and limits."
    ;;
  find)
    MSG="Use the Glob tool instead of find. It supports patterns like **/*.ts."
    ;;
  grep|rg|ripgrep)
    MSG="Use the Grep tool instead of $FIRST_CMD. It supports regex, glob filters, and output modes."
    ;;
  sed|awk)
    MSG="Use the Edit tool instead of $FIRST_CMD. It does exact string replacement in files."
    ;;
  ls)
    # Allow ls for directory listing (no good dedicated tool for that)
    exit 0
    ;;
  *)
    exit 0
    ;;
esac

jq -n --arg reason "$MSG" '{
  hookSpecificOutput: {
    hookEventName: "PreToolUse",
    permissionDecision: "deny",
    permissionDecisionReason: $reason
  }
}'
