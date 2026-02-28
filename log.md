# 变更日志

## 2026-02-28
- Viewer 支持打开任意目录：后端新增 `POST /api/folders/open`，`resolve_folder_path` 放开绝对路径限制，并把手工打开目录纳入 `/api/folders` 返回列表。
- Viewer 顶栏新增路径输入框与 `Open / 打开` 按钮，可直接输入本机绝对路径或项目内相对路径切换浏览。
- 修复“直接点击复制提示词失败”：`copyText` 增加 `navigator.clipboard` 失败后的 `execCommand('copy')` 回退，并将弹窗复制按钮改为显式事件绑定。
- `.gitignore` 改为忽略 `good_outputs/` 与 `good_results/`，并已通过历史重写彻底移除对应目录的历史对象。
- 查看器新增输出目录切换能力：后端增加 `/api/folders`、`/api/image/{filename}`，并让 `/api/images`、`/api/metadata/{filename}` 支持 `folder` 参数。
- 查看器页面顶部新增 `Folder / 文件夹` 下拉，可在默认输出目录与 `good_outputs` 等目录之间切换浏览。
- `.gitignore` 显式放行 `good_outputs`（`!good_outputs/`、`!good_outputs/**`），确保该目录内容可被 Git 跟踪并同步到 GitHub。
- 修复查看器缩略图加载失败：卡片图片 URL 由固定拼接 `?w=500` 改为根据现有查询参数安全拼接，避免 `?folder=...?...` 造成图片 404。
- 增加 Electron 桌面壳：新增 `electron/` 主进程、预加载脚本与双面板壳页面，在单个桌面窗口内同时显示 Drawer 和 Viewer。
- 增加 `start-electron.ps1` 与 `package.json`（`electron:start`、`electron:dist`），支持本地启动与 Windows 安装包构建。
- 修复 Electron 安装不完整导致启动失败：`start-electron.ps1` 新增自检与自修复（检测 `node_modules/electron/path.txt` 与 `dist` 可执行文件，缺失时自动执行 `npm rebuild electron --foreground-scripts`）。
- 改进桌面壳启动流程：`start-electron.ps1` 在默认本地地址不可达时自动调用 `start.ps1 -NoOpenBrowser` 拉起后端，并在自定义 URL 不可达时直接报错。
- 修复 PowerShell 版本兼容问题：`start-electron.ps1` 不再通过 `powershell.exe`（5.1）中转执行 `start.ps1`，改为当前会话直接调用，避免 UTF-8 中文脚本解析异常。
- `start.ps1` 新增 `-NoOpenBrowser` 参数与 `Docker daemon` 前置检测，未启动 Docker Desktop 时给出明确错误提示。
- Electron 主进程新增后端自启动：默认 URL 不可达时自动探测运行目录并拉起 `start.ps1`，失败时弹窗提示并可手动重载。
- 打包配置新增 `extraResources/runtime-template`，将 Docker 运行所需脚本与后端文件打入安装包，并在打包版首次启动时复制到用户目录运行（避免安装目录写权限问题）。
- 新增统一应用图标：设计 `web/static/winddrawer-icon.svg`，并通过 `npm run icon:build` 生成 `web/static/favicon.png` 与 `build/icon.ico`；网页页签/页面 logo 与 Windows 打包 exe 图标全部切换为新图标。
- 文档补充桌面壳使用说明，并支持 `WINDDRAWER_DRAWER_URL` / `WINDDRAWER_VIEWER_URL` 覆盖地址。

## 2026-02-27
- 初始化 `agents.md`、`todo.md`、`log.md`。
- 增加指南、任务清单与日志记录的基础结构。
- 调整启动与构建配置：CUDA 镜像升级至 `12.8.0`，默认 CUDA 架构改为 `89;120`，并发编译默认 `4`。
- 修复 `sd-cli` 参数兼容：不再硬编码 `--diffusion-fa`，改为按 `--help` 动态检测后再追加，兼容新旧 stable-diffusion.cpp。
- 修复 Docker 拉取 `nvidia/cuda` 401 场景：应用镜像改为可配置基础镜像，启动脚本新增 CUDA 镜像源自动回退（`nvidia/cuda` -> `nvcr.io/nvidia/cuda`），并补充 `WINDDRAWER_DOCKER_BASE_IMAGE` 覆盖入口。
- 增加可配置宿主机模型目录：支持通过 `WINDDRAWER_HOST_MODEL_DIR` 挂载外部模型路径（例如 `D:\_code\models`），并在启动脚本中自动创建与导出该目录。
- 调整模型目录探测策略：Windows 启动脚本同时检测 `./models` 与 `D:\_code\models`（也可通过 `WINDDRAWER_HOST_MODEL_DIR`/`WINDDRAWER_HOST_MODEL_DIR_ALT` 覆盖），任一目录命中 `*.gguf` 即可启动。
