# Auto-Handoff System for Claude Code

> **Walk-away automation for unlimited context sessions**

## The Problem

Claude Code has a context window limit (~200k tokens). When working on complex, multi-step tasks, the context fills up and triggers "auto-compact" which summarizes the conversation - losing detailed task state, file references, and progress markers.

This forces users to either:
- Manually save state and restart frequently
- Lose important context mid-task
- Re-explain the same things repeatedly

## The Solution

The Auto-Handoff System solves this by:

1. **Monitoring** - A hook tracks context size after every tool call
2. **Warning** - Claude sees status updates (OK → WARN → CRITICAL)
3. **Handoff** - At CRITICAL, Claude saves task state to a handoff file
4. **Restart** - A wrapper script kills and restarts Claude automatically
5. **Instant Resume** - Hook includes handoff content directly in session start (zero tool calls needed)

**Result:** Claude can work autonomously for hours/days with no user intervention.

## Quick Start

### For New Users (Fresh Install)

1. Copy the contents of `auto-handoff-install-prompt.md`
2. Paste it to Claude Code in a new session
3. Claude will set everything up automatically

### For Existing Users (Upgrade)

**No migration needed!** Just update the hook file and it works on next resume:

```bash
# Update the session-start hook (copy from install-prompt or backup)
# Old handoffs are still compatible - they just load faster now
```

### For Existing Users (Full Backup Restore)

```bash
# Extract backup
tar -xzf auto-handoff-system-YYYYMMDD.tar.gz
cd auto-handoff-YYYYMMDD/

# Restore files
cp -r hooks ~/.claude/
cp channel-registry.json ~/.claude/
cp settings.json ~/.claude/
cp claude-wrapper ~/infrastructure/bin/
chmod +x ~/infrastructure/bin/claude-wrapper

# Set up alias
echo "alias claude='~/infrastructure/bin/claude-wrapper'" >> ~/.bashrc
source ~/.bashrc

# Install memory-keeper MCP
claude mcp add memory-keeper -- npx mcp-memory-keeper
```

## Documentation

| File | Description |
|------|-------------|
| `auto-handoff-system.md` | Full technical documentation |
| `auto-handoff-install-prompt.md` | Copy-paste installation for Claude |
| `README-auto-handoff.md` | This overview |

## Components

```
~/.claude/
├── hooks/
│   ├── context-monitor.sh           # Tracks context (PostToolUse hook)
│   ├── session-start-from-handoff.sh # Loads handoff on start
│   ├── pre-compact-handoff.sh       # Creates handoff at CRITICAL
│   ├── zombie-killer.sh             # Cleanup zombie processes
│   └── lib/
│       ├── get-channel.sh           # Channel detection
│       ├── handoff-manifest.sh      # Handoff manifest system
│       └── trigger-restart.sh       # Helper for restart signals
├── handoff/
│   ├── {channel}-CURRENT.md         # Active handoff
│   ├── {channel}.manifest.json      # Handoff tracking
│   └── archive/                     # Consumed handoffs
├── channel-registry.json            # Directory → channel mapping
└── settings.json                    # Hook configuration

~/infrastructure/bin/
└── claude-wrapper                   # Main wrapper script
```

## Usage

| Command | Description |
|---------|-------------|
| `claude` | Start fresh session (ignores existing handoffs) |
| `claude --handoff` | Load handoff if one exists |
| `claude-direct` | Bypass wrapper, use raw Claude |

## How It Works

```
┌─────────────────────────────────────────────────────────────┐
│                    WRAPPER SCRIPT                           │
│                                                             │
│   1. Starts background monitor                              │
│   2. Launches Claude                                        │
│   3. Monitor checks for restart signal every 0.5s           │
│   4. If signal found: kill Claude, increment count, restart │
└─────────────────────────────────────────────────────────────┘
                              │
                              ▼
┌─────────────────────────────────────────────────────────────┐
│                    CLAUDE SESSION                           │
│                                                             │
│   PostToolUse Hook runs after EVERY tool call:              │
│   - Checks transcript file size                             │
│   - Writes status to ~/.claude/.context-status              │
│                                                             │
│   Claude (per CLAUDE.md instructions):                      │
│   - Periodically checks status                              │
│   - At CRITICAL: creates handoff + restart signal           │
└─────────────────────────────────────────────────────────────┘
                              │
                              ▼
┌─────────────────────────────────────────────────────────────┐
│                    RESTART SEQUENCE                         │
│                                                             │
│   1. CRITICAL triggers, creates handoff with unique ID      │
│   2. Restart signal written: SESSION:DIR:HANDOFF_ID         │
│   3. Monitor sees signal, kills Claude (SIGTERM/SIGKILL)    │
│   4. Wrapper extracts EXACT handoff ID from signal          │
│   5. SessionStart hook loads that specific handoff INLINE   │
│   6. Claude sees full handoff in context - instant resume   │
│                                                             │
│   Handoff ID in signal ensures correct handoff loads        │
│   even with multiple concurrent sessions on same channel.   │
└─────────────────────────────────────────────────────────────┘
```

## Thresholds

Token-based thresholds (200k context limit, 98% hard cutoff):

| Tokens | % | Status | Action |
|--------|---|--------|--------|
| < 160k | < 80% | OK | Normal operation |
| 160-184k | 80-92% | EARLY_WARN | Status file only |
| 184-192k | 92-96% | WARN | Wrap up current task |
| > 192k | > 96% | CRITICAL | Auto-handoff triggered |

**Test mode** (touch `~/.claude/.test-mode`): CRITICAL at 5% for testing.

## Dependencies

- **Claude Code CLI** - `npm install -g @anthropic-ai/claude-code`
- **Node.js 18+** - Runtime for MCPs
- **mcp-memory-keeper** - `claude mcp add memory-keeper -- npx mcp-memory-keeper`

## Archive System

Old conversations are automatically archived and cleaned:

**Automatic cleanup (runs during handoff):**
- Archives current session transcript
- Deletes original if >24 hours old
- Archives and deletes orphaned transcripts >30 days old

**Manual commands:**
```bash
~/.claude/hooks/archive-manager.sh report   # Show stats
~/.claude/hooks/archive-manager.sh cleanup  # Remove archives >30 days
~/.claude/hooks/archive-manager.sh orphans  # Archive orphaned transcripts
~/.claude/hooks/archive-manager.sh full     # Both cleanup + orphans
```

**Archive location:**
```bash
~/.claude/archives/{channel}/
# Format: {uuid}-{timestamp}.jsonl.gz

# Access archived sessions
zcat ~/.claude/archives/global/abc123-20260201.jsonl.gz | less
zgrep "search term" ~/.claude/archives/global/*.gz
```

## Channel System

Channels organize conversations and handoffs by project:

```json
{
  "registry": {
    "/home/user/project-a": "project-a",
    "/home/user/project-b": "project-b",
    "/home/user": "global"
  }
}
```

Longest path match wins, so `/home/user/project-a` uses `project-a` channel, not `global`.

## Limitations

1. **Network drops** - No handoff created if connection lost
2. **Crash before handoff** - State lost if Claude crashes before saving
3. **2-hour expiry** - Old handoffs ignored to prevent stale state
4. **Max 10 restarts** - Prevents infinite loops

## Credits

Developed by Jesse + Claude (Opus 4.5), February 2026.

GitHub Issue: https://github.com/anthropics/claude-code/issues/18417
