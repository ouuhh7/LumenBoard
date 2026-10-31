> **Historical audit snapshot:** this report records an earlier repository state and must not be used as the current source inventory or release verdict. The current implementation and verification status are recorded in `README.md` and `docs/BUILD_AND_DEVICE_VALIDATION.md`.

<!-- Historical snapshot. This report records the pre-integration review performed on 29 October 2026; subsequent commits added and packaged the daemon/descriptor importer. Current authoritative implementation status: README.md, docs/ARCHITECTURE.md and docs/BUILD_AND_DEVICE_VALIDATION.md. -->

# LumenBoard-Development-Fresh — technical review

Review date: 29 October 2026. Scope: direct inspection of the local source tree, source history, ZIP artifact, Python validator and tests; read-only study of public PosterForge/Nugget/Tools documentation. No GitHub repository was created and no push was made.

## Artifact and Git provenance

The original artifact was present at `/mnt/data/LumenBoard-Development-Fresh-baseline.zip`. Its SHA-256 was recalculated and matched the previously declared value:

`59e559feaad9bc9a3d6fe75d93e154b9366160799bea8a3cfe9c6ab6316db369`

`unzip -t` reported no archive errors. The source directory existed. Before this review's corrections, `git branch --show-current` returned `main`, HEAD was `ed7d1fb619d7e6d0b4409a19cc2637c3526f2596`, the repository contained one commit and 25 tracked source/project files, the working tree was clean, and `git fsck --full --no-reflogs` reported no integrity errors. This was a separate, newly initialized history; no prior project Git history was imported.

## Findings and corrections

1. **Rootless Debian architecture mismatch — corrected.** `control` declared `iphoneos-arm` while `THEOS_PACKAGE_SCHEME = rootless`. Theos documents `iphoneos-arm64` for rootless packages. `control` now uses `iphoneos-arm64`.
2. **Missing Preferences executable metadata — corrected.** `Preferences/Info.plist` did not declare `CFBundleExecutable`; it now declares `LumenBoardPrefs`. The bundle still needs compilation and on-device loading tests.
3. **Unnecessary privileged daemon was staged for installation — corrected by removing it from the package target.** The daemon had no implemented native install/remove operation and the UI did not enqueue requests. A root process polling a mobile-writable directory adds attack surface without providing a current user function. `Daemon/main.m` remains a source prototype; its LaunchDaemon plist and maintainer scripts were moved to `docs/prototypes/`, outside the Theos package layout. The top-level Makefile now packages only the unprivileged Preferences bundle. The daemon is not compiled, staged, or run.
4. **False-positive archive validation — corrected.** Previously, a descriptor-looking ZIP containing a malformed `Wallpaper.plist` could return `valid_zip: true` with an empty `parseable_plists` list. Small `.plist` entries are now required to parse; malformed or over-limit plist entries are rejected and at least one parseable plist is required.
5. **Filesystem path collisions — corrected in the portable inspector.** Duplicate detection now uses Unicode NFD normalization plus case folding (relevant to case-insensitive/Unicode-normalizing target filesystems), and file/directory prefix collisions are rejected before extraction.
6. **Preferences UI responsiveness — corrected in source.** File inspection/copying moved off the UI thread. The importer no longer silently relabels an unknown media extension as `.jpg` or `.mov`; it uses a preferred extension only when allowed and otherwise rejects the import. `.tendies` import feedback says that the archive is stored but neither validated nor installed.
7. **Managed-library enumeration — hardened in source.** List/refresh operations now require UUID-named regular directories and manifests whose identifier matches the directory, instead of counting/reading any plist encountered under the library path.

These Objective-C changes have not been compiled in this environment because Theos and an iOS SDK are absent. They are source-level corrections, not a claim that the Preferences bundle builds.

## Current tracked-file inventory (25 files)

| Path | Purpose | Implementation status after review |
|---|---|---|
| `.gitignore` | Excludes build output, Theos cache, Python caches and packaging artifacts | Implemented configuration |
| `Daemon/main.m` | Prototype request queue / completion responder | Not packaged; native install/remove remains disabled; requires IPC path/ownership/race review before use |
| `LICENSE` | LumenBoard MIT license | Present; does not license third-party wallpaper assets automatically |
| `Makefile` | Theos rootless aggregate package | Corrected to package only Preferences; not build-verified |
| `NOTICE.md` | PosterForge technical-reference and rights notice | Present; no PosterForge source files are claimed to be copied |
| `Preferences/Info.plist` | Preferences bundle metadata | `CFBundleExecutable` added; build/load unverified |
| `Preferences/LBRootListController.h` | Declares PreferenceLoader controller and picker delegates | Present; compile unverified |
| `Preferences/LBRootListController.m` | Import, local list/removal and refresh UI | Local-only operations implemented in source; no previews, CAML generation or native install; compile/device testing pending |
| `Preferences/Makefile` | Theos Preferences bundle source/framework configuration | Present; compile unverified |
| `Preferences/Resources/Root.plist` | Settings rows/actions and explicit native-integration warning | Present; parser checked, behavior not device-tested |
| `README.md` | User/build/status documentation | Updated to state daemon is prototype-only and not packaged |
| `Shared/LBPaths.h` | Shared filesystem helper declarations | Present; Objective-C compile unverified |
| `Shared/LBPaths.m` | Fixed support/library/request/completion paths and directory setup | Local library helper implemented; future root-daemon use still requires stronger directory-handle/TOCTOU protection |
| `control` | Debian package metadata/dependencies | Rootless architecture corrected to `iphoneos-arm64`; generated package not examined because no build |
| `docs/ARCHITECTURE.md` | Current and future privilege-boundary design | Updated; no active privileged daemon in current package |
| `docs/BUILD_AND_DEVICE_VALIDATION.md` | Environment blockers and test history | Updated for 29-test suite and daemon not being packaged |
| `docs/POSTERFORGE_ANALYSIS.md` | PosterForge/Nugget findings and design choices | Contains source-based findings and unresolved device-specific questions |
| `docs/REVIEW_REPORT.md` | This file: findings, inventory, comparison and results | Updated during this review |
| `docs/TEST_PLAN.md` | Portable checks and target-device validation plan | Updated to separate present checks from future native/daemon tests |
| `docs/prototypes/com.iuyghi.lumenboardd.plist` | Unused launchd prototype | Documentation only; not in package layout |
| `docs/prototypes/postinst` | Unused maintainer-script prototype | Documentation only; not run by this package |
| `docs/prototypes/prerm` | Unused maintainer-script prototype | Documentation only; not run by this package |
| `layout/Library/PreferenceLoader/Preferences/LumenBoard.plist` | PreferenceLoader registration entry | Staged by layout in principle; unverified in a built package/device |
| `tests/test_tendies_inspect.py` | Synthetic archive tests and static packaging guards | 29 tests; these do not compile Objective-C or verify native wallpaper rendering |
| `tools/tendies_inspect.py` | Developer-only ZIP inspector/extractor | Portable source implemented and unit-tested; not called from the iOS pane; not validated against an actual `.tendies` fixture |

## PosterForge feature comparison

The public PosterForge README describes a Preferences pane, Photos selection, photo crop/zoom, optional blurred Home layer, video-to-looping-CAML conversion, descriptor-format `.tendies` import with randomized identifiers, native Collections gallery entries, swipe-to-delete management and a privileged rootless daemon. The current LumenBoard implementation is deliberately far behind those runtime features:

| PosterForge capability | Current LumenBoard implementation | Files | Difference / remaining work | Required test |
|---|---|---|---|---|
| PreferenceLoader UI | Root plist/controller source exists | `Preferences/Resources/Root.plist`, `Preferences/LBRootListController.*`, `layout/Library/PreferenceLoader/Preferences/LumenBoard.plist` | No compile/load evidence yet | Build bundle and open pane on device |
| Photo import | Stores original photo bytes and manifest locally | `Preferences/LBRootListController.m`, `Shared/LBPaths.*` | No crop/zoom editor, conversion, preview or PosterBoard output | JPEG/HEIC format, repeated import, cancel and removal on device |
| Video import | Stores original video bytes and manifest locally | Same UI files | No AVAsset frame extraction, FPS/duration cap, JPEG frame generation or looping animation | MOV/MP4 fixture and resource measurements on target |
| Generated descriptor root | Absent | No LumenBoard builder currently | Need verified container discovery and version-59/CollectionsPoster path, with stage/rollback | Compare a generated tree to a known-good iOS 16 descriptor |
| `Wallpaper.plist` and provider userInfo | Absent | None | Need verified fields, ids, names, screen-class choice and linked references | Parse plist trees and compare to fixture; then native picker |
| Identifier/role files and collision prevention | No generated descriptors; inspector does not rewrite any IDs | `tools/tendies_inspect.py` | ID randomization and all-reference rewrite absent | Fixture with known IDs, ensure no collisions and references consistent |
| CAML (`main.caml`, `assetManifest.caml`) | Absent | None | Need image and video layer-tree generation; cannot infer success from XML serialization | Structural diff against known-good CAML plus actual PosterBoard render |
| Animation indexes (`index.xml`, `.ca` assets) | Absent | None | Need binary plist index, asset package and correct animation timings | Validate all referenced assets and test rendering/performance |
| `.tendies` selection | UI stores an archive and marks it pending-validation | `Preferences/LBRootListController.m` | No on-device parser/extractor; does not invoke Python or install archive | Test representative real descriptor `.tendies`, plus corrupt/adversarial cases |
| Descriptor-format `.tendies` safety | Developer-only inspector validates ZIP structure, path names, file types, resource limits, plist parseability and CRC | `tools/tendies_inspect.py`, `tests/test_tendies_inspect.py` | Does not schema-validate every descriptor and has not seen a real archive | Run a known-good archive and compare reports/tree after extraction |
| Container-format restore | Inspector rejects any archive with a path component named `container` | Same tool/tests | Intentionally reject broad container restores on-device; current UI merely stores the file | Confirm representative container archive is refused by inspector |
| ID randomization during import | Absent | None | Must rewrite descriptor UUID, numeric wallpaper ID, Wallpaper.plist and provider userInfo atomically | Verify all references against fixture; inject partial failure and test rollback |
| Native gallery addition and persistence | Absent/disabled | `README.md`, `Preferences/Resources/Root.plist` | No PosterBoard writes, refresh or restart operation | On iPhone X: appear in Collections, select, lock/unlock, reboot/respring |
| Delete installed wallpaper | Only deletes local source folder after UUID/path checks | `Preferences/LBRootListController.m` | No PosterBoard descriptor removal or ownership registry | Confirm removal affects only IDs created by LumenBoard; stock wallpapers survive |
| Privilege separation | Daemon source prototype exists but is not compiled/staged/run | `Daemon/main.m`, `docs/prototypes/*`, `Makefile` | Deliberate least-privilege choice. A later daemon needs hardened IPC, ownership/size validation, queue bounds and race-resistant file access | Static security review and adversarial IPC tests before enabling |
| Rootless package | Makefiles declare rootless; `control` now specifies `iphoneos-arm64` | `Makefile`, `Preferences/Makefile`, `control` | No current SDK/Theos build; package contents not examined | `make clean package FINALPACKAGE=1`, then inspect DEB staging and contents |

## Test results

The original 18 tests were re-run against the baseline before changes and passed. Review showed that the prior malformed-plist test asserted only an empty `parseable_plists` list even though the overall archive was accepted. The validator and regression test were corrected; path-alias and packaging-contract tests were added. The post-change suite passed 29 tests (25 archive tests plus 4 static packaging guards), including a CRC-corruption regression case.

Synthetic fixtures only. No real `.tendies` file was provided or tested. Therefore descriptor-schema and PosterBoard compatibility remain unverified.

### Baseline 18-test inventory (from the original commit)

The original commit defined these 18 test methods; all passed when run against the original baseline before corrections:

1. `test_accepts_descriptor_archive_and_reports_parseable_plist`
2. `test_accepts_singular_descriptor_root`
3. `test_rejects_container_format`
4. `test_rejects_parent_traversal`
5. `test_rejects_absolute_paths`
6. `test_rejects_windows_path_separator`
7. `test_rejects_symlink_entries`
8. `test_rejects_special_file_entries`
9. `test_rejects_duplicate_casefolded_paths`
10. `test_rejects_archive_without_descriptor_directory`
11. `test_rejects_size_limit`
12. `test_rejects_bad_zip`
13. `test_extracts_verified_archive_to_new_directory`
14. `test_refuses_nonempty_extraction_destination`
15. `test_rejects_non_tendies_extension`
16. `test_refuses_symlink_extraction_destination`
17. `test_refuses_empty_archive_file`
18. `test_rejects_malformed_plist_is_reported_not_mistaken_for_valid_plist`

### Revised 29-test inventory (after corrections)

The current suite consists of 25 synthetic archive tests and 4 static package-contract tests. The additional/updated archive tests cover CRC corruption, absence of plist entries, generic plist without `Wallpaper.plist`, missing required wallpaper fields, Unicode normalization aliases, file/directory collisions, and oversized plist entries. The four static guards check rootless Debian architecture, Preferences executable metadata, the daemon being excluded from the package, and maintainer scripts remaining outside package hooks. Exact test names are in `tests/test_tendies_inspect.py`; the current complete run passed all 29.

## Build and device limitations

The environment has Python 3.13.5, Git and `make`, but `THEOS` is unset, `xcrun` is absent, and no Apple SDK/Xcode or attached iPhone X is available. The build command cannot complete here. No DEB was built, installed or signed; no tests exercised iOS APIs, PreferenceLoader at runtime, RootHide, PosterBoard discovery, gallery appearance, selection or persistence.

Dopamine/RootHide compatibility cannot be inferred solely from a Theos `arm64`/`arm64e` target. The exact jailbreak variant/build, rootless prefix behavior, PreferenceLoader, root permissions and actual `PRBPosterExtensionDataStore/59` tree must be checked on the stated device. PosterForge's README documents iOS 16.0–16.7.x and compatible rootless configurations, but that upstream statement is not a guarantee for this installation.

## Publication gate

Do not create `iuyghi/LumenBoard-Development` or push yet. First build and inspect the unprivileged bundle on an appropriate environment, test local imports on the target, acquire a lawful known-good iOS 16 descriptor fixture, implement/validate the descriptor builder and parser, audit a future privileged IPC design, and prove native gallery appearance/selection/persistence plus safe removal. Repository creation remains explicitly out of scope for this review.


## Later engine phase

This report records the 29-test baseline review. The later static-image engine phase adds `tools/static_wallpaper_builder.py`, `tests/test_static_wallpaper_builder.py`, `docs/STATIC_IMAGE_ENGINE.md`, and `docs/ENGINE_PHASE_REPORT.md`. The combined current suite passes 45 tests; see `ENGINE_PHASE_REPORT.md` for current scope and limitations.
