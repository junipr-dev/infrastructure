# End Day

Complete end-of-day workflow: check all repos, commit changes, push everything, and shut down cleanly.

## Task

This command combines `/check-repos` and `/end-session` into a single workflow for ending your work day.

### Step 1: Repository Health Check
Run `/check-repos` to scan all repositories and identify:
- Uncommitted changes
- Unpushed commits
- Repos behind remote
- Configuration issues (detached HEAD, missing remotes, conflicts)

### Step 2: Review Findings
- Show summary of all repos with issues
- Confirm with user before proceeding with commits
- If user declines, exit gracefully

### Step 3: Pull Updates
For repos behind remote:
- Pull latest changes from remote
- Check for and handle any merge conflicts
- Ensure sync with other machines (desktop/laptop)

### Step 4: Commit All Changes
For each repo with uncommitted changes:
- Show summary of what changed in this repo
- Generate descriptive commit message: `End of day: [description]`
- Include agent attribution (Claude Code, Codex, or Gemini)
- Commit changes

### Step 5: Push Everything
- Push all repos with new commits
- Verify each push succeeded
- Report any failures

### Step 6: Sync Agent Context Files (If Present)

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

### Step 7: Update Session Notes
- Check for `.session-notes.md` (project) or `~/infrastructure/SESSION-NOTES.md` (global)
- Create if doesn't exist
- Add session log entry with:
  - What was accomplished
  - Commits made
  - Pending tasks
  - Next steps for next session
  - Any blockers or notes

### Step 8: Final Status
- Re-run check to confirm all repos are clean
- Show summary:
  - Total repos processed
  - Commits created
  - Repos pushed
  - Any remaining issues
  - Session notes updated
  - Agent context files synced
- Confirm ready for next session

### Step 9: Goodbye Message
Display summary message:
```
✅ All repositories clean and synced
📊 Session stats: X repos checked, Y commits made, Z repos pushed
📝 Session notes updated
🤖 Agent context files synced
🌙 Ready for next session. Use /start-session to resume!
```

## When to Use

Run this at the end of your work day:
- Before shutting down your computer
- Before switching to your other machine (desktop ↔ laptop)
- After a long coding session
- Anytime you want peace of mind that everything is backed up

## Safety

- Always confirms before committing
- Never force pushes
- Reports any errors clearly
- Won't commit if merge conflicts exist
- Won't proceed if critical issues detected
- Automatically syncs all agent context files
