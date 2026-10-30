#!/usr/bin/env bash
set -Eeuo pipefail

LOG=/tmp/LumenBoard-P38-transfer.log
REPORT=/tmp/LumenBoard-P38-transfer-report.txt
exec >"$LOG" 2>&1

SOURCE_URL="https://github.com/iuyghi/LumenBoard.git"
DEST_URL="https://github.com/ouuhh7/LumenBoard.git"
EXPECTED_MAIN="c6392551bebc5803e811449de35cd56374657b1e"
EXPECTED_WORK="4f474e7b3f1e4f11a15f6679e688e6652f3fba49"
EXPECTED_RECOVERY="4b9a5e1f0473e6918283bc6afa065e3f25b4e66a"
ORIGINAL="5c9bfd516d93243d3bd7625839b39e0e68f6c9fb"
WORKDIR="/tmp/LumenBoard-P38"
MIRROR="$WORKDIR/source-mirror.git"
BUNDLE="$WORKDIR/source-all.bundle"
INDEPENDENT="$WORKDIR/independent-clone.git"

mkdir -p "$WORKDIR"
cat >"$REPORT" <<'EOF'
LumenBoard P38 transfer report
EOF

echo "=== GitHub CLI authentication ==="
if ! gh auth status -h github.com; then
  echo "STOP: gh auth status failed; no push attempted."
  echo "RESULT=BLOCKED_AUTH"
  exit 20
fi
gh auth setup-git

if ! gh api repos/ouuhh7/LumenBoard >/dev/null; then
  echo "STOP: authenticated user cannot read destination via gh api."
  echo "RESULT=BLOCKED_DESTINATION_ACCESS"
  exit 21
fi

echo "=== Source mirror ==="
git clone --mirror "$SOURCE_URL" "$MIRROR"
cd "$MIRROR"

test "$(git rev-parse refs/heads/main)" = "$EXPECTED_MAIN"
test "$(git rev-parse refs/heads/work/tendies-native-validation)" = "$EXPECTED_WORK"
test "$(git rev-parse refs/heads/recovery/original-bundle-2026-10-30)" = "$EXPECTED_RECOVERY"
git cat-file -e "${ORIGINAL}^{commit}"
git merge-base --is-ancestor "$ORIGINAL" refs/heads/main
git merge-base --is-ancestor "$ORIGINAL" refs/heads/work/tendies-native-validation
git fsck --full --strict

echo "=== LFS and submodules ==="
git lfs install --local
git lfs fetch --all origin
git lfs ls-files --all > "$WORKDIR/lfs-manifest.txt"
LFS_COUNT="$(wc -l < "$WORKDIR/lfs-manifest.txt" | tr -d ' ')"
GITLINK_COUNT="$(git ls-tree -r refs/heads/main refs/heads/work/tendies-native-validation refs/heads/recovery/original-bundle-2026-10-30 | awk '$1=="160000"{n++} END{print n+0}')"
if [ "$LFS_COUNT" -ne 0 ]; then
  echo "LFS_COUNT=$LFS_COUNT"
fi
if [ "$GITLINK_COUNT" -ne 0 ]; then
  echo "GITLINK_COUNT=$GITLINK_COUNT"
fi

echo "=== Bundle and independent clone ==="
git bundle create "$BUNDLE" --all
git bundle verify "$BUNDLE"
git clone --mirror "$BUNDLE" "$INDEPENDENT"
git --git-dir="$INDEPENDENT" fsck --full --strict
test "$(git --git-dir="$INDEPENDENT" rev-parse refs/heads/main)" = "$EXPECTED_MAIN"
test "$(git --git-dir="$INDEPENDENT" rev-parse refs/heads/work/tendies-native-validation)" = "$EXPECTED_WORK"
test "$(git --git-dir="$INDEPENDENT" rev-parse refs/heads/recovery/original-bundle-2026-10-30)" = "$EXPECTED_RECOVERY"
git --git-dir="$INDEPENDENT" merge-base --is-ancestor "$ORIGINAL" refs/heads/main
git --git-dir="$INDEPENDENT" merge-base --is-ancestor "$ORIGINAL" refs/heads/work/tendies-native-validation

echo "=== Destination preflight ==="
git remote add destination "$DEST_URL"
git ls-remote destination

for pair in \
  "main $EXPECTED_MAIN" \
  "work/tendies-native-validation $EXPECTED_WORK" \
  "recovery/original-bundle-2026-10-30 $EXPECTED_RECOVERY"; do
  branch="${pair%% *}"
  expected="${pair#* }"
  actual="$(git ls-remote destination "refs/heads/$branch" | awk '{print $1}')"
  if [ -n "$actual" ] && [ "$actual" != "$expected" ]; then
    echo "STOP: destination ref $branch already exists at unexpected SHA $actual"
    echo "RESULT=BLOCKED_UNEXPECTED_REMOTE_REF"
    exit 22
  fi
done

echo "=== Explicit non-force branch pushes ==="
PUSH_ERRORS=0
for pair in \
  "main $EXPECTED_MAIN" \
  "work/tendies-native-validation $EXPECTED_WORK" \
  "recovery/original-bundle-2026-10-30 $EXPECTED_RECOVERY"; do
  branch="${pair%% *}"
  expected="${pair#* }"
  actual="$(git ls-remote destination "refs/heads/$branch" | awk '{print $1}')"
  if [ "$actual" = "$expected" ]; then
    echo "ALREADY_EXACT $branch $expected"
    continue
  fi
  if [ -n "$actual" ]; then
    echo "PUSH_REFUSED $branch unexpected-existing-sha=$actual"
    PUSH_ERRORS=1
    continue
  fi
  if git push destination "refs/heads/$branch:refs/heads/$branch"; then
    echo "PUSH_OK $branch $expected"
  else
    echo "PUSH_FAILED $branch"
    PUSH_ERRORS=1
  fi
done

echo "=== Git LFS upload ==="
if ! git lfs push --all destination; then
  echo "LFS_PUSH_FAILED"
  PUSH_ERRORS=1
fi

echo "=== Remote verification ==="
git fetch destination \
  refs/heads/main:refs/remotes/destination/main \
  refs/heads/work/tendies-native-validation:refs/remotes/destination/work/tendies-native-validation \
  refs/heads/recovery/original-bundle-2026-10-30:refs/remotes/destination/recovery/original-bundle-2026-10-30

test "$(git rev-parse refs/remotes/destination/main)" = "$EXPECTED_MAIN"
test "$(git rev-parse refs/remotes/destination/work/tendies-native-validation)" = "$EXPECTED_WORK"
test "$(git rev-parse refs/remotes/destination/recovery/original-bundle-2026-10-30)" = "$EXPECTED_RECOVERY"
git merge-base --is-ancestor "$ORIGINAL" refs/remotes/destination/main
git merge-base --is-ancestor "$ORIGINAL" refs/remotes/destination/work/tendies-native-validation
git fsck --full --strict

{
  echo "RESULT=$([ "$PUSH_ERRORS" -eq 0 ] && echo SUCCESS || echo PARTIAL_OR_FAILED)"
  echo "main=$(git rev-parse refs/remotes/destination/main)"
  echo "work/tendies-native-validation=$(git rev-parse refs/remotes/destination/work/tendies-native-validation)"
  echo "recovery/original-bundle-2026-10-30=$(git rev-parse refs/remotes/destination/recovery/original-bundle-2026-10-30)"
  echo "original_commit=$ORIGINAL"
  echo "original_commit_reachable_from_main_and_work=yes"
  echo "source_fsck=passed"
  echo "bundle_verify=passed"
  echo "independent_clone_fsck=passed"
  echo "git_lfs_objects=$LFS_COUNT"
  echo "gitlinks_or_submodules=$GITLINK_COUNT"
  echo "bundle_sha256=$(sha256sum "$BUNDLE" | awk '{print $1}')"
  echo "mirror_sha256=$(tar -czf - -C "$WORKDIR" source-mirror.git | sha256sum | awk '{print $1}')"
} | tee "$REPORT"

# Publish the execution report only to the temporary bootstrap branch.
CONTENT="$(base64 -w0 "$REPORT")"
if gh api --method PUT repos/ouuhh7/LumenBoard/contents/P38-TRANSFER-REPORT.txt \
  -f message="chore: record P38 transfer report" \
  -f content="$CONTENT" \
  -f branch="p38-transfer-bootstrap" >/dev/null; then
  echo "REPORT_COMMITTED_TO_TEMP_BRANCH=yes"
else
  echo "REPORT_COMMITTED_TO_TEMP_BRANCH=no"
fi

if [ "$PUSH_ERRORS" -ne 0 ]; then
  echo "RESULT=PARTIAL_OR_FAILED"
  exit 30
fi
echo "RESULT=SUCCESS"
