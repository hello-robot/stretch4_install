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
#   5.  Remove VS Code credentials and configuration
#   6.  Remove Chrome profile data (full)
#   7.  Remove Firefox profile data (full)
#   8.  Clear standard user directories content
#   9.  Remove ROS domain ID assignment
#  10.  Remove Sunshine remote desktop config
#  11.  Uninstall production tools Python package
#  12.  Remove production repos in ~/repos (preserve stretch4 model repos)
#
# Run from the machine you used for bringup (robot NUC).
# ============================================================

set -uo pipefail

# -------------------------------------------------------
# Clean exit on Ctrl+C / SIGTERM
# -------------------------------------------------------
trap 'echo ""; echo "Interrupted — cleanup aborted."; exit 130' INT TERM

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$SCRIPT_DIR/production_logger.sh"

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
echo "  [ 4] Remove Antigravity (Gemini) credentials and data"
echo "  [ 5] Remove VS Code credentials and configuration"
echo "  [ 6] Remove Chrome profile data (full)"
echo "  [ 7] Remove Firefox profile data (full)"
echo "  [ 8] Clear ~/Pictures, ~/Downloads, ~/Documents"
echo "  [ 9] Remove the ROS domain ID assignment"
echo "  [10] Remove Sunshine remote desktop config"
echo "  [11] Uninstall production tools Python package"
echo "  [12] Remove production repos in ~/repos (keep stretch4_body, stretch4_urdf, stretch4_flying_gripper)"
echo ""
confirm "Are you sure you want to continue?" || { echo "Exiting."; exit 0; }

STEP_TIMEOUT=120
set_total_steps 12
errors=()

# Derive robot ID from hostname (e.g. stretch-se4-4032 -> SE4-4032)
ROBOT_ID="$(hostname)"

# -------------------------------------------------------
# Step 1: Push production data repos to remote
# -------------------------------------------------------
section "Step 1 / 12 — Pushing production data repos"

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
        && git commit -m "cleanup done from stretch4_install, ${ROBOT_ID}" --allow-empty \
        && git push 2>&1)
    exit_code=$?

    echo "$output"

    if [ $exit_code -ne 0 ]; then
        # Detect PAT / credential failures and give actionable guidance
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
            echo "  │    2. Store it:  gh auth login                              │"
            echo "  │       (or: git credential approve with the new token)       │"
            echo "  │    3. Test:  git -C $repo_path push --dry-run               │"
            echo "  │    4. Re-run this script once the push succeeds.            │"
            echo "  └─────────────────────────────────────────────────────────────┘"
        else
            echo "  Push failed for '$repo'. Check the output above for details."
        fi
        return 1
    fi
}

step1_ok=true
for repo in stretch_production_data_ii stretch_fleet_ii; do
    if ! push_repo "$repo"; then
        step1_ok=false
        errors+=("[1/12] Push $repo")
    fi
done

echo ""
confirm "Confirm all production data has been pushed (check git log if unsure). Continue?" \
    || { echo "Exiting — please push data manually before re-running."; exit 1; }

# -------------------------------------------------------
# Step 2: Clear git credentials, PAT, and identity
# -------------------------------------------------------
section "Step 2 / 12 — Clearing git credentials and PAT"

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

if ! run_step "[2/12] Clear git credentials and PAT" "$GIT_CRED_CMD"; then
    errors+=("[2/12] Clear git credentials and PAT")
fi

# -------------------------------------------------------
# Step 3: Clear GitHub CLI (gh) auth credentials
# -------------------------------------------------------
section "Step 3 / 12 — Clearing GitHub CLI (gh) auth"

GH_CMD="gh auth logout --hostname github.com 2>/dev/null || true"
# Remove gh config directory entirely (stores tokens, hosts.yml)
GH_CMD="$GH_CMD; rm -rf ~/.config/gh/ 2>/dev/null || true"

if ! run_step "[3/12] Clear gh auth credentials" "$GH_CMD"; then
    errors+=("[3/12] Clear gh auth credentials")
fi

# -------------------------------------------------------
# Step 4: Remove Antigravity (Gemini) credentials and data
# -------------------------------------------------------
section "Step 4 / 12 — Removing Antigravity / Gemini credentials"

ANTI_CMD="rm -rf ~/.gemini/ 2>/dev/null || true"
# Also remove any Google application default credentials
ANTI_CMD="$ANTI_CMD; rm -rf ~/.config/gcloud/ 2>/dev/null || true"

if ! run_step "[4/12] Remove Antigravity credentials" "$ANTI_CMD"; then
    errors+=("[4/12] Remove Antigravity credentials")
fi

# -------------------------------------------------------
# Step 5: Remove VS Code credentials and configuration
# -------------------------------------------------------
section "Step 5 / 12 — Removing VS Code credentials and config"

VSCODE_CMD="rm -rf ~/.config/Code/ 2>/dev/null || true"
VSCODE_CMD="$VSCODE_CMD; rm -rf ~/.vscode/ 2>/dev/null || true"
VSCODE_CMD="$VSCODE_CMD; rm -rf ~/.vscode-server/ 2>/dev/null || true"

if ! run_step "[5/12] Remove VS Code credentials" "$VSCODE_CMD"; then
    errors+=("[5/12] Remove VS Code credentials")
fi

# -------------------------------------------------------
# Step 6: Remove Chrome profile data (full)
# -------------------------------------------------------
section "Step 6 / 12 — Removing Chrome profile data"

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

if ! run_step "[6/12] Remove Chrome profile data + Gmail keyring tokens" "$CHROME_CMD"; then
    errors+=("[6/12] Remove Chrome profile data")
fi

# -------------------------------------------------------
# Step 7: Remove Firefox profile data (full)
# -------------------------------------------------------
section "Step 7 / 12 — Removing Firefox profile data"

FIREFOX_CMD="rm -rf \"\$HOME/.mozilla/\" 2>/dev/null || true"
FIREFOX_CMD="$FIREFOX_CMD; rm -rf \"\$HOME/.cache/mozilla/\" 2>/dev/null || true"
# Snap-installed Firefox
FIREFOX_CMD="$FIREFOX_CMD; rm -rf \"\$HOME/snap/firefox/\" 2>/dev/null || true"

if ! run_step "[7/12] Remove Firefox profile data" "$FIREFOX_CMD"; then
    errors+=("[7/12] Remove Firefox profile data")
fi

# -------------------------------------------------------
# Step 8: Clear standard user directories
# -------------------------------------------------------
section "Step 8 / 12 — Clearing user directories"

if ! run_step "[8/12] Clear ~/Pictures, ~/Downloads, ~/Documents" "rm -rf ~/Pictures/* ~/Downloads/* ~/Documents/* 2>/dev/null || true"; then
    errors+=("[8/12] Clear user directories")
fi

# -------------------------------------------------------
# Step 9: Remove ROS domain ID assignment
# -------------------------------------------------------
section "Step 9 / 12 — Removing ROS domain ID"

if [ -f ~/repos/stretch_production_tools_ii/utils/assign_random_ros_domain_id.py ]; then
    if ! run_step "[9/12] Remove ROS domain ID" "python3 ~/repos/stretch_production_tools_ii/utils/assign_random_ros_domain_id.py --remove || true"; then
        errors+=("[9/12] Remove ROS domain ID")
    fi
else
    finish_progress "[9/12] ROS domain ID script not found — skipped"
    warn "assign_random_ros_domain_id.py not found. Skipping."
fi

# -------------------------------------------------------
# Step 10: Remove Sunshine remote desktop config
# -------------------------------------------------------
section "Step 10 / 12 — Removing Sunshine config"

if ! run_step "[10/12] Remove Sunshine config" "rm -rf ~/.config/sunshine/ 2>/dev/null || true"; then
    errors+=("[10/12] Remove Sunshine config")
fi

# -------------------------------------------------------
# Step 11: Uninstall production tools Python package
# -------------------------------------------------------
section "Step 11 / 12 — Uninstalling production tools"

if ! run_step "[11/12] Uninstall production tools" "pip3 uninstall -y hello-robot-stretch-production_tools 2>/dev/null || true; pip3 uninstall -y hello-robot-stretch-production-tools-ii 2>/dev/null || true"; then
    errors+=("[11/12] Uninstall production tools")
fi

# -------------------------------------------------------
# Step 12: Remove production repos in ~/repos
#   Preserved: stretch4_body, stretch4_urdf, stretch4_flying_gripper
#   Deleted:   everything else (incl. stretch_production_data_ii,
#              stretch_production_tools_ii, stretch_firmware_ii, etc.)
#   Note:      ~/stretch_install is intentionally left untouched.
# -------------------------------------------------------
section "Step 12 / 12 — Removing production repos"

REPO_DEL_CMD="find ~/repos -maxdepth 1 -mindepth 1"
REPO_DEL_CMD="$REPO_DEL_CMD ! -name 'stretch4_body'"
REPO_DEL_CMD="$REPO_DEL_CMD ! -name 'stretch4_urdf'"
REPO_DEL_CMD="$REPO_DEL_CMD ! -name 'stretch4_flying_gripper'"
REPO_DEL_CMD="$REPO_DEL_CMD -exec rm -rf {} +"

if ! run_step "[12/12] Remove production repos in ~/repos" "$REPO_DEL_CMD"; then
    errors+=("[12/12] Remove repos")
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
