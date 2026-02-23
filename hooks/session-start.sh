#!/bin/bash
# SessionStart hook: detect project frameworks, output knowledge manifest
# Outputs relevant knowledge files as context for Claude Code
# Performance target: <100ms (filesystem checks only, no network)

INPUT=$(cat)
CWD=$(echo "$INPUT" | jq -r '.cwd // empty')
[ -z "$CWD" ] && CWD="$PWD"

# Clear friction scratch for new session
mkdir -p "$HOME/.claude/scratch"
rm -f "$HOME/.claude/scratch"/friction-*

KNOWLEDGE_DIR="$HOME/.claude/knowledge/fw"
RELEVANT=()
AVAILABLE=()

# --- Find project root ---
source "$HOME/.claude/hooks/lib-project-root.sh"
find_project_root "$CWD"

# --- Helper: add to relevant if file exists ---
add_relevant() {
  local name="$1"
  local path="$KNOWLEDGE_DIR/$name.md"
  if [ -f "$path" ]; then
    for r in "${RELEVANT[@]}"; do [ "$r" = "$name" ] && return; done
    RELEVANT+=("$name")
  fi
}

# --- Always relevant ---
add_relevant "security"
add_relevant "git"

# --- Detect from package.json ---
if [ -n "$PROJECT_ROOT" ] && [ -f "$PROJECT_ROOT/package.json" ]; then
  DEPS=$(cat "$PROJECT_ROOT/package.json" 2>/dev/null)

  echo "$DEPS" | grep -q '"next"' && add_relevant "nextjs"
  echo "$DEPS" | grep -q '"next"' && [ -f "$PROJECT_ROOT/app/sitemap.ts" -o -f "$PROJECT_ROOT/src/app/sitemap.ts" ] && add_relevant "seo"
  echo "$DEPS" | grep -qE '"(motion|framer-motion)"' && add_relevant "motion"
  echo "$DEPS" | grep -q '"fastify"' && add_relevant "fastify"
  echo "$DEPS" | grep -q '"playwright"' && add_relevant "playwright"
  echo "$DEPS" | grep -q '"twilio"' && add_relevant "twilio"
  echo "$DEPS" | grep -q '"recharts"' && add_relevant "seo"
fi

# --- Detect Python project ---
if [ -n "$PROJECT_ROOT" ]; then
  PY_DEPS=""
  [ -f "$PROJECT_ROOT/pyproject.toml" ] && PY_DEPS=$(cat "$PROJECT_ROOT/pyproject.toml" 2>/dev/null)
  [ -f "$PROJECT_ROOT/requirements.txt" ] && PY_DEPS="$PY_DEPS$(cat "$PROJECT_ROOT/requirements.txt" 2>/dev/null)"

  if [ -n "$PY_DEPS" ]; then
    add_relevant "python"
    add_relevant "uv"
    echo "$PY_DEPS" | grep -qiE '(starlette|fastapi)' && add_relevant "starlette"
    echo "$PY_DEPS" | grep -qi 'textual' && add_relevant "textual"
    echo "$PY_DEPS" | grep -qi 'rumps' && add_relevant "rumps"
    echo "$PY_DEPS" | grep -qi 'openwakeword' && add_relevant "openwakeword"
  fi
fi

# --- Detect Swift/macOS ---
if [ -n "$PROJECT_ROOT" ]; then
  if [ -f "$PROJECT_ROOT/Package.swift" ] || ls "$PROJECT_ROOT"/*.xcodeproj 1>/dev/null 2>&1; then
    add_relevant "swiftui"
    add_relevant "macos"
  fi
fi

# --- Detect Docker ---
if [ -n "$PROJECT_ROOT" ]; then
  if [ -f "$PROJECT_ROOT/Dockerfile" ] || [ -f "$PROJECT_ROOT/docker-compose.yml" ] || [ -f "$PROJECT_ROOT/docker-compose.yaml" ]; then
    add_relevant "docker"
  fi
fi

# --- Detect deploy/infra ---
if [ -n "$PROJECT_ROOT" ]; then
  if [ -f "$PROJECT_ROOT/deploy.sh" ] || [ -f "$PROJECT_ROOT/ecosystem.config.cjs" ] || [ -f "$PROJECT_ROOT/ecosystem.config.js" ]; then
    add_relevant "deploy-daemon"
    add_relevant "infrastructure"
  fi
fi

# --- Detect Rust ---
if [ -n "$PROJECT_ROOT" ] && [ -f "$PROJECT_ROOT/Cargo.toml" ]; then
  add_relevant "rust"
fi

# --- Build available list (everything not already relevant) ---
if [ -d "$KNOWLEDGE_DIR" ]; then
  for f in "$KNOWLEDGE_DIR"/*.md; do
    [ -f "$f" ] || continue
    name=$(basename "$f" .md)
    found=false
    for r in "${RELEVANT[@]}"; do [ "$r" = "$name" ] && found=true && break; done
    $found || AVAILABLE+=("$name")
  done
fi

# --- Output manifest ---
OUTPUT=""

if [ -z "$PROJECT_ROOT" ]; then
  OUTPUT+="No project root detected (no .git, package.json, or CLAUDE.md found walking up from $CWD).\n"
  OUTPUT+="Framework knowledge available on request — read from ~/.claude/knowledge/fw/{name}.md\n\n"
fi

if [ ${#RELEVANT[@]} -gt 0 ]; then
  PATHS=""
  for r in "${RELEVANT[@]}"; do
    PATHS+="  - ~/.claude/knowledge/fw/$r.md\n"
  done
  OUTPUT+="Relevant framework knowledge detected for this project:\n$PATHS\n"
  OUTPUT+="Read these files when working on related tasks.\n\n"
fi

if [ ${#AVAILABLE[@]} -gt 0 ]; then
  NAMES=$(printf ", %s" "${AVAILABLE[@]}")
  NAMES="${NAMES:2}"
  OUTPUT+="Other knowledge available on request: $NAMES\n"
  OUTPUT+="Path: ~/.claude/knowledge/fw/{name}.md\n\n"
fi

# --- Dynamic reference docs listing ---
REF_DIR="$HOME/.claude/knowledge/ref"
if [ -d "$REF_DIR" ]; then
  REF_FILES=()
  for f in "$REF_DIR"/*.md; do
    [ -f "$f" ] || continue
    REF_FILES+=("$(basename "$f")")
  done
  if [ ${#REF_FILES[@]} -gt 0 ]; then
    REF_NAMES=$(printf ", %s" "${REF_FILES[@]}")
    REF_NAMES="${REF_NAMES:2}"
    OUTPUT+="Reference docs: ~/.claude/knowledge/ref/ ($REF_NAMES)\n"
  fi
fi

# --- Health condition checks ---
HEALTH=""

# Global learnings entry count
GLOBAL_LEARNINGS="$HOME/.claude/rules/learnings.md"
if [ -f "$GLOBAL_LEARNINGS" ]; then
  LC=$(grep -c '^\- \[' "$GLOBAL_LEARNINGS" 2>/dev/null || echo 0)
  [ "$LC" -gt 30 ] && HEALTH+="  - Global learnings.md: $LC entries (budget 30)\n"
fi

# Project learnings entry count
if [ -n "$PROJECT_ROOT" ] && [ -f "$PROJECT_ROOT/.claude/rules/learnings.md" ]; then
  LC=$(grep -c '^\- \[' "$PROJECT_ROOT/.claude/rules/learnings.md" 2>/dev/null || echo 0)
  [ "$LC" -gt 30 ] && HEALTH+="  - Project learnings.md: $LC entries (budget 30)\n"
fi

# fw files over budget
OVER=0
for f in "$KNOWLEDGE_DIR"/*.md; do
  [ -f "$f" ] || continue
  LC=$(wc -l < "$f" 2>/dev/null | tr -d ' ')
  [ "${LC:-0}" -gt 25 ] && OVER=$((OVER + 1))
done
[ "$OVER" -gt 0 ] && HEALTH+="  - $OVER fw knowledge files over 25-line budget\n"

# Handoff staleness
if [ -n "$PROJECT_ROOT" ] && [ -f "$PROJECT_ROOT/.claude/rules/handoff.md" ]; then
  # Cross-platform stat: GNU stat vs BSD stat
  if stat --version >/dev/null 2>&1; then
    MOD=$(stat -c %Y "$PROJECT_ROOT/.claude/rules/handoff.md" 2>/dev/null || echo 0)
  else
    MOD=$(stat -f %m "$PROJECT_ROOT/.claude/rules/handoff.md" 2>/dev/null || echo 0)
  fi
  AGE=$(( ($(date +%s) - MOD) / 86400 ))
  [ "$AGE" -gt 7 ] && HEALTH+="  - Project handoff.md is ${AGE}d old\n"
fi

if [ -n "$HEALTH" ]; then
  OUTPUT+="\n\nLearning system health:\n$HEALTH"
fi

printf '%b' "$OUTPUT"
