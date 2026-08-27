#!/bin/bash
set -e

REDIRECT_LOGDIR="$HOME/stretch_user/log"
if getopts ":l:" opt && [[ $opt == "l" && -d $OPTARG ]]; then
    REDIRECT_LOGDIR=$OPTARG
fi
REDIRECT_LOGFILE="$REDIRECT_LOGDIR/stretch_install_system.`date '+%Y%m%d%H%M'`_redirected.txt"

function install {
    sudo apt-get install -y "$@" >> $REDIRECT_LOGFILE
}

echo "###########################################"
echo "INSTALLATION OF SYSTEM WIDE PACKAGES"
echo "###########################################"
echo "Apt update & upgrade (this might take a while)"
sudo apt-add-repository universe -y >> $REDIRECT_LOGFILE
sudo add-apt-repository -y ppa:kobuk-team/intel-graphics >> $REDIRECT_LOGFILE
sudo apt-get --yes update >> $REDIRECT_LOGFILE
sudo apt-get --yes upgrade &>> $REDIRECT_LOGFILE
echo "Install zip & unzip"
install zip unzip
echo "Install Curl"
install curl
echo "Install ca-certificates"
install ca-certificates
echo "Install gnupg"
install gnupg
echo "Install Git"
install git
echo "Install rpl"
install rpl
echo "Install ipython3"
install ipython3
echo "Install pip3"
install python3-pip
echo "Install Emacs packages"
sudo bash -c 'echo "postfix postfix/mailname string my.hostname.example" | debconf-set-selections'
sudo bash -c 'echo "postfix postfix/main_mailer_type string '\''Internet Site'\''" | debconf-set-selections'
install emacs yaml-mode
echo "Install nettools"
install net-tools
echo "Install wget"
install wget
echo "Install vim"
install vim
echo "Install pyserial"
install python3-serial
echo "Install Port Audio"
install portaudio19-dev
echo "Install lm-sensors & nvme-cli"
install lm-sensors
install nvme-cli
echo "Install cheese for camera testing"
install cheese
echo "Install SSH Server"
install ssh
echo "Install Chromium"
install chromium-browser
echo "Install htop"
install htop
echo "Install Ubuntu Sounds"
install ubuntu-sounds
echo "Install BleachBit"
install bleachbit
echo "Install APT HTTPS"
install apt-transport-https
echo "Install Network Security Services libraries"
install libnss3-tools
echo "Install arp-scan"
install arp-scan
echo "Install stretch_tray dependencies"
install pkg-config libcairo-dev gir1.2-appindicator3-0.1 libgirepository-2.0-dev
echo "Install Intel GPU dependencies"
install intel-gpu-tools intel-media-va-driver-non-free libva-glx2 va-driver-all vainfo intel-opencl-icd
echo "Install xterm (needed by stretch_simulation launch files)"
install xterm
echo ""

# ROS 2 Jazzy is NOT installed from apt. It is installed into the pixi
# environment from RoboStack (conda-forge builds of ROS 2), so that the ROS
# distribution, the Python interpreter, and the build toolchain all come from a
# single locked environment. See stretch_venv/pyproject.toml.
#
# stretch_venv/setup_venv.sh (invoked by stretch_new_user_install.sh) installs
# it, along with colcon, rosdep, vcstool, and every ROS package the ament
# workspace depends on. Nothing needs to be done here, and /opt/ros must stay
# empty: an apt ROS install alongside the RoboStack one will shadow it via
# AMENT_PREFIX_PATH and produce ABI mismatches at runtime.
echo "###########################################"
echo "ROS 2 JAZZY (installed later, via pixi/RoboStack)"
echo "###########################################"
if [ -d /opt/ros/jazzy ]; then
    echo "WARNING: /opt/ros/jazzy exists. ROS 2 now comes from the pixi"
    echo "         environment (RoboStack). The apt install should be removed:"
    echo "             sudo apt-get remove --purge 'ros-jazzy-*' ros2-apt-source"
    echo "             sudo apt-get autoremove"
fi
echo ""

echo "###########################################"
echo "INSTALLATION OF NON-ROS URDF TOOLING"
echo "###########################################"
echo "Install packages to work with URDFs"
install liburdfdom-tools meshlab
echo ""

echo "###########################################"
echo "INSTALLATION OF WEB INTERFACE"
echo "###########################################"
echo "Register the nodesource APT server's public key"
function register_nodesource_apt_server {
    curl -fsSL https://deb.nodesource.com/gpgkey/nodesource-repo.gpg.key | sudo gpg --batch --yes --dearmor -o /etc/apt/keyrings/nodesource.gpg
}
register_nodesource_apt_server &>> $REDIRECT_LOGFILE
echo "Add the nodesource APT server to the list of APT respositories"
function add_nodesource_apt_server {
    NODE_MAJOR=24
    echo "deb [signed-by=/etc/apt/keyrings/nodesource.gpg, arch=amd64] https://deb.nodesource.com/node_$NODE_MAJOR.x nodistro main" | sudo tee /etc/apt/sources.list.d/nodesource.list
}
add_nodesource_apt_server &>> $REDIRECT_LOGFILE
echo "Apt update"
sudo apt-get --yes update >> $REDIRECT_LOGFILE
echo "Install NodeJS"
install nodejs
# echo "Install PyPCL and PyKDL"
# install python3-pykdl screen libpcl-dev
# pip3 install -U cython --break-system-packages
# pip3 install python-pcl --break-system-packages

echo "Install PM2"
sudo npm install -g pm2 &>> $REDIRECT_LOGFILE
echo ""

