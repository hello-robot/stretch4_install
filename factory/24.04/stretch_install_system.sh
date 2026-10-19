#!/bin/bash
set -e

REDIRECT_LOGDIR="$HOME/stretch_user/log"
if getopts ":l:" opt && [[ $opt == "l" && -d $OPTARG ]]; then
    REDIRECT_LOGDIR=$OPTARG
fi
REDIRECT_LOGFILE="$REDIRECT_LOGDIR/stretch_install_system.`date '+%Y%m%d%H%M'`_redirected.txt"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/stretch_apt_common.sh"

apt_configure

function install {
    retry_cmd sudo apt-get install -y "$@" >> $REDIRECT_LOGFILE
}

echo "###########################################"
echo "INSTALLATION OF SYSTEM WIDE PACKAGES"
echo "###########################################"
echo "Add apt sources (universe, Intel graphics, ROS 2, NodeSource)"
add_stretch_apt_sources &>> $REDIRECT_LOGFILE
echo "Apt upgrade (this might take a while)"
retry_cmd sudo apt-get --yes upgrade &>> $REDIRECT_LOGFILE
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
preseed_debconf
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
install lm-sensors nvme-cli
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
echo ""

echo "###########################################"
echo "CONFIGURATION OF SYSTEM SETTINGS"
echo "###########################################"
echo "Raise UDP receive buffer limit for the Hesai lidar"
echo 'net.core.rmem_max=262144000' | sudo tee /etc/sysctl.d/90-hesai.conf >> $REDIRECT_LOGFILE
echo "Allow non-root users to bind ports 80 and above (for web teleop)"
echo 'net.ipv4.ip_unprivileged_port_start=80' | sudo tee /etc/sysctl.d/90-unprivileged-ports.conf >> $REDIRECT_LOGFILE
sudo sysctl --system >> $REDIRECT_LOGFILE
echo ""

# https://docs.ros.org/en/jazzy/Installation/Ubuntu-Install-Debs.html
echo "###########################################"
echo "INSTALLATION OF ROS 2 JAZZY"
echo "###########################################"
echo "Install ROS 2 Jazzy (this might take a while)"
install ros-jazzy-desktop-full
# https://discourse.ros.org/t/ros-developer-tools-now-in-binary-form/29802
echo "Install Zenoh middleware"
install ros-jazzy-rmw-zenoh-cpp
echo "Install ROS 2 Dev Tools"
install ros-dev-tools
echo "Install colcon"
install python3-colcon-common-extensions python3-colcon-clean
echo "Install rosdep"
install python3-rosdep
echo "Configure rosdep"
if [ -f "/etc/ros/rosdep/sources.list.d/20-default.list" ]; then
    sudo rm /etc/ros/rosdep/sources.list.d/20-default.list
fi
sudo rosdep init &>> $REDIRECT_LOGFILE
echo "Install vcstool"
install python3-vcstool
echo ""

echo "###########################################"
echo "INSTALLATION OF ADDITIONAL ROS JAZZY PKGS"
echo "###########################################"
echo "Install packages to work with URDFs"
install liburdfdom-tools meshlab ros-jazzy-urdfdom-py
echo "Install joint state GUI package"
install ros-jazzy-joint-state-publisher-gui
echo "Install IMU visualization plugin for RViz and IMU filter"
install ros-jazzy-imu-tools ros-jazzy-imu-filter-madgwick
echo "Install robot localization package for use with IMU and wheel odometry"
install ros-jazzy-robot-localization
echo "Install teleop packages"
install ros-jazzy-teleop-twist-keyboard
echo ""

echo "###########################################"
echo "INSTALLATION OF WEB INTERFACE"
echo "###########################################"
echo "Install NodeJS"
install nodejs
# echo "Install PyPCL and PyKDL"
# install python3-pykdl screen libpcl-dev
# pip3 install -U cython --break-system-packages
# pip3 install python-pcl --break-system-packages

echo "Install PM2"
sudo npm install -g pm2 &>> $REDIRECT_LOGFILE
echo ""
echo "Installation complete!"
