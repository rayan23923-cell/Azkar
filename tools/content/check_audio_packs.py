#!/usr/bin/env python3
"""Integrity check of every bundled audio pack (Phase 3H).

For each `*_audio.json` in the bundled content directory it checks the manifest and the files
beside it: plain file names, matching extension, size and SHA-256, PRODUCTION usage only
(test assets never ship), one recording per content id, and no audio file that the manifest
does not list. It also prints whether the pack is ready for release (rights decided, status
READY); that part is a report, not a failure, because rights are a pre-release gate.

usage: check_audio_packs.py [content_dir]
"""
import hashlib
import json
import pathlib
import re
import sys

CONTENT = pathlib.Path(__file__).resolve().parents[2] / "Packages/IslamicCore/Sources/IslamicCore/Resources/Content"
AUDIO_DIRS = {"hisn_audio.json": "HisnAudio", "content_audio.json": "ContentAudio"}
FORMATS = {"m4a", "mp3", "wav"}
PLAIN = re.compile(r"^[A-Za-z0-9_.-]{1,128}$")


def check(manifest_path: pathlib.Path) -> list[str]:
    errors: list[str] = []
    data = json.loads(manifest_path.read_text(encoding="utf-8"))
    if data.get("formatVersion") != 1:
        errors.append("formatVersion must be 1")
    if not data.get("packStatus"):
        errors.append("packStatus is empty")
    directory = manifest_path.parent / AUDIO_DIRS.get(manifest_path.name, manifest_path.stem)
    ids, owners, listed = set(), set(), set()
    blockers = []
    for asset in data.get("assets", []):
        at = f"{manifest_path.name} {asset.get('id')}"
        owner = asset.get("itemId") or asset.get("ref")
        name = asset.get("resourceName", "")
        if asset.get("id") in ids:
            errors.append(f"{at}: duplicate id")
        ids.add(asset.get("id"))
        if owner in owners:
            errors.append(f"{at}: {owner} already has a recording")
        owners.add(owner)
        if asset.get("usage") != "PRODUCTION":
            errors.append(f"{at}: only PRODUCTION assets may be bundled (found {asset.get('usage')})")
        if not PLAIN.match(name) or name.startswith("."):
            errors.append(f"{at}: resource name is not a plain file name")
            continue
        if asset.get("format") not in FORMATS or not name.lower().endswith("." + asset.get("format", "")):
            errors.append(f"{at}: extension does not match format")
        path = directory / name
        listed.add(name)
        if not path.is_file():
            errors.append(f"{at}: missing file {path.relative_to(CONTENT)}")
            continue
        blob = path.read_bytes()
        if len(blob) != asset.get("byteCount"):
            errors.append(f"{at}: byteCount {asset.get('byteCount')} != {len(blob)}")
        if hashlib.sha256(blob).hexdigest() != asset.get("sha256"):
            errors.append(f"{at}: checksum mismatch")
        rights = (asset.get("source") or {}).get("rightsStatus")
        if rights == "PENDING_PRE_RELEASE_REVIEW":
            blockers.append(f"{asset.get('id')} rights pending")
    if directory.is_dir():
        for extra in sorted(p.name for p in directory.iterdir() if p.is_file() and p.name not in listed):
            errors.append(f"{manifest_path.name}: unlisted file {extra} in {directory.name}")
    status = data.get("packStatus")
    if status != "READY":
        blockers.insert(0, f"packStatus {status}")
    if not data.get("assets"):
        blockers.append("no recordings")
    print(f"{manifest_path.name}: {len(data.get('assets', []))} assets, status {status}; "
          f"release: {'READY' if not blockers else 'BLOCKED (' + '; '.join(blockers) + ')'}")
    return errors


def main() -> int:
    content = pathlib.Path(sys.argv[1]) if len(sys.argv) > 1 else CONTENT
    errors = []
    manifests = sorted(content.glob("*_audio.json"))
    if not manifests:
        print("no audio manifests found")
        return 1
    for manifest in manifests:
        errors += check(manifest)
    for error in errors:
        print("ERROR", error)
    return 1 if errors else 0


if __name__ == "__main__":
    sys.exit(main())
