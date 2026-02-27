# 变更日志

## 2026-02-27
- 初始化 `agents.md`、`todo.md`、`log.md`。
- 增加指南、任务清单与日志记录的基础结构。
- 调整启动与构建配置：CUDA 镜像升级至 `12.8.0`，默认 CUDA 架构改为 `89;120`，并发编译默认 `4`。
- 修复 `sd-cli` 参数兼容：不再硬编码 `--diffusion-fa`，改为按 `--help` 动态检测后再追加，兼容新旧 stable-diffusion.cpp。
