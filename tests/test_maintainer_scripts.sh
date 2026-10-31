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
    case "$2" in
      system/*) [ "${FAKE_LEGACY:-absent}" = running ] && [ ! -f "${FAKE_SYSTEM_GONE:-/nonexistent-lb-system}" ] && exit 0 ;;
      user/foreground/*) [ "${FAKE_USER:-running}" = running ] && [ ! -f "${FAKE_USER_GONE:-/nonexistent-lb-user}" ] && exit 0 ;;
    esac
    exit 113 ;;
  bootout)
    case "$2" in
      system/*) mode="${FAKE_BOOTOUT_SYSTEM:-${FAKE_BOOTOUT:-ok}}"; marker="${FAKE_SYSTEM_GONE:-/nonexistent-lb-system}" ;;
      *) mode="${FAKE_BOOTOUT_USER:-${FAKE_BOOTOUT:-ok}}"; marker="${FAKE_USER_GONE:-/nonexistent-lb-user}" ;;
    esac
    case "$mode" in
      fail) exit 1 ;;
      gone) : > "$marker"; exit 1 ;;
      *) : > "$marker"; exit 0 ;;
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
run_postinst env FAKE_LEGACY=running
grep -q '^bootout system/com.iuyghi.lumenboardd$' "$TMP/calls"
if run_postinst env FAKE_LEGACY=running FAKE_BOOTOUT_SYSTEM=fail; then echo "FAIL: legacy service left active" >&2; exit 1; fi

FAKE_LAUNCHCTL_LOG="$TMP/calls" LUMENBOARD_LAUNCHCTL="$TMP/launchctl" FAKE_USER=absent FAKE_LEGACY=absent FAKE_SYSTEM_GONE="$TMP/systemgone" FAKE_USER_GONE="$TMP/usergone" "$CONTROL/prerm"
FAKE_LAUNCHCTL_LOG="$TMP/calls" LUMENBOARD_LAUNCHCTL="$TMP/launchctl" FAKE_USER=running FAKE_LEGACY=running FAKE_SYSTEM_GONE="$TMP/systemgone" FAKE_USER_GONE="$TMP/usergone" "$CONTROL/prerm"
rm -f "$TMP/usergone" "$TMP/systemgone"
if FAKE_LAUNCHCTL_LOG="$TMP/calls" LUMENBOARD_LAUNCHCTL="$TMP/launchctl" FAKE_USER=running FAKE_LEGACY=absent FAKE_SYSTEM_GONE="$TMP/systemgone" FAKE_USER_GONE="$TMP/usergone" FAKE_BOOTOUT_USER=fail "$CONTROL/prerm"; then echo "FAIL: prerm accepted a running foreground daemon" >&2; exit 1; fi
if FAKE_LAUNCHCTL_LOG="$TMP/calls" LUMENBOARD_LAUNCHCTL="$TMP/launchctl" FAKE_USER=absent FAKE_LEGACY=running FAKE_SYSTEM_GONE="$TMP/systemgone" FAKE_USER_GONE="$TMP/usergone" FAKE_BOOTOUT_SYSTEM=fail "$CONTROL/prerm"; then echo "FAIL: prerm accepted a running legacy daemon" >&2; exit 1; fi
echo "PASS: maintainer scripts cover fresh/repeated install, strict status-37 handling, legacy system-domain migration, launch failure, and safe removal of both service domains."
