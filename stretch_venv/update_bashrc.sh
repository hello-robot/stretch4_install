#!/usr/bin/env bash
# Script to update and sanitize ~/.bashrc for the Stretch 4 unified environment.
#
# ROS 2 Jazzy lives inside the pixi environment (RoboStack), so activating that
# environment is what makes ROS available. There is no /opt/ros to source.

set -e

BASHRC="$HOME/.bashrc"

if [ ! -f "$BASHRC" ]; then
    echo "No ~/.bashrc file found. Creating one..."
    touch "$BASHRC"
fi

echo "Sanitizing ~/.bashrc of old duplicate entries..."
TEMP_BASHRC=$(mktemp)

# Read the file and comment out redundant/duplicate hardcoded lines. The
# /opt/ros/jazzy line is now always wrong: sourcing the apt ROS install shadows
# the RoboStack one in AMENT_PREFIX_PATH and drags in the system numpy.
while IFS= read -r line || [[ -n "$line" ]]; do
    if [[ "$line" =~ ^[[:space:]]*source[[:space:]]+/opt/ros/jazzy/setup.bash ]] || \
       [[ "$line" =~ ^[[:space:]]*source[[:space:]]+.*ament_ws.*/install/setup.bash ]] || \
       [[ "$line" =~ ^[[:space:]]*source[[:space:]]+/usr/share/colcon_cd/function/colcon_cd.sh ]] || \
       [[ "$line" =~ stretch_install/stretch_venv ]]; then
        echo "# Commented out by Stretch installer to use unified setup:" >> "$TEMP_BASHRC"
        echo "# $line" >> "$TEMP_BASHRC"
    else
        echo "$line" >> "$TEMP_BASHRC"
    fi
done < "$BASHRC"

mv "$TEMP_BASHRC" "$BASHRC"

# Append the unified conditional block if it is not already present
if ! grep -q "stretch4_install/stretch_venv/.pixi" "$BASHRC"; then
    echo "Appending unified ROS 2 & Virtual Environment setup block to ~/.bashrc..."
    cat << 'EOF' >> "$BASHRC"

# STRETCH ROS2 & UNIFIED ENVIRONMENT SETUP
# The pixi environment provides Python, the build toolchain, AND ROS 2 Jazzy
# (from RoboStack). It must be activated before the ament workspace overlay is
# sourced, because that overlay depends on the ROS 2 install underneath it.
STRETCH_PIXI_ENV="$HOME/stretch4_install/stretch_venv/.pixi/envs/default"
if [ -d "$STRETCH_PIXI_ENV" ]; then
    export PATH="$STRETCH_PIXI_ENV/bin:$PATH"
    export CONDA_PREFIX="$STRETCH_PIXI_ENV"
    # Source conda activation scripts if they exist. This is what sets
    # ROS_DISTRO, AMENT_PREFIX_PATH and friends.
    for f in "$CONDA_PREFIX/etc/conda/activate.d/"*.sh; do
        if [ -f "$f" ]; then source "$f"; fi
    done
fi

# Overlay the locally built ament workspace on top of the ROS 2 install.
if [ -f ~/ament_ws/install/setup.bash ]; then
    source ~/ament_ws/install/setup.bash
fi

# colcon_cd now ships inside the pixi environment rather than in /usr/share.
if [ -n "$CONDA_PREFIX" ] && [ -f "$CONDA_PREFIX/share/colcon_cd/function/colcon_cd.sh" ]; then
    source "$CONDA_PREFIX/share/colcon_cd/function/colcon_cd.sh"
fi
unset STRETCH_PIXI_ENV
EOF
else
    echo "ROS 2 and Virtual Environment setup block is already present in ~/.bashrc."
fi
