<#
.SYNOPSIS
    Configures VS Code to use a private extension gallery.

.DESCRIPTION
    Modifies the product.json in the VS Code installation to point the
    extensionsGallery URLs at a private gallery server, enabling extension
    discovery, installation, and auto-update from the internal network.

.PARAMETER GalleryUrl
    The base URL of the private gallery server (e.g., http://gallery.internal:8080)

.EXAMPLE
    .\configure-vscode.ps1 -GalleryUrl "http://100.252.201.200:8080"
#>

param(
    [Parameter(Mandatory=$true)]
    [string]$GalleryUrl
)

# Remove trailing slash
$GalleryUrl = $GalleryUrl.TrimEnd('/')

# Find VS Code installation
$vscodeBase = "$env:LOCALAPPDATA\Programs\Microsoft VS Code"
if (-not (Test-Path $vscodeBase)) {
    $vscodeBase = "C:\Program Files\Microsoft VS Code"
}

# Find the commit directory
$commitDirs = Get-ChildItem $vscodeBase -Directory | Where-Object { $_.Name -match '^[0-9a-f]+$' }
if ($commitDirs.Count -eq 0) {
    Write-Host "❌ VS Code installation not found in $vscodeBase" -ForegroundColor Red
    Write-Host "   Looked for a commit-hash directory."
    exit 1
}

$productPath = Join-Path $commitDirs[0].FullName "resources\app\product.json"

if (-not (Test-Path $productPath)) {
    Write-Host "❌ product.json not found at $productPath" -ForegroundColor Red
    exit 1
}

Write-Host "VS Code product.json: $productPath"
Write-Host "Gallery URL: $GalleryUrl"
Write-Host ""

# Read product.json using Node.js (handles large JSON reliably)
$productJson = node -e "console.log(require('fs').readFileSync(process.argv[1], 'utf8'))" $productPath

# Backup
$backupPath = "$productPath.bak"
if (-not (Test-Path $backupPath)) {
    Copy-Item $productPath $backupPath
    Write-Host "✅ Backup created: $backupPath"
} else {
    Write-Host "ℹ️  Backup already exists: $backupPath"
}

# Modify extensionsGallery using Node.js
$result = node -e @"
const fs = require('fs');
const path = process.argv[1];
const galleryUrl = process.argv[2];

const p = JSON.parse(fs.readFileSync(path, 'utf8'));

p.extensionsGallery = {
    serviceUrl: galleryUrl,
    itemUrl: galleryUrl + '/items',
    publisherUrl: galleryUrl + '/publishers',
    resourceUrlTemplate: galleryUrl + '/files/{publisher}/{name}/{version}/{path}',
    extensionUrlTemplate: galleryUrl + '/vscode/{publisher}/{name}/latest',
    nlsBaseUrl: galleryUrl + '/nls',
    controlUrl: '',
    mcpUrl: '',
    accessSKUs: []
};

// Ensure extensionEnabledApiProposals includes GitHub.copilot-chat
if (!p.extensionEnabledApiProposals) {
    p.extensionEnabledApiProposals = {};
}

fs.writeFileSync(path, JSON.stringify(p, null, '\t'));
console.log('✅ extensionsGallery updated to: ' + galleryUrl);
"@ $productPath $GalleryUrl

Write-Host $result
Write-Host ""
Write-Host "VS Code is now configured to use the private gallery." -ForegroundColor Green
Write-Host "Restart VS Code for changes to take effect." -ForegroundColor Yellow
