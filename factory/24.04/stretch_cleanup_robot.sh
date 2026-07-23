#!/bin/bash
# ============================================================
# Post-Bringup Comprehensive Cleanup Script
#
# Clears all temporary bringup artifacts from the robot NUC
# before the robot is handed off to QA / shipped to customer.
#
# Steps performed:
#   1.  Push production data repos to remote (git push)
#   2.  Clear git credentials, PAT, and identity
#   3.  Clear GitHub CLI (gh) auth credentials
#   4.  Remove Antigravity (Gemini) credentials and data
#   5.  Uninstall Antigravity (apt-get remove --purge)
#   6.  Remove VS Code credentials and configuration
#   7.  Remove Chrome profile data (full)
#   8.  Remove Firefox profile data (full)
#   9.  Clear standard user directories content (incl. Videos)
#  10.  Remove ROS domain ID assignment
#  11.  Remove Sunshine remote desktop config
#  12.  Remove RustDesk remote desktop config and history
#  13.  Clear system trash
#  14.  Install latest stretch4 packages
#  15.  Remove production repos in ~/repos (LAST — script lives inside ~/repos)
#
# Run from the machine you used for bringup (robot NUC).
# ============================================================

set -uo pipefail

# -------------------------------------------------------
# Clean exit on Ctrl+C / SIGTERM
# -------------------------------------------------------
trap 'echo ""; echo "Interrupted — cleanup aborted."; exit 130' INT TERM

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

# -------------------------------------------------------
# Output helpers
# -------------------------------------------------------
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
CYAN='\033[0;36m'
BOLD='\033[1m'
DIM='\033[2m'
NC='\033[0m'

section() { echo -e "\n${CYAN}${BOLD}==> $*${NC}"; }
ok()      { echo -e "  ${GREEN}[OK]${NC} $*"; }
warn()    { echo -e "  ${YELLOW}[WARN]${NC} $*"; }
fail()    { echo -e "  ${RED}[FAIL]${NC} $*"; }

# Run a command with a timeout; print its output only on failure.
# Usage: run_step "label" "command string"
run_step() {
    local label="$1"
    shift
    local cmd_str="$*"
    local timeout_secs="${STEP_TIMEOUT:-300}"
    local output exit_code

    output=$(timeout "$timeout_secs" bash -c "$cmd_str" 2>&1)
    exit_code=$?

    if [ "$exit_code" -eq 0 ]; then
        ok "$label"
        return 0
    elif [ "$exit_code" -eq 124 ]; then
        fail "$label — ${RED}TIMED OUT${NC} after ${timeout_secs}s"
    else
        fail "$label — exit code $exit_code"
    fi
    echo -e "    ${DIM}Command: $cmd_str${NC}"
    echo -e "    ${DIM}Last output:${NC}"
    echo "$output" | tail -10 | sed 's/^/      /'
    return 1
}

print_summary() {
    local -n _errors=$1
    echo ""
    echo -e "${BOLD}────────────────────────────────────────${NC}"
    if [ ${#_errors[@]} -eq 0 ]; then
        echo -e "${GREEN}${BOLD}✓ All steps completed successfully.${NC}"
    else
        for err in "${_errors[@]}"; do
            fail "$err"
        done
    fi
    echo ""
}

confirm() {
    while true; do
        read -rp "$1 (yes/no): " yn
        case $yn in
            [Yy]* ) return 0;;
            [Nn]* ) return 1;;
            * ) echo "Please answer yes or no.";;
        esac
    done
}

echo ""
echo "================================================="
echo "   Post-Bringup Comprehensive Cleanup Script     "
echo "================================================="
echo ""
echo "This script will:"
echo "  [ 1] Push stretch_production_data_ii and stretch_fleet_ii to remote"
echo "  [ 2] Remove all git credentials, PAT, and SSH keys"
echo "  [ 3] Clear GitHub CLI (gh) auth credentials"
echo "  [ 4] Remove Antigravity (Gemini) credentials and data (~/.gemini, ~/.antigravity, ~/.antigravity-ide, ~/.config/Antigravity, ~/Downloads/Antigravity*)"
echo "  [ 5] Uninstall Antigravity (apt-get remove --purge antigravity)"
echo "  [ 6] Remove VS Code credentials and configuration"
echo "  [ 7] Remove Chrome profile data (full)"
echo "  [ 8] Remove Firefox profile data (full)"
echo "  [ 9] Clear ~/Pictures, ~/Downloads, ~/Documents, ~/Videos, and shell history (~/.bash_history, ~/.python_history)"
echo "  [10] Remove the ROS domain ID assignment"
echo "  [11] Remove Sunshine remote desktop config"
echo "  [12] Remove RustDesk remote desktop config and history"
echo "  [13] Clear system trash (~/.local/share/Trash)"
echo "  [14] Install latest stretch4 packages"
echo "  [15] Remove production repos in ~/repos (keep stretch4_pyhesai_wrapper) — runs last"
echo ""
confirm "Are you sure you want to continue?" || { echo "Exiting."; exit 0; }

STEP_TIMEOUT=120
errors=()

# Derive robot ID from hostname (e.g. stretch-se4-4032 -> SE4-4032)
ROBOT_ID="$(hostname)"

# -------------------------------------------------------
# Step 1: Store and push production data
# -------------------------------------------------------
section "Step 1 / 15 — Storing and pushing production data"

STORE_SCRIPT="$SCRIPT_DIR/store_production_data.sh"
if [ -f "$STORE_SCRIPT" ]; then
    echo "  Running store_production_data.sh to copy and push robot data..."
    if ! bash "$STORE_SCRIPT"; then
        warn "store_production_data.sh reported errors — continuing with cleanup anyway."
        errors+=("[1/15] store_production_data.sh")
    fi
else
    # Fallback: bare git push if the store script is somehow missing
    warn "store_production_data.sh not found at $STORE_SCRIPT — falling back to bare git push."
    push_repo() {
        local repo="$1"
        local repo_path
        repo_path="$(eval echo ~/repos/$repo)"

        if [ ! -d "$repo_path" ]; then
            warn "$repo not found at $repo_path — skipping."
            return 0
        fi

        local output exit_code
        output=$(cd "$repo_path" \
            && git config http.postBuffer 524288000 \
            && git add -A \
            && { git diff --cached --quiet || git commit -m "cleanup: final data push, ${ROBOT_ID} ready to ship"; } \
            && git push 2>&1)
        exit_code=$?

        echo "$output"

        if [ $exit_code -ne 0 ]; then
            if echo "$output" | grep -qiE \
                "authentication failed|invalid credentials|bad credentials|401|403|could not read Username|permission denied|token|PAT|credential"; then
                echo ""
                echo "  ┌─────────────────────────────────────────────────────────────┐"
                echo "  │  GIT AUTHENTICATION ERROR — push to '$repo' failed          │"
                echo "  │                                                             │"
                echo "  │  Your GitHub PAT is likely expired, revoked, or missing     │"
                echo "  │  the required 'repo' scope.                                 │"
                echo "  │                                                             │"
                echo "  │  To fix before re-running this script:                      │"
                echo "  │    1. Generate a new PAT (repo scope):                      │"
                echo "  │       https://github.com/settings/tokens/new               │"
                echo "  │    2. Clear old helper & login:                             │"
                echo "  │       git config --global --unset credential.helper         │"
                echo "  │       gh auth login                                         │"
                echo "  │    3. Test:  git -C $repo_path push --dry-run               │"
                echo "  │    4. Re-run this script once the push succeeds.            │"
                echo "  └─────────────────────────────────────────────────────────────┘"
            else
                echo "  Push failed for '$repo'. Check the output above for details."
            fi
            return 1
        fi
    }
    for repo in stretch_production_data_ii stretch_fleet_ii; do
        if ! push_repo "$repo"; then
            errors+=("[1/15] Push $repo")
        fi
    done
fi

echo ""
confirm "Confirm all production data has been pushed (check git log if unsure). Continue?" \
    || { echo "Exiting — please push data manually before re-running."; exit 1; }

# -------------------------------------------------------
# Step 2: Clear git credentials, PAT, and identity
# -------------------------------------------------------
section "Step 2 / 14 — Clearing git credentials and PAT"

GIT_CRED_CMD="rm -f ~/.git-credentials 2>/dev/null || true"
GIT_CRED_CMD="$GIT_CRED_CMD; git config --global --unset credential.helper 2>/dev/null || true"
GIT_CRED_CMD="$GIT_CRED_CMD; git config --global --unset user.name 2>/dev/null || true"
GIT_CRED_CMD="$GIT_CRED_CMD; git config --global --unset user.email 2>/dev/null || true"
GIT_CRED_CMD="$GIT_CRED_CMD; rm -f ~/.ssh/id_rsa* ~/.ssh/id_ed25519* 2>/dev/null || true"
# Remove any PAT stored in .gitconfig or .netrc
GIT_CRED_CMD="$GIT_CRED_CMD; rm -f ~/.netrc 2>/dev/null || true"
# Remove git credential cache socket
GIT_CRED_CMD="$GIT_CRED_CMD; rm -rf ~/.cache/git/ 2>/dev/null || true"
# Remove entire .gitconfig to ensure no PAT remnants in credential helper
GIT_CRED_CMD="$GIT_CRED_CMD; rm -f ~/.gitconfig 2>/dev/null || true"

if ! run_step "[2/14] Clear git credentials and PAT" "$GIT_CRED_CMD"; then
    errors+=("[2/14] Clear git credentials and PAT")
fi

# -------------------------------------------------------
# Step 3: Clear GitHub CLI (gh) auth credentials
# -------------------------------------------------------
section "Step 3 / 14 — Clearing GitHub CLI (gh) auth"

GH_CMD="gh auth logout --hostname github.com 2>/dev/null || true"
# Remove gh config directory entirely (stores tokens, hosts.yml)
GH_CMD="$GH_CMD; rm -rf ~/.config/gh/ 2>/dev/null || true"

if ! run_step "[3/14] Clear gh auth credentials" "$GH_CMD"; then
    errors+=("[3/14] Clear gh auth credentials")
fi

# -------------------------------------------------------
# Step 4: Remove Antigravity (Gemini) credentials and data
# -------------------------------------------------------
section "Step 4 / 14 — Removing Antigravity / Gemini credentials"

ANTI_CMD="rm -rf ~/.gemini/ 2>/dev/null || true"
# ~/.antigravity — home-directory data folder (sign-in state, workspace cache)
ANTI_CMD="$ANTI_CMD; rm -rf ~/.antigravity/ 2>/dev/null || true"
# Also remove Antigravity IDE local data (contains conversation history)
ANTI_CMD="$ANTI_CMD; rm -rf ~/.antigravity-ide/ 2>/dev/null || true"
# Remove the Electron app data directory — 
ANTI_CMD="$ANTI_CMD; rm -rf ~/.config/Antigravity/ 2>/dev/null || true"
# Remove Antigravity installer tarballs and extracted app folders from Downloads
ANTI_CMD="$ANTI_CMD; rm -rf ~/Downloads/Antigravity* ~/Downloads/Antigravity\ IDE* 2>/dev/null || true"
# Also remove any Google application default credentials
ANTI_CMD="$ANTI_CMD; rm -rf ~/.config/gcloud/ 2>/dev/null || true"

if ! run_step "[4/15] Remove Antigravity credentials" "$ANTI_CMD"; then
    errors+=("[4/15] Remove Antigravity credentials")
fi

# -------------------------------------------------------
# Step 5: Uninstall Antigravity
# -------------------------------------------------------
section "Step 5 / 15 — Uninstalling Antigravity"

# Uninstall the .deb package (purge removes config files too)
UNINSTALL_CMD="sudo apt-get remove --purge -y antigravity 2>/dev/null || true"
# Clean up any leftover apt dependencies
UNINSTALL_CMD="$UNINSTALL_CMD; sudo apt-get autoremove -y 2>/dev/null || true"

if ! run_step "[5/15] Uninstall Antigravity" "$UNINSTALL_CMD"; then
    errors+=("[5/15] Uninstall Antigravity")
fi

# -------------------------------------------------------
# Step 6: Remove VS Code credentials and configuration
# -------------------------------------------------------
section "Step 6 / 15 — Removing VS Code credentials and config"

VSCODE_CMD="rm -rf ~/.config/Code/ 2>/dev/null || true"
VSCODE_CMD="$VSCODE_CMD; rm -rf ~/.vscode/ 2>/dev/null || true"
VSCODE_CMD="$VSCODE_CMD; rm -rf ~/.vscode-server/ 2>/dev/null || true"

if ! run_step "[6/15] Remove VS Code credentials" "$VSCODE_CMD"; then
    errors+=("[6/15] Remove VS Code credentials")
fi

# -------------------------------------------------------
# Step 7: Remove Chrome profile data (full)
# -------------------------------------------------------
section "Step 7 / 15 — Removing Chrome profile data"

CHROME_CMD="rm -rf \"\$HOME/.config/google-chrome/\" 2>/dev/null || true"
CHROME_CMD="$CHROME_CMD; rm -rf \"\$HOME/.cache/google-chrome/\" 2>/dev/null || true"
CHROME_CMD="$CHROME_CMD; rm -rf \"\$HOME/.config/chromium/\" 2>/dev/null || true"
CHROME_CMD="$CHROME_CMD; rm -rf \"\$HOME/.cache/chromium/\" 2>/dev/null || true"
# Snap-installed Chromium
CHROME_CMD="$CHROME_CMD; rm -rf \"\$HOME/snap/chromium/\" 2>/dev/null || true"
# Clear GNOME keyring — Chrome stores Google account tokens here independently
# of the profile folder; without this, Gmail sessions can survive the wipe.
CHROME_CMD="$CHROME_CMD; rm -f \"\$HOME/.local/share/keyrings/login.keyring\" 2>/dev/null || true"
CHROME_CMD="$CHROME_CMD; rm -f \"\$HOME/.local/share/keyrings/user.keystore\" 2>/dev/null || true"
# Kill the keyring daemon so deleted files are also purged from memory
CHROME_CMD="$CHROME_CMD; pkill -u \"\$USER\" gnome-keyring-daemon 2>/dev/null || true"

if ! run_step "[7/15] Remove Chrome profile data + Gmail keyring tokens" "$CHROME_CMD"; then
    errors+=("[7/15] Remove Chrome profile data")
fi

# -------------------------------------------------------
# Step 8: Remove Firefox profile data (full)
# -------------------------------------------------------
section "Step 8 / 15 — Removing Firefox profile data"

FIREFOX_CMD="rm -rf \"\$HOME/.mozilla/\" 2>/dev/null || true"
FIREFOX_CMD="$FIREFOX_CMD; rm -rf \"\$HOME/.cache/mozilla/\" 2>/dev/null || true"
# Snap-installed Firefox
FIREFOX_CMD="$FIREFOX_CMD; rm -rf \"\$HOME/snap/firefox/\" 2>/dev/null || true"

if ! run_step "[8/15] Remove Firefox profile data" "$FIREFOX_CMD"; then
    errors+=("[8/15] Remove Firefox profile data")
fi

# -------------------------------------------------------
# Step 9: Clear standard user directories
# -------------------------------------------------------
section "Step 9 / 15 — Clearing user directories and shell history"
# Clear standard user directories
USER_DIR_CMD="rm -rf ~/Pictures/* ~/Downloads/* ~/Documents/* ~/Videos/* 2>/dev/null || true"
# Clear shell command history — contains PATs, IPs, and bringup commands
USER_DIR_CMD="$USER_DIR_CMD; truncate -s 0 ~/.bash_history 2>/dev/null || true"
USER_DIR_CMD="$USER_DIR_CMD; truncate -s 0 ~/.zsh_history 2>/dev/null || true"
USER_DIR_CMD="$USER_DIR_CMD; truncate -s 0 ~/.python_history 2>/dev/null || true"
USER_DIR_CMD="$USER_DIR_CMD; truncate -s 0 ~/.local/share/fish/fish_history 2>/dev/null || true"
# Also clear the in-memory history so it can't be recalled after this script
USER_DIR_CMD="$USER_DIR_CMD; history -c 2>/dev/null || true"

if ! run_step "[9/15] Clear user dirs and shell history" "$USER_DIR_CMD"; then
    errors+=("[9/15] Clear user directories and shell history")
fi

# -------------------------------------------------------
# Step 10: Remove ROS domain ID assignment
# -------------------------------------------------------
section "Step 10 / 15 — Removing ROS domain ID"

if [ -f ~/repos/stretch_production_tools_ii/utils/assign_random_ros_domain_id.py ]; then
    if ! run_step "[10/15] Remove ROS domain ID" "python3 ~/repos/stretch_production_tools_ii/utils/assign_random_ros_domain_id.py --remove || true"; then
        errors+=("[10/15] Remove ROS domain ID")
    fi
else
    warn "assign_random_ros_domain_id.py not found. Skipping."
fi

# -------------------------------------------------------
# Step 11: Remove Sunshine remote desktop config
# -------------------------------------------------------
section "Step 11 / 15 — Removing Sunshine config"

SUNSHINE_CMD="rm -rf \"\$HOME/.config/sunshine/\" 2>/dev/null || true"

if ! run_step "[11/15] Remove Sunshine config" "$SUNSHINE_CMD"; then
    errors+=("[11/15] Remove Sunshine config")
fi

# -------------------------------------------------------
# Step 12: Remove RustDesk remote desktop config and history
# -------------------------------------------------------
section "Step 12 / 15 — Removing RustDesk config"

RUSTDESK_CMD="sudo systemctl stop rustdesk 2>/dev/null || true"
RUSTDESK_CMD="$RUSTDESK_CMD; pkill -u \"\$USER\" rustdesk 2>/dev/null || true"
RUSTDESK_CMD="$RUSTDESK_CMD; rm -rf \"\$HOME/.config/rustdesk/\" 2>/dev/null || true"
RUSTDESK_CMD="$RUSTDESK_CMD; sudo rm -rf /root/.config/rustdesk/ 2>/dev/null || true"

if ! run_step "[12/15] Remove RustDesk config" "$RUSTDESK_CMD"; then
    errors+=("[12/15] Remove RustDesk config")
fi

# -------------------------------------------------------
# Step 13: Clear system trash
# -------------------------------------------------------
section "Step 13 / 15 — Clearing system trash"

TRASH_CMD="rm -rf \$HOME/.local/share/Trash/files/* 2>/dev/null || true"
TRASH_CMD="$TRASH_CMD; rm -rf \$HOME/.local/share/Trash/info/* 2>/dev/null || true"
TRASH_CMD="$TRASH_CMD; rm -rf \$HOME/.local/share/Trash/expunged/* 2>/dev/null || true"

if ! run_step "[13/15] Clear system trash" "$TRASH_CMD"; then
    errors+=("[13/15] Clear system trash")
fi

# -------------------------------------------------------
# Step 14: Install latest stretch4 packages
# -------------------------------------------------------
section "Step 14 / 15 — Installing latest stretch4 packages"

PIP_CMD="pip3 install --upgrade hello-robot-stretch4-body hello-robot-stretch4-urdf hello-robot-stretch4-flying-gripper hello-robot-stretch4-tray"

if ! run_step "[14/15] Install latest stretch4 packages" "$PIP_CMD"; then
    errors+=("[14/15] Install latest stretch4 packages")
fi

# -------------------------------------------------------
# Step 15: Remove production repos in ~/repos
#   This step runs LAST because the script itself lives inside ~/repos.
#   Note:      ~/stretch4_install is intentionally left untouched.
# -------------------------------------------------------
section "Step 15 / 15 — Removing production repos"

# cd away from ~/repos before deleting it so the shell keeps a valid CWD
cd "$HOME"

REPO_DEL_CMD="find ~/repos -maxdepth 1 -mindepth 1"
REPO_DEL_CMD="$REPO_DEL_CMD ! -name 'stretch4_pyhesai_wrapper'"
REPO_DEL_CMD="$REPO_DEL_CMD -exec rm -rf {} +"

if ! run_step "[15/15] Remove production repos in ~/repos" "$REPO_DEL_CMD"; then
    errors+=("[15/15] Remove repos")
fi



# -------------------------------------------------------
# Summary
# -------------------------------------------------------
print_summary errors

if [ ${#errors[@]} -eq 0 ]; then
    echo -e "${GREEN}${BOLD}Cleanup complete! Robot is ready for handoff.${NC}"
    echo ""
else
    exit 1
fi

# -------------------------------------------------------
# Reboot reminder
# -------------------------------------------------------
echo ""
echo "  ┌─────────────────────────────────────────────────────────────┐"
echo "  │  ⚠  REBOOT REQUIRED before handing off the robot           │"
echo "  │                                                             │"
echo "  │  The GNOME keyring daemon may still hold deleted tokens     │"
echo "  │  in memory. A reboot ensures all credentials are fully      │"
echo "  │  cleared from RAM before the robot ships.                   │"
echo "  │                                                             │"
echo "  │  Run:  sudo reboot                                          │"
echo "  └─────────────────────────────────────────────────────────────┘"
echo ""
