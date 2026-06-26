#!/usr/bin/env bash
# Uninstaller for claude-god-mode. Reverses install.sh 1-for-1.
#
# What it removes:
#   - Agents copied to ~/.claude/agents/ (only the 15 we installed; never
#     touches the user's other agents)
#   - The CLAUDE.md we placed (optionally restores the most recent backup)
#   - Hook entries we added to ~/.claude/settings.json (matched by
#     fingerprint substrings on the command strings, not by index)
#   - The 6 plugins we enabled in ~/.claude/settings.json
#   - The MCP server entries we added to ~/.claude.json (matched by name)
#   - The ENABLE_LSP_TOOL=1 line in ~/.bashrc / ~/.zshrc
#
# What it does NOT remove:
#   - Globally-installed binaries (npm/pip/cargo packages like
#     context-mode, jcodemunch, headroom, RTK, Cozempic, Graphify,
#     mcp-compressor). The user may use them in other tools. We print a
#     list of "manually remove if no longer needed".
#   - The ~/.claude/ directory itself (user may have other config there).
#   - Hooks or MCP entries the user added themselves.
#
# Usage:
#   ./uninstall.sh                # interactive — asks before each step
#   ./uninstall.sh --dry-run      # show what would be removed; touches nothing
#   ./uninstall.sh --yes          # skip prompts (for scripts / CI)

set -euo pipefail

# ── Argument parsing ──────────────────────────────────────
DRY_RUN=0
ASSUME_YES=0
for arg in "$@"; do
  case "$arg" in
    --dry-run|-n) DRY_RUN=1 ;;
    --yes|-y)     ASSUME_YES=1 ;;
    --help|-h)
      sed -n '2,28p' "$0" | sed 's/^# \?//'
      exit 0
      ;;
    *)
      echo "unknown argument: $arg" >&2
      echo "see --help" >&2
      exit 2
      ;;
  esac
done

# ── Style ─────────────────────────────────────────────────
RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'
BLUE='\033[0;34m'; PURPLE='\033[0;35m'; CYAN='\033[0;36m'
NC='\033[0m'; BOLD='\033[1m'

info()    { echo -e "  ${BLUE}[*]${NC} $1"; }
success() { echo -e "  ${GREEN}[+]${NC} $1"; }
warn()    { echo -e "  ${YELLOW}[!]${NC} $1"; }
error()   { echo -e "  ${RED}[-]${NC} $1"; }
ask() {
  [ "$ASSUME_YES" -eq 1 ] && return 0
  echo -ne "  ${CYAN}[?]${NC} $1 (y/n): "
  read -r ans
  [[ "$ans" =~ ^[Yy] ]]
}
dry() {
  [ "$DRY_RUN" -eq 1 ] && echo -e "  ${PURPLE}[dry-run]${NC} would: $1"
}

# ── Paths (must match install.sh) ─────────────────────────
CLAUDE_DIR="$HOME/.claude"
CLAUDE_JSON="$HOME/.claude.json"
SETTINGS="$CLAUDE_DIR/settings.json"
AGENTS_DIR="$CLAUDE_DIR/agents"

# Detect repo dir (same logic as install.sh) so we can read the agent
# manifest from the cloned repo if available; fall back to a hard-coded
# list when run via curl-pipe.
if [ -d "$(dirname "$0")/agents" ]; then
  REPO_DIR="$(cd "$(dirname "$0")" && pwd)"
else
  REPO_DIR=""
fi

# Detect shell rc file (same as install.sh)
SHELL_RC="$HOME/.bashrc"
[ -f "$HOME/.zshrc" ] && SHELL_RC="$HOME/.zshrc"

echo ""
echo -e "${PURPLE}${BOLD}"
echo "  ============================================"
echo "         Claude God Mode Uninstaller"
echo "  ============================================"
echo -e "${NC}"
if [ "$DRY_RUN" -eq 1 ]; then
  echo -e "  ${PURPLE}DRY RUN — nothing will be changed${NC}"
fi
echo ""

# ── Step 1: Remove agents we installed ────────────────────
echo -e "${BOLD}Step 1/6: Agents${NC}"
if [ -d "$AGENTS_DIR" ]; then
  agent_names=()
  if [ -n "$REPO_DIR" ] && [ -d "$REPO_DIR/agents" ]; then
    for f in "$REPO_DIR/agents/"*.md; do
      agent_names+=("$(basename "$f")")
    done
  else
    # Hard-coded list (matches the 15 agents in agents/ at install.sh's
    # last release). Update this list when the agent set changes.
    agent_names=(
      adversarial-coach.md architect.md constitutional-reviewer.md
      design-critic.md ensemble-judge.md hypothesis-tester.md
      integration-enforcer.md multi-perspective-reviewer.md red-team.md
      researcher.md socratic-questioner.md spec-interviewer.md
      test-authenticator.md tree-of-thought.md ui-architect.md
    )
  fi
  found=0
  for name in "${agent_names[@]}"; do
    [ -f "$AGENTS_DIR/$name" ] && found=$((found + 1))
  done
  if [ "$found" -eq 0 ]; then
    info "No claude-god-mode agents found in $AGENTS_DIR"
  elif ask "Remove $found agents from $AGENTS_DIR?"; then
    removed=0
    for name in "${agent_names[@]}"; do
      if [ -f "$AGENTS_DIR/$name" ]; then
        if [ "$DRY_RUN" -eq 1 ]; then
          dry "rm $AGENTS_DIR/$name"
        else
          rm -f "$AGENTS_DIR/$name"
        fi
        removed=$((removed + 1))
      fi
    done
    success "Removed $removed agents"
  else
    info "Skipped agent removal"
  fi
else
  info "Agents dir $AGENTS_DIR does not exist"
fi

# ── Step 2: Restore CLAUDE.md (if backup exists) ──────────
echo -e "\n${BOLD}Step 2/6: CLAUDE.md${NC}"
if [ -f "$CLAUDE_DIR/CLAUDE.md" ]; then
  # Find most recent backup
  latest_backup=$(ls -t "$CLAUDE_DIR"/CLAUDE.md.backup-* 2>/dev/null | head -1 || true)
  if [ -n "$latest_backup" ]; then
    info "Found backup: $(basename "$latest_backup")"
    if ask "Restore CLAUDE.md from this backup?"; then
      if [ "$DRY_RUN" -eq 1 ]; then
        dry "mv $latest_backup $CLAUDE_DIR/CLAUDE.md"
      else
        mv "$latest_backup" "$CLAUDE_DIR/CLAUDE.md"
      fi
      success "Restored CLAUDE.md from backup"
    else
      if ask "Just delete the installed CLAUDE.md instead?"; then
        if [ "$DRY_RUN" -eq 1 ]; then
          dry "rm $CLAUDE_DIR/CLAUDE.md"
        else
          rm -f "$CLAUDE_DIR/CLAUDE.md"
        fi
        success "Removed CLAUDE.md (backup preserved at $latest_backup)"
      fi
    fi
  else
    warn "No backup found at $CLAUDE_DIR/CLAUDE.md.backup-*"
    if ask "Delete the installed CLAUDE.md anyway?"; then
      if [ "$DRY_RUN" -eq 1 ]; then
        dry "rm $CLAUDE_DIR/CLAUDE.md"
      else
        rm -f "$CLAUDE_DIR/CLAUDE.md"
      fi
      success "Removed CLAUDE.md"
    fi
  fi
else
  info "$CLAUDE_DIR/CLAUDE.md does not exist"
fi

# ── Step 3: Remove hooks from settings.json ───────────────
echo -e "\n${BOLD}Step 3/6: Hooks${NC}"
if [ ! -f "$SETTINGS" ]; then
  info "$SETTINGS does not exist"
else
  # Fingerprint substrings — if a hook's command contains ANY of these,
  # we installed it. These match the commands in config/hooks.json.
  FINGERPRINTS=(
    "serena-bash-guard.js"
    "serena-glob-guard.js"
    "serena-grep-guard.js"
    "check-orphan.sh"
    "loop-guard.sh"
    "cozempic checkpoint"
    "AKIA[A-Z0-9]{16}"
    "DROP\\\\s+TABLE"
    "--no-verify"
    "biome check"
  )
  fp_json=$(printf '%s\n' "${FINGERPRINTS[@]}" | python3 -c "import json,sys; print(json.dumps([l.strip() for l in sys.stdin if l.strip()]))")

  removed_count=$(DRY_RUN="$DRY_RUN" SETTINGS="$SETTINGS" FP_JSON="$fp_json" python3 << 'PYEOF'
import json, os, sys
settings_path = os.environ["SETTINGS"]
dry = os.environ["DRY_RUN"] == "1"
fps = json.loads(os.environ["FP_JSON"])

try:
    with open(settings_path, encoding="utf-8") as f:
        settings = json.load(f)
except (json.JSONDecodeError, FileNotFoundError):
    print("0", end=""); sys.exit(0)

if "hooks" not in settings:
    print("0", end=""); sys.exit(0)

removed = 0
for event, entries in list(settings["hooks"].items()):
    kept_entries = []
    for entry in entries:
        kept_hooks = []
        for hook in entry.get("hooks", []):
            cmd = hook.get("command", "")
            if any(fp in cmd for fp in fps):
                removed += 1
                continue
            kept_hooks.append(hook)
        if kept_hooks:
            new_entry = dict(entry)
            new_entry["hooks"] = kept_hooks
            kept_entries.append(new_entry)
    if kept_entries:
        settings["hooks"][event] = kept_entries
    else:
        del settings["hooks"][event]

if not settings["hooks"]:
    del settings["hooks"]

if not dry:
    with open(settings_path, "w", encoding="utf-8") as f:
        json.dump(settings, f, indent=2)

print(str(removed), end="")
PYEOF
)
  if [ "$removed_count" -gt 0 ]; then
    if [ "$DRY_RUN" -eq 1 ]; then
      dry "remove $removed_count hook entries from $SETTINGS"
    else
      success "Removed $removed_count hook entries from settings.json"
    fi
  else
    info "No matching hook entries to remove"
  fi
fi

# ── Step 4: Disable plugins ───────────────────────────────
echo -e "\n${BOLD}Step 4/6: Plugins${NC}"
PLUGINS=(
  "pyright-lsp@claude-plugins-official"
  "rust-analyzer-lsp@claude-plugins-official"
  "context7@claude-plugins-official"
  "superpowers@claude-plugins-official"
  "semgrep@claude-plugins-official"
  "code-review@claude-plugins-official"
)
if [ -f "$SETTINGS" ]; then
  plugins_json=$(printf '%s\n' "${PLUGINS[@]}" | python3 -c "import json,sys; print(json.dumps([l.strip() for l in sys.stdin if l.strip()]))")
  disabled_count=$(DRY_RUN="$DRY_RUN" SETTINGS="$SETTINGS" PLUGINS_JSON="$plugins_json" python3 << 'PYEOF'
import json, os, sys
settings_path = os.environ["SETTINGS"]
dry = os.environ["DRY_RUN"] == "1"
plugins = json.loads(os.environ["PLUGINS_JSON"])

try:
    with open(settings_path, encoding="utf-8") as f:
        settings = json.load(f)
except (json.JSONDecodeError, FileNotFoundError):
    print("0", end=""); sys.exit(0)

if "enabledPlugins" not in settings:
    print("0", end=""); sys.exit(0)

disabled = 0
for p in plugins:
    if p in settings["enabledPlugins"]:
        del settings["enabledPlugins"][p]
        disabled += 1

if not settings["enabledPlugins"]:
    del settings["enabledPlugins"]

if not dry:
    with open(settings_path, "w", encoding="utf-8") as f:
        json.dump(settings, f, indent=2)

print(str(disabled), end="")
PYEOF
)
  if [ "$disabled_count" -gt 0 ]; then
    if [ "$DRY_RUN" -eq 1 ]; then
      dry "disable $disabled_count plugins in $SETTINGS"
    else
      success "Disabled $disabled_count plugins"
    fi
  else
    info "No matching plugins to disable"
  fi
else
  info "$SETTINGS does not exist"
fi

# ── Step 5: Remove MCP servers from ~/.claude.json ────────
echo -e "\n${BOLD}Step 5/6: MCP servers${NC}"
MCP_NAMES=(
  "context-mode" "jcodemunch" "headroom" "serena" "docfork"
  "21st-dev-magic" "shadcn" "magicui" "animotion" "aceternity"
  "dembrandt" "glance"
)
if [ -f "$CLAUDE_JSON" ]; then
  mcp_json=$(printf '%s\n' "${MCP_NAMES[@]}" | python3 -c "import json,sys; print(json.dumps([l.strip() for l in sys.stdin if l.strip()]))")
  removed_mcp=$(DRY_RUN="$DRY_RUN" CLAUDE_JSON="$CLAUDE_JSON" MCP_JSON="$mcp_json" python3 << 'PYEOF'
import json, os, sys
path = os.environ["CLAUDE_JSON"]
dry = os.environ["DRY_RUN"] == "1"
names = json.loads(os.environ["MCP_JSON"])

try:
    with open(path, encoding="utf-8") as f:
        d = json.load(f)
except (json.JSONDecodeError, FileNotFoundError):
    print("0", end=""); sys.exit(0)

if "mcpServers" not in d:
    print("0", end=""); sys.exit(0)

removed = 0
for n in names:
    if n in d["mcpServers"]:
        del d["mcpServers"][n]
        removed += 1

if not d["mcpServers"]:
    del d["mcpServers"]

if not dry:
    with open(path, "w", encoding="utf-8") as f:
        json.dump(d, f, indent=2)

print(str(removed), end="")
PYEOF
)
  if [ "$removed_mcp" -gt 0 ]; then
    if [ "$DRY_RUN" -eq 1 ]; then
      dry "remove $removed_mcp MCP server entries from $CLAUDE_JSON"
    else
      success "Removed $removed_mcp MCP server entries"
    fi
  else
    info "No matching MCP servers to remove"
  fi
else
  info "$CLAUDE_JSON does not exist"
fi

# ── Step 6: Remove env var from shell rc ──────────────────
echo -e "\n${BOLD}Step 6/6: Shell environment${NC}"
if [ -f "$SHELL_RC" ] && grep -q "ENABLE_LSP_TOOL=1" "$SHELL_RC"; then
  if ask "Remove ENABLE_LSP_TOOL=1 line from $SHELL_RC?"; then
    if [ "$DRY_RUN" -eq 1 ]; then
      dry "sed -i remove ENABLE_LSP_TOOL=1 from $SHELL_RC"
    else
      # Portable in-place edit (BSD vs GNU sed)
      tmp_rc="$(mktemp)"
      grep -v "^export ENABLE_LSP_TOOL=1$" "$SHELL_RC" > "$tmp_rc"
      cat "$tmp_rc" > "$SHELL_RC"
      rm -f "$tmp_rc"
    fi
    success "Removed ENABLE_LSP_TOOL=1 from $SHELL_RC"
  else
    info "Left $SHELL_RC alone"
  fi
else
  info "ENABLE_LSP_TOOL=1 not found in $SHELL_RC"
fi

# ── Done ──────────────────────────────────────────────────
echo ""
echo -e "  ${GREEN}${BOLD}============================================"
if [ "$DRY_RUN" -eq 1 ]; then
  echo "        Dry Run Complete (no changes made)"
else
  echo "          Uninstall Complete!"
fi
echo -e "  ============================================${NC}"
echo ""

warn "Globally-installed binaries were NOT removed automatically."
warn "If you no longer need them, remove manually:"
echo -e "    ${YELLOW}npm uninstall -g${NC}  context-mode docfork @21st-dev/magic magicui-mcp animotion-mcp aceternityui-mcp dembrandt-mcp glance-mcp"
echo -e "    ${YELLOW}pip uninstall${NC}    jcodemunch-mcp headroom-ai cozempic graphifyy mcp-compressor"
echo -e "    ${YELLOW}cargo uninstall${NC}  rtk"
echo -e "    ${YELLOW}uv tool uninstall${NC} serena-agent"
echo ""
info "If you restart Claude Code and still see effects, the user's other"
info "configuration in $SETTINGS / $CLAUDE_JSON may need a manual review."
echo ""
