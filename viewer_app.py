import os
import json
import uvicorn
from urllib.parse import quote
from fastapi import FastAPI, HTTPException, Query
from fastapi.responses import HTMLResponse, FileResponse
from fastapi.staticfiles import StaticFiles
from PIL import Image
from typing import Dict, Any, Optional, List, Tuple

# Configuration
BASE_DIR = os.path.dirname(os.path.abspath(__file__))
OUTPUT_DIR = os.getenv("WINDDRAWER_OUTPUT_DIR") or os.path.join(BASE_DIR, "outputs")
WEB_DIR = os.path.join(BASE_DIR, "web")
DEFAULT_FOLDER_KEY = "__default__"
PINNED_FOLDERS = {"outputs", "good_output", "good_outputs"}

app = FastAPI(title="WindDrawer Viewer")

# Ensure output directory exists (though this viewer expects to read from it)
os.makedirs(OUTPUT_DIR, exist_ok=True)


def resolve_folder_path(folder: Optional[str]) -> Tuple[str, str]:
    if not folder or folder == DEFAULT_FOLDER_KEY:
        return OUTPUT_DIR, DEFAULT_FOLDER_KEY

    folder_name = os.path.normpath(folder.strip())
    if folder_name in ("", "."):
        return OUTPUT_DIR, DEFAULT_FOLDER_KEY
    if os.path.isabs(folder_name):
        raise HTTPException(status_code=400, detail="Absolute folder path is not allowed")

    full_path = os.path.abspath(os.path.join(BASE_DIR, folder_name))
    base_path = os.path.abspath(BASE_DIR)
    try:
        in_repo = os.path.commonpath([full_path, base_path]) == base_path
    except ValueError:
        in_repo = False
    if not in_repo:
        raise HTTPException(status_code=400, detail="Invalid folder path")
    if not os.path.isdir(full_path):
        raise HTTPException(status_code=404, detail="Folder not found")

    return full_path, folder_name.replace("\\", "/")


def has_png_files(folder_path: str) -> bool:
    try:
        with os.scandir(folder_path) as it:
            for entry in it:
                if entry.is_file() and entry.name.lower().endswith(".png"):
                    return True
    except OSError:
        return False
    return False


def default_folder_label() -> str:
    output_abs = os.path.abspath(OUTPUT_DIR)
    base_abs = os.path.abspath(BASE_DIR)
    try:
        if os.path.commonpath([output_abs, base_abs]) == base_abs:
            rel = os.path.relpath(output_abs, base_abs).replace("\\", "/")
            return f"{rel} (default)"
    except ValueError:
        pass
    return f"{output_abs} (default)"

# Helper function to read metadata (copied/simplified from app_fastapi.py)
def read_png_metadata(png_path: str) -> Dict[str, Any]:
    try:
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
            "zimage": zimage, # Full custom metadata
            "prompt": info.get("prompt"),
            "seed": info.get("seed"),
            "steps": info.get("steps"),
            "width": info.get("width"),
            "height": info.get("height"),
            "sampling_method": info.get("sampling_method"),
            "diffusion_model": info.get("diffusion_model"),
            # Fallback to standard info if zimage is missing, or merge them as needed. 
            # The frontend can prefer zimage struct.
        }
    except Exception as e:
        print(f"Error reading metadata for {png_path}: {e}")
        return {}

# Mount static files
app.mount("/static", StaticFiles(directory=os.path.join(WEB_DIR, "static")), name="static")
app.mount("/outputs", StaticFiles(directory=OUTPUT_DIR), name="outputs")

@app.get("/", response_class=HTMLResponse)
def index():
    # We will serve the viewer.html here
    viewer_path = os.path.join(WEB_DIR, "viewer.html")
    if os.path.exists(viewer_path):
        with open(viewer_path, "r", encoding="utf-8") as f:
            return f.read()
    return "viewer.html not found"


@app.get("/api/folders")
def api_folders():
    items = [{"value": DEFAULT_FOLDER_KEY, "label": default_folder_label()}]
    seen = {os.path.abspath(OUTPUT_DIR)}

    try:
        with os.scandir(BASE_DIR) as it:
            for entry in it:
                if not entry.is_dir():
                    continue
                if entry.name.startswith("."):
                    continue

                folder_abs = os.path.abspath(entry.path)
                if folder_abs in seen:
                    continue

                folder_name = entry.name.replace("\\", "/")
                if entry.name in PINNED_FOLDERS or has_png_files(entry.path):
                    items.append({"value": folder_name, "label": folder_name})
    except OSError:
        pass

    fixed = items[:1]
    others = sorted(items[1:], key=lambda x: x["label"].lower())
    return {"current": DEFAULT_FOLDER_KEY, "items": fixed + others}


@app.get("/api/images")
def api_images(folder: Optional[str] = Query(default=DEFAULT_FOLDER_KEY)):
    target_dir, folder_value = resolve_folder_path(folder)
    items: List[dict] = []
    try:
        for name in os.listdir(target_dir):
            if not name.lower().endswith(".png"):
                continue
            path = os.path.join(target_dir, name)
            try:
                stat = os.stat(path)
                image_url = f"/api/image/{quote(name)}?folder={quote(folder_value)}"
                items.append({
                    "filename": name,
                    "folder": folder_value,
                    "url": image_url,
                    "mtime": stat.st_mtime,
                    "size": stat.st_size
                })
            except OSError:
                continue
    except OSError:
        pass
    
    # Sort by modification time descending (newest first)
    items.sort(key=lambda x: x.get("mtime", 0), reverse=True)
    return {"folder": folder_value, "items": items}


@app.get("/api/image/{filename}")
def api_image(filename: str, folder: Optional[str] = Query(default=DEFAULT_FOLDER_KEY)):
    target_dir, _ = resolve_folder_path(folder)
    safe_name = os.path.basename(filename)
    path = os.path.join(target_dir, safe_name)
    if not os.path.isfile(path):
        raise HTTPException(status_code=404, detail="File not found")

    return FileResponse(path)

@app.get("/api/metadata/{filename}")
def api_metadata(filename: str, folder: Optional[str] = Query(default=DEFAULT_FOLDER_KEY)):
    target_dir, _ = resolve_folder_path(folder)
    safe_name = os.path.basename(filename)
    path = os.path.join(target_dir, safe_name)
    if not os.path.exists(path):
        raise HTTPException(status_code=404, detail="File not found")
    
    meta = read_png_metadata(path)
    return {"filename": safe_name, "metadata": meta}

if __name__ == "__main__":
    # Use a different port than the main app (8000)
    uvicorn.run(app, host="127.0.0.1", port=8001)
