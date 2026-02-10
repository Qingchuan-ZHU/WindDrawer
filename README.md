# 风语画笺 (WindDrawer): Local AI Image Generation Platform / 本地影像生成系统

---

## Contact & Credits / 联系与鸣谢

- **Blog**: [QingChuan's Blog](https://qingchuan-zhu-github-io.pages.dev/)
- **Social Media / 社交媒体 (风语幻镜)**: 
  - [YouTube](https://www.youtube.com/@WindWhisperer_Stories)
  - 微信公众号 / 抖音 / Bilibili / 小红书 / 快手 / 百家号: **风语幻镜**
- **Acknowledgment**: Thanks to [Tongyi-MAI/Z-Image](https://github.com/Tongyi-MAI/Z-Image) for the excellent model and technical guidance.

---


**FastAPI + Vanilla JS + stable-diffusion.cpp**

![Main Generation UI](./screenshot/main.png)
*Image Generation Workspace / 生图工作台主界面*

A lightweight, local image generation workbench. Designed as two independent applications: one for dedicated image creation/generation, and another for convenient metadata viewing with a waterfall layout.


一个基于 **FastAPI + 原生前端 + stable-diffusion.cpp** 的本地影像生成系统。系统设计为两个独立的应用：一个负责极致的生图创作（影像生成工作台），另一个负责便捷的元数据浏览与瀑布流展示（拾光查看器）。

## Directory Structure / 目录概览

```
WindDrawer/
├── models/                # (Optional) Local weights / 本地模型权重
├── ... (other files)
└── (Default Model path: D:\_code\models)
├── outputs/               # Render outputs / 渲染输出 (Auto-created, PNG with metadata)
├── app_fastapi.py         # Generation Backend / 生图后端 (SSE + Async Rendering)
├── viewer_app.py          # Viewer Backend / 查看器后端
├── web/                   # Frontend / 前端
│   ├── index.html         # Generation UI / 生图工作台
│   └── viewer.html        # Viewer UI / 元数据查看器
├── run_generation.ps1     # 1-Click Start Generation / 生图工作台一键启动
├── run_viewer.ps1         # 1-Click Start Viewer / 元数据查看器一键启动
├── pyproject.toml         # Dependencies / 依赖配置
└── uv.lock                # Lock file / 锁定文件
```

## Prerequisites / 环境准备

We recommend using [uv](https://github.com/astral-sh/uv) for fast environment management.
本项目推荐使用 [uv](https://github.com/astral-sh/uv) 进行极速环境管理与运行。

1. **Install uv / 安装 uv**:
   Windows (PowerShell):
   ```powershell
   powershell -c "irm https://astral.sh/uv/install.ps1 | iex"
   ```

2. **Python Version**:
   Project requires Python 3.10+. `uv` will manage Python versions and virtual environments automatically.
   本项目指定使用 Python 3.10+。`uv` 会自动为你管理 Python 版本与虚拟环境，无需手动安装 Anaconda。

3. **Install Dependencies / 安装依赖**:
   Dependencies are synced automatically on first run, or manually via:
   首次运行会自动同步，也可手动执行：
   ```powershell
   uv sync
   ```

4. **GPU Drivers / 显卡驱动**:
   - NVIDIA: Driver version 535+.
   - AMD/Intel: Refer to stable-diffusion.cpp official docs.

## Quick Start / 运行项目

This project provides two entry points that can run simultaneously on different ports.
本项目提供两个入口，可同时运行在同一个局域网内不同的端口上。双击以下 `.ps1` 脚本即可直接启动。

### 1. 影像生成工作台 (Generation Workspace)
- **Script**: `.\run_generation.ps1`
- **Files**: `app_fastapi.py`, `web/index.html`, `web/static/app.js`
- **URL**: `http://127.0.0.1:17865`
- **Features**: Minimalist UI, aspect ratio switching, dynamic model loading, real-time SSE logs, instant gallery.
- **核心功能**：极简界面，支持画幅比例切换、多模型动态加载、实时日志推送、逐张结果追加入库。

### 2. 拾光查看器 (Metadata Viewer)
- **Script**: `.\run_viewer.ps1`
- **Files**: `viewer_app.py`, `web/viewer.html`
- **URL**: `http://127.0.0.1:17866`
- **Features**:
    - **Waterfall Layout**: Chronological Masonry layout. / 瀑布流展示。
    - **Instant Preview**: Reads embedded metadata from PNGs. / 极速预览。
    - **One-Click Copy**: Click **Seed** or **Prompt** on cards to copy. / 一键复制 Seed/Prompt。
    - **Detail Modal**: View full generation parameters. / 详情弹窗。

![Viewer UI](./screenshot/viewer.png)
*Metadata Viewer / 瀑布流查看器*

![Detail Modal](./screenshot/viewer_detail.png)
*Detail Modal with Metadata / 元数据详情弹窗*

---

## Usage Guide / 使用指南

### 1. Image Generation / 影像生成
- **Prompt (提示词)**: Enter your creative text. Supports English (more compatible with most models).
- **Model (选择模型)**: Select from GGUF models in your weights folder. The UI supports real-time switching without restart.
- **Aspect Ratio (画幅比例)**: Choose from Square (1:1), Portrait (3:4), Landscape (4:3), etc.
- **Batch Size (批量生成)**: Generate multiple variations in one go.
- **Auto Random Seed (自动随机种子)**: Enable to get different results every time. Disable to fix a seed for fine-tuning.
- **Stop (停止)**: If the generation is taking too long or you want to abort, use the **Stop** button.

### 2. Viewing & Management / 查看与管理
- **Waterfall Layout**: All generated images are saved to the `outputs/` folder and displayed chronologically in the Viewer.
- **Metadata Recovery**: Every PNG file has its generation parameters (Prompt, Seed, Model) embedded. Click any image in the Viewer to see the original "recipe".
- **Copy & Reuse**: Use the **Copy** buttons in the Viewer to quickly reuse successful prompts or seeds in the Generation Workspace.

---


## Models Configuration / 模型下载与配置

1. **Backend Binaries / 核心引擎**:
   You can either download pre-compiled binaries or build them from source for better performance (e.g., CUDA support).
   您可以选择直接下载预编译文件，或从源码编译以获得更好的性能（如 CUDA 支持）。

   - **Option A: Download / 直接下载 (NVIDIA GPU)**:
     Download **two files** from [stable-diffusion.cpp Releases](https://github.com/leejet/stable-diffusion.cpp/releases):
     从官方 [Releases](https://github.com/leejet/stable-diffusion.cpp/releases) 页面下载以下 **两个** 文件：
     1. `sd-master-xxxx-bin-win-cuda12-x64.zip` (Main binary with CUDA support / 开启 CUDA 支持的主程序)
     2. `cudart-sd-bin-win-cu12-x64.zip` (CUDA runtime libraries / CUDA 运行时库)
     *Copy the `.exe` and `.dll` files into your target bin folder.*

   - **Option B: Build from Source / 源码编译 (Recommended for NVIDIA GPU)**:
     ```bash
     git clone --recursive https://github.com/leejet/stable-diffusion.cpp
     cd stable-diffusion.cpp
1.  **Backend Binaries / 核心引擎**:
    You can either download pre-compiled binaries or build them from source for better performance (e.g., CUDA support).
    您可以选择直接下载预编译文件，或从源码编译以获得更好的性能（如 CUDA 支持）。

    -   **Option A: Download / 直接下载 (NVIDIA GPU)**:
        Download **two files** from [stable-diffusion.cpp Releases](https://github.com/leejet/stable-diffusion.cpp/releases):
        从官方 [Releases](https://github.com/leejet/stable-diffusion.cpp/releases) 页面下载以下 **两个** 文件：
        1.  `sd-master-xxxx-bin-win-cuda12-x64.zip` (Main binary with CUDA support / 开启 CUDA 支持的主程序)
        2.  `cudart-sd-bin-win-cu12-x64.zip` (CUDA runtime libraries / CUDA 运行时库)
        *Copy the `.exe` and `.dll` files into your target bin folder.*

    -   **Option B: Build from Source / 源码编译 (Recommended for NVIDIA GPU)**:
        ```bash
        git clone --recursive https://github.com/leejet/stable-diffusion.cpp
        cd stable-diffusion.cpp
        mkdir build && cd build
        # For NVIDIA CUDA:
        cmake .. -DSD_CUDA=ON
        cmake --build . --config Release
        ```
    
    -   **Default Path / 默认路径**:
        The app automatically looks for `sd-cli.exe` in the project root or the parent directory:
        - `stable-diffusion.cpp/build/bin/Release/sd-cli.exe` (Project Root or Parent)
        程序会自动在项目根目录或上级目录下寻找 `sd-cli.exe`。


2.  **Model Weights / 模型权重**:
    By default, the application looks for models in a `models/` folder in the project root or the parent directory.
    默认情况下，程序会从项目根目录或上级目录下的 `models/` 文件夹加载模型。

**Note:** You must download model weights manually before running.
**注意：** 您必须在运行前手动准备模型权重。

| Model File | Description / 说明 | Path / 路径 | Download / 下载 |
| --- | --- | --- | --- |
| `Qwen3-...-Q4_K_S...` | LLM for stable-diffusion.cpp | `models/` | [HuggingFace](https://huggingface.co/byteshape/Qwen3-4B-Instruct-2507-GGUF/tree/main) |
| `z-image-turbo-Q4_K_M` | Diffusion (Fast / RTX 5060 OK) | `models/` | [HuggingFace](https://huggingface.co/unsloth/Z-Image-Turbo-GGUF/tree/main) |
| `z-image-turbo-Q8_0` | Diffusion (High Quality) | `models/` | [HuggingFace](https://huggingface.co/unsloth/Z-Image-Turbo-GGUF/tree/main) |
| `ae-Q8_0.gguf` | VAE Encoder | `models/` | [HuggingFace](https://huggingface.co/gaianet/FLUX.1-Fill-dev-GGUF/blob/main/ae-Q8_0.gguf) |

> **Hardware Note / 硬件说明**: 
> The above models (especially Q4_K_M and Q8_0 versions) have been tested and run smoothly on **NVIDIA RTX 5060**.
> 以上模型（特别是 Q4_K_M 和 Q8_0 版本）已在 **NVIDIA RTX 5060** 上测试，运行流畅。

> Tip: Ensure the `sd-cli.exe` path in `app_fastapi.py` is correct for your system.
> 提示：编译后的 `sd-cli.exe` 路径默认为项目相对路径或环境变量，请确保配置正确。

---

## Technical Details / 技术细节

### Generation (`app_fastapi.py`)
- **SSE Push**: Frontend listens to `sd-cli.exe` output via SSE for real-time progress without refreshing.
- **PNG Metadata**: Prompt, Seed, and Model info are automatically embedded into the PNG `tEXt` chunk.

### Viewer (`viewer_app.py`)
- **Masonry Layout**: JS-based dynamic layout ensuring a strict Left-to-Right chronological order.
- **Lazy Loading**: Uses native `loading="lazy"` and on-demand metadata fetching for performance.

---

## FAQ / 常见问题

| Issue | Solution / 解决办法 |
| --- | --- |
| **Cannot copy to clipboard** <br> 无法复制到剪贴板 | Modern browsers require `localhost` or `https` for the Clipboard API. <br> 现代浏览器要求站点必须运行在安全环境下。 |
| **Port Conflict?** <br> 应用冲突吗？ | No. They use different ports (17865 & 17866) and share the `outputs/` folder. <br> 不冲突，端口不同且共享输出目录。 |
| **Logs stuck** <br> 实时日志不动了 | Check if `sd-cli.exe` is blocked by antivirus software. <br> 检查后台进程是否被拦截。 |

- [llama.cpp](https://github.com/ggerganov/llama.cpp)
- [stable-diffusion.cpp](https://github.com/leejet/stable-diffusion.cpp)
- [Z-Image (Tongyi-MAI)](https://github.com/Tongyi-MAI/Z-Image) - Special thanks for the inspiration and model support.
- [VS 2026 + CUDA Compilation Guide](./readme-llama-cpp.md)


## License / 许可证

This project is licensed under the MIT License. See the [LICENSE](./LICENSE) file for details.
本项目采用 MIT 许可证。详情请参阅 [LICENSE](./LICENSE) 文件。

> **Note on Model Licenses**: The MIT License above applies to the source code of WindDrawer. The model weights (e.g., Z-Image, Qwen) used in this project are subject to their respective original licenses.
>
> **关于模型许可的说明**：上述 MIT 许可证仅适用于 WindDrawer 的源代码。本项目中使用的模型权重（如 Z-Image, Qwen 等）遵循其原始发布者的许可协议。


---
*风语画笺 (WindDrawer): Making AI Art Creation Simple.*
