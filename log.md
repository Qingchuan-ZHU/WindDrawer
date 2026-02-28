# 变更日志

## 2026-02-28
- 查看器新增输出目录切换能力：后端增加 `/api/folders`、`/api/image/{filename}`，并让 `/api/images`、`/api/metadata/{filename}` 支持 `folder` 参数。
- 查看器页面顶部新增 `Folder / 文件夹` 下拉，可在默认输出目录与 `good_outputs` 等目录之间切换浏览。
- `.gitignore` 显式放行 `good_outputs`（`!good_outputs/`、`!good_outputs/**`），确保该目录内容可被 Git 跟踪并同步到 GitHub。
- 修复查看器缩略图加载失败：卡片图片 URL 由固定拼接 `?w=500` 改为根据现有查询参数安全拼接，避免 `?folder=...?...` 造成图片 404。
- 增加 Electron 桌面壳：新增 `electron/` 主进程、预加载脚本与双面板壳页面，在单个桌面窗口内同时显示 Drawer 和 Viewer。
- 增加 `start-electron.ps1` 与 `package.json`（`electron:start`、`electron:dist`），支持本地启动与 Windows 安装包构建。
- 文档补充桌面壳使用说明，并支持 `WINDDRAWER_DRAWER_URL` / `WINDDRAWER_VIEWER_URL` 覆盖地址。

## 2026-02-27
- 初始化 `agents.md`、`todo.md`、`log.md`。
- 增加指南、任务清单与日志记录的基础结构。
- 调整启动与构建配置：CUDA 镜像升级至 `12.8.0`，默认 CUDA 架构改为 `89;120`，并发编译默认 `4`。
- 修复 `sd-cli` 参数兼容：不再硬编码 `--diffusion-fa`，改为按 `--help` 动态检测后再追加，兼容新旧 stable-diffusion.cpp。
- 修复 Docker 拉取 `nvidia/cuda` 401 场景：应用镜像改为可配置基础镜像，启动脚本新增 CUDA 镜像源自动回退（`nvidia/cuda` -> `nvcr.io/nvidia/cuda`），并补充 `WINDDRAWER_DOCKER_BASE_IMAGE` 覆盖入口。
- 增加可配置宿主机模型目录：支持通过 `WINDDRAWER_HOST_MODEL_DIR` 挂载外部模型路径（例如 `D:\_code\models`），并在启动脚本中自动创建与导出该目录。
- 调整模型目录探测策略：Windows 启动脚本同时检测 `./models` 与 `D:\_code\models`（也可通过 `WINDDRAWER_HOST_MODEL_DIR`/`WINDDRAWER_HOST_MODEL_DIR_ALT` 覆盖），任一目录命中 `*.gguf` 即可启动。
