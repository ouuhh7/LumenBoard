# Verification plan — current packaged daemon

## Automated checks

- `python3 -m unittest discover -s tests -v` for the portable archive and descriptor utilities.
- XcodeGen + `xcodebuild test` for the Objective-C native suite.
- `sh -n` for `layout/DEBIAN/postinst` and `layout/DEBIAN/prerm`.
- `sh tests/test_maintainer_scripts.sh` to exercise fresh bootstrap, repeat configure with launchctl status 37, misleading status 5 rejection, bootstrap failure, kickstart failure, and idempotent prerm.
- `plutil -lint` for the launchd plist and built Preferences Info.plist.
- Build and inspect the Debian archive: package fields, rootless paths, file modes/owners, arm64 Mach-O binaries, signatures, and exact maintainer scripts.

Automated checks use macOS and synthetic fixtures. They do not reproduce iOS launchd, Dopamine permissions, actual PosterBoard container state, or wallpaper rendering.

## Target-device acceptance tests

On the iPhone X running iOS 16.7.16 with the exact Dopamine/RootHide build:

1. Confirm the installed package version and SHA-256 before installation; capture complete dpkg output.
2. Confirm `dpkg` finishes configuration with no maintainer-script error.
3. Confirm `launchctl print user/foreground/com.iuyghi.lumenboardd` shows the daemon. Inspect `/var/mobile/Library/Logs/LumenBoard-daemon.log` if it does not.
4. Open Settings > LumenBoard and import a small, known-good descriptor-format `.tendies` fixture.
5. Confirm the managed manifest progresses from validation to registration and the daemon completion record reports descriptor publication.
6. Re-import the exact same `.tendies` archive. LumenBoard must not publish duplicates; it must run the read-only live-store verifier against the previously recorded UUIDs and report complete, partial, missing, or structurally invalid records.
7. A `complete` filesystem result proves only that the expected descriptor directories and required plist/CAML structure are present in the Collections store. It does not prove PosterBoard gallery visibility, selectability, preview loading, or wallpaper application; verify those manually on the device.
6. Confirm the descriptor appears in native PosterBoard Collections, opens in preview, is selectable, and actually renders on Lock Screen and Home Screen.
7. Reboot/respring and verify both wallpaper persistence and daemon relaunch.
8. Run dpkg configure/upgrade again to exercise the already-bootstrapped path; it must not fail or create duplicate service instances.
9. Remove the package and confirm both `user/foreground` and legacy `system` service registrations are stopped. Confirm no user library files or unrelated PosterBoard descriptors were deleted.

Capture dpkg output, launchctl print output, daemon log, the relevant manifest and screenshots. Redact device identifiers before sharing.

## Device-only acceptance gates

- Native gallery appearance, preview, selection and wallpaper application for generated photo/video descriptors.
- Safe removal of LumenBoard-owned descriptors from PosterBoard.
- Claims that descriptor publication means gallery visibility or actual wallpaper application.
- iOS 17+ or whole-container `.tendies` import.

A successful compile or DEB creation is a packaging check only. It is not evidence that PosterBoard accepts or renders an installed descriptor.


## PosterBoard refresh diagnostics (0.1.0-12)

- Confirm refresh preference ownership is checked with `lstat`; skip `chown` when the file is already owned by `mobile:mobile`.
- Permit ownership repair only when the daemon effective UID is root; otherwise report `EPERM` with the actual owner and effective UID.
- Do not launch the PosterBoard restart command if refresh preferences were not written and ownership-verified.
- Persist structured diagnostics for preference write/ownership, `posix_spawn`, `waitpid`, command exit status, and termination signal. A successful descriptor publication must remain distinct from a successful PosterBoard process refresh.
- On-device, inspect the returned diagnostic fields before deciding whether a restart is needed. Do not claim gallery visibility or wallpaper application from a successful process signal.


## Current 0.1.0-16 refresh regression coverage

The native XCTest suite now exercises the shared refresh process runner with temporary executable fixtures: ordered fallback selection, all candidates missing (ENOENT), spawn failure from a missing script interpreter, non-zero child exit, signal termination, a timeout that sends SIGKILL and reaps the child, a simulated ECHILD wait failure after child reaping, and the case where refresh flags are written but no executable exists. The portable contract test additionally guards the 15-second production timeout, both refresh call sites, waitpid(WNOHANG), EINTR, exit/signal distinctions, and the version contract across Debian control, Preferences CFBundleVersion, the build helper and CI workflow.

These tests validate process-management behavior on macOS, not the presence of any particular killall binary or the effect of killing PosterBoard on iOS 16.7.16. The exact process restart behavior remains a device-only check.


## Media descriptor index contract

`Daemon/LBPosterMediaBuilder.m` writes `index.xml` as a binary property list, includes the public iOS 16 PosterForge index fields including `unitsInPixelsInPlayer`, and sizes the empty Floating layer to 1×1. Portable contract tests guard the writer contract. The installer parses CAML documents, rejects unsafe or missing asset references, validates plist root types, and updates the default layer identifier. Native XCTest cases cover these paths and ordered descriptor IDs. These structural checks are not a substitute for loading generated wallpapers in PosterBoard on iOS 16.7.16.
