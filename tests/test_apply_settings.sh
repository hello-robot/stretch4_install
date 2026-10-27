#!/bin/bash
# Harness for stretch_apply_settings. Runs every item's check, plan, apply and revert
# inside a throwaway root (STRETCH_SYSROOT) with PATH shims standing in for apt-get,
# dpkg-query, systemctl and dconf. The shims record their calls so the harness can
# assert what was run. Needs bash, python3 and the usual coreutils; no root.
#
#   tests/test_apply_settings.sh           run and report
#   KEEP=1 tests/test_apply_settings.sh    leave the fake root behind for a look
set -u -o pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO="$(cd "$HERE/.." && pwd)"
SAS="$REPO/stretch_apply_settings.sh"

ROOT="$(mktemp -d "${TMPDIR:-/tmp}/sas-test.XXXXXX")"
SHIMS="$ROOT/.shims"
STATE="$ROOT/.state"
CALLS="$STATE/calls.log"
mkdir -p "$SHIMS" "$STATE" "$ROOT/etc"
printf 'ID=ubuntu\nVERSION_ID="24.04"\n' > "$ROOT/etc/os-release"

cleanup() {
    if [ "${KEEP:-0}" = 1 ]; then
        echo "fake root kept at $ROOT"
    else
        rm -rf "$ROOT"
    fi
}
trap cleanup EXIT

# shims
write_shim() {
    # write_shim <name> <body>
    printf '#!/bin/bash\necho "%s $*" >> "%s"\n%s\n' "$1" "$CALLS" "$2" > "$SHIMS/$1"
    chmod +x "$SHIMS/$1"
}

write_shim apt-get "case \"\$*\" in *install*acpid*) touch '$STATE/pkg.acpid' ;; esac; exit 0"

write_shim dpkg-query "pkg=\${!#}
if [ -e '$STATE/pkg.'\"\$pkg\" ]; then echo 'install ok installed'; exit 0; fi
exit 1"

write_shim systemctl "while [ \$# -gt 0 ] && [ \"\${1#-}\" != \"\$1\" ]; do case \"\$1\" in -M|--machine) shift ;; esac; shift; done
verb=\$1; shift
unit=\${!#}; unit=\${unit%.service}
case \"\$verb\" in
  enable)  touch '$STATE/enabled.'\"\$unit\"; case \"\$*\" in *--now*) touch '$STATE/active.'\"\$unit\" ;; esac ;;
  disable) rm -f '$STATE/enabled.'\"\$unit\" ;;
  start|restart) touch '$STATE/active.'\"\$unit\" ;;
  stop)    rm -f '$STATE/active.'\"\$unit\" ;;
  is-enabled) if [ -e '$STATE/enabled.'\"\$unit\" ]; then echo enabled; else echo disabled; exit 1; fi ;;
  is-active)  if [ -e '$STATE/active.'\"\$unit\" ]; then [ \"\$1\" = --quiet ] || echo active; else [ \"\$1\" = --quiet ] || echo inactive; exit 3; fi ;;
  daemon-reload) ;;
esac
exit 0"

write_shim dconf "case \"\$1\" in update) mkdir -p '$ROOT/etc/dconf/db'; touch '$ROOT/etc/dconf/db/local' ;; esac; exit 0"

export PATH="$SHIMS:$PATH"
export STRETCH_SYSROOT="$ROOT"
unset STRETCH_SETTINGS_DIR STRETCH_APPLY_SETTINGS_LOG

# assertions
PASS=0
FAIL=0
OUT=
RC=0

run() {
    # run <args...>: run the command, keep stdout+stderr in OUT and the status in RC
    if OUT="$("$@" 2>&1)"; then RC=0; else RC=$?; fi
}

ok() {
    PASS=$((PASS + 1))
    echo "pass  $1"
}

bad() {
    FAIL=$((FAIL + 1))
    echo "FAIL  $1"
    [ -n "${2:-}" ] && printf '%s\n' "$2" | sed 's/^/      /'
}

assert_rc() {
    # assert_rc <expected> <label>
    if [ "$RC" = "$1" ]; then ok "$2 (rc $1)"; else bad "$2: rc $RC, wanted $1" "$OUT"; fi
}

assert_out() {
    # assert_out <grep -E pattern> <label>
    if printf '%s\n' "$OUT" | grep -qE -- "$1"; then ok "$2"; else bad "$2: output lacks /$1/" "$OUT"; fi
}

assert_not_out() {
    if printf '%s\n' "$OUT" | grep -qE -- "$1"; then bad "$2: output has /$1/" "$OUT"; else ok "$2"; fi
}

assert_file() {
    if [ -e "$1" ]; then ok "$2"; else bad "$2: $1 does not exist"; fi
}

assert_no_file() {
    if [ -e "$1" ]; then bad "$2: $1 exists"; else ok "$2"; fi
}

assert_call() {
    if grep -qE -- "$1" "$CALLS" 2>/dev/null; then ok "$2"; else bad "$2: no shim call /$1/" "$(cat "$CALLS" 2>/dev/null)"; fi
}

assert_json() {
    # assert_json <python expression over doc d> <label>
    local verdict
    verdict="$(printf '%s' "$OUT" | python3 -c "
import json, sys
d = json.load(sys.stdin)
print('yes' if ($1) else 'no')
" 2>&1)"
    if [ "$verdict" = yes ]; then ok "$2"; else bad "$2: $1 -> $verdict" "$OUT"; fi
}

json_states() {
    # a compact id=state list for messages
    printf '%s' "$OUT" | python3 -c "import json,sys; d=json.load(sys.stdin); print(' '.join(i['id']+'='+i['state'] for i in d['items']))"
}

assert_true() {
    # assert_true <label> <command...>: pass when the command succeeds
    local label=$1; shift
    if "$@" >/dev/null 2>&1; then ok "$label"; else bad "$label: $* failed"; fi
}

assert_false() {
    local label=$1; shift
    if "$@" >/dev/null 2>&1; then bad "$label: $* succeeded"; else ok "$label"; fi
}

HANDLER="$ROOT/usr/local/sbin/hello-powerkey"
EVENT="$ROOT/etc/acpi/events/hello-powerbtn"
KEYFILE="$ROOT/etc/dconf/db/local.d/10-hello-powerkey"
LOCK="$ROOT/etc/dconf/db/local.d/locks/hello-powerkey"
PROFILE="$ROOT/etc/dconf/profile/user"
LINK="$ROOT/usr/local/bin/stretch_apply_settings"
LOG="$ROOT/var/log/stretch_apply_settings.log"
CHIME_WAV="$ROOT/usr/local/share/hello-robot/sounds/ready.wav"
CHIME_BIN="$ROOT/usr/local/bin/hello-ready-chime"
CHIME_UNIT="$ROOT/etc/systemd/user/hello-ready-chime.service"
CHIME_WANT="$ROOT/etc/systemd/user/default.target.wants/hello-ready-chime.service"
CHIME_SRC="$REPO/factory/24.04/sounds"

echo "fake root: $ROOT"
echo

# list
run "$SAS" --list
assert_rc 0 "list"
assert_out '^command ' "list names command"
assert_out '^powerkey ' "list names powerkey"
assert_out '^lidar-ptp ' "list names lidar-ptp"
assert_out '^ready-chime ' "list names ready-chime"
run "$SAS" --list --json
assert_json "len(d['items']) == 4 and d['mode'] == 'list'" "list json has 4 items"

# fresh system
run "$SAS"
assert_rc 1 "fresh check"
assert_out '^command +missing' "fresh: command missing"
assert_out '^powerkey +missing +acpid package not installed' "fresh: powerkey missing (acpid first)"
assert_out '^lidar-ptp +unmanaged +not managed yet; units absent' "fresh: lidar-ptp unmanaged"
assert_out '^ready-chime +missing +sound .*ready.wav missing' "fresh: ready-chime missing (sound first)"
assert_out 'sudo stretch_apply_settings --apply' "fresh: tells the apply command"

run "$SAS" --check --json
assert_rc 1 "fresh json check"
assert_json "d['tool'] == 'stretch_apply_settings' and d['version'] == 1" "json tool and version"
assert_json "[i['state'] for i in d['items']] == ['missing', 'missing', 'unmanaged', 'missing']" "json states $(json_states)"
assert_json "d['summary'] == {'ok': 0, 'missing': 3, 'changed': 0, 'failed': 0, 'unmanaged': 1}" "json summary counts"
assert_json "d['action'] == 'sudo stretch_apply_settings --apply' and d['root'] is True" "json action and root flag"
assert_json "all(i['changed'] is False for i in d['items'])" "json nothing changed on check"

# dry run
run "$SAS" --dry-run
assert_rc 1 "dry-run"
assert_out 'apt-get install -y acpid' "dry-run lists the apt step"
assert_out 'ln -sfn .*stretch_apply_settings' "dry-run lists the link step"
assert_out 'install .*ready.wav -> .*sounds/ready.wav' "dry-run lists the chime sound step"
assert_out 'ln -sfn /etc/systemd/user/hello-ready-chime.service' "dry-run lists the chime enable step"
assert_out 'Nothing was changed' "dry-run says nothing changed"
assert_no_file "$HANDLER" "dry-run wrote no handler"
assert_no_file "$LINK" "dry-run made no link"
assert_no_file "$CHIME_WAV" "dry-run installed no sound"
if [ ! -e "$CALLS" ] || ! grep -qvE '^(dpkg-query|systemctl is-)' "$CALLS"; then ok "dry-run ran no write command"; else bad "dry-run ran a write command" "$(cat "$CALLS")"; fi
assert_no_file "$LOG" "dry-run wrote no log"

run "$SAS" --dry-run --json
assert_json "d['items'][1]['detail'].count('\\n') >= 5" "dry-run json carries the plan"

# apply
run "$SAS" --apply
assert_rc 0 "apply"
assert_out '^command +changed' "apply: command changed"
assert_out '^powerkey +changed +acpid handles the power button' "apply: powerkey changed, reason from check"
assert_out '^lidar-ptp +unmanaged' "apply: lidar-ptp left unmanaged"
assert_out '^ready-chime +changed +chime installed, hello-ready-chime.service enabled' "apply: ready-chime changed, reason from check"
assert_out 'Applied\. Log: ' "apply: summary names the log"
assert_file "$HANDLER" "handler written"
assert_file "$EVENT" "acpid event written"
assert_file "$KEYFILE" "dconf keyfile written"
assert_file "$LOCK" "dconf lock written"
assert_file "$PROFILE" "dconf profile written"
assert_file "$LINK" "command link made"
assert_true "handler executable" test -x "$HANDLER"
assert_true "link points at the script" test "$(readlink -f "$LINK")" = "$(readlink -f "$SAS")"
assert_true "handler powers off" grep -q "^exec systemctl poweroff" "$HANDLER"
assert_true "event is button/power" grep -q "^event=button/power" "$EVENT"
assert_true "keyfile sets nothing" grep -q "^power-button-action='nothing'" "$KEYFILE"
assert_true "profile has system-db:local" grep -q "^system-db:local" "$PROFILE"
assert_call '^apt-get install -y acpid' "apt-get install acpid called"
assert_call '^dconf update' "dconf update called"
assert_call '^systemctl enable --now acpid' "acpid enabled"
assert_call '^systemctl restart acpid' "acpid restarted"
assert_file "$LOG" "log written"
assert_true "log records powerkey done" grep -q " powerkey apply: done" "$LOG"
assert_true "log records command done" grep -q " command apply: done" "$LOG"
assert_file "$CHIME_WAV" "chime sound installed"
assert_file "$CHIME_BIN" "chime player installed"
assert_file "$CHIME_UNIT" "chime unit written"
assert_true "chime sound identical to the repo file" cmp -s "$CHIME_SRC/ready.wav" "$CHIME_WAV"
assert_true "chime player identical to the repo file" cmp -s "$CHIME_SRC/hello-ready-chime" "$CHIME_BIN"
assert_true "chime player executable" test -x "$CHIME_BIN"
assert_true "chime unit starts after the body server" grep -q "^After=stretch_body_server.service" "$CHIME_UNIT"
assert_true "chime unit runs the player" grep -q "^ExecStart=/usr/local/bin/hello-ready-chime$" "$CHIME_UNIT"
assert_true "chime unit wanted by default.target" grep -q "^WantedBy=default.target" "$CHIME_UNIT"
assert_true "chime enabled by a wants link" test -L "$CHIME_WANT"
assert_true "chime wants link points at the unit" test "$(readlink "$CHIME_WANT")" = /etc/systemd/user/hello-ready-chime.service
assert_call '^systemctl --user -M [a-z_-]+@ daemon-reload' "user manager reloaded for the chime unit"
assert_true "log records ready-chime done" grep -q " ready-chime apply: done" "$LOG"

# settled system
run "$SAS"
assert_rc 0 "check after apply"
assert_out '^command +ok' "settled: command ok"
assert_out '^powerkey +ok' "settled: powerkey ok"
assert_out '^ready-chime +ok' "settled: ready-chime ok"
assert_out 'Everything is in place' "settled: nothing to run"
run "$SAS" --json
assert_json "d['summary']['missing'] == 0 and d['summary']['ok'] == 3 and d['action'] is None" "settled json"

calls_before="$(wc -l < "$CALLS")"
run "$SAS" --apply --json
assert_rc 0 "second apply"
assert_json "all(i['changed'] is False for i in d['items']) and d['summary']['changed'] == 0" "second apply changes nothing"
calls_after="$(wc -l < "$CALLS")"
# the second apply may only call read-only shims (dpkg-query, systemctl is-*)
if ! sed -n "$((calls_before + 1)),\$p" "$CALLS" | grep -qvE '^(dpkg-query|systemctl is-)'; then
    ok "second apply ran no write command"
else
    bad "second apply ran a write command" "$(sed -n "$((calls_before + 1)),\$p" "$CALLS")"
fi
[ "$calls_after" -ge "$calls_before" ] || bad "call log shrank"

# drift and repair
echo "# tampered" >> "$HANDLER"
run "$SAS" --only powerkey
assert_rc 1 "drifted handler is missing"
assert_out 'handler .* missing or different' "drift reason names the handler"
run "$SAS" --apply --only powerkey
assert_rc 0 "repair apply"
assert_out '^powerkey +changed' "repair changed powerkey"
assert_false "handler rewritten" grep -q tampered "$HANDLER"
run "$SAS" --only command
assert_rc 0 "--only command still ok"
printf '\n# drifted\n' >> "$CHIME_UNIT"
run "$SAS" --only ready-chime
assert_rc 1 "drifted chime unit is missing"
assert_out 'unit .* missing or different' "chime drift reason names the unit"
rm -f "$CHIME_WANT"
run "$SAS" --apply --only ready-chime
assert_rc 0 "chime repair apply"
assert_out '^ready-chime +changed' "repair changed ready-chime"
assert_true "chime unit rewritten" cmp -s <(grep -c drifted "$CHIME_UNIT") <(echo 0)
assert_true "chime wants link back" test -L "$CHIME_WANT"

# PTP stub reporting
mkdir -p "$ROOT/etc/systemd/system"
touch "$ROOT/etc/systemd/system/lidar-ptp4l.service"
run "$SAS" --only lidar-ptp
assert_rc 0 "unmanaged never fails the check"
assert_out 'only lidar-ptp4l present' "ptp stub reports a partial install"
touch "$ROOT/etc/systemd/system/lidar-phc2sys.service"
run "$SAS" --only lidar-ptp
assert_out 'both units present, not both running' "ptp stub reports units not running"
touch "$STATE/active.lidar-ptp4l" "$STATE/active.lidar-phc2sys"
run "$SAS" --only lidar-ptp
assert_out 'both units present and running' "ptp stub reports running"
run "$SAS" --apply --only lidar-ptp
assert_rc 0 "apply on the stub is a no-op"
assert_out '^lidar-ptp +unmanaged' "stub stays unmanaged after apply"

# revert
run "$SAS" --revert powerkey
assert_rc 0 "revert powerkey"
assert_out '^powerkey +reverted' "revert reports reverted"
assert_no_file "$HANDLER" "revert removed the handler"
assert_no_file "$EVENT" "revert removed the event"
assert_no_file "$KEYFILE" "revert removed the keyfile"
assert_no_file "$LOCK" "revert removed the lock"
assert_file "$PROFILE" "revert left the dconf profile"
run "$SAS" --only powerkey
assert_rc 1 "powerkey missing after revert"
assert_true "log records the revert" grep -q " powerkey revert: done" "$LOG"

run "$SAS" --revert command
assert_rc 0 "revert command"
assert_no_file "$LINK" "revert removed the link"

run "$SAS" --revert ready-chime --json
assert_rc 0 "revert ready-chime"
assert_json "d['items'][0]['id'] == 'ready-chime' and d['items'][0]['state'] == 'reverted'" "revert ready-chime json"
assert_no_file "$CHIME_WAV" "revert removed the chime sound"
assert_no_file "$CHIME_BIN" "revert removed the chime player"
assert_no_file "$CHIME_UNIT" "revert removed the chime unit"
assert_no_file "$CHIME_WANT" "revert removed the chime wants link"
run "$SAS" --only ready-chime
assert_rc 1 "ready-chime missing after revert"
assert_true "log records the chime revert" grep -q " ready-chime revert: done" "$LOG"

run "$SAS" --revert lidar-ptp
assert_rc 2 "revert on an item without revert"
assert_out 'has no revert' "revert refusal wording"

# wrapper and errors
run "$REPO/factory/24.04/hello_powerkey_install.sh"
assert_rc 0 "hello_powerkey_install.sh wrapper applies the item"
assert_out '^powerkey +changed' "wrapper changed powerkey"

run "$SAS" --only nope
assert_rc 2 "unknown --only id"
run "$SAS" --bogus
assert_rc 2 "unknown argument"
run "$SAS" --revert
assert_rc 2 "--revert without id"

if [ "$(id -u)" != 0 ]; then
    STRETCH_SYSROOT='' run "$SAS" --apply
    assert_rc 2 "apply without root is refused on the real root"
    assert_out 'needs root' "refusal names root"
fi

# result
echo
echo "$PASS passed, $FAIL failed"
[ $FAIL -eq 0 ]
