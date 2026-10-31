<!-- Historical snapshot. This report describes the earlier offline-only generator phase; subsequent commits added the native .tendies daemon and descriptor publisher. Current authoritative implementation status: README.md, docs/ARCHITECTURE.md and docs/BUILD_AND_DEVICE_VALIDATION.md. -->

# LumenBoard engine phase report

Date: 2026-10-29

## Summary

This increment adds a full offline static-image descriptor candidate generator based on the public MIT-licensed PosterForge source, while keeping all native PosterBoard operations disabled. It also retains the previous template asset transformer and read-only descriptor consistency checker.

**Result by validation level:**

1. **Structural validation — passed for generated synthetic candidates.** The generator creates the descriptor tree, all metadata and two `.ca` layers, then runs the internal consistency checker before atomic publication.
2. **Comparison with a real iOS 16.7.16 reference — not completed.** A public release exists that describes its iOS 16 wallpaper as dumped from an iPhone 12, but its exact iOS build and successful rendering on 16.7.16 are not documented. Its Apple wallpaper assets have no explicit redistribution license in the release. Direct binary download was unavailable in this environment, so the archive was not analyzed or bundled.
3. **Native gallery on iPhone X / iOS 16.7.16 / Dopamine / RootHide — not tested.** No claim of native compatibility is made.

## Fixture research

- `C4ndyF1sh/Nugget-Wallpapers` GitHub releases contains a release titled `iPadOS 17+iOS16`; its release notes say the iOS 16 wallpaper was dumped from the author's iPhone 12. This is a credible provenance lead for an iOS 16-era descriptor, but not proof of iOS 16.7.16 compatibility. No explicit asset redistribution license was found, so it is not included.
- `SerStars/Nugget-Wallpapers` lists `wallpapers/apple/iOS16.tendies`; its README states the repository license as GPL-3.0 and the contribution guide says copyrighted Apple wallpapers are not accepted as ordinary user submissions. A GPL license for repository software does not automatically license Apple wallpaper assets.
- Nugget documentation states that descriptor-format packages target structure version `59` on iOS 16 and `61` on iOS 17+. This is format documentation, not evidence that any given archive renders on a particular point release.
- The direct GitHub binary fetch failed in this environment (the container cannot resolve GitHub and the web reader does not expose the archive bytes). No third-party wallpaper was copied into the project.

Public references:
- https://github.com/C4ndyF1sh/Nugget-Wallpapers/releases — release notes for `iPadOS 17+iOS16`.
- https://github.com/SerStars/Nugget-Wallpapers/blob/main/wallpapers-apple.json — catalog entry for `iOS16.tendies`.
- https://github.com/SerStars/Nugget-Wallpapers/blob/main/README.md — project GPL-3.0 notice.
- https://github.com/SerStars/Nugget-Wallpapers/blob/main/CONTRIBUTING.md — wallpaper contribution policy.
- https://github.com/leminlimez/Nugget/blob/main/documentation.md — descriptor format and structure-version notes.
- https://github.com/mubixbyte/PosterForge/blob/main/Daemon/PFPosterBuilder.m — technical reference for the generator.

## PosterForge source and implementation decisions

The source study is recorded in `docs/POSTERFORGE_ANALYSIS.md`. Key references include `installItem:error:`, `writeIndexAt:width:height:error:`, `writeEmptyLayerAt:error:`, `buildAnimationAt:source:kind:maxFPS:blurred:error:`, `randomizeDescriptorAtPath:`, `importTendiesAtPath:error:`, `removeIdentifier:error:`, and `refreshPosterBoard` in `Daemon/PFPosterBuilder.m`.

The new `tools/static_descriptor_generator.py` reimplements the observed static-image descriptor shape without copying upstream source. It creates:

- a UUID-named descriptor folder and collision-checked numeric identifier;
- root descriptor ID, role ID and an `NSKeyedArchiver`-style `providerInfo.plist`;
- `versions/1/contents/<UUID>.Custom.wallpaper/Wallpaper.plist`;
- provider user-info with matching wallpaper filename and numeric ID;
- `PF_Background.ca` with a single JPEG asset and static `CGImage` CAML;
- `PF_Floating.ca` with an empty layer;
- binary-plist `index.xml` files and an empty `assetManifest.caml` in each layer.

The empty manifest is a deliberate improvement over the visible upstream writer, which references `assetManifest.caml` from `index.xml` without creating it in the image/empty-layer path. The exact manifest contents accepted by Apple's renderer are unknown; the empty CAML root only closes local references and must be checked against a real reference before native use.

The generator stages into a temporary directory under the selected output root, checks the generated descriptor with `descriptor_consistency.py`, and atomically renames it to a new UUID destination. It never overwrites a prior descriptor. It does not touch the device, app container, system wallpapers or PosterBoard preferences.

## License and attribution

PosterForge's public repository declares MIT. The current code is a new implementation informed by public source behavior, not copied source files. `NOTICE.md` records this technical reference. No third-party wallpaper assets are bundled. Any future adaptation of upstream code must preserve the relevant copyright and MIT license notices; any wallpaper fixture needs its own provenance and redistribution-rights review.

## Automated tests

The suite now contains **68 tests**:

- 29 existing `.tendies` inspector and package-contract tests;
- 16 template-transformer tests;
- 13 descriptor-consistency tests;
- 10 full descriptor-generator tests;
- one synthetic JPEG file used only by tests.

Commands run:

```sh
python3 -m unittest discover -s tests -v
python3 -m py_compile tools/tendies_inspect.py tools/static_wallpaper_builder.py tools/descriptor_consistency.py tools/static_descriptor_generator.py tests/test_tendies_inspect.py tests/test_static_wallpaper_builder.py tests/test_descriptor_consistency.py tests/test_static_descriptor_generator.py
python3 tools/tendies_inspect.py --help
python3 tools/static_wallpaper_builder.py --help
python3 tools/descriptor_consistency.py --help
python3 tools/static_descriptor_generator.py --help
```

The suite passes with `Ran 68 tests ... OK`. The generated candidate passes the project's structural checker and its ID/file references are internally consistent. All generator tests use the synthetic JPEG, not a real iOS wallpaper fixture.

## Build/device status

- Theos is not configured (`THEOS` unset).
- `xcrun` and an Apple SDK are unavailable.
- `make clean package FINALPACKAGE=1` is blocked because the Makefile resolves `/makefiles/common.mk` when `THEOS` is unset. No build success is claimed.
- No DEB, install, native gallery, persistence, reboot or rollback test was performed.
- Native PosterBoard writes, refresh, import, update and removal remain disabled.
- No GitHub repository was created and no push was made.

## Single indispensable evidence item remaining

A complete descriptor-format `.tendies` archive or extracted descriptor tree **known to appear and render in native Collections on iOS 16.7.16**, accompanied by provenance and permission to inspect it locally. It need not be redistributed in the project. That one reference artifact enables a true file-by-file/CAML/metadata comparison; the eventual on-device LumenBoard rendering test remains a separate device-only gate.
