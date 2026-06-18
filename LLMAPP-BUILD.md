# LLMAPP Build Guide — MacBook Pro 16 (2019), Intel + AMD 5600M

## About this file
- Step-by-step guide to build and run a local llmapp on MacBook Pro 16 2019 (Intel + AMD 5600M).
- Goal: maximum inference speed via Metal on the host, with a single unified API via Docker.

## Machine Specs
- CPU: Intel i9-9980HK
- RAM: 64 GB
- GPU: AMD Radeon Pro 5600M, 8 GB HBM2

---

## Installing llama.cpp

### Option A: Via Homebrew (Quickest)

```bash
brew install llama.cpp
which llama-server
llama-server --version
```

**What you get:** Pre-built binary with Metal support included. Fast setup, but version may be slightly outdated.

---

### Option B: Build from Source (Recommended)

Two build variants are available:

#### Build B-1: CPU Build (Recommended for Stability)
Use this if you experience 'garbage' output or GPU Timeout errors with Metal.

```bash
git clone https://github.com/ggerganov/llama.cpp
cd llama.cpp
cmake -B build-cpu -DGGML_METAL=OFF -DCMAKE_BUILD_TYPE=Release
cmake --build build-cpu -j
```

**What you get:**
- 100% stable operation, no GPU-related corruption.
- ~10 t/s inference speed on i9-9980HK for 4B models.
- Optimized for your specific CPU with -march=native.

#### Build B-2: GPU Build (Metal, Experimental)
Provides accelerated inference but may cause issues on AMD 5600M.

```bash
git clone https://github.com/ggerganov/llama.cpp
cd llama.cpp
cmake -B build-metal -DGGML_METAL=ON -DGGML_METAL_EMBED_LIBRARY=ON -DGGML_METAL_NDEBUG=ON -DCMAKE_BUILD_TYPE=Release
cmake --build build-metal -j
```

**What you get:**
- GPU acceleration on capable hardware.
- May cause 'garbage' output and GPU Timeout on AMD 5600M.
- If issues occur, switch to CPU build.

---

## Optimal Launch Parameters

### For CPU Build (Recommended)
```bash
./build-cpu/bin/llama-server \
  -m ./models/model.gguf \
  -c 4096 \
  -ngl 0 \
  -t 12 \
  -b 512 \
  --flash-attn off \
  --port 8080
```

Parameters explained:
- -ngl 0: all computations on CPU (stable).
- -t 12: use 12 threads (optimal for i9).
- -b 512: optimal batch size.
- --flash-attn off: disable for stability.

### For GPU Build (If Using)
```bash
./build-metal/bin/llama-server \
  -m ./models/model.gguf \
  -c 4096 \
  -ngl 10 \
  -t 10 \
  -b 64 \
  --flash-attn off \
  --port 8080
```

Parameters explained:
- -ngl 10: only 10 layers on GPU (reduce garbage risk).
- -b 64: small batch to avoid GPU Timeout.
- If still experiencing issues, switch to CPU build.
