#!/usr/bin/env sh
# rtk uninstaller - https://github.com/linuxdevel/rtk
# Usage: curl -fsSL https://raw.githubusercontent.com/linuxdevel/rtk/refs/heads/master/uninstall.sh | sh
#
# Removes the rtk binary, Claude Code hooks, config, and local data.
# Does NOT modify project-local CLAUDE.md files — remove @RTK.md lines manually.

set -e

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
NC='\033[0m'

info()  { printf "${GREEN}[INFO]${NC} %s\n" "$1"; }
warn()  { printf "${YELLOW}[WARN]${NC} %s\n" "$1"; }
skip()  { printf "${CYAN}[SKIP]${NC} %s\n" "$1"; }
error() { printf "${RED}[ERROR]${NC} %s\n" "$1"; exit 1; }

REMOVED=0
removed() { REMOVED=$((REMOVED + 1)); }

# ── 1. Remove Claude Code integration (hooks, RTK.md, settings.json entry) ──

remove_claude_hooks() {
    info "Removing Claude Code integration..."

    # Try the built-in uninstall first (handles settings.json patching)
    if command -v rtk >/dev/null 2>&1; then
        if rtk init -g --uninstall 2>/dev/null; then
            info "Removed Claude Code hooks via 'rtk init -g --uninstall'"
            removed
            return
        fi
    fi

    # Manual fallback if rtk binary is already gone
    HOOK="$HOME/.claude/hooks/rtk-rewrite.sh"
    HASH="$HOME/.claude/hooks/.rtk-hook.sha256"
    RTK_MD="$HOME/.claude/RTK.md"

    for f in "$HOOK" "$HASH" "$RTK_MD"; do
        if [ -f "$f" ]; then
            rm -f "$f"
            info "Removed $f"
            removed
        fi
    done

    # Remove @RTK.md reference from global CLAUDE.md
    CLAUDE_MD="$HOME/.claude/CLAUDE.md"
    if [ -f "$CLAUDE_MD" ] && grep -q "@RTK.md" "$CLAUDE_MD"; then
        # Remove lines containing @RTK.md (both relative and absolute paths)
        sed -i.bak '/@RTK\.md/d' "$CLAUDE_MD" 2>/dev/null || \
            sed -i '' '/@RTK\.md/d' "$CLAUDE_MD"  # macOS sed
        info "Removed @RTK.md reference from $CLAUDE_MD"
        removed
    fi

    # Remove RTK hook entry from settings.json
    SETTINGS="$HOME/.claude/settings.json"
    if [ -f "$SETTINGS" ] && grep -q "rtk-rewrite" "$SETTINGS"; then
        warn "RTK hook entry remains in $SETTINGS"
        warn "  Run: rtk init -g --uninstall (before removing binary) or edit manually"
        warn "  Backup available at: ${SETTINGS}.bak"
    fi
}

# ── 2. Remove binary ──

remove_binary() {
    info "Removing rtk binary..."

    FOUND_BIN=""

    # Check common install locations
    for candidate in \
        "$HOME/.local/bin/rtk" \
        "$HOME/.cargo/bin/rtk" \
        "/usr/local/bin/rtk" \
        "/usr/bin/rtk"; do
        if [ -f "$candidate" ]; then
            FOUND_BIN="$candidate"
            break
        fi
    done

    # Also check via which
    if [ -z "$FOUND_BIN" ] && command -v rtk >/dev/null 2>&1; then
        FOUND_BIN="$(command -v rtk)"
    fi

    if [ -z "$FOUND_BIN" ]; then
        skip "rtk binary not found (already removed or not installed)"
        return
    fi

    # Check if installed via package manager
    if echo "$FOUND_BIN" | grep -q "/Cellar/\|/homebrew/"; then
        warn "rtk was installed via Homebrew. Run: brew uninstall rtk"
        return
    fi

    if dpkg -s rtk >/dev/null 2>&1; then
        warn "rtk was installed via apt/dpkg. Run: sudo apt remove rtk"
        return
    fi

    if rpm -q rtk >/dev/null 2>&1; then
        warn "rtk was installed via rpm/dnf. Run: sudo dnf remove rtk"
        return
    fi

    # Try cargo uninstall first (cleanest for cargo installs)
    if echo "$FOUND_BIN" | grep -q "\.cargo/bin"; then
        if cargo uninstall rtk 2>/dev/null; then
            info "Removed via 'cargo uninstall rtk'"
            removed
            return
        fi
    fi

    # Direct removal for script-installed binary
    if [ -w "$FOUND_BIN" ] || [ -w "$(dirname "$FOUND_BIN")" ]; then
        rm -f "$FOUND_BIN"
        info "Removed $FOUND_BIN"
        removed
    else
        warn "Cannot remove $FOUND_BIN (permission denied). Run with sudo or remove manually."
    fi
}

# ── 3. Remove local data ──

remove_data() {
    info "Removing local data..."

    # ~/.local/share/rtk/ (tracking DB, telemetry salt, tee logs, hook audit)
    DATA_DIR="${XDG_DATA_HOME:-$HOME/.local/share}/rtk"
    if [ -d "$DATA_DIR" ]; then
        rm -rf "$DATA_DIR"
        info "Removed $DATA_DIR"
        removed
    else
        skip "$DATA_DIR not found"
    fi

    # ~/.config/rtk/ (config.toml, filters.toml, trust store)
    CONFIG_DIR="${XDG_CONFIG_HOME:-$HOME/.config}/rtk"
    if [ -d "$CONFIG_DIR" ]; then
        rm -rf "$CONFIG_DIR"
        info "Removed $CONFIG_DIR"
        removed
    else
        skip "$CONFIG_DIR not found"
    fi
}

# ── Main ──

main() {
    echo ""
    info "RTK Uninstaller"
    echo ""

    remove_claude_hooks
    remove_binary
    remove_data

    echo ""
    if [ "$REMOVED" -gt 0 ]; then
        info "Done. Removed $REMOVED item(s)."
    else
        info "Nothing to remove — RTK does not appear to be installed."
    fi

    echo ""
    warn "Project-local files (RTK.md, @RTK.md in CLAUDE.md/AGENTS.md) are NOT removed."
    warn "  Check your projects and remove any @RTK.md lines from CLAUDE.md or AGENTS.md."
    echo ""
}

main
