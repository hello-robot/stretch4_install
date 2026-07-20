#!/bin/bash
set -e

# Load fleet configuration to get HELLO_FLEET_ID if not already set
if [ -z "$HELLO_FLEET_ID" ]; then
    if [ -f "/etc/hello-robot/hello-robot.conf" ]; then
        . /etc/hello-robot/hello-robot.conf
    fi
fi

if [ -z "$HELLO_FLEET_ID" ]; then
    echo "Error: HELLO_FLEET_ID is not set and /etc/hello-robot/hello-robot.conf is missing." >&2
    exit 1
fi

SOURCE_USER="hello-robot"
TARGET_USER="${SUDO_USER:-$USER}"
FORCE=false

# Helper function to print usage
show_usage() {
    echo "Usage: $0 [options] [target_user]"
    echo
    echo "Options:"
    echo "  -s, --source USER  Source user account to copy calibration from (default: hello-robot)"
    echo "  -u, --user USER    Target user account to copy calibration to (default: current user)"
    echo "  -f, --force        Force copy without prompting the user"
    echo "  -h, --help         Show this help message"
    exit 0
}

# Parse command line options
while [[ $# -gt 0 ]]; do
    case "$1" in
        -s|--source)
            if [ -n "$2" ]; then
                SOURCE_USER="$2"
                shift 2
            else
                echo "Error: --source requires an argument." >&2
                exit 1
            fi
            ;;
        -u|--user)
            if [ -n "$2" ]; then
                TARGET_USER="$2"
                shift 2
            else
                echo "Error: --user requires an argument." >&2
                exit 1
            fi
            ;;
        -f|--force)
            FORCE=true
            shift
            ;;
        -h|--help)
            show_usage
            ;;
        -*)
            echo "Unknown option: $1" >&2
            exit 1
            ;;
        *)
            TARGET_USER="$1"
            shift
            ;;
    esac
done

if [ -z "$TARGET_USER" ] || [ "$TARGET_USER" = "root" ]; then
    echo "Error: Target user must be specified or run from a non-root user." >&2
    exit 1
fi

if [ "$TARGET_USER" = "$SOURCE_USER" ]; then
    echo "Target user is the same as source user ($SOURCE_USER). No copy needed."
    exit 0
fi

# Define source directories to check
SRC_DIR=""
if [ -d "/home/$SOURCE_USER/stretch_user/$HELLO_FLEET_ID" ]; then
    SRC_DIR="/home/$SOURCE_USER/stretch_user/$HELLO_FLEET_ID"
elif [ -d "/home/$SOURCE_USER/$HELLO_FLEET_ID" ]; then
    SRC_DIR="/home/$SOURCE_USER/$HELLO_FLEET_ID"
fi

if [ -z "$SRC_DIR" ]; then
    echo "Error: No calibration data found for $SOURCE_USER at /home/$SOURCE_USER/stretch_user/$HELLO_FLEET_ID or /home/$SOURCE_USER/$HELLO_FLEET_ID." >&2
    exit 2
fi

# Define destination directory
DEST_PARENT="/home/$TARGET_USER/stretch_user"
DEST_DIR="$DEST_PARENT/$HELLO_FLEET_ID"

# If FORCE is false, list files and ask for confirmation
if [ "$FORCE" = false ]; then
    echo "The following files from $SOURCE_USER's calibration directory will be copied to $DEST_DIR:"
    sudo find "$SRC_DIR" -type f | sed "s|^$SRC_DIR/||" | sort
    echo
    read -p "Do you want to copy these files? [y/N] " response
    if [[ ! "$response" =~ ^[Yy]$ ]]; then
        echo "Copy skipped by user."
        exit 0
    fi
fi

echo "Copying to $DEST_DIR..."
# Ensure destination parent and destination directory exist
sudo mkdir -p "$DEST_DIR"

# Copy calibration directory contents
sudo cp -rf "$SRC_DIR/." "$DEST_DIR/"

# Fix ownership to the target user
sudo chown -R "$TARGET_USER:$TARGET_USER" "$DEST_DIR"

# Adjust permissions to ensure directories are accessible and files are not all executable
sudo chmod -R a-x,o-w,+X "$DEST_DIR"

# Ensure udev rules are not writable
if [ -d "$DEST_DIR/udev" ]; then
    sudo chmod a-w "$DEST_DIR"/udev/*.rules || true
fi

echo "Successfully copied calibration data from $SOURCE_USER to $TARGET_USER."
