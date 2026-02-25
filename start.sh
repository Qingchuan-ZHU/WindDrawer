#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$ROOT_DIR"

require_cmd() {
  local name="$1"
  local hint="$2"
  if ! command -v "$name" >/dev/null 2>&1; then
    echo "[ERROR] Missing command: $name"
    echo "$hint"
    exit 1
  fi
}

wait_http_ready() {
  local url="$1"
  local timeout="${2:-120}"
  local i
  for ((i=0; i<timeout; i++)); do
    if curl -fsS --max-time 5 "$url" >/dev/null 2>&1; then
      return 0
    fi
    sleep 1
  done
  return 1
}

require_cmd docker "Please install Docker Engine / Docker Desktop first."
require_cmd curl "Please install curl first."

MODELS_DIR="$ROOT_DIR/models"
OUTPUTS_DIR="$ROOT_DIR/outputs"
SDCPP_DIR="$ROOT_DIR/stable-diffusion.cpp"
SDCLI_PATH="$SDCPP_DIR/build-linux/bin/sd-cli"

echo "------------------------------------"
echo "  WindDrawer Docker One-Click Start "
echo "------------------------------------"

mkdir -p "$MODELS_DIR" "$OUTPUTS_DIR"

if [[ ! -d "$SDCPP_DIR" ]]; then
  require_cmd git "First startup needs to clone stable-diffusion.cpp. Please install git."
  echo "[Prepare] Cloning stable-diffusion.cpp..."
  git clone --recursive https://github.com/leejet/stable-diffusion.cpp "$SDCPP_DIR"
fi

if [[ ! -f "$SDCPP_DIR/CMakeLists.txt" ]]; then
  echo "[ERROR] Invalid stable-diffusion.cpp directory: $SDCPP_DIR"
  exit 1
fi

if [[ ! -x "$SDCLI_PATH" ]]; then
  echo "[Build] CUDA sd-cli not found. Building Linux binary in Docker..."
  docker run --rm \
    -v "$SDCPP_DIR:/sd.cpp" \
    -w /sd.cpp \
    nvidia/cuda:12.4.1-devel-ubuntu22.04 \
    bash -lc "apt-get update && apt-get install -y --no-install-recommends build-essential cmake git && cmake -S . -B build-linux -DCMAKE_BUILD_TYPE=Release -DSD_CUDA=ON && cmake --build build-linux --config Release --parallel --target sd-cli"
  if [[ ! -x "$SDCLI_PATH" ]]; then
    echo "[ERROR] Build command completed but sd-cli is still missing: $SDCLI_PATH"
    exit 1
  fi
fi

shopt -s nullglob
ggufs=("$MODELS_DIR"/*.gguf)
if [[ ${#ggufs[@]} -eq 0 ]]; then
  echo "[Tip] models/ is empty. Put GGUF model files in $MODELS_DIR before generating images."
fi

if [[ ! -f "$ROOT_DIR/.env" && -f "$ROOT_DIR/.env.example" ]]; then
  cp "$ROOT_DIR/.env.example" "$ROOT_DIR/.env"
fi

echo "[Check] Verifying Docker GPU access..."
docker run --rm --gpus all nvidia/cuda:12.4.1-base-ubuntu22.04 nvidia-smi >/dev/null

echo "[Start] Launching containers..."
docker compose up -d --build

DRAWER_URL="http://127.0.0.1:17865"
VIEWER_URL="http://127.0.0.1:17866"
echo "[Wait] Waiting for services..."

wait_http_ready "$DRAWER_URL/api/models" 120
wait_http_ready "$VIEWER_URL/api/images" 120

echo "[OK] WindDrawer is ready:"
echo "  Drawer: $DRAWER_URL"
echo "  Viewer: $VIEWER_URL"

if command -v xdg-open >/dev/null 2>&1; then
  xdg-open "$VIEWER_URL" >/dev/null 2>&1 || true
  sleep 0.5
  xdg-open "$DRAWER_URL" >/dev/null 2>&1 || true
fi
