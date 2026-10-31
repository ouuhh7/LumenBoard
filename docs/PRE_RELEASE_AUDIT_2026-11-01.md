# LumenBoard pre-release audit — 2026-11-01

## Scope

This audit inspected the public repository after collaborator write access was enabled. It is a source/repository review, not an iPhone validation. A separate pull request fixes one confirmed release-blocking check.

## Repository state inspected

- Repository: `ouuhh7/LumenBoard`
- Default branch: `main`
- Active implementation branch: `fix/rootless-deb-installation`
- Inspected implementation HEAD: `3a0323f7ac352165ae4697fb350d309c6c18c63b`
- Package control metadata: `0.1.0-14`, architecture `iphoneos-arm64`
- The branch Makefile targets arm64, rootless packaging, iOS SDK 16.5 with iOS 16.0 deployment.
- Preferences `Info.plist` currently reports `CFBundleVersion = 9`.

## Findings and changes

1. **Build verifier version mismatch — fixed on a separate PR branch.** `control` declares `0.1.0-14`, while `tools/build_and_verify_deb.sh` expected `0.1.0-9`. The guard was updated to `0.1.0-14` in PR #1, based on this branch. The PR is open and not merged.
2. **Version metadata still deserves reconciliation.** Preferences `CFBundleVersion` remains `9`; it is distinct from the Debian package version but should be consciously synchronized or documented before release.
3. **Stale CI import workflow.** `.github/workflows/bootstrap-and-build.yml` runs on pushes to `main`, imports historical source history, and checks `0.1.0-13`. It is not the active branch's package workflow and should not be treated as 0.1.0-14 release evidence.
4. **Previous CI failures did not execute jobs.** Run 123 at `3a0323f7ac352165ae4697fb350d309c6c18c63b` has three failed jobs, each with `runner_id=0` and an empty step list. This indicates runner dispatch/provisioning failure, not a source compiler/test diagnostic; it provides no successful build evidence.
5. **No fresh verified artifact.** No new DEB was built or downloaded/validated in this audit. The supplied 0.1.0-13 interim package is not evidence for current source/version 0.1.0-14.
6. **No device validation.** Gallery visibility, preview, selection, Lock Screen and Home Screen rendering require physical-device verification, as the branch README states.

## Positive findings

- The active branch contains a native daemon and Preferences subproject in its aggregate Makefile.
- Package metadata specifies rootless architecture `iphoneos-arm64` and firmware 16.x.
- The active native-validator workflow covers portable tests, macOS native XCTest, package construction and package inspection.
- The workflow distinguishes archive validation from native device runtime validation.

## Release decision

**Do not publish a release DEB yet.** Merge PR #1 only after review, run the active native-validator workflow successfully on the resulting source, obtain a fresh 0.1.0-14 package artifact, and independently verify its contents and SHA-256. Then perform an iPhone X / iOS 16.7.16 / Dopamine rootless installation and PosterBoard validation. No claim of that device validation is made here.

## Changes made by this audit

- Added this report to `fix/rootless-deb-installation`.
- Opened PR #1 to correct the stale package-version assertion.
- No implementation files on the original branch, default branch, or release tags were changed.
- No DEB was built and no GitHub Release was created.
