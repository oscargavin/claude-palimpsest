#!/bin/bash
# PostToolUse friction capture — detect mistakes as they happen
# Fast (~5ms): single jq call + file append. No LLM calls.
# Also bootstraps session setup if SessionStart hook didn't fire (plugin env var bug #27145)

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PLUGIN_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"

SCRATCH="$HOME/.claude/scratch"

# Bootstrap: run session setup once per session if SessionStart didn't fire
# Guard file is cleared by session-start.sh; if it doesn't exist, setup hasn't run
if [ ! -f "$SCRATCH/.session-active" ]; then
  mkdir -p "$SCRATCH"
  mkdir -p "$HOME/.claude/knowledge/fw"
  mkdir -p "$HOME/.claude/knowledge/ref"
  mkdir -p "$HOME/.claude/rules"
  for tmpl in learnings.md handoff.md learned.md codebase.md; do
    [ ! -f "$HOME/.claude/rules/$tmpl" ] && [ -f "$PLUGIN_ROOT/templates/$tmpl" ] && \
      cp "$PLUGIN_ROOT/templates/$tmpl" "$HOME/.claude/rules/$tmpl"
  done
  rm -f "$SCRATCH"/friction-*
  touch "$SCRATCH/.session-active"
fi

mkdir -p "$SCRATCH"

INPUT=$(cat)
TS=$(date +%H:%M:%S)

# Single jq call extracts everything we might need (tab-separated)
eval "$(echo "$INPUT" | jq -r '
  @sh "TOOL=\(.tool_name)",
  @sh "EXIT_CODE=\(.tool_response.exitCode // "")",
  @sh "CMD=\(.tool_input.command // "")",
  @sh "STDERR=\(.tool_response.stderr // "")",
  @sh "FILE=\(.tool_input.file_path // "")",
  @sh "PATTERN=\(.tool_input.pattern // "")",
  @sh "OLD_STR=\(.tool_input.old_string // "")"
')"

case "$TOOL" in
  Bash)
    CMD="${CMD:0:200}"
    if [ "$EXIT_CODE" != "0" ] && [ -n "$EXIT_CODE" ]; then
      STDERR="${STDERR:0:200}"
      # Tab-delimited to avoid pipe collision in commands
      printf '%s\t%s\t%s\n' "$TS" "$CMD" "$STDERR" > "$SCRATCH/friction-open-bash"

    elif [ -f "$SCRATCH/friction-open-bash" ]; then
      IFS=$'\t' read -r fail_ts fail_cmd fail_err < "$SCRATCH/friction-open-bash"
      echo "[$fail_ts→$TS] \`$fail_cmd\` failed ($fail_err) → fixed by \`$CMD\`" >> "$SCRATCH/friction-pairs.log"
      rm -f "$SCRATCH/friction-open-bash"
    fi
    ;;

  Edit|Write)
    # Include first 50 chars of old_string so haiku can detect same-spot re-edits
    CONTEXT="${OLD_STR:0:50}"
    [ -n "$FILE" ] && echo "$TS|$FILE|$CONTEXT" >> "$SCRATCH/friction-edits.log"
    ;;

  Grep|Glob)
    [ -n "$PATTERN" ] && echo "$TS|$TOOL|$PATTERN" >> "$SCRATCH/friction-searches.log"
    ;;
esac

exit 0
