<#
.SYNOPSIS
    Configures VS Code to use a private code-marketplace gallery.

.DESCRIPTION
    Points VS Code's product.json extensionsGallery at a private code-marketplace
    instance (fronted by a Caddy HTTPS reverse proxy).

    JSON editing is done via Python if available (most reliable on PS 5.1),
    falling back to PowerShell's ConvertFrom/ConvertTo-Json otherwise.

    Also: installs the gallery's self-signed HTTPS certificate and disables
    extension signature verification in settings.json.

.PARAMETER GalleryUrl
    The base HTTPS URL of the private gallery server.
    Example: https://100.252.201.200:8443

.PARAMETER InstallCert
    Download the gallery certificate from <GalleryUrl>/cert and install it.

.EXAMPLE
    .\configure-vscode.ps1 -GalleryUrl "https://100.252.201.200:8443" -InstallCert
#>

param(
    [Parameter(Mandatory=$true)]
    [string]$GalleryUrl,

    [switch]$InstallCert
)

$GalleryUrl = $GalleryUrl.TrimEnd('/')

# Find VS Code installation (per-user first, then system-wide).
$vscodeBase = "$env:LOCALAPPDATA\Programs\Microsoft VS Code"
if (-not (Test-Path $vscodeBase)) {
    $vscodeBase = "C:\Program Files\Microsoft VS Code"
}

# Apply to ALL commit directories (VS Code keeps old versions for rollback).
$commitDirs = Get-ChildItem $vscodeBase -Directory -ErrorAction SilentlyContinue | Where-Object { $_.Name -match '^[0-9a-f]+$' }
if ($commitDirs.Count -eq 0) {
    Write-Host "[FAIL] VS Code installation not found under $vscodeBase" -ForegroundColor Red
    exit 1
}

Write-Host "Gallery URL: $GalleryUrl"
Write-Host ""

# ============================================================
# Update product.json extensionsGallery in every commit dir.
# Use Python if available (reliable JSON on any PowerShell version),
# otherwise fall back to PowerShell's built-in JSON cmdlets.
# ============================================================
Write-Host "Updating product.json extensionsGallery..."

# Check if Python is available.
$usePython = $false
try { $null = Get-Command python -ErrorAction Stop; $usePython = $true } catch {}

if ($usePython) {
    Write-Host "  (using Python for JSON editing)"
} else {
    Write-Host "  (Python not found, using PowerShell JSON cmdlets)"
}

foreach ($dir in $commitDirs) {
    $productPath = Join-Path $dir.FullName "resources\app\product.json"
    if (-not (Test-Path $productPath)) {
        continue
    }

    Write-Host "  $($dir.Name): $productPath"

    # Backup (only once per file).
    $backupPath = "$productPath.bak"
    if (-not (Test-Path $backupPath)) {
        Copy-Item $productPath $backupPath
        Write-Host "    Backup created"
    } else {
        Write-Host "    Backup already exists"
    }

    if ($usePython) {
        # Python: precise JSON parse/edit/serialize. Handles nested arrays
        # (accessSKUs) and any PowerShell-version quirks perfectly.
        $pyScript = @"
import json, sys
path = sys.argv[1]
gallery_url = sys.argv[2]
with open(path, 'r', encoding='utf-8') as f:
    p = json.load(f)
p['extensionsGallery'] = {
    'serviceUrl': gallery_url + '/api',
    'itemUrl': gallery_url + '/item',
    'resourceUrlTemplate': gallery_url + '/files/{publisher}/{name}/{version}/{path}',
    'controlUrl': '',
    'nlsBaseUrl': '',
    'publisherUrl': '',
}
with open(path, 'w', encoding='utf-8') as f:
    json.dump(p, f, indent='\t', ensure_ascii=False)
"@
        & python -c $pyScript $productPath $GalleryUrl 2>&1 | ForEach-Object { Write-Host "    $_" }
        if ($LASTEXITCODE -eq 0) {
            Write-Host "    [OK] extensionsGallery updated"
        } else {
            Write-Host "    [FAIL] Python error" -ForegroundColor Red
        }
    } else {
        # PowerShell fallback: ConvertFrom/ConvertTo-Json.
        try {
            $raw = Get-Content $productPath -Raw
            $product = $raw | ConvertFrom-Json -ErrorAction Stop
        } catch {
            Write-Host "    [FAIL] Cannot parse product.json: $_" -ForegroundColor Red
            continue
        }

        $newGallery = [PSCustomObject]@{
            serviceUrl            = "$GalleryUrl/api"
            itemUrl               = "$GalleryUrl/item"
            resourceUrlTemplate   = "$GalleryUrl/files/{publisher}/{name}/{version}/{path}"
            controlUrl            = ""
            nlsBaseUrl            = ""
            publisherUrl          = ""
        }

        if (Get-Member -InputObject $product -Name "extensionsGallery" -MemberType NoteProperty -ErrorAction SilentlyContinue) {
            $product.extensionsGallery = $newGallery
        } else {
            $product | Add-Member -MemberType NoteProperty -Name "extensionsGallery" -Value $newGallery
        }

        $jsonText = $product | ConvertTo-Json -Depth 10
        $utf8NoBom = New-Object System.Text.UTF8Encoding $false
        [System.IO.File]::WriteAllText($productPath, $jsonText, $utf8NoBom)
        Write-Host "    [OK] extensionsGallery updated"
    }
}

Write-Host ""

# ============================================================
# Certificate trust (required for self-signed HTTPS gallery).
# ============================================================
if ($InstallCert) {
    Write-Host "Downloading gallery certificate from $GalleryUrl/cert ..."
    $certPath = Join-Path $env:TEMP "lambda-gallery-ca.cer"

    & curl.exe -k -s -o "$certPath" "$GalleryUrl/cert"
    if (-not (Test-Path $certPath) -or (Get-Item $certPath).Length -eq 0) {
        Write-Host "[WARN] Could not download certificate. Install it manually." -ForegroundColor Yellow
    } else {
        Write-Host "  Downloaded to $certPath"
        # Try LocalMachine first (system-wide, needs admin), then fall back to
        # CurrentUser (per-user, no admin).
        $import = $null
        try {
            Write-Host "  Installing into Trusted Root (Local Machine)..."
            $import = Import-Certificate -FilePath "$certPath" -CertStoreLocation Cert:\LocalMachine\Root -ErrorAction Stop
        } catch [System.UnauthorizedAccessException] {
            Write-Host "  Local Machine store requires admin - using Current User store instead." -ForegroundColor Yellow
            $import = Import-Certificate -FilePath "$certPath" -CertStoreLocation Cert:\CurrentUser\Root
        } catch {
            Write-Host "  Local Machine install failed - trying Current User store..." -ForegroundColor Yellow
            $import = Import-Certificate -FilePath "$certPath" -CertStoreLocation Cert:\CurrentUser\Root
        }
        if ($import) {
            Write-Host "  [OK] Certificate installed (thumbprint: $($import.Thumbprint))" -ForegroundColor Green
        } else {
            Write-Host "  [WARN] Auto-install failed. Double-click $certPath to install manually." -ForegroundColor Yellow
            Write-Host "         Choose 'Current User' -> 'Trusted Root Certification Authorities'." -ForegroundColor Yellow
        }
    }
} else {
    Write-Host "Certificate install skipped. Trust the gallery cert manually or re-run with -InstallCert." -ForegroundColor Yellow
    Write-Host "  Open $GalleryUrl in a browser -> view certificate -> install to Trusted Root."
}

Write-Host ""

# ============================================================
# Disable extension signature verification in settings.json.
#
# code-marketplace emits empty signatures (--sign flag) that VS Code cannot
# verify. On a private airgapped gallery this is pointless, so we disable it.
# Uses Python for JSON editing when available, regex fallback otherwise.
# ============================================================
Write-Host "Disabling extension signature verification (private gallery)..."
$settingsPath = Join-Path $env:APPDATA "Code\User\settings.json"
$settingsDir = Split-Path $settingsPath
if (-not (Test-Path $settingsDir)) {
    New-Item -ItemType Directory -Path $settingsDir -Force | Out-Null
}

if ($usePython) {
    $pySettings = @"
import json, os, sys
path = sys.argv[1]
if os.path.exists(path):
    with open(path, 'r', encoding='utf-8') as f:
        text = f.read()
    text = text.lstrip('\ufeff')
    text = text.rstrip()
    if text:
        s = json.loads(text)
    else:
        s = {}
else:
    s = {}
s['extensions.verifySignature'] = False
# Disable GitHub MCP Server - it triggers GitHub login prompts when the
# agent tries to use tools (file save, etc). Not usable on airgapped network.
s['chat.githubMcpServer.enabled'] = False
with open(path, 'w', encoding='utf-8') as f:
    json.dump(s, f, indent=4, ensure_ascii=False)
print('[OK] extensions.verifySignature = false')
print('[OK] chat.githubMcpServer.enabled = false')
"@
    & python -c $pySettings $settingsPath 2>&1 | ForEach-Object { Write-Host "  $_" }
} else {
    # Regex fallback for when Python is unavailable.
    if (Test-Path $settingsPath) {
        $settingsText = Get-Content $settingsPath -Raw -ErrorAction SilentlyContinue
        $settingsText = $settingsText -replace "^\xEF\xBB\xBF", ""
        $settingsText = $settingsText -replace ",(\s*[}\]])", '$1'

        if ($settingsText -and $settingsText.Trim()) {
            if ($settingsText -match '"extensions\.verifySignature"') {
                $settingsText = $settingsText -replace '"extensions\.verifySignature"\s*:\s*(true|false)', '"extensions.verifySignature": false'
                Write-Host "  [OK] Updated existing extensions.verifySignature = false"
            } else {
                $settingsText = $settingsText.TrimEnd() -replace '\}\s*$', "`n    ,`"extensions.verifySignature`": false`n}"
                Write-Host "  [OK] Added extensions.verifySignature = false"
            }
        } else {
            $settingsText = "{`n    `"extensions.verifySignature`": false`n}"
            Write-Host "  [OK] Created settings.json with extensions.verifySignature = false"
        }
    } else {
        $settingsText = "{`n    `"extensions.verifySignature`": false`n}"
        Write-Host "  [OK] Created settings.json with extensions.verifySignature = false"
    }

    $utf8NoBom = New-Object System.Text.UTF8Encoding $false
    [System.IO.File]::WriteAllText($settingsPath, $settingsText, $utf8NoBom)
    Write-Host "  Saved to $settingsPath"
}

Write-Host ""
Write-Host "[OK] VS Code is configured to use the private gallery." -ForegroundColor Green
Write-Host "     Restart VS Code (Developer: Reload Window) for changes to take effect."
Write-Host ""
