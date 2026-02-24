import os
import json
import uvicorn
from fastapi import FastAPI, HTTPException
from fastapi.responses import HTMLResponse
from fastapi.staticfiles import StaticFiles
from PIL import Image
from typing import Dict, Any, Optional, List

# Configuration
BASE_DIR = os.path.dirname(os.path.abspath(__file__))
OUTPUT_DIR = os.getenv("WINDDRAWER_OUTPUT_DIR") or os.path.join(BASE_DIR, "outputs")
WEB_DIR = os.path.join(BASE_DIR, "web")

app = FastAPI(title="WindDrawer Viewer")

# Ensure output directory exists (though this viewer expects to read from it)
os.makedirs(OUTPUT_DIR, exist_ok=True)

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

@app.get("/api/images")
def api_images():
    items: List[dict] = []
    try:
        for name in os.listdir(OUTPUT_DIR):
            if not name.lower().endswith(".png"):
                continue
            path = os.path.join(OUTPUT_DIR, name)
            try:
                stat = os.stat(path)
                items.append({
                    "filename": name,
                    "url": f"/outputs/{name}",
                    "mtime": stat.st_mtime,
                    "size": stat.st_size
                })
            except OSError:
                continue
    except OSError:
        pass
    
    # Sort by modification time descending (newest first)
    items.sort(key=lambda x: x.get("mtime", 0), reverse=True)
    return {"items": items}

@app.get("/api/metadata/{filename}")
def api_metadata(filename: str):
    safe_name = os.path.basename(filename)
    path = os.path.join(OUTPUT_DIR, safe_name)
    if not os.path.exists(path):
        raise HTTPException(status_code=404, detail="File not found")
    
    meta = read_png_metadata(path)
    return {"filename": safe_name, "metadata": meta}

if __name__ == "__main__":
    # Use a different port than the main app (8000)
    uvicorn.run(app, host="127.0.0.1", port=8001)
