#!/bin/bash
# stretch_apply_settings: bring the NUC settings of a Stretch 4 up to the maintained list.
#
# This is the rerunnable slice of stretch_initial_setup.sh: the NUC settings that a
# robot must carry, kept as one item file each in factory/<ubuntu version>/settings.d.
# Each item knows how to check its setting, apply it, say what apply would do, and
# (where cheap) revert it. This script runs them and reports one line per item. It is
# safe to run again at any time: it changes only what is missing and says what it did.
#
#   stretch_apply_settings                 check only, exit 1 if anything is missing
#   sudo stretch_apply_settings --apply    apply what is missing, re-check, report
#   stretch_apply_settings --dry-run       show what --apply would do
#   stretch_apply_settings --json          machine readable report
#   sudo stretch_apply_settings --revert powerkey
#
# Only NUC settings live here. Firmware has REx_firmware_updater, the Python packages
# have pip and stretch_system_check --check_updates covers both; the factory
# stretch_system_update.sh pulls the HQ repos. None of that is done here.
set -u -o pipefail

SAS_SELF="$(readlink -f "${BASH_SOURCE[0]}")"
SAS_REPO="$(cd "$(dirname "$SAS_SELF")" && pwd)"
SAS_ROOT="${STRETCH_SYSROOT:-}"
SAS_LOG="${STRETCH_APPLY_SETTINGS_LOG:-$SAS_ROOT/var/log/stretch_apply_settings.log}"
export SAS_SELF SAS_REPO SAS_ROOT SAS_LOG

usage() {
    cat <<EOF
Usage: stretch_apply_settings [mode] [options]

Modes (one of, default --check):
  --check            Report the state of every item. Exit 1 if anything is missing.
  --apply            Apply the missing items, then check again. Needs root.
  --dry-run          Print what --apply would do, change nothing.
  --revert ID        Undo one item where that is cheap. Needs root.
  --list             List the items with a one line description.

Options:
  --only ID          Limit --check, --apply and --dry-run to one item.
  --json             Machine readable output instead of the text report.
  --verbose          Show the output of each apply, not only on failure.
  -h, --help         This text.

States: ok (present and correct), missing (not there or different), changed
(applied in this run), failed (check or apply did not succeed), unmanaged (the
item is on the list but has no installer here yet).
EOF
}

die() {
    echo "stretch_apply_settings: $*" >&2
    exit 2
}

MODE=check
ONLY=
JSON=0
VERBOSE=0
REVERT_ID=
while [ $# -gt 0 ]; do
    case "$1" in
        --check)   MODE=check ;;
        --apply)   MODE=apply ;;
        --dry-run) MODE=dry-run ;;
        --list)    MODE=list ;;
        --revert)  MODE=revert; shift; [ $# -gt 0 ] || die "--revert needs an item id"; REVERT_ID=$1 ;;
        --only)    shift; [ $# -gt 0 ] || die "--only needs an item id"; ONLY=$1 ;;
        --json)    JSON=1 ;;
        --verbose) VERBOSE=1 ;;
        -h|--help) usage; exit 0 ;;
        *) die "unknown argument '$1' (try --help)" ;;
    esac
    shift
done

if [ -n "${STRETCH_SETTINGS_DIR:-}" ]; then
    ITEM_DIR="$STRETCH_SETTINGS_DIR"
else
    OS_RELEASE="$SAS_ROOT/etc/os-release"
    [ -r "$OS_RELEASE" ] || die "cannot read $OS_RELEASE"
    # shellcheck disable=SC1090
    VERSION_ID="$(. "$OS_RELEASE" && echo "${VERSION_ID:-}")"
    ITEM_DIR="$SAS_REPO/factory/$VERSION_ID/settings.d"
fi
[ -d "$ITEM_DIR" ] || die "no settings list for this OS at $ITEM_DIR"

ITEM_FILES=()
for f in "$ITEM_DIR"/[0-9][0-9]-*.sh; do
    [ -f "$f" ] && ITEM_FILES+=("$f")
done
[ ${#ITEM_FILES[@]} -gt 0 ] || die "no items in $ITEM_DIR"

item_id() {
    local b
    b="$(basename "$1" .sh)"
    echo "${b#[0-9][0-9]-}"
}

if [ -n "$ONLY" ]; then
    FILTERED=()
    for f in "${ITEM_FILES[@]}"; do
        [ "$(item_id "$f")" = "$ONLY" ] && FILTERED+=("$f")
    done
    [ ${#FILTERED[@]} -gt 0 ] || die "no item with id '$ONLY' (see --list)"
    ITEM_FILES=("${FILTERED[@]}")
fi

is_root() {
    [ "$(id -u)" = "0" ] || [ -n "$SAS_ROOT" ]
}

case "$MODE" in
    apply|revert)
        is_root || die "--$MODE needs root. Run: sudo stretch_apply_settings --$MODE${REVERT_ID:+ $REVERT_ID}" ;;
esac

sas_log() {
    # sas_log <item> <text>: one line in the log, only when we may write it.
    local line
    line="$(date '+%Y-%m-%dT%H:%M:%S') $1 $2"
    if is_root; then
        mkdir -p "$(dirname "$SAS_LOG")" 2>/dev/null || true
        echo "$line" >> "$SAS_LOG" 2>/dev/null || true
    fi
}
export -f sas_log

# run_fn <file> <function>: source the item in a subshell and call one function.
# Stdout goes to RUN_OUT, the exit status to RUN_RC.
RUN_OUT=
RUN_RC=0
run_fn() {
    local file=$1 fn=$2
    local strict=0
    if [ "$fn" = apply ] || [ "$fn" = revert ]; then
        strict=1
    fi
    # shellcheck disable=SC1090
    if RUN_OUT="$( ( [ $strict = 1 ] && set -e; . "$file" && "$fn" ) 2>&1 )"; then
        RUN_RC=0
    else
        RUN_RC=$?
    fi
}

first_line() {
    printf '%s\n' "$1" | sed -n '1p'
}

# check_item <file>: sets ITEM_STATE (ok, missing, unmanaged, failed) and ITEM_REASON.
check_item() {
    run_fn "$1" check
    ITEM_REASON="$(first_line "$RUN_OUT")"
    case $RUN_RC in
        0) ITEM_STATE=ok ;;
        1) ITEM_STATE=missing ;;
        3) ITEM_STATE=unmanaged ;;
        *) ITEM_STATE=failed; ITEM_REASON="check exited $RUN_RC: ${ITEM_REASON:-no output}" ;;
    esac
}

json_escape() {
    local s=$1
    s=${s//\\/\\\\}
    s=${s//\"/\\\"}
    s=${s//$'\n'/\\n}
    s=${s//$'\t'/\\t}
    s=${s//$'\r'/}
    printf '%s' "$s"
}

print_row() {
    # print_row <id> <state> <reason>
    printf '%-12s %-9s %s\n' "$1" "$2" "$3"
}

print_detail() {
    # indent a block of text under its row
    [ -n "$1" ] || return 0
    printf '%s\n' "$1" | sed 's/^/             /'
}

N_OK=0 N_MISSING=0 N_CHANGED=0 N_FAILED=0 N_UNMANAGED=0
count_state() {
    case $1 in
        ok) N_OK=$((N_OK + 1)) ;;
        missing) N_MISSING=$((N_MISSING + 1)) ;;
        changed) N_CHANGED=$((N_CHANGED + 1)) ;;
        failed) N_FAILED=$((N_FAILED + 1)) ;;
        unmanaged) N_UNMANAGED=$((N_UNMANAGED + 1)) ;;
    esac
}

JSON_ITEMS=()
add_json_item() {
    # add_json_item <id> <state> <reason> <changed 0|1> [detail]
    local changed=false
    [ "$4" = 1 ] && changed=true
    JSON_ITEMS+=("{\"id\":\"$(json_escape "$1")\",\"state\":\"$2\",\"reason\":\"$(json_escape "$3")\",\"changed\":$changed,\"detail\":\"$(json_escape "${5:-}")\"}")
}

summary_action() {
    if [ $N_FAILED -gt 0 ]; then
        echo "look at $SAS_LOG and the detail above"
    elif [ $N_MISSING -gt 0 ]; then
        echo "sudo stretch_apply_settings --apply${ONLY:+ --only $ONLY}"
    fi
}

emit_json() {
    local items="" i action root=false
    for i in "${JSON_ITEMS[@]}"; do
        items="${items:+$items,}$i"
    done
    action="$(summary_action)"
    is_root && root=true
    printf '{"tool":"stretch_apply_settings","version":1,"mode":"%s","root":%s,"items":[%s],' "$MODE" "$root" "$items"
    printf '"summary":{"ok":%d,"missing":%d,"changed":%d,"failed":%d,"unmanaged":%d},' "$N_OK" "$N_MISSING" "$N_CHANGED" "$N_FAILED" "$N_UNMANAGED"
    if [ -n "$action" ]; then
        printf '"action":"%s"}\n' "$(json_escape "$action")"
    else
        printf '"action":null}\n'
    fi
}

emit_summary() {
    local total=$((N_OK + N_MISSING + N_CHANGED + N_FAILED + N_UNMANAGED))
    local parts=""
    [ $N_OK -gt 0 ] && parts="$N_OK ok"
    [ $N_CHANGED -gt 0 ] && parts="${parts:+$parts, }$N_CHANGED changed"
    [ $N_MISSING -gt 0 ] && parts="${parts:+$parts, }$N_MISSING missing"
    [ $N_FAILED -gt 0 ] && parts="${parts:+$parts, }$N_FAILED failed"
    [ $N_UNMANAGED -gt 0 ] && parts="${parts:+$parts, }$N_UNMANAGED unmanaged"
    echo
    if [ $total = 1 ]; then echo "1 item: $parts."; else echo "$total items: $parts."; fi
    case "$MODE" in
        check)
            if [ $N_MISSING -gt 0 ] && [ $N_FAILED -eq 0 ]; then
                echo "To apply the missing settings run: $(summary_action)"
            elif [ $N_FAILED -gt 0 ]; then
                echo "A check failed, see the detail above."
            else
                echo "Everything is in place, nothing to run."
            fi ;;
        dry-run)
            if [ $N_MISSING -gt 0 ]; then
                echo "Nothing was changed. Run: $(summary_action)"
            else
                echo "Nothing to do."
            fi ;;
        apply)
            if [ $N_FAILED -gt 0 ]; then
                echo "Some items did not apply. Log: $SAS_LOG"
            elif [ $N_CHANGED -gt 0 ]; then
                echo "Applied. Log: $SAS_LOG"
            else
                echo "Everything was already in place, nothing changed."
            fi ;;
    esac
}

exit_code=0

mode_list() {
    local f id desc
    for f in "${ITEM_FILES[@]}"; do
        id="$(item_id "$f")"
        # shellcheck disable=SC1090
        desc="$( ( . "$f" >/dev/null 2>&1; echo "${ITEM_DESC:-}" ) )"
        if [ $JSON = 1 ]; then
            JSON_ITEMS+=("{\"id\":\"$(json_escape "$id")\",\"file\":\"$(json_escape "$f")\",\"description\":\"$(json_escape "$desc")\"}")
        else
            printf '%-12s %s\n' "$id" "$desc"
        fi
    done
    if [ $JSON = 1 ]; then
        local items="" i
        for i in "${JSON_ITEMS[@]}"; do items="${items:+$items,}$i"; done
        printf '{"tool":"stretch_apply_settings","version":1,"mode":"list","items":[%s]}\n' "$items"
    fi
}

mode_check() {
    local f id
    for f in "${ITEM_FILES[@]}"; do
        id="$(item_id "$f")"
        check_item "$f"
        count_state "$ITEM_STATE"
        [ $JSON = 1 ] && add_json_item "$id" "$ITEM_STATE" "$ITEM_REASON" 0
        [ $JSON = 0 ] && print_row "$id" "$ITEM_STATE" "$ITEM_REASON"
        if [ "$ITEM_STATE" = failed ] && [ $JSON = 0 ]; then
            print_detail "$RUN_OUT"
        fi
    done
    [ $N_MISSING -gt 0 ] && exit_code=1
    [ $N_FAILED -gt 0 ] && exit_code=2
}

mode_dry_run() {
    local f id plan
    for f in "${ITEM_FILES[@]}"; do
        id="$(item_id "$f")"
        check_item "$f"
        count_state "$ITEM_STATE"
        plan=""
        if [ "$ITEM_STATE" = missing ]; then
            run_fn "$f" plan
            plan="$RUN_OUT"
        fi
        if [ $JSON = 1 ]; then
            add_json_item "$id" "$ITEM_STATE" "$ITEM_REASON" 0 "$plan"
        else
            print_row "$id" "$ITEM_STATE" "$ITEM_REASON"
            print_detail "$plan"
        fi
    done
    [ $N_MISSING -gt 0 ] && exit_code=1
    [ $N_FAILED -gt 0 ] && exit_code=2
}

mode_apply() {
    local f id before state detail
    for f in "${ITEM_FILES[@]}"; do
        id="$(item_id "$f")"
        check_item "$f"
        before=$ITEM_STATE
        detail=""
        case $before in
            missing)
                sas_log "$id" "apply: start ($ITEM_REASON)"
                run_fn "$f" apply
                detail="$RUN_OUT"
                while IFS= read -r line; do
                    [ -n "$line" ] && sas_log "$id" "apply: $line"
                done <<< "$detail"
                if [ $RUN_RC -ne 0 ]; then
                    state=failed
                    ITEM_REASON="apply exited $RUN_RC"
                    sas_log "$id" "apply: FAILED ($ITEM_REASON)"
                else
                    check_item "$f"
                    if [ "$ITEM_STATE" = ok ]; then
                        state=changed
                        sas_log "$id" "apply: done, check ok ($ITEM_REASON)"
                    else
                        state=failed
                        ITEM_REASON="still $ITEM_STATE after apply: $ITEM_REASON"
                        sas_log "$id" "apply: FAILED ($ITEM_REASON)"
                    fi
                fi ;;
            *)
                state=$before ;;
        esac
        count_state "$state"
        if [ $JSON = 1 ]; then
            add_json_item "$id" "$state" "$ITEM_REASON" "$([ "$state" = changed ] && echo 1 || echo 0)" "$detail"
        else
            print_row "$id" "$state" "$ITEM_REASON"
            if [ "$state" = failed ] || { [ $VERBOSE = 1 ] && [ -n "$detail" ]; }; then
                print_detail "$detail"
            fi
        fi
    done
    [ $N_FAILED -gt 0 ] && exit_code=1
    [ $N_MISSING -gt 0 ] && exit_code=1
}

mode_revert() {
    local f id has
    f=""
    for id in "${ITEM_FILES[@]}"; do
        [ "$(item_id "$id")" = "$REVERT_ID" ] && f=$id
    done
    [ -n "$f" ] || die "no item with id '$REVERT_ID' (see --list)"
    # shellcheck disable=SC1090
    has="$( ( . "$f" >/dev/null 2>&1; declare -F revert >/dev/null && echo yes ) )"
    if [ "$has" != yes ]; then
        print_row "$REVERT_ID" failed "this item has no revert"
        exit_code=2
        return
    fi
    sas_log "$REVERT_ID" "revert: start"
    run_fn "$f" revert
    while IFS= read -r line; do
        [ -n "$line" ] && sas_log "$REVERT_ID" "revert: $line"
    done <<< "$RUN_OUT"
    if [ $RUN_RC -ne 0 ]; then
        sas_log "$REVERT_ID" "revert: FAILED (exit $RUN_RC)"
        print_row "$REVERT_ID" failed "revert exited $RUN_RC"
        print_detail "$RUN_OUT"
        exit_code=1
        return
    fi
    check_item "$f"
    if [ "$ITEM_STATE" = missing ]; then
        sas_log "$REVERT_ID" "revert: done ($ITEM_REASON)"
        if [ $JSON = 1 ]; then
            add_json_item "$REVERT_ID" reverted "$ITEM_REASON" 1 "$RUN_OUT"
        else
            print_row "$REVERT_ID" reverted "$ITEM_REASON"
            [ $VERBOSE = 1 ] && print_detail "$RUN_OUT"
        fi
    else
        sas_log "$REVERT_ID" "revert: FAILED (still $ITEM_STATE: $ITEM_REASON)"
        print_row "$REVERT_ID" failed "still $ITEM_STATE after revert: $ITEM_REASON"
        exit_code=1
    fi
}

case "$MODE" in
    list) mode_list; exit 0 ;;
    check) mode_check ;;
    dry-run) mode_dry_run ;;
    apply) mode_apply ;;
    revert) mode_revert ;;
esac

if [ $JSON = 1 ]; then
    [ "$MODE" = revert ] && [ ${#JSON_ITEMS[@]} -eq 0 ] && add_json_item "$REVERT_ID" failed "revert did not complete" 0
    emit_json
elif [ "$MODE" != revert ]; then
    emit_summary
fi
exit $exit_code
