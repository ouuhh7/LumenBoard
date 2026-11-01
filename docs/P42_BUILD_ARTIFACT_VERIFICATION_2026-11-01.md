# P42 — Build, artifact and PosterBoard source verification

Date: 2026-11-01  
Repository: `ouuhh7/LumenBoard`  
Branch: `fix/rootless-deb-installation`  
Verified source commit: `646a570e3d8592b26489b9b7c440383f150e9cd7`  
Workflow run: [41305123557](https://github.com/ouuhh7/LumenBoard/actions/runs/41305123557)

## 1. Source and branch identity

The GitHub branch endpoint was read directly. Its head was exactly `646a570e3d8592b26489b9b7c440383f150e9cd7`. The commit message is `ci: accept compressed control archive variants`; its parent is `16d48ec401cf27a9328388c24d017cee27e9bf68`.

The current execution container did not contain a local LumenBoard checkout, and direct git network access was unavailable. Therefore local branch/HEAD and local uncommitted state could not be inspected or synchronized. No existing local work was overwritten, and no local repository mutation was attempted. Repository files were read through GitHub at the exact commit above.

## 2. CI result at the verified commit

All three jobs for workflow run 41305123557 completed successfully:

| Job | Result | Observed result |
|---|---|---|
| portable-tests | success | 87 Python unittest cases passed; `compileall`, shell syntax and CLI smoke checks completed |
| native-tests | success | 55 XCTest cases passed, 0 failures |
| rootless-package | success | Theos rootless build and Debian package verification completed |

The CI log reports 87 portable tests, not 90. The native XCTest log reports 55 tests and 0 failures.

## 3. Downloaded artifacts and checksums

Artifacts were downloaded from workflow run 41305123557 and inspected from their actual ZIP contents.

| Artifact | GitHub artifact ID | ZIP size | ZIP SHA-256 |
|---|---:|---:|---|
| lumenboard-rootless-package | 13082828196 | 61,728 bytes | `99251f94ed9f334e2a411fcdfc2dd535f1a98e550bf0515ef57772c486b74ab6` |
| native-xctest-log | 13082748290 | 9,690 bytes | `f66e4f6cb6359d30d3774c9117289517024fef8dd4181fac27ee8fb40b032f0c` |

The package artifact contains the Debian package at:
`packages/com.iuyghi.lumenboard_0.1.0-16_iphoneos-arm64.deb`

The SHA-256 computed from that exact extracted .deb is:

`baf9ca5214b2820e9cdebd37bab006afbbff8420458c7d0d3dd92c2125f46fe9`

The artifact's own `SHA256SUMS` and `package-verification.txt` report the same digest. This supersedes any earlier note assigning `45dfb3e415a66280f5cd9b102df84957822081339075231658fd2ba1e89aa383` to this CI artifact; that earlier value does not match the package bytes downloaded from artifact 13082828196.

## 4. Independently inspected Debian package

The downloaded .deb was opened as an ar archive and its control/data members were inspected.

Archive members:
- `debian-binary`
- `control.tar.xz`
- `data.tar.xz`

Control metadata:
- Package: `com.iuyghi.lumenboard`
- Version: `0.1.0-16`
- Architecture: `iphoneos-arm64`
- Depends: `firmware (>= 16.0), firmware (<< 17.0), preferenceloader`

Rootless payload paths include:
- `/var/jb/Library/LaunchDaemons/com.iuyghi.lumenboardd.plist`
- `/var/jb/Library/PreferenceBundles/LumenBoardPrefs.bundle/`
- `/var/jb/Library/PreferenceLoader/Preferences/LumenBoard.plist`
- `/var/jb/usr/libexec/lumenboardd`

The numeric-owner listing of data.tar.xz showed UID/GID `0/0` for every one of its 17 entries. The two executable Mach-O files, Preferences and `lumenboardd`, were identified by CI as arm64. The CI also checked rootless paths, file modes, absence of symlinks and unsafe permission bits, Preferences Info.plist fields, LaunchDaemon plist fields, maintainer-script executability and shell syntax.

The CI checked for the `LC_CODE_SIGNATURE` load command. This does **not** establish cryptographic signature validity or entitlement correctness.

## 5. Public source comparison: Nugget and PosterForge

Primary references inspected:

- Nugget documentation: https://github.com/leminlimez/Nugget/blob/26e0c50ec114ca3a4ff6ab2fb4ae309abfd39fa1/documentation.md
- Nugget PosterBoard implementation: https://github.com/leminlimez/Nugget/blob/26e0c50ec114ca3a4ff6ab2fb4ae309abfd39fa1/src/tweaks/posterboard/posterboard_tweak.py
- PosterForge README: https://github.com/mubixbyte/PosterForge/blob/1acacd5e01f676422195b4fbb644796f83c7671e/README.md
- PosterForge builder: https://github.com/mubixbyte/PosterForge/blob/1acacd5e01f676422195b4fbb644796f83c7671e/Daemon/PFPosterBuilder.m
- PosterForge shared helpers: https://github.com/mubixbyte/PosterForge/blob/1acacd5e01f676422195b4fbb644796f83c7671e/Shared/PFShared.m

Observed format facts:
- Nugget distinguishes whole-container archives from descriptor-format archives.
- Nugget documents descriptor(s) import to store version 59 on iOS 16 and version 61 on iOS 17+; descriptor import randomizes UUIDs and wallpaper IDs.
- PosterForge documents iOS 16.0–16.7.x rootless support and targets Collections descriptor storage at structure version 59.
- PosterForge's writer emits the descriptor root ID, role ID, keyed-archive providerInfo, provider contents user-info, Wallpaper.plist, background/floating .ca directories, CAML main.caml and a property-list index.xml.
- In the inspected static-image path, index.xml is written using property-list serialization (binary plist), despite the filename. The image is written as assets/0.jpg and referenced from main.caml.
- PosterForge's visible writer references assetManifest.caml from the index but its empty-layer helper does not write that file. LumenBoard's generator writes an empty CAML assetManifest.caml to close the reference. That difference is structurally explicit but is not proven necessary or renderer-compatible without a known-good iOS 16 fixture.

LumenBoard's native validator and installer enforce a stronger hostile-archive boundary than the simple path checks visible in PosterForge's importer: ZIP metadata consistency, CRC, bounds, traversal, duplicate/case/Unicode collisions, encrypted entries, symlink/special entries, extraction destination safety, and descriptor/CAML reference checks. LumenBoard targets the Collections extension and structure version 59.

No schema change was made based solely on conjecture. There is no license-cleared, known-good descriptor-format .tendies fixture in the project proving actual rendering on iOS 16.7.x. Generated descriptor output remains a structurally validated candidate, not a device-validated wallpaper.

## 6. Diagnostic procedure — not executed on device

After explicit authorization for a device test, collect evidence in this order:

1. Record the current package state and preserve the exact .deb checksum before any change.
2. Install only the named package/version after confirming the device is the intended iOS 16 rootless environment.
3. Record dpkg configure output and confirm package state; stop if maintainer scripts fail.
4. Inspect `launchctl print user/foreground/com.iuyghi.lumenboardd`; check the daemon log at `/var/mobile/Library/Logs/LumenBoard-daemon.log`.
5. Inspect the request/completion records and managed manifest. A successful descriptor publication is not proof of gallery rendering.
6. Import only a known-good descriptor-format fixture. Do not use a container-format archive.
7. Verify the descriptor under the PosterBoard Collections store, then separately verify native Collections visibility, preview, selection, Lock/Home rendering and persistence after reboot/respring.
8. Capture redacted logs and screenshots. Do not include device identifiers, private wallpaper assets or unrelated app data.

## 7. Rollback procedure — not executed on device

Rollback is conditional on first recording the pre-test package version and service state.

1. Stop the LumenBoard service in the `user/foreground` launchd domain using the package's supported teardown path; inspect for any stale legacy `system` registration.
2. Remove only `com.iuyghi.lumenboard` through the package manager if rollback is authorized and the package's prerm checks succeed.
3. Confirm the LumenBoard daemon is no longer registered and its executable/bundle payload is removed.
4. Preserve user library data and all unrelated PosterBoard descriptors. Do not recursively clear the PosterBoard descriptor store.
5. Reboot/respring only if needed and authorized; re-check service absence and system wallpaper state.
6. Record rollback logs and verify no unrelated descriptor or wallpaper was removed.

No install, upgrade, removal, launchctl action, PosterBoard refresh or other device-side mutation has been performed.

## 8. Evidence boundary and next prerequisite

CI establishes that the exact source commit built a rootless .deb and passed the listed automated checks. Artifact inspection independently establishes the downloaded package digest, metadata, archive members and numeric payload ownership.

Not established:
- cryptographic Mach-O signature validity or entitlements;
- successful installation/configuration on Dopamine;
- actual PreferenceLoader runtime loading;
- daemon startup on the iPhone;
- IPC behavior on the iPhone;
- native PosterBoard Collections visibility;
- preview, selection, wallpaper rendering or persistence after reboot.

Before a device test, obtain a legally sourced, known-good descriptor-format fixture verified on the target iOS 16.7.x build, and obtain explicit authorization for installation of the exact package identified by the .deb SHA-256 above. Until then, no device operation is authorized or performed.
