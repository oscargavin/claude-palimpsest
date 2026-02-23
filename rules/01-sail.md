# SAIL Phase Constraints

## Scout
- Explore subagent for broad searches; Glob/Grep for targeted lookups
- Check `rules/codebase.md` before scouting — it may already have the answer
- Build understanding in layers: structure → patterns → boundaries

## Architect
- Search skills + Context7 before designing — don't reinvent what exists
- Plan structure: Context (why) → Approach (how) → Files (what) → Verification (proof)
- Reuse existing code before proposing new. If 5+ files, find simpler approach
- ExitPlanMode → "clear context and auto-accept edits" → create tasks in fresh session
- Known bug (#23754): if clear fails silently, use `/clear` as fallback

## Implement
- **Feature**: types first → implement → test → verify types
- **Bug fix**: reproduce → fix → regression test
- **Refactor**: characterization tests first, incremental changes, tests pass after each file
- Verify after EVERY file change. If tests break: fix immediately
- 3+ failed attempts at same thing → STOP, re-architect
- After 5+ file changes, run `/code-simplifier` before launch

## Launch
- Never commit without: typecheck passes, tests pass, git diff reviewed
- Never commit .env, credentials, large binaries, node_modules
- Commit messages describe WHY, not WHAT
