# shellcheck shell=bash
# Item: command. A link in /usr/local/bin so `sudo stretch_apply_settings` works from
# any directory. The link points at the checkout that applied it (normally
# ~/stretch4_install of the hello-robot user); running from another checkout moves it.
#
# Sourced by stretch_apply_settings. SAS_ROOT is empty on a robot and a fake root
# in the test harness.

# shellcheck disable=SC2034
ITEM_DESC="stretch_apply_settings on the PATH (/usr/local/bin link to this checkout)"

CMD_LINK="$SAS_ROOT/usr/local/bin/stretch_apply_settings"

check() {
    if [ ! -L "$CMD_LINK" ]; then
        echo "$CMD_LINK missing"; return 1
    fi
    if [ "$(readlink -f "$CMD_LINK")" != "$SAS_SELF" ]; then
        echo "$CMD_LINK points at $(readlink "$CMD_LINK"), not $SAS_SELF"; return 1
    fi
    echo "$CMD_LINK -> $SAS_SELF"
    return 0
}

plan() {
    echo "ln -sfn $SAS_SELF $CMD_LINK"
}

apply() {
    install -d "$(dirname "$CMD_LINK")"
    ln -sfn "$SAS_SELF" "$CMD_LINK"
    echo "linked $CMD_LINK -> $SAS_SELF"
}

revert() {
    if [ -L "$CMD_LINK" ]; then
        rm -f "$CMD_LINK"
        echo "removed $CMD_LINK"
    fi
}
