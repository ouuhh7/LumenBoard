# BlackHole.tendies fixture assessment — 2026-11-01

## Scope

Read-only inspection of the user-supplied `BlackHole.tendies` archive. The archive was not executed, installed, or modified. No PosterBoard process or device state was touched.

- Archive size: 1,924,292 bytes
- SHA-256: `28189fb9d018d73bc503f6e7181482138236f11b9973a3ec57d2c0db93bf5e0d`
- ZIP entries: 110
- ZIP CRC verification: passed
- Descriptor UUID: `07B0E8C1-2763-4FCB-8640-9026FC9B0225`
- Descriptor identifier: `3141`
- Role: `PRPosterRoleLockScreen`

## Structural observations

The archive is descriptor-format, with the expected `versions/1/contents` tree, provider metadata, provider contents user-info, one `.wallpaper` bundle, `Wallpaper.plist`, and Background/Floating `.ca` bundles.

The root provider metadata and property lists parse. The user-info wallpaper filename matches the actual bundle name; its wallpaper identifier matches both the descriptor identifier and the top-level/default identifiers in `Wallpaper.plist`.

Both `index.xml` files parse as property lists and point to `main.caml` and `assetManifest.caml`. Both CAML documents parse as XML. The Floating CAML contains 36 asset references; all resolve after URL-percent-decoding, including filenames containing spaces. The Background CAML contains no asset references.

The Background `.ca` bundle does not contain `assetManifest.caml`, despite the index pointer. This is a warning, not evidence by itself that the package is unusable: PosterForge's public `writeEmptyLayerAt` implementation writes `main.caml` and an index pointing to `assetManifest.caml` without creating that manifest file. The Background layer here has no CAML asset references, which is consistent with that manifest-free pattern. Actual Apple renderer tolerance remains unverified.

Finder metadata (`__MACOSX`, AppleDouble `._*`, and `.DS_Store`) is present. LumenBoard's native validator explicitly excludes these paths from extraction while still validating archive paths, sizes, and CRCs.

A `script.js` file is present in the Floating assets directory. It was treated as inert archive data and was not executed. It is not required for the observed CAML asset-reference checks.

## Device compatibility finding

`Wallpaper.plist` declares:

- `logicalScreenClass = 810w-1080h@2x~ipad`
- Background/Floating document geometry: 3176 × 3176

This is an iPad-oriented descriptor, not an iPhone X descriptor. PosterForge's iOS 16 reference builder uses `375w-812h@3x~iphone` for its iPhone poster template, matching the iPhone X logical dimensions. Renaming the screen-class string alone would not safely convert this package: its CAML geometry and artwork layout are square and iPad-derived.

**Disposition:** structurally useful as a real descriptor-format parser/import fixture, but not suitable as an iPhone X / iOS 16.7.16 rendering-compatibility fixture. Do not auto-rewrite its screen class or CAML geometry and do not publish it to the device as an iPhone wallpaper.

## LumenBoard implementation implications

- `LBTendiesValidator` checks ZIP integrity, path safety, metadata plist syntax, and basic `Wallpaper.plist` presence. Its successful result is structural only.
- `LBValidateDescriptorTree` checks the descriptor metadata relationships, wallpaper bundle, both CA bundles, index plist fields, CAML XML, and referenced asset files.
- The current native descriptor-tree check verifies that `index.xml` names `main.caml` and `assetManifest.caml`; it does not require the manifest target itself to exist. The separate Python consistency checker reports an absent manifest target as a warning.
- The archive's percent-encoded/spaced asset names should remain unchanged; URL-decoding is for reference resolution, not a reason to rename payload files.

## Verification boundary

No cryptographic or Apple-private schema guarantee is claimed. No install, PosterBoard refresh, gallery visibility, wallpaper selection, Lock Screen rendering, or Home Screen rendering was tested. Device validation remains a separate step requiring an iPhone X running the target iOS 16 build and explicit installation authorization.

## Source references

- Nugget format documentation: https://github.com/leminlimez/Nugget/blob/main/documentation.md
- PosterForge iOS 16 reference builder: https://github.com/mubixbyte/PosterForge/blob/main/Daemon/PFPosterBuilder.m
- PosterForge project compatibility and device-target notes: https://github.com/mubixbyte/PosterForge/blob/main/README.md
- LumenBoard native validator: https://github.com/ouuhh7/LumenBoard/blob/fix/rootless-deb-installation/Preferences/LBTendiesValidator.m
- LumenBoard descriptor consistency checker: https://github.com/ouuhh7/LumenBoard/blob/fix/rootless-deb-installation/tools/descriptor_consistency.py
- LumenBoard descriptor publisher: https://github.com/ouuhh7/LumenBoard/blob/fix/rootless-deb-installation/Daemon/LBPosterBoardInstaller.m
