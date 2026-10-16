# shellcheck shell=bash
# Item: powerkey. The power button powers the NUC off at once.
#
# The PIMU shuts the robot down by pressing the NUC's power button (through the
# ESP) and then waits for the NUC to go away. With a desktop login, GNOME takes
# the key (gsd-media-keys holds logind's handle-power-key inhibitor, whatever
# power-button-action is set to) and shows its Power Off dialog, which counts
# down 60 s before it acts. The robot sits for that minute.
#
# This puts acpid on the button event with a handler that calls systemctl
# poweroff, independent of the desktop, and locks GNOME's power-button-action to
# nothing so no dialog is drawn. Everything it writes is a file of its own
# (drop-ins), so revert removes them and leaves the rest alone.
#
# Sourced by stretch_apply_settings. SAS_ROOT is empty on a robot and a fake root
# in the test harness.

# shellcheck disable=SC2034
ITEM_DESC="power button powers off at once (acpid handler, GNOME dialog locked off)"

PK_HANDLER="$SAS_ROOT/usr/local/sbin/hello-powerkey"
PK_EVENT="$SAS_ROOT/etc/acpi/events/hello-powerbtn"
PK_PROFILE="$SAS_ROOT/etc/dconf/profile/user"
PK_KEYFILE="$SAS_ROOT/etc/dconf/db/local.d/10-hello-powerkey"
PK_LOCK="$SAS_ROOT/etc/dconf/db/local.d/locks/hello-powerkey"
PK_DB="$SAS_ROOT/etc/dconf/db/local"

pk_handler_content() {
    cat <<'HANDLER'
#!/bin/bash
# Power button pressed (the PIMU asking for a shutdown). Power off now.
logger -t hello-powerkey "power button pressed, powering off"
exec systemctl poweroff
HANDLER
}

pk_event_content() {
    cat <<'EVENT'
event=button/power
action=/usr/local/sbin/hello-powerkey
EVENT
}

pk_keyfile_content() {
    cat <<'DCONF'
[org/gnome/settings-daemon/plugins/power]
power-button-action='nothing'
DCONF
}

pk_lock_content() {
    echo '/org/gnome/settings-daemon/plugins/power/power-button-action'
}

pk_same() {
    # pk_same <content function> <file>: true when the file holds exactly that content
    [ -f "$2" ] && cmp -s <("$1") "$2"
}

pk_acpid_installed() {
    dpkg-query -W -f='${Status}' acpid 2>/dev/null | grep -q 'install ok installed'
}

check() {
    if ! pk_acpid_installed; then
        echo "acpid package not installed"; return 1
    fi
    if ! pk_same pk_handler_content "$PK_HANDLER" || [ ! -x "$PK_HANDLER" ]; then
        echo "handler $PK_HANDLER missing or different"; return 1
    fi
    if ! pk_same pk_event_content "$PK_EVENT"; then
        echo "acpid event $PK_EVENT missing or different"; return 1
    fi
    if ! grep -qs '^system-db:local' "$PK_PROFILE"; then
        echo "dconf profile $PK_PROFILE has no system-db:local"; return 1
    fi
    if ! pk_same pk_keyfile_content "$PK_KEYFILE"; then
        echo "dconf keyfile $PK_KEYFILE missing or different"; return 1
    fi
    if ! pk_same pk_lock_content "$PK_LOCK"; then
        echo "dconf lock $PK_LOCK missing or different"; return 1
    fi
    if [ ! -f "$PK_DB" ] || [ "$PK_KEYFILE" -nt "$PK_DB" ] || [ "$PK_LOCK" -nt "$PK_DB" ]; then
        echo "dconf database $PK_DB older than the keyfile (dconf update not run)"; return 1
    fi
    case "$(systemctl is-enabled acpid 2>/dev/null)" in
        enabled|static|alias|indirect) ;;
        *) echo "acpid.service not enabled"; return 1 ;;
    esac
    if ! systemctl is-active --quiet acpid; then
        echo "acpid.service not running"; return 1
    fi
    echo "acpid handles the power button, GNOME dialog locked off"
    return 0
}

plan() {
    pk_acpid_installed || echo "apt-get install -y acpid"
    pk_same pk_handler_content "$PK_HANDLER" || echo "write $PK_HANDLER (mode 0755)"
    pk_same pk_event_content "$PK_EVENT" || echo "write $PK_EVENT"
    grep -qs '^system-db:local' "$PK_PROFILE" || echo "add system-db:local to $PK_PROFILE"
    pk_same pk_keyfile_content "$PK_KEYFILE" || echo "write $PK_KEYFILE"
    pk_same pk_lock_content "$PK_LOCK" || echo "write $PK_LOCK"
    echo "dconf update"
    echo "systemctl enable --now acpid, systemctl restart acpid"
}

apply() {
    export DEBIAN_FRONTEND=noninteractive
    if ! pk_acpid_installed; then
        echo "installing acpid"
        apt-get install -y acpid
    fi

    install -d "$(dirname "$PK_HANDLER")" "$(dirname "$PK_EVENT")"
    pk_handler_content > "$PK_HANDLER"
    chmod 0755 "$PK_HANDLER"
    echo "wrote $PK_HANDLER"
    pk_event_content > "$PK_EVENT"
    echo "wrote $PK_EVENT"

    install -d "$(dirname "$PK_PROFILE")" "$(dirname "$PK_LOCK")"
    if [ ! -f "$PK_PROFILE" ]; then
        printf 'user-db:user\nsystem-db:local\n' > "$PK_PROFILE"
        echo "wrote $PK_PROFILE"
    elif ! grep -q '^system-db:local' "$PK_PROFILE"; then
        echo 'system-db:local' >> "$PK_PROFILE"
        echo "added system-db:local to $PK_PROFILE"
    fi
    pk_keyfile_content > "$PK_KEYFILE"
    echo "wrote $PK_KEYFILE"
    pk_lock_content > "$PK_LOCK"
    echo "wrote $PK_LOCK"
    dconf update
    echo "dconf update"

    systemctl enable --now acpid >/dev/null
    systemctl restart acpid
    echo "acpid enabled and restarted (sessions already open pick the GNOME change up at next login)"
}

revert() {
    local f
    for f in "$PK_EVENT" "$PK_HANDLER" "$PK_KEYFILE" "$PK_LOCK"; do
        if [ -e "$f" ]; then
            rm -f "$f"
            echo "removed $f"
        fi
    done
    dconf update
    echo "dconf update"
    if systemctl is-active --quiet acpid; then
        systemctl restart acpid
        echo "acpid restarted (left installed and enabled)"
    fi
    echo "left $PK_PROFILE as it is"
}
