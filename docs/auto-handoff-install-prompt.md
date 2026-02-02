# Auto-Handoff System Installation Prompt

> **Usage:** Copy this entire document and paste it to Claude Code on a fresh system.
> Claude will set up the complete auto-handoff system for walk-away automation.

---

## Instructions for Claude

You are setting up an auto-handoff system that allows you to work autonomously for extended periods without losing context when the conversation gets too large. This system:

1. Monitors context size after every tool call
2. When context approaches limits, saves state to a handoff file
3. Signals a wrapper script to restart Claude
4. New Claude session reads handoff and continues seamlessly

### Step 1: Check Prerequisites

First, verify the system meets requirements:

```bash
# Check Node.js version (need 18+)
node --version

# Check Claude Code is installed
which claude

# Check home directory
echo $HOME
```

If Node.js < 18, install via nvm:
```bash
curl -o- https://raw.githubusercontent.com/nvm-sh/nvm/v0.39.0/install.sh | bash
source ~/.bashrc
nvm install 20
nvm use 20
```

### Step 2: Install memory-keeper MCP

This MCP provides persistent storage for context across sessions:

```bash
claude mcp add memory-keeper -- npx mcp-memory-keeper
```

Verify it's connected:
```bash
claude mcp list
# Should show: memory-keeper: npx mcp-memory-keeper - ✓ Connected
```

### Step 3: Create Directory Structure

```bash
mkdir -p ~/.claude/hooks/lib
mkdir -p ~/.claude/handoff
mkdir -p ~/.claude/archives
mkdir -p ~/infrastructure/bin
```

### Step 4: Create the Context Monitor Hook

Create `~/.claude/hooks/context-monitor.sh`:

```bash
#!/bin/bash
# Context Monitor - Check usage and warn when approaching limits

SESSION_DIR="$HOME/.claude/projects"
STATUS_FILE="$HOME/.claude/.context-status"
TEST_MODE_FILE="$HOME/.claude/.test-mode"

# Find main session transcript (not subagent files)
CURRENT_TRANSCRIPT=$(find "$SESSION_DIR" -maxdepth 2 -name "*.jsonl" -mmin -60 -type f 2>/dev/null | \
    grep -v "/subagents/" | \
    xargs -r ls -t 2>/dev/null | \
    head -1)

[ -z "$CURRENT_TRANSCRIPT" ] && exit 0
[ ! -f "$CURRENT_TRANSCRIPT" ] && exit 0

SIZE_BYTES=$(stat -c %s "$CURRENT_TRANSCRIPT" 2>/dev/null)
[ -z "$SIZE_BYTES" ] && exit 0

SIZE_KB=$((SIZE_BYTES / 1024))

# Display format
if [ "$SIZE_BYTES" -ge 1048576 ]; then
    SIZE_DISPLAY=$(awk "BEGIN {printf \"%.1fMB\", $SIZE_BYTES / 1048576}")
else
    SIZE_DISPLAY="${SIZE_KB}KB"
fi

# Thresholds
if [ -f "$TEST_MODE_FILE" ]; then
    EARLY_WARN_KB=5
    WARN_KB=10
    CRITICAL_KB=15
else
    # Based on observed compact trigger at ~1.4MB - adjust for your system
    EARLY_WARN_KB=800
    WARN_KB=1024
    CRITICAL_KB=1200
fi

if [ "$SIZE_KB" -ge "$CRITICAL_KB" ]; then
    echo "CRITICAL:${SIZE_DISPLAY}" > "$STATUS_FILE"
elif [ "$SIZE_KB" -ge "$WARN_KB" ]; then
    echo "WARN:${SIZE_DISPLAY}" > "$STATUS_FILE"
elif [ "$SIZE_KB" -ge "$EARLY_WARN_KB" ]; then
    echo "EARLY_WARN:${SIZE_DISPLAY}" > "$STATUS_FILE"
else
    echo "OK:${SIZE_DISPLAY}" > "$STATUS_FILE"
fi

exit 0
```

Make it executable:
```bash
chmod +x ~/.claude/hooks/context-monitor.sh
```

### Step 5: Create Channel Detection Utility

Create `~/.claude/hooks/lib/get-channel.sh`:

```bash
#!/bin/bash
# Channel detection utility - shared by all hooks

REGISTRY_FILE="$HOME/.claude/channel-registry.json"

get_channel() {
    local cwd="${1:-$PWD}"

    if [ ! -f "$REGISTRY_FILE" ]; then
        echo "global"
        return
    fi

    local best_match=""
    local best_channel="global"

    while IFS=: read -r path channel; do
        path=$(echo "$path" | tr -d ' "' | sed 's/,$//')
        channel=$(echo "$channel" | tr -d ' "' | sed 's/,$//')

        if [[ "$cwd" == "$path"* ]]; then
            if [ ${#path} -gt ${#best_match} ]; then
                best_match="$path"
                best_channel="$channel"
            fi
        fi
    done < <(grep -E '^\s*"/' "$REGISTRY_FILE" | sed 's/^\s*//')

    echo "$best_channel"
}

# If sourced, function is available. If run directly, output channel.
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    get_channel "$@"
fi
```

Make it executable:
```bash
chmod +x ~/.claude/hooks/lib/get-channel.sh
```

### Step 6: Create Session Start Hook

Create `~/.claude/hooks/session-start-from-handoff.sh`:

```bash
#!/bin/bash
# Session Start Hook - Load handoff when explicitly requested
# Supports multiple concurrent instances via PID-based handoffs and locks

HANDOFF_DIR="$HOME/.claude/handoff"
LOAD_HANDOFF_FLAG="$HOME/.claude/.load-handoff"

mkdir -p "$HANDOFF_DIR"

# Check if we should load handoffs (flag set by wrapper on auto-restart)
SHOULD_LOAD_HANDOFF=false
if [ -f "$LOAD_HANDOFF_FLAG" ]; then
    SHOULD_LOAD_HANDOFF=true
    rm -f "$LOAD_HANDOFF_FLAG"
fi

source "$HOME/.claude/hooks/lib/get-channel.sh"

is_pid_alive() {
    local pid="$1"
    [ -n "$pid" ] && kill -0 "$pid" 2>/dev/null
}

CHANNEL=$(get_channel)
LOCK_DIR="$HANDOFF_DIR/${CHANNEL}.lock.d"
LOCK_FILE="$LOCK_DIR/pid"
MY_PID="$PPID"

# Atomic lock acquisition using mkdir
acquire_lock() {
    if mkdir "$LOCK_DIR" 2>/dev/null; then
        echo "${MY_PID}:$(date +%s)" > "$LOCK_FILE"
        return 0
    fi
    if [ -f "$LOCK_FILE" ]; then
        LOCK_PID=$(cat "$LOCK_FILE" 2>/dev/null | cut -d: -f1)
        if is_pid_alive "$LOCK_PID"; then
            return 1
        fi
    fi
    rm -rf "$LOCK_DIR"
    if mkdir "$LOCK_DIR" 2>/dev/null; then
        echo "${MY_PID}:$(date +%s)" > "$LOCK_FILE"
        return 0
    fi
    return 1
}

PARALLEL_SESSION=false
if ! acquire_lock; then
    PARALLEL_SESSION=true
    LOCK_PID=$(cat "$LOCK_FILE" 2>/dev/null | cut -d: -f1)
fi

find_handoff() {
    local best_file=""
    local best_time=0
    for f in "$HANDOFF_DIR/${CHANNEL}"-*.md "$HANDOFF_DIR/${CHANNEL}.md"; do
        [ -f "$f" ] || continue
        local age=$(( $(date +%s) - $(stat -c %Y "$f" 2>/dev/null || echo 0) ))
        [ "$age" -gt 7200 ] && continue
        local fname=$(basename "$f")
        local file_pid=$(echo "$fname" | sed -n "s/${CHANNEL}-\([0-9]*\)\.md/\1/p")
        if [ -n "$file_pid" ] && is_pid_alive "$file_pid"; then
            continue
        fi
        local mtime=$(stat -c %Y "$f" 2>/dev/null || echo 0)
        if [ "$mtime" -gt "$best_time" ]; then
            best_time="$mtime"
            best_file="$f"
        fi
    done
    echo "$best_file"
}

if [ "$PARALLEL_SESSION" = true ]; then
    cat << EOF
{
    "hookSpecificOutput": {
        "hookEventName": "SessionStart",
        "additionalContext": "=== PARALLEL SESSION (Channel: $CHANNEL) ===\\n\\nAnother Claude instance is active (PID: $LOCK_PID).\\nStarting fresh to avoid conflicts."
    }
}
EOF
    exit 0
fi

HANDOFF_FILE=""
if [ "$SHOULD_LOAD_HANDOFF" = true ]; then
    HANDOFF_FILE=$(find_handoff)
fi

if [ -n "$HANDOFF_FILE" ] && [ -f "$HANDOFF_FILE" ]; then
    HANDOFF_CONTENT=$(cat "$HANDOFF_FILE" 2>/dev/null) || {
        cat << EOF
{
    "hookSpecificOutput": {
        "hookEventName": "SessionStart",
        "additionalContext": "=== SESSION START (Channel: $CHANNEL) ===\\n\\nHandoff file disappeared. Starting fresh."
    }
}
EOF
        exit 0
    }

    HANDOFF_ID=$(basename "$HANDOFF_FILE" .md)
    PREV_PID=$(echo "$HANDOFF_ID" | sed 's/.*-//')

    # JSON-escape content (python3 with sed fallback)
    if command -v python3 >/dev/null 2>&1; then
        ESCAPED_CONTENT=$(echo "$HANDOFF_CONTENT" | python3 -c 'import json,sys; print(json.dumps(sys.stdin.read())[1:-1])')
    else
        ESCAPED_CONTENT=$(echo "$HANDOFF_CONTENT" | sed 's/\\/\\\\/g; s/"/\\"/g' | tr '\n' '\036' | sed 's/\036/\\n/g')
    fi

    cat << EOF
{
    "hookSpecificOutput": {
        "hookEventName": "SessionStart",
        "additionalContext": "=== HANDOFF LOADED ===\\nChannel: $CHANNEL\\nHandoff ID: $HANDOFF_ID\\nPrevious PID: $PREV_PID\\n\\n$ESCAPED_CONTENT\\n\\n=== END HANDOFF ==="
    }
}
EOF
    rm -f "$HANDOFF_FILE"
    exit 0
fi

# Check for pending handoffs on manual start (notify but don't auto-load)
PENDING_HANDOFFS=""
for f in "$HANDOFF_DIR/${CHANNEL}"-*.md "$HANDOFF_DIR/${CHANNEL}.md"; do
    [ -f "$f" ] || continue
    PENDING_HANDOFFS="$PENDING_HANDOFFS $(basename $f)"
done

if [ -n "$PENDING_HANDOFFS" ]; then
    cat << EOF
{
    "hookSpecificOutput": {
        "hookEventName": "SessionStart",
        "additionalContext": "=== SESSION START (Channel: $CHANNEL) ===\\n\\n⚠️ PENDING HANDOFFS FOUND:$PENDING_HANDOFFS\\nTo load: Read ~/.claude/handoff/{filename}\\n\\nWorking directory: $PWD"
    }
}
EOF
else
    cat << EOF
{
    "hookSpecificOutput": {
        "hookEventName": "SessionStart",
        "additionalContext": "=== SESSION START (Channel: $CHANNEL) ===\\n\\nWorking directory: $PWD"
    }
}
EOF
fi
```

Make it executable:
```bash
chmod +x ~/.claude/hooks/session-start-from-handoff.sh
```

### Step 7: Create the Wrapper Script

Create `~/infrastructure/bin/claude-wrapper`:

```bash
#!/bin/bash
# Claude Auto-Session Wrapper

LOG_FILE="$HOME/.claude/auto-session.log"
RESTART_FILE="$HOME/.claude/.restart-session"
HANDOFF_DIR="$HOME/.claude/handoff"
WRAPPER_PID_FILE="$HOME/.claude/.wrapper-pid"
KILLED_BY_MONITOR="$HOME/.claude/.killed-by-monitor"

log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $*" >> "$LOG_FILE"
}

find_claude() {
    for c in "$HOME/.local/bin/claude" "/usr/local/bin/claude" "/usr/bin/claude"; do
        [ -x "$c" ] && [ ! "$c" -ef "$0" ] && echo "$c" && return
    done
    command -v claude
}

CLAUDE_BIN=$(find_claude)
[ -z "$CLAUDE_BIN" ] && echo "ERROR: Cannot find claude" && exit 1

CLAUDE_DEFAULT_FLAGS="--dangerously-skip-permissions"

source "$HOME/.claude/hooks/lib/get-channel.sh" 2>/dev/null || true

get_current_channel() {
    type get_channel &>/dev/null && get_channel "$1" || echo "global"
}

find_handoff_for_channel() {
    local channel="$1"
    for f in "$HANDOFF_DIR/${channel}"-*.md "$HANDOFF_DIR/${channel}.md"; do
        [ -f "$f" ] || continue
        local age=$(( $(date +%s) - $(stat -c %Y "$f" 2>/dev/null || echo 0) ))
        [ "$age" -gt 7200 ] && continue
        echo "$f"
        return
    done
}

echo $$ > "$WRAPPER_PID_FILE"
MONITOR_PID=""

cleanup() {
    rm -f "$WRAPPER_PID_FILE"
    [ -n "$MONITOR_PID" ] && kill $MONITOR_PID 2>/dev/null
}
trap cleanup EXIT

start_monitor() {
    [ -n "$MONITOR_PID" ] && kill $MONITOR_PID 2>/dev/null
    (
        while true; do
            sleep 0.5
            [ ! -f "$WRAPPER_PID_FILE" ] && exit 0
            if [ -f "$RESTART_FILE" ]; then
                MY_PID=$BASHPID
                CLAUDE_PID=$(pgrep -P "$(cat "$WRAPPER_PID_FILE" 2>/dev/null)" 2>/dev/null | grep -v "^${MY_PID}$" | head -1)
                if [ -n "$CLAUDE_PID" ]; then
                    log "Monitor: Killing Claude PID $CLAUDE_PID"
                    touch "$KILLED_BY_MONITOR"
                    kill -TERM "$CLAUDE_PID" 2>/dev/null
                    sleep 1
                    kill -9 "$CLAUDE_PID" 2>/dev/null
                fi
                exit 0
            fi
        done
    ) &
    MONITOR_PID=$!
}

USER_WANTS_HANDOFF=false
FILTERED_ARGS=()
for arg in "$@"; do
    case "$arg" in
        -h|--handoff) USER_WANTS_HANDOFF=true ;;
        *) FILTERED_ARGS+=("$arg") ;;
    esac
done

RESTART_COUNT=0
MAX_RESTARTS=10
WORKING_DIR="${PWD}"

log "=== Wrapper $$ started in $WORKING_DIR ==="

while true; do
    rm -f "$RESTART_FILE" "$KILLED_BY_MONITOR"
    CHANNEL=$(get_current_channel "$WORKING_DIR")
    log "Channel: $CHANNEL, Restart #$RESTART_COUNT"

    start_monitor
    log "Monitor PID: $MONITOR_PID"

    if [ $RESTART_COUNT -eq 0 ]; then
        if [ "$USER_WANTS_HANDOFF" = true ]; then
            EXISTING_HANDOFF=$(find_handoff_for_channel "$CHANNEL")
            if [ -n "$EXISTING_HANDOFF" ]; then
                log "User requested handoff, found: $EXISTING_HANDOFF"
                $CLAUDE_BIN $CLAUDE_DEFAULT_FLAGS "Continue from handoff. Check ~/.claude/handoff/ for handoff file, read it, then continue the task."
            else
                log "User requested handoff but none found - starting fresh"
                $CLAUDE_BIN $CLAUDE_DEFAULT_FLAGS "${FILTERED_ARGS[@]}"
            fi
        else
            log "Starting fresh"
            $CLAUDE_BIN $CLAUDE_DEFAULT_FLAGS "${FILTERED_ARGS[@]}"
        fi
    else
        log "Restarting with handoff prompt"
        printf '\033[2J\033[3J\033[H'
        $CLAUDE_BIN $CLAUDE_DEFAULT_FLAGS "Continue from handoff. Check ~/.claude/handoff/ for handoff file, read it, then continue the task."
    fi
    EXIT_CODE=$?
    log "Claude exited: $EXIT_CODE"

    if [ $EXIT_CODE -eq 130 ]; then
        log "User pressed Ctrl+C - clean exit"
        rm -f "$RESTART_FILE" "$KILLED_BY_MONITOR"
        break
    fi

    if [ -f "$KILLED_BY_MONITOR" ]; then
        rm -f "$KILLED_BY_MONITOR"
        if [ -f "$RESTART_FILE" ]; then
            SIGNAL_DIR=$(cat "$RESTART_FILE" 2>/dev/null)
            log "Auto-restart triggered"
            rm -f "$RESTART_FILE"
            [ -n "$SIGNAL_DIR" ] && [ -d "$SIGNAL_DIR" ] && WORKING_DIR="$SIGNAL_DIR" && cd "$WORKING_DIR"
            RESTART_COUNT=$((RESTART_COUNT + 1))
            [ $RESTART_COUNT -ge $MAX_RESTARTS ] && echo "Max restarts reached" && exit 1
            # Set flag so hook knows to auto-load handoff
            touch "$HOME/.claude/.load-handoff"
            rm -f "$RESTART_FILE" "$KILLED_BY_MONITOR"
            continue
        fi
    fi

    rm -f "$RESTART_FILE"
    HANDOFF=$(find_handoff_for_channel "$CHANNEL")
    [ -n "$HANDOFF" ] && echo "Handoff available: $HANDOFF (use 'claude --handoff' to load)"
    log "Clean exit"
    break
done

log "=== Wrapper finished ==="
exit $EXIT_CODE
```

Make it executable:
```bash
chmod +x ~/infrastructure/bin/claude-wrapper
```

### Step 8: Configure Claude Code Hooks

Update `~/.claude/settings.json`:

```json
{
  "hooks": {
    "SessionStart": [
      {
        "matcher": "startup",
        "hooks": [
          {
            "type": "command",
            "command": "$HOME/.claude/hooks/session-start-from-handoff.sh"
          }
        ]
      }
    ],
    "PostToolUse": [
      {
        "matcher": ".*",
        "hooks": [
          {
            "type": "command",
            "command": "$HOME/.claude/hooks/context-monitor.sh",
            "timeout": 5
          }
        ]
      }
    ]
  }
}
```

### Step 9: Create Channel Registry

Create `~/.claude/channel-registry.json`:

```json
{
  "description": "Maps project paths to memory-keeper channels. Longest matching path wins.",
  "registry": {
    "/home/USERNAME": "global"
  },
  "notes": {
    "global": "Cross-project settings, user preferences"
  }
}
```

Replace `USERNAME` with the actual username.

### Step 10: Set Up Alias

Add to `~/.bashrc`:

```bash
alias claude='~/infrastructure/bin/claude-wrapper'
alias claude-direct='~/.local/bin/claude --dangerously-skip-permissions'
```

Then:
```bash
source ~/.bashrc
```

### Step 11: Add CLAUDE.md Instructions

Add to your project's `CLAUDE.md` or global `~/CLAUDE.md`:

```markdown
## Auto-Handoff Protocol

**When context status shows CRITICAL or WARN:**

1. Stop current task at safe point
2. Save state to memory-keeper:
   ```
   context_save({ key: "{channel}-handoff-state", value: "...", priority: "high", channel: "{channel}" })
   ```
3. Create handoff file:
   ```bash
   cat > ~/.claude/handoff/{channel}-$$.md << 'EOF'
   # Handoff State
   **Task:** [description]
   **Progress:** [what's done]
   **Next:** [next steps]
   EOF
   ```
4. Create restart signal:
   ```bash
   echo "$(pwd)" > ~/.claude/.restart-session
   ```
5. Make one more tool call (triggers the restart)

**On startup (handoff loads instantly in context):**
The hook automatically includes handoff content in the session start message.
You'll see "=== HANDOFF LOADED ===" with the full content - no need to read files.
Just continue the task from where it left off.
```

### Step 12: Verify Installation

```bash
# Test channel detection
~/.claude/hooks/lib/get-channel.sh

# Test context monitor
~/.claude/hooks/context-monitor.sh
cat ~/.claude/.context-status

# Test wrapper
claude --help
```

### Step 13: Optional - Migrate Existing Conversations

If you want to organize existing conversations:

**Archive old conversations (older than N days):**
```python
# Python script to archive conversations older than 10 days
import os, gzip, shutil
from datetime import datetime, timedelta
from pathlib import Path

projects_dir = Path.home() / ".claude" / "projects"
archives_dir = Path.home() / ".claude" / "archives"
cutoff = datetime.now() - timedelta(days=10)

for project_path in projects_dir.iterdir():
    if not project_path.is_dir():
        continue
    channel = "global"  # or derive from project name
    archive_dir = archives_dir / channel
    archive_dir.mkdir(parents=True, exist_ok=True)

    for f in project_path.glob("*.jsonl"):
        mtime = datetime.fromtimestamp(f.stat().st_mtime)
        if mtime < cutoff:
            archive_name = f"{f.stem}-{datetime.now().strftime('%Y%m%d')}.jsonl.gz"
            with open(f, 'rb') as f_in:
                with gzip.open(archive_dir / archive_name, 'wb') as f_out:
                    shutil.copyfileobj(f_in, f_out)
            f.unlink()
            print(f"Archived: {f.name}")
```

---

## Usage

After installation:

| Command | What it does |
|---------|-------------|
| `claude` | Fresh session (default) |
| `claude --handoff` | Load existing handoff if available |
| `claude-direct` | Bypass wrapper |

The system will automatically:
1. Monitor context size after every tool call
2. Create handoff + restart signal when CRITICAL
3. Kill and restart Claude
4. New session continues from handoff

**No user intervention needed after starting `claude`.**

---

## Troubleshooting

If auto-restart doesn't trigger:
1. Check wrapper is running: `cat ~/.claude/.wrapper-pid`
2. Check for restart signal: `cat ~/.claude/.restart-session`
3. Check logs: `tail ~/.claude/auto-session.log`

If handoff not loading:
1. Check handoff exists: `ls ~/.claude/handoff/`
2. Check channel detection: `~/.claude/hooks/lib/get-channel.sh`
3. Use `claude --handoff` to force load
