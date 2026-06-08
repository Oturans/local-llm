# local-llm

Local LLM stack for MacBook Pro 16 (2019) — Intel i9 + AMD Radeon Pro 5600M.

## Hardware

- **CPU:** Intel Core i9-9980HK
- **RAM:** 64 GB
- **GPU:** AMD Radeon Pro 5600M (8 GB HBM2) — discrete PCIe GPU

## GPU Status

> **GPU inference is not functional on this machine.**

Extensive testing confirmed that AMD Radeon Pro 5600M (discrete PCIe GPU on Intel Mac x86_64)
does not produce correct output with any available Metal backend:

| Tool | GPU detected | Output correct |
|---|---|---|
| llama.cpp (custom build, Metal ON) | yes | no — garbage output |
| Ollama 0.30.6 | no — CPU only | yes |
| brew llama-server 9430 | no — built without Metal | yes |

Root cause: Metal compute kernels in llama.cpp are not validated for discrete AMD GPUs
on Intel Mac x86_64. Apple Silicon (M-series) is the only supported Metal platform.

**Current setup runs CPU-only.** Performance: ~6 t/s with Gemma 3 4B Q4_K_M.

## Architecture

```
OpenWebUI (port 3000)
    |
    v
llama-server (port 8080, CPU, ngl=0)
    |
    model: google_gemma-3-4b-it-Q4_K_M.gguf

LiteLLM proxy (port 4000) — optional, for multi-model routing
    |
    Postgres
```

- **llama-server** runs natively on the host (not in Docker) for direct hardware access.
- **OpenWebUI** runs in Docker, connects directly to llama-server.
- **LiteLLM** runs in Docker, optional — use `make up-litellm` if needed.

## Quick Start

```bash
# 1. Install llama.cpp (brew build, CPU-only on this machine)
brew install llama.cpp

# 2. Download model
make download

# 3. Start llama-server + OpenWebUI
make bootstrap

# 4. Open http://localhost:3000
```

## Makefile targets

| Command | Description |
|---|---|
| `make bootstrap` | Download model, start llama-server + OpenWebUI |
| `make serve-fast` | Start llama-server on port 8080 |
| `make stop-fast` | Stop llama-server |
| `make up-openwebui` | Start OpenWebUI only |
| `make up-litellm` | Start LiteLLM + Postgres |
| `make down` | Stop all Docker services |
| `make logs` | OpenWebUI logs |
| `make health` | Check LiteLLM health |
| `make download` | Download Gemma 3 4B model |

## Environment variables

Copy `.env.example` to `.env` and adjust:

```bash
cp .env.example .env
```

Key variables:

| Variable | Default | Description |
|---|---|---|
| `LLAMA_SERVER_BIN` | auto-detect | Path to llama-server binary |
| `FAST_NGL` | `0` | GPU layers. Keep 0 — Metal is broken on this machine |
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

## Notes on GPU (for future reference)

If running on Apple Silicon Mac, set `FAST_NGL=999` in `.env` to offload all layers to GPU.

On this Intel Mac with AMD Radeon Pro 5600M, `FAST_NGL=0` is the only working configuration.
Any value above 0 causes garbled/garbage output due to broken Metal compute kernels for
discrete AMD GPUs on x86_64.

## Security

- Never commit `.env` or GGUF model files.
- Change `LITELLM_MASTER_KEY` before exposing any port externally.
- Model files are excluded via `.gitignore`.


