# VS Code Lambda - Offline Network Integration Guide

Complete guide for deploying VS Code with custom extensions and Python
package management in an airgapped internal network.

## System Architecture

```
┌─────────────────────────────────────────────────────────────┐
│                    Internal Network                          │
│                                                              │
│  ┌─────────────┐  ┌─────────────┐  ┌─────────────┐         │
│  │ VS Code     │  │ Extension   │  │ devpi       │         │
│  │ Clients     │  │ Gallery     │  │ PyPI Proxy  │         │
│  │ (Windows)   │  │ :8080       │  │ :3141       │         │
│  └──────┬──────┘  └──────┬──────┘  └──────┬──────┘         │
│         │                │                │                  │
│         │ Extensions     │ VSIX files     │ Python packages  │
│         │ (install/update)│ (search/install)│ (pip install) │
└─────────┴────────────────┴────────────────┴─────────────────┘
                          │
                    ┌─────┴─────┐
                    │  Docker   │
                    │  Host     │
                    │ (Linux)   │
                    └───────────┘
```

## Components

| Component | Port | Purpose |
|-----------|------|---------|
| Extension Gallery | 8080 | VS Code extensions (search, install, update) |
| devpi Server | 3141 | Python packages (pip install) |
| LiteLLM Proxy | 8088 | LLM models (chat completions) |

## 1. Extension Gallery Server

**Location:** `gallery-server/`

A FastAPI server implementing the VS Code gallery API for extension
discovery, installation, and auto-update.

### Setup

```bash
cd gallery-server
docker compose up -d --build
# Available at http://<server-ip>:8080
```

### Add Extensions

```bash
# Add Lambda Chat extension
./gallery-server/scripts/publish.sh copilot-chat-999.1.0.vsix http://<server-ip>:8080

# Download and add common VS Code extensions from marketplace
# (run from a machine with internet)
./gallery-server/scripts/fetch-vscode-extensions.sh http://<server-ip>:8080
```

### Client Setup

```powershell
# On each user machine:
.\lambda-chat-deploy\install.bat
```

This configures VS Code to use the private gallery and installs the
Lambda Chat extension.

## 2. Python Package Server (devpi)

**Location:** `devpi/`

A caching PyPI proxy for installing Python packages without internet.

### Setup

```bash
cd devpi
docker compose up -d
# Available at http://<server-ip>:3141
```

### Pre-populate Packages

From a machine **with internet access**:

```bash
pip install devpi-client
devpi use http://<server-ip>:3141
devpi login admin
devpi use admin/staging

# Sync common packages
./devpi/scripts/sync-packages.sh devpi/requirements-common.txt http://<server-ip>:3141
```

### Client Setup

```powershell
# On each user machine (Windows):
.\devpi\scripts\configure-pip.ps1 -DevpiUrl "http://<server-ip>:3141"

# Linux:
./devpi/scripts/configure-pip.sh http://<server-ip>:3141
```

After this, `pip install numpy pandas` works from the local cache.

## 3. Lambda Chat Extension

**Location:** `lambda-chat-deploy/`

Custom VS Code extension for offline LLM chat via LiteLLM.

### Build

```bash
npm run build
vsce package --no-dependencies
# Produces copilot-chat-<version>.vsix
```

### Publish to Gallery

```bash
./gallery-server/scripts/publish.sh copilot-chat-999.1.0.vsix http://<server-ip>:8080
```

### Version Management

```bash
# Bump version
npm version minor  # 999.1.0 → 999.2.0

# Build and publish
npm run build
vsce package --no-dependencies
./gallery-server/scripts/publish.sh copilot-chat-999.2.0.vsix http://<server-ip>:8080

# Users get automatic update notification in VS Code
```

## Quick Deployment Checklist

### Server Setup (one-time)

- [ ] Start extension gallery: `cd gallery-server && docker compose up -d --build`
- [ ] Start devpi: `cd devpi && docker compose up -d`
- [ ] Initialize devpi: create admin user and staging index
- [ ] Publish Lambda Chat VSIX to gallery
- [ ] Download VS Code extensions to gallery (from internet machine)
- [ ] Sync Python packages to devpi (from internet machine)

### Client Setup (per machine)

- [ ] Install VS Code 1.115+
- [ ] Run `install.bat` (configures gallery + installs extension)
- [ ] Run `configure-pip.ps1` (configures Python packages)
- [ ] Restart VS Code
- [ ] Verify: Chat panel works, `pip install` works

## IP Address Configuration

Replace `100.252.201.200` with your server IP in:

- `lambda-chat-deploy/install.bat` → `GALLERY_URL`
- `devpi/docker-compose.yml` → `--outside-url`
- `devpi/scripts/configure-pip.ps1` → default URL
- `devpi/scripts/sync-packages.sh` → default URL
- `gallery-server/scripts/fetch-vscode-extensions.sh` → default URL

## File Locations

```
vscode-lambda/
├── gallery-server/          # Extension gallery server
│   ├── server.py
│   ├── docker-compose.yml
│   ├── Dockerfile
│   └── scripts/
│       ├── add_extension.py
│       ├── publish.sh
│       ├── fetch-vscode-extensions.sh
│       └── configure-vscode.ps1
├── devpi/                   # Python package server
│   ├── docker-compose.yml
│   ├── requirements-common.txt
│   └── scripts/
│       ├── sync-packages.sh
│       ├── configure-pip.ps1
│       └── configure-pip.sh
├── lambda-chat-deploy/      # Client deployment package
│   ├── install.bat
│   ├── configure-vscode.ps1
│   ├── copilot-chat-*.vsix
│   └── README.txt
├── OFFLINE-GUIDE.md         # This file
└── src/                     # Extension source code
```
