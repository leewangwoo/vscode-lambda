# devpi-server: Private Python Package Repository

A caching PyPI proxy that lets internal-network machines install Python
packages without direct internet access.

## How It Works

```
External Network                          Internal Network
┌──────────────┐    ┌─────────────────┐    ┌──────────────┐
│  pypi.org    │◄───│  devpi-server   │◄───│  User pip    │
│  (PyPI)      │    │  (cache/proxy)  │    │  install     │
└──────────────┘    └─────────────────┘    └──────────────┘
                     100.252.201.200:3141
```

1. **With internet (briefly):** devpi caches packages from PyPI
2. **Offline:** users install from the local cache
3. **Admin sync:** pre-populate the cache with commonly-used packages

## Quick Start

### 1. Start devpi-server

```bash
cd devpi
docker compose up -d
```

devpi will be available at `http://100.252.201.200:3141`.

### 2. Initialize (first time only)

```bash
# Create admin user and a staging index
docker exec devpi-server devpi-server --start

# From a machine with devpi-client installed:
pip install devpi-client
devpi use http://100.252.201.200:3141
devpi user -c admin password=admin
devpi login admin --password=admin
devpi index -c staging bases=root/pypi volatile=True
```

### 3. Pre-populate packages (external network)

From a machine **with internet access**, download commonly-used packages:

```bash
devpi use http://100.252.201.200:3141
devpi login admin --password=admin
devpi use admin/staging

# Bulk download + upload
# Windows:
.\scripts\sync-packages.bat requirements-common.txt

# Linux/macOS:
./scripts/sync-packages.sh requirements-common.txt
```

### 4. Configure user machines (internal network)

On each user machine:

```powershell
.\scripts\configure-pip.ps1 -DevpiUrl "http://100.252.201.200:3141"
```

Then `pip install numpy pandas requests` works from the local cache.

## Architecture

```
devpi/
├── docker-compose.yml              # devpi-server Docker config
├── README.md                       # This file
├── scripts/
│   ├── sync-packages.bat           # Download & upload packages to devpi (Windows)
│   ├── sync-packages.sh            # Download & upload packages to devpi (Linux)
│   ├── configure-pip.ps1           # Configure pip on user machines
│   └── configure-pip.sh            # Configure pip on Linux user machines
└── requirements-common.txt         # Common packages to pre-populate
```

## Admin Operations

### Sync packages from PyPI (external network)

```bash
# Install devpi-client on a machine with internet
pip install devpi-client

# Point to devpi server
devpi use http://100.252.201.200:3141
devpi login admin --password=admin
devpi use admin/staging

# Download and upload packages listed in a requirements file
# Windows:
.\scripts\sync-packages.bat requirements-common.txt
# Linux/macOS:
./scripts/sync-packages.sh requirements-common.txt

# Or upload a single package
devpi upload some-package==1.2.3
```

### Upload internal/private packages

```bash
# Build your package
python setup.py sdist bdist_wheel

# Upload to devpi
devpi upload
```

### Manage users

```bash
devpi login admin --password=admin
devpi user -c newuser password=theirpassword
devpi user -m newuser password=newpassword  # change password
devpi user -y --delete newuser              # delete user
```

## User Machine Setup

### Windows

```powershell
.\configure-pip.ps1 -DevpiUrl "http://100.252.201.200:3141"
```

Or manually create `%APPDATA%\pip\pip.ini`:

```ini
[global]
index-url = http://100.252.201.200:3141/root/pypi/+simple/
trusted-host = 100.252.201.200
```

### Linux/macOS

```bash
./configure-pip.sh http://100.252.201.200:3141
```

Or manually create `~/.pip/pip.conf`:

```ini
[global]
index-url = http://100.252.201.200:3141/root/pypi/+simple/
trusted-host = 100.252.201.200
```

### Virtual Environments

pip.conf is inherited by virtualenvs, so no special configuration needed:

```bash
python -m venv myproject
source myproject/bin/activate  # Linux
pip install numpy              # Uses devpi automatically
```

## Troubleshooting

### "No matching distribution found"

The package hasn't been cached yet. From a machine with internet:
```bash
devpi use admin/staging
devpi download <package-name>
```

### SSL/Certificate errors

devpi runs on HTTP (internal network). Add to pip.conf:
```ini
trusted-host = 100.252.201.200
```

### Check cached packages

```bash
devpi list                       # List all cached packages
devpi list numpy                 # Show versions of numpy
```
