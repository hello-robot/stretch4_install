# shellcheck shell=bash
# Item: lidar-ptp. The NUC as PTP grandmaster for the Hesai lidars
# (lidar-ptp4l.service and lidar-phc2sys.service).
#
# Not managed here yet. FAB installs these through stretch_production_tools_ii
# (python/fab_tests/test_FAB_ptp_grandmaster.py): it installs the linuxptp package,
# renders the two unit templates for the lidar interface (the one carrying
# 192.168.1.2), copies /etc/linuxptp/ptp4l.conf and the /usr/local/sbin/lidar-ptp-gm-settings
# helper, then enables both units. That is more than a copy of unit files, so this
# item only reports what is on the machine until the install moves here.
#
# check exits 3 (unmanaged): the state is shown, it never counts as missing.

# shellcheck disable=SC2034
ITEM_DESC="NUC as PTP grandmaster for the lidars (reported only, installed by FAB)"

PTP_UNIT_DIR="$SAS_ROOT/etc/systemd/system"

check() {
    local present=() absent=() u
    for u in lidar-ptp4l lidar-phc2sys; do
        if [ -f "$PTP_UNIT_DIR/$u.service" ]; then
            present+=("$u")
        else
            absent+=("$u")
        fi
    done
    if [ ${#absent[@]} -eq 0 ]; then
        if systemctl is-active --quiet lidar-ptp4l && systemctl is-active --quiet lidar-phc2sys; then
            echo "not managed yet; both units present and running"
        else
            echo "not managed yet; both units present, not both running"
        fi
    elif [ ${#present[@]} -eq 0 ]; then
        echo "not managed yet; units absent (FAB installs them with test_FAB_ptp_grandmaster)"
    else
        echo "not managed yet; only ${present[*]} present"
    fi
    return 3
}

plan() {
    echo "nothing: this item is not managed yet"
}

apply() {
    echo "nothing: this item is not managed yet"
}
