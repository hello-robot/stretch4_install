#!/bin/bash
set -e 

REDIRECT_LOGDIR="$HOME/stretch_user/log"
CREATE_USER=""
DEB_FILE=""
STRETCH_DEB_NAME="hello-robot-stretch4-system"
STRETCH_PREFIX="/opt/hello-robot/stretch4"
declare -a FORWARD_ARGS
OPTIND=1

while getopts ":l:u:d:" opt; do
  case $opt in
    l)
      if [[ -d $OPTARG ]]; then
          REDIRECT_LOGDIR=$OPTARG
          FORWARD_ARGS+=("-l" "$OPTARG")
      fi
      ;;
    u)
      CREATE_USER=$OPTARG
      ;;
    d)
      # Install the system package from a local .deb (built by stretch_create_deb_package.sh)
      # instead of from the apt repository
      if [[ ! -f $OPTARG ]]; then
          echo "Package file not found: $OPTARG" >&2
          exit 1
      fi
      DEB_FILE=$(readlink -f "$OPTARG")
      FORWARD_ARGS+=("-d" "$DEB_FILE")
      ;;
    \?)
      echo "Invalid option: -$OPTARG" >&2
      exit 1
      ;;
  esac
done

if [ -n "$CREATE_USER" ]; then
    if id "$CREATE_USER" &>/dev/null; then
        echo "User $CREATE_USER already exists."
        read -p "Continue running the rest of the script for the $CREATE_USER user? [y/N] " response
        if [[ ! "$response" =~ ^[Yy]$ ]]; then
            echo "Exiting."
            exit 1
        fi
    else
        echo "Creating admin user $CREATE_USER..."
        sudo useradd -m -s /bin/bash -G sudo "$CREATE_USER"
        
        echo "Please set a password for the new user $CREATE_USER:"
        if [ -t 0 ]; then
            sudo passwd "$CREATE_USER"
        else
            echo "Non-interactive environment detected, setting default password for $CREATE_USER..."
            echo "$CREATE_USER:$CREATE_USER" | sudo chpasswd
        fi
    fi
    
    echo "Copying stretch4_install to the new user's home directory..."
    SCRIPT_DIR="$(dirname "$(readlink -f "$0")")"
    sudo mkdir -p "/home/$CREATE_USER/stretch4_install"
    sudo cp -r "$SCRIPT_DIR/." "/home/$CREATE_USER/stretch4_install/"
    sudo chown -R "$CREATE_USER:$CREATE_USER" "/home/$CREATE_USER/stretch4_install"
    
    echo "Switching execution to $CREATE_USER..."
    exec sudo -i -u "$CREATE_USER" bash -c "cd \"/home/$CREATE_USER/stretch4_install\" && IS_SECONDARY_USER_INSTALL=1 \"/home/$CREATE_USER/stretch4_install/stretch_new_user_install.sh\" ${FORWARD_ARGS[*]}"
fi
REDIRECT_LOGFILE="$REDIRECT_LOGDIR/stretch_new_user_install.`date '+%Y%m%d%H%M'`_redirected.txt"


function on_failure {
    local failed_line=$1
    local failed_command=$2

    echo ""
    echo "#############################################"
    echo "FAILURE. INSTALL DID NOT COMPLETE."
    echo "Failed at line: $failed_line"
    echo "Failed command: $failed_command"
    echo "Check $REDIRECT_LOGFILE for more details."
    echo "#############################################"
    echo ""
}

trap 'on_failure $LINENO "$BASH_COMMAND"' ERR

# TODO: no prompting in scripts included inside new_robot_install
# SCRIPT_DIR="$(dirname "$(readlink -f "$0")")"
# "$SCRIPT_DIR/factory/setup_git.sh"

source /etc/os-release
factory_osdir="$VERSION_ID"
if [[ ! $factory_osdir =~ ^(24.04)$ ]]; then
    echo "Could not identify OS. Please contact Hello Robot Support."
    exit 1
fi

if [ "$HELLO_FLEET_ID" ]; then
    UPDATING=true
    echo "###########################################"
    echo "UPDATING USER SOFTWARE"
    echo "###########################################"
else
    UPDATING=false
    . /etc/hello-robot/hello-robot.conf
    export HELLO_FLEET_ID="${HELLO_FLEET_ID}"
    export HELLO_FLEET_PATH="${HOME}/stretch_user"
    echo "###########################################"
    echo "NEW INSTALLATION OF USER SOFTWARE"
    echo "###########################################"
    echo "Update ~/.bashrc dotfile..."
    echo "" >> ~/.bashrc
    echo "######################" >> ~/.bashrc
    echo "# STRETCH BASHRC SETUP" >> ~/.bashrc
    echo "######################" >> ~/.bashrc
    echo "export HELLO_FLEET_PATH=${HOME}/stretch_user" >> ~/.bashrc
    echo "export HELLO_FLEET_ID=${HELLO_FLEET_ID}">> ~/.bashrc
    echo "export PATH=\${PATH}:~/.local/bin" >> ~/.bashrc
    echo "export LRS_LOG_LEVEL=None #Debug" >> ~/.bashrc
    echo "export PYTHONWARNINGS='ignore:setup.py install is deprecated,ignore:Invalid dash-separated options,ignore:pkg_resources is deprecated as an API,ignore:Usage of dash-separated'" >> ~/.bashrc
    if [[ $factory_osdir = "24.04" ]]; then
        echo "export PIP_BREAK_SYSTEM_PACKAGES=1" >> ~/.bashrc
        echo "export RMW_IMPLEMENTATION=rmw_zenoh_cpp" >> ~/.bashrc
        echo "source $STRETCH_PREFIX/setup.bash" >> ~/.bashrc
    fi
fi
if [[ $factory_osdir = "24.04" ]] && ! grep -qxF "source $STRETCH_PREFIX/setup.bash" ~/.bashrc; then
    echo "Update ~/.bashrc dotfile to source $STRETCH_DEB_NAME..."
    if grep -qxF "source /opt/ros/jazzy/setup.bash" ~/.bashrc; then
        # Keep it ahead of any workspace overlay sourced later in the file
        sed -i "\|^source /opt/ros/jazzy/setup.bash\$|a source $STRETCH_PREFIX/setup.bash" ~/.bashrc
    else
        echo "source $STRETCH_PREFIX/setup.bash" >> ~/.bashrc
    fi
fi


echo "Prevent screen dimming..."
gsettings set org.gnome.desktop.session idle-delay 0 &> /dev/null || true
gsettings set org.gnome.settings-daemon.plugins.power sleep-inactive-ac-timeout 0 &> /dev/null || true
gsettings set org.gnome.settings-daemon.plugins.power idle-dim false &> /dev/null || true

echo "Creating repos and stretch_user directories..."
mkdir -p ~/.local/bin
mkdir -p ~/repos
mkdir -p ~/stretch_user
mkdir -p ~/stretch_user/log
mkdir -p ~/stretch_user/debug
mkdir -p ~/stretch_user/maps
mkdir -p ~/stretch_user/models

echo "Setting up user copy of robot factory data (if not already there)..."
if [ "$UPDATING" = true ]; then
    echo "~/stretch_user/$HELLO_FLEET_ID data present: not updating"
else
    if [ "$USER" != "hello-robot" ]; then
        echo "Non-hello-robot user detected. Attempting to copy calibration data from hello-robot account..."
        SCRIPT_DIR="$(dirname "$(readlink -f "$0")")"
        if [ -f "$SCRIPT_DIR/stretch_copy_calibration.sh" ] && sudo "$SCRIPT_DIR/stretch_copy_calibration.sh" --force -u "$USER"; then
            echo "Successfully copied calibration data from hello-robot."
        else
            echo "Failed to copy hello-robot calibration data or copy utility not found. Falling back to factory defaults..."
            sudo cp -rf /etc/hello-robot/$HELLO_FLEET_ID $HOME/stretch_user
            sudo chown -R $USER:$USER $HOME/stretch_user/$HELLO_FLEET_ID
            chmod a-w $HOME/stretch_user/$HELLO_FLEET_ID/udev/*.rules
        fi
    else
        sudo cp -rf /etc/hello-robot/$HELLO_FLEET_ID $HOME/stretch_user
        sudo chown -R $USER:$USER $HOME/stretch_user/$HELLO_FLEET_ID
        chmod a-w $HOME/stretch_user/$HELLO_FLEET_ID/udev/*.rules
    fi
fi
chmod -R a-x,o-w,+X ~/stretch_user

# TODO: Figure out which of these are needed in Stretch 4
# echo "Setting up this user to start the robot's code automatically on boot..."
# mkdir -p ~/.config/autostart
# cp ~/stretch4_install/factory/$factory_osdir/hello_robot_audio.desktop ~/.config/autostart/

echo "Setting up stretch_gamepad_teleop to run on startup..."
mkdir -p ~/.config/autostart
cat << 'EOF' > ~/.config/autostart/stretch_gamepad_teleop.desktop
[Desktop Entry]
Type=Application
Exec=gnome-terminal -- bash -ic "sleep 60 && stretch_gamepad_teleop"
Hidden=false
NoDisplay=false
X-GNOME-Autostart-enabled=true
Name[en_US]=Stretch Gamepad Teleop
Name=Stretch Gamepad Teleop
Comment=Start Stretch Gamepad Teleop
EOF
chmod +x ~/.config/autostart/stretch_gamepad_teleop.desktop

echo "Updating media assets..."
sudo cp $HOME/stretch4_install/factory/$factory_osdir/stretch_about.png /etc/hello-robot

echo "Install uv"
curl -LsSf https://astral.sh/uv/install.sh | sh &>> $REDIRECT_LOGFILE

echo "Adding user to the dialout group to access Arduino..."
sudo adduser $USER dialout >> $REDIRECT_LOGFILE
echo "Adding user to the plugdev group to access serial..."
sudo adduser $USER plugdev >> $REDIRECT_LOGFILE
echo "Adding user to the input group to access input devices (e.g. gamepad)..."
sudo adduser $USER input >> $REDIRECT_LOGFILE
echo "Adding user to the audio group to access audio (needed for RDP and recording)..."
sudo adduser $USER audio >> $REDIRECT_LOGFILE
echo "Adding user to the video group..."
sudo adduser $USER video >> $REDIRECT_LOGFILE
echo "Adding user to the render group..."
sudo adduser $USER render >> $REDIRECT_LOGFILE
echo "Adding user to the users group..."
sudo adduser $USER users >> $REDIRECT_LOGFILE
echo ""

if [[ $factory_osdir = "24.04" ]]; then
    echo "Disabling audio suppression"
    python3 $HOME/stretch4_install/factory/$factory_osdir/hello_robot_audio_disable_suspension.py &>> $REDIRECT_LOGFILE
    
    echo "###########################################"
    echo "INSTALLATION OF $STRETCH_DEB_NAME"
    echo "###########################################"
    SCRIPT_DIR="$(dirname "$(readlink -f "$0")")"
    source "$SCRIPT_DIR/factory/$factory_osdir/stretch_apt_common.sh"
    apt_configure
    echo "Add apt sources (universe, Intel graphics, ROS 2, NodeSource)"
    add_stretch_apt_sources &>> $REDIRECT_LOGFILE
    preseed_debconf
    if [ -n "$DEB_FILE" ]; then
        echo "Install $DEB_FILE (this might take a while)"
        retry_cmd sudo apt-get install -y "$DEB_FILE" &>> $REDIRECT_LOGFILE
    else
        candidate=$(apt-cache policy $STRETCH_DEB_NAME | sed -n 's/ *Candidate: //p')
        if [[ -z $candidate || $candidate = "(none)" ]]; then
            echo "$STRETCH_DEB_NAME is not available from any configured apt repository."
            echo "Add the Hello Robot apt repository, or pass a local package with -d <file.deb>."
            exit 1
        fi
        echo "Install $STRETCH_DEB_NAME $candidate (this might take a while)"
        retry_cmd sudo apt-get install -y $STRETCH_DEB_NAME &>> $REDIRECT_LOGFILE
    fi

    echo "Remove user level copies of the Stretch pip packages (now provided by $STRETCH_DEB_NAME)"
    export PIP_BREAK_SYSTEM_PACKAGES=1
    for pkg in hello-robot-stretch4-urdf hello-robot-stretch4-flying-gripper hello-robot-stretch4-body \
               hello-robot-stretch4-tray hello-robot-stretch4-pyhesai-wrapper hello-robot-stretch4-kinematics; do
        location=$(python3 -m pip show $pkg 2> /dev/null | sed -n 's/^Location: //p')
        if [[ $location == $HOME/.local/* ]]; then
            python3 -m pip uninstall -y $pkg &>> $REDIRECT_LOGFILE
        fi
    done

    # # TODO: doesn't work in a fresh install currently, needs investigation
    # echo "###########################################"
    # echo "INSTALLING SERVICES"
    # echo "###########################################"
    # if [ -z "$IS_SECONDARY_USER_INSTALL" ]; then
    #     echo "Install the services"
    #     "$HOME/stretch4_install/factory/$factory_osdir/background_services_installer.sh" &>> $REDIRECT_LOGFILE
    # else
    #     echo "========================================================================"
    #     echo "This installation was run automatically to run on a different user account."
    #     if [[ $factory_osdir = "24.04" ]]; then
    #         echo "Configuring automatic service installation on first login."
    #         echo -e "\n# Run service install once on first login\nbash ~/stretch4_install/factory/24.04/background_services_installer.sh --auto-startup &" >> "$HOME/.bashrc"
    #     fi
    #     echo "========================================================================"
    #     echo ""
    # fi
fi




echo ""
echo "###########################################"
echo "CREATING ROS WORKSPACE"
echo "###########################################"
# The prebuilt ROS 2 packages come from $STRETCH_DEB_NAME. ~/ament_ws is an overlay holding
# stretch4_web_teleop, which runs from source with this robot's certificates. To build the
# whole workspace from source instead, run stretch_update_ros_workspace.sh.
if [[ $factory_osdir = "24.04" ]]; then
    AMENT_WSDIR="$HOME/ament_ws"
    export COLCON_EXTENSION_BLOCKLIST=colcon_core.event_handler.desktop_notification
    source $STRETCH_PREFIX/setup.bash

    if [[ -d $AMENT_WSDIR ]]; then
        AMENT_WSDIR_BACKUP="${AMENT_WSDIR}_backup_`date '+%Y%m%d%H%M'`"
        echo "Moving the existing workspace to $AMENT_WSDIR_BACKUP..."
        mv "$AMENT_WSDIR" "$AMENT_WSDIR_BACKUP"
    fi
    echo "Creating the workspace at $AMENT_WSDIR..."
    mkdir -p $AMENT_WSDIR/src
    cp -a $STRETCH_PREFIX/src/stretch4_web_teleop $AMENT_WSDIR/src/

    echo "Generating web interface certs..."
    cd $AMENT_WSDIR/src/stretch4_web_teleop/certificates
    CAROOT=`pwd` mkcert --install &>> $REDIRECT_LOGFILE
    mkdir -p ~/.local/share/mkcert
    rm -rf ~/.local/share/mkcert/root*
    cp root* ~/.local/share/mkcert
    mkcert ${HELLO_FLEET_ID} ${HELLO_FLEET_ID}.local ${HELLO_FLEET_ID}.dev localhost 127.0.0.1 0.0.0.0 ::1 &>> $REDIRECT_LOGFILE
    cd $AMENT_WSDIR/src/stretch4_web_teleop
    touch .env
    echo certfile=${HELLO_FLEET_ID}+6.pem >> .env
    echo keyfile=${HELLO_FLEET_ID}+6-key.pem >> .env

    echo "Compile the workspace..."
    cd $AMENT_WSDIR
    colcon build --symlink-install &>> $REDIRECT_LOGFILE

    echo "Update ~/.bashrc dotfile to source workspace..."
    grep -qxF "source $AMENT_WSDIR/install/setup.bash" ~/.bashrc || echo "source $AMENT_WSDIR/install/setup.bash" >> ~/.bashrc
    grep -qxF "source /usr/share/colcon_cd/function/colcon_cd.sh" ~/.bashrc || echo "source /usr/share/colcon_cd/function/colcon_cd.sh" >> ~/.bashrc
fi
