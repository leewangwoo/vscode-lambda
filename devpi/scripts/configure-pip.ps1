<#
.SYNOPSIS
    Configures pip to use the devpi private PyPI server.

.DESCRIPTION
    Creates or updates pip.conf/pip.ini to point at the internal devpi server,
    so all pip install commands use the local cache instead of pypi.org.

.PARAMETER DevpiUrl
    The base URL of the devpi server (e.g., http://100.252.201.200:3141)

.PARAMETER Index
    The devpi index to use (default: root/pypi, which proxies PyPI)

.EXAMPLE
    .\configure-pip.ps1 -DevpiUrl "http://100.252.201.200:3141"
    .\configure-pip.ps1 -DevpiUrl "http://100.252.201.200:3141" -Index "admin/staging"
#>

param(
    [Parameter(Mandatory=$true)]
    [string]$DevpiUrl,

    [string]$Index = "root/pypi"
)

# Remove trailing slash
$DevpiUrl = $DevpiUrl.TrimEnd('/')

# Extract host for trusted-host
$DevpiHost = ([System.Uri]$DevpiUrl).Host

# Determine pip config path
$pipConfigDir = "$env:APPDATA\pip"
$pipConfigPath = "$pipConfigDir\pip.ini"

# Create directory if needed
if (-not (Test-Path $pipConfigDir)) {
    New-Item -ItemType Directory -Path $pipConfigDir -Force | Out-Null
}

# Build pip.ini content
$IndexUrl = "$DevpiUrl/$Index/+simple/"

$pipIni = @"
[global]
index-url = $IndexUrl
trusted-host = $DevpiHost
timeout = 60

[install]
trusted-host = $DevpiHost
"@

# Write pip.ini
Set-Content -Path $pipConfigPath -Value $pipIni -Encoding UTF8

Write-Host "✅ pip configuration created: $pipConfigPath" -ForegroundColor Green
Write-Host ""
Write-Host "  index-url: $IndexUrl"
Write-Host "  trusted-host: $DevpiHost"
Write-Host ""

# Verify
Write-Host "Testing pip configuration..."
$pipVersion = pip --version 2>&1
Write-Host "  pip version: $pipVersion"

Write-Host ""
Write-Host "You can now run: pip install <package-name>" -ForegroundColor Cyan
Write-Host "It will use the devpi server at $DevpiUrl"
