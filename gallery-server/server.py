"""
Private VS Code Extension Gallery Server

A lightweight FastAPI server that implements the VS Code extension gallery API,
enabling extension discovery, installation, and auto-update from a private
internal network without access to the public marketplace.

API Endpoints:
  POST /extensionquery                          - VS Code main query API
  GET  /vscode/{publisher}/{name}/latest        - Latest version probe
  GET  /files/{publisher}/{name}/{version}/{path:path} - Asset download
  POST /api/upload                              - Upload VSIX (admin)
  GET  /api/extensions                          - List all extensions (admin)
  DELETE /api/extensions/{ext_id}/{version}     - Remove extension version (admin)
  GET  /                                        - Gallery info
"""

from __future__ import annotations

import io
import json
import shutil
import zipfile
from datetime import datetime, timezone
from pathlib import Path
from typing import Any

from fastapi import FastAPI, File, HTTPException, UploadFile
from fastapi.responses import FileResponse, JSONResponse

# ---------------------------------------------------------------------------
# Configuration
# ---------------------------------------------------------------------------

import os

DATA_DIR = Path(os.environ.get("GALLERY_DATA_DIR", Path(__file__).resolve().parent))
EXTENSIONS_DIR = DATA_DIR / "extensions"
GALLERY_JSON = DATA_DIR / "gallery.json"

EXTENSIONS_DIR.mkdir(exist_ok=True)

# ---------------------------------------------------------------------------
# Gallery metadata storage
# ---------------------------------------------------------------------------


def _load_gallery() -> dict[str, list[dict]]:
    """Load gallery.json, returning an empty structure if it doesn't exist."""
    if GALLERY_JSON.exists():
        return json.loads(GALLERY_JSON.read_text(encoding="utf-8"))
    return {"extensions": []}


def _save_gallery(data: dict[str, list[dict]]) -> None:
    """Persist gallery.json atomically."""
    tmp = GALLERY_JSON.with_suffix(".tmp")
    tmp.write_text(json.dumps(data, indent=2, ensure_ascii=False), encoding="utf-8")
    tmp.replace(GALLERY_JSON)


def _extension_dir(publisher: str, name: str, version: str) -> Path:
    return EXTENSIONS_DIR / publisher / name / version


# ---------------------------------------------------------------------------
# VSIX metadata extraction
# ---------------------------------------------------------------------------


def _extract_vsix_metadata(vsix_bytes: bytes) -> dict[str, Any]:
    """Extract package.json and manifest info from a VSIX (zip) blob."""
    try:
        zf = zipfile.ZipFile(io.BytesIO(vsix_bytes))
    except zipfile.BadZipFile as exc:
        raise ValueError("Invalid VSIX file") from exc

    # Read extension/package.json
    try:
        pkg_raw = zf.read("extension/package.json")
        pkg = json.loads(pkg_raw)
    except KeyError as exc:
        raise ValueError("VSIX missing extension/package.json") from exc

    # Read vsixmanifest for additional metadata
    manifest: dict[str, Any] = {}
    for name in zf.namelist():
        if name.endswith("extension.vsixmanifest"):
            try:
                manifest_raw = zf.read(name).decode("utf-8", errors="replace")
                # Simple tag extraction (avoid heavy XML deps)
                import re

                tags = {}
                for tag in ["DisplayName", "Description", "Tags", "GalleryFlags"]:
                    m = re.search(rf"<{tag}>(.*?)</{tag}>", manifest_raw, re.DOTALL)
                    if m:
                        tags[tag] = m.group(1).strip()
                manifest = tags
            except Exception:
                pass
            break

    publisher = pkg.get("publisher", "unknown")
    name = pkg.get("name", "unknown")

    return {
        "publisher": publisher,
        "name": name,
        "extensionId": f"{publisher}.{name}",
        "version": pkg.get("version", "0.0.0"),
        "displayName": pkg.get("displayName", name),
        "description": pkg.get("description", manifest.get("Description", "")),
        "engines": pkg.get("engines", {}).get("vscode", ""),
        "categories": pkg.get("categories", []),
        "tags": pkg.get("keywords", []),
        "icon": pkg.get("icon", ""),
        "main": pkg.get("main", ""),
        "enabledApiProposals": pkg.get("enabledApiProposals", []),
    }


def _build_asset_files(version: str) -> list[dict[str, str]]:
    """Build the standard asset files list for a version."""
    return [
        {
            "assetType": "Microsoft.VisualStudio.Code.VSIXPackage",
            "source": "extension.vsix",
        },
        {
            "assetType": "Microsoft.VisualStudio.Services.Content.Details",
            "source": "extension/README.md",
        },
        {
            "assetType": "Microsoft.VisualStudio.Services.Content.Changelog",
            "source": "extension/CHANGELOG.md",
        },
        {
            "assetType": "Microsoft.VisualStudio.Services.Icons.Default",
            "source": "extension/icon.png",
        },
    ]


def _build_properties(meta: dict[str, Any]) -> list[dict[str, str]]:
    """Build the properties array for the gallery response."""
    props = [
        {"key": "Microsoft.VisualStudio.Code.ExtensionDependencies", "value": ""},
        {"key": "Microsoft.VisualStudio.Code.ExtensionKind", "value": "workspace"},
        {"key": "Microsoft.VisualStudio.Code.Engine", "value": meta.get("engines", "^1.115.0")},
    ]
    if meta.get("enabledApiProposals"):
        props.append(
            {
                "key": "Microsoft.VisualStudio.Code.EnabledApiProposals",
                "value": ",".join(meta["enabledApiProposals"]),
            }
        )
    return props


# ---------------------------------------------------------------------------
# Gallery management operations
# ---------------------------------------------------------------------------


def add_extension(vsix_bytes: bytes) -> dict[str, Any]:
    """
    Register a VSIX in the gallery.

    Stores the VSIX file under extensions/{publisher}/{name}/{version}/
    and updates gallery.json metadata.
    """
    meta = _extract_vsix_metadata(vsix_bytes)
    publisher = meta["publisher"]
    name = meta["name"]
    version = meta["version"]

    ext_dir = _extension_dir(publisher, name, version)
    ext_dir.mkdir(parents=True, exist_ok=True)

    # Save the VSIX file
    vsix_path = ext_dir / "extension.vsix"
    vsix_path.write_bytes(vsix_bytes)

    # Extract README/CHANGELOG/icon from VSIX for asset serving
    try:
        zf = zipfile.ZipFile(io.BytesIO(vsix_bytes))
        for asset_name, target in [
            ("extension/README.md", "README.md"),
            ("extension/CHANGELOG.md", "CHANGELOG.md"),
        ]:
            if asset_name in zf.namelist():
                (ext_dir / target).write_bytes(zf.read(asset_name))
        # Icon
        icon = meta.get("icon", "")
        if icon:
            icon_path = f"extension/{icon}"
            if icon_path in zf.namelist():
                (ext_dir / "icon.png").write_bytes(zf.read(icon_path))
    except Exception:
        pass

    # Update gallery.json
    gallery = _load_gallery()
    extensions = gallery["extensions"]

    # Find or create the extension entry
    ext_entry: dict[str, Any] | None = None
    for e in extensions:
        if e["extensionId"] == meta["extensionId"]:
            ext_entry = e
            break

    now = datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")

    version_entry = {
        "version": version,
        "lastUpdated": now,
        "assetUri": f"/files/{publisher}/{name}/{version}",
        "fallbackAssetUri": f"/files/{publisher}/{name}/{version}",
        "files": _build_asset_files(version),
        "properties": _build_properties(meta),
    }

    if ext_entry is None:
        ext_entry = {
            "extensionId": meta["extensionId"],
            "publisher": publisher,
            "name": name,
            "displayName": meta["displayName"],
            "description": meta["description"],
            "categories": meta.get("categories", ["Other"]),
            "tags": meta.get("tags", []),
            "versions": [version_entry],
        }
        extensions.append(ext_entry)
    else:
        # Update metadata
        ext_entry["displayName"] = meta["displayName"]
        ext_entry["description"] = meta["description"]
        # Replace or add version
        versions = ext_entry.get("versions", [])
        versions = [v for v in versions if v["version"] != version]
        versions.insert(0, version_entry)  # newest first
        ext_entry["versions"] = versions

    _save_gallery(gallery)
    return {"status": "ok", "extensionId": meta["extensionId"], "version": version}


def remove_extension_version(extension_id: str, version: str) -> dict[str, Any]:
    """Remove a specific version of an extension from the gallery."""
    gallery = _load_gallery()
    for ext in gallery["extensions"]:
        if ext["extensionId"] == extension_id:
            ext["versions"] = [v for v in ext.get("versions", []) if v["version"] != version]
            # Remove the directory
            ext_dir = _extension_dir(ext["publisher"], ext["name"], version)
            if ext_dir.exists():
                shutil.rmtree(ext_dir)
            # Remove extension entry if no versions remain
            if not ext["versions"]:
                gallery["extensions"] = [
                    e for e in gallery["extensions"] if e["extensionId"] != extension_id
                ]
            _save_gallery(gallery)
            return {"status": "ok", "removed": f"{extension_id}@{version}"}
    raise HTTPException(status_code=404, detail=f"Extension {extension_id} not found")


# ---------------------------------------------------------------------------
# VS Code Gallery API
# ---------------------------------------------------------------------------

app = FastAPI(title="Private VS Code Extension Gallery", version="1.0.0")


@app.get("/")
async def gallery_info():
    """Gallery information page."""
    gallery = _load_gallery()
    exts = gallery["extensions"]
    total_versions = sum(len(e.get("versions", [])) for e in exts)
    return {
        "name": "Private VS Code Extension Gallery",
        "extensions": len(exts),
        "versions": total_versions,
        "extensionList": [
            {
                "id": e["extensionId"],
                "displayName": e["displayName"],
                "latestVersion": e["versions"][0]["version"] if e.get("versions") else None,
            }
            for e in exts
        ],
    }


def _build_extension_query_response(
    extensions: list[dict], criteria: list[dict] | None = None
) -> dict[str, Any]:
    """Build the extensionquery API response for VS Code."""
    # Filter by criteria if provided
    filtered = extensions
    if criteria:
        for c in criteria:
            ft = c.get("filterType")
            val = c.get("value", "")
            # filterType 1=Tag, 4=ExtensionId, 7=ExtensionName, 8=Target, 10=SearchText
            if ft == 4:  # ExtensionId
                filtered = [e for e in filtered if val.lower() in e.get("extensionId", "").lower()]
            elif ft == 7:  # ExtensionName (publisher.name)
                filtered = [e for e in filtered if val.lower() in e.get("extensionId", "").lower()]
            elif ft == 10:  # SearchText
                val_lower = val.lower()
                filtered = [
                    e
                    for e in filtered
                    if val_lower in e.get("extensionId", "").lower()
                    or val_lower in e.get("displayName", "").lower()
                    or val_lower in e.get("description", "").lower()
                    or any(val_lower in t.lower() for t in e.get("tags", []))
                ]
            elif ft == 8:  # Target = Microsoft.VisualStudio.Code (always match)
                pass

    metadata_items = []
    for ext in filtered:
        versions = ext.get("versions", [])
        if not versions:
            continue
        latest = versions[0]

        item: dict[str, Any] = {
            "extensionId": ext["extensionId"],
            "extensionName": ext["name"],
            "displayName": ext["displayName"],
            "shortDescription": ext.get("description", ""),
            "publisher": {
                "publisherId": f"{ext['publisher']}-private",
                "publisherName": ext["publisher"],
                "displayName": ext["publisher"],
            },
            "versions": [
                {
                    "version": v["version"],
                    "lastUpdated": v.get("lastUpdated", ""),
                    "assetUri": v.get("assetUri", ""),
                    "fallbackAssetUri": v.get("fallbackAssetUri", ""),
                    "files": v.get("files", []),
                    "properties": v.get("properties", []),
                    "targetPlatform": "universal",
                }
                for v in versions
            ],
            "tags": ext.get("tags", []),
            "categories": ext.get("categories", ["Other"]),
            "statistics": [],
            "flags": "public",
        }
        metadata_items.append(item)

    return {
        "results": [
            {
                "extensionMetadata": [],
                "resultMetadata": [
                    {
                        "metadataType": "ResultCount",
                        "metadataItems": [
                            {"name": "TotalCount", "count": len(metadata_items), "categories": []}
                        ],
                    },
                    {
                        "metadataType": "LatestVersionMetadata",
                        "metadataItems": metadata_items,
                    },
                ],
            }
        ]
    }


@app.post("/extensionquery")
async def extension_query(request: dict[str, Any]):
    """
    Main VS Code gallery query endpoint.

    Handles search, install, and update-check queries.
    """
    gallery = _load_gallery()
    extensions = gallery["extensions"]

    # Extract filters
    filters = request.get("filters", [])
    criteria = []
    if filters:
        criteria = filters[0].get("criteria", [])

    # Build response
    return _build_extension_query_response(extensions, criteria)


@app.get("/vscode/{publisher}/{name}/latest")
async def latest_version(publisher: str, name: str):
    """
    Fast latest-version probe for update detection.

    VS Code calls this to check if an installed extension has an update.
    """
    extension_id = f"{publisher}.{name}"
    gallery = _load_gallery()

    for ext in gallery["extensions"]:
        if ext["extensionId"].lower() == extension_id.lower():
            versions = ext.get("versions", [])
            if versions:
                latest = versions[0]
                return {
                    "extensionId": extension_id,
                    "version": latest["version"],
                    "assetUri": latest.get("assetUri", ""),
                    "files": latest.get("files", []),
                    "properties": latest.get("properties", []),
                }
    raise HTTPException(status_code=404, detail=f"Extension {extension_id} not found")


@app.get("/files/{publisher}/{name}/{version}/{path:path}")
async def download_asset(publisher: str, name: str, version: str, path: str):
    """
    Serve extension assets (VSIX package, README, icon, etc.).
    """
    # Map asset types to actual files
    file_map = {
        "Microsoft.VisualStudio.Code.VSIXPackage": "extension.vsix",
        "extension.vsix": "extension.vsix",
        "extension/README.md": "README.md",
        "extension/CHANGELOG.md": "CHANGELOG.md",
        "extension/icon.png": "icon.png",
        "Microsoft.VisualStudio.Services.Content.Details": "README.md",
        "Microsoft.VisualStudio.Services.Content.Changelog": "CHANGELOG.md",
        "Microsoft.VisualStudio.Services.Icons.Default": "icon.png",
    }

    actual_file = file_map.get(path, path.replace("extension/", ""))

    ext_dir = _extension_dir(publisher, name, version)
    file_path = ext_dir / actual_file

    if not file_path.exists():
        # Try the raw path
        file_path = ext_dir / path

    if not file_path.exists():
        raise HTTPException(status_code=404, detail=f"Asset {path} not found")

    # Determine media type
    media_types = {
        ".vsix": "application/zip",
        ".json": "application/json",
        ".md": "text/markdown",
        ".png": "image/png",
        ".jpg": "image/jpeg",
        ".svg": "image/svg+xml",
    }
    suffix = file_path.suffix.lower()
    media_type = media_types.get(suffix, "application/octet-stream")

    return FileResponse(file_path, media_type=media_type)


# ---------------------------------------------------------------------------
# Admin API
# ---------------------------------------------------------------------------


@app.post("/api/upload")
async def upload_extension(file: UploadFile = File(...)):
    """Upload and register a VSIX file."""
    content = await file.read()
    result = add_extension(content)
    return result


@app.get("/api/extensions")
async def list_extensions():
    """List all registered extensions."""
    gallery = _load_gallery()
    return gallery


@app.delete("/api/extensions/{extension_id}/{version}")
async def delete_extension(extension_id: str, version: str):
    """Remove a specific extension version."""
    return remove_extension_version(extension_id, version)


@app.post("/api/reload")
async def reload_gallery():
    """Reload gallery.json from disk."""
    return {"status": "ok", "extensions": len(_load_gallery()["extensions"])}


# ---------------------------------------------------------------------------
# Health check
# ---------------------------------------------------------------------------


@app.get("/health")
async def health():
    return {"status": "ok"}


if __name__ == "__main__":
    import uvicorn

    uvicorn.run(app, host="0.0.0.0", port=8080)
