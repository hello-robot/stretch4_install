#!/usr/bin/env bash
# Script to bootstrap or restore the Stretch 4 virtual environment

set -e

echo "===================================================="
echo "Bootstrapping Stretch 4 Python Virtual Environment"
echo "===================================================="

# 1. Ensure pixi is installed
export PATH="${HOME}/.pixi/bin:${PATH}"
if ! command -v pixi &> /dev/null; then
    echo "pixi not found in PATH. Attempting to install..."
    curl -fsSL https://pixi.sh/install.sh | sh
fi

# Double check pixi is now available
if ! command -v pixi &> /dev/null; then
    echo "ERROR: Failed to install or locate pixi. Please install it manually from https://pixi.sh."
    exit 1
fi

# 2. Synchronize dependencies using pixi
SCRIPT_DIR="$(dirname "$(readlink -f "$0")")"
echo "Synchronizing dependencies in $SCRIPT_DIR using pixi..."
cd "$SCRIPT_DIR"
pixi install

# 3. Install local development repositories in editable mode if they exist
# Note: Pixi handles pypi-dependencies in editable mode via pyproject.toml
# but we can also manually add them if needed.
if [ -d "$HOME/repos/stretch4_flying_gripper" ]; then
    echo "Installing stretch4_flying_gripper in editable mode..."
    pixi run pip install -e "$HOME/repos/stretch4_flying_gripper"
fi

if [ -d "$HOME/repos/stretch_tray" ]; then
    echo "Installing stretch_tray in editable mode..."
    pixi run pip install -e "$HOME/repos/stretch_tray"
fi

echo "===================================================="
echo "Unified environment successfully setup!"
echo "Location: $SCRIPT_DIR/.pixi/envs/default"
echo "===================================================="
