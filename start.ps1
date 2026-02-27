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

function Ensure-DockerImageAvailable {
    param([string]$Image)
    if (-not $Image -or -not $Image.Trim()) {
        return $false
    }
    & docker image inspect $Image *> $null
    if ($LASTEXITCODE -eq 0) {
        return $true
    }
    & docker pull $Image
    return ($LASTEXITCODE -eq 0)
}

function Resolve-ModelDirectory {
    param([string[]]$Candidates)

    $NormalizedCandidates = @()
    foreach ($Candidate in $Candidates) {
        if (-not $Candidate -or -not $Candidate.Trim()) {
            continue
        }
        $FullPath = [System.IO.Path]::GetFullPath($Candidate.Trim())
        if ($NormalizedCandidates -notcontains $FullPath) {
            $NormalizedCandidates += $FullPath
        }
    }

    if ($NormalizedCandidates.Count -eq 0) {
        throw "未提供可用的模型目录候选路径。"
    }

    $HitDirs = @()
    foreach ($Dir in $NormalizedCandidates) {
        if (-not (Test-Path -Path $Dir -PathType Container)) {
            continue
        }
        $Count = (Get-ChildItem -Path $Dir -Filter *.gguf -File -ErrorAction SilentlyContinue | Measure-Object).Count
        if ($Count -gt 0) {
            $HitDirs += $Dir
        }
    }

    $SelectedDir = if ($HitDirs.Count -gt 0) { $HitDirs[0] } else { $NormalizedCandidates[0] }
    return [PSCustomObject]@{
        SelectedDir = $SelectedDir
        CandidateDirs = $NormalizedCandidates
        HitDirs = $HitDirs
    }
}

if (-not (Get-Command "docker" -ErrorAction SilentlyContinue)) {
    $DockerBin = "C:\Program Files\Docker\Docker\resources\bin"
    if (Test-Path (Join-Path $DockerBin "docker.exe")) {
        $env:Path = "$DockerBin;$env:Path"
    }
}

Require-Command -Name "docker" -Hint "请先安装 Docker Desktop 并确认 `docker` 在 PATH 中。"

$RootDir = $PSScriptRoot
$DefaultModelsDir = Join-Path $RootDir "models"
$DefaultExternalModelsDir = "D:\_code\models"
$PreferredModelsDir = if ($env:WINDDRAWER_HOST_MODEL_DIR -and $env:WINDDRAWER_HOST_MODEL_DIR.Trim()) { $env:WINDDRAWER_HOST_MODEL_DIR.Trim() } else { $null }
$ExtraModelsDir = if ($env:WINDDRAWER_HOST_MODEL_DIR_ALT -and $env:WINDDRAWER_HOST_MODEL_DIR_ALT.Trim()) { $env:WINDDRAWER_HOST_MODEL_DIR_ALT.Trim() } else { $DefaultExternalModelsDir }
$ModelProbe = Resolve-ModelDirectory -Candidates @($PreferredModelsDir, $DefaultModelsDir, $ExtraModelsDir)
$ModelsDir = $ModelProbe.SelectedDir
$OutputsDir = Join-Path $RootDir "outputs"
$SdCppDir = Join-Path $RootDir "stable-diffusion.cpp"
$SdCliPath = Join-Path $SdCppDir "build-linux/bin/sd-cli"
$BuildStampPath = Join-Path $SdCppDir "build-linux/.winddrawer_build_info"

$CudaImageTag = if ($env:WINDDRAWER_CUDA_IMAGE_TAG -and $env:WINDDRAWER_CUDA_IMAGE_TAG.Trim()) { $env:WINDDRAWER_CUDA_IMAGE_TAG.Trim() } else { "12.8.0" }
$ExplicitCudaImageRepo = if ($env:WINDDRAWER_CUDA_IMAGE_REPO -and $env:WINDDRAWER_CUDA_IMAGE_REPO.Trim()) { $env:WINDDRAWER_CUDA_IMAGE_REPO.Trim() } else { $null }
$ExplicitDockerBaseImage = if ($env:WINDDRAWER_DOCKER_BASE_IMAGE -and $env:WINDDRAWER_DOCKER_BASE_IMAGE.Trim()) { $env:WINDDRAWER_DOCKER_BASE_IMAGE.Trim() } else { $null }
$CudaImageRepo = if ($ExplicitCudaImageRepo) { $ExplicitCudaImageRepo } else { "nvidia/cuda" }
$CudaArchs = if ($env:WINDDRAWER_CUDA_ARCHS -and $env:WINDDRAWER_CUDA_ARCHS.Trim()) { $env:WINDDRAWER_CUDA_ARCHS.Trim() } else { "89;120" }
$BuildJobs = 4
if ($env:WINDDRAWER_BUILD_JOBS -and $env:WINDDRAWER_BUILD_JOBS -match '^\d+$') {
    $ParsedJobs = [int]$env:WINDDRAWER_BUILD_JOBS
    if ($ParsedJobs -ge 1) {
        $BuildJobs = $ParsedJobs
    }
}
$DesiredBuildStamp = "cuda_image_tag=$CudaImageTag`ncuda_archs=$CudaArchs"

if (-not $ExplicitCudaImageRepo -and -not $ExplicitDockerBaseImage) {
    $DefaultRuntimeImage = "nvidia/cuda:${CudaImageTag}-runtime-ubuntu22.04"
    Write-Host "[检测] 正在验证 CUDA runtime 镜像可用性..." -ForegroundColor Gray
    if (-not (Ensure-DockerImageAvailable -Image $DefaultRuntimeImage)) {
        $FallbackRepo = "nvcr.io/nvidia/cuda"
        $FallbackRuntimeImage = "${FallbackRepo}:${CudaImageTag}-runtime-ubuntu22.04"
        if (Ensure-DockerImageAvailable -Image $FallbackRuntimeImage) {
            Write-Host "[提示] Docker Hub CUDA runtime 镜像不可用，自动切换为 nvcr.io 源。" -ForegroundColor Yellow
            $CudaImageRepo = $FallbackRepo
        }
        else {
            throw "无法访问 CUDA runtime 镜像，请设置 `WINDDRAWER_DOCKER_BASE_IMAGE` 或修复 Docker 镜像源后重试。"
        }
    }
}

$CudaRuntimeImage = "${CudaImageRepo}:${CudaImageTag}-runtime-ubuntu22.04"
$CudaDevelImage = "${CudaImageRepo}:${CudaImageTag}-devel-ubuntu22.04"
$CudaBaseImage = "${CudaImageRepo}:${CudaImageTag}-base-ubuntu22.04"
$DockerBaseImage = if ($ExplicitDockerBaseImage) { $ExplicitDockerBaseImage } else { $CudaRuntimeImage }
$ShouldExportDockerBaseImage = [bool]$ExplicitDockerBaseImage -or ($CudaImageRepo -ne "nvidia/cuda")
if ($ShouldExportDockerBaseImage) {
    $env:WINDDRAWER_DOCKER_BASE_IMAGE = $DockerBaseImage
}

Write-Host "------------------------------------" -ForegroundColor Cyan
Write-Host "   WindDrawer Docker 一键启动脚本   " -ForegroundColor Cyan
Write-Host "------------------------------------" -ForegroundColor Cyan
Write-Host "[配置] CUDA 仓库: $CudaImageRepo" -ForegroundColor DarkGray
Write-Host "[配置] 构建基础镜像: $DockerBaseImage" -ForegroundColor DarkGray
Write-Host "[配置] 模型目录: $ModelsDir" -ForegroundColor DarkGray
Write-Host "[配置] 模型候选目录: $($ModelProbe.CandidateDirs -join '; ')" -ForegroundColor DarkGray
if ($ModelProbe.HitDirs.Count -gt 1) {
    Write-Host "[提示] 检测到多个模型目录命中，当前优先使用: $ModelsDir" -ForegroundColor Yellow
}

New-Item -ItemType Directory -Path $ModelsDir -Force | Out-Null
New-Item -ItemType Directory -Path $OutputsDir -Force | Out-Null
$env:WINDDRAWER_HOST_MODEL_DIR = $ModelsDir

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


$NeedBuild = -not (Test-Path $SdCliPath)
if (-not $NeedBuild -and -not (Test-Path $BuildStampPath)) {
    $NeedBuild = $true
}
if (-not $NeedBuild) {
    $CurrentBuildStamp = Get-Content -LiteralPath $BuildStampPath -Raw
    if ($CurrentBuildStamp.Trim() -ne $DesiredBuildStamp.Trim()) {
        $NeedBuild = $true
    }
}

if ($NeedBuild) {
    Write-Host "[编译] 未找到可复用的 CUDA 版 sd-cli，开始在 Docker 中编译..." -ForegroundColor Gray
    Write-Host "  CUDA 镜像: $CudaImageTag, 架构: $CudaArchs, 并发: $BuildJobs" -ForegroundColor DarkGray
    $BuildCmd = @"
apt-get update && \
apt-get install -y --no-install-recommends build-essential cmake git && \
cmake -S . -B build-linux -DCMAKE_BUILD_TYPE=Release -DSD_CUDA=ON "-DCMAKE_CUDA_ARCHITECTURES=$CudaArchs" && \
cmake --build build-linux --config Release --parallel $BuildJobs --target sd-cli
"@
    $SdCppMount = (Resolve-Path $SdCppDir).Path -replace "\\", "/"
    $DockerArgs = @(
        "run", "--rm",
        "-v", "${SdCppMount}:/sd.cpp",
        "-w", "/sd.cpp",
        $CudaDevelImage,
        "bash", "-lc", $BuildCmd
    )
    & docker @DockerArgs
    if ($LASTEXITCODE -ne 0) {
        throw "sd-cli 编译失败，请执行 `docker compose logs -f drawer` 查看更多信息。"
    }
    if (-not (Test-Path $SdCliPath)) {
        throw "sd-cli 编译命令已执行，但未找到产物: $SdCliPath"
    }
    New-Item -ItemType Directory -Path (Split-Path -Path $BuildStampPath -Parent) -Force | Out-Null
    Set-Content -LiteralPath $BuildStampPath -Value $DesiredBuildStamp -NoNewline
}

$MatchedModelDirs = $ModelProbe.HitDirs
if ($MatchedModelDirs.Count -eq 0) {
    Write-Host "[提示] 未在以下目录找到 GGUF 模型：$($ModelProbe.CandidateDirs -join '; ')" -ForegroundColor Yellow
    Write-Host "      请在任一目录放入模型后重试。" -ForegroundColor Yellow
}

if (-not (Test-Path ".env") -and (Test-Path ".env.example")) {
    Copy-Item ".env.example" ".env"
}

$GpuCheckCmd = @(
    "run", "--rm", "--gpus", "all",
    $CudaBaseImage,
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
