#!/bin/bash
# PostToolUse friction capture — detect mistakes as they happen
# Fast (~5ms): single jq call + file append. No LLM calls.

SCRATCH="$HOME/.claude/scratch"
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
