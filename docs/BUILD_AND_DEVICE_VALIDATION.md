# Build, package, and device validation

## Latest candidate

- Package: `com.iuyghi.lumenboard`
- Version: `0.1.0-8`
- Architecture: `iphoneos-arm64`
- Branch: `fix/rootless-deb-installation`
- CI: native XCTest + rootless package build/verification + maintainer-script regression tests

CI validation covers compilation, unit tests, Debian archive and metadata, rootless paths, Mach-O arm64 architecture/signatures, bundle Info.plist, launchd plist, and the maintainer scripts. It does not prove installation on Dopamine or PosterBoard rendering.

## Device validation still required

1. Confirm dpkg reaches configured state without maintainer-script errors.
2. Confirm `launchctl print user/foreground/com.iuyghi.lumenboardd` shows the expected service and inspect `/var/mobile/Library/Logs/LumenBoard-daemon.log`.
3. Import a known-good descriptor-format `.tendies` fixture from Settings > LumenBoard.
4. Confirm the daemon writes a successful completion and the UI reports descriptor publication, not verified application.
5. Confirm the item appears in native PosterBoard Collections, opens in preview, can be selected, and renders on Lock Screen/Home Screen.
6. Reboot/respring and verify persistence and daemon relaunch.
7. Test repeated dpkg configure/upgrade and package removal. Verify removal stops the daemon without deleting user wallpaper data or unrelated PosterBoard descriptors.

Capture dpkg output, launchctl print output, daemon log, the managed item manifest, and screenshots of Collections/preview/applied wallpaper. Redact device identifiers before sharing logs.

## Evidence boundary

- Previous CI run for version `0.1.0-5`: 39 native XCTest cases passed; rootless package artifact independently extracted and hashed.
- Version `0.1.0-8`: adds shell regression coverage for fresh bootstrap, repeated configure with launchctl status 37, rejection of misleading status 5, bootstrap failure, kickstart failure, and idempotent prerm behavior. Await the CI result for this exact commit before treating the candidate as validated.
- Device: user-reported installs of `0.1.0-3` and `0.1.0-4` failed in maintainer scripts. The `0.1.0-8` change addresses the observed already-bootstrapped case but still requires target-device testing.
- PosterBoard: gallery visibility and rendering remain unverified.

## Local build

On a supported Theos/macOS environment:

```sh
make clean package FINALPACKAGE=1
dpkg-deb --info packages/*.deb
dpkg-deb --contents packages/*.deb
```

Treat every artifact as a candidate until the device validation sequence passes.
