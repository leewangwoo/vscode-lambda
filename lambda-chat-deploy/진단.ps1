<#
.SYNOPSIS
    Lambda Chat Diagnostic Tool
    Run on both working and non-working PCs to compare results.
#>

Write-Host ""
Write-Host "============================================================"
Write-Host "  Lambda Chat Diagnostic Tool"
Write-Host "============================================================"
Write-Host ""
Write-Host "  Run on both working and non-working PCs to compare."
Write-Host ""
Read-Host "  Press Enter to continue"
Write-Host ""

# ============================================================
# 1. VS Code settings.json
# ============================================================
Write-Host "============================================================"
Write-Host "  [1] VS Code settings.json"
Write-Host "============================================================"
$settingsPath = Join-Path $env:APPDATA "Code\User\settings.json"
if (Test-Path $settingsPath) {
    Get-Content $settingsPath -Raw
} else {
    Write-Host "  settings.json NOT FOUND"
}
Write-Host ""
Write-Host ""

# ============================================================
# 2. customoai / byok / mcp / verify settings
# ============================================================
Write-Host "============================================================"
Write-Host "  [2] customoai / byok / mcp settings"
Write-Host "============================================================"
if (Test-Path $settingsPath) {
    try {
        $raw = Get-Content $settingsPath -Raw
        $raw = $raw -replace "^\xEF\xBB\xBF", ""
        $s = $raw | ConvertFrom-Json -ErrorAction Stop
        $found = $false
        $s.PSObject.Properties | Where-Object {
            $_.Name -match "customoai|byok|mcp|verify"
        } | ForEach-Object {
            Write-Host ("  {0} = {1}" -f $_.Name, $_.Value)
            $found = $true
        }
        if (-not $found) {
            Write-Host "  (no customoai/byok/mcp/verify settings found)"
        }
    } catch {
        Write-Host "  settings.json parse FAILED: $_"
    }
} else {
    Write-Host "  settings.json NOT FOUND"
}
Write-Host ""
Write-Host ""

# ============================================================
# 3. Installed copilot-chat extensions
# ============================================================
Write-Host "============================================================"
Write-Host "  [3] Installed copilot-chat extensions"
Write-Host "============================================================"

Write-Host "  User extensions:"
$extDir = Join-Path $env:USERPROFILE ".vscode\extensions"
$userExts = Get-ChildItem -Path $extDir -Filter "github.copilot-chat*" -Directory -ErrorAction SilentlyContinue
if ($userExts) {
    $userExts | ForEach-Object {
        $pkgPath = Join-Path $_.FullName "package.json"
        if (Test-Path $pkgPath) {
            $raw = Get-Content $pkgPath -Raw
            $ver = ($raw | Select-String '"version"\s*:\s*"([^"]+)"').Matches.Groups[1].Value
            $dn = ($raw | Select-String '"displayName"\s*:\s*"([^"]+)"').Matches.Groups[1].Value
            Write-Host ("    {0} (version: {1}, displayName: {2})" -f $_.Name, $ver, $dn)
        } else {
            Write-Host "    $($_.Name)"
        }
    }
} else {
    Write-Host "    (none)"
}

Write-Host ""
Write-Host "  Builtin extensions:"
$vscodeBase = Join-Path $env:LOCALAPPDATA "Programs\Microsoft VS Code"
if (-not (Test-Path $vscodeBase)) {
    $vscodeBase = "C:\Program Files\Microsoft VS Code"
}
Get-ChildItem $vscodeBase -Directory -ErrorAction SilentlyContinue | Where-Object { $_.Name -match '^[0-9a-f]+$' } | ForEach-Object {
    $builtinExt = Join-Path $_.FullName "resources\app\extensions\github.copilot-chat"
    if (Test-Path $builtinExt) {
        $pkgPath = Join-Path $builtinExt "package.json"
        if (Test-Path $pkgPath) {
            $raw = Get-Content $pkgPath -Raw
            $ver = ($raw | Select-String '"version"\s*:\s*"([^"]+)"').Matches.Groups[1].Value
            $dn = ($raw | Select-String '"displayName"\s*:\s*"([^"]+)"').Matches.Groups[1].Value
            Write-Host ("    {0}: version={1}, displayName={2}" -f $_.Name, $ver, $dn)
        } else {
            Write-Host ("    {0}: copilot-chat exists" -f $_.Name)
        }
    }
}
Write-Host ""
Write-Host ""

# ============================================================
# 4. product.json gallery URL
# ============================================================
Write-Host "============================================================"
Write-Host "  [4] product.json gallery settings"
Write-Host "============================================================"
Get-ChildItem $vscodeBase -Directory -ErrorAction SilentlyContinue | Where-Object { $_.Name -match '^[0-9a-f]+$' } | ForEach-Object {
    $pjson = Join-Path $_.FullName "resources\app\product.json"
    if (Test-Path $pjson) {
        $raw = Get-Content $pjson -Raw
        $svc = ($raw | Select-String '"serviceUrl"\s*:\s*"([^"]+)"').Matches.Groups[1].Value
        $item = ($raw | Select-String '"itemUrl"\s*:\s*"([^"]+)"').Matches.Groups[1].Value
        Write-Host ("  {0}:" -f $_.Name)
        if ($svc) {
            Write-Host ("    serviceUrl: {0}" -f $svc)
            Write-Host ("    itemUrl:    {0}" -f $item)
        } else {
            Write-Host "    extensionsGallery: (missing)"
        }
    }
}
Write-Host ""
Write-Host ""

# ============================================================
# 5. LiteLLM server connectivity
# ============================================================
Write-Host "============================================================"
Write-Host "  [5] LiteLLM server test"
Write-Host "============================================================"
Write-Host "  Server: http://100.252.201.200:8088/v1/models"
try {
    $resp = Invoke-RestMethod -Uri "http://100.252.201.200:8088/v1/models" -Method GET -TimeoutSec 10 -ErrorAction Stop
    Write-Host "  [OK] LiteLLM server responded"
    $models = $resp.data | ForEach-Object { $_.id }
    Write-Host ("  Available models: {0}" -f ($models -join ", "))
} catch {
    Write-Host "  [FAIL] Server unreachable: $_"
}
Write-Host ""
Write-Host ""

# ============================================================
# 6. Python / pip status
# ============================================================
Write-Host "============================================================"
Write-Host "  [6] Python / pip status"
Write-Host "============================================================"
$pyCmd = Get-Command python -ErrorAction SilentlyContinue
if ($pyCmd) {
    $pyVer = & python --version 2>&1
    Write-Host "  Python: $pyVer"
    Write-Host "  Path:   $($pyCmd.Source)"
} else {
    Write-Host "  Python NOT INSTALLED"
}

$pipCmd = Get-Command pip -ErrorAction SilentlyContinue
if ($pipCmd) {
    $pipVer = & pip --version 2>&1
    Write-Host "  pip: $pipVer"
} else {
    Write-Host "  pip NOT FOUND"
}

Write-Host ""
$pipIni = Join-Path $env:APPDATA "pip\pip.ini"
Write-Host "  pip config:"
if (Test-Path $pipIni) {
    Get-Content $pipIni -Raw
} else {
    Write-Host "    pip.ini NOT FOUND"
}
Write-Host ""
Write-Host ""

# ============================================================
# 7. Certificate status
# ============================================================
Write-Host "============================================================"
Write-Host "  [7] Gallery certificate"
Write-Host "============================================================"
$certs = Get-ChildItem Cert:\CurrentUser\Root | Where-Object { $_.Subject -match "100\.252\.201\.200" }
if ($certs) {
    $certs | ForEach-Object {
        Write-Host ("  Thumbprint: {0}" -f $_.Thumbprint)
        Write-Host ("  Subject:    {0}" -f $_.Subject)
    }
} else {
    Write-Host "  Certificate NOT FOUND in CurrentUser\Root"
}
Write-Host ""
Write-Host ""

# ============================================================
# Done
# ============================================================
Write-Host "============================================================"
Write-Host "  Diagnostic complete"
Write-Host "============================================================"
Write-Host ""
Write-Host "  Copy this entire output and send to your infra team."
Write-Host ""
Write-Host "  Additional info needed for troubleshooting:"
Write-Host "  1. Developer Tools logs"
Write-Host "     Help -> Toggle Developer Tools -> Console tab"
Write-Host "     (look for errors when sending a chat message)"
Write-Host "  2. Extension Host logs"
Write-Host "     Ctrl+Shift+P -> Developer: Show Logs -> Extension Host"
Write-Host ""
Read-Host "  Press Enter to exit"
