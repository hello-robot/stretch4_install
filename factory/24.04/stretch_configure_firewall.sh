#!/bin/bash
# Enables the ufw firewall on Stretch and opens the ports the robot needs.
#
# Policy: deny incoming, allow outgoing. Replies to connections the robot opens
# (e.g. PTC to the lidars, apt, WebRTC) are allowed by ufw's connection tracking,
# and loopback, DHCP and mDNS (<hostname>.local) are allowed by ufw's built-in rules.
#
# Safe to re-run: ufw skips rules that already exist, and existing rules are kept.
set -e

###############################################################################
# IPs AND PORTS
# These are documented in stretch4_docs/working-with-stretch/networking-stretch.md
# ("Firewall and Network Ports"). Update the docs when changing them.
###############################################################################

# Internal network, set up by stretch_initial_setup.sh (/etc/netplan/99-stretch.yaml).
# Rules for these devices only apply on the internal Ethernet interface.
NUC_IP="192.168.1.2"
JETSON_IP="192.168.1.101"           # All traffic from the Jetson is allowed

# Hesai lidars, see stretch4_pyhesai_wrapper/config.yaml and stretch_core/config/hesai_dual_lidar.yaml.
# Only the point cloud UDP stream needs an inbound rule. PTC (TCP 9347) is opened by
# the robot towards the lidar, so its replies are already allowed.
RIGHT_LIDAR_IP="192.168.1.201"
RIGHT_LIDAR_UDP_PORT="2368"
LEFT_LIDAR_IP="192.168.1.202"
LEFT_LIDAR_UDP_PORT="2378"
# PTP time sync (UDPv4, E2E). The NUC is the lidars' PTP grandmaster (lidar-ptp4l.service from
# REx_ptp_manager), and the lidars send it Delay_Req (319) and general messages (320) by multicast.
LIDAR_PTP_UDP_PORTS="319:320"

# Open on all interfaces (Wi-Fi included)
SSH_PORT="22"
ZENOH_ROUTER_PORT="7447"            # ROS 2 rmw_zenoh router (rmw_zenohd)
BODY_SERVER_ZMQ_PORTS="23114:23116" # Stretch Body Server admin/command/status. Only listen
                                    # when robot.server.enable_network_access is set.
WEB_TELEOP_HTTP_PORT="80"
WEB_TELEOP_HTTPS_PORT="443"

###############################################################################

usage() {
    echo "Usage: $0 [-i <ethernet_interface>]"
    echo "  -i  Internal (lidar/Jetson) Ethernet interface. Default: the interface holding"
    echo "      $NUC_IP, or else the first en*/eth* interface."
}

ETH_IFACE=""
while getopts ":i:h" opt; do
    case $opt in
        i) ETH_IFACE=$OPTARG ;;
        h) usage; exit 0 ;;
        *) usage; exit 1 ;;
    esac
done

if [[ -z "$ETH_IFACE" ]]; then
    ETH_IFACE=$(ip -o -4 addr show | awk -v ip="$NUC_IP" '$4 ~ "^"ip"/" {print $2; exit}')
fi
if [[ -z "$ETH_IFACE" ]]; then
    ETH_IFACE=$(ip -o link show | awk -F': ' '{print $2}' | grep -E '^(en|eth)' | head -n 1)
fi
# Drop the "@ifN" suffix that ip shows for veth/vlan links (e.g. eth0@if20 in Docker)
ETH_IFACE=${ETH_IFACE%%@*}
if [[ -z "$ETH_IFACE" ]]; then
    echo "ERROR: could not find the internal Ethernet interface. Pass it with -i."
    exit 1
fi
echo "Using internal Ethernet interface: $ETH_IFACE"

if ! command -v ufw &> /dev/null; then
    echo "Install ufw"
    SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
    source "$SCRIPT_DIR/stretch_apt_common.sh"
    apt_configure
    retry_cmd sudo apt-get update > /dev/null
    retry_cmd sudo apt-get install -y ufw > /dev/null
fi

echo "Set default policy: deny incoming, allow outgoing"
sudo ufw default deny incoming > /dev/null
sudo ufw default allow outgoing > /dev/null

# Added before enabling so an SSH session running this script isn't cut off
echo "Allow SSH ($SSH_PORT/tcp)"
sudo ufw allow "$SSH_PORT/tcp" comment 'Stretch: SSH' > /dev/null

echo "Allow Hesai lidar point clouds on $ETH_IFACE only"
sudo ufw allow in on "$ETH_IFACE" proto udp from "$RIGHT_LIDAR_IP" to any port "$RIGHT_LIDAR_UDP_PORT" comment 'Stretch: right lidar' > /dev/null
sudo ufw allow in on "$ETH_IFACE" proto udp from "$LEFT_LIDAR_IP" to any port "$LEFT_LIDAR_UDP_PORT" comment 'Stretch: left lidar' > /dev/null

echo "Allow Hesai lidar PTP time sync ($LIDAR_PTP_UDP_PORTS/udp) on $ETH_IFACE only"
sudo ufw allow in on "$ETH_IFACE" proto udp from "$RIGHT_LIDAR_IP" to any port "$LIDAR_PTP_UDP_PORTS" comment 'Stretch: right lidar PTP' > /dev/null
sudo ufw allow in on "$ETH_IFACE" proto udp from "$LEFT_LIDAR_IP" to any port "$LIDAR_PTP_UDP_PORTS" comment 'Stretch: left lidar PTP' > /dev/null

echo "Allow all traffic from the Jetson on $ETH_IFACE only"
sudo ufw allow in on "$ETH_IFACE" from "$JETSON_IP" comment 'Stretch: Jetson' > /dev/null

echo "Allow ROS 2 Zenoh router ($ZENOH_ROUTER_PORT/tcp)"
sudo ufw allow "$ZENOH_ROUTER_PORT/tcp" comment 'Stretch: ROS 2 Zenoh router' > /dev/null

echo "Allow Stretch Body Server ZMQ ($BODY_SERVER_ZMQ_PORTS/tcp)"
sudo ufw allow "$BODY_SERVER_ZMQ_PORTS/tcp" comment 'Stretch: Body Server ZMQ' > /dev/null

echo "Allow web teleop ($WEB_TELEOP_HTTP_PORT/tcp, $WEB_TELEOP_HTTPS_PORT/tcp)"
sudo ufw allow "$WEB_TELEOP_HTTP_PORT/tcp" comment 'Stretch: web teleop HTTP' > /dev/null
sudo ufw allow "$WEB_TELEOP_HTTPS_PORT/tcp" comment 'Stretch: web teleop HTTPS' > /dev/null

echo "Enable ufw"
sudo ufw --force enable > /dev/null
sudo systemctl enable ufw &> /dev/null

sudo ufw status verbose
