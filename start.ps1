Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"
Set-Location -Path $PSScriptRoot

function Require-Command {
    param([string]$Name, [string]$Hint)
    if (-not (Get-Command $Name -ErrorAction SilentlyContinue)) {
        Write-Host "[错误] 未找到命令: $Name" -ForegroundColor Red
        Write-Host $Hint -ForegroundColor Yellow
        exit 1
    }
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

if (-not (Get-Command "docker" -ErrorAction SilentlyContinue)) {
    $DockerBin = "C:\Program Files\Docker\Docker\resources\bin"
    if (Test-Path (Join-Path $DockerBin "docker.exe")) {
        $env:Path = "$DockerBin;$env:Path"
    }
}

Require-Command -Name "docker" -Hint "请先安装 Docker Desktop 并确认 `docker` 在 PATH 中。"

$RootDir = $PSScriptRoot
$ModelsDir = Join-Path $RootDir "models"
$OutputsDir = Join-Path $RootDir "outputs"
$SdCppDir = Join-Path $RootDir "stable-diffusion.cpp"
$SdCliPath = Join-Path $SdCppDir "build-linux/bin/sd-cli"

Write-Host "------------------------------------" -ForegroundColor Cyan
Write-Host "   WindDrawer Docker 一键启动脚本   " -ForegroundColor Cyan
Write-Host "------------------------------------" -ForegroundColor Cyan

New-Item -ItemType Directory -Path $ModelsDir -Force | Out-Null
New-Item -ItemType Directory -Path $OutputsDir -Force | Out-Null

if (-not (Test-Path $SdCppDir)) {
    Require-Command -Name "git" -Hint "首次启动需要自动拉取 stable-diffusion.cpp，请先安装 Git。"
    Write-Host "[准备] 首次运行，正在拉取 stable-diffusion.cpp..." -ForegroundColor Gray
    & git clone --recursive https://github.com/leejet/stable-diffusion.cpp $SdCppDir
    if ($LASTEXITCODE -ne 0) {
        throw "拉取 stable-diffusion.cpp 失败。"
    }
}

if (-not (Test-Path (Join-Path $SdCppDir "CMakeLists.txt"))) {
    throw "stable-diffusion.cpp 目录异常，请检查: $SdCppDir"
}

if (-not (Test-Path $SdCliPath)) {
    Write-Host "[编译] 未找到 CUDA 版 sd-cli，开始在 Docker 中编译..." -ForegroundColor Gray
    $BuildCmd = @"
apt-get update && \
apt-get install -y --no-install-recommends build-essential cmake git && \
cmake -S . -B build-linux -DCMAKE_BUILD_TYPE=Release -DSD_CUDA=ON && \
cmake --build build-linux --config Release --parallel --target sd-cli
"@
    $SdCppMount = (Resolve-Path $SdCppDir).Path -replace "\\", "/"
    $DockerArgs = @(
        "run", "--rm",
        "-v", "${SdCppMount}:/sd.cpp",
        "-w", "/sd.cpp",
        "nvidia/cuda:12.4.1-devel-ubuntu22.04",
        "bash", "-lc", $BuildCmd
    )
    & docker @DockerArgs
    if ($LASTEXITCODE -ne 0) {
        throw "sd-cli 编译失败，请执行 `docker compose logs -f drawer` 查看更多信息。"
    }
    if (-not (Test-Path $SdCliPath)) {
        throw "sd-cli 编译命令已执行，但未找到产物: $SdCliPath"
    }
}

$ModelCount = (Get-ChildItem -Path $ModelsDir -Filter *.gguf -File -ErrorAction SilentlyContinue | Measure-Object).Count
if ($ModelCount -eq 0) {
    Write-Host "[提示] models/ 目录当前为空。请放入 GGUF 模型后再进行生图。" -ForegroundColor Yellow
}

if (-not (Test-Path ".env") -and (Test-Path ".env.example")) {
    Copy-Item ".env.example" ".env"
}

$GpuCheckCmd = @(
    "run", "--rm", "--gpus", "all",
    "nvidia/cuda:12.4.1-base-ubuntu22.04",
    "nvidia-smi"
)
Write-Host "[检测] 正在验证 Docker GPU 可用性..." -ForegroundColor Gray
& docker @GpuCheckCmd | Out-Null
if ($LASTEXITCODE -ne 0) {
    throw "Docker GPU 不可用。请在 Docker Desktop 中启用 WSL2/GPU 支持，并确认 NVIDIA 驱动正常。"
}

Write-Host "[启动] 正在启动 WindDrawer 容器..." -ForegroundColor Gray
& docker compose up -d --build
if ($LASTEXITCODE -ne 0) {
    throw "docker compose 启动失败。"
}

$MainUrl = "http://127.0.0.1:17865"
$ViewerUrl = "http://127.0.0.1:17866"
Write-Host "[检测] 正在等待服务就绪..." -ForegroundColor Gray

$DrawerReady = Wait-HttpReady -Url "$MainUrl/api/models" -TimeoutSec 120
$ViewerReady = Wait-HttpReady -Url "$ViewerUrl/api/images" -TimeoutSec 120

if ($DrawerReady -and $ViewerReady) {
    Write-Host "[成功] 服务已就绪:" -ForegroundColor Green
    Write-Host "  Drawer: $MainUrl"
    Write-Host "  Viewer: $ViewerUrl"

    try {
        Start-Process "explorer.exe" $ViewerUrl
        Start-Sleep -Milliseconds 500
        Start-Process "explorer.exe" $MainUrl
    }
    catch {
        Start-Process $ViewerUrl
        Start-Sleep -Milliseconds 500
        Start-Process $MainUrl
    }
}
else {
    Write-Host "[超时] 服务未在预期时间内就绪，请查看日志：" -ForegroundColor Red
    Write-Host "  docker compose logs -f drawer"
    Write-Host "  docker compose logs -f viewer"
    exit 1
}
