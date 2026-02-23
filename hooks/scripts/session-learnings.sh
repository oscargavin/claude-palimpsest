#!/bin/bash
# SessionEnd hook: spawn background claude -p to capture session learnings + handoff
# Non-blocking — exits 0 immediately, background process writes files asynchronously
#
# Fires once when the session actually ends (not per-response like Stop)
# Transcript is pre-condensed by jq (human/assistant text only, no tool noise)
#
# Learnings format: - [YYYY-MM-DD] (Nx) description
# Pinned entries:   - [YYYY-MM-DD] (Nx) !! description (never pruned)
# Graduation: project (3x)+ → rules/learned.md, framework (5x)+ → global learned.md
# Pruning: graduated decay — (1x)+14d flag, (1x)+30d remove, (2x)+60d consolidate, (3x)+ never

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PLUGIN_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"

INPUT=$(cat)

# Debug logging
DEBUG_LOG="/tmp/claude-hooks/session-end-debug.log"
mkdir -p /tmp/claude-hooks
echo "$(date): Hook fired. Input length: ${#INPUT}" >> "$DEBUG_LOG"

TRANSCRIPT_PATH=$(echo "$INPUT" | jq -r '.transcript_path // empty')
CWD=$(echo "$INPUT" | jq -r '.cwd // empty')
REASON=$(echo "$INPUT" | jq -r '.reason // empty')
echo "$(date): Reason: $REASON" >> "$DEBUG_LOG"

# Skip non-interactive sessions (claude -p spawned by this hook exits with "other")
[[ "$REASON" == "other" ]] && echo "$(date): Skipped (non-interactive session)" >> "$DEBUG_LOG" && exit 0

[ -z "$TRANSCRIPT_PATH" ] && echo "$(date): Skipped (no transcript)" >> "$DEBUG_LOG" && exit 0
[ ! -f "$TRANSCRIPT_PATH" ] && echo "$(date): Skipped (transcript missing)" >> "$DEBUG_LOG" && exit 0

# --- Dynamic project detection ---
source "$SCRIPT_DIR/lib-project-root.sh"
find_project_root "$CWD"

if [ -n "$PROJECT_ROOT" ]; then
  LEARNINGS_PATH="$PROJECT_ROOT/.claude/rules/learnings.md"
  GRADUATED_PATH="$PROJECT_ROOT/.claude/rules/learned.md"
  HANDOFF_PATH="$PROJECT_ROOT/.claude/rules/handoff.md"
  CODEBASE_PATH="$PROJECT_ROOT/.claude/rules/codebase.md"
else
  LEARNINGS_PATH="$HOME/.claude/rules/learnings.md"
  GRADUATED_PATH=""
  HANDOFF_PATH="$HOME/.claude/rules/handoff.md"
  CODEBASE_PATH=""
fi

GLOBAL_RULES_DIR="$HOME/.claude/rules"
FW_KNOWLEDGE_DIR="$HOME/.claude/knowledge/fw"

# --- Check if session was substantial enough ---
MSG_COUNT=$(wc -l < "$TRANSCRIPT_PATH" 2>/dev/null | tr -d ' ')
[ "${MSG_COUNT:-0}" -lt 10 ] && echo "$(date): Skipped (too short: $MSG_COUNT lines)" >> "$DEBUG_LOG" && exit 0

# --- Detect if learnings are needed ---
NEEDS_LEARNINGS=false
PATTERNS='(no,? that|that'\''s wrong|don'\''t do|that'\''s not|actually,? you|I said |I meant |you should have|that was incorrect|not what I|fix that|undo that|you forgot|you missed|instead of that)'
if jq -r 'select(.type == "user") | .message.content | if type == "array" then map(select(type == "object") | .text // "") | join(" ") elif type == "string" then . else "" end' \
   "$TRANSCRIPT_PATH" 2>/dev/null | grep -qiE "$PATTERNS"; then
  NEEDS_LEARNINGS=true
fi
if grep -qiE '"(error|Error|failed|Failed|FAILED|No such file|Cannot find|not found|ENOENT|EACCES|TypeError|SyntaxError)' "$TRANSCRIPT_PATH" 2>/dev/null; then
  NEEDS_LEARNINGS=true
fi

# Friction pairs are high-signal — if they exist, always run learnings
if [ -f "$HOME/.claude/scratch/friction-pairs.log" ] && [ -s "$HOME/.claude/scratch/friction-pairs.log" ]; then
  NEEDS_LEARNINGS=true
fi

echo "$(date): MSG_COUNT=$MSG_COUNT NEEDS_LEARNINGS=$NEEDS_LEARNINGS" >> "$DEBUG_LOG"

# --- Condense transcript ---
LOG_DIR="/tmp/claude-hooks"
CONDENSED="$LOG_DIR/condensed-$(date +%s).txt"

jq -r '
  if .type == "user" then
    .message.content |
    (if type == "array" then map(select(type == "object") | .text // "") | join(" ") elif type == "string" then . else "" end) |
    select(length > 0) | "USER: " + .
  elif .type == "assistant" then
    .message.content |
    (if type == "array" then map(select(type == "object" and .type == "text") | .text // "") | join(" ") elif type == "string" then . else "" end) |
    select(length > 0) | "CLAUDE: " + .
  else empty end
' "$TRANSCRIPT_PATH" 2>/dev/null | tail -300 > "$CONDENSED"

[ ! -s "$CONDENSED" ] && rm -f "$CONDENSED" && echo "$(date): Skipped (empty condensed)" >> "$DEBUG_LOG" && exit 0

# --- Read friction signals ---
FRICTION_CONTENT=""
SCRATCH_DIR="$HOME/.claude/scratch"

# Resolved bash pairs (highest signal)
if [ -f "$SCRATCH_DIR/friction-pairs.log" ] && [ -s "$SCRATCH_DIR/friction-pairs.log" ]; then
  FRICTION_CONTENT+="=== RESOLVED (failure → fix pairs) ===\n"
  FRICTION_CONTENT+="$(cat "$SCRATCH_DIR/friction-pairs.log")\n\n"
fi

# Re-edits (files edited 3+ times) — includes edit context for same-spot detection
if [ -f "$SCRATCH_DIR/friction-edits.log" ] && [ -s "$SCRATCH_DIR/friction-edits.log" ]; then
  RE_EDITS=$(cut -d'|' -f2 "$SCRATCH_DIR/friction-edits.log" | sort | uniq -c | sort -rn | awk '$1 >= 3 {print "  " $1 "x " $2}')
  if [ -n "$RE_EDITS" ]; then
    FRICTION_CONTENT+="=== RE-EDITS (3+ edits to same file) ===\n$RE_EDITS\n"
    # Include raw edit log so haiku can see context (what was edited each time)
    FRICTION_CONTENT+="--- edit timeline ---\n$(cat "$SCRATCH_DIR/friction-edits.log")\n\n"
  fi
fi

# Search timeline (for haiku to identify chains)
if [ -f "$SCRATCH_DIR/friction-searches.log" ] && [ -s "$SCRATCH_DIR/friction-searches.log" ]; then
  SEARCH_COUNT=$(wc -l < "$SCRATCH_DIR/friction-searches.log" | tr -d ' ')
  if [ "$SEARCH_COUNT" -gt 5 ]; then
    FRICTION_CONTENT+="=== SEARCH TIMELINE ($SEARCH_COUNT searches this session) ===\n"
    FRICTION_CONTENT+="$(cat "$SCRATCH_DIR/friction-searches.log")\n\n"
  fi
fi

# Unresolved open bash failure
if [ -f "$SCRATCH_DIR/friction-open-bash" ]; then
  FRICTION_CONTENT+="=== UNRESOLVED ===\n"
  FRICTION_CONTENT+="Bash failure never fixed: $(cat "$SCRATCH_DIR/friction-open-bash")\n"
fi

echo "$(date): Friction content length: ${#FRICTION_CONTENT}" >> "$DEBUG_LOG"

# --- Ensure directories exist ---
mkdir -p "$(dirname "$LEARNINGS_PATH")" 2>/dev/null
mkdir -p "$(dirname "$HANDOFF_PATH")" 2>/dev/null
[ -n "$GRADUATED_PATH" ] && mkdir -p "$(dirname "$GRADUATED_PATH")" 2>/dev/null
[ -n "$CODEBASE_PATH" ] && mkdir -p "$(dirname "$CODEBASE_PATH")" 2>/dev/null
mkdir -p "$FW_KNOWLEDGE_DIR" 2>/dev/null

# --- Build prompt ---
PROMPT="You are a session analyst for Claude Code. You read development session transcripts and extract three types of knowledge into files that are auto-loaded into future sessions.

Your output files directly shape how Claude behaves in the next session — accuracy and conciseness matter. Complete whichever tasks are listed below.

<data>
<transcript_file>$CONDENSED</transcript_file>
<date>$(date +%Y-%m-%d)</date>
<project>${PROJECT_NAME:-none}</project>
</data>

<instructions>
1. Read the transcript file first. It contains USER and CLAUDE messages from a development session.
2. RELEVANCE CHECK: If a project is detected, determine whether the session content is actually about that project. Look for: file edits within the project, project-specific discussion, commands run in the project directory. If the session topic is clearly unrelated to the project (e.g., macOS config, unrelated tool setup, general questions), treat it as a GLOBAL session:
   - Route learnings to framework/workflow scopes only (skip project scope)
   - Skip the codebase-knowledge task entirely
   - Write handoff to \$HOME/.claude/rules/handoff.md instead of the project path
   This prevents polluting project memory with off-topic sessions that just happened to start from that directory.
3. Complete each task below in order.
4. For every task, read the destination file before writing — merge with existing content unless the task says to overwrite.
5. Be terse — maximum signal, minimum words. Sacrifice grammar for brevity. These files are injected into system prompts where every token counts.
6. Stop when all tasks are done.
</instructions>

<friction_signals>
${FRICTION_CONTENT:-No friction signals captured this session.}

These are real-time friction signals captured by PostToolUse hooks during the session.
They survive context compaction — use them as the PRIMARY source for mistake/correction learnings.

RESOLVED pairs: highest signal. Each is a confirmed failure→fix pattern.
RE-EDITS: files edited 3+ times suggest trial-and-error. Cross-reference with transcript.
SEARCH TIMELINE: look for chains of 3+ searches before an Edit — that's navigation friction
  (the last search pattern before the edit is what worked, earlier ones missed).
UNRESOLVED: bash failure with no fix — lower priority, note if transcript provides context.
</friction_signals>"

# Task 1: Learnings (only if corrections/errors detected)
if [ "$NEEDS_LEARNINGS" = "true" ]; then
  PROMPT+="

<task name=\"learnings\" index=\"1\">
<goal>Extract lessons from corrections and debugging. Route to correct scope. Maximum signal, minimum words.</goal>

<scopes>
<scope name=\"project\">
<description>Learnings specific to this project's setup, config, architecture, or conventions.</description>
<destination>$LEARNINGS_PATH</destination>
</scope>

<scope name=\"framework\">
<description>Learnings about a framework, library, or tool that apply across ANY project using it.</description>
<destination>$FW_KNOWLEDGE_DIR/{name}.md</destination>
<naming>{name} is lowercase, hyphenated: react.md, nextjs.md, react-native.md, typescript.md, vitest.md, tailwind.md (no fw- prefix)</naming>
<new-file-format>
# {Framework} Learnings
</new-file-format>
</scope>

<scope name=\"workflow\">
<description>Cross-project patterns about how Claude Code itself works — not project or framework specific.</description>
<destination>$GLOBAL_RULES_DIR/learnings.md</destination>
</scope>
</scopes>

<entry-format>- [YYYY-MM-DD] (Nx) description</entry-format>
<pinned-format>- [YYYY-MM-DD] (Nx) !! description</pinned-format>

<examples>
<example>
<input>USER: no, don't use as casts for that — define a proper type guard</input>
<output scope=\"framework\" file=\"typescript.md\">- [2026-02-09] (1x) no \`as\` casts for API responses — use type guards with runtime checks</output>
</example>
<example>
<input>USER: the basil webhook only accepts POST, not GET</input>
<output scope=\"project\">- [2026-02-09] (1x) /webhook/github: POST only, not GET</output>
</example>
<example>
<input>CLAUDE debugged for 20 minutes before realizing the table was dropped</input>
<output scope=\"framework\" file=\"postgresql.md\">- [2026-02-09] (1x) !! migrations: always IF EXISTS, test on copy — drops are irreversible</output>
</example>
</examples>

<rules>
1. Read existing files before writing — check both project and any relevant knowledge/fw/*.md files.
2. DEDUP: If an entry covers the same root cause (even differently worded), bump its counter and update date. \"vitest hangs without --run\" and \"always pass --run to vitest\" are the SAME learning.
3. New entries start at (1x). Auto-pin with !! for: data loss, security, broken deploys, silent failures, irreversible operations.
4. Skip routine errors (404s, typos, lint warnings) — only capture insights that prevent real mistakes.
5. Keep each knowledge/fw/*.md under 20 entries. If full, prune lowest-value (1x) entries.
6. Use Glob to check for existing files in $FW_KNOWLEDGE_DIR before creating new ones.
</rules>

<graduation>
Project learnings at (3x)+ graduate to ${GRADUATED_PATH:-skip} — rewrite as a declarative rule (drop date/counter) and remove from source.
Framework learnings at (5x)+ graduate to $GLOBAL_RULES_DIR/learned.md — same format. Create with YAML frontmatter if needed.
</graduation>

<pruning>
Graduated decay — frequency protects against age:
- (1x) + 14 days: remove if low-value or superseded by another entry
- (1x) + 30 days (project) or 90 days (framework): remove
- (2x) + 60 days: consolidate with similar entries if possible, otherwise keep
- (3x)+: never auto-prune — these are graduation candidates
- !! pinned: NEVER prune regardless of age or frequency
</pruning>
</task>"
fi

# Task 2: Handoff (always for substantial sessions)
PROMPT+="

<task name=\"handoff\" index=\"2\">
<goal>Write a terse handoff so the next session starts with full context. Auto-loaded into system prompt — every word must earn its place.</goal>
<destination>$HANDOFF_PATH</destination>
<action>Overwrite entirely — only the latest session matters.</action>
<format>
# Last Session Handoff

## Done
- terse summary of what shipped (file paths, not prose)

## Decisions
- decision — why (one line each)

## Next
- concrete next step with file path
- another step

## Open
- question needing user input
</format>
<rules>
1. Under 30 lines. No YAML frontmatter. No decorative markdown.
2. File paths, function names, error messages — not descriptions of them.
3. Skip sections with nothing to say. Don't write \"None\" or \"N/A\".
</rules>
</task>"

# Task 3: Codebase knowledge (only for project sessions)
if [ -n "$CODEBASE_PATH" ]; then
  PROMPT+="

<task name=\"codebase-knowledge\" index=\"3\">
<goal>Build incremental codebase knowledge from this session. Helps future sessions skip exploration — go straight to the right files.</goal>
<destination>$CODEBASE_PATH</destination>
<action>Read existing file, merge new entries. Don't remove unless clearly wrong.</action>
<format>
# Codebase Knowledge

## Map
- ComponentName: path/to/file.ts — what it does and what it connects to

## Navigation
- description of what you're looking for → where it actually lives

## Reusables
- utility/hook/component name: path — what it does, use instead of writing your own

## Recipes
- task name: step 1 (file) → step 2 (file) → step 3 (file)
- testing pattern: how tests are structured, what helpers exist, where they live

## Fragile
- path or area — why it's risky, what to watch out for, and the fix if known
</format>

<examples>
<example type=\"map\">- AuthService: src/domain/auth-service.ts — login/signup, calls UserRepo</example>
<example type=\"navigation\">- API handlers → src/adapters/primary/ (not src/routes/)</example>
<example type=\"reusables\">- formatDate(): src/utils/date.ts — ISO→locale, don't reimplement</example>
<example type=\"recipe\">- new endpoint: adapters/primary/ → schemas/ → routes.ts → __tests__/</example>
<example type=\"recipe\">- tests: renderWithProviders() from test-utils.ts, msw not jest.mock</example>
<example type=\"fragile\">- stripe-webhook.ts — no tests, coupled to billing. ECONNREFUSED → docker compose up -d stripe-cli</example>
</examples>

<rules>
1. Only add entries you have evidence for from the transcript — do not guess or infer architecture you didn't see.
2. Keep each section under 15 entries. Prioritize entries that save the most exploration time.
3. Map entries should describe relationships (what connects to what), not just file locations.
4. Navigation entries capture cases where Claude searched in the wrong place, or the user corrected a path assumption.
5. Reusables entries capture existing utils, hooks, or components that Claude either used or should have used instead of writing new code.
6. Recipe entries include both task patterns and testing patterns — any repeatable multi-step sequence.
7. Fragile entries include known issues with their fixes when available.
8. Skip entirely if the session was purely conversational with no code navigation or changes.
9. Skip entirely if the relevance check (instruction 2) determined the session is off-topic for this project.
</rules>
</task>"
fi

# Budget constraint (always appended)
PROMPT+="

<budget>
All output files in the project's .claude/rules/ directory are injected into Claude's system prompt. Keep them concise.

Target line counts:
- learnings.md: under 30 lines
- codebase.md: under 60 lines
- learned.md: under 20 lines
- handoff.md: under 40 lines (already enforced above)
- Total per project: under 150 lines

If any file exceeds its budget after your edits, consolidate: merge similar entries, remove lowest-value (1x) items, and graduate (3x)+ entries to learned.md. Prioritize keeping codebase.md and learned.md over learnings.md — permanent knowledge beats transient corrections.

Framework files (knowledge/fw/*.md): each under 20 entries. Total across all fw files: under 100 lines.
Global learned.md: under 20 lines.
</budget>"

# --- Tier 2: Budget-triggered consolidation ---
BUDGET_LEARNINGS=35
BUDGET_CODEBASE=70
BUDGET_FW=25

# --- Spawn background claude -p (Tier 1: extract & append) ---
LOG_FILE="$LOG_DIR/session-learnings-$(date +%s).log"

echo "$(date): Spawning Tier 1 haiku" >> "$DEBUG_LOG"

nohup claude -p "$PROMPT" \
  --allowedTools "Read,Write,Edit,Glob" \
  --model haiku \
  < /dev/null > "$LOG_FILE" 2>&1 &
HAIKU_PID=$!
disown $HAIKU_PID

# Cross-platform sound helper
play_sound() {
  local file="$1"
  if command -v afplay >/dev/null 2>&1; then
    afplay "$file" 2>/dev/null
  elif command -v paplay >/dev/null 2>&1; then
    paplay "$file" 2>/dev/null
  elif command -v aplay >/dev/null 2>&1; then
    aplay "$file" 2>/dev/null
  fi
}

# Notify when Tier 1 finishes, then check for Tier 2
(
  while kill -0 $HAIKU_PID 2>/dev/null; do sleep 5; done
  play_sound "$PLUGIN_ROOT/sounds/tap_02.wav"
  rm -f "$CONDENSED"
  rm -f "$HOME/.claude/scratch/.session-active"

  # --- Tier 2: Check files against budgets ---
  OVER_BUDGET=()

  if [ -f "$LEARNINGS_PATH" ]; then
    LC=$(wc -l < "$LEARNINGS_PATH" 2>/dev/null | tr -d ' ')
    [ "${LC:-0}" -gt "$BUDGET_LEARNINGS" ] && OVER_BUDGET+=("$LEARNINGS_PATH|$BUDGET_LEARNINGS|learnings|${GRADUATED_PATH:-none}")
  fi

  if [ -n "$CODEBASE_PATH" ] && [ -f "$CODEBASE_PATH" ]; then
    LC=$(wc -l < "$CODEBASE_PATH" 2>/dev/null | tr -d ' ')
    [ "${LC:-0}" -gt "$BUDGET_CODEBASE" ] && OVER_BUDGET+=("$CODEBASE_PATH|$BUDGET_CODEBASE|codebase|none")
  fi

  for f in "$FW_KNOWLEDGE_DIR"/*.md; do
    [ -f "$f" ] || continue
    LC=$(wc -l < "$f" 2>/dev/null | tr -d ' ')
    [ "${LC:-0}" -gt "$BUDGET_FW" ] && OVER_BUDGET+=("$f|$BUDGET_FW|framework|$GLOBAL_RULES_DIR/learned.md")
  done

  if [ ${#OVER_BUDGET[@]} -gt 0 ]; then
    echo "$(date): Tier 2: ${#OVER_BUDGET[@]} file(s) over budget" >> "$DEBUG_LOG"

    FILE_LIST=""
    for entry in "${OVER_BUDGET[@]}"; do
      IFS='|' read -r fpath fbudget ftype fgrad <<< "$entry"
      CURRENT=$(wc -l < "$fpath" 2>/dev/null | tr -d ' ')
      FILE_LIST+="- $fpath (currently $CURRENT lines, budget $fbudget, type: $ftype, graduate to: $fgrad)\n"
    done

    T2_PROMPT="You are a knowledge file consolidator for Claude Code's learning system.
Inspired by NPC memory consolidation: read existing state, synthesize a clean rewrite.

Files over budget:
$(printf '%b' "$FILE_LIST")

For EACH file above:
1. Read it completely
2. Rewrite to fit within its line budget. Strategies in priority order:
   a. MERGE: entries covering the same root cause → one entry with higher hit counter and newest date
   b. GRADUATE: entries at (3x)+ → rewrite as declarative rule (no date/counter) in the graduation target file, remove from source. Skip if graduation target is 'none'
   c. PRUNE: remove lowest-value (1x) entries, oldest first. Entries >14 days old with (1x) are prime candidates
   d. CONSOLIDATE: (2x) entries >60 days old — merge with similar if possible
3. Write the result back to the same path

NEVER prune:
- !! pinned entries (regardless of age or counter)
- (3x)+ entries (graduation candidates — graduate them instead of deleting)

Format (preserve exactly):
- Regular: - [YYYY-MM-DD] (Nx) description
- Pinned: - [YYYY-MM-DD] (Nx) !! description
- Graduated rules: - description (declarative, no date/counter)
- Codebase sections: ## headers with - entries

Priority when cutting: !! pinned > (3x)+ > (2x) > (1x). Same counter → keep newer. Same age → keep data-loss/security/deploy entries over routine patterns.

Today's date: $(date +%Y-%m-%d)"

    T2_LOG="$LOG_DIR/consolidation-$(date +%s).log"
    echo "$(date): Spawning Tier 2 haiku for ${#OVER_BUDGET[@]} file(s)" >> "$DEBUG_LOG"

    claude -p "$T2_PROMPT" \
      --allowedTools "Read,Write,Edit,Glob" \
      --model haiku \
      < /dev/null > "$T2_LOG" 2>&1

    echo "$(date): Tier 2 consolidation complete" >> "$DEBUG_LOG"
  fi

  # Clean up old log files (keep last 10 each)
  ls -t "$LOG_DIR"/session-learnings-*.log 2>/dev/null | tail -n +11 | xargs rm -f 2>/dev/null
  ls -t "$LOG_DIR"/consolidation-*.log 2>/dev/null | tail -n +11 | xargs rm -f 2>/dev/null
  # Rotate debug log if over 100 lines
  if [ "$(wc -l < "$DEBUG_LOG" 2>/dev/null)" -gt 100 ]; then
    tail -50 "$DEBUG_LOG" > "$DEBUG_LOG.tmp" && mv "$DEBUG_LOG.tmp" "$DEBUG_LOG"
  fi
) </dev/null >/dev/null 2>&1 &
disown

exit 0
