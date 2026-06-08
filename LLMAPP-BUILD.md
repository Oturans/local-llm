# LLMAPP Build Guide — MacBook Pro 16 (2019), Intel + AMD 5600M

## About this file
- Step-by-step guide to build and run a local llmapp on MacBook Pro 16 2019 (Intel + AMD 5600M).
- Goal: maximum inference speed via Metal on the host, with a single unified API via Docker.

## Hardware and constraints
- CPU: Intel i9-9980HK
- RAM: 64 GB
- GPU: AMD Radeon Pro 5600M, 8 GB HBM2
- Note: on macOS Intel, Docker does not provide reliable GPU passthrough for llama.cpp.
- Conclusion: run llama.cpp natively; use Docker as an API gateway only.

> **GPU STATUS:** AMD Radeon Pro 5600M on Intel Mac x86_64 does NOT work with Metal compute in llama.cpp.
> Use `ngl=0` (CPU-only). For GPU acceleration, Apple Silicon (M1/M2/M3/M4) is required.

## Target architecture
- llama-server #1 (host, GPU on Apple Silicon / CPU on Intel): fast 8B model
- llama-server #2 (host, CPU or partial GPU): heavier model
- LiteLLM (Docker): single endpoint for all clients

## 1) System preparation
1. Connect the laptop to power.
2. Disable Automatic graphics switching.
3. Check tools:

```bash
xcode-select -p
brew --version
docker --version
```

If xcode-select is not configured:

```bash
xcode-select --install
```

## 2) Create project structure
Run from the local-llm folder:

```bash
mkdir -p models
mkdir -p config
```

Expected:
- `models/` — GGUF model files
- `config/` — LiteLLM config files

## 3) Install llama.cpp

### Option A (quick): via brew

```bash
brew install llama.cpp
which llama-server
llama-server --help | head
```

What this gives:
- Fast installation of a prebuilt binary.
- Metal is usually already enabled in the brew build (Apple Silicon only).

### Option B (full control, recommended if you need 100% Metal guarantee)

```bash
git clone https://github.com/ggerganov/llama.cpp
cd llama.cpp
cmake -B build -DGGML_METAL=ON
cmake --build build -j
./build/bin/llama-server --help | head
```

What this gives:
- You explicitly set GGML_METAL=ON.
- Useful for diagnostics and reproducible builds.

## 4) Prepare models
Place GGUF files in the `models/` folder.
Recommended starting profiles:
- Fast: 8B Instruct Q4_K_M
- Strong: 14B Instruct Q4_K_M (slower)

Example filenames:
- `models/Llama-3.1-8B-Instruct-Q4_K_M.gguf`
- `models/Qwen2.5-14B-Instruct-Q4_K_M.gguf`

## 5) Start two native API servers

Terminal 1 (Fast, Apple Silicon GPU / Intel CPU):

```bash
llama-server \
  -m ./models/Llama-3.1-8B-Instruct-Q4_K_M.gguf \
  -c 4096 \
  -ngl 999 \
  -t 10 \
  -b 512 \
  --host 127.0.0.1 \
  --port 8080
```

> On Intel Mac with AMD 5600M, use `-ngl 0` (CPU-only). Metal does not work correctly.

Terminal 2 (Strong, CPU-only):

```bash
llama-server \
  -m ./models/Qwen2.5-14B-Instruct-Q4_K_M.gguf \
  -c 3072 \
  -ngl 0 \
  -t 12 \
  -b 256 \
  --host 127.0.0.1 \
  --port 8081
```

Purpose:
- 8080: fast everyday requests.
- 8081: more complex tasks where quality is the priority.

## 6) Verify servers are alive

```bash
curl http://127.0.0.1:8080/health
curl http://127.0.0.1:8081/health
```

If health endpoint is not supported in your build, test via chat/completions.

## 7) Connect Docker gateway (LiteLLM)

Create `config/litellm_config.yaml`:

```yaml
model_list:
  - model_name: local-fast
    litellm_params:
      model: openai/local-fast
      api_base: http://host.docker.internal:8080/v1
      api_key: dummy

  - model_name: local-strong
    litellm_params:
      model: openai/local-strong
      api_base: http://host.docker.internal:8081/v1
      api_key: dummy

general_settings:
  master_key: sk-local-master
```

Create `docker-compose.yml` in the local-llm root:

```yaml
services:
  litellm:
    image: ghcr.io/berriai/litellm:main-latest
    container_name: litellm
    ports:
      - "4000:4000"
    volumes:
      - ./config/litellm_config.yaml:/app/config.yaml:ro
    command: ["--config", "/app/config.yaml", "--port", "4000", "--host", "0.0.0.0"]
    restart: unless-stopped
```

Start:

```bash
docker compose up -d
docker compose ps
```

## 8) Verify unified API

```bash
curl http://127.0.0.1:4000/health
curl http://127.0.0.1:4000/v1/models \
  -H "Authorization: Bearer sk-local-master"
```

Test local-fast:

```bash
curl http://127.0.0.1:4000/v1/chat/completions \
  -H "Authorization: Bearer sk-local-master" \
  -H "Content-Type: application/json" \
  -d '{
    "model": "local-fast",
    "messages": [{"role": "user", "content": "Write a short migration plan"}],
    "temperature": 0.2,
    "max_tokens": 200
  }'
```

Test local-strong:

```bash
curl http://127.0.0.1:4000/v1/chat/completions \
  -H "Authorization: Bearer sk-local-master" \
  -H "Content-Type: application/json" \
  -d '{
    "model": "local-strong",
    "messages": [{"role": "user", "content": "Compare 2 architectures and their risks"}],
    "temperature": 0.2,
    "max_tokens": 300
  }'
```

## 9) Tuning for your hardware

Steps when encountering problems:
1. Reduce context: 4096 -> 3072 -> 2048.
2. Reduce `ngl` on the GPU profile.
3. Reduce batch size (`-b`).
4. Switch to a lighter quantization or smaller model.

Best practices:
- Do not aggressively load VRAM with two heavy models simultaneously.
- For stability, keep GPU primarily on the fast profile.

## 10) Daily startup routine
1. Start both llama-server processes.
2. Bring up docker compose.
3. All clients send requests only to port 4000.
4. Select the model using the `model` field: `local-fast` or `local-strong`.

## 11) Common issues
- Slow: verify the fast model is actually running with `ngl > 0` (Apple Silicon only).
- Crashes/OOM: reduce context and `ngl`.
- Docker cannot reach the host: check `host.docker.internal` and ports 8080/8081.

## 12) Definition of a successful llmapp build
- Both llama-server instances respond stably.
- LiteLLM returns the model list.
- Both test requests pass through the unified endpoint on port 4000.
- System runs without constant swap usage or crashes.
