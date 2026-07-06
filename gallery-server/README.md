# Private VS Code Extension Gallery Server

A lightweight FastAPI server that implements the VS Code extension gallery API,
enabling extension discovery, installation, and auto-update from a private
internal network without access to the public marketplace.

## Quick Start

### 1. Build and Run with Docker

```bash
cd gallery-server
docker compose up -d --build
```

The gallery server will be available at `http://localhost:8000`.

### 2. Add Extensions

#### Option A: Upload via HTTP (requires running server)

```bash
./scripts/publish.sh ../lambda-chat-deploy/copilot-chat-999.1.0.vsix http://localhost:8000
```

#### Option B: Add to storage directly (no running server needed)

```bash
python scripts/add_extension.py ../lambda-chat-deploy/copilot-chat-999.1.0.vsix --data-dir ./data
```

### 3. Configure VS Code

On each client machine, run:

```powershell
.\configure-vscode.ps1 -GalleryUrl "http://gallery.internal:8000"
```

Then restart VS Code.

## Architecture

```
gallery-server/
├── server.py              # FastAPI server implementing VS Code gallery API
├── Dockerfile             # Docker image definition
├── docker-compose.yml     # Docker Compose configuration
├── requirements.txt       # Python dependencies
├── scripts/
│   ├── add_extension.py   # Add VSIX to gallery storage (CLI)
│   ├── publish.sh         # Upload VSIX to running server (HTTP)
│   └── configure-vscode.ps1  # Configure VS Code to use this gallery
└── extensions/            # VSIX file storage (auto-created)
    └── {publisher}/{name}/{version}/
        ├── extension.vsix
        ├── README.md
        ├── CHANGELOG.md
        └── icon.png
```

## API Endpoints

### VS Code Gallery API

| Endpoint | Method | Purpose |
|----------|--------|---------|
| `/extensionquery` | POST | Search, install, update-check queries |
| `/vscode/{publisher}/{name}/latest` | GET | Latest version probe for update detection |
| `/files/{publisher}/{name}/{version}/{path}` | GET | Download assets (VSIX, README, icon) |

### Admin API

| Endpoint | Method | Purpose |
|----------|--------|---------|
| `/api/upload` | POST | Upload and register a VSIX |
| `/api/extensions` | GET | List all registered extensions |
| `/api/extensions/{id}/{version}` | DELETE | Remove an extension version |
| `/health` | GET | Health check |
| `/` | GET | Gallery info page |

## Version Management

Extensions use semantic versioning (semver). VS Code automatically detects
updates by comparing the gallery-reported version with the installed version.

### Publishing a New Version

```bash
# 1. Bump version in the extension's package.json
npm version minor  # 999.1.0 → 999.2.0

# 2. Build and package
npm run build
vsce package --no-dependencies

# 3. Publish to gallery
./gallery-server/scripts/publish.sh ./copilot-chat-999.2.0.vsix http://gallery.internal:8000
```

VS Code clients will automatically detect the new version and prompt for update
(if `extensions.autoUpdate` is enabled, which is the default).

## Docker Configuration

### docker-compose.yml

```yaml
services:
  gallery:
    build: .
    ports:
      - "8000:8000"
    volumes:
      - gallery-data:/data
    environment:
      - GALLERY_DATA_DIR=/data
```

### Data Persistence

Extension files and gallery metadata are stored in a Docker volume (`gallery-data`).
This persists across container restarts.

## Client Setup

### Using install.bat (Automated)

The `lambda-chat-deploy/install.bat` script handles everything:
1. Configures VS Code to use the private gallery
2. Installs the original Copilot Chat (trust setup)
3. Installs the Lambda custom extension
4. Refreshes extension configuration

### Manual Setup

```powershell
# Configure gallery URL
.\configure-vscode.ps1 -GalleryUrl "http://gallery.internal:8000"

# Restart VS Code
```

After configuration, the Extensions tab will show extensions from the private
gallery, and auto-update will work automatically.
