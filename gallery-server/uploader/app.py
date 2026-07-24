"""
Tiny sidecar that accepts VSIX uploads over HTTP and registers them in the
running code-marketplace container.

Why this exists
---------------
code-marketplace has no upload endpoint of its own; VSIXes are added via the
`code-marketplace add` CLI inside the container. On an airgapped network you
cannot `docker cp` from an external PC, so this service exposes a small
authenticated `/upload` endpoint. Caddy fronts it with TLS + CORS so the
external (online) PC can push VSIXes straight in, and each upload is handed
to code-marketplace immediately — no need to SSH into the server.

Flow:
    client POST /upload  ->  save VSIX to /inbox  ->  docker exec
    code-marketplace add /inbox/<file> --extensions-dir /extensions
"""

from __future__ import annotations

import logging
import os
import shutil
import subprocess
import threading
from pathlib import Path
from typing import Optional

from fastapi import FastAPI, File, Header, HTTPException, UploadFile
from fastapi.responses import JSONResponse

# ---------------------------------------------------------------------------
# Configuration
# ---------------------------------------------------------------------------

INBOX_DIR = Path(os.environ.get("INBOX_DIR", "/inbox"))
EXTENSIONS_DIR = Path(os.environ.get("CODE_MARKETPLACE_EXT_DIR", "/extensions"))
CONTAINER = os.environ.get("CODE_MARKETPLACE_CONTAINER", "code-marketplace")
# Shared secret. Keep it simple — the network is airgapped and TLS is
# terminated by Caddy; this just blocks random POSTs.
UPLOAD_TOKEN = os.environ.get("UPLOAD_TOKEN", "lambda-upload")
# When non-empty, call code-marketplace inside a container of this name.
# Empty string => run the `code-marketplace` binary on the host instead.
# Set CODE_MARKETPLACE_CONTAINER="" to disable docker exec.
MAX_FILE_SIZE = int(os.environ.get("MAX_FILE_SIZE", str(2 * 1024 * 1024 * 1024)))  # 2 GB

logging.basicConfig(level=logging.INFO, format="%(asctime)s [%(levelname)s] %(message)s")
log = logging.getLogger("uploader")

INBOX_DIR.mkdir(parents=True, exist_ok=True)

app = FastAPI(title="Gallery Uploader", version="1.0.0")

# Serialize the `add` calls: code-marketplace scans the extensions dir on each
# request, and concurrent inserts race / cause duplicate work.
_add_lock = threading.Lock()


# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

def _register_vsix(vsix_path: Path) -> tuple[bool, str]:
    """Register a VSIX in code-marketplace. Returns (ok, message)."""
    if CONTAINER:
        # The file lives on the host's filesystem as seen by docker: we mount
        # INBOX_DIR identically into both this container and code-marketplace,
        # so the in-container path is the same.
        in_container = vsix_path.as_posix()
        cmd = [
            "docker", "exec", CONTAINER,
            "code-marketplace", "add", in_container,
            "--extensions-dir", str(EXTENSIONS_DIR),
        ]
    else:
        cmd = [
            "code-marketplace", "add", str(vsix_path),
            "--extensions-dir", str(EXTENSIONS_DIR),
        ]

    log.info("Registering %s: %s", vsix_path.name, " ".join(cmd))
    try:
        proc = subprocess.run(cmd, capture_output=True, text=True, timeout=120)
    except FileNotFoundError:
        return False, "`docker` not found in PATH"
    except subprocess.TimeoutExpired:
        return False, "code-marketplace add timed out"

    out = (proc.stdout + proc.stderr).strip()
    if proc.returncode == 0:
        return True, out or "registered"
    return False, out or f"code-marketplace add exited {proc.returncode}"


# ---------------------------------------------------------------------------
# Endpoints
# ---------------------------------------------------------------------------

@app.get("/health")
async def health() -> dict:
    return {"status": "ok", "container": CONTAINER or "host"}


@app.post("/upload")
async def upload(
    file: UploadFile = File(...),
    x_upload_token: Optional[str] = Header(default=None, alias="X-Upload-Token"),
) -> JSONResponse:
    if x_upload_token != UPLOAD_TOKEN:
        raise HTTPException(status_code=401, detail="invalid or missing X-Upload-Token")

    if not file.filename or not file.filename.lower().endswith(".vsix"):
        raise HTTPException(status_code=400, detail="file must be a .vsix")

    # Defensive: hard cap the size so nobody OOMs the box with a stray upload.
    tmp_path = INBOX_DIR / f".{file.filename}.part"
    final_path = INBOX_DIR / file.filename
    size = 0
    try:
        with tmp_path.open("wb") as fh:
            while chunk := await file.read(1024 * 1024):
                size += len(chunk)
                if size > MAX_FILE_SIZE:
                    raise HTTPException(
                        status_code=413,
                        detail=f"file exceeds {MAX_FILE_SIZE} bytes",
                    )
                fh.write(chunk)
    except HTTPException:
        tmp_path.unlink(missing_ok=True)
        raise
    except Exception as exc:
        tmp_path.unlink(missing_ok=True)
        raise HTTPException(status_code=500, detail=f"write failed: {exc}")
    finally:
        await file.close()

    shutil.move(str(tmp_path), str(final_path))
    log.info("Received %s (%d bytes)", final_path.name, size)

    with _add_lock:
        ok, msg = _register_vsix(final_path)
        if not ok:
            # Keep the file in the inbox so an operator can retry by hand.
            log.error("Registration failed for %s: %s", final_path.name, msg)
            return JSONResponse(
                status_code=500,
                content={"status": "error", "file": final_path.name, "detail": msg},
            )

    log.info("Registered %s: %s", final_path.name, msg.replace("\n", " | "))
    return {"status": "ok", "file": final_path.name, "size": size, "detail": msg}


@app.post("/upload-batch")
async def upload_batch(
    files: list[UploadFile] = File(...),
    x_upload_token: Optional[str] = Header(default=None, alias="X-Upload-Token"),
) -> JSONResponse:
    """Register multiple VSIXes. Processes sequentially to avoid races."""
    if x_upload_token != UPLOAD_TOKEN:
        raise HTTPException(status_code=401, detail="invalid or missing X-Upload-Token")

    results = []
    for f in files:
        if not f.filename or not f.filename.lower().endswith(".vsix"):
            results.append({"file": f.filename, "status": "skip", "detail": "not a .vsix"})
            await f.close()
            continue
        # Reuse the single-upload logic by saving then registering.
        final_path = INBOX_DIR / f.filename
        size = 0
        try:
            with final_path.open("wb") as fh:
                while chunk := await f.read(1024 * 1024):
                    size += len(chunk)
                    fh.write(chunk)
        except Exception as exc:
            results.append({"file": f.filename, "status": "error", "detail": str(exc)})
            await f.close()
            continue
        finally:
            await f.close()

        with _add_lock:
            ok, msg = _register_vsix(final_path)
        results.append({
            "file": f.filename,
            "size": size,
            "status": "ok" if ok else "error",
            "detail": msg,
        })
    return {"results": results}
