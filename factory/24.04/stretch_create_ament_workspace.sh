#!/bin/bash
set -e
export COLCON_EXTENSION_BLOCKLIST=colcon_core.event_handler.desktop_notification
SCRIPT_DIR=$(cd $(dirname "$0") && pwd)


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

SCRIPT_ROOT="$(dirname "$(dirname "$(dirname "$(readlink -f "$0")")")")"
PIXI_ENV_DIR="$SCRIPT_ROOT/stretch_venv/.pixi/envs/default"
if [ ! -d "$PIXI_ENV_DIR" ]; then
    echo "ERROR: The unified environment $PIXI_ENV_DIR does not exist."
    echo "Please run the setup script to generate it:"
    echo "    $SCRIPT_ROOT/stretch_venv/setup_venv.sh"
    echo "Exiting."
    exit 1
fi

# Source the Pixi environment. ROS 2 Jazzy lives inside it (RoboStack), so this
# is also what puts ros2/colcon/vcs on the PATH and sets ROS_DISTRO and
# AMENT_PREFIX_PATH. There is no /opt/ros/jazzy/setup.bash to source.
export PATH="$PIXI_ENV_DIR/bin:$PATH"
export CONDA_PREFIX="$PIXI_ENV_DIR"
for f in "$CONDA_PREFIX/etc/conda/activate.d/"*.sh; do
    if [ -f "$f" ]; then source "$f"; fi
done

echo "###########################################"
echo "CREATING JAZZY AMENT WORKSPACE at $AMENT_WSDIR"
echo "###########################################"

echo "Ensuring correct version of ROS is sourced..."
if [[ $ROS_DISTRO && ! $ROS_DISTRO = "jazzy" ]]; then
    echo "Cannot create workspace while a conflicting ROS version is sourced. Exiting."
    exit 1
fi
# ROS 2 must come from the pixi environment, not from apt. A stray
# /opt/ros/jazzy on the PATH links the workspace against a different libstdc++
# and a different Python, which fails at runtime rather than at build time.
ROS2_BIN="$(command -v ros2 || true)"
if [[ "$ROS2_BIN" != "$PIXI_ENV_DIR/bin/ros2" ]]; then
    echo "ERROR: 'ros2' resolved to '${ROS2_BIN:-<not found>}' instead of"
    echo "       '$PIXI_ENV_DIR/bin/ros2'."
    echo "ROS 2 Jazzy is provided by the pixi environment (RoboStack). If an apt"
    echo "ROS install is present, remove it:"
    echo "    sudo apt-get remove --purge 'ros-jazzy-*' ros2-apt-source && sudo apt-get autoremove"
    echo "Exiting."
    exit 1
fi
echo "Using ROS 2 $ROS_DISTRO from $PIXI_ENV_DIR"

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

# The compiler, cmake, ninja and make all come from the pixi environment. They
# must, because the RoboStack packages this workspace links against are built
# with conda's toolchain (libstdcxx >= 14), which is newer than Ubuntu 24.04's.
echo "Checking build tools from the pixi environment..."
for tool in cmake ninja make gcc g++ colcon vcs; do
    if ! command -v "$tool" &> /dev/null; then
        echo "ERROR: '$tool' not found in the pixi environment. Re-run:"
        echo "    $SCRIPT_ROOT/stretch_venv/setup_venv.sh"
        exit 1
    fi
done

. /etc/hello-robot/hello-robot.conf
export HELLO_FLEET_ID=$HELLO_FLEET_ID
export HELLO_FLEET_PATH=${HOME}/stretch_user
echo "Deleting $AMENT_WSDIR if it already exists..."
sudo rm -rf $AMENT_WSDIR
echo "Creating the workspace directory..."
mkdir -p $AMENT_WSDIR/src

echo "Cloning the workspace's packages..."
cd $AMENT_WSDIR/src
# Use the .repos file that ships next to this script rather than a hardcoded
# ~/stretch4_install path, so a checkout elsewhere imports its own repo list.
vcs import --input "$SCRIPT_DIR/stretch_ros2_jazzy.repos" &>> $REDIRECT_LOGFILE

echo "Cloning HesaiLidar_ROS_2.0 submodules..."
cd $AMENT_WSDIR/src/HesaiLidar_ROS_2.0
git submodule update --init --recursive &>> $REDIRECT_LOGFILE

cd $AMENT_WSDIR/
export ROS_PYTHON_VERSION=3

# `rosdep install` is deliberately NOT run any more: it resolves keys to apt
# packages, and every ROS dependency of this workspace is now declared in
# stretch_venv/pyproject.toml and installed from RoboStack into the pixi
# environment. This check reports any package.xml dependency that the pixi
# environment does not satisfy, so that a newly added dependency shows up here
# instead of as a confusing colcon error.
echo "Checking workspace dependencies against the pixi environment..."
# pipefail so that an unsatisfied dependency aborts here (via set -e) rather
# than surfacing later as an opaque colcon error. tee alone would mask it.
set -o pipefail
# -s disables user site-packages, so a stale ~/.local install cannot make a
# dependency look satisfied when it is absent from the pixi environment.
python -s "$SCRIPT_DIR/check_workspace_dependencies.py" "$AMENT_WSDIR/src" | tee -a $REDIRECT_LOGFILE
set +o pipefail

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
export PATH="$PIXI_ENV_DIR/bin:$PATH"
# Use the pixi environment's compilers, not the system ones, so the workspace
# matches the ABI of the RoboStack packages it links against.
export CC="$PIXI_ENV_DIR/bin/gcc"
export CXX="$PIXI_ENV_DIR/bin/g++"
PIXI_SITE_PACKAGES=$(python -c "import site; print(site.getsitepackages()[0])")
# Only the pixi environment is on PYTHONPATH. /opt/ros and the system
# dist-packages are intentionally absent: mixing them in re-introduces the
# system numpy 1.x and the apt ROS python packages.
export PYTHONPATH="$PIXI_SITE_PACKAGES:$PYTHONPATH"
export COLCON_DEBIAN_PYTHON_INSTALL_LAYOUT=off

colcon build --symlink-install --cmake-args \
    -DCMAKE_PREFIX_PATH="$PIXI_ENV_DIR" \
    -DCMAKE_C_COMPILER="$CC" \
    -DCMAKE_CXX_COMPILER="$CXX" \
    -DCMAKE_MAKE_PROGRAM="$PIXI_ENV_DIR/bin/make" \
    -DPython3_EXECUTABLE="$PIXI_ENV_DIR/bin/python" &>> $REDIRECT_LOGFILE


echo "Source setup.bash file..."
source $AMENT_WSDIR/install/setup.bash
echo "Updating port privledges..."
sudo sysctl -w net.ipv4.ip_unprivileged_port_start=80 &>> $REDIRECT_LOGFILE
echo net.ipv4.ip_unprivileged_port_start=80 | sudo tee --append /etc/sysctl.d/99-sysctl.conf &>> $REDIRECT_LOGFILE


echo "Installing Zenoh router system service..."
sudo cp "$SCRIPT_DIR/stretch-ros2-zenoh-router.service" /etc/systemd/system/
sudo sed -i "s|__USER__|$USER|g" /etc/systemd/system/stretch-ros2-zenoh-router.service
sudo sed -i "s|__USER_HOME__|$HOME|g" /etc/systemd/system/stretch-ros2-zenoh-router.service

sudo systemctl daemon-reload
sudo systemctl enable stretch-ros2-zenoh-router.service
sudo systemctl restart stretch-ros2-zenoh-router.service
