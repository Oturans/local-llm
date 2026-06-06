#!/usr/bin/env zsh
# download-models.sh — скачать выбранные GGUF-модели в папку models/
# Использование:
#   ./scripts/download-models.sh          — скачать fast-модель
#   ./scripts/download-models.sh fast     — только fast-профиль

set -euo pipefail

MODELS_DIR="$(cd "$(dirname "$0")/.." && pwd)/models"
mkdir -p "$MODELS_DIR"

# Базовый URL для скачивания
HF_BASE="https://huggingface.co"

# Список моделей: <profile> <repo> <filename>
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
    echo "  ✓ уже есть: $filename"
    return
  fi

  local url="$HF_BASE/$repo/resolve/main/$filename"
  echo "  ↓ скачиваю: $filename"
  echo "    из: $url"
  curl -L --progress-bar -o "$dest" "$url"
  echo "  ✓ сохранено: $dest"
}

echo "=== Скачивание моделей в $MODELS_DIR ==="
echo

for entry in "${MODELS[@]}"; do
  local_profile=$(echo "$entry" | awk '{print $1}')
  local_repo=$(echo    "$entry" | awk '{print $2}')
  local_file=$(echo    "$entry" | awk '{print $3}')

  if [[ "$FILTER" == "all" || "$FILTER" == "$local_profile" ]]; then
    echo "--- профиль: $local_profile ---"
    download_model "$local_repo" "$local_file"
    echo
  fi
done

echo "=== Готово ==="
echo "Файлы в $MODELS_DIR:"
ls -lh "$MODELS_DIR"/*.gguf 2>/dev/null || echo "  (нет gguf файлов)"
