# LumenBoard — rootless iOS 16 PosterBoard importer

LumenBoard is a rootless jailbreak package targeting arm64 iOS 16, including iPhone X / iOS 16.7.16. The current package includes a PreferenceLoader pane, native `.tendies` validation, a launchd-managed daemon, and a descriptor publisher for the iOS 16 Collections PosterBoard store.

## Current status

Package version under validation: `0.1.0-9` (`iphoneos-arm64`). The package compiles the Preferences bundle and `lumenboardd`; the daemon is staged at `/var/jb/usr/libexec/lumenboardd` and registered through `/var/jb/Library/LaunchDaemons/com.iuyghi.lumenboardd.plist` in Dopamine's `user/foreground` launchd domain.

The Preferences pane stores photo/video selections as local source imports. `.tendies` archives are copied into the managed library, validated, submitted to the daemon, and—when accepted—published as descriptor records into the iOS 16 Collections store. The UI distinguishes descriptor publication from confirmed gallery visibility, selection, and wallpaper application.

The package has passed native XCTest and rootless package validation in earlier CI runs. Version `0.1.0-9` adds regression tests for repeated configuration, strict status-37 handling, migration of any stale `system`-domain registration, and safe package removal from both service domains. CI success does not prove installation or PosterBoard rendering on the target iPhone. Device validation remains mandatory.

Not claimed: a complete photo/video-to-CAML conversion pipeline, safe native removal of published descriptors, or verified wallpaper rendering on iOS 16.7.16. Removing a source from LumenBoard's local library does not remove an already-published PosterBoard descriptor.

## Build and package requirements

- A supported Theos environment: macOS with Xcode/iOS SDK, or Linux with the official Theos cross-toolchain and a suitable iOS SDK (the public Theos SDK repository includes iOS 16.5),
- Theos configured in `THEOS`,
- the applicable rootless packaging tools and PreferenceLoader headers/framework.

The original local build attempt on 2026-10-29 is documented in [`docs/THEOS_BUILD_REPORT_2026-10-29.md`](docs/THEOS_BUILD_REPORT_2026-10-29.md). That environment lacked Theos/SDK; the package is now built in GitHub Actions using a supported macOS/Theos toolchain.

Then run:

```sh
make clean package FINALPACKAGE=1
```

The package is emitted under `packages/`. The current aggregate target compiles and stages both the Preferences bundle and the native daemon. Use the GitHub Actions artifact for the exact verified CI build; local builds require a supported Theos installation and iOS SDK.

## Portable validation tests

Python 3.11+ is sufficient; no third-party Python package is needed:

```sh
python3 -m unittest discover -s tests -v
python3 tools/tendies_inspect.py --help
python3 tools/static_wallpaper_builder.py --help
python3 tools/descriptor_consistency.py --help
python3 tools/static_descriptor_generator.py --help
```

Inspect a user-supplied archive without extracting it:

```sh
python3 tools/tendies_inspect.py path/to/wallpaper.tendies
```

Extract only a descriptor-format archive into a new/empty directory:

```sh
python3 tools/tendies_inspect.py path/to/wallpaper.tendies --extract /tmp/lb-inspected
```

The inspector is a development/test utility; the Preferences app does not shell out to Python. Do not interpret a successful ZIP inspection as proof that the wallpaper is compatible with PosterBoard.

## Repository/publication status

Development is maintained in the private GitHub repository `ouuhh7/LumenBoard`; active fixes are isolated on `fix/rootless-deb-installation`. The default branch is not modified.

## Descriptor consistency checker

`tools/descriptor_consistency.py` performs a read-only structural check over an extracted descriptor-format tree. It cross-checks observed descriptor identifiers and provider user-info references, wallpaper bundle paths, `.ca` layer references, index plist targets, CAML XML syntax and referenced assets. It reports only structural consistency; it does not prove compatibility with PosterBoard or replace a real iOS 16 reference. See `docs/DESCRIPTOR_VALIDATOR.md`.

Example after extracting a verified reference archive:

```sh
python3 tools/descriptor_consistency.py /tmp/lb-reference/descriptors
```

## Experimental static-image template transformer

`tools/static_wallpaper_builder.py` is a conservative, developer-only prototype. It does **not** synthesize a new PosterBoard schema. It requires a `.wallpaper` bundle extracted from a known-good iOS 16 descriptor fixture, then replaces one existing PNG/JPEG asset that is referenced by `main.caml`, `assetManifest.caml`, or `index.xml`. The source and target extensions must match. It preserves the reference CAML and plist files, stages output beside the destination, and refuses to overwrite existing paths.

Example (only after obtaining and inspecting a lawful known-good iOS 16 fixture):

```sh
python3 tools/tendies_inspect.py /path/to/known-good-ios16-descriptor.tendies --extract /tmp/lb-reference
python3 tools/static_wallpaper_builder.py \
  --template-bundle /tmp/lb-reference/descriptors/UUID/versions/1/contents/NAME.wallpaper \
  --asset 'BACKGROUND.ca/assets/existing.png' \
  --image /path/to/replacement.png \
  --output /tmp/LumenBoard-Candidate.wallpaper
```

The example paths after `descriptors/UUID/...` are placeholders and must be replaced with the exact tree and asset path present in the supplied archive. The tool produces a sibling `.report.json` sidecar. It does not rewrite descriptor UUIDs, wallpaper IDs, `providerInfo.plist`, `Wallpaper.plist`, provider user-info, or references outside the `.wallpaper` bundle. Consequently, its output is an offline candidate for comparison only—not an installable wallpaper descriptor and not proof of iOS 16.7.16 compatibility.

Supported source formats are PNG and JPEG, with basic signature/dimension checks. Video, CAML generation, `.tendies` runtime import, native installation/removal, and PosterBoard refresh remain out of scope. No native PosterBoard writes are enabled.


## Experimental full static descriptor generator

`tools/static_descriptor_generator.py` generates a complete local descriptor candidate from a JPEG using the public MIT-licensed PosterForge implementation as a technical reference. It creates the root metadata, `providerInfo.plist`, provider user-info, `Wallpaper.plist`, background/floating `.ca` bundles, CAML, manifests and index plists; it checks for ID collisions and runs the descriptor validator before atomically publishing the output.

```sh
python3 tools/static_descriptor_generator.py /path/to/photo.jpg /tmp/lb-candidates --title "My Static Poster"
python3 tools/descriptor_consistency.py /tmp/lb-candidates
```

This is structural validation only. A public iOS 16 dump from an iPhone 12 was found as a research lead, but the exact build/native rendering on iOS 16.7.16 and redistribution rights for its Apple assets are not verified; no third-party fixture is included. The generated empty `assetManifest.caml` is an unverified schema choice and must be compared with a real reference. No native PosterBoard write, refresh, import, update or removal is enabled. See `docs/ENGINE_PHASE_REPORT.md` for the fixture search, source attribution and three validation levels.
