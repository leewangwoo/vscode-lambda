"""
LLM Instance Monitor — lightweight sidecar that polls each llama.cpp instance's
/slots endpoint and reports real-time busy/available status.

Designed to run alongside LiteLLM in the same Docker network.
"""

import asyncio
import json
import time
from datetime import datetime

import httpx
from fastapi import FastAPI
from fastapi.middleware.cors import CORSMiddleware

# LLM instances to monitor — must match litellm-config.yaml
LLM_INSTANCES = [
    {"name": "qwen27-local", "model": "qwen27", "url": "http://qwen27-5:8080"},
    {"name": "qwen35-local", "model": "qwen35", "url": "http://qwen35-4:8080"},
    {"name": "qwen27-r1", "model": "qwen27", "url": "http://100.253.190.178:8080"},
    {"name": "qwen27-r2", "model": "qwen27", "url": "http://100.253.190.178:8081"},
    {"name": "qwen27-r3", "model": "qwen27", "url": "http://100.253.190.178:8082"},
    {"name": "qwen27-r4", "model": "qwen27", "url": "http://100.253.190.178:8083"},
    {"name": "qwen35-r1", "model": "qwen35", "url": "http://100.253.190.178:8084"},
    {"name": "qwen35-r2", "model": "qwen35", "url": "http://100.253.190.178:8085"},
    {"name": "qwen35-r3", "model": "qwen35", "url": "http://100.253.190.178:8086"},
    {"name": "qwen35-r4", "model": "qwen35", "url": "http://100.253.190.178:8087"},
]

POLL_INTERVAL = 3  # seconds
SLOT_TIMEOUT = 2   # seconds per instance

app = FastAPI(title="LLM Monitor")
app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_methods=["*"],
    allow_headers=["*"],
)

# Cached status — updated by background poller
_status: dict = {
    "instances": [],
    "summary": {"total": len(LLM_INSTANCES), "available": 0, "busy": 0, "offline": 0},
    "updated_at": None,
}


async def _check_instance(client: httpx.AsyncClient, inst: dict) -> dict:
    """Check a single instance's /slots endpoint."""
    try:
        resp = await client.get(f"{inst['url']}/slots", timeout=SLOT_TIMEOUT)
        slots = resp.json()
        busy_slots = sum(1 for s in slots if s.get("is_processing"))
        total_slots = len(slots)
        return {
            "name": inst["name"],
            "model": inst["model"],
            "url": inst["url"],
            "status": "busy" if busy_slots > 0 else "available",
            "busy_slots": busy_slots,
            "total_slots": total_slots,
            "prompt_tokens": sum(s.get("n_prompt_tokens", 0) for s in slots),
            "decoded_tokens": sum(s.get("n_decoded", 0) for s in slots),
        }
    except Exception:
        return {
            "name": inst["name"],
            "model": inst["model"],
            "url": inst["url"],
            "status": "offline",
            "busy_slots": 0,
            "total_slots": 0,
            "prompt_tokens": 0,
            "decoded_tokens": 0,
        }


async def _poll_loop():
    """Background task that polls all instances every POLL_INTERVAL seconds."""
    async with httpx.AsyncClient() as client:
        while True:
            tasks = [_check_instance(client, inst) for inst in LLM_INSTANCES]
            results = await asyncio.gather(*tasks)

            available = sum(1 for r in results if r["status"] == "available")
            busy = sum(1 for r in results if r["status"] == "busy")
            offline = sum(1 for r in results if r["status"] == "offline")

            _status["instances"] = results
            _status["summary"] = {
                "total": len(LLM_INSTANCES),
                "available": available,
                "busy": busy,
                "offline": offline,
            }
            _status["updated_at"] = datetime.utcnow().isoformat() + "Z"

            await asyncio.sleep(POLL_INTERVAL)


@app.on_event("startup")
async def _startup():
    asyncio.create_task(_poll_loop())


@app.get("/health")
async def health():
    """Summary status — used by VS Code extension."""
    return _status["summary"]


@app.get("/status")
async def status():
    """Detailed status with per-instance info."""
    return _status


@app.get("/")
async def root():
    return {"service": "LLM Monitor", "endpoints": ["/health", "/status"]}
