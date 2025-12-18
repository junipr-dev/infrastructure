# End Session

Complete end-of-session cleanup for the current project. Ensures all work is committed, pushed, and documented.

## Task

Perform the following steps to wrap up the current work session:

### 1. Check Repository Status
- Run `/check-repos` to identify uncommitted changes
- Show what will be committed
- Auto-detect ALL repositories (not just hardcoded list)

### 2. Pull Updates First
- For each repo that's behind remote, pull updates
- Handle merge conflicts if they occur
- Ensures we're syncing latest changes from other machines

### 3. Commit Changes (if any)
- For each repo with changes, show a summary of what changed
- Create descriptive commit message based on changes
- Follow format: `Session end: [brief description of changes]`
- Commit with agent attribution (Claude Code, Codex, or Gemini)

### 4. Push All Repos
- Push all committed changes to remote
- Verify push succeeded for each repo
- Confirm sync with remote is complete

### 5. Sync Agent Context Files (If Present)

**Check for project-level context files in current directory:**
- Look for `CLAUDE.md` in current directory
- If found, sync to `AGENTS.md` and `GEMINI.md`

**Synchronization process:**
1. Read `CLAUDE.md` content (skip first 2 header lines)
2. Create/update `AGENTS.md`:
   - Header: `# Project Agent Instructions (Codex)`
   - Description: `This file provides project-specific guidance to Codex.`
   - Body: Content from CLAUDE.md (line 3 onwards)
3. Create/update `GEMINI.md`:
   - Header: `# Project Agent Instructions (Gemini)`
   - Description: `This file provides project-specific guidance to Gemini.`
   - Body: Content from CLAUDE.md (line 3 onwards)

**Report what was synced:**
- If synced: "✅ Synced CLAUDE.md → AGENTS.md, GEMINI.md"
- If no CLAUDE.md: "No project context files to sync"

### 6. Update Session Notes

**Check for session notes file:**
1. **Project-specific:** `.session-notes.md` in current directory
2. **Global:** `~/infrastructure/SESSION-NOTES.md` for cross-project work
3. **Create if missing:** Use template format (see `/start-session` command)

**Add new session log entry:**
```markdown
### Session: [Date/Time]
**Accomplishments:**
- [What was done this session - be specific]
- [List all major changes]

**Commits Made:**
- [Repo 1]: [Commit message]
- [Repo 2]: [Commit message]

**Pending Tasks:**
- [ ] [Tasks that still need to be done]
- [ ] [Blockers or dependencies]

**Next Steps:**
1. [What should happen in the next session]
2. [Priority order]

**Notes:**
- [Any important context for next session]
```

### 7. Final Status Report
- Confirm all repos are clean and pushed
- Summarize what was committed
- List any manual follow-up items needed
- Confirm session notes were updated

## When to Use

Run this command when:
- Finishing a work session
- About to switch to a different machine
- Before shutting down for the day
- After an agent has made significant changes

## Notes

- This command is safe to run anytime - if nothing needs committing, it just verifies clean state
- Does NOT create empty commits
- Does NOT commit files that should be ignored (respects .gitignore)
- Automatically syncs agent context files (CLAUDE.md, AGENTS.md, GEMINI.md)
