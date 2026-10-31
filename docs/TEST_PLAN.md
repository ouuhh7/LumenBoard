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
6. Confirm the descriptor appears in native PosterBoard Collections, opens in preview, is selectable, and actually renders on Lock Screen and Home Screen.
7. Reboot/respring and verify both wallpaper persistence and daemon relaunch.
8. Run dpkg configure/upgrade again to exercise the already-bootstrapped path; it must not fail or create duplicate service instances.
9. Remove the package and confirm the daemon is stopped. Confirm no user library files or unrelated PosterBoard descriptors were deleted.

Capture dpkg output, launchctl print output, daemon log, the relevant manifest and screenshots. Redact device identifiers before sharing.

## Explicitly out of scope until separately implemented

- Complete photo/video-to-CAML conversion and native gallery publishing.
- Safe removal of LumenBoard-owned descriptors from PosterBoard.
- Claims that descriptor publication means gallery visibility or actual wallpaper application.
- iOS 17+ or whole-container `.tendies` import.

A successful compile or DEB creation is a packaging check only. It is not evidence that PosterBoard accepts or renders an installed descriptor.
