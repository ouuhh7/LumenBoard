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
  print)
    if [ -f "${FAKE_LAUNCHCTL_GONE:-/nonexistent-lb-marker}" ] || [ "${FAKE_PRINT:-running}" != running ]; then exit 113; fi
    echo "state = running"; exit 0 ;;
  bootout)
    case "${FAKE_BOOTOUT:-ok}" in
      fail) exit 1 ;;
      gone) : > "$FAKE_LAUNCHCTL_GONE"; exit 1 ;;
      *) : > "$FAKE_LAUNCHCTL_GONE"; exit 0 ;;
    esac ;;
esac
exit 64
FAKE
chmod 0755 "$TMP/launchctl"

run_postinst() {
  : > "$TMP/calls"
  rm -f "$TMP/systemgone" "$TMP/usergone"
  FAKE_LAUNCHCTL_LOG="$TMP/calls" LUMENBOARD_LAUNCHCTL="$TMP/launchctl" FAKE_SYSTEM_GONE="$TMP/systemgone" FAKE_USER_GONE="$TMP/usergone" "$@" "$CONTROL/postinst"
}

run_postinst env
run_postinst env FAKE_BOOTSTRAP=already
if run_postinst env FAKE_BOOTSTRAP=wrong-status; then echo "FAIL: status 5 accepted" >&2; exit 1; fi
if run_postinst env FAKE_BOOTSTRAP=fail; then echo "FAIL: bootstrap failure accepted" >&2; exit 1; fi
if run_postinst env FAKE_KICKSTART=fail; then echo "FAIL: kickstart failure accepted" >&2; exit 1; fi
FAKE_LAUNCHCTL_LOG="$TMP/calls" LUMENBOARD_LAUNCHCTL="$TMP/launchctl" FAKE_LAUNCHCTL_GONE="$TMP/gone" FAKE_PRINT=absent "$CONTROL/prerm"
FAKE_LAUNCHCTL_LOG="$TMP/calls" LUMENBOARD_LAUNCHCTL="$TMP/launchctl" FAKE_LAUNCHCTL_GONE="$TMP/gone" FAKE_PRINT=running FAKE_BOOTOUT=gone "$CONTROL/prerm"
rm -f "$TMP/gone"
if FAKE_LAUNCHCTL_LOG="$TMP/calls" LUMENBOARD_LAUNCHCTL="$TMP/launchctl" FAKE_LAUNCHCTL_GONE="$TMP/gone" FAKE_PRINT=running FAKE_BOOTOUT=fail "$CONTROL/prerm"; then
  echo "FAIL: prerm accepted a daemon that remained registered" >&2
  exit 1
fi
echo "PASS: maintainer scripts cover fresh install, repeated configure, strict status-37 handling, launch failure, safe removal, and refusal to remove files while the daemon remains registered."
