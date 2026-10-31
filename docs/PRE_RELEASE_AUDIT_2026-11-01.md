# LumenBoard pre-release audit — 2026-11-01

## Scope

This audit inspected the public repository branch `fix/rootless-deb-installation` after collaborator write access was enabled. It is a source/repository review only. No source code, build scripts, package metadata, branch refs, default branch, or release tags were changed by this audit.

## Repository state inspected

- Repository: `ouuhh7/LumenBoard`
- Default branch: `main`
- Active implementation branch: `fix/rootless-deb-installation`
- Inspected branch HEAD: `3a0323f7ac352165ae4697fb350d309c6c18c63b`
- Package control metadata: `0.1.0-14`, architecture `iphoneos-arm64`
- The branch Makefile targets arm64, rootless packaging, iOS SDK 16.5 with iOS 16.0 deployment.
- The Preferences bundle Info.plist currently reports CFBundleVersion 9.

## Blocking findings

1. **Build verifier version mismatch.** `control` declares package version `0.1.0-14`, but `tools/build_and_verify_deb.sh` still hard-codes expected version `0.1.0-9`. This will reject a correct 0.1.0-14 build.
2. **Workflow version mismatch.** `.github/workflows/native-validator.yml` verifies version `0.1.0-14`; the build helper's stale version check contradicts it.
3. **Stale CI import workflow.** `.github/workflows/bootstrap-and-build.yml` is configured for pushes to `main`, reconstructs/imports a historical bundle, and verifies version `0.1.0-13`. It is not the active branch's package workflow and should not be used as release evidence for 0.1.0-14.
4. **Previous CI failures did not execute jobs.** Run 123 (head `3a0323f7ac352165ae4697fb350d309c6c18c63b`) has three failed jobs, each with `runner_id=0` and an empty step list. This is runner provisioning/dispatch failure evidence, not a source compiler/test failure, but it also provides no successful build evidence.
5. **No device validation.** The branch README itself says gallery visibility, preview, selection, Lock Screen and Home Screen rendering require physical-device verification. These checks are not established by the repository inspection.
6. **No verified fresh artifact in this audit.** No new DEB was built or downloaded/validated during this inspection. The prior intermediate version 0.1.0-13 package is not evidence for current source/version 0.1.0-14.

## Positive findings

- The active branch carries a native daemon and Preferences subproject in its aggregate Makefile.
- The package control metadata uses the rootless architecture `iphoneos-arm64` and constrains firmware to iOS 16.x.
- The native-validator workflow contains portable tests, macOS native XCTest, rootless package construction, and extensive package inspection steps.
- Workflow checks distinguish package-level validation from actual device runtime validation.

## Release decision

**Do not publish a release DEB yet.** The stale package-version guard must be reconciled with `control`, then the active workflow must run successfully and produce a fresh package artifact. The built artifact must be independently checked for metadata, rootless paths, Mach-O architecture, launchd scripts and daemon/preferences bundle contents. Device installation and native PosterBoard validation remain a separate, explicitly unverified gate.

## Changes made

Only this audit report was added. No implementation code or package build configuration was changed; no package was built; no GitHub Release was created.
