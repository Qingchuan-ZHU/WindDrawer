# 设置工作目录为脚本所在文件夹
Set-Location -Path $PSScriptRoot

# 定义服务地址
$url = "http://127.0.0.1:17865"

# 自动打开默认浏览器访问指定地址
Write-Host "正在启动浏览器并访问 $url ..."
Start-Process $url

# 启动 FastAPI 服务
# 移除了 --with-requirements 以避免重复检查依赖
uv run uvicorn app_fastapi:app --host 127.0.0.1 --port 17865

# 防止窗口闪退
Read-Host -Prompt "服务已停止，按回车键退出..."