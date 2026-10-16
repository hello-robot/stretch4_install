# shellcheck shell=bash
# Item: ready-chime. One soft sound from the robot's speaker when the robot is ready.
#
# After stretch_body_server starts, hello-ready-chime watches the status the server
# publishes (its status socket only, nothing is sent) and plays ready.wav once the
# robot has been ready for 2 s: server RUNNING with status flowing, every configured
# subsystem reporting, power board ACTIVE, no device fault. If that does not happen
# within 90 s it stays silent and says why in the journal (journalctl --user -u
# hello-ready-chime). The PIMU's own buzzer is separate and not touched.
#
# Files, all ours: the sound, the player, a user unit in /etc/systemd/user (so it
# runs in the robot user's session, desktop or not) and its default.target.wants
# link. `hello-ready-chime --test` plays the sound at any time.
#
# Sourced by stretch_apply_settings. SAS_ROOT is empty on a robot and a fake root
# in the test harness.

# shellcheck disable=SC2034
ITEM_DESC="ready chime from the speaker once the robot passes its startup checks (user unit)"

RC_SRC_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../sounds" && pwd)"
RC_WAV_SRC="$RC_SRC_DIR/ready.wav"
RC_BIN_SRC="$RC_SRC_DIR/hello-ready-chime"
RC_WAV="$SAS_ROOT/usr/local/share/hello-robot/sounds/ready.wav"
RC_BIN="$SAS_ROOT/usr/local/bin/hello-ready-chime"
RC_UNIT_NAME="hello-ready-chime.service"
RC_UNIT="$SAS_ROOT/etc/systemd/user/$RC_UNIT_NAME"
RC_WANT="$SAS_ROOT/etc/systemd/user/default.target.wants/$RC_UNIT_NAME"
RC_WANT_TARGET="/etc/systemd/user/$RC_UNIT_NAME"
RC_USER="${SUDO_USER:-hello-robot}"

rc_unit_content() {
    cat <<'UNIT'
[Unit]
Description=Ready chime: one soft sound from the speaker once the robot passes its startup checks
After=stretch_body_server.service pipewire.service

[Service]
Type=oneshot
ExecStart=/usr/local/bin/hello-ready-chime
TimeoutStartSec=150

[Install]
WantedBy=default.target
UNIT
}

rc_same() {
    # rc_same <source file> <installed file>
    [ -f "$2" ] && cmp -s "$1" "$2"
}

rc_reload_user_manager() {
    # Tell the robot user's running manager about the unit; harmless when it is not up.
    if systemctl --user -M "$RC_USER@" daemon-reload >/dev/null 2>&1; then
        echo "user manager of $RC_USER reloaded"
    else
        echo "user manager of $RC_USER not reachable, the unit is read at the next login"
    fi
}

check() {
    [ -f "$RC_WAV_SRC" ] && [ -f "$RC_BIN_SRC" ] || { echo "sources missing under $RC_SRC_DIR"; return 4; }
    if ! rc_same "$RC_WAV_SRC" "$RC_WAV"; then
        echo "sound $RC_WAV missing or different"; return 1
    fi
    if ! rc_same "$RC_BIN_SRC" "$RC_BIN" || [ ! -x "$RC_BIN" ]; then
        echo "player $RC_BIN missing or different"; return 1
    fi
    if [ ! -f "$RC_UNIT" ] || ! cmp -s <(rc_unit_content) "$RC_UNIT"; then
        echo "unit $RC_UNIT missing or different"; return 1
    fi
    if [ ! -L "$RC_WANT" ] || [ "$(readlink "$RC_WANT")" != "$RC_WANT_TARGET" ]; then
        echo "unit not enabled ($RC_WANT)"; return 1
    fi
    echo "chime installed, $RC_UNIT_NAME enabled for the user session"
    return 0
}

plan() {
    rc_same "$RC_WAV_SRC" "$RC_WAV" || echo "install $RC_WAV_SRC -> $RC_WAV (mode 0644)"
    rc_same "$RC_BIN_SRC" "$RC_BIN" || echo "install $RC_BIN_SRC -> $RC_BIN (mode 0755)"
    cmp -s <(rc_unit_content) "$RC_UNIT" 2>/dev/null || echo "write $RC_UNIT"
    echo "ln -sfn $RC_WANT_TARGET $RC_WANT"
    echo "systemctl --user -M $RC_USER@ daemon-reload"
}

apply() {
    install -D -m 0644 "$RC_WAV_SRC" "$RC_WAV"
    echo "installed $RC_WAV"
    install -D -m 0755 "$RC_BIN_SRC" "$RC_BIN"
    echo "installed $RC_BIN"
    install -d "$(dirname "$RC_UNIT")" "$(dirname "$RC_WANT")"
    rc_unit_content > "$RC_UNIT"
    echo "wrote $RC_UNIT"
    ln -sfn "$RC_WANT_TARGET" "$RC_WANT"
    echo "enabled $RC_UNIT_NAME for default.target"
    rc_reload_user_manager
    echo "plays at the next start of stretch_body_server; hello-ready-chime --test plays it now"
}

revert() {
    local f
    for f in "$RC_WANT" "$RC_UNIT" "$RC_BIN" "$RC_WAV"; do
        if [ -e "$f" ] || [ -L "$f" ]; then
            rm -f "$f"
            echo "removed $f"
        fi
    done
    rc_reload_user_manager
}
