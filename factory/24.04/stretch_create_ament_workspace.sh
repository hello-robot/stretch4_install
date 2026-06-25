#!/bin/bash
set -e
export COLCON_EXTENSION_BLOCKLIST=colcon_core.event_handler.desktop_notification


REDIRECT_LOGDIR="$HOME/stretch_user/log"
AMENT_WSDIR="$HOME/ament_ws"
while getopts l:w: opt; do
    case $opt in
        l)
            if [[ -d $OPTARG ]]; then
                REDIRECT_LOGDIR=$OPTARG
            fi
            ;;
        w)
            AMENT_WSDIR=$OPTARG
            ;;
    esac
done

REDIRECT_LOGFILE="$REDIRECT_LOGDIR/stretch_create_ament_workspace.`date '+%Y%m%d%H%M'`_redirected.txt"

function on_failure {
    local failed_line=$1
    local failed_command=$2

    echo ""
    echo "#############################################"
    echo "FAILURE. UPDATING ROS WORKSPACE DID NOT COMPLETE."
    echo "Failed at line: $failed_line"
    echo "Failed command: $failed_command"
    echo "Check $REDIRECT_LOGFILE for more details."
    echo "#############################################"
    echo ""
}

trap 'on_failure $LINENO "$BASH_COMMAND"' ERR

if [ ! -f "$HOME/stretch_user/stretch_venv/bin/activate" ]; then
    echo "ERROR: The virtual environment ~/stretch_user/stretch_venv does not exist."
    echo "Please run the setup script to generate it:"
    if [ -d "$HOME/stretch4_install" ]; then
        echo "    ~/stretch4_install/stretch_venv/setup_venv.sh"
    else
        echo "    ~/stretch_install/stretch_venv/setup_venv.sh"
    fi
    echo "Exiting."
    exit 1
fi

source "$HOME/stretch_user/stretch_venv/bin/activate"

echo "###########################################"
echo "CREATING JAZZY AMENT WORKSPACE at $AMENT_WSDIR"
echo "###########################################"

echo "Ensuring correct version of ROS is sourced..."
if [[ $ROS_DISTRO && ! $ROS_DISTRO = "jazzy" ]]; then
    echo "Cannot create workspace while a conflicting ROS version is sourced. Exiting."
    exit 1
fi
source /opt/ros/jazzy/setup.bash

if [[ -d $AMENT_WSDIR ]]; then
    echo "You are about to delete and replace the existing ament workspace. If you have any personal data in the workspace, please create a back up before proceeding."
    prompt_yes_no(){
    read -p "Do you want to continue? Press (y/n for yes/no): " x
    if [ $x = "n" ]; then
            echo "Exiting the script."
            exit 1
    elif [ $x = "y" ]; then
            echo "Continuing to create a new ament workspace."
    else
        echo "Press 'y' for yes or 'n' for no."
        prompt_yes_no
    fi
    }
    prompt_yes_no
fi

echo "Apt update..."
sudo apt-get --yes update >> $REDIRECT_LOGFILE
echo "Ensuring build tools are present (required for depthai-core/vcpkg)..."
sudo apt-get --yes install build-essential ninja-build >> $REDIRECT_LOGFILE

echo "Purging pip cache..."
export PATH="${HOME}/.local/bin:${PATH}"
uv pip cache purge &>> $REDIRECT_LOGFILE || true

. /etc/hello-robot/hello-robot.conf
export HELLO_FLEET_ID=$HELLO_FLEET_ID
export HELLO_FLEET_PATH=${HOME}/stretch_user
echo "Updating rosdep indices..."
rosdep update --include-eol-distros &>> $REDIRECT_LOGFILE

echo "Deleting $AMENT_WSDIR if it already exists..."
sudo rm -rf $AMENT_WSDIR
echo "Creating the workspace directory..."
mkdir -p $AMENT_WSDIR/src

# TODO:
# echo "Cloning Stretch AI's and symlinking its ROS packages..."
# cd "$HOME/repos"
# rm -rf ./stretch4_ai
# git clone https://github.com/hello-robot/stretch4_ai.git &>> $REDIRECT_LOGFILE
# ln -s "$HOME/repos/stretch4_ai/src/stretch_ros2_bridge" "$AMENT_WSDIR/src"

echo "Cloning the workspace's packages..."
cd $AMENT_WSDIR/src
vcs import --input ~/stretch4_install/factory/24.04/stretch_ros2_jazzy.repos &>> $REDIRECT_LOGFILE

echo "Cloning HesaiLidar_ROS_2.0 submodules..."
cd $AMENT_WSDIR/src/HesaiLidar_ROS_2.0
git submodule update --init --recursive &>> $REDIRECT_LOGFILE

echo "Cloning Luxonis depthai submodules..."
cd $AMENT_WSDIR/src/depthai-core
git submodule update --init --recursive &>> $REDIRECT_LOGFILE

echo "Fetch ROS packages' dependencies (this might take a while)..."
cd $AMENT_WSDIR/
# The rosdep flags below have been chosen very carefully. Please review the docs before changing them.
# https://docs.ros.org/en/independent/api/rosdep/html/commands.html
rosdep install --rosdistro=jazzy -iy --from-paths src &>> $REDIRECT_LOGFILE

echo "Install web interface dependencies..."
cd $AMENT_WSDIR/src/stretch4_web_teleop
npm install --force &>> $REDIRECT_LOGFILE
echo "Generating web interface certs..."
cd $AMENT_WSDIR/src/stretch4_web_teleop/certificates
curl -JLO "https://dl.filippo.io/mkcert/latest?for=linux/amd64" &>> $REDIRECT_LOGFILE
chmod +x mkcert-v*-linux-amd64
sudo cp mkcert-v*-linux-amd64 /usr/local/bin/mkcert
CAROOT=`pwd` mkcert --install &>> $REDIRECT_LOGFILE
mkdir -p ~/.local/share/mkcert
rm -rf ~/.local/share/mkcert/root*
cp root* ~/.local/share/mkcert
mkcert ${HELLO_FLEET_ID} ${HELLO_FLEET_ID}.local ${HELLO_FLEET_ID}.dev localhost 127.0.0.1 0.0.0.0 ::1 &>> $REDIRECT_LOGFILE
rm mkcert-v*-linux-amd64
cd $AMENT_WSDIR/src/stretch4_web_teleop
touch .env
echo certfile=${HELLO_FLEET_ID}+6.pem >> .env
echo keyfile=${HELLO_FLEET_ID}+6-key.pem >> .env
cd $AMENT_WSDIR/

echo "Compile the workspace (this might take a while)..."
export MAKEFLAGS="-j 4" # the NUC cannot handle the memory intensive build of depthai_core, this and --executor sequential are the best config for getting a successful build.
colcon build --symlink-install --executor sequential &>> $REDIRECT_LOGFILE
unset MAKEFLAGS

echo "Source setup.bash file..."
source $AMENT_WSDIR/install/setup.bash
echo "Updating port privledges..."
sudo sysctl -w net.ipv4.ip_unprivileged_port_start=80 &>> $REDIRECT_LOGFILE
echo net.ipv4.ip_unprivileged_port_start=80 | sudo tee --append /etc/sysctl.d/99-sysctl.conf &>> $REDIRECT_LOGFILE


echo "Installing Zenoh router system service..."
sudo cp "$(dirname "$0")/stretch-ros2-zenoh-router.service" /etc/systemd/system/
sudo sed -i "s|__USER__|$USER|g" /etc/systemd/system/stretch-ros2-zenoh-router.service
sudo sed -i "s|__USER_HOME__|$HOME|g" /etc/systemd/system/stretch-ros2-zenoh-router.service

sudo systemctl daemon-reload
sudo systemctl enable stretch-ros2-zenoh-router.service
sudo systemctl restart stretch-ros2-zenoh-router.service
