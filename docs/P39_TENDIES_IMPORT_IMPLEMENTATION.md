# P39 — Tendies → PosterBoard Collections implementation report

Date: 2026-10-30  
Repository: `ouuhh7/LumenBoard`  
Working branch: `work/tendies-native-validation`  
Verified implementation commit: `f02e0e016643e70f9822cecb762de9f4c74f63c1`  
CI run: [41132915128](https://github.com/ouuhh7/LumenBoard/actions/runs/41132915128)

## 1. Original defect

The old Preferences import flow copied a `.tendies` archive into LumenBoard's managed library, validated/extracted it, then intentionally stopped at `pending-validation` / `Stored for inspection`. It persisted `installationState = installation-disabled` and did not submit an installation request.

The daemon was also a stub: it returned `native_integration_disabled`. It was not part of the top-level Theos build/package, and its LaunchDaemon plist and maintainer scripts existed only as prototypes. Therefore the archive was never published into PosterBoard's descriptor store. The failure was downstream of copying and ZIP validation, not merely a bad file picker.

## 2. Implemented end-to-end path

The implemented descriptor-format path is:

`document picker → security-scoped source access → source SHA-256 → private copy → copy SHA-256 comparison → LBTendiesValidator → safe extraction → descriptor-tree validation → fresh identifiers → staged publish → PosterBoard refresh request → daemon completion → manifest imported/failed/queued`.

The Preferences UI now persists explicit states:
- `copying`
- `validating`
- `extracting`
- `registering`
- `imported`
- `failed`

A daemon timeout leaves the source and extracted tree intact with `registering` plus a request ID; the library refresh action can reconcile the completion record. Re-selecting an already imported or currently registering archive with the same SHA-256 is deduplicated, so no second descriptor publication or request is created.

### Acquisition and integrity

- File picker URLs are accessed through the security-scoped URL API and released in a `finally` path.
- Inputs must be regular, non-symlink files, non-empty, and no larger than 300 MiB.
- SHA-256 is computed before source movement/copy and again on the managed copy; mismatch is rejected.
- The daemon independently recomputes and compares the stored manifest SHA-256 before processing the source.
- The original archive remains stored as `source.tendies`; extraction is separate and does not overwrite it.

### Validation and extraction

The existing Objective-C `LBTendiesValidator` is reused; no second ZIP implementation was introduced. It rejects malformed ZIP metadata, unsafe paths, duplicates/collisions, CRC inconsistencies, encrypted entries, malformed plist data, false size declarations, excessive compression ratios, and extraction destination errors. The full native test set also covers accepted signed/unsigned data descriptors and preserves the original archive.

### Descriptor installer

New components:
- `Daemon/LBPosterBoardInstaller.h`
- `Daemon/LBPosterBoardInstaller.m`

The installer targets descriptor-format iOS 16 Collections PosterBoard packages only:
- PosterBoard container is resolved using `MCMMetadataIdentifier = com.apple.PosterBoard`.
- Extension: `com.apple.WallpaperKit.CollectionsPoster`.
- Store structure version: `59`.
- Descriptor directory: `Library/Application Support/PRBPosterExtensionDataStore/59/Extensions/com.apple.WallpaperKit.CollectionsPoster/descriptors`.

It requires exactly one `descriptor` or `descriptors` group and rejects container restore, video/photos, and Mercury extension variants. It validates descriptor roots, `providerInfo.plist`, role identifier, provider contents user-info, referenced wallpaper bundle, `Wallpaper.plist`, lock/home defaults, referenced background/floating `.ca` bundles, and their `index.xml` / `main.caml` files.

Each imported descriptor is copied into a staging directory, assigned a new UUID folder and collision-free numeric wallpaper ID, and its root identifier, provider user-info identifier, and relevant `Wallpaper.plist` identifiers are rewritten consistently. Staged entries are published by rename only after all source descriptors validate. On failure, rollback removes only folders actually published by that request; it will not delete a path that appeared concurrently.

The path creation routine rejects symlinks in ancestors except Apple's known `/var` alias, which is resolved to its real path. The staged descriptor tree is set to `mobile:mobile` ownership and readable directory/file modes before publication.

### Registration and refresh

The daemon `lumenboardd` now handles the `import-tendies` IPC action, verifies request IDs, manifest identity, source filename, file type, maximum size, and SHA-256, then invokes the installer. It writes a bounded completion plist for the Preferences process and updates the managed manifest to `imported` or `failed`.

After descriptor publication, the installer writes the observed PosterBoard refresh preferences (`PBF_LOCALE_DID_CHANGE`, `PBF_RESET_FILE_PROTECTIONS`) and requests a PosterBoard process restart. This follows the descriptor-store import pattern observed in PosterForge's iOS 16 implementation; it is an on-disk/private implementation convention, not a documented public Apple API. The code does not fabricate CAML or a new wallpaper schema: it imports and validates CAML/descriptor payload already present in the .tendies archive.

No SQLite database writes were added. The available local descriptor-import reference implementation publishes descriptor folders and refreshes PosterBoard without a SQLite mutation; other PosterBoard database code paths relate to backup/configuration management and are not assumed to be the installation contract.

## 3. Rootless package

The root Makefile now builds:
- `lumenboardd` for `arm64`, installed to `/usr/libexec` (rootless staging makes this `/var/jb/usr/libexec/lumenboardd`);
- the Preferences bundle under `/Library/PreferenceBundles`;
- LaunchDaemon plist `com.iuyghi.lumenboardd.plist` under `/Library/LaunchDaemons`;
- `postinst` / `prerm` scripts for bootstrap and teardown.

Package scheme: `rootless`. Target: iOS 16, patched Theos iOS 16.5 SDK. The patched SDK is required because Xcode's public SDK no longer carries the private Preferences framework link stub used by the Preferences bundle. Package compression is XZ. Maintainer scripts are chmodded in the actual Theos staging directory before packaging.

The workflow uses macOS 15 runners; macOS 14 runners were cancelled by GitHub's scheduled runner retirement/brownout.

## 4. Automated verification

CI run [41132915128](https://github.com/ouuhh7/LumenBoard/actions/runs/41132915128) completed with both jobs successful:

| Suite | Tests | Result |
|---|---:|---|
| `LBTendiesValidatorTests` | 27 | 0 failures |
| `LBPosterBoardInstallerTests` | 7 | 0 failures |
| Total XCTest | 34 | **0 failures** |

Installer tests verify: one valid descriptor with all linked IDs rewritten; multiple descriptors with distinct UUIDs/IDs; missing `Wallpaper.plist`; missing `providerInfo.plist`; a symlink inside a descriptor; a symlinked PosterBoard destination parent; and multiple descriptor groups.

The ZIP validator suite includes non-ZIP/missing/truncated archives, bad CRC, path traversal/absolute/backslash paths, duplicate names and Unicode/case collisions, encrypted entries, EOCD/ZIP64/multidisk errors, inconsistent headers/central directory offsets, malformed wallpaper plist, false uncompressed-size declarations, excessive compression ratio, and extraction-root creation failure.

### Rootless .deb result

The build and package verification succeeded for:
- Package: `com.iuyghi.lumenboard`
- Version: `0.1.0-1`
- Architecture: `iphoneos-arm64`
- Depends: `firmware (>= 16.0), firmware (<< 17.0), preferenceloader`

CI verified the package metadata, contents, extraction, executable daemon, LaunchDaemon plist, and maintainer script permissions. Package SHA-256:

`0c5cc1f3b2578ffcdb044633b876724c3be99cedb5bf3af518750266bf1c42ca`

Artifacts:
- `lumenboard-rootless-package` (artifact ID `13013254911`)
- `native-xctest-log` (artifact ID `13012889750`)

## 5. Scope and remaining proof

**Verified in CI:** Objective-C native compilation for arm64, 34 XCTest cases, creation and structural verification of the rootless .deb, presence and packaging of daemon/Preferences/LaunchDaemon, and ZIP/descriptor installation logic against synthetic descriptor fixtures.

**Not verified:** actual execution of `lumenboardd` on iOS 16.7.16; PosterBoard container discovery on the target phone; acceptance of a real user-supplied `.tendies` archive; native gallery display, wallpaper selection, and wallpaper application on an iPhone X. No package was installed on a device, as required by the development constraint.

The implementation therefore advances beyond local file storage and builds a complete descriptor-import/registration route, but **real PosterBoard visibility and applicability are not certified until a device test is performed**. The P39 workflow intentionally does not claim that on-device result.

## 6. Branch and safety status

- All P39 source changes are on `work/tendies-native-validation`.
- `main` was not modified.
- Repository visibility and migration state were not changed.
- No iPhone package installation or device modification was performed.
