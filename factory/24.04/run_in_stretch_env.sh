#!/usr/bin/env bash
# Run a command inside the Stretch unified environment.
#
# The pixi environment provides Python, the build toolchain, and ROS 2 Jazzy
# (from RoboStack); the ament workspace is overlaid on top of it. Use this
# wrapper from systemd units and other non-interactive contexts, which do not
# read ~/.bashrc.
#
# Usage: run_in_stretch_env.sh <command> [args...]

set -e

STRETCH_PIXI_ENV="${STRETCH_PIXI_ENV:-$HOME/stretch4_install/stretch_venv/.pixi/envs/default}"

if [ ! -d "$STRETCH_PIXI_ENV" ]; then
    echo "ERROR: The unified environment $STRETCH_PIXI_ENV does not exist." >&2
    echo "Run $HOME/stretch4_install/stretch_venv/setup_venv.sh first." >&2
    exit 1
fi

export CONDA_PREFIX="$STRETCH_PIXI_ENV"
export PATH="$CONDA_PREFIX/bin:$PATH"
for f in "$CONDA_PREFIX/etc/conda/activate.d/"*.sh; do
    [ -f "$f" ] && source "$f"
done

if [ -f "$HOME/ament_ws/install/setup.bash" ]; then
    source "$HOME/ament_ws/install/setup.bash"
fi

exec "$@"
