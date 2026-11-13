# shellcheck shell=bash
# Item: powerkey. The power button powers the NUC off at once; a press commits.
#
# The PIMU passes the robot's power button to the NUC as its power key and puts
# the robot to sleep once the NUC is off; a sleep from the app or the host and
# the PIMU's own shutdowns press the same key. With a desktop login, GNOME takes
# the key (gsd-media-keys holds logind's handle-power-key inhibitor, whatever
# power-button-action is set to) and shows its Power Off dialog, which counts
# down 60 s before it acts.
#
# A logind drop-in makes logind power off on the key and ignore that inhibitor.
# GNOME's power-button-action is locked to nothing for the user session and the
# login screen so no dialog is drawn. The countdown service and the acpid
# handler of earlier versions are removed. Everything it writes is a file of its
# own (drop-ins), so revert removes them and leaves the rest alone.
#
# Sourced by stretch_apply_settings. SAS_ROOT is empty on a robot and a fake root
# in the test harness.

# shellcheck disable=SC2034
ITEM_DESC="power button powers the NUC off at once (logind drop-in, GNOME dialog locked off)"

PK_LOGIND="$SAS_ROOT/etc/systemd/logind.conf.d/50-hello-powerkey.conf"
PK_OLD_SCRIPT="$SAS_ROOT/usr/local/sbin/hello_powerkey.py"
PK_OLD_UNIT="$SAS_ROOT/etc/systemd/system/hello-powerkey.service"
PK_OLD_HANDLER="$SAS_ROOT/usr/local/sbin/hello-powerkey"
PK_OLD_EVENT="$SAS_ROOT/etc/acpi/events/hello-powerbtn"
PK_PROFILE="$SAS_ROOT/etc/dconf/profile/user"
PK_GDM_PROFILE="$SAS_ROOT/etc/dconf/profile/gdm"
PK_KEYFILE="$SAS_ROOT/etc/dconf/db/local.d/10-hello-powerkey"
PK_LOCK="$SAS_ROOT/etc/dconf/db/local.d/locks/hello-powerkey"
PK_DB="$SAS_ROOT/etc/dconf/db/local"
PK_GDM_KEYFILE="$SAS_ROOT/etc/dconf/db/gdm.d/10-hello-powerkey"
PK_GDM_LOCK="$SAS_ROOT/etc/dconf/db/gdm.d/locks/hello-powerkey"
PK_GDM_DB="$SAS_ROOT/etc/dconf/db/gdm"

pk_logind_content() {
    cat <<'CONF'
[Login]
HandlePowerKey=poweroff
PowerKeyIgnoreInhibited=yes
CONF
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

check() {
    if [ -e "$PK_OLD_EVENT" ] || [ -e "$PK_OLD_HANDLER" ]; then
        echo "acpid handler $PK_OLD_EVENT of an earlier version still installed"; return 1
    fi
    if [ -e "$PK_OLD_UNIT" ] || [ -e "$PK_OLD_SCRIPT" ]; then
        echo "countdown service $PK_OLD_UNIT of an earlier version still installed"; return 1
    fi
    if ! pk_same pk_logind_content "$PK_LOGIND"; then
        echo "logind drop-in $PK_LOGIND missing or different"; return 1
    fi
    if ! grep -qs '^system-db:local' "$PK_PROFILE"; then
        echo "dconf profile $PK_PROFILE has no system-db:local"; return 1
    fi
    if ! grep -qs '^system-db:gdm' "$PK_GDM_PROFILE"; then
        echo "dconf profile $PK_GDM_PROFILE has no system-db:gdm"; return 1
    fi
    if ! pk_same pk_keyfile_content "$PK_KEYFILE" || ! pk_same pk_keyfile_content "$PK_GDM_KEYFILE"; then
        echo "dconf keyfile $PK_KEYFILE or $PK_GDM_KEYFILE missing or different"; return 1
    fi
    if ! pk_same pk_lock_content "$PK_LOCK" || ! pk_same pk_lock_content "$PK_GDM_LOCK"; then
        echo "dconf lock $PK_LOCK or $PK_GDM_LOCK missing or different"; return 1
    fi
    if [ ! -f "$PK_DB" ] || [ "$PK_KEYFILE" -nt "$PK_DB" ] || [ "$PK_LOCK" -nt "$PK_DB" ] ||
        [ ! -f "$PK_GDM_DB" ] || [ "$PK_GDM_KEYFILE" -nt "$PK_GDM_DB" ] || [ "$PK_GDM_LOCK" -nt "$PK_GDM_DB" ]; then
        echo "dconf database older than the keyfiles (dconf update not run)"; return 1
    fi
    echo "logind powers off on the power key, GNOME dialog locked off"
    return 0
}

plan() {
    [ -e "$PK_OLD_EVENT" ] && echo "remove $PK_OLD_EVENT, restart acpid"
    [ -e "$PK_OLD_HANDLER" ] && echo "remove $PK_OLD_HANDLER"
    [ -e "$PK_OLD_UNIT" ] && echo "stop and disable hello-powerkey, remove $PK_OLD_UNIT"
    [ -e "$PK_OLD_SCRIPT" ] && echo "remove $PK_OLD_SCRIPT"
    pk_same pk_logind_content "$PK_LOGIND" || echo "write $PK_LOGIND"
    grep -qs '^system-db:local' "$PK_PROFILE" || echo "add system-db:local to $PK_PROFILE"
    grep -qs '^system-db:gdm' "$PK_GDM_PROFILE" || echo "add system-db:gdm to $PK_GDM_PROFILE"
    pk_same pk_keyfile_content "$PK_KEYFILE" || echo "write $PK_KEYFILE"
    pk_same pk_lock_content "$PK_LOCK" || echo "write $PK_LOCK"
    pk_same pk_keyfile_content "$PK_GDM_KEYFILE" || echo "write $PK_GDM_KEYFILE"
    pk_same pk_lock_content "$PK_GDM_LOCK" || echo "write $PK_GDM_LOCK"
    echo "dconf update"
    echo "systemctl daemon-reload, systemctl kill --signal=HUP systemd-logind"
}

apply() {
    local f
    for f in "$PK_OLD_EVENT" "$PK_OLD_HANDLER"; do
        if [ -e "$f" ]; then
            rm -f "$f"
            echo "removed $f"
        fi
    done
    if systemctl is-active --quiet acpid; then
        systemctl restart acpid
        echo "acpid restarted"
    fi

    if [ -e "$PK_OLD_UNIT" ]; then
        systemctl disable --now hello-powerkey >/dev/null 2>&1
        echo "hello-powerkey stopped and disabled"
    fi
    for f in "$PK_OLD_UNIT" "$PK_OLD_SCRIPT"; do
        if [ -e "$f" ]; then
            rm -f "$f"
            echo "removed $f"
        fi
    done
    install -d "$(dirname "$PK_LOGIND")"
    pk_logind_content > "$PK_LOGIND"
    echo "wrote $PK_LOGIND"

    install -d "$(dirname "$PK_PROFILE")" "$(dirname "$PK_LOCK")" "$(dirname "$PK_GDM_LOCK")"
    if [ ! -f "$PK_PROFILE" ]; then
        printf 'user-db:user\nsystem-db:local\n' > "$PK_PROFILE"
        echo "wrote $PK_PROFILE"
    elif ! grep -q '^system-db:local' "$PK_PROFILE"; then
        echo 'system-db:local' >> "$PK_PROFILE"
        echo "added system-db:local to $PK_PROFILE"
    fi
    if [ ! -f "$PK_GDM_PROFILE" ]; then
        printf 'user-db:user\nsystem-db:gdm\nfile-db:/var/lib/gdm3/greeter-dconf-defaults\n' > "$PK_GDM_PROFILE"
        echo "wrote $PK_GDM_PROFILE"
    elif ! grep -q '^system-db:gdm' "$PK_GDM_PROFILE"; then
        echo 'system-db:gdm' >> "$PK_GDM_PROFILE"
        echo "added system-db:gdm to $PK_GDM_PROFILE"
    fi
    for f in "$PK_KEYFILE" "$PK_GDM_KEYFILE"; do
        pk_keyfile_content > "$f"
        echo "wrote $f"
    done
    for f in "$PK_LOCK" "$PK_GDM_LOCK"; do
        pk_lock_content > "$f"
        echo "wrote $f"
    done
    dconf update
    echo "dconf update"

    systemctl daemon-reload
    systemctl kill --signal=HUP systemd-logind
    echo "logind reloaded (sessions already open pick the GNOME change up at next login)"
}

revert() {
    local f
    for f in "$PK_LOGIND" "$PK_KEYFILE" "$PK_LOCK" "$PK_GDM_KEYFILE" "$PK_GDM_LOCK"; do
        if [ -e "$f" ]; then
            rm -f "$f"
            echo "removed $f"
        fi
    done
    systemctl kill --signal=HUP systemd-logind
    dconf update
    echo "dconf update"
    echo "left $PK_PROFILE and $PK_GDM_PROFILE as they are"
}
