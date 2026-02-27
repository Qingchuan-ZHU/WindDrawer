import os
import re
import time
import uuid
import json
import queue
import random
import threading
import subprocess
from dataclasses import dataclass, field
from functools import lru_cache
from typing import Dict, Optional, List, Any, Generator

from PIL import Image
from PIL.PngImagePlugin import PngInfo

from fastapi import FastAPI, HTTPException
from fastapi.responses import HTMLResponse, StreamingResponse
from fastapi.staticfiles import StaticFiles
from fastapi.responses import FileResponse


BASE_DIR = os.path.dirname(os.path.abspath(__file__))
PARENT_DIR = os.path.dirname(BASE_DIR)

def _first_existing_dir(paths: List[str]) -> Optional[str]:
    for path in paths:
        if path and os.path.isdir(path):
            return path
    return None


def _first_existing_file(paths: List[str]) -> Optional[str]:
    for path in paths:
        if path and os.path.isfile(path):
            return path
    return None


_LOCAL_MODEL_DIR = os.path.join(BASE_DIR, "models")
_PARENT_MODEL_DIR = os.path.join(PARENT_DIR, "models")
MODEL_DIR = (
    os.getenv("WINDDRAWER_MODEL_DIR")
    or os.getenv("MODEL_DIR")
    or _first_existing_dir([
        _LOCAL_MODEL_DIR,
        _PARENT_MODEL_DIR,
    ])
    or _LOCAL_MODEL_DIR
)

_LOCAL_SD_CLI_WIN = os.path.join(BASE_DIR, "stable-diffusion.cpp", "build", "bin", "Release", "sd-cli.exe")
_PARENT_SD_CLI_WIN = os.path.join(PARENT_DIR, "stable-diffusion.cpp", "build", "bin", "Release", "sd-cli.exe")
_LOCAL_SD_CLI_LINUX = os.path.join(BASE_DIR, "stable-diffusion.cpp", "build", "bin", "sd-cli")
_PARENT_SD_CLI_LINUX = os.path.join(PARENT_DIR, "stable-diffusion.cpp", "build", "bin", "sd-cli")
_LOCAL_SD_LINUX = os.path.join(BASE_DIR, "stable-diffusion.cpp", "build", "bin", "sd")
_PARENT_SD_LINUX = os.path.join(PARENT_DIR, "stable-diffusion.cpp", "build", "bin", "sd")
_LOCAL_SD_CLI_LINUX_ALT = os.path.join(BASE_DIR, "stable-diffusion.cpp", "build-linux", "bin", "sd-cli")
_PARENT_SD_CLI_LINUX_ALT = os.path.join(PARENT_DIR, "stable-diffusion.cpp", "build-linux", "bin", "sd-cli")
_LOCAL_SD_LINUX_ALT = os.path.join(BASE_DIR, "stable-diffusion.cpp", "build-linux", "bin", "sd")
_PARENT_SD_LINUX_ALT = os.path.join(PARENT_DIR, "stable-diffusion.cpp", "build-linux", "bin", "sd")
SD_CLI = (
    os.getenv("WINDDRAWER_SD_CLI")
    or os.getenv("SD_CLI")
    or _first_existing_file([
        _LOCAL_SD_CLI_WIN,
        _PARENT_SD_CLI_WIN,
        _LOCAL_SD_CLI_LINUX,
        _PARENT_SD_CLI_LINUX,
        _LOCAL_SD_LINUX,
        _PARENT_SD_LINUX,
        _LOCAL_SD_CLI_LINUX_ALT,
        _PARENT_SD_CLI_LINUX_ALT,
        _LOCAL_SD_LINUX_ALT,
        _PARENT_SD_LINUX_ALT,
    ])
    or _LOCAL_SD_CLI_LINUX_ALT
)

QWEN_PATH = (
    os.getenv("WINDDRAWER_QWEN_PATH")
    or os.getenv("QWEN_PATH")
    or os.path.join(MODEL_DIR, "Qwen3-4B-Instruct-2507-Q4_K_S-4.31bpw.gguf")
)
VAE_PATH = (
    os.getenv("WINDDRAWER_VAE_PATH")
    or os.getenv("VAE_PATH")
    or os.path.join(MODEL_DIR, "ae-Q8_0.gguf")
)
OUTPUT_DIR = os.getenv("WINDDRAWER_OUTPUT_DIR") or os.path.join(BASE_DIR, "outputs")

os.makedirs(OUTPUT_DIR, exist_ok=True)


def clean_ansi(text: str) -> str:
    ansi_escape = re.compile(r"\x1B(?:[@-Z\\-_]|\[[0-?]*[ -/]*[@-~])")
    return ansi_escape.sub("", text)


@lru_cache(maxsize=1)
def _sd_cli_help_text() -> str:
    exe_dir = os.path.dirname(SD_CLI) or None
    try:
        result = subprocess.run(
            [SD_CLI, "--help"],
            stdout=subprocess.PIPE,
            stderr=subprocess.STDOUT,
            text=True,
            encoding="utf-8",
            errors="replace",
            cwd=exe_dir,
            check=False,
        )
    except Exception:
        return ""
    return clean_ansi(result.stdout or "")


def _sd_cli_supports(flag: str) -> bool:
    return flag in _sd_cli_help_text()


def write_png_metadata(png_path: str, meta: Dict[str, Any]) -> bool:
    try:
        img = Image.open(png_path)
        pnginfo = PngInfo()
        for k, v in meta.items():
            if v is None:
                continue
            if isinstance(v, (dict, list)):
                pnginfo.add_text(str(k), json.dumps(v, ensure_ascii=False))
            else:
                pnginfo.add_text(str(k), str(v))
        pnginfo.add_text("zimage", json.dumps(meta, ensure_ascii=False))
        img.save(png_path, pnginfo=pnginfo)
        return True
    except Exception:
        return False


def read_png_metadata(png_path: str) -> Dict[str, Any]:
    img = Image.open(png_path)
    info: Dict[str, Any] = dict(getattr(img, "info", {}) or {})

    zimage_raw = info.get("zimage")
    zimage: Optional[Dict[str, Any]] = None
    if isinstance(zimage_raw, str) and zimage_raw.strip():
        try:
            zimage = json.loads(zimage_raw)
        except json.JSONDecodeError:
            zimage = None

    return {
        "zimage": zimage,
        "prompt": info.get("prompt"),
        "seed": info.get("seed"),
        "steps": info.get("steps"),
        "width": info.get("width"),
        "height": info.get("height"),
        "sampling_method": info.get("sampling_method"),
        "diffusion_model": info.get("diffusion_model"),
        "llm": info.get("llm"),
        "vae": info.get("vae"),
        "cfg_scale": info.get("cfg_scale"),
        "guidance": info.get("guidance"),
        "duration_sec": info.get("duration_sec"),
        "timestamp": info.get("timestamp"),
    }


def list_sd_models() -> List[str]:
    try:
        entries = os.listdir(MODEL_DIR)
    except OSError:
        return []

    models: List[str] = []
    for name in entries:
        if not name.lower().endswith(".gguf"):
            continue
        lower = name.lower()
        if lower.startswith("ae-"):
            continue
        if "qwen" in lower:
            continue
        models.append(name)

    def sort_key(s: str):
        lower = s.lower()
        turbo_first = 0 if lower.startswith("z-image-turbo") else 1
        return (turbo_first, lower)

    models.sort(key=sort_key)
    return models


@dataclass
class Job:
    id: str
    created_at: float
    q: "queue.Queue[dict]"
    done: bool = False
    error: Optional[str] = None
    stop_event: threading.Event = field(default_factory=threading.Event)
    current_proc: Optional[subprocess.Popen] = None
    cancelled: bool = False


class JobCancelled(Exception):
    pass


app = FastAPI(title="WindDrawer API")

WEB_DIR = os.path.join(BASE_DIR, "web")
app.mount("/static", StaticFiles(directory=os.path.join(WEB_DIR, "static")), name="static")
app.mount("/outputs", StaticFiles(directory=OUTPUT_DIR), name="outputs")

_jobs: Dict[str, Job] = {}
_render_lock = threading.Lock()
_sys_random = random.SystemRandom()


@app.get("/", response_class=HTMLResponse)
def index() -> str:
    index_path = os.path.join(WEB_DIR, "index.html")
    with open(index_path, "r", encoding="utf-8") as f:
        return f.read()


@app.get("/metadata", response_class=HTMLResponse)
def metadata_page() -> str:
    page_path = os.path.join(WEB_DIR, "metadata.html")
    with open(page_path, "r", encoding="utf-8") as f:
        return f.read()


@app.get("/favicon.ico", include_in_schema=False)
async def favicon():
    fav_path = os.path.join(WEB_DIR, "static", "favicon.png")
    return FileResponse(fav_path)


@app.get("/api/models")
def api_models() -> dict:
    return {"models": list_sd_models()}


@app.get("/api/aspects")
def api_aspects() -> dict:
    return {
        "aspects": [
            {"label": "Vertical 9:16 / 竖屏 (1080x1920)", "w": 1080, "h": 1920},
            {"label": "Square 1:1 / 方形 (1080x1080)", "w": 1080, "h": 1080},
            {"label": "Landscape 16:9 / 横屏 (1920x1080)", "w": 1920, "h": 1080},
            {"label": "Portrait 4:5 / 竖长 (1080x1350)", "w": 1080, "h": 1350},
            {"label": "Landscape 5:4 / 横宽 (1350x1080)", "w": 1350, "h": 1080},
            {"label": "Cinema 21:9 / 电影 (2520x1080)", "w": 2520, "h": 1080},
            {"label": "Wide 3:2 / 宽屏 (1620x1080)", "w": 1620, "h": 1080},
            {"label": "Classic 2:3 / 经典 (1080x1620)", "w": 1080, "h": 1620},
        ]
    }


@app.get("/api/outputs")
def api_outputs() -> dict:
    items: List[dict] = []
    out_dir = os.path.abspath(OUTPUT_DIR)
    try:
        for name in os.listdir(out_dir):
            if not name.lower().endswith(".png"):
                continue
            path = os.path.join(out_dir, name)
            try:
                stat = os.stat(path)
            except OSError:
                continue
            items.append({
                "filename": name,
                "url": f"/outputs/{name}",
                "mtime": stat.st_mtime,
                "size": stat.st_size,
            })
    except OSError:
        items = []

    items.sort(key=lambda x: x.get("mtime", 0), reverse=True)
    return {"items": items}


@app.get("/api/metadata/{filename}")
def api_metadata(filename: str) -> dict:
    safe_name = os.path.basename(filename)
    if safe_name != filename:
        raise HTTPException(status_code=400, detail="invalid filename")
    if not safe_name.lower().endswith(".png"):
        raise HTTPException(status_code=400, detail="only .png supported")

    path = os.path.abspath(os.path.join(OUTPUT_DIR, safe_name))
    out_dir = os.path.abspath(OUTPUT_DIR)
    if not path.startswith(out_dir + os.sep):
        raise HTTPException(status_code=400, detail="invalid path")
    if not os.path.exists(path):
        raise HTTPException(status_code=404, detail="file not found")

    try:
        meta = read_png_metadata(path)
    except Exception as exc:
        raise HTTPException(status_code=500, detail=f"read metadata failed: {exc}")

    return {"filename": safe_name, "metadata": meta}


def _emit(job: Job, event: str, data: Dict[str, Any]) -> None:
    job.q.put({"event": event, "data": data, "ts": time.time()})


def _run_sd_cli(
    job: Job,
    *,
    prompt: str,
    width: int,
    height: int,
    steps: int,
    seed: int,
    sd_model_name: str,
) -> str:
    output_file = f"out_{int(time.time())}_{seed}.png"
    output_path = os.path.join(OUTPUT_DIR, output_file)

    cmd = [
        SD_CLI,
        "--diffusion-model",
        os.path.join(MODEL_DIR, sd_model_name),
        "--llm",
        QWEN_PATH,
        "--vae",
        VAE_PATH,
        "-p",
        prompt,
        "-W",
        str(width),
        "-H",
        str(height),
        "--steps",
        str(steps),
        "--seed",
        str(seed),
        "--cfg-scale",
        "1.0",
        "--guidance",
        "0.0",
        "--sampling-method",
        "euler",
        "--clip-on-cpu",
        "--vae-tiling",
    ]
    if _sd_cli_supports("--diffusion-fa"):
        cmd.append("--diffusion-fa")
    cmd.extend(["-o", output_path])

    exe_dir = os.path.dirname(SD_CLI) or None
    start = time.time()

    try:
        process = subprocess.Popen(
            cmd,
            stdout=subprocess.PIPE,
            stderr=subprocess.STDOUT,
            text=True,
            encoding="utf-8",
            errors="replace",
            cwd=exe_dir,
        )
    except FileNotFoundError as exc:
        raise RuntimeError(f"启动失败：{exc} (SD_CLI={SD_CLI})")

    job.current_proc = process

    try:
        assert process.stdout is not None
        for line in process.stdout:
            clean_line = clean_ansi(line.rstrip("\n"))
            if clean_line:
                _emit(job, "log", {"line": clean_line})

        process.wait()
    finally:
        job.current_proc = None

    duration = time.time() - start

    if job.stop_event.is_set():
        raise JobCancelled()

    if process.returncode != 0 or not os.path.exists(output_path):
        raise RuntimeError("渲染失败，请检查日志")

    meta = {
        "prompt": prompt,
        "seed": seed,
        "steps": steps,
        "width": width,
        "height": height,
        "sampling_method": "euler",
        "cfg_scale": 1.0,
        "guidance": 0.0,
        "diffusion_model": sd_model_name,
        "llm": os.path.basename(QWEN_PATH),
        "vae": os.path.basename(VAE_PATH),
        "generator": "stable-diffusion.cpp sd-cli",
        "duration_sec": duration,
        "timestamp": int(time.time()),
    }
    if not write_png_metadata(output_path, meta):
        _emit(job, "log", {"line": "[meta] 写入 PNG 元数据失败（不影响渲染结果）"})

    _emit(job, "render_done", {"seed": seed, "duration": duration, "path": output_path})
    return output_path


def _render_worker(job: Job, payload: dict) -> None:
    acquired = False
    try:
        acquired = _render_lock.acquire(blocking=False)
        if not acquired:
            raise RuntimeError("已有渲染任务正在运行")

        _emit(job, "job_started", {})

        prompt = str(payload.get("prompt") or "美丽汉服美少女，胸部丰满，披着轻纱，胸口上用金色的字绣着“风语幻镜”。A beautiful Hanfu girl with a full bust, draped in a translucent veil. The words \"风语幻镜\" (WindWhisperer Stories) are embroidered in shimmering gold on her chest.").strip() or "美丽汉服美少女，胸部丰满，披着轻纱，胸口上用金色的字绣着“风语幻镜”。A beautiful Hanfu girl with a full bust, draped in a translucent veil. The words \"风语幻镜\" (WindWhisperer Stories) are embroidered in shimmering gold on her chest."
        width = int(payload.get("width") or 1080)
        height = int(payload.get("height") or 1080)
        steps = int(payload.get("steps") or 8)
        batch_size = int(payload.get("batch_size") or 1)
        auto_random_seed = bool(payload.get("auto_random_seed") if payload.get("auto_random_seed") is not None else True)
        base_seed = int(payload.get("seed") or 42)
        sd_model = str(payload.get("sd_model") or "").strip()

        sd_models = list_sd_models()
        if not sd_models:
            raise RuntimeError("未找到可用的扩散模型（请检查 MODEL_DIR）")
        if sd_model not in sd_models:
            sd_model = sd_models[0]

        for idx in range(batch_size):
            if job.stop_event.is_set():
                job.cancelled = True
                _emit(job, "job_cancelled", {})
                job.done = True
                return
            current_seed = _sys_random.randint(0, 4294967295) if auto_random_seed else (base_seed + idx) % 4294967296
            _emit(
                job,
                "render_start",
                {
                    "idx": idx,
                    "batch_size": batch_size,
                    "seed": current_seed,
                    "width": width,
                    "height": height,
                    "sd_model": sd_model,
                },
            )

            try:
                path = _run_sd_cli(
                    job,
                    prompt=prompt,
                    width=width,
                    height=height,
                    steps=steps,
                    seed=current_seed,
                    sd_model_name=sd_model,
                )
            except JobCancelled:
                job.cancelled = True
                _emit(job, "job_cancelled", {})
                job.done = True
                return

            filename = os.path.basename(path)
            _emit(
                job,
                "image",
                {
                    "idx": idx,
                    "batch_size": batch_size,
                    "seed": current_seed,
                    "width": width,
                    "height": height,
                    "url": f"/outputs/{filename}",
                    "filename": filename,
                },
            )

        _emit(job, "job_done", {})
        job.done = True
    except Exception as exc:
        if job.stop_event.is_set():
            job.cancelled = True
            _emit(job, "job_cancelled", {"message": str(exc)})
        else:
            job.error = str(exc)
            _emit(job, "job_error", {"message": str(exc)})
        job.done = True
    finally:
        if acquired:
            try:
                _render_lock.release()
            except RuntimeError:
                pass


@app.post("/api/render")
def api_render(payload: dict) -> dict:
    job_id = uuid.uuid4().hex
    job = Job(id=job_id, created_at=time.time(), q=queue.Queue())
    _jobs[job_id] = job

    t = threading.Thread(target=_render_worker, args=(job, payload), daemon=True)
    t.start()

    return {"job_id": job_id}


def _sse_format(event: str, data: dict) -> str:
    return f"event: {event}\ndata: {json.dumps(data, ensure_ascii=False)}\n\n"


@app.get("/api/events/{job_id}")
def api_events(job_id: str) -> StreamingResponse:
    job = _jobs.get(job_id)
    if not job:
        raise HTTPException(status_code=404, detail="job not found")

    def gen() -> Generator[str, None, None]:
        yield _sse_format("hello", {"job_id": job_id})
        while True:
            try:
                item = job.q.get(timeout=1.0)
                yield _sse_format(item["event"], item["data"])
            except queue.Empty:
                yield ": keep-alive\n\n"

            if job.done and job.q.empty():
                break

    return StreamingResponse(gen(), media_type="text/event-stream")


@app.post("/api/render/{job_id}/stop")
def api_stop(job_id: str) -> dict:
    job = _jobs.get(job_id)
    if not job:
        raise HTTPException(status_code=404, detail="job not found")

    job.stop_event.set()
    proc = job.current_proc
    if proc and proc.poll() is None:
        proc.terminate()
        try:
            proc.wait(timeout=5)
        except subprocess.TimeoutExpired:
            proc.kill()

    _emit(job, "job_stopping", {})
    return {"status": "stopping"}
