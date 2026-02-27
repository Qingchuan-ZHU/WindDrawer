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
BUILD_STAMP_PATH="$SDCPP_DIR/build-linux/.winddrawer_build_info"

CUDA_IMAGE_TAG="${WINDDRAWER_CUDA_IMAGE_TAG:-12.8.0}"
CUDA_ARCHS="${WINDDRAWER_CUDA_ARCHS:-89;120}"
BUILD_JOBS="${WINDDRAWER_BUILD_JOBS:-4}"
if ! [[ "$BUILD_JOBS" =~ ^[0-9]+$ ]] || [[ "$BUILD_JOBS" -lt 1 ]]; then
  BUILD_JOBS=4
fi
DESIRED_BUILD_STAMP=$'cuda_image_tag='"$CUDA_IMAGE_TAG"$'\ncuda_archs='"$CUDA_ARCHS"

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

should_build=0
if [[ ! -x "$SDCLI_PATH" ]]; then
  should_build=1
elif [[ ! -f "$BUILD_STAMP_PATH" ]] || [[ "$(cat "$BUILD_STAMP_PATH")" != "$DESIRED_BUILD_STAMP" ]]; then
  should_build=1
fi

if [[ "$should_build" -eq 1 ]]; then
  echo "[Build] CUDA sd-cli not reusable. Building Linux binary in Docker..."
  echo "  CUDA image: $CUDA_IMAGE_TAG, archs: $CUDA_ARCHS, parallel jobs: $BUILD_JOBS"
  docker run --rm \
    -v "$SDCPP_DIR:/sd.cpp" \
    -w /sd.cpp \
    "nvidia/cuda:${CUDA_IMAGE_TAG}-devel-ubuntu22.04" \
    bash -lc "apt-get update && apt-get install -y --no-install-recommends build-essential cmake git && cmake -S . -B build-linux -DCMAKE_BUILD_TYPE=Release -DSD_CUDA=ON \"-DCMAKE_CUDA_ARCHITECTURES=${CUDA_ARCHS}\" && cmake --build build-linux --config Release --parallel ${BUILD_JOBS} --target sd-cli"
  if [[ ! -x "$SDCLI_PATH" ]]; then
    echo "[ERROR] Build command completed but sd-cli is still missing: $SDCLI_PATH"
    exit 1
  fi
  mkdir -p "$(dirname "$BUILD_STAMP_PATH")"
  printf '%s' "$DESIRED_BUILD_STAMP" > "$BUILD_STAMP_PATH"
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
docker run --rm --gpus all "nvidia/cuda:${CUDA_IMAGE_TAG}-base-ubuntu22.04" nvidia-smi >/dev/null

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
