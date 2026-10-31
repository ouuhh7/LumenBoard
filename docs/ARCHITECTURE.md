# LumenBoard architecture — packaged implementation

## Runtime components

```text
PreferenceLoader pane (foreground mobile user)
  ├─ imports .tendies through UIDocumentPicker
  ├─ stores source archive + manifest under mobile Application Support
  ├─ writes bounded request plist into Requests/
  └─ polls Completed/ and reports registration state

launchd user/foreground/com.iuyghi.lumenboardd
  └─ /var/jb/usr/libexec/lumenboardd
       ├─ watches Darwin notification and polls request queue
       ├─ validates managed source identity + SHA-256
       ├─ discovers PosterBoard container by MCMMetadataIdentifier
       ├─ validates/extracts descriptor archive
       ├─ rewrites descriptor identifiers and stages trees
       └─ publishes new UUID directories into CollectionsPoster/59
```

## Package and launchd contract

- Package: `com.iuyghi.lumenboard`
- Current candidate: `0.1.0-9`
- Debian architecture: `iphoneos-arm64`
- Target: iOS 16.x, PosterBoard store structure 59, Collections extension
- Daemon: `/var/jb/usr/libexec/lumenboardd`
- LaunchDaemon plist: `/var/jb/Library/LaunchDaemons/com.iuyghi.lumenboardd.plist`
- Service identifier: `user/foreground/com.iuyghi.lumenboardd`

The foreground user domain is intentional for Dopamine rootless. `postinst` accepts an already-registered service only when launchctl returns status 37 and includes the `service already bootstrapped` diagnostic. It then requests `kickstart`. A successful kickstart means launchd accepted the request; it does not prove the daemon remained alive or completed an import.

## IPC and local source storage

`/var/mobile/Library/Application Support/LumenBoard/` contains `Library/<UUID>/source.tendies` and `manifest.plist`, `Requests/<request UUID>.plist`, and `Completed/<request UUID>.plist`.

The pane writes a bounded request with a fixed action allowlist. The daemon validates UUID, manifest identity, source filename, size and SHA-256 before processing. There is no arbitrary destination-path IPC action. Requests are serialized under a daemon lock; completion records are written atomically. A pane timeout is represented as queued/pending, not successful installation.

## Descriptor publication

The native installer targets `Library/Application Support/PRBPosterExtensionDataStore/59/Extensions/com.apple.WallpaperKit.CollectionsPoster/descriptors` inside the discovered PosterBoard app container. It validates descriptor roots and required metadata, rejects unsafe filesystem objects, assigns new UUID directory names and collision-checked numeric wallpaper identifiers, rewrites linked identifier fields, stages complete trees, and publishes by rename. Rollback is restricted to paths successfully published by the current invocation.

After publication, the implementation requests a PosterBoard refresh. This is separate from successful filesystem publication. UI status `registered-unverified` means descriptor records were published; it does not mean the item appeared in Collections, was selectable, or was applied as wallpaper.

## Known limitations and evidence gates

- Automated XCTest runs on macOS with synthetic fixtures; it does not reproduce iOS launchd, actual container permissions, or PosterBoard rendering.
- Package CI validates Debian metadata/archive, rootless paths, Mach-O architecture/signatures, Preferences bundle metadata, launchd plist, and maintainer-script behavior using a fake launchctl.
- Device evidence is still required for dpkg configuration, daemon survival, successful `.tendies` import, native gallery visibility, selection, wallpaper rendering, and persistence after reboot.
- Photo/video source import exists, but full conversion into PosterBoard animation descriptors is not claimed.
- Removing a source from LumenBoard's local library does not remove its published PosterBoard descriptor. Safe descriptor cleanup requires a separate ownership index and rollback-safe implementation.

Do not describe the package as fully working until all device-only evidence gates pass.
