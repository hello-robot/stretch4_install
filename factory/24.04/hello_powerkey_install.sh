#!/bin/bash
# Make the NUC power off at once when the power button is pressed.
#
# The PIMU shuts the robot down by pressing the NUC's power button (through the
# ESP) and then waits for the NUC to go away. With a desktop login, GNOME takes
# the key (gsd-media-keys holds logind's handle-power-key inhibitor, whatever
# power-button-action is set to) and shows its Power Off dialog, which counts
# down 60 s before it acts. The robot sits for that minute.
#
# This puts acpid on the button event with a handler that calls systemctl
# poweroff, independent of the desktop, and locks GNOME's power-button-action to
# nothing so no dialog is drawn. Run as root. Idempotent.
set -euo pipefail
export DEBIAN_FRONTEND=noninteractive

if ! dpkg -s acpid >/dev/null 2>&1; then
    apt-get install -y acpid
fi

cat > /usr/local/sbin/hello-powerkey <<'HANDLER'
#!/bin/bash
# Power button pressed (the PIMU asking for a shutdown). Power off now.
logger -t hello-powerkey "power button pressed, powering off"
exec systemctl poweroff
HANDLER
chmod 0755 /usr/local/sbin/hello-powerkey

install -d /etc/acpi/events
cat > /etc/acpi/events/hello-powerbtn <<'EVENT'
event=button/power
action=/usr/local/sbin/hello-powerkey
EVENT

# GNOME: no Power Off dialog on the key, locked for every user.
install -d /etc/dconf/profile /etc/dconf/db/local.d/locks
if [ ! -f /etc/dconf/profile/user ]; then
    printf 'user-db:user\nsystem-db:local\n' > /etc/dconf/profile/user
elif ! grep -q '^system-db:local' /etc/dconf/profile/user; then
    echo 'system-db:local' >> /etc/dconf/profile/user
fi
cat > /etc/dconf/db/local.d/10-hello-powerkey <<'DCONF'
[org/gnome/settings-daemon/plugins/power]
power-button-action='nothing'
DCONF
echo '/org/gnome/settings-daemon/plugins/power/power-button-action' \
    > /etc/dconf/db/local.d/locks/hello-powerkey
dconf update

systemctl enable --now acpid >/dev/null
systemctl restart acpid
echo "hello-powerkey: acpid handles the power button, GNOME dialog locked off (sessions already open pick it up at next login)."
