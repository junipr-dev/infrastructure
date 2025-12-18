# Check All Repositories

Automatically detect and check ALL git repositories for issues.

## Task

Run the repository status check script: `/home/jesse/infrastructure/system-utilities/scripts/check-all-repos.sh`

**Auto-detects repositories in:**
- `~/portfolio/`
- `~/work/`
- `~/school/`
- `~/junipr/`
- `~/projects/`
- `~/infrastructure/`
- `~/dotfiles/`
- `~/media-server/`

**Checks performed (per repository):**
1. ❗ Merge conflicts (unresolved conflicts)
2. ⚠️  Detached HEAD state
3. ⚠️  Missing remote configuration
4. 🔴 Uncommitted changes (modified/untracked files)
5. 🔴 Unpushed commits (local commits not pushed to remote)
6. ⚠️  Behind remote (need to pull updates)

**Output includes:**
- Total repositories found and checked
- Clean count (repos with no issues)
- Dirty count (repos needing commits/pushes)
- Warning count (repos with configuration issues)
- Detailed list of all issues found

**After running:**
- If issues found, ask user if they want to address them now
- Offer to run `/wrap-session` if multiple repos have changes
