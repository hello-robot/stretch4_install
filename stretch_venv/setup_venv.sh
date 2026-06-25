#!/usr/bin/env bash
# Script to bootstrap or restore the Stretch 4 virtual environment

set -e

echo "===================================================="
echo "Bootstrapping Stretch 4 Python Virtual Environment"
echo "===================================================="

# 1. Ensure uv is installed
export PATH="${HOME}/.local/bin:${PATH}"
if ! command -v uv &> /dev/null; then
    echo "uv not found in PATH. Attempting to install..."
    curl -LsSf https://astral.sh/uv/install.sh | sh
fi

# Double check uv is now available
if ! command -v uv &> /dev/null; then
    echo "ERROR: Failed to install or locate uv. Please install it manually from https://astral.sh/uv."
    exit 1
fi

# 2. Create the virtual environment directory
echo "Creating virtual environment at ~/stretch_user/stretch_venv..."
mkdir -p ~/stretch_user
uv venv ~/stretch_user/stretch_venv --system-site-packages --seed --clear

# 3. Synchronize dependencies using project config
SCRIPT_DIR="$(dirname "$(readlink -f "$0")")"
echo "Synchronizing dependencies from $SCRIPT_DIR/pyproject.toml..."
export UV_PROJECT_ENVIRONMENT="$HOME/stretch_user/stretch_venv"
cd "$SCRIPT_DIR"
uv sync --frozen

# 4. Install local development repositories in editable mode if they exist
if [ -d "$HOME/repos/stretch4_flying_gripper" ]; then
    echo "Reinstalling stretch4_flying_gripper in editable mode..."
    uv pip install -p "$UV_PROJECT_ENVIRONMENT" -e "$HOME/repos/stretch4_flying_gripper"
fi

if [ -d "$HOME/repos/stretch_tray" ]; then
    echo "Reinstalling stretch_tray in editable mode..."
    uv pip install -p "$UV_PROJECT_ENVIRONMENT" -e "$HOME/repos/stretch_tray"
fi

echo "===================================================="
echo "Virtual environment successfully setup!"
echo "Location: ~/stretch_user/stretch_venv"
echo "===================================================="
