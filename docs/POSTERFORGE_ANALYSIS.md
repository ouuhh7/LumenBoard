# PosterForge source study and LumenBoard safety decisions

## Public source examined

Repository: [mubixbyte/PosterForge](https://github.com/mubixbyte/PosterForge)

The analysis refers to the public source currently reachable at the links below. These are implementation observations, not evidence of a successful build or a test on the target iPhone.

| Source file | Exact API/helper | Observed responsibility |
|---|---|---|
| [`Daemon/PFPosterBuilder.h`](https://github.com/mubixbyte/PosterForge/blob/main/Daemon/PFPosterBuilder.h) | `installItem:error:`, `removeIdentifier:error:`, `importTendiesAtPath:error:`, `refreshPosterBoard` | Declares the daemon's install, remove, import and refresh operations. |
| [`Daemon/PFPosterBuilder.m`](https://github.com/mubixbyte/PosterForge/blob/main/Daemon/PFPosterBuilder.m) | `descriptorRoot:error` | Finds the PosterBoard container and targets `Library/Application Support/PRBPosterExtensionDataStore/59/Extensions/com.apple.WallpaperKit.CollectionsPoster/descriptors`. |
| same | `installItem:error:` | Creates a UUID-named descriptor directory and `<UUID>.Custom.wallpaper`; writes root metadata and provider user-info; creates `PF_Background.ca` and `PF_Floating.ca`; writes `Wallpaper.plist`; builds the layer CAML and calls `refreshPosterBoard`. |
| same | `writeIndexAt:width:height:error:` | Serializes a property-list dictionary to a file named `index.xml`, with `rootDocument = main.caml`, `assetManifest = assetManifest.caml`, width/height and rendering flags. The extension is therefore not proof that this file is XML text. |
| same | `writeEmptyLayerAt:error:` | Writes an empty `main.caml` and an `index.xml` for the empty layer. In the visible source path, the index declares `assetManifest.caml` while this helper does not itself write that file. Whether PosterBoard tolerates the dangling reference must be resolved against a real fixture/device; LumenBoard must not copy this detail as an established requirement. |
| same | `buildAnimationAt:source:kind:maxFPS:blurred:error:` | Builds a layer's `assets` and animation description. The visible video branch uses `AVURLAsset`/`AVAssetImageGenerator`, clamps requested FPS to 1–30, caps the frame count at 400 and discards the video's audio. The image branch and optional blur are implemented in this method. |
| same | `removeIdentifier:error:` | Removes the descriptor path derived from the supplied identifier and then calls `refreshPosterBoard`. LumenBoard must enforce its own validated identifier, root containment and ownership checks; it must not copy an unchecked path-join pattern. |
| same | `importTendiesAtPath:error:` | Lists archive members, rejects obvious absolute paths, backslashes and `..`, extracts to a temporary directory, searches for descriptor directories, copies child descriptor directories into the store, randomizes IDs and refreshes. This is a useful reference, not a sufficient security model for LumenBoard. |
| same | `randomizeDescriptorAtPath:` | Rewrites the root descriptor identifier, `wallpaperRepresentingIdentifier`, the top-level `Wallpaper.plist` identifier, and `assets.lockAndHome.default.identifier`. |
| same | `refreshPosterBoard` | Writes keys in `com.apple.PosterBoard.unprotectedUserDefaults.plist` and runs `killall -9 PosterBoard`. LumenBoard implements a separately bounded and diagnosed refresh request after publication; source code behavior here is reference only. |
| [`Shared/PFShared.h`](https://github.com/mubixbyte/PosterForge/blob/main/Shared/PFShared.h), [`Shared/PFShared.m`](https://github.com/mubixbyte/PosterForge/blob/main/Shared/PFShared.m) | `PFNewIdentifier`, `PFPosterBoardContainer`, `PFQueueRequest`, `PFSaveItem`, `PFDeleteItem` | Defines UUID generation, container discovery, local manifest/request/completion paths and the daemon request queue. |
| [`Daemon/main.m`](https://github.com/mubixbyte/PosterForge/blob/main/Daemon/main.m) | `ProcessRequests`, `NotificationCallback`, `main` | Processes `install`, `remove` and `tendies` requests, records completion results, and watches the Darwin notification plus a polling timer. |

## Descriptor fields observed in `installItem:error:`

The visible source writes these files beneath a per-descriptor directory:

- `com.apple.posterkit.provider.descriptor.identifier` — numeric ID rendered as a string.
- `com.apple.posterkit.role.identifier` — `PRPosterRoleLockScreen` in this implementation.
- `providerInfo.plist` — data produced by `NSKeyedArchiver` with a configuration-last-use date.
- `versions/1/contents/<UUID>.Custom.wallpaper/Wallpaper.plist`.
- `versions/1/contents/com.apple.posterkit.provider.contents.userInfo`.
- The wallpaper plist's `assets.lockAndHome.default` dictionary refers to the background/floating `.ca` bundle names and repeats the numeric wallpaper ID; it also includes fields such as `type = LayeredAnimation`, `contentVersion = 2.01`, `family = Marble`, `logicalScreenClass = 375w-812h@3x~iphone`, `name`, `version` and prominent colors.

The user-info dictionary includes `wallpaperRepresentingFileName`, `wallpaperRepresentingIdentifier`, and `posterEnvironmentOverrides`. ID rewriting must update all observed copies consistently, and must first verify collisions against the entire target descriptor store. The upstream source chooses IDs randomly but does not visibly perform an exhaustive collision check before publication.

Each `.ca` animation bundle uses `main.caml`, `assetManifest.caml`, `index.xml`, and any referenced assets. In this implementation, `index.xml` is written through property-list serialization. The exact file syntax, complete CAML shape, optional assets and tolerated omissions must be checked against a real reference rather than inferred from filenames alone.

## Public evidence on `.tendies` formats and structure versions

The [PosterForge README](https://github.com/mubixbyte/PosterForge) claims support for rootless iOS 16.0–16.7.x, descriptor-format `.tendies`, static images and video, and descriptor store structure version `59`. The [Nugget PosterBoard implementation](https://github.com/leminlimez/Nugget/blob/main/src/tweaks/posterboard/posterboard_tweak.py) and [Nugget documentation](https://github.com/leminlimez/Nugget/blob/main/documentation.md) distinguish descriptor-format archives (`descriptor/` or `descriptors/`) from whole-container archives, and describe `59` as the iOS 16 destination and `61` for iOS 17 and later. These sources support the format distinction; they do not supply proof that any generated LumenBoard output renders on this iPhone X.

## Findings that affect LumenBoard design

1. Keep runtime writes staged, validated and rollback-bounded. Metadata serialization alone does not prove compatibility. The exact iOS build, device-specific `logicalScreenClass`, CAML parser behavior and optional files remain unknown until compared with a real working iOS 16 reference.
2. Generate in a staging directory and verify every write before publication. Do not delete an existing descriptor path during generation.
3. Generate identifiers with collision checks, then update all fields and filename references from a verified mapping. Never reuse identifiers merely because they look UUID-like or numeric.
4. Treat archive imports as hostile: inspect the ZIP before extraction; reject duplicate/aliased names, traversal, symlinks/special files and resource exhaustion. The portable inspector's stronger checks do not imply that the iOS UI currently invokes it.
5. Limit remove/update operations to descriptors recorded as LumenBoard-owned, with validated identifiers and safe canonical paths. Never remove an arbitrary path or mutate the whole PosterBoard container.
6. LumenBoard's import/publication and refresh code is implemented, but only structural publication is claimed. PosterForge's `killall -9 PosterBoard` is a reference behavior; LumenBoard uses its own bounded runner and reports the outcome separately. Removal remains unimplemented, and native gallery acceptance still requires on-device evidence.

## Reference fixture: not present

No known-good `.tendies` archive or full extracted descriptor tree verified to appear and render on iOS 16.7.x was found in the working project or incoming files during this phase. Public schemas and source code are not a substitute for that missing fixture.

The next implementation step requires one legally obtained **descriptor-format** archive known to render on iOS 16.7.x (not a whole-container restore), or an exported tree from the working iPhone. Include:

- The entire `descriptors/<descriptor-id>/` directory, including the three root metadata files, not only `Wallpaper.plist`.
- `versions/1/contents/`, the complete `.wallpaper` bundle and provider user-info.
- All `.ca` folders with their actual `main.caml`, `assetManifest.caml`, `index.xml` and assets, with no omitted siblings.
- A record of source iOS build/device, how the wallpaper was imported, and evidence that it appears in the native Collections gallery and actually renders.
- License/provenance information sufficient to use it as a local test fixture. The reference asset itself will not be redistributed in the project ZIP.

Record the real tree exactly as observed. If it differs from the current PosterForge writer, document the difference; do not force the fixture into an assumed schema.

## License

PosterForge's repository states an MIT license. This project currently uses it as a technical reference and does not copy its source files. If future code adapts substantial portions, preserve the relevant copyright/license notice. A wallpaper archive or Apple image assets can have separate rights and must not be bundled without a lawful basis.

## Static-image CAML details used by LumenBoard's offline generator

The public `buildAnimationAt:source:kind:maxFPS:blurred:error:` implementation was inspected directly. For a static image it loads a `UIImage`, records its pixel width/height, writes JPEG data at `assets/0.jpg`, and writes `main.caml` with a CoreAnimation namespace, a background `CALayer`, a nested layer whose `contents` references `assets/0.jpg`, and the `Locked`, `Unlock`, and `Sleep` states. The video branch constructs `CAKeyframeAnimation` values over frame names; the static branch has no sequence animation. `writeIndexAt:width:height:error:` serializes a property-list dictionary with `rootDocument`, `assetManifest`, `documentWidth`, `documentHeight`, and rendering flags to `index.xml` in binary plist format.

LumenBoard's `tools/static_descriptor_generator.py` independently implements this observed static-image shape and uses a minimal empty `assetManifest.caml` to close the path referenced by `index.xml`. PosterForge's visible image/empty-layer helper does not itself write that file. The empty manifest choice is not validated against a real iOS 16 descriptor; the generator therefore reports structural success only and cannot claim renderer compatibility.
