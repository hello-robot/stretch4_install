#!/bin/bash
set -o pipefail

cd $HOME/stretch4_install/factory/24.04

echo "Updating UDEV rules..."
# the environment variable $SETUP_FLEET_ID might be set by arguments, otherwise fallback to the conf file
if [ -z "$SETUP_FLEET_ID" ] && [ -f "/etc/hello-robot/hello-robot.conf" ]; then
    . /etc/hello-robot/hello-robot.conf
    SETUP_FLEET_ID=$HELLO_FLEET_ID
fi

if [ -n "$SETUP_FLEET_ID" ]; then
    # Fleet repo is already updated by system update, checking paths:
    FLEET_REPO=""
    if [ -d "$HOME/stretch_fleet_ii" ]; then
        FLEET_REPO="$HOME/stretch_fleet_ii"
    elif [ -d "$HOME/repos/stretch_fleet_ii" ]; then
        FLEET_REPO="$HOME/repos/stretch_fleet_ii"
    elif [ -d "$HOME/stretch_fleet" ]; then
        FLEET_REPO="$HOME/stretch_fleet"
    fi

    if [ -n "$FLEET_REPO" ]; then
        if [ -d "$FLEET_REPO/robots/$SETUP_FLEET_ID" ]; then
            echo "Copying updated robot configuration to /etc/hello-robot..."
            sudo cp -rf "$FLEET_REPO/robots/$SETUP_FLEET_ID" /etc/hello-robot/
        fi
    fi

    if [ -d "/etc/hello-robot/$SETUP_FLEET_ID/udev" ]; then
        sudo sh -c "cp /etc/hello-robot/$SETUP_FLEET_ID/udev/*.rules /etc/udev/rules.d 2>/dev/null || true"
        sudo udevadm control --reload
    fi
fi

echo "Fleet configuration completed successfully."
