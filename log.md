# 变更日志

## 2026-02-27
- 初始化 `agents.md`、`todo.md`、`log.md`。
- 增加指南、任务清单与日志记录的基础结构。
- 调整启动与构建配置：CUDA 镜像升级至 `12.8.0`，默认 CUDA 架构改为 `89;120`，并发编译默认 `4`。
- 修复 `sd-cli` 参数兼容：不再硬编码 `--diffusion-fa`，改为按 `--help` 动态检测后再追加，兼容新旧 stable-diffusion.cpp。
- 修复 Docker 拉取 `nvidia/cuda` 401 场景：应用镜像改为可配置基础镜像，启动脚本新增 CUDA 镜像源自动回退（`nvidia/cuda` -> `nvcr.io/nvidia/cuda`），并补充 `WINDDRAWER_DOCKER_BASE_IMAGE` 覆盖入口。
- 增加可配置宿主机模型目录：支持通过 `WINDDRAWER_HOST_MODEL_DIR` 挂载外部模型路径（例如 `D:\_code\models`），并在启动脚本中自动创建与导出该目录。
- 调整模型目录探测策略：Windows 启动脚本同时检测 `./models` 与 `D:\_code\models`（也可通过 `WINDDRAWER_HOST_MODEL_DIR`/`WINDDRAWER_HOST_MODEL_DIR_ALT` 覆盖），任一目录命中 `*.gguf` 即可启动。
