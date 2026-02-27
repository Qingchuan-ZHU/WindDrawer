# WindDrawer (GPU Docker Only)

本项目现在只提供 **GPU Docker** 运行方式（NVIDIA）。

## 一键启动

### Windows
```powershell
.\start.ps1
```

### Ubuntu
```bash
bash ./start.sh
```

脚本会自动执行：

1. 创建 `models/`、`outputs/`
2. 首次自动拉取 `stable-diffusion.cpp`
3. 自动编译 **CUDA 版** `sd-cli`（`-DSD_CUDA=ON`）
4. 验证 `docker --gpus all` 可用
5. `docker compose up -d --build`

## 访问地址

- Drawer: `http://127.0.0.1:17865`
- Viewer: `http://127.0.0.1:17866`

## 前置条件

- NVIDIA 显卡 + 最新驱动
- Docker Desktop（Windows）或 Docker Engine + NVIDIA Container Toolkit（Ubuntu）
- Git（首次自动拉取 `stable-diffusion.cpp`）

## Docker 安装

### Windows（推荐）
```powershell
winget install -e --id Docker.DockerDesktop --accept-source-agreements --accept-package-agreements --silent
```

### Ubuntu（示例）
请按 Docker 官方文档安装 Docker Engine，并安装 NVIDIA Container Toolkit。

## GPU 验证

```bash
docker run --rm --gpus all nvidia/cuda:12.8.0-base-ubuntu22.04 nvidia-smi
```

如果能看到 GPU 信息，说明 Docker GPU 通路正常。

## 编译参数（可选）

`start.ps1` / `start.sh` 支持以下环境变量：

- `WINDDRAWER_CUDA_IMAGE_TAG`：默认 `12.8.0`
- `WINDDRAWER_CUDA_ARCHS`：默认 `89;120`（兼容 RTX 4070 Ti Super 与 RTX 5060）
- `WINDDRAWER_BUILD_JOBS`：默认 `4`

## 模型文件

把模型放到仓库内 `models/`：

- `Qwen3-4B-Instruct-2507-Q4_K_S-4.31bpw.gguf`
- `ae-Q8_0.gguf`
- 至少一个扩散模型（如 `z-image-turbo-*.gguf`）

## 常用命令

启动：
```bash
docker compose up -d --build
```

日志：
```bash
docker compose logs -f drawer
docker compose logs -f viewer
```

停止：
```bash
docker compose down
```

## 环境变量 (`.env`)

```env
WINDDRAWER_SD_CLI=/app/stable-diffusion.cpp/build-linux/bin/sd-cli
WINDDRAWER_QWEN_PATH=/app/models/Qwen3-4B-Instruct-2507-Q4_K_S-4.31bpw.gguf
WINDDRAWER_VAE_PATH=/app/models/ae-Q8_0.gguf
```
