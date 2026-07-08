#!/bin/bash
# This script installs essential background daemons for Stretch.
# When a new user is created and logs in for the first time, this script is optionally 
# triggered via the --auto-startup flag inside ~/.bashrc. It will execute in a new terminal 
# window to show the user the progress. After running successfully, it cleans up its own 
# auto-startup configuration from ~/.bashrc.
set -e

run_install() {
    set -e

    . /etc/hello-robot/hello-robot.conf
    export HELLO_FLEET_ID="${HELLO_FLEET_ID}"
    export HELLO_FLEET_PATH="${HOME}/stretch_user"

    local auto_start="${1:-true}"

    echo "Installing and starting Stretch Body Server daemon service"
    if [ "$auto_start" = "false" ]; then
        ~/.local/bin/stretch_body_server --install_daemon
    else
        ~/.local/bin/stretch_body_server --daemon
    fi

    echo "Installing and starting the Stretch Tray"
    ~/.local/bin/stretch_tray --install
    if [ "$auto_start" = "true" ]; then
        ~/.local/bin/stretch_tray --restart
    fi
}

if [ "$1" == "--auto-startup" ]; then
    if [ -n "$DISPLAY" ] && command -v gnome-terminal &> /dev/null; then
        gnome-terminal -- bash -c "$0 --in-terminal"
        exit 0
    else
        bash "$0" --in-terminal
        exit 0
    fi
fi

if [ "$1" == "--in-terminal" ]; then
    echo "========================================================================"
    echo "This background daemon auto-install script is running on your first login."
    echo "It will automatically configure and start the ROS services."
    echo "========================================================================"
    echo ""
    
    if run_install true 2>&1 | tee -a "$HOME/stretch_user/log/service_install_redirected.log"; then
        echo "Services installed correctly!"
        echo "Cleaning up auto-startup script from ~/.bashrc..."
        sed -i '/# Run service install once on first login/d' "$HOME/.bashrc"
        sed -i '\|bash ~/stretch4_install/factory/24.04/background_services_installer.sh --auto-startup &|d' "$HOME/.bashrc"
        sleep 3
    else
        echo ""
        echo "########################################################################"
        echo "FAILURE. Background daemons did not successfully install."
        echo "Please verify there are no errors in your environment, then install them"
        echo "manually by running:"
        echo ""
        echo "  bash ~/stretch4_install/factory/24.04/background_services_installer.sh"
        echo "########################################################################"
        echo ""
        read -p "Press Enter to close this window..."
    fi
    exit 0
fi

if [ "$USER" = "$(logname 2>/dev/null || echo "$USER")" ]; then
    run_install true
else
    run_install false
fi

