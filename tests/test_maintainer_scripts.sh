#!/bin/sh
set -eu

ROOT=$(CDPATH= cd -- "$(dirname "$0")/.." && pwd)
CONTROL="$ROOT/layout/DEBIAN"
TMP="${TMPDIR:-/tmp}/lumenboard-maintainer-tests-$$"
mkdir -p "$TMP"
trap 'rm -rf "$TMP"' EXIT HUP INT TERM

cat > "$TMP/launchctl" <<'FAKE'
#!/bin/sh
printf '%s\n' "$*" >> "$FAKE_LAUNCHCTL_LOG"
case "$1" in
  bootstrap)
    case "${FAKE_BOOTSTRAP:-ok}" in
      already) echo "Bootstrap failed: 37: service already bootstrapped" >&2; exit 37 ;;
      wrong-status) echo "service already bootstrapped" >&2; exit 5 ;;
      fail) echo "Bootstrap failed: permission denied" >&2; exit 5 ;;
      *) exit 0 ;;
    esac ;;
  kickstart) [ "${FAKE_KICKSTART:-ok}" = fail ] && exit 1; exit 0 ;;
  print) [ "${FAKE_PRINT:-running}" = running ] && { echo "state = running"; exit 0; }; exit 113 ;;
  bootout) [ "${FAKE_BOOTOUT:-ok}" = fail ] && exit 1; exit 0 ;;
esac
exit 64
FAKE
chmod 0755 "$TMP/launchctl"

run_postinst() {
  : > "$TMP/calls"
  FAKE_LAUNCHCTL_LOG="$TMP/calls" LUMENBOARD_LAUNCHCTL="$TMP/launchctl" "$@" "$CONTROL/postinst"
}

run_postinst env
run_postinst env FAKE_BOOTSTRAP=already
if run_postinst env FAKE_BOOTSTRAP=wrong-status; then echo "FAIL: status 5 accepted" >&2; exit 1; fi
if run_postinst env FAKE_BOOTSTRAP=fail; then echo "FAIL: bootstrap failure accepted" >&2; exit 1; fi
if run_postinst env FAKE_KICKSTART=fail; then echo "FAIL: kickstart failure accepted" >&2; exit 1; fi
FAKE_LAUNCHCTL_LOG="$TMP/calls" LUMENBOARD_LAUNCHCTL="$TMP/launchctl" FAKE_PRINT=absent "$CONTROL/prerm"
FAKE_LAUNCHCTL_LOG="$TMP/calls" LUMENBOARD_LAUNCHCTL="$TMP/launchctl" FAKE_PRINT=running FAKE_BOOTOUT=fail "$CONTROL/prerm"
echo "PASS: maintainer scripts cover fresh install, repeated configure, strict status-37 handling, launch failure, and idempotent removal."
