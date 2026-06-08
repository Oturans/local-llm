#!/usr/bin/env zsh
# download-models.sh - download selected GGUF models into the models/ folder
# Usage:
#   ./scripts/download-models.sh          - download fast model
#   ./scripts/download-models.sh fast     - fast profile only

set -euo pipefail

MODELS_DIR="$(cd "$(dirname "$0")/.." && pwd)/models"
mkdir -p "$MODELS_DIR"

# Base URL for downloads
HF_BASE="https://huggingface.co"

# Model list: <profile> <repo> <filename>
typeset -a MODELS
MODELS=(
  "fast   bartowski/google_gemma-3-4b-it-GGUF       google_gemma-3-4b-it-Q4_K_M.gguf"
)

FILTER="${1:-all}"

download_model() {
  local repo="$1"
  local filename="$2"
  local dest="$MODELS_DIR/$filename"

  if [[ -f "$dest" ]]; then
    echo "  ✓ already exists: $filename"
    return
  fi

  local url="$HF_BASE/$repo/resolve/main/$filename"
  echo "  ↓ downloading: $filename"
  echo "    from: $url"
  curl -L --progress-bar -o "$dest" "$url"
  echo "  ✓ saved: $dest"
}

echo "=== Downloading models to $MODELS_DIR ==="
echo

for entry in "${MODELS[@]}"; do
  local_profile=$(echo "$entry" | awk '{print $1}')
  local_repo=$(echo    "$entry" | awk '{print $2}')
  local_file=$(echo    "$entry" | awk '{print $3}')

  if [[ "$FILTER" == "all" || "$FILTER" == "$local_profile" ]]; then
    echo "--- profile: $local_profile ---"
    download_model "$local_repo" "$local_file"
    echo
  fi
done

echo "=== Done ==="
echo "Files in $MODELS_DIR:"
ls -lh "$MODELS_DIR"/*.gguf 2>/dev/null || echo "  (no gguf files)"
