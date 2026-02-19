# 设置工作目录为脚本所在目录
Set-Location -Path $PSScriptRoot

# 配置应用信息：名称、端口、启动命令
$Apps = @(
    @{ Name = "WindDrawer 主服务"; Port = 17865; Command = "uv run uvicorn app_fastapi:app --host 127.0.0.1 --port 17865" },
    @{ Name = "WindDrawer 预览服务"; Port = 17866; Command = "uv run uvicorn viewer_app:app --host 127.0.0.1 --port 17866" }
)

# 函数：清理指定端口的进程
function Stop-PortOccupation {
    param([int]$Port)
    $connections = Get-NetTCPConnection -LocalPort $Port -State Listen -ErrorAction SilentlyContinue
    if ($connections) {
        foreach ($conn in $connections) {
            $targetPid = $conn.OwningProcess
            $process = Get-Process -Id $targetPid -ErrorAction SilentlyContinue
            if ($process) {
                Write-Host "[清理] 发现端口 $Port 被 $($process.Name) (PID: $targetPid) 占用，正在结束进程..." -ForegroundColor Yellow
                Stop-Process -Id $targetPid -Force -ErrorAction SilentlyContinue
            }
        }
    }
}

# 基础检查：确保 uv 可用
if (!(Get-Command "uv" -ErrorAction SilentlyContinue)) {
    Write-Host "[错误] 未找到 uv 命令，请确保已安装 uv 且已添加到环境变量。" -ForegroundColor Red
    Read-Host "按回车键退出..."
    exit
}

Write-Host "------------------------------------" -ForegroundColor Cyan
Write-Host "       WindDrawer 无感启动脚本       " -ForegroundColor Cyan
Write-Host "------------------------------------" -ForegroundColor Cyan

foreach ($app in $Apps) {
    # 1. 清理端口
    Stop-PortOccupation -Port $app.Port
    
    # 2. 无感启动应用 (隐藏窗口并在后台运行)
    # 使用 Start-Process 启动 cmd 并执行命令，设置 WindowStyle 为 Hidden 实现无感
    $CommandArgs = "/c " + $app.Command
    Write-Host "[启动] 正在启动 $($app.Name)..." -ForegroundColor Gray
    Start-Process -FilePath "cmd.exe" -ArgumentList $CommandArgs -WindowStyle Hidden
}

# 3. 等待并检查服务是否就绪
$MainPort = 17865
$MainUrl = "http://127.0.0.1:$MainPort"
Write-Host "[检测] 正在等待服务就绪..." -ForegroundColor Cyan

$RetryCount = 0
$MaxRetries = 15
$ServiceReady = $false

while ($RetryCount -lt $MaxRetries) {
    if (Test-NetConnection -ComputerName 127.0.0.1 -Port $MainPort -InformationLevel Quiet) {
        $ServiceReady = $true
        break
    }
    Write-Host "." -NoNewline
    Start-Sleep -Seconds 1
    $RetryCount++
}

if ($ServiceReady) {
    Write-Host "`n[成功] 服务已就绪，正在打开浏览器..." -ForegroundColor Green
    
    $ViewerUrl = "http://127.0.0.1:17866"
    
    # 尝试多种方式打开浏览器，确保成功
    try {
        # 先打开预览应用 (Viewer)
        Start-Process "explorer.exe" $ViewerUrl
        Start-Sleep -Milliseconds 500
        # 后打开主应用 (Drawer)，确保它是最后打开的（即当前激活的标签页）
        Start-Process "explorer.exe" $MainUrl
    }
    catch {
        Start-Process $ViewerUrl
        Start-Sleep -Milliseconds 500
        Start-Process $MainUrl
    }
}
else {
    Write-Host "`n[超时] 服务启动时间过长，请检查后台进程是否异常。" -ForegroundColor Red
}

Write-Host "------------------------------------" -ForegroundColor Cyan
Write-Host "本窗口将在 3 秒后关闭。" -ForegroundColor Gray
Start-Sleep -Seconds 3
