#!/bin/bash
# Update this user's Stretch software: audio settings and the unified
# Python/ROS 2 environment. Safe to re-run at any time.
set -e

SCRIPT_DIR="$(dirname "$(readlink -f "$0")")"

source /etc/os-release
factory_osdir="$VERSION_ID"
if [[ ! $factory_osdir =~ ^(24.04)$ ]]; then
    echo "Could not identify OS. Please contact Hello Robot Support."
    exit 1
fi

REDIRECT_LOGDIR="$HOME/stretch_user/log"
while getopts l: opt; do
    case $opt in
        l)
            if [[ -d $OPTARG ]]; then
                REDIRECT_LOGDIR=$OPTARG
            fi
            ;;
    esac
done

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
