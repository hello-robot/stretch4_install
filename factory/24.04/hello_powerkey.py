#!/usr/bin/env python3
"""Power key: power off 3 s after a press, a second press inside the 3 s cancels.

The power board passes the robot's power button to the NUC as its power key and
turns the robot off once the NUC is off. This reads the Power Button input
devices directly, below GNOME (whose own dialog waits 60 s), and runs under a
handle-power-key inhibitor so logind does not power off at the first press.
With someone logged in to the desktop the countdown shows there as a dialog.
"""
import os
import re
import select
import struct
import subprocess
import time

FMT = 'llHHi'
SZ = struct.calcsize(FMT)
KEY_POWER = 116
COUNTDOWN_S = 3
LATE_CANCEL_S = 0.5  # the robot forwards a cancel pressed as its 3 s blink ends a little after 3 s


def power_button_events():
    devs, block = [], []
    for line in open('/proc/bus/input/devices'):
        if line.startswith('N:'):
            block = [line]
        elif line.startswith('H:') and block and 'Power Button' in block[0]:
            devs += re.findall(r'(event\d+)', line)
    return devs


def desktop_session():
    """(user, uid) of the active graphical login, None when there is none."""
    out = subprocess.run(['loginctl', 'list-sessions', '--no-legend'],
                         capture_output=True, text=True).stdout
    for line in out.splitlines():
        sid = line.split()[0]
        props = dict(p.split('=', 1) for p in subprocess.run(
            ['loginctl', 'show-session', sid, '-p', 'Name', '-p', 'User', '-p', 'Type',
             '-p', 'Class', '-p', 'Active'], capture_output=True, text=True).stdout.splitlines())
        if props.get('Class') == 'user' and props.get('Active') == 'yes' \
                and props.get('Type') in ('x11', 'wayland'):
            return props['Name'], props['User']
    return None


def show_dialog():
    session = desktop_session()
    if session is None:
        return None
    user, uid = session
    env = ['DISPLAY=:0', 'WAYLAND_DISPLAY=wayland-0', 'XDG_RUNTIME_DIR=/run/user/%s' % uid,
           'DBUS_SESSION_BUS_ADDRESS=unix:path=/run/user/%s/bus' % uid]
    return subprocess.Popen(
        ['runuser', '-u', user, '--', 'env'] + env +
        ['zenity', '--progress', '--auto-close', '--no-cancel', '--title', 'Shutting down',
         '--text', 'The robot powers off in %d s. Press the power button again to cancel.' % COUNTDOWN_S],
        stdin=subprocess.PIPE, text=True)


def update_dialog(dialog, remaining):
    if dialog is None or dialog.poll() is not None:
        return
    try:
        dialog.stdin.write('%d\n#The robot powers off in %d s. Press the power button again to cancel.\n'
                           % (100 * (COUNTDOWN_S - remaining) // COUNTDOWN_S, remaining))
        dialog.stdin.flush()
    except BrokenPipeError:
        pass


def close_dialog(dialog):
    if dialog is not None and dialog.poll() is None:
        dialog.terminate()


def main():
    names = power_button_events()
    if not names:
        raise SystemExit('no Power Button input device')
    fds = [os.open('/dev/input/%s' % name, os.O_RDONLY | os.O_NONBLOCK) for name in names]
    print('ARMED on %s' % names)
    deadline = None
    dialog = None
    while True:
        r, _, _ = select.select(fds, [], [], 0.25)
        pressed = False
        for fd in r:
            data = os.read(fd, SZ * 64)
            for off in range(0, len(data) - SZ + 1, SZ):
                _, _, etype, code, val = struct.unpack_from(FMT, data, off)
                if etype == 1 and code == KEY_POWER and val == 1:
                    pressed = True
        if pressed and deadline is None:
            print('power key: powering off in %d s' % COUNTDOWN_S)
            deadline = time.monotonic() + COUNTDOWN_S
            dialog = show_dialog()
        elif pressed:
            print('power key again: shutdown cancelled')
            deadline = None
            close_dialog(dialog)
        if deadline is not None:
            remaining = deadline - time.monotonic()
            if remaining <= -LATE_CANCEL_S:
                print('powering off')
                close_dialog(dialog)
                subprocess.run(['systemctl', 'poweroff'])
                deadline = None
            else:
                update_dialog(dialog, max(0, int(remaining + 0.999)))


if __name__ == '__main__':
    main()
