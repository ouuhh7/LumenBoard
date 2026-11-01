#!/usr/bin/env python3
"""Generate an offline iOS 16 PosterForge-shaped static-image descriptor candidate.

The generated schema is derived from public MIT-licensed PosterForge source, not
validated against a known-good iOS 16.7.x fixture. Output is never installed and
this module never writes to an Apple app container.
"""
from __future__ import annotations

import argparse
import hashlib
import json
import os
import plistlib
import re
import secrets
import shutil
import sys
import tempfile
import uuid
from datetime import datetime, timezone
from pathlib import Path
from typing import Any

sys.path.insert(0, str(Path(__file__).resolve().parent))
from static_wallpaper_builder import BuildError, _image_info  # noqa: E402
from descriptor_consistency import validate_descriptors_root  # noqa: E402

MAX_SOURCE_BYTES = 100 * 1024 * 1024
NAME_RE = re.compile(r"[^A-Za-z0-9 _.-]+")
CAM_NS = "http://www.apple.com/CoreAnimation/1.0"


class GeneratorError(ValueError):
    """Invalid input or unsafe output target."""


def _sha256(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as stream:
        for chunk in iter(lambda: stream.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def _title(raw: str) -> str:
    value = " ".join(NAME_RE.sub("", raw).split()).strip(" .-")
    if not value:
        raise GeneratorError("title must contain at least one supported letter or number")
    if len(value) > 80:
        raise GeneratorError("title must be 80 characters or fewer")
    return value


def _load_existing_ids(root: Path) -> tuple[set[str], set[int]]:
    descriptor_ids: set[str] = set()
    wallpaper_ids: set[int] = set()
    if not root.exists():
        return descriptor_ids, wallpaper_ids
    if root.is_symlink() or not root.is_dir():
        raise GeneratorError("output root must be a real directory, not a symlink")
    for child in root.iterdir():
        if child.is_symlink():
            raise GeneratorError(f"output root contains symlink: {child.name}")
        if not child.is_dir():
            continue
        if re.fullmatch(r"[0-9A-Fa-f-]{36}", child.name):
            descriptor_ids.add(child.name.upper())
        id_file = child / "com.apple.posterkit.provider.descriptor.identifier"
        if id_file.is_file() and not id_file.is_symlink():
            try:
                value = id_file.read_text(encoding="utf-8").strip()
                if value.isdecimal():
                    wallpaper_ids.add(int(value))
            except OSError as exc:
                raise GeneratorError(f"cannot inspect existing descriptor {child.name}: {exc}") from exc
        for wp in child.glob("versions/1/contents/*.wallpaper/Wallpaper.plist"):
            if wp.is_symlink():
                raise GeneratorError(f"existing wallpaper plist is a symlink: {wp}")
            try:
                data = plistlib.loads(wp.read_bytes())
            except (OSError, plistlib.InvalidFileException, ValueError) as exc:
                raise GeneratorError(f"cannot inspect existing Wallpaper.plist {wp}: {exc}") from exc
            if isinstance(data, dict):
                value = data.get("identifier")
                if isinstance(value, int) and not isinstance(value, bool):
                    wallpaper_ids.add(value)
    return descriptor_ids, wallpaper_ids


def _new_ids(existing_uuids: set[str], existing_numeric: set[int]) -> tuple[str, int]:
    for _ in range(1000):
        descriptor_uuid = str(uuid.uuid4()).upper()
        numeric_id = 10_000 + secrets.randbelow(89_999)
        if descriptor_uuid not in existing_uuids and numeric_id not in existing_numeric:
            return descriptor_uuid, numeric_id
    raise GeneratorError("could not allocate collision-free descriptor identifiers")


def _keyed_provider_info() -> bytes:
    """Build the minimal NSKeyedArchiver object graph observed in PosterForge."""
    # NSDictionary(root) -> NSDate(kConfigurationLastUseDateKey), using the
    # standard NSKeyedArchiver plist representation for NSDictionary and NSDate.
    now = datetime.now(timezone.utc).timestamp() - 978307200.0  # seconds since 2001-01-01
    archive = {
        "$archiver": "NSKeyedArchiver",
        "$version": 100000,
        "$objects": [
            "$null",
            {"$class": plistlib.UID(2), "kConfigurationLastUseDateKey": plistlib.UID(3)},
            {"$classname": "NSDictionary", "$classes": ["NSDictionary", "NSObject"]},
            {"$class": plistlib.UID(4), "NS.time": now},
            {"$classname": "NSDate", "$classes": ["NSDate", "NSObject"]},
        ],
        "$top": {"root": plistlib.UID(1)},
    }
    return plistlib.dumps(archive, fmt=plistlib.FMT_BINARY, sort_keys=False)


def _write_plist(path: Path, value: Any) -> None:
    path.write_bytes(plistlib.dumps(value, fmt=plistlib.FMT_BINARY, sort_keys=False))


def _write_layer(ca_dir: Path, *, width: int, height: int, image: bool) -> None:
    ca_dir.mkdir(parents=True, exist_ok=False)
    (ca_dir / "assets").mkdir()
    if image:
        # The one-image CAML shape and attributes are based on PosterForge's
        # public buildAnimationAt:source:kind:maxFPS:blurred:error: implementation.
        caml = (
            '<?xml version="1.0" encoding="UTF-8"?>'
            f'<caml xmlns="{CAM_NS}">'
            f'<CALayer bounds="0 0 {width} {height}" contentsFormat="RGBA8" '
            f'name="_BACKGROUND" position="{width / 2:g} {height / 2:g}">'
            '<sublayers><CALayer '
            f'bounds="0 0 {width} {height}" contentsFormat="RGBA8" '
            f'position="{width / 2:g} {height / 2:g}">'
            '<contents type="CGImage" src="assets/0.jpg"/>'
            '</CALayer></sublayers>'
            '<states><LKState name="Locked"><elements/></LKState>'
            '<LKState name="Unlock"><elements/></LKState>'
            '<LKState name="Sleep"><elements/></LKState></states>'
            '</CALayer></caml>'
        )
        index = {
            "assetManifest": "assetManifest.caml",
            "documentHeight": height,
            "documentResizesToView": True,
            "documentWidth": width,
            "geometryFlipped": False,
            "rootDocument": "main.caml",
            "scalesToFitInPlayer": True,
            "unitsInPixelsInPlayer": True,
        }
    else:
        caml = (
            '<?xml version="1.0" encoding="UTF-8"?>'
            f'<caml xmlns="{CAM_NS}">'
            '<CALayer bounds="0 0 1 1" hidden="0" name="_FLOATING" '
            'position="0.5 0.5"><sublayers/></CALayer></caml>'
        )
        index = {
            "assetManifest": "assetManifest.caml",
            "documentHeight": 1,
            "documentResizesToView": True,
            "documentWidth": 1,
            "geometryFlipped": False,
            "rootDocument": "main.caml",
            "scalesToFitInPlayer": True,
            "unitsInPixelsInPlayer": True,
        }
    (ca_dir / "main.caml").write_text(caml, encoding="utf-8")
    # PosterForge's observed writer references assetManifest.caml in index.xml
    # but does not emit it. LumenBoard emits an empty CAML root so the generated
    # tree is internally closed; whether this is renderer-accepted is unverified.
    (ca_dir / "assetManifest.caml").write_text(
        f'<?xml version="1.0" encoding="UTF-8"?><caml xmlns="{CAM_NS}"/>',
        encoding="utf-8",
    )
    _write_plist(ca_dir / "index.xml", index)


def generate_static_descriptor(source_image: Path, output_root: Path, title: str) -> dict[str, Any]:
    """Create a full descriptor candidate under output_root, atomically.

    Only JPEG inputs are accepted to match the observed PosterForge static-image
    path, which writes assets/0.jpg. The output is a local candidate, never installed.
    """
    source = source_image.absolute()
    root = output_root.absolute()
    if source.is_symlink() or not source.is_file():
        raise GeneratorError("source image must be an existing regular, non-symlink file")
    if source.stat().st_size > MAX_SOURCE_BYTES:
        raise GeneratorError(f"source image exceeds {MAX_SOURCE_BYTES} bytes")
    if source.suffix.lower() not in {".jpg", ".jpeg"}:
        raise GeneratorError("source image must be JPEG (.jpg or .jpeg) to match the observed PosterForge writer")
    try:
        info = _image_info(source)
    except BuildError as exc:
        raise GeneratorError(str(exc)) from exc
    if info["format"] != "jpeg":
        raise GeneratorError("source image bytes do not match JPEG format")
    raw = source.read_bytes()
    if not raw.startswith(b"\xff\xd8\xff") or not raw.endswith(b"\xff\xd9"):
        raise GeneratorError("JPEG must contain SOI/header and EOI markers")
    safe_title = _title(title)
    root.mkdir(parents=True, exist_ok=True)
    if root.is_symlink() or not root.is_dir():
        raise GeneratorError("output root must be a real directory")
    existing_uuids, existing_numeric = _load_existing_ids(root)
    descriptor_uuid, wallpaper_id = _new_ids(existing_uuids, existing_numeric)
    wallpaper_name = f"{descriptor_uuid}.Custom.wallpaper"
    stage = Path(tempfile.mkdtemp(prefix=".lumenboard-stage-", dir=root))
    final = root / descriptor_uuid
    try:
        contents = stage / "versions" / "1" / "contents"
        wallpaper = contents / wallpaper_name
        background = wallpaper / "PF_Background.ca"
        floating = wallpaper / "PF_Floating.ca"
        _write_layer(background, width=info["width"], height=info["height"], image=True)
        (background / "assets" / "0.jpg").write_bytes(raw)
        _write_layer(floating, width=1, height=1, image=False)

        (stage / "com.apple.posterkit.provider.descriptor.identifier").write_text(str(wallpaper_id), encoding="utf-8")
        (stage / "com.apple.posterkit.role.identifier").write_text("PRPosterRoleLockScreen", encoding="utf-8")
        (stage / "providerInfo.plist").write_bytes(_keyed_provider_info())
        _write_plist(contents / "com.apple.posterkit.provider.contents.userInfo", {
            "posterEnvironmentOverrides": b"{}",
            "wallpaperRepresentingFileName": wallpaper_name,
            "wallpaperRepresentingIdentifier": str(wallpaper_id),
        })
        _write_plist(wallpaper / "Wallpaper.plist", {
            "appearanceAware": True,
            "assets": {"lockAndHome": {"default": {
                "backgroundAnimationFileName": "PF_Background.ca",
                "floatingAnimationFileNameKey": "PF_Floating.ca",
                "identifier": wallpaper_id,
                "name": safe_title,
                "type": "LayeredAnimation",
            }}},
            "contentVersion": 2.01,
            "family": "Marble",
            "identifier": wallpaper_id,
            "logicalScreenClass": "375w-812h@3x~iphone",
            "name": safe_title,
            "preferredProminentColor": {"dark": "#000000", "default": "#FFFFFF"},
            "version": 1,
        })

        # Validate before publication against the project's internal consistency
        # profile. It is explicitly not an Apple renderer compatibility test.
        report = _validate_staged(stage)
        if report["status"] != "passes-structural-checks":
            raise GeneratorError("generated descriptor failed structural validation: " + json.dumps(report, ensure_ascii=False))
        if final.exists() or final.is_symlink():
            raise GeneratorError("destination descriptor path already exists; refusing overwrite")
        os.replace(stage, final)
        return {
            "status": "generated-structurally-validated-candidate-not-device-verified",
            "descriptor_uuid": descriptor_uuid,
            "wallpaper_identifier": wallpaper_id,
            "output_directory": str(final),
            "title": safe_title,
            "image": {**info, "sha256": _sha256(source)},
            "validation": report,
            "compatibility": {
                "structural_validation": "passed",
                "comparison_with_real_ios16_fixture": "not-run-no-license-cleared-binary-fixture-available-in-workspace",
                "native_gallery_on_iphone_x_ios_16_7_16": "not-tested",
            },
        }
    except Exception:
        if stage.exists():
            shutil.rmtree(stage, ignore_errors=True)
        raise


def _validate_staged(stage: Path) -> dict[str, Any]:
    wrapper = Path(tempfile.mkdtemp(prefix=".lumenboard-validation-", dir=stage.parent))
    try:
        shutil.copytree(stage, wrapper / stage.name)
        return validate_descriptors_root(wrapper)
    finally:
        shutil.rmtree(wrapper, ignore_errors=True)


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("source_image", type=Path, help="JPEG image to use as static poster")
    parser.add_argument("output_root", type=Path, help="local output root for generated descriptor; no system writes")
    parser.add_argument("--title", default="LumenBoard Static", help="display name (max 80 supported characters)")
    args = parser.parse_args(argv)
    try:
        report = generate_static_descriptor(args.source_image, args.output_root, args.title)
    except (GeneratorError, OSError, ValueError) as exc:
        print(json.dumps({"status": "failed", "error": str(exc)}, ensure_ascii=False, indent=2), file=sys.stderr)
        return 2
    print(json.dumps(report, ensure_ascii=False, indent=2))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
