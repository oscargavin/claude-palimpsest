#!/bin/bash
# Shared project root detection — sourced by hooks to prevent drift
# Sets: PROJECT_ROOT, PROJECT_NAME (empty if no project found)
# Expects: CWD to be set by caller

find_project_root() {
  PROJECT_ROOT=""
  PROJECT_NAME=""
  local DIR="${1:-$CWD}"
  while [ "$DIR" != "/" ] && [ "$DIR" != "$HOME" ]; do
    if [ -d "$DIR/.git" ] || [ -f "$DIR/package.json" ] || [ -f "$DIR/CLAUDE.md" ]; then
      PROJECT_ROOT="$DIR"
      PROJECT_NAME=$(basename "$DIR")
      return 0
    fi
    DIR=$(dirname "$DIR")
  done
  return 1
}
