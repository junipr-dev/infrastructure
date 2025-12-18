#!/bin/bash
# Check all git repositories for uncommitted changes, unpushed commits, and other issues

# Auto-detect all git repos in known directories
SEARCH_PATHS=(
    "$HOME/portfolio"
    "$HOME/work"
    "$HOME/school"
    "$HOME/junipr"
    "$HOME/projects"
    "$HOME/infrastructure"
    "$HOME/dotfiles"
    "$HOME/media-server"
)

# Find all git repos (max depth 3 to avoid going too deep)
REPOS=()
for search_path in "${SEARCH_PATHS[@]}"; do
    if [ -d "$search_path" ]; then
        while IFS= read -r -d '' git_dir; do
            repo_path=$(dirname "$git_dir")
            REPOS+=("$repo_path")
        done < <(find "$search_path" -maxdepth 3 -type d -name ".git" -print0 2>/dev/null)
    fi
done

# Remove duplicates and sort
IFS=$'\n' REPOS=($(sort -u <<<"${REPOS[*]}"))
unset IFS

if [ ${#REPOS[@]} -eq 0 ]; then
    echo "⚠️  No git repositories found in search paths"
    exit 1
fi

clean_count=0
dirty_count=0
warning_count=0
dirty_repos=()

echo "=== Checking ${#REPOS[@]} repositories ==="
echo ""

for repo in "${REPOS[@]}"; do
    if [ ! -d "$repo/.git" ]; then
        continue
    fi

    cd "$repo" || continue

    # Get repo name relative to home
    repo_name="${repo/#$HOME\//\~\/}"

    # Check for uncommitted changes
    uncommitted=$(git status --porcelain)

    # Check for unpushed commits (fetch first)
    git fetch --quiet 2>/dev/null
    unpushed=$(git log @{u}.. --oneline 2>/dev/null)

    # Check if behind remote
    behind=$(git log ..@{u} --oneline 2>/dev/null)

    # Check for detached HEAD
    detached=$(git symbolic-ref -q HEAD &>/dev/null || echo "detached")

    # Check if remote exists
    has_remote=$(git remote -v | grep -q "origin" && echo "yes" || echo "no")

    # Check for merge conflicts
    conflicts=$(git diff --name-only --diff-filter=U 2>/dev/null)

    # Determine status
    has_issues=false

    if [[ -n "$conflicts" ]]; then
        echo "🔴 $repo_name - MERGE CONFLICTS"
        echo "   Files with conflicts:"
        echo "$conflicts" | sed 's/^/     /'
        has_issues=true
        ((dirty_count++))
    fi

    if [[ "$detached" == "detached" ]]; then
        echo "⚠️  $repo_name - DETACHED HEAD"
        head_commit=$(git rev-parse --short HEAD)
        echo "   Currently at: $head_commit"
        has_issues=true
        ((warning_count++))
    fi

    if [[ "$has_remote" == "no" ]]; then
        echo "⚠️  $repo_name - NO REMOTE CONFIGURED"
        has_issues=true
        ((warning_count++))
    fi

    if [[ -n "$uncommitted" ]]; then
        if [[ "$has_issues" == "false" ]]; then
            echo "🔴 $repo_name"
            ((dirty_count++))
            has_issues=true
        fi
        echo "   Uncommitted changes:"
        echo "$uncommitted" | sed 's/^/     /'
    fi

    if [[ -n "$unpushed" ]]; then
        if [[ "$has_issues" == "false" ]]; then
            echo "🔴 $repo_name"
            ((dirty_count++))
            has_issues=true
        fi
        commit_count=$(echo "$unpushed" | wc -l)
        echo "   Unpushed commits: $commit_count"
        echo "$unpushed" | sed 's/^/     /' | head -5
    fi

    if [[ -n "$behind" ]]; then
        if [[ "$has_issues" == "false" ]]; then
            echo "⚠️  $repo_name - Behind remote"
            ((warning_count++))
            has_issues=true
        fi
        commit_count=$(echo "$behind" | wc -l)
        echo "   Behind remote: $commit_count commits"
    fi

    if [[ "$has_issues" == "true" ]]; then
        dirty_repos+=("$repo")
        echo ""
    else
        ((clean_count++))
    fi
done

echo "=== Summary ==="
echo "✅ Clean repositories: $clean_count"
echo "🔴 Repositories needing attention: $dirty_count"
echo "⚠️  Repositories with warnings: $warning_count"
echo ""
echo "Total repositories checked: ${#REPOS[@]}"

if [ $dirty_count -gt 0 ] || [ $warning_count -gt 0 ]; then
    exit 1
else
    exit 0
fi
