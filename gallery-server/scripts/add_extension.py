#!/usr/bin/env python3
"""
Add a VSIX file to the gallery server's storage directly (no running server needed).

Usage:
    python add_extension.py <vsix-file> [--data-dir <path>]

This is useful for populating the gallery before starting the server,
or for batch-importing existing VSIX files.
"""

import argparse
import io
import json
import shutil
import sys
import zipfile
from datetime import datetime, timezone
from pathlib import Path

# Import metadata extraction from server.py
sys.path.insert(0, str(Path(__file__).resolve().parent.parent))
from server import (
    _extract_vsix_metadata,
    _build_asset_files,
    _build_properties,
)


def add_vsix(vsix_path: Path, data_dir: Path) -> None:
    """Add a single VSIX to the gallery."""
    vsix_bytes = vsix_path.read_bytes()
    meta = _extract_vsix_metadata(vsix_bytes)

    publisher = meta["publisher"]
    name = meta["name"]
    version = meta["version"]
    extension_id = meta["extensionId"]

    ext_dir = data_dir / "extensions" / publisher / name / version
    ext_dir.mkdir(parents=True, exist_ok=True)

    # Save VSIX
    (ext_dir / "extension.vsix").write_bytes(vsix_bytes)

    # Extract assets
    try:
        zf = zipfile.ZipFile(io.BytesIO(vsix_bytes))
        for asset_name, target in [
            ("extension/README.md", "README.md"),
            ("extension/CHANGELOG.md", "CHANGELOG.md"),
        ]:
            if asset_name in zf.namelist():
                (ext_dir / target).write_bytes(zf.read(asset_name))
        icon = meta.get("icon", "")
        if icon and f"extension/{icon}" in zf.namelist():
            (ext_dir / "icon.png").write_bytes(zf.read(f"extension/{icon}"))
    except Exception:
        pass

    # Update gallery.json
    gallery_path = data_dir / "gallery.json"
    if gallery_path.exists():
        gallery = json.loads(gallery_path.read_text(encoding="utf-8"))
    else:
        gallery = {"extensions": []}

    now = datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")

    version_entry = {
        "version": version,
        "lastUpdated": now,
        "assetUri": f"/files/{publisher}/{name}/{version}",
        "fallbackAssetUri": f"/files/{publisher}/{name}/{version}",
        "files": _build_asset_files(version),
        "properties": _build_properties(meta),
    }

    ext_entry = None
    for e in gallery["extensions"]:
        if e["extensionId"] == extension_id:
            ext_entry = e
            break

    if ext_entry is None:
        ext_entry = {
            "extensionId": extension_id,
            "publisher": publisher,
            "name": name,
            "displayName": meta["displayName"],
            "description": meta["description"],
            "categories": meta.get("categories", ["Other"]),
            "tags": meta.get("tags", []),
            "versions": [version_entry],
        }
        gallery["extensions"].append(ext_entry)
    else:
        ext_entry["displayName"] = meta["displayName"]
        ext_entry["description"] = meta["description"]
        versions = [v for v in ext_entry.get("versions", []) if v["version"] != version]
        versions.insert(0, version_entry)
        ext_entry["versions"] = versions

    gallery_path.write_text(json.dumps(gallery, indent=2, ensure_ascii=False), encoding="utf-8")
    print(f"✅ Added {extension_id}@{version}")


def main():
    parser = argparse.ArgumentParser(description="Add VSIX to gallery storage")
    parser.add_argument("vsix", help="Path to VSIX file or directory of VSIX files")
    parser.add_argument(
        "--data-dir",
        default=str(Path(__file__).resolve().parent.parent),
        help="Gallery data directory (default: server directory)",
    )
    args = parser.parse_args()

    data_dir = Path(args.data_dir)
    data_dir.mkdir(parents=True, exist_ok=True)

    vsix_input = Path(args.vsix)
    if vsix_input.is_dir():
        vsix_files = sorted(vsix_input.glob("*.vsix"))
        if not vsix_files:
            print(f"No VSIX files found in {vsix_input}")
            sys.exit(1)
        for vf in vsix_files:
            add_vsix(vf, data_dir)
    elif vsix_input.is_file() and vsix_input.suffix == ".vsix":
        add_vsix(vsix_input, data_dir)
    else:
        print(f"Invalid input: {vsix_input}")
        sys.exit(1)

    print(f"\nDone. Gallery data in: {data_dir}")


if __name__ == "__main__":
    main()
