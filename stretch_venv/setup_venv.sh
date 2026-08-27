#!/usr/bin/env bash
# Script to bootstrap or restore the Stretch 4 unified environment.
#
# This environment contains EVERYTHING: Python, the build toolchain, and ROS 2
# Jazzy itself (from RoboStack, https://robostack.github.io). Nothing ROS
# related is installed via apt, and /opt/ros is not used.

set -e

echo "===================================================="
echo "Bootstrapping Stretch 4 Unified Environment"
echo "  (Python + build tools + ROS 2 Jazzy via RoboStack)"
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

# 2. Raise the open file limit before installing.
#
# pixi's package cache (rattler) holds a lock file open per package while it
# fetches and links. Now that ROS 2 is in here the environment is ~950 packages,
# which exceeds the default 1024 soft limit and fails partway through with:
#
#   failed to open cache metadata file: '.../rattler/cache/pkgs/<pkg>.lock'
#   No file descriptors available (os error 24)
#
# The soft limit can be raised up to the hard limit without privileges.
DESIRED_NOFILE=65536
SOFT_NOFILE="$(ulimit -S -n)"
HARD_NOFILE="$(ulimit -H -n)"
if [ "$HARD_NOFILE" != "unlimited" ] && [ "$DESIRED_NOFILE" -gt "$HARD_NOFILE" ]; then
    DESIRED_NOFILE="$HARD_NOFILE"
fi
if [ "$SOFT_NOFILE" != "unlimited" ] && [ "$SOFT_NOFILE" -lt "$DESIRED_NOFILE" ]; then
    if ulimit -S -n "$DESIRED_NOFILE" 2>/dev/null; then
        echo "Raised open file limit from $SOFT_NOFILE to $(ulimit -S -n) for pixi."
    else
        echo "WARNING: could not raise the open file limit above $SOFT_NOFILE."
        echo "         'pixi install' may fail with 'No file descriptors available'."
    fi
fi

# 3. Synchronize dependencies using pixi
SCRIPT_DIR="$(dirname "$(readlink -f "$0")")"
echo "Synchronizing dependencies in $SCRIPT_DIR using pixi..."
echo "(ROS 2 Jazzy is ~1.5GB of downloads on a first install; this takes a while.)"
cd "$SCRIPT_DIR"
pixi install

# 4. Install local development repositories in editable mode if they exist
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

# 5. Verify the environment. In particular, assert NumPy 2: RoboStack ships both
# a numpy-1.26 and a numpy-2 build variant of every ROS package, and silently
# solving back to the numpy-1.26 variants is the main way this environment can
# regress. Fail loudly here rather than at runtime.
echo "Verifying the environment..."
pixi run python - <<'PYCHECK'
import sys

failures = []

import numpy
print(f"  python  {sys.version.split()[0]}")
print(f"  numpy   {numpy.__version__}  ({numpy.__file__})")
if int(numpy.__version__.split(".")[0]) < 2:
    failures.append(
        f"numpy {numpy.__version__} is installed, but NumPy 2 is required. "
        "Pixi has most likely selected RoboStack's np126py312* build variants; "
        "check the 'numpy' and 'ros2-distro-mutex' constraints in pyproject.toml."
    )

for mod in ("rclpy", "cv_bridge", "tf_transformations", "scipy", "cv2", "trimesh"):
    try:
        __import__(mod)
    except Exception as exc:
        failures.append(f"failed to import {mod}: {exc}")
    else:
        print(f"  {mod} OK")

if failures:
    print("\nENVIRONMENT VERIFICATION FAILED:")
    for f in failures:
        print(f"  - {f}")
    sys.exit(1)
PYCHECK

# ROS 2 must resolve to the pixi environment, not to a stray /opt/ros install.
ROS2_BIN="$(pixi run bash -c 'command -v ros2')"
echo "  ros2    $ROS2_BIN"
case "$ROS2_BIN" in
    "$SCRIPT_DIR/.pixi/envs/default/bin/ros2") ;;
    *)
        echo "ERROR: 'ros2' resolved to $ROS2_BIN instead of the pixi environment."
        exit 1
        ;;
esac
echo "  ROS_DISTRO=$(pixi run bash -c 'echo $ROS_DISTRO')"

echo "===================================================="
echo "Unified environment successfully setup!"
echo "Location: $SCRIPT_DIR/.pixi/envs/default"
echo "===================================================="
