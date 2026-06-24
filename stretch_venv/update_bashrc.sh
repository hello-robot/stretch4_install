#!/usr/bin/env bash
# Script to update and sanitize ~/.bashrc for Stretch 4 ROS 2 and Virtual Environment

set -e

BASHRC="$HOME/.bashrc"
INSTALL_ROOT="$(dirname "$(dirname "$(readlink -f "$0")")")"
VENV_PATH_REL="${INSTALL_ROOT#$HOME/}/stretch_venv"

if [ ! -f "$BASHRC" ]; then
    echo "No ~/.bashrc file found. Creating one..."
    touch "$BASHRC"
fi

echo "Sanitizing ~/.bashrc of old duplicate entries..."
TEMP_BASHRC=$(mktemp)

# Read the file and comment out redundant/duplicate hardcoded lines
while IFS= read -r line || [[ -n "$line" ]]; do
    if [[ "$line" =~ ^[[:space:]]*source[[:space:]]+/opt/ros/jazzy/setup.bash ]] || \
       [[ "$line" =~ ^[[:space:]]*source[[:space:]]+.*ament_ws.*/install/setup.bash ]] || \
       [[ "$line" =~ ^[[:space:]]*source[[:space:]]+/usr/share/colcon_cd/function/colcon_cd.sh ]]; then
        echo "# Commented out by Stretch installer to use unified setup:" >> "$TEMP_BASHRC"
        echo "# $line" >> "$TEMP_BASHRC"
    else
        echo "$line" >> "$TEMP_BASHRC"
    fi
done < "$BASHRC"

mv "$TEMP_BASHRC" "$BASHRC"

# Append the unified conditional block if it is not already present
if ! grep -q "$VENV_PATH_REL/.pixi" "$BASHRC"; then
    echo "Appending unified ROS 2 & Virtual Environment setup block to ~/.bashrc..."
    cat << EOF >> "$BASHRC"

# STRETCH ROS2 & UNIFIED ENVIRONMENT SETUP
if [ -f /opt/ros/jazzy/setup.bash ]; then
    source /opt/ros/jazzy/setup.bash
fi
if [ -f ~/ament_ws/install/setup.bash ]; then
    source ~/ament_ws/install/setup.bash
fi
if [ -f /usr/share/colcon_cd/function/colcon_cd.sh ]; then
    source /usr/share/colcon_cd/function/colcon_cd.sh
fi

# Activate the Pixi environment if it exists
PIXI_ENV_ACTIVATE="\$HOME/$VENV_PATH_REL/.pixi/envs/default/etc/conda/activate.d/activate.sh"
# Alternatively, we can use 'pixi shell' logic or just source the bin/activate if it's a conda env
# The most robust way is to source the activate script provided by pixi/conda
if [ -d "\$HOME/$VENV_PATH_REL/.pixi/envs/default" ]; then
    export PATH="\$HOME/$VENV_PATH_REL/.pixi/envs/default/bin:\$PATH"
    export CONDA_PREFIX="\$HOME/$VENV_PATH_REL/.pixi/envs/default"
    # Source conda activation scripts if they exist
    for f in "\$CONDA_PREFIX/etc/conda/activate.d/"*.sh; do
        if [ -f "\$f" ]; then source "\$f"; fi
    done
fi
EOF
else
    echo "ROS 2 and Virtual Environment setup block is already present in ~/.bashrc."
fi
