#!/bin/bash
set -e

# Builds the hello-robot-stretch4-system .deb: a known-good snapshot of the
# Stretch 4 system install, ROS 2 workspace and Python packages.
#
#   * Depends on every apt package installed by factory/24.04/stretch_install_system.sh,
#     plus the apt packages that rosdep resolves for the ROS 2 workspace.
#   * Bundles the ROS 2 workspace from factory/24.04/stretch_ros2_jazzy.repos, prebuilt
#     as an underlay in /opt/hello-robot/stretch4/ament_ws. stretch4_web_teleop is shipped
#     as source (with node_modules) because it must run from each user's ~/ament_ws.
#   * Bundles the hello-robot-stretch4-* pip packages (and any pip deps not already
#     provided by apt) in /opt/hello-robot/stretch4/python.
#   * Bundles pm2 and mkcert, the sysctl settings and the Zenoh router service.
#
# Run this on a 24.04 build machine that has already had stretch_install_system.sh run.
# The workspace is compiled in place at /opt/hello-robot/stretch4 (so that paths embedded
# by colcon/CMake are correct), copied into the package, then removed again.

PKG_NAME="hello-robot-stretch4-system"
PREFIX="/opt/hello-robot/stretch4"
VERSION="$(date '+%Y.%m.%d.%H%M')"
OUTPUT_DIR="$PWD"
REDIRECT_LOGDIR="$HOME/stretch_user/log"
PYTHON_PACKAGES=(
    hello-robot-stretch4-urdf
    hello-robot-stretch4-flying-gripper
    hello-robot-stretch4-body
    hello-robot-stretch4-tray
    hello-robot-stretch4-pyhesai-wrapper
    hello-robot-stretch4-kinematics
)

function usage {
    echo "Usage: $0 [-v version] [-o output_dir] [-l log_dir]"
    echo "  -v  Package version (default: $VERSION)"
    echo "  -o  Directory to write the .deb into (default: current directory)"
    echo "  -l  Directory to write the build log into (default: $REDIRECT_LOGDIR)"
}

while getopts ":v:o:l:h" opt; do
    case $opt in
        v) VERSION=$OPTARG ;;
        o) OUTPUT_DIR=$(readlink -f "$OPTARG") ;;
        l) [[ -d $OPTARG ]] && REDIRECT_LOGDIR=$OPTARG ;;
        h) usage; exit 0 ;;
        \?) echo "Invalid option: -$OPTARG" >&2; usage; exit 1 ;;
    esac
done

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
FACTORY_DIR="$SCRIPT_DIR/factory/24.04"
mkdir -p "$REDIRECT_LOGDIR" "$OUTPUT_DIR"
REDIRECT_LOGFILE="$REDIRECT_LOGDIR/stretch_create_deb_package.`date '+%Y%m%d%H%M'`_redirected.txt"
WORK_DIR="$(mktemp -d --tmpdir="${TMPDIR:-/var/tmp}" stretch_deb.XXXXXX)"
STAGE_DIR="$WORK_DIR/stage"
CREATED_PREFIX=false

function cleanup {
    if $CREATED_PREFIX; then
        sudo rm -rf "$PREFIX"
    fi
    rm -rf "$WORK_DIR"
}
trap cleanup EXIT

function on_failure {
    echo ""
    echo "#############################################"
    echo "FAILURE. DEB PACKAGE WAS NOT CREATED."
    echo "Failed at line: $1"
    echo "Failed command: $2"
    echo "Check $REDIRECT_LOGFILE for more details."
    echo "#############################################"
    echo ""
}
trap 'on_failure $LINENO "$BASH_COMMAND"' ERR

# Run a command with only ROS 2 Jazzy sourced, so the developer's own overlays, ~/.local
# packages, etc. on the build machine don't leak into the package.
function clean_env {
    env -i HOME="$HOME" USER="$USER" PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin \
        LANG=C.UTF-8 PYTHONNOUSERSITE=1 PIP_BREAK_SYSTEM_PACKAGES=1 \
        COLCON_EXTENSION_BLOCKLIST=colcon_core.event_handler.desktop_notification \
        bash -c 'source /opt/ros/jazzy/setup.bash && "$@"' _ "$@"
}

echo "###########################################"
echo "CREATING $PKG_NAME $VERSION"
echo "###########################################"

echo "Checking the build machine..."
source /etc/os-release
if [[ $VERSION_ID != "24.04" ]]; then
    echo "This package must be built on Ubuntu 24.04."
    exit 1
fi
for cmd in colcon vcs rosdep npm dpkg-deb python3 git curl; do
    if ! command -v $cmd &> /dev/null; then
        echo "Missing '$cmd'. Run factory/24.04/stretch_install_system.sh on this machine first."
        exit 1
    fi
done
if [[ ! -f /opt/ros/jazzy/setup.bash ]]; then
    echo "ROS 2 Jazzy is not installed. Run factory/24.04/stretch_install_system.sh on this machine first."
    exit 1
fi
if [[ -e $PREFIX ]]; then
    echo "$PREFIX already exists. The workspace is compiled in place there, so it must not exist."
    echo "If $PKG_NAME is installed on this machine, remove it (sudo apt remove $PKG_NAME) or build elsewhere."
    exit 1
fi
sudo mkdir -p "$PREFIX"
CREATED_PREFIX=true
sudo chown "$USER:$USER" "$PREFIX"

echo "Updating rosdep indices..."
clean_env rosdep update --include-eol-distros &>> $REDIRECT_LOGFILE

echo "Cloning the workspace's packages..."
mkdir -p "$WORK_DIR/src"
cd "$WORK_DIR/src"
vcs import --input "$FACTORY_DIR/stretch_ros2_jazzy.repos" &>> $REDIRECT_LOGFILE
cd "$WORK_DIR/src/HesaiLidar_ROS_2.0"
git submodule update --init --recursive &>> $REDIRECT_LOGFILE

echo "Resolving the workspace's dependencies with rosdep..."
cd "$WORK_DIR"
clean_env rosdep install --rosdistro=jazzy -iy --from-paths src &>> $REDIRECT_LOGFILE
ROSDEP_KEYS=$(clean_env rosdep keys --ignore-src --from-paths src -t build_export -t buildtool_export -t exec 2> /dev/null | sort -u)
declare -a ROSDEP_APT ROSDEP_PIP
if [[ -n $ROSDEP_KEYS ]]; then
    # 'rosdep resolve' prints a '#<installer>' line followed by that installer's packages
    while read -r installer pkgs; do
        case $installer in
            apt) ROSDEP_APT+=($pkgs) ;;
            pip) ROSDEP_PIP+=($pkgs) ;;
        esac
    done < <(clean_env rosdep resolve --rosdistro=jazzy $ROSDEP_KEYS 2>> $REDIRECT_LOGFILE \
                 | awk '/^#/ {installer=substr($1, 2); next} {print installer, $0}')
fi

echo "Compiling the workspace into $PREFIX/ament_ws (this might take a while)..."
clean_env colcon build \
    --base-paths "$WORK_DIR/src" \
    --build-base "$WORK_DIR/build" \
    --install-base "$PREFIX/ament_ws/install" \
    --packages-skip stretch4_web_teleop \
    --cmake-args -DCMAKE_BUILD_TYPE=Release \
    &>> $REDIRECT_LOGFILE

echo "Installing web interface dependencies..."
cd "$WORK_DIR/src/stretch4_web_teleop"
npm install --force &>> $REDIRECT_LOGFILE
mkdir -p "$PREFIX/src"
cp -a "$WORK_DIR/src/stretch4_web_teleop" "$PREFIX/src/"

echo "Bundling PM2..."
clean_env npm install --global --prefix "$PREFIX/node" pm2 &>> $REDIRECT_LOGFILE

echo "Bundling mkcert..."
mkdir -p "$PREFIX/bin"
curl -fL --retry 5 --retry-delay 5 --retry-all-errors --connect-timeout 15 -o "$PREFIX/bin/mkcert" \
    "https://dl.filippo.io/mkcert/latest?for=linux/amd64" &>> $REDIRECT_LOGFILE
chmod 755 "$PREFIX/bin/mkcert"

echo "Bundling Python packages..."
# Dependencies already provided by apt on this machine are skipped, so these
# packages layer on top of the same system Python that ROS 2 uses.
clean_env python3 -m pip install --no-warn-script-location --no-compile \
    --prefix "$PREFIX/python" "${PYTHON_PACKAGES[@]}" "${ROSDEP_PIP[@]}" &>> $REDIRECT_LOGFILE
PYTHON_SITE_DIR=$(find "$PREFIX/python/lib" -maxdepth 2 -type d \( -name site-packages -o -name dist-packages \) | head -n 1)
for pkg in "${PYTHON_PACKAGES[@]}"; do
    if ! PYTHONPATH="$PYTHON_SITE_DIR" PYTHONNOUSERSITE=1 python3 -m pip show "$pkg" 2> /dev/null \
            | grep -q "^Location: $PYTHON_SITE_DIR"; then
        echo "$pkg was not bundled into $PYTHON_SITE_DIR. Is it already installed system-wide on this machine?"
        exit 1
    fi
done

echo "Writing environment setup and manifest..."
cat > "$PREFIX/setup.bash" << EOF
# Sets up the environment provided by $PKG_NAME. Source this instead of /opt/ros/jazzy/setup.bash.
source $PREFIX/ament_ws/install/setup.bash
export PATH="$PREFIX/bin:$PREFIX/python/bin:$PREFIX/node/bin:\$PATH"
EOF
{
    echo "$PKG_NAME $VERSION"
    echo "Built $(date -u '+%Y-%m-%dT%H:%M:%SZ') on $(hostname) from stretch4_install $(git -C "$SCRIPT_DIR" rev-parse --short HEAD)"
    echo ""
    echo "## ROS 2 workspace"
    vcs export --exact "$WORK_DIR/src" 2> /dev/null
    echo ""
    echo "## Python packages"
    PYTHONPATH="$PYTHON_SITE_DIR" PYTHONNOUSERSITE=1 python3 -m pip list --format=freeze --path "$PYTHON_SITE_DIR"
    echo ""
    echo "## Node packages"
    echo "pm2 $(cat "$PREFIX/node/lib/node_modules/pm2/package.json" | python3 -c 'import json,sys; print(json.load(sys.stdin)["version"])')"
} > "$PREFIX/manifest.txt"

echo "Staging the package..."
mkdir -p "$STAGE_DIR/opt/hello-robot" "$STAGE_DIR/DEBIAN"
cp -a "$PREFIX" "$STAGE_DIR/opt/hello-robot/"

# Put the bundled Python packages on the system Python's path
mkdir -p "$STAGE_DIR/usr/lib/python3/dist-packages"
echo "$PYTHON_SITE_DIR" > "$STAGE_DIR/usr/lib/python3/dist-packages/$PKG_NAME.pth"

# The sysctl settings are taken from stretch_install_system.sh so both installs stay in sync
mkdir -p "$STAGE_DIR/etc/sysctl.d"
sed -nE "s|^echo '([^']*)' [|] sudo tee (/etc/sysctl.d/[^ ]+).*|\1 \2|p" "$FACTORY_DIR/stretch_install_system.sh" \
    | while read -r setting file; do
        echo "$setting" > "$STAGE_DIR$file"
    done

mkdir -p "$STAGE_DIR/usr/lib/systemd/system"
cat > "$STAGE_DIR/usr/lib/systemd/system/stretch-ros2-zenoh-router.service" << EOF
[Unit]
Description=Stretch ROS2 Zenoh Router
After=network.target network-online.target
Wants=network-online.target

[Service]
Type=simple
DynamicUser=yes
StateDirectory=stretch-ros2-zenoh-router
Environment="RMW_IMPLEMENTATION=rmw_zenoh_cpp"
Environment="ROS_HOME=/var/lib/stretch-ros2-zenoh-router"
ExecStart=/bin/bash -c "source $PREFIX/setup.bash && exec ros2 run rmw_zenoh_cpp rmw_zenohd"
Restart=on-failure
RestartSec=3

[Install]
WantedBy=multi-user.target
EOF

echo "Writing package metadata..."
# Every 'install <pkgs>' line of stretch_install_system.sh becomes a dependency
SYSTEM_APT=$(sed -nE 's/^install (.*)/\1/p' "$FACTORY_DIR/stretch_install_system.sh")
DEPENDS=$(printf '%s\n' $SYSTEM_APT "${ROSDEP_APT[@]}" python3 init-system-helpers | sort -u | paste -sd, - | sed 's/,/, /g')
DEPENDS=$(echo "$DEPENDS" | sed -E 's/(^|, )nodejs(,|$)/\1nodejs (>= 24)\2/')
MAINTAINER="$(git -C "$SCRIPT_DIR" config user.name || echo "Hello Robot") <$(git -C "$SCRIPT_DIR" config user.email || echo "support@hello-robot.com")>"

cat > "$STAGE_DIR/DEBIAN/control" << EOF
Package: $PKG_NAME
Version: $VERSION
Architecture: amd64
Maintainer: $MAINTAINER
Section: misc
Priority: optional
Installed-Size: $(du -sk --exclude=DEBIAN "$STAGE_DIR" | cut -f1)
Depends: $DEPENDS
Homepage: https://github.com/hello-robot/stretch4_install
Description: Hello Robot Stretch 4 system software
 A known-good snapshot of the Stretch 4 system packages, prebuilt ROS 2 Jazzy
 workspace and Python packages. Source $PREFIX/setup.bash to use it.
 See $PREFIX/manifest.txt for the exact versions bundled.
EOF

find "$STAGE_DIR/etc" -type f | sed "s|^$STAGE_DIR||" > "$STAGE_DIR/DEBIAN/conffiles"

cat > "$STAGE_DIR/DEBIAN/postinst" << EOF
#!/bin/sh
set -e
if [ "\$1" = "configure" ]; then
    sysctl --system > /dev/null || true
    python3 -m compileall -q "$PREFIX/python" > /dev/null || true
    if [ ! -f /etc/ros/rosdep/sources.list.d/20-default.list ]; then
        rosdep init > /dev/null 2>&1 || echo "Warning: 'rosdep init' failed. Run it manually once online."
    fi
    if [ -d /run/systemd/system ]; then
        systemctl daemon-reload || true
    fi
    deb-systemd-helper unmask stretch-ros2-zenoh-router.service > /dev/null || true
    # was-enabled defaults to true, so new installations run enable
    if deb-systemd-helper --quiet was-enabled stretch-ros2-zenoh-router.service; then
        deb-systemd-helper enable stretch-ros2-zenoh-router.service > /dev/null || true
    else
        deb-systemd-helper update-state stretch-ros2-zenoh-router.service > /dev/null || true
    fi
    if [ -d /run/systemd/system ]; then
        deb-systemd-invoke restart stretch-ros2-zenoh-router.service > /dev/null || true
    fi
fi
exit 0
EOF

cat > "$STAGE_DIR/DEBIAN/prerm" << EOF
#!/bin/sh
set -e
if [ -d /run/systemd/system ] && [ "\$1" = "remove" ]; then
    deb-systemd-invoke stop stretch-ros2-zenoh-router.service > /dev/null || true
fi
find "$PREFIX/python" -type d -name __pycache__ -prune -exec rm -rf {} + 2> /dev/null || true
exit 0
EOF

cat > "$STAGE_DIR/DEBIAN/postrm" << EOF
#!/bin/sh
set -e
if [ -d /run/systemd/system ]; then
    systemctl daemon-reload || true
fi
if [ "\$1" = "remove" ]; then
    deb-systemd-helper mask stretch-ros2-zenoh-router.service > /dev/null || true
fi
if [ "\$1" = "purge" ]; then
    deb-systemd-helper purge stretch-ros2-zenoh-router.service > /dev/null || true
    deb-systemd-helper unmask stretch-ros2-zenoh-router.service > /dev/null || true
fi
exit 0
EOF
chmod 755 "$STAGE_DIR/DEBIAN/postinst" "$STAGE_DIR/DEBIAN/prerm" "$STAGE_DIR/DEBIAN/postrm"

echo "Building the .deb (this might take a while)..."
DEB_FILE="$OUTPUT_DIR/${PKG_NAME}_${VERSION}_amd64.deb"
dpkg-deb --root-owner-group -Zxz --build "$STAGE_DIR" "$DEB_FILE" &>> $REDIRECT_LOGFILE

echo ""
echo "###########################################"
echo "DONE! Created $DEB_FILE"
echo "Install it with: ./stretch_new_user_install.sh -d $DEB_FILE"
echo "###########################################"
