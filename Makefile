SHELL := /bin/zsh

-include .env

MODELS_DIR := ./models
FAST_MODEL  := $(MODELS_DIR)/gemma-4-12b-it-Q3_K_S.gguf
LLAMA_SERVER_BIN ?=
LLAMA_SERVER ?= $(if $(LLAMA_SERVER_BIN),$(LLAMA_SERVER_BIN),$(shell if command -v llama-server >/dev/null 2>&1; then command -v llama-server; elif [ -x /opt/homebrew/bin/llama-server ]; then echo /opt/homebrew/bin/llama-server; elif [ -x /usr/local/bin/llama-server ]; then echo /usr/local/bin/llama-server; elif [ -x /opt/homebrew/opt/llama.cpp/bin/llama-server ]; then echo /opt/homebrew/opt/llama.cpp/bin/llama-server; elif [ -x /usr/local/opt/llama.cpp/bin/llama-server ]; then echo /usr/local/opt/llama.cpp/bin/llama-server; fi))
LITELLM_PORT ?= 4000
MASTER_KEY   ?= sk-local-change-me
# ngl=99 = offload all layers to GPU.
# Metal backend on AMD Radeon Pro 5600M (Intel Mac) produces garbled output
# and GPU timeouts (kIOAccelCommandBufferCallbackErrorTimeout) across all
# tested llama.cpp builds (9430, 10369, 10582). Use the Vulkan build instead
# (build-vulkan with MoltenVK) - it works correctly and faster than CPU.
# Requires flash-attn on for Vulkan (-fa on) to avoid hangs on longer prompts.
FAST_NGL     ?= 99
# Context size tuned for opencode (code agent): gemma-4-12b Q3_K_S (4.8GB) +
# KV-cache for 64K ctx (~1.5GB) = ~6.5GB of 8GB VRAM (~80% utilization).
# 64K context fits large files + project trees. -np 1 = single slot (full ctx
# in one conversation, not split across 4 slots).
FAST_CTX     ?= 65536
# Threads: with full GPU offload (-ngl 99) CPU only does prompt-processing,
# so few threads are optimal (2 = good for most prompts).
FAST_THREADS ?= 2
# Parallel slots. 1 = dedicated to one opencode session (uses full context).
FAST_NP      ?= 1

# ── Docker ────────────────────────────────────────────────────────────────────

up:
	docker compose up -d open-webui

up-all:
	docker compose up -d

up-litellm:
	docker compose up -d postgres litellm

up-openwebui:
	docker compose up -d open-webui

down:
	docker compose down

down-litellm:
	docker compose stop litellm postgres

down-openwebui:
	docker compose stop open-webui

restart:
	docker compose down && docker compose up -d open-webui

restart-litellm:
	docker compose restart litellm

restart-openwebui:
	docker compose restart open-webui

logs:
	docker compose logs -f open-webui

logs-litellm:
	docker compose logs -f litellm

logs-openwebui:
	docker compose logs -f open-webui

ps:
	docker compose ps

# ── API checks ────────────────────────────────────────────────────────────────

health:
	curl -sS http://127.0.0.1:$(LITELLM_PORT)/health | cat

list-models:
	curl -sS http://127.0.0.1:$(LITELLM_PORT)/v1/models \
	  -H "Authorization: Bearer $(MASTER_KEY)" | cat

# ── Models ────────────────────────────────────────────────────────────────────

download:
	./scripts/download-models.sh fast

download-fast:
	./scripts/download-models.sh fast

ls-models:
	@ls -lh $(MODELS_DIR)/*.gguf 2>/dev/null || echo "No gguf files in $(MODELS_DIR)"

# ── llama-server (native, background via nohup) ───────────────────────────────

check-llama-server:
	@if [ -z "$(LLAMA_SERVER)" ]; then \
		echo "llama-server not found."; \
		echo "Install it with: brew install llama.cpp"; \
		echo "Or build from source with GGML_METAL=ON and set LLAMA_SERVER_BIN=/full/path/to/llama-server"; \
		exit 1; \
	fi

serve-fast: check-llama-server
	@echo "Starting fast server on port 8080 (FAST_NGL=$(FAST_NGL), ctx=$(FAST_CTX), np=$(FAST_NP))..."
	nohup $(LLAMA_SERVER) \
	  -m $(FAST_MODEL) \
	  -c $(FAST_CTX) -np $(FAST_NP) -ngl $(FAST_NGL) -t $(FAST_THREADS) -b 512 -fa on \
	  --host 127.0.0.1 --port 8080 \
	  $(FAST_EXTRA_ARGS) \
	  > logs/llama-fast.log 2>&1 & echo $$! > .pid-fast
	@echo "PID: $$(cat .pid-fast) | log: logs/llama-fast.log"

serve-all: serve-fast
	@echo "Fast server started."

# ── Qwen3.8-27B (27B dense, hybrid CPU+GPU or pure CPU) ───────────────────────
# 27B model does NOT fit fully in 8GB VRAM. Two presets:
#   serve-qwen3-cpu    : ngl=0, pure CPU (slow, ~1-2 t/s, but stable)
#   serve-qwen3-hybrid : ngl=auto, offload as much as fits in VRAM, rest on CPU
# Override model file / ngl via env:
#   make serve-qwen3-hybrid QWEN3_FILE=...Qwen3.8-27B-UD-Q4_K_S.gguf QWEN3_NGL=20

QWEN3_FILE  ?= $(MODELS_DIR)/Qwen3.8-27B-UD-IQ2_S.gguf
QWEN3_NGL   ?= 0
QWEN3_CTX   ?= 2048
QWEN3_PORT  ?= 8081

serve-qwen3-cpu: check-llama-server
	@echo "Starting Qwen3.8-27B on port $(QWEN3_PORT) (CPU-only, ngl=0)..."
	nohup $(LLAMA_SERVER) \
	  -m $(QWEN3_FILE) \
	  -c $(QWEN3_CTX) -ngl 0 -t 8 -b 512 -fa on \
	  --host 127.0.0.1 --port $(QWEN3_PORT) \
	  $(QWEN3_EXTRA_ARGS) \
	  > logs/llama-qwen3.log 2>&1 & echo $$! > .pid-qwen3
	@echo "PID: $$(cat .pid-qwen3) | log: logs/llama-qwen3.log"

serve-qwen3-hybrid: check-llama-server
	@echo "Starting Qwen3.8-27B on port $(QWEN3_PORT) (hybrid, ngl=$(QWEN3_NGL))..."
	nohup $(LLAMA_SERVER) \
	  -m $(QWEN3_FILE) \
	  -c $(QWEN3_CTX) -ngl $(QWEN3_NGL) -t 8 -b 512 -fa on \
	  --host 127.0.0.1 --port $(QWEN3_PORT) \
	  $(QWEN3_EXTRA_ARGS) \
	  > logs/llama-qwen3.log 2>&1 & echo $$! > .pid-qwen3
	@echo "PID: $$(cat .pid-qwen3) | log: logs/llama-qwen3.log"

stop-qwen3:
	@if [ -f .pid-qwen3 ]; then kill $$(cat .pid-qwen3) && rm .pid-qwen3 && echo "qwen3 stopped"; else echo "qwen3 is not running"; fi

logs-qwen3:
	@tail -f logs/llama-qwen3.log

stop-fast:
	@if [ -f .pid-fast ]; then kill $$(cat .pid-fast) && rm .pid-fast && echo "fast stopped"; else echo "fast is not running"; fi

stop-all: stop-fast stop-qwen3

check-process-files:
	@for pidfile in .pid-fast; do \
		if [ -f "$$pidfile" ]; then \
			pid=$$(cat "$$pidfile"); \
			if kill -0 "$$pid" 2>/dev/null; then \
					echo "$$pidfile -> PID $$pid alive"; \
				else \
					echo "$$pidfile -> PID $$pid dead"; \
				fi; \
		else \
			echo "$$pidfile -> file not found"; \
	done

stop-process-files: check-process-files
	@for pidfile in .pid-fast; do \
		if [ -f "$$pidfile" ]; then \
			pid=$$(cat "$$pidfile"); \
			if kill -0 "$$pid" 2>/dev/null; then \
					kill "$$pid" && echo "stopped $$pid (from $$pidfile)"; \
				else \
					echo "$$pidfile -> PID $$pid no longer exists"; \
			fi; \
			rm -f "$$pidfile"; \
		fi; \
	done

llama-processes: check-process-files
	@echo "== llama-server processes =="
	@pgrep -af 'llama-server' || echo "No llama-server processes running"

status: llama-processes
	@echo "== docker compose =="
	@docker compose ps 2>/dev/null || echo "docker compose is not running or not available"

logs-fast:
	tail -f logs/llama-fast.log

# ── Full start (download + start servers + bring up docker) ──────────────────

bootstrap: download check-llama-server serve-fast up-openwebui
	@echo "=== bootstrap complete ==="
	@echo "  llama fast  -> http://127.0.0.1:8080"
	@echo "  OpenWebUI   -> http://127.0.0.1:3000"
	@echo "  LiteLLM     -> start separately: make up-litellm"

.PHONY: up up-all up-litellm up-openwebui \
	down down-litellm down-openwebui \
	restart restart-litellm restart-openwebui \
	logs logs-litellm logs-openwebui ps health list-models \
	download download-fast ls-models \
	check-llama-server serve-fast serve-all stop-fast stop-all \
	serve-qwen3-cpu serve-qwen3-hybrid stop-qwen3 logs-qwen3 \
	check-process-files stop-process-files llama-processes status \
	logs-fast bootstrap
