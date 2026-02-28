Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"
Set-Location -Path $PSScriptRoot

function Normalize-Url {
    param([string]$Value, [string]$Fallback)
    $raw = if ($Value) { $Value.Trim() } else { "" }
    if (-not $raw) {
        return $Fallback
    }
    if ($raw.EndsWith("/")) {
        return $raw
    }
    return "$raw/"
}

function Wait-HttpReady {
    param([string]$Url, [int]$TimeoutSec = 120)
    for ($i = 0; $i -lt $TimeoutSec; $i++) {
        try {
            $resp = Invoke-WebRequest -Uri $Url -TimeoutSec 5 -UseBasicParsing
            if ($resp.StatusCode -ge 200 -and $resp.StatusCode -lt 500) {
                return $true
            }
        }
        catch {}
        Start-Sleep -Seconds 1
    }
    return $false
}

function Is-UrlReady {
    param([string]$Url)
    try {
        $resp = Invoke-WebRequest -Uri $Url -TimeoutSec 3 -UseBasicParsing
        return ($resp.StatusCode -ge 200 -and $resp.StatusCode -lt 500)
    }
    catch {
        return $false
    }
}

if (-not (Get-Command "node" -ErrorAction SilentlyContinue)) {
    Write-Host "[ERROR] Node.js not found. Please install Node.js LTS first." -ForegroundColor Red
    exit 1
}

if (-not (Get-Command "npm" -ErrorAction SilentlyContinue)) {
    Write-Host "[ERROR] npm not found. Please verify your Node.js install." -ForegroundColor Red
    exit 1
}

if (-not (Test-Path "package.json")) {
    Write-Host "[ERROR] package.json not found. Cannot start Electron." -ForegroundColor Red
    exit 1
}

if (-not (Test-Path "node_modules")) {
    Write-Host "[Setup] Installing Electron dependencies..." -ForegroundColor Gray
    & npm install
    if ($LASTEXITCODE -ne 0) {
        throw "npm install failed."
    }
}

$electronPkgDir = Join-Path -Path $PSScriptRoot -ChildPath "node_modules/electron"
$electronPathFile = Join-Path -Path $electronPkgDir -ChildPath "path.txt"
$needsElectronRepair = $false

if (-not (Test-Path $electronPkgDir)) {
    Write-Host "[Setup] electron package missing. Installing dependencies..." -ForegroundColor Gray
    & npm install
    if ($LASTEXITCODE -ne 0) {
        throw "npm install failed."
    }
}

if (-not (Test-Path $electronPathFile)) {
    $needsElectronRepair = $true
} else {
    $electronBinaryName = (Get-Content -Raw $electronPathFile).Trim()
    if ([string]::IsNullOrWhiteSpace($electronBinaryName)) {
        $needsElectronRepair = $true
    } else {
        $electronBinaryPath = Join-Path -Path $electronPkgDir -ChildPath ("dist/" + $electronBinaryName)
        if (-not (Test-Path $electronBinaryPath)) {
            $needsElectronRepair = $true
        }
    }
}

if ($needsElectronRepair) {
    Write-Host "[Setup] Repairing Electron runtime..." -ForegroundColor Gray
    & npm rebuild electron --foreground-scripts
    if ($LASTEXITCODE -ne 0) {
        throw "npm rebuild electron failed."
    }
}

$defaultDrawerUrl = "http://127.0.0.1:17865/"
$defaultViewerUrl = "http://127.0.0.1:17866/"
$drawerUrl = Normalize-Url -Value $env:WINDDRAWER_DRAWER_URL -Fallback $defaultDrawerUrl
$viewerUrl = Normalize-Url -Value $env:WINDDRAWER_VIEWER_URL -Fallback $defaultViewerUrl

$drawerHealthUrl = "$($drawerUrl.TrimEnd('/'))/api/models"
$viewerHealthUrl = "$($viewerUrl.TrimEnd('/'))/api/images"

$drawerReady = Is-UrlReady -Url $drawerHealthUrl
$viewerReady = Is-UrlReady -Url $viewerHealthUrl

if (-not ($drawerReady -and $viewerReady)) {
    if ($drawerUrl -eq $defaultDrawerUrl -and $viewerUrl -eq $defaultViewerUrl) {
        $backendScript = Join-Path -Path $PSScriptRoot -ChildPath "start.ps1"
        if (-not (Test-Path $backendScript)) {
            throw "Backend bootstrap script not found: $backendScript"
        }

        Write-Host "[Setup] Drawer/Viewer not ready. Starting backend via start.ps1..." -ForegroundColor Gray
        try {
            & $backendScript -NoOpenBrowser
        }
        catch {
            throw "start.ps1 failed to start backend services. $($_.Exception.Message)"
        }

        $drawerReady = Wait-HttpReady -Url $drawerHealthUrl -TimeoutSec 120
        $viewerReady = Wait-HttpReady -Url $viewerHealthUrl -TimeoutSec 120
        if (-not ($drawerReady -and $viewerReady)) {
            throw "Backend services are still not reachable. Drawer: $drawerHealthUrl ; Viewer: $viewerHealthUrl"
        }
    }
    else {
        throw "Configured URLs are not reachable. Drawer: $drawerHealthUrl ; Viewer: $viewerHealthUrl"
    }
}

if (Test-Path Env:ELECTRON_RUN_AS_NODE) {
    Remove-Item Env:ELECTRON_RUN_AS_NODE -ErrorAction SilentlyContinue
}

Write-Host "[Start] WindDrawer Desktop..." -ForegroundColor Green
& npm run electron:start
