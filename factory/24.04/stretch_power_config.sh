#!/usr/bin/env bash
# ==============================================================================
# Stretch Robot Power Provisioning Script (v5)
#
# The robot's power board, not this computer, decides when the NUC powers off.
# This script makes every way of shutting down from the OS go through the robot:
#
#   1. Disables sleep, suspend and hibernate on the NUC
#   2. Powers the NUC off at once when the robot pulses its power key
#   3. Desktop: the GNOME power menu becomes 'Robot Power Off', with
#      Robot Sleep, Robot Shutdown and Robot Reboot (stretch_shutdown) in place
#      of Suspend, Restart and Power Off. Log Out and Switch User stay: remote
#      login (RDP) needs the user's local session logged out first, and the
#      other way round.
#   4. CLI/SSH: when a person at a terminal runs shutdown, poweroff, halt,
#      reboot or gnome-session-quit --power-off|--reboot, they are warned that
#      it changes only this computer, and asked whether to run the recommended
#      Robot Reboot / Shutdown / Sleep (stretch_shutdown) or the OS command.
#      Scripts and services (no terminal) and machines with no robot power
#      board (/dev/hello-power-periph) get the OS command as usual.
#      systemctl is not wrapped: as non-root, logind refuses power changes on
#      a robot (polkit); as root, 'systemctl reboot' etc. run as usual.
#
# OS-only, without the prompt: run the real command by its full path as root,
# e.g. sudo /usr/sbin/reboot.
#
# Usage:
#   sudo ./stretch_power_config.sh --apply   (or --disable)
#   sudo ./stretch_power_config.sh --revert  (or --enable)
# ==============================================================================

set -euo pipefail

# Use the real system commands, never the guards this script installs
export PATH=/usr/sbin:/usr/bin:/sbin:/bin

LOGIND_CONF="/etc/systemd/logind.conf.d/99-robot-power.conf"
POLKIT_RULES="/etc/polkit-1/rules.d/99-robot-power.rules"
POLKIT_PKLA="/etc/polkit-1/localauthority/50-local.d/99-robot-power.pkla"
DCONF_CONF="/etc/dconf/db/local.d/99-robot-power"
DCONF_LOCKS="/etc/dconf/db/local.d/locks/99-robot-power-locks"
ACPI_EVENT="/etc/acpi/events/99-robot-powerbtn"

EXT_UUID="stretch-robot-power@hello-robot.com"
EXT_DIR="/usr/share/gnome-shell/extensions/${EXT_UUID}"

LIB_DIR="/usr/local/lib/stretch-power"
GUARD="${LIB_DIR}/os-power-guard"
RUNNER="${LIB_DIR}/run-stretch-shutdown"
GUARD_DIR="/usr/local/sbin"   # Ahead of /usr/sbin and /usr/bin in PATH and in sudo's secure_path
GUARDED_CMDS=(shutdown poweroff halt reboot gnome-session-quit)

# Installed by v4 of this script
LEGACY_EXT_DIR="/usr/share/gnome-shell/extensions/hide-poweroff@robot.local"
LEGACY_WRAPPERS=(/usr/local/sbin/poweroff /usr/local/sbin/shutdown /usr/local/sbin/halt)

if [[ "$EUID" -ne 0 ]]; then
  echo "[ERROR] Please run this script as root (sudo)." >&2
  exit 1
fi

usage() {
  echo "Usage: sudo $0 [--apply | --revert]"
  echo "  --apply   (or --disable) Route desktop and CLI power commands through the robot"
  echo "  --revert  (or --enable)  Restore default Ubuntu desktop & CLI behavior"
  exit 1
}

remove_legacy() {
  rm -rf "$LEGACY_EXT_DIR"
  local w
  for w in "${LEGACY_WRAPPERS[@]}"; do
    if [[ -f "$w" && ! -L "$w" ]] && grep -q "ROBOT SAFETY" "$w"; then
      rm -f "$w"
    fi
  done
}

remove_guards() {
  # Every link to the guard, including commands an earlier version guarded
  find "$GUARD_DIR" -maxdepth 1 -lname "$GUARD" -delete 2>/dev/null || true
  rm -rf "$LIB_DIR"
}

install_guard() {
  mkdir -p "$LIB_DIR"
  cat << 'EOF' > "$GUARD"
#!/usr/bin/env bash
# Installed by stretch_power_config.sh, and linked in /usr/local/sbin as shutdown,
# poweroff, halt, reboot and gnome-session-quit, ahead of the real commands in PATH.
#
# When a person runs one of these in a terminal (local or SSH) on a robot, it warns
# that the command changes only this computer's power, recommends the robot power
# action (stretch_shutdown), and asks which to run.
# Everything else gets the real command: scripts and services with no terminal,
# commands that don't change power, and machines with no robot power board.

RUNNER=/usr/local/lib/stretch-power/run-stretch-shutdown
POWER_BOARD=/dev/hello-power-periph

name=$(basename "$0")
case "$name" in
  gnome-session-quit) real="/usr/bin/${name}" ;;
  *) real="/usr/sbin/${name}" ;;
esac

action=""   # stretch_shutdown action this command maps to; empty runs the real command

case "$name" in
  shutdown)
    action=power_off
    for a in "$@"; do
      case "$a" in
        --help|--cancel|--show|-c|-k) action=""; break ;;  # Not a power change
        --reboot|-r) action=reboot ;;
        --*) ;;
        -*[ck]*) action=""; break ;;
        -*r*) action=reboot ;;
      esac
    done ;;
  reboot)
    action=reboot
    for a in "$@"; do
      case "$a" in
        --help|--wtmp-only|-w) action=""; break ;;
        --poweroff|-p) action=power_off ;;
      esac
    done ;;
  poweroff|halt)
    action=power_off
    for a in "$@"; do
      case "$a" in
        --help|--wtmp-only|-w) action=""; break ;;
        --reboot) action=reboot ;;
      esac
    done ;;
  gnome-session-quit)
    for a in "$@"; do
      case "$a" in
        --power-off) action=power_off ;;
        --reboot) action=reboot ;;
      esac
    done ;;
esac

# Not a power change, or no person at a terminal to ask
if [[ -z "$action" || ! -t 0 || ! -t 2 ]]; then
  exec "$real" "$@"
fi

cmd="${name}${*:+ $*}"

if [[ ! -e "$POWER_BOARD" ]]; then
  echo "No robot power board found (${POWER_BOARD}). Running '${cmd}' on this computer only." >&2
  exec "$real" "$@"
fi

# logind refuses power changes from non-root users on a robot, so the
# OS-only choice runs the real command through sudo
os_cmd=("$real" "$@")
if [[ "$EUID" -ne 0 ]]; then
  os_cmd=(sudo "${os_cmd[@]}")
fi

if [[ "$action" == reboot ]]; then
  warning="'${cmd}' restarts only this computer, not the robot."
  recommended="Robot Reboot"
  labels=("Robot Reboot    stretch_shutdown --reboot      (recommended)")
  actions=(reboot)
else
  warning="'${cmd}' turns off only this computer. The robot stays on and drains its battery."
  recommended="Robot Shutdown or Robot Sleep"
  labels=("Robot Shutdown  stretch_shutdown --power_off   (recommended)"
          "Robot Sleep     stretch_shutdown --sleep")
  actions=(power_off sleep)
fi
labels+=("This computer only: ${os_cmd[*]}" "Cancel")
actions+=(os cancel)
n=${#labels[@]}

if [[ -t 2 ]]; then hi=$'\e[1;33m'; lo=$'\e[0m'; else hi=""; lo=""; fi
{
  echo "${hi}WARNING: ${warning}${lo}"
  echo "It is recommended to use ${recommended} instead."
  echo ""
  for i in "${!labels[@]}"; do
    echo "  $((i + 1))) ${labels[$i]}"
  done
  echo ""
} >&2
read -r -p "Choose [1-${n}] (default ${n}, Cancel): " choice
if ! [[ "$choice" =~ ^[0-9]+$ ]] || (( choice < 1 || choice > n )); then
  choice=$n
fi
chosen=${actions[$((choice - 1))]}

case "$chosen" in
  cancel)
    echo "Cancelled. Nothing was changed." >&2
    exit 1 ;;
  os)
    exec "${os_cmd[@]}" ;;
esac

# stretch_shutdown is installed for the robot user, so under sudo run it as that user
if [[ "$EUID" -eq 0 ]]; then
  if [[ -z "${SUDO_USER:-}" || "$SUDO_USER" == root ]]; then
    echo "Run 'stretch_shutdown --${chosen}' as the robot user, not root." >&2
    exit 1
  fi
  sudo -u "$SUDO_USER" -H "$RUNNER" "--${chosen}"
else
  "$RUNNER" "--${chosen}"
fi
status=$?
if [[ $status -ne 0 ]]; then
  echo "" >&2
  echo "Could not reach the robot. To change only this computer's power, run: sudo ${real}${*:+ $*}" >&2
fi
exit $status
EOF
  chmod 755 "$GUARD"

  # Runs stretch_shutdown for the desktop menu and the CLI guard, which may not
  # have the Stretch environment that a terminal gets from ~/.bashrc
  cat << 'EOF' > "$RUNNER"
#!/usr/bin/env bash
# Installed by stretch_power_config.sh. Runs stretch_shutdown -y (the caller has
# already confirmed) with the environment the Stretch Body Server runs with.
# The desktop menu and 'sudo -u' (the CLI guard) don't get the ROS/Python setup
# a terminal gets from ~/.bashrc. Without it 'stretch_body_server --kill' can't
# import its dependencies (e.g. xacro), so the server keeps the power board.
export PATH="${HOME}/.local/bin:${PATH}"
# Under 'sudo -u' there is no user session environment, which
# 'stretch_body_server --kill' needs to stop the server daemon (systemctl --user)
export XDG_RUNTIME_DIR="${XDG_RUNTIME_DIR:-/run/user/$(id -u)}"
# Keep Python's output in order, so the last lines (which the desktop menu
# shows when it fails) are the real error
export PYTHONUNBUFFERED=1

# Take each variable the server's user service sets (HELLO_FLEET_*, PYTHONPATH,
# LD_LIBRARY_PATH, AMENT_PREFIX_PATH, ...) that this environment lacks
set -f
for kv in $(/usr/bin/systemctl --user show -p Environment --value stretch_body_server.service 2>/dev/null); do
  k=${kv%%=*}
  if [[ "$k" =~ ^[A-Za-z_][A-Za-z0-9_]*$ && -z "${!k:-}" ]]; then
    export "$kv"
  fi
done
set +f

# No server service: take the fleet settings from ~/.bashrc
if [[ -z "${HELLO_FLEET_ID:-}" || -z "${HELLO_FLEET_PATH:-}" ]]; then
  eval "$(grep -E '^[[:space:]]*export[[:space:]]+HELLO_FLEET_(PATH|ID)=' "${HOME}/.bashrc" 2>/dev/null)"
fi
exec stretch_shutdown -y "$@"
EOF
  chmod 755 "$RUNNER"

  local c
  for c in "${GUARDED_CMDS[@]}"; do
    rm -f "${GUARD_DIR}/${c}"
    ln -s "$GUARD" "${GUARD_DIR}/${c}"
  done
}

install_extension() {
  mkdir -p "$EXT_DIR"
  cat << EOF > "${EXT_DIR}/metadata.json"
{
  "uuid": "${EXT_UUID}",
  "name": "Stretch Robot Power",
  "description": "Replaces Suspend, Restart and Power Off with Robot Sleep, Robot Shutdown and Robot Reboot",
  "shell-version": ["45", "46", "47", "48"]
}
EOF

  cat << 'EOF' > "${EXT_DIR}/extension.js"
import Clutter from 'gi://Clutter';
import Gio from 'gi://Gio';
import GLib from 'gi://GLib';
import {Extension} from 'resource:///org/gnome/shell/extensions/extension.js';
import * as Main from 'resource:///org/gnome/shell/ui/main.js';
import * as ModalDialog from 'resource:///org/gnome/shell/ui/modalDialog.js';
import * as Dialog from 'resource:///org/gnome/shell/ui/dialog.js';
import * as PopupMenu from 'resource:///org/gnome/shell/ui/popupMenu.js';

const RUNNER = '/usr/local/lib/stretch-power/run-stretch-shutdown';
const MENU_TITLE = 'Robot Power Off';

// Same wording as stretch_shutdown
const ACTIONS = [
    {
        arg: '--sleep', label: 'Robot Sleep', confirm: 'Sleep',
        body: 'This computer shuts down and the robot goes to sleep. The power button ' +
              'pulses yellow, then red. Tap the power button to wake the robot.',
    },
    {
        arg: '--power_off', label: 'Robot Shutdown', confirm: 'Shut Down',
        body: 'This computer shuts down, then the robot turns off fully, as after a long ' +
              'press of the power button. With the charger connected it stays off and ' +
              'charging. Press the power button to turn it on again.',
    },
    {
        arg: '--reboot', label: 'Robot Reboot', confirm: 'Reboot',
        body: 'This computer shuts down, the robot sleeps for a moment, then it wakes by ' +
              'itself and this computer starts again. The power button pulses yellow ' +
              'until the robot is back up.',
    },
];

// The power button at the bottom right of Quick Settings
function findShutdownItem() {
    const box = Main.panel.statusArea.quickSettings?._system?._systemItem?.child;
    if (!box)
        return null;
    return box.get_children().find(
        c => c.menu && c.icon_name === 'system-shutdown-symbolic') ?? null;
}

export default class StretchRobotPowerExtension extends Extension {
    enable() {
        this._tries = 0;
        this._attach();
    }

    // Quick Settings builds its items asynchronously at login, so retry until they exist
    _attach() {
        const item = findShutdownItem();
        if (!item) {
            if (this._tries++ < 80) {
                this._retryId = GLib.timeout_add(GLib.PRIORITY_DEFAULT, 250, () => {
                    this._retryId = 0;
                    this._attach();
                    return GLib.SOURCE_REMOVE;
                });
            }
            return;
        }

        this._item = item;
        const menu = item.menu;

        // Take out Suspend, Restart and Power Off: the items above the separator.
        // Log Out and Switch User stay below it, since remote login (RDP) only
        // starts once the user's local session is logged out, and vice versa.
        const children = menu.box.get_children();
        const sep = children.findIndex(c => c instanceof PopupMenu.PopupSeparatorMenuItem);
        this._origChildren = sep >= 0 ? children.slice(0, sep) : children;
        this._origChildren.forEach(c => menu.box.remove_child(c));

        menu.setHeader('system-shutdown-symbolic', MENU_TITLE);
        this._origAccessibleName = item.accessible_name;
        item.accessible_name = `${MENU_TITLE} Menu`;
        this._ourItems = ACTIONS.map((a, i) => {
            const mi = new PopupMenu.PopupMenuItem(a.label);
            mi.connect('activate', () => this._confirm(a));
            menu.addMenuItem(mi, i);
            return mi;
        });

        // GNOME hides the button when it thinks no power action is allowed
        this._visId = item.connect('notify::visible', () => {
            if (!item.visible)
                item.show();
        });
        item.show();
    }

    _confirm(action) {
        Main.panel.closeQuickSettings();
        const dialog = new ModalDialog.ModalDialog();
        dialog.contentLayout.add_child(new Dialog.MessageDialogContent({
            title: `${action.label}?`,
            description: action.body,
        }));
        // Cancel comes first, so it has the key focus
        dialog.setButtons([
            {label: 'Cancel', action: () => dialog.close(), key: Clutter.KEY_Escape},
            {label: action.confirm, action: () => {
                dialog.close();
                this._run(action);
            }},
        ]);
        dialog.open();
    }

    _run(action) {
        let proc;
        try {
            proc = Gio.Subprocess.new([RUNNER, action.arg],
                Gio.SubprocessFlags.STDOUT_PIPE | Gio.SubprocessFlags.STDERR_MERGE);
        } catch (e) {
            Main.notifyError(`${action.label} failed`, e.message);
            return;
        }
        proc.communicate_utf8_async(null, null, (p, res) => {
            let out = '';
            try {
                [, out] = p.communicate_utf8_finish(res);
            } catch (e) {
                out = e.message;
            }
            if (p.get_successful()) {
                Main.notify(action.label, 'This computer will shut down in a few seconds.');
            } else {
                const tail = (out ?? '').trim().split('\n').slice(-3).join('\n');
                Main.notifyError(`${action.label} failed`,
                    tail || 'Could not reach the robot. Run stretch_system_check.');
            }
        });
    }

    disable() {
        if (this._retryId) {
            GLib.source_remove(this._retryId);
            this._retryId = 0;
        }
        if (!this._item)
            return;

        const item = this._item;
        item.disconnect(this._visId);
        this._ourItems.forEach(i => i.destroy());
        this._origChildren.forEach((c, i) => item.menu.box.insert_child_at_index(c, i));
        item.menu.setHeader('system-shutdown-symbolic', 'Power Off');
        item.accessible_name = this._origAccessibleName;
        item._sync?.();

        this._item = null;
        this._ourItems = null;
        this._origChildren = null;
    }
}
EOF
  chmod -R a+rX "$EXT_DIR"
}

apply_config() {
  echo "==> [1/8] Masking all sleep and suspend targets..."
  systemctl mask \
    sleep.target \
    suspend.target \
    hibernate.target \
    hybrid-sleep.target \
    suspend-then-hibernate.target

  echo "==> [2/8] Configuring systemd-logind for immediate hardware poweroff..."
  mkdir -p /etc/systemd/logind.conf.d
  cat << 'EOF' > "$LOGIND_CONF"
[Login]
HandlePowerKey=poweroff
PowerKeyIgnoreInhibited=yes
HandleSuspendKey=ignore
HandleHibernateKey=ignore
HandleLidSwitch=ignore
IdleAction=ignore
InhibitDelayMaxSec=1
EOF

  # acpid fallback, if installed. The full path skips the CLI guard.
  if [[ -d /etc/acpi/events ]]; then
    cat << 'EOF' > "$ACPI_EVENT"
event=button[ /]power
action=/usr/sbin/poweroff
EOF
    systemctl restart acpid 2>/dev/null || true
  fi

  echo "==> [3/8] Blocking the power-key inhibitor and non-root power changes over D-Bus..."
  mkdir -p /etc/polkit-1/rules.d
  cat << 'EOF' > "$POLKIT_RULES"
// polkitd runs with PrivateDevices=yes, so /dev/hello-power-periph is not
// visible to it. The board's udev symlink is in the udev database under /run.
function hasPowerBoard() {
    try {
        polkit.spawn(["/bin/sh", "-c",
            "/usr/bin/grep -qsx S:hello-power-periph /run/udev/data/c*"]);
        return true;
    } catch (e) {
        return false;
    }
}

var POWER_ACTIONS = ["power-off", "reboot", "halt", "suspend", "hibernate"];

function isPowerAction(id) {
    return POWER_ACTIONS.some(function(a) {
        return id.indexOf("org.freedesktop.login1." + a) === 0;
    });
}

polkit.addRule(function(action, subject) {
    // 1. Prevent GNOME from taking the low-level lock on the hardware power key
    if (action.id.indexOf("org.freedesktop.login1.inhibit-handle-") === 0) {
        return polkit.Result.NO;
    }
    // 2. On a robot (power board present), block non-root power changes through
    //    logind: GNOME's own dialogs, systemctl, busctl/gdbus. Power changes go
    //    through stretch_shutdown instead; root can still use the OS commands.
    //    Log out and switch user are not power changes and stay allowed.
    if (subject.user !== "root" && isPowerAction(action.id) && hasPowerBoard()) {
        return polkit.Result.NO;
    }
});
EOF

  if [[ -d /etc/polkit-1/localauthority/50-local.d ]]; then
    cat << 'EOF' > "$POLKIT_PKLA"
[Robot Block GNOME Power Key Inhibitor and OS Power Changes]
Identity=unix-user:*
Action=org.freedesktop.login1.inhibit-handle-*;org.freedesktop.login1.power-off*;org.freedesktop.login1.reboot*;org.freedesktop.login1.halt*;org.freedesktop.login1.suspend*;org.freedesktop.login1.hibernate*
ResultAny=no
ResultInactive=no
ResultActive=no
EOF
  fi

  echo "==> [4/8] Removing v4 guardrails (hide-Power-Off extension, CLI wrappers)..."
  remove_legacy

  echo "==> [5/8] Installing GNOME extension for the 'Robot Power Off' menu..."
  GNOME_VER=$(gnome-shell --version 2>/dev/null | grep -oP '\d+' | head -1 || echo "0")
  if [[ "$GNOME_VER" -ge 45 ]]; then
    install_extension
  else
    echo "    [WARN] GNOME Shell ${GNOME_VER} is older than 45; skipping the desktop menu."
  fi

  echo "==> [6/8] Locking GNOME dconf settings & forcing extension activation..."
  if command -v dconf >/dev/null 2>&1; then
    mkdir -p /etc/dconf/profile
    cat << 'EOF' > /etc/dconf/profile/user
user-db:user
system-db:local
EOF

    mkdir -p /etc/dconf/db/local.d/locks
    cat << EOF > "$DCONF_CONF"
[org/gnome/settings-daemon/plugins/power]
sleep-inactive-ac-type='nothing'
sleep-inactive-ac-timeout=0
sleep-inactive-battery-type='nothing'
sleep-inactive-battery-timeout=0
power-button-action='nothing'

[org/gnome/shell]
disable-user-extensions=false
enabled-extensions=['${EXT_UUID}', 'ubuntu-dock@ubuntu.com', 'ubuntu-appindicators@ubuntu.com', 'ding@rastersoft.com', 'tiling-assistant@ubuntu.com']
EOF

    cat << 'EOF' > "$DCONF_LOCKS"
/org/gnome/settings-daemon/plugins/power/sleep-inactive-ac-type
/org/gnome/settings-daemon/plugins/power/power-button-action
/org/gnome/shell/enabled-extensions
/org/gnome/shell/disable-user-extensions
EOF
    dconf update
  fi

  echo "==> [7/8] Installing CLI/SSH power command guards in ${GUARD_DIR}..."
  remove_guards
  install_guard

  echo "==> [8/8] Reloading system services..."
  systemctl daemon-reload
  systemctl restart polkit 2>/dev/null || true
  echo "[SUCCESS] Robot power configuration APPLIED!"
  echo "          Log out and back in (or restart GNOME Shell) to see the Robot Power Off menu."
}

revert_config() {
  echo "==> [1/5] Unmasking sleep and suspend targets..."
  systemctl unmask \
    sleep.target \
    suspend.target \
    hibernate.target \
    hybrid-sleep.target \
    suspend-then-hibernate.target

  echo "==> [2/5] Removing systemd-logind and ACPI overrides..."
  rm -f "$LOGIND_CONF" "$ACPI_EVENT"
  systemctl restart acpid 2>/dev/null || true

  echo "==> [3/5] Removing Polkit rules and GNOME extensions..."
  rm -f "$POLKIT_RULES" "$POLKIT_PKLA"
  rm -rf "$EXT_DIR"

  echo "==> [4/5] Removing GNOME dconf locks..."
  rm -f "$DCONF_CONF" "$DCONF_LOCKS"
  if command -v dconf >/dev/null 2>&1; then
    dconf update
  fi

  echo "==> [5/5] Removing CLI/SSH power command guards..."
  remove_guards
  remove_legacy

  systemctl daemon-reload
  systemctl restart polkit 2>/dev/null || true
  echo "[SUCCESS] Reverted to stock Ubuntu settings! Reboot once to take full effect."
}

case "${1:-}" in
  --apply|--disable)
    apply_config
    ;;
  --revert|--enable)
    revert_config
    ;;
  *)
    usage
    ;;
esac

systemctl reload systemd-logind
