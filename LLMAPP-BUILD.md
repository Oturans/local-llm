# LLMAPP Build Guide — llama.cpp on macOS (CPU / Metal / Vulkan)

## About this file
- Universal guide for building [llama.cpp](https://github.com/ggml-org/llama.cpp) for a local llmapp in three variants: **CPU-only**, **Metal**, and **Vulkan**.
- Anyone who clones this repository can build the backend that fits their hardware.
- Reference machine for notes below: MacBook Pro 16" 2019, Intel i9-9980HK, 64 GB RAM, AMD Radeon Pro 5600M 8 GB HBM2 + Intel UHD 630 (not used for compute).
- On this machine **Metal is broken** (garbage output + GPU timeouts on AMD 5600M), so the working backend there is **Vulkan**. On Apple Silicon (M1–M4) Metal works perfectly and is the preferred choice.

---

## Prerequisites

Before building, verify these tools are installed. On a fresh macOS they are usually missing.

### 1. Homebrew

```bash
brew --version || /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
```

### 2. Xcode Command Line Tools (provides C/C++ compiler)

```bash
xcode-select --version || xcode-select --install
```

### 3. CMake and git (required for all build variants)

```bash
brew install cmake git
cmake --version && git --version
```

### 4. Vulkan dependencies (only for the Vulkan build, B-3)

```bash
brew install molten-vk vulkan-loader glslang shaderc
```

If CMake later fails with `Could NOT find Vulkan (missing: glslc)`, that means `shaderc` is not installed — run `brew install shaderc` and re-run cmake.

### 5. Disk space

- Build artifacts: ~2 GB per build directory
- Models: 2–15 GB per GGUF file
- Recommended free space: at least 20 GB

```bash
df -h .
```

---

## Installing llama.cpp

### Option A: Via Homebrew (Quickest)

```bash
brew install llama.cpp
which llama-server
llama-server --version
```

**What you get:**
- On **Apple Silicon** (M1–M4) the bottle is built with Metal — ready for GPU acceleration.
- On **Intel Mac** the bottle is built **without Metal** (CPU + Accelerate BLAS only) — the GPU is not used. For GPU on Intel Mac, build from source (Option B, Vulkan variant).
- The Vulkan backend is not provided via brew — only from source.

---

### Option B: Build from Source (Recommended)

```bash
git clone https://github.com/ggml-org/llama.cpp
cd llama.cpp
```

#### B-1: CPU-only Build (Fallback, maximum stability)

Use this if there is no GPU, the GPU is not supported, or for debugging.

```bash
cmake -B build-cpu \
  -DGGML_METAL=OFF \
  -DGGML_VULKAN=OFF \
  -DGGML_BLAS=ON \
  -DGGML_BLAS_VENDOR=Apple \
  -DGGML_NATIVE=ON \
  -DCMAKE_BUILD_TYPE=Release
cmake --build build-cpu -j --target llama-server
```

Binary: `build-cpu/bin/llama-server`. 100% stable CPU inference via Apple Accelerate BLAS + `-march=native`.

#### B-2: Metal Build (Recommended for Apple Silicon)

Use on Apple Silicon (M1–M4) — Metal works correctly there and is faster than the alternatives. On Intel Mac with AMD GPU — see the warning below.

```bash
cmake -B build-metal \
  -DGGML_METAL=ON \
  -DGGML_METAL_EMBED_LIBRARY=ON \
  -DGGML_METAL_NDEBUG=ON \
  -DCMAKE_BUILD_TYPE=Release
cmake --build build-metal -j --target llama-server
```

Binary: `build-metal/bin/llama-server`.

**⚠️ Warning for Intel Mac with AMD Radeon (including AMD 5600M):**
The Metal backend on these cards produces **garbage output** (random multilingual characters, repetitions) and/or `kIOAccelCommandBufferCallbackErrorTimeout` (GPU timeout). Confirmed on llama.cpp builds 9430, 10369, 10582. Use **Vulkan** (B-3) instead.

#### B-3: Vulkan Build (Recommended for Intel Mac with AMD GPU)

Vulkan runs via MoltenVK and correctly supports AMD Radeon on Intel Mac. It detects both GPUs (AMD + Intel UHD).

> Prerequisites: install the Vulkan dependencies from the [Prerequisites](#4-vulkan-dependencies-only-for-the-vulkan-build-b-3) section first:
> `brew install molten-vk vulkan-loader glslang shaderc`
>
> - `molten-vk` → `libMoltenVK.dylib` (Vulkan over Metal)
> - `vulkan-loader` → `libvulkan.dylib` + headers
> - `glslang` → `glslangValidator`, `shaderc` → `glslc` (shader compilers, required by CMake `FindVulkan`)

```bash
cmake -B build-vulkan \
  -DGGML_VULKAN=ON \
  -DGGML_METAL=OFF \
  -DGGML_BLAS=ON \
  -DGGML_BLAS_VENDOR=Apple \
  -DGGML_NATIVE=ON \
  -DCMAKE_BUILD_TYPE=Release
cmake --build build-vulkan -j --target llama-server
```

**Common CMake errors:**
- `Could NOT find Vulkan (missing: glslc)` → `brew install shaderc` (provides `glslc`)
- `Could NOT find Vulkan (missing: Vulkan_LIBRARY)` → `brew install vulkan-loader`
- `Could NOT find Vulkan (missing: Vulkan_INCLUDE_DIR)` → `brew install vulkan-headers` (usually pulled in by vulkan-loader)

**Verify the build detects your GPU:**
```bash
./build-vulkan/bin/llama-server --list-devices
```
Expected output on Intel Mac with AMD dGPU:
```
Available devices:
  Vulkan0: AMD Radeon Pro 5600M (8176 MiB, 8175 MiB free)
  Vulkan1: Intel(R) UHD Graphics 630 (65536 MiB, 1527 MiB free)
  BLAS: Accelerate (0 MiB, 0 MiB free)
```

Binary: `build-vulkan/bin/llama-server`.

---

## Optimal Launch Parameters

> Values below are examples. The actual defaults used by this repo are in the `Makefile` variables (`FAST_NGL`, `FAST_CTX`, `FAST_THREADS`, `FAST_NP`) — see the [Integration](#integration-with-makefile-and-env) section.

### CPU Build
```bash
./build-cpu/bin/llama-server \
  -m ./models/model.gguf \
  -c 4096 \
  -ngl 0 \
  -t 8 \
  -b 512 \
  -fa on \
  --host 127.0.0.1 --port 8080
```
- `-ngl 0`: all computation on CPU (stable).
- `-fa on`: flash-attention works on CPU and speeds up long contexts.
- `-t 8`: number of threads (tune for your CPU; 8 is optimal for i9).

### Metal Build
```bash
./build-metal/bin/llama-server \
  -m ./models/model.gguf \
  -c 4096 \
  -ngl 99 \
  -t 8 \
  -b 512 \
  -fa on \
  --host 127.0.0.1 --port 8080
```
- `-ngl 99`: all layers on GPU (if the model fits in VRAM).
- `-fa on`: enable flash-attention.
- If Metal produces garbage output (see troubleshooting) — switch to Vulkan or CPU.

### Vulkan Build
```bash
./build-vulkan/bin/llama-server \
  -m ./models/model.gguf \
  -c 4096 \
  -ngl 99 \
  -t 8 \
  -b 512 \
  -fa on \
  --host 127.0.0.1 --port 8080
```
- `-ngl 99`: all layers on GPU, if the model fits entirely in VRAM.
- `-fa on`: **required** for Vulkan — without it, long prompts hang.
- If the model is **larger than VRAM** (e.g. 27B on an 8 GB card): tune `-ngl` so that model weights + ~1.5 GB for KV-cache ≤ VRAM size. The remaining layers stay on CPU; the speed is then CPU-bound. Example for Qwen3.8-27B Q4_K_S (15.4 GB) on 8 GB VRAM: `-ngl 28`.

---

## Troubleshooting / Known Issues

### Metal: garbage output on AMD 5600M (Intel Mac)
**Symptoms:** random multilingual characters in output, `kIOAccelCommandBufferCallbackErrorTimeout` in logs.
**Cause:** broken Metal blk-kernels (confirmed on builds 9430, 10369, 10582).
**Fix:** use Vulkan (B-3) or CPU (B-1).

### brew bottle on Intel Mac without Metal
`llama-server --list-devices` shows only `BLAS: Accelerate`. brew does not build with Metal on Intel Mac — build from source (B-2 or B-3).

### Vulkan: hangs on long prompts
Always run with `-fa on`. Without it, Vulkan hangs on prompts longer than ~20 tokens.

### `no usable GPU found`
```bash
./build-vulkan/bin/llama-server --list-devices   # Vulkan — should list AMD Radeon
./build-metal/bin/llama-server --list-devices    # Metal
```

### `blk.64.*` tensors ignored (Qwen3.8-27B)
Normal. `blk.64` is MTP (Multi-Token Prediction), used only for training/speculative-decoding. llama.cpp ignores it for regular inference.

---

## Test Cases

Use `scripts/test-model.sh` to verify a model produces correct output after building. The script runs 7 test cases (knowledge, math, coding, reasoning) against a running llama-server instance.

```bash
# Start a server first (in another terminal)
make serve-fast

# Run the test suite
./scripts/test-model.sh 8080 "gemma-4-12b Q3_K_S Vulkan"

# Output: per-test PASS/FAIL + throughput (tg/s) + summary
```

### Test cases

| # | Test | Prompt (short) | Expected |
|---|---|---|---|
| 1 | Capital of France | "What is the capital of France? One word." | `Paris` |
| 2 | Multiplication | "How much is 7 * 8? One number." | `56` |
| 3 | Primary colors | "Name 3 primary colors." | `red`, `blue`, `yellow` |
| 4 | Author | "Who wrote Romeo and Juliet? Author name only." | `Shakespeare` |
| 5 | Chemistry | "What is the chemical symbol for water?" | `H2O` |
| 6 | Coding | "Write a Python palindrome function with docstring and type hints." | `def ... palindrome` |
| 7 | Reasoning | "If A>B and B>C, which is greater: A or C? One letter." | `A` |

### Reference results (2026-08-23, llama.cpp build 10582)

Use these as a baseline when changing builds, models, or settings. A correct setup should pass all 7 cases.

| Backend | Model | -ngl | -ctx | -np | gen t/s | All pass |
|---|---|---|---|---|---|---|
| Vulkan | gemma-3-4b Q4_K_M (2.3 GB) | 99 | 4096 | 4 | 18–20 | 7/7 |
| Vulkan | Llama-3.1-8B Q4_K_M (4.6 GB) | 99 | 4096 | 4 | 14 | 7/7 |
| Vulkan | gemma-4-12b Q3_K_S (4.8 GB) | 99 | 65536 | 1 | 5–8 | 7/7 |
| CPU | gemma-4-12b Q3_K_S (4.8 GB) | 0 | 65536 | 1 | 3.6–4.5 | 7/7 |
| Vulkan hybrid | Qwen2.5-14B Q4_K_M (8.4 GB) | 24 | 2048 | 4 | 5.0 | 7/7 |
| Vulkan hybrid | Qwen3.8-27B Q4_K_S (15.4 GB) | 28 | 2048 | 4 | 1.48 | 7/7 |
| Vulkan hybrid | Qwen3.8-27B IQ3_S (12.0 GB) | 35 | 2048 | 4 | 0.91 | 7/7 |
| CPU | Qwen3.8-27B Q4_K_S (15.4 GB) | 0 | 2048 | 4 | 1.05 | 7/7 |
| Metal | any | >0 | — | — | — | 0/7 (garbage) |

**When to re-run:**
- After rebuilding llama.cpp (new commit / different backend)
- After changing model or quantization
- After changing `-ngl`, `-ctx`, `-np`, `-fa` settings
- As a smoke test before committing changes to the Makefile

---

## Integration with Makefile and .env

Run configuration is stored in `.env` and `Makefile` of this repository.

### .env
```
LLAMA_SERVER_BIN=/path/to/llama.cpp/build-vulkan/bin/llama-server
```
Point this to the binary you want to use (CPU / Metal / Vulkan) — all make targets use this variable.

### Makefile — main targets
```bash
make serve-fast                         # gemma-4-12b on GPU (ngl from FAST_NGL)
make serve-qwen3-cpu     QWEN3_FILE=…   # 27B model, pure CPU
make serve-qwen3-hybrid  QWEN3_FILE=… QWEN3_NGL=28   # 27B model, part on GPU
make stop-fast  | make stop-qwen3       # stop the server
make logs-fast | make logs-qwen3        # view logs
make status                             # process and docker status
```

### Variables (with defaults)
- `FAST_NGL` — GPU layers for serve-fast (99 = all, if it fits).
- `QWEN3_FILE` — path to the GGUF file for serve-qwen3-*.
- `QWEN3_NGL` — GPU layers for serve-qwen3-hybrid (0 = CPU-only).
- `QWEN3_CTX` — context size (default 2048).
- `QWEN3_PORT` — port (default 8081).

For details — see the `Makefile` itself.