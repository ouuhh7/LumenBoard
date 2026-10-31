# LumenBoard 0.1.0-9 — CI-verified package

## Source and build

- Repository: `ouuhh7/LumenBoard`
- Branch: `fix/rootless-deb-installation`
- Commit: `7ac16e7ef6cc759e7d6c96b0069e3ca3df175f85`
- Workflow run: [41193825292](https://github.com/ouuhh7/LumenBoard/actions/runs/41193825292)
- Result: portable tests, native XCTest, and rootless package build all passed

## Automated evidence

- 68 portable Python tests passed.
- 39 native Objective-C XCTest cases passed.
- Shell tests passed for first install, repeat configure, strict handling of launchctl status 37, rejection of misleading status 5, launch failure, legacy system-domain migration, and safe teardown of both service domains.
- The Debian archive, package fields, rootless payload, arm64 Mach-O binaries, bundle metadata, launchd plist, permissions, and maintainer scripts were independently checked.

## Package

- File: `com.iuyghi.lumenboard_0.1.0-9_iphoneos-arm64.deb`
- Architecture: `iphoneos-arm64`
- SHA-256: `67947c2f2106ce8b8dfb3dd372abdf9649c09e06f182d49201fd91f31ce64c50`

## Changes from the failed 0.1.0-3 / 0.1.0-4 install attempts

1. No calls to missing `/rootfs/usr/bin/grep` or `/rootfs/bin/sleep` remain in the package maintainer scripts.
2. The daemon uses Dopamine's `user/foreground` domain.
3. Repeated configuration recognizes the observed status-37 already-bootstrapped response only when the corresponding diagnostic is present.
4. The old `system`-domain registration is explicitly booted out before foreground registration.
5. `prerm` stops both service domains and fails safely if either service remains registered.
6. Ownership code no longer assumes the foreground daemon has root privileges to `chown` files it already owns.

## Not yet proven

The package has not been installed by the assistant on the user's iPhone. Device-side dpkg configuration, daemon survival, actual `.tendies` import, PosterBoard gallery visibility, selection, wallpaper rendering, and reboot persistence remain unverified. A CI pass cannot establish those behaviors.
