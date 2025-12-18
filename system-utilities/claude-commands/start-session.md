# Start Session

Begin a new work session by reviewing what was done last and what's coming next.

## Task

Help the user (and Claude/Codex/Gemini) get back on track at the start of a new session.

### Step 1: Locate Session Notes

Check for session notes in order of priority:
1. **Project-specific:** `.session-notes.md` in current directory
2. **Global:** `~/infrastructure/SESSION-NOTES.md` for cross-project work
3. **None found:** This is the first session - start fresh

**If no session notes found:**
- Display brief disclaimer: "📝 No session notes found. This appears to be the first session in this project. Starting fresh!"
- Skip to Step 3 (Check Repository Status)
- Offer to create session notes file for future sessions

### Step 2: Read and Parse Session Notes

If session notes exist, read the file and extract:
- **Last Session Date:** When was the last session?
- **What Was Done:** Accomplishments from last session
- **Current Status:** Where things were left off
- **Pending Tasks:** What still needs to be done
- **Next Steps:** What should happen next
- **Blockers:** Any issues or dependencies

### Step 3: Check Repository Status

Run quick repo check:
- Are there any uncommitted changes since last session?
- Any new updates pulled from remote?
- Any merge conflicts or issues?

### Step 4: Present Summary

Display a clear, concise summary:

```
📅 Last Session: [Date/Time]
✅ Recent Accomplishments:
   - [Item 1]
   - [Item 2]

📍 Current Status:
   [Brief status description]

⏳ Pending Tasks:
   [ ] Task 1
   [ ] Task 2
   [ ] Task 3

🎯 Next Steps:
   - [Recommended next action]

⚠️  Blockers/Notes:
   - [Any issues to be aware of]

📊 Repository Status:
   - X repos clean
   - Y repos with changes
```

### Step 5: Offer Guidance

Based on pending tasks and next steps:
- Suggest what to work on first
- Ask if priorities have changed
- Offer to continue where left off or pivot to something new

### Step 6: Update Session Notes

Add new entry marking session start:
```markdown
### Session: [Date/Time]
**Status:** Started
**Focus:** [What user wants to work on]
```

## Session Notes Format

Session notes should follow this structure:

```markdown
# Session Notes - [Project Name or "General"]

## Current Status
[High-level overview of where things stand]

## Pending Tasks
- [ ] Task 1
- [ ] Task 2
- [x] Completed task

## Next Steps
1. [Priority 1]
2. [Priority 2]

## Blockers/Dependencies
- [Any blockers]

## Session Log

### Session: 2024-12-18 15:30
**Accomplishments:**
- Created repository management commands
- Set up session tracking system

**Next:**
- Test the new commands
- Commit changes

---

### Session: 2024-12-17 14:00
**Accomplishments:**
- Reorganized home directory
- Created dotfiles repo

**Next:**
- Set up slash commands
```

## When to Use

Run this command:
- At the start of every work session
- When returning to a project after time away
- After pulling latest changes from remote
- When you need a reminder of where you left off

## Notes

- Session notes are git-ignored by default (in .gitignore)
- Each project can have its own session notes
- Global session notes track cross-project work
- Commands will create session notes file if it doesn't exist
