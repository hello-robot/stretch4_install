#!/usr/bin/env bash
# Script to update and sanitize ~/.bashrc for Stretch 4 ROS 2 and Virtual Environment

set -e

BASHRC="$HOME/.bashrc"

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
if ! grep -q "stretch_user/stretch_venv/bin/activate" "$BASHRC"; then
    echo "Appending unified ROS 2 & Virtual Environment setup block to ~/.bashrc..."
    cat << 'EOF' >> "$BASHRC"

# STRETCH ROS2 & VIRTUAL ENVIRONMENT SETUP
if [ -f /opt/ros/jazzy/setup.bash ]; then
    source /opt/ros/jazzy/setup.bash
fi
if [ -f ~/ament_ws/install/setup.bash ]; then
    source ~/ament_ws/install/setup.bash
fi
if [ -f /usr/share/colcon_cd/function/colcon_cd.sh ]; then
    source /usr/share/colcon_cd/function/colcon_cd.sh
fi
if [ -f ~/stretch_user/stretch_venv/bin/activate ]; then
    source ~/stretch_user/stretch_venv/bin/activate
    PY_VER=$(python3 -c "import sys; print(f'{sys.version_info.major}.{sys.version_info.minor}')")
    export PYTHONPATH=~/stretch_user/stretch_venv/lib/python${PY_VER}/site-packages:$PYTHONPATH
fi
EOF
else
    echo "ROS 2 and Virtual Environment setup block is already present in ~/.bashrc."
fi
