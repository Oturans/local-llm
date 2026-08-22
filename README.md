# local-llm

Local LLM stack for MacBook Pro 16 (2019) — Intel i9 + AMD Radeon Pro 5600M.

## Hardware

- **CPU:** Intel Core i9-9980HK
- **RAM:** 64 GB
- **GPU:** AMD Radeon Pro 5600M (8 GB HBM2) — discrete PCIe GPU
- **iGPU:** Intel UHD Graphics 630 (not used for compute)

## GPU Status

> **Metal is broken on AMD 5600M (Intel Mac), but Vulkan works.**

Extensive testing confirmed that the Metal backend produces garbage output on this
GPU, while the Vulkan backend (via MoltenVK) works correctly and faster than CPU.

### Test results (5-question benchmark: capitals, math, colors, literature, chemistry)

| Backend | Model | t/s (gen) | Quality | Notes |
|---|---|---|---|---|
| **Vulkan** (ngl=99) | gemma-3-4b Q4_K_M (2.3 GB) | 18–20 | 5/5 | best speed |
| **Vulkan** (ngl=99) | Llama-3.1-8B Q4_K_M (4.6 GB) | 14 | 5/5 | |
| **Vulkan** (ngl=99) | **gemma-4-12b Q3_K_S (4.8 GB)** | 5–8 | 5/5 | current default |
| **Vulkan** (ngl=99) | gemma-4-12b Q3_K_S, ctx 64K | 5–8 | 5/5 | opencode preset |
| **CPU** (ngl=0, 8 threads) | gemma-4-12b Q3_K_S | 3.6–4.5 | 5/5 | fallback |
| **Vulkan hybrid** (ngl=24) | Qwen2.5-14B Q4_K_M (8.4 GB) | 5.0 | 5/5 | partial offload |
| **Vulkan hybrid** (ngl=28) | Qwen3.8-27B Q4_K_S (15.4 GB) | 1.48 | 5/5 | partial offload |
| **Vulkan hybrid** (ngl=35) | Qwen3.8-27B IQ3_S (12.0 GB) | 0.91 | 5/5 | partial offload |
| **CPU** (ngl=0) | Qwen3.8-27B Q4_K_S (15.4 GB) | 1.05 | 5/5 | slow but stable |
| **Metal** (ngl>0) | any model | — | garbage | broken, see below |

### Why Metal fails on AMD 5600M

| Tool | GPU detected | Output correct |
|---|---|---|
| llama.cpp (custom build, Metal ON) | yes | no — garbage output + GPU timeout |
| Ollama 0.30.6 | no — CPU only | yes |
| brew llama-server 9430 | no — built without Metal | yes |

Root cause: Metal compute kernels in llama.cpp are not validated for discrete AMD GPUs
on Intel Mac x86_64. Tested llama.cpp builds: 9430, 10369, 10582 — all produce garbage
(`kIOAccelCommandBufferCallbackErrorTimeout`). Apple Silicon (M-series) is the only
Metal platform that works.

**Current setup uses Vulkan backend** via `build-vulkan` (see `LLMAPP-BUILD.md`).
Performance: ~5–8 t/s with Gemma 4 12B Q3_K_S on GPU, ~4 t/s on CPU.

## Architecture

```
OpenWebUI (port 3000)
    |
    v
llama-server (port 8080, Vulkan, ngl=99)
    |
    model: gemma-4-12b-it-Q3_K_S.gguf (64K context, single slot)

llama-server (port 8081, Qwen3.8-27B) — optional, hybrid CPU+GPU
    |
LiteLLM proxy (port 4000) — optional, for multi-model routing
    |
    Postgres
```

- **llama-server** runs natively on the host (not in Docker) for direct hardware access.
- **OpenWebUI** runs in Docker, connects directly to llama-server.
- **LiteLLM** runs in Docker, optional — use `make up-litellm` if needed.

## Quick Start

```bash
# 0. Prerequisites (one-time): Homebrew, Xcode CLT, CMake, git
brew --version || /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
xcode-select --version || xcode-select --install
brew install cmake git

# 1. Build llama.cpp with Vulkan (one-time, see LLMAPP-BUILD.md for details)
brew install molten-vk vulkan-loader glslang shaderc
git clone https://github.com/ggml-org/llama.cpp
cd llama.cpp
cmake -B build-vulkan -DGGML_VULKAN=ON -DGGML_METAL=OFF -DGGML_BLAS=ON \
  -DGGML_BLAS_VENDOR=Apple -DGGML_NATIVE=ON -DCMAKE_BUILD_TYPE=Release
cmake --build build-vulkan -j --target llama-server
./build-vulkan/bin/llama-server --list-devices   # verify AMD Radeon is listed

# 2. Point .env to the Vulkan build
cd ..   # back to local-llm repo
cp .env.example .env
# edit LLAMA_SERVER_BIN=/path/to/llama.cpp/build-vulkan/bin/llama-server

# 3. Download model
make download

# 4. Start llama-server + OpenWebUI
make bootstrap

# 5. Open http://localhost:3000
```

## Makefile targets

| Command | Description |
|---|---|
| `make bootstrap` | Download model, start llama-server + OpenWebUI |
| `make serve-fast` | Start llama-server on port 8080 (Vulkan, gemma-4-12b, 64K ctx) |
| `make serve-qwen3-cpu` | Start Qwen3.8-27B on port 8081 (CPU-only) |
| `make serve-qwen3-hybrid` | Start Qwen3.8-27B on port 8081 (hybrid CPU+GPU) |
| `make stop-fast` / `make stop-qwen3` | Stop servers |
| `make up-openwebui` | Start OpenWebUI only |
| `make up-litellm` | Start LiteLLM + Postgres |
| `make down` | Stop all Docker services |
| `make logs` / `make logs-qwen3` | View logs |
| `make health` | Check LiteLLM health |
| `make download` | Download the default fast model (gemma-4-12b Q3_K_S). Supports `fast`/`qwen3` profiles |
| `make test` | Run 7-case test suite against running server (knowledge, math, coding, reasoning) |
| `make status` | Show llama-server processes + docker status |

## Environment variables

Copy `.env.example` to `.env` and adjust:

```bash
cp .env.example .env
```

Key variables:

| Variable | Default | Description |
|---|---|---|
| `LLAMA_SERVER_BIN` | auto-detect | Path to llama-server binary (use build-vulkan) |
| `FAST_NGL` | `99` | GPU layers. 99 = full offload (Vulkan) |
| `FAST_CTX` | `65536` | Context size (64K for opencode) |
| `FAST_NP` | `1` | Parallel slots (1 = full context for one session) |
| `LITELLM_MASTER_KEY` | `sk-local-change-me` | Change before any external access |

## Diagnostics

### Check llama-server directly

```bash
curl -sS http://127.0.0.1:8080/health

curl -sS http://127.0.0.1:8080/v1/chat/completions \
  -H "Content-Type: application/json" \
  -d '{"model":"local-fast","messages":[{"role":"user","content":"Say: ok"}],"max_tokens":10}'
```

### Check LiteLLM

```bash
curl -sS http://127.0.0.1:4000/health

curl -sS http://127.0.0.1:4000/v1/models \
  -H "Authorization: Bearer sk-local-change-me"
```

### LiteLLM not responding (Empty reply from server)

```bash
docker compose ps
docker logs litellm | tail -50
docker exec litellm env | grep -E "DATABASE_URL|LITELLM_MASTER_KEY"
make down && make up-litellm
```

## GPU troubleshooting

For build errors, Metal garbage output, Vulkan hangs, and `no usable GPU found` —
see the [Troubleshooting section in LLMAPP-BUILD.md](LLMAPP-BUILD.md#troubleshooting--known-issues).

Quick checks:
```bash
./build-vulkan/bin/llama-server --list-devices   # should list AMD Radeon
curl -sS http://127.0.0.1:8080/health             # server alive?
```

## Security

- Never commit `.env` or GGUF model files.
- Change `LITELLM_MASTER_KEY` before exposing any port externally.
- Model files are excluded via `.gitignore`.


