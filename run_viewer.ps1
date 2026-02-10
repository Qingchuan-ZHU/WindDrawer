# 设置工作目录为脚本所在文件夹
Set-Location -Path $PSScriptRoot

# 定义服务地址 (使用与主应用不同的端口，例如 17866)
$url = "http://127.0.0.1:17866"

# 自动打开默认浏览器访问指定地址
Write-Host "正在启动浏览器并访问 $url ..."
Start-Process $url

# 启动 FastAPI 服务
# 使用 uv run uvicorn 运行 viewer_app:app
uv run uvicorn viewer_app:app --host 127.0.0.1 --port 17866

# 防止窗口闪退
Read-Host -Prompt "服务已停止，按回车键退出..."
