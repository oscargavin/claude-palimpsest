#!/bin/bash
# TaskCompleted hook: verify tests pass before task completion
# Auto-detects test runner from project config files

INPUT=$(cat)

TASK_SUBJECT=$(echo "$INPUT" | jq -r '.task_subject // empty')
TASK_DESC=$(echo "$INPUT" | jq -r '.task_description // empty')
CWD=$(echo "$INPUT" | jq -r '.cwd // empty')

[ -z "$CWD" ] && exit 0

# --- Find project root ---
source "$HOME/.claude/hooks/lib-project-root.sh"
find_project_root "$CWD"

[ -z "$PROJECT_ROOT" ] && exit 0

# Allow explicit bypass via [skip-tests] in task subject/description
COMBINED="$TASK_SUBJECT $TASK_DESC"
echo "$COMBINED" | grep -qiF "[skip-tests]" && exit 0

# --- Auto-detect test runner ---
TEST_CMD=""

if [ -f "$PROJECT_ROOT/vitest.config.ts" ] || [ -f "$PROJECT_ROOT/vitest.config.js" ] || [ -f "$PROJECT_ROOT/vitest.config.mts" ]; then
  TEST_CMD="npx vitest run"
elif [ -f "$PROJECT_ROOT/jest.config.ts" ] || [ -f "$PROJECT_ROOT/jest.config.js" ] || [ -f "$PROJECT_ROOT/jest.config.cjs" ]; then
  TEST_CMD="npx jest --passWithNoTests"
elif [ -f "$PROJECT_ROOT/pytest.ini" ] || [ -f "$PROJECT_ROOT/pyproject.toml" ] && grep -q '\[tool\.pytest' "$PROJECT_ROOT/pyproject.toml" 2>/dev/null; then
  TEST_CMD="python -m pytest"
elif [ -f "$PROJECT_ROOT/Cargo.toml" ]; then
  TEST_CMD="cargo test"
elif [ -f "$PROJECT_ROOT/package.json" ] && grep -q '"test"' "$PROJECT_ROOT/package.json" 2>/dev/null; then
  TEST_CMD="npm test"
fi

# No test runner found — skip silently
[ -z "$TEST_CMD" ] && exit 0

# Run tests
TEST_OUTPUT=$(cd "$PROJECT_ROOT" && $TEST_CMD 2>&1)
[ $? -eq 0 ] && exit 0

# Tests failed — write to friction log so session-learnings captures it
SCRATCH="$HOME/.claude/scratch"
mkdir -p "$SCRATCH"
FAIL_SUMMARY=$(echo "$TEST_OUTPUT" | tail -5 | head -c 200)
printf '%s\t%s\t%s\n' "$(date +%H:%M:%S)" "task-verify: $TEST_CMD ($TASK_SUBJECT)" "$FAIL_SUMMARY" > "$SCRATCH/friction-open-bash"

# Block completion
cat >&2 << EOF
Tests failing in $PROJECT_NAME. Fix before completing: $TASK_SUBJECT

$(echo "$TEST_OUTPUT" | tail -30)
EOF
exit 2
