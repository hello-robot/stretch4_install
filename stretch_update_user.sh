#!/bin/bash
# Update this user's Stretch software: audio settings and the unified
# Python/ROS 2 environment. Safe to re-run at any time.
#
# By default the Hello Robot Python packages come from PyPI, which is what most
# users want. With --developer they are instead cloned into ~/repos and
# installed into the environment in editable mode, so changes to the source are
# picked up without reinstalling.
set -e

SCRIPT_DIR="$(dirname "$(readlink -f "$0")")"
export PATH="${HOME}/.pixi/bin:${PATH}"

REDIRECT_LOGDIR="$HOME/stretch_user/log"
DEVELOPER=false
GIT_REMOTE="https://github.com/hello-robot"

show_usage() {
    echo "Usage: $0 [options]"
    echo
    echo "Options:"
    echo "  -d, --developer    Clone the Hello Robot packages into ~/repos and install"
    echo "                     them into the environment in editable mode, instead of"
    echo "                     using the PyPI releases"
    echo "      --ssh          Clone over SSH (git@github.com:hello-robot) rather than"
    echo "                     HTTPS. Only meaningful with --developer"
    echo "  -l, --log-dir DIR  Directory to write the install log to"
    echo "                     (default: ~/stretch_user/log)"
    echo "  -h, --help         Show this help message"
    exit 0
}

while [[ $# -gt 0 ]]; do
    case "$1" in
        -l|--log-dir)
            if [ -z "$2" ]; then
                echo "Error: --log-dir requires an argument." >&2
                exit 1
            fi
            if [ -d "$2" ]; then
                REDIRECT_LOGDIR="$2"
            fi
            shift 2
            ;;
        -d|--developer)
            DEVELOPER=true
            shift
            ;;
        --ssh)
            GIT_REMOTE="git@github.com:hello-robot"
            shift
            ;;
        -h|--help)
            show_usage
            ;;
        *)
            echo "Unknown option: $1" >&2
            exit 1
            ;;
    esac
done

source /etc/os-release
factory_osdir="$VERSION_ID"
if [[ ! $factory_osdir =~ ^(24.04)$ ]]; then
    echo "Could not identify OS. Please contact Hello Robot Support."
    exit 1
fi

mkdir -p "$REDIRECT_LOGDIR"
REDIRECT_LOGFILE="$REDIRECT_LOGDIR/stretch_update_user.`date '+%Y%m%d%H%M'`_redirected.txt"

function on_failure {
    local failed_line=$1
    local failed_command=$2

    echo ""
    echo "#############################################"
    echo "FAILURE. UPDATING USER SOFTWARE DID NOT COMPLETE."
    echo "Failed at line: $failed_line"
    echo "Failed command: $failed_command"
    echo "Check $REDIRECT_LOGFILE for more details."
    echo "#############################################"
    echo ""
}

trap 'on_failure $LINENO "$BASH_COMMAND"' ERR

echo "Disabling audio suppression"
python3 "$SCRIPT_DIR/factory/$factory_osdir/hello_robot_audio_disable_suspension.py" &>> $REDIRECT_LOGFILE

echo "###########################################"
echo "CREATING AND SYNCHRONIZING STRETCH PYTHON VIRTUAL ENVIRONMENT"
echo "###########################################"
# Call the dedicated setup_venv.sh script to handle virtual environment and package installation
bash "$SCRIPT_DIR/stretch_venv/setup_venv.sh" &>> $REDIRECT_LOGFILE

if [ "$DEVELOPER" = true ]; then
    echo "###########################################"
    echo "INSTALLING HELLO ROBOT PACKAGES FROM SOURCE"
    echo "###########################################"

    # The Hello Robot packages are declared once, in the [project] dependencies
    # of stretch_venv/pyproject.toml. Each PyPI name maps to a repository by
    # dropping the distribution prefix and swapping dashes for underscores:
    #   hello-robot-stretch4-flying-gripper -> hello-robot/stretch4_flying_gripper
    PKG_PREFIX="hello-robot-stretch4-"
    mapfile -t PYPI_PACKAGES < <(
        awk '/^\[project\]/ {in_project=1; next} /^\[/ {in_project=0} in_project' \
            "$SCRIPT_DIR/stretch_venv/pyproject.toml" \
            | grep -oE "\"${PKG_PREFIX}[a-z0-9-]+\"" | tr -d '"'
    )
    if [ ${#PYPI_PACKAGES[@]} -eq 0 ]; then
        echo "ERROR: found no ${PKG_PREFIX}* packages in stretch_venv/pyproject.toml."
        exit 1
    fi

    mkdir -p "$HOME/repos"
    for pkg in "${PYPI_PACKAGES[@]}"; do
        repo="stretch4_${pkg#"$PKG_PREFIX"}"
        repo="${repo//-/_}"
        repo_dir="$HOME/repos/$repo"

        if [ -d "$repo_dir" ]; then
            echo "$repo is already cloned at $repo_dir, leaving it untouched."
        else
            echo "Cloning $repo into $repo_dir..."
            git clone "$GIT_REMOTE/$repo.git" "$repo_dir" &>> $REDIRECT_LOGFILE
        fi

        echo "Installing $repo in editable mode..."
        # pip must run inside the pixi environment so the editable install lands
        # there rather than in the system Python.
        (cd "$SCRIPT_DIR/stretch_venv" && pixi run pip install -e "$repo_dir") &>> $REDIRECT_LOGFILE
    done

    echo ""
    echo "Editable installs live in ~/repos. Note that a later 'pixi install'"
    echo "may restore the PyPI releases; re-run this script with --developer to"
    echo "put the editable installs back."
fi
