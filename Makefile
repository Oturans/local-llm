SHELL := /bin/zsh

-include .env

MODELS_DIR := ./models
FAST_MODEL  := $(MODELS_DIR)/Meta-Llama-3.1-8B-Instruct-Q4_K_M.gguf
STRONG_MODEL := $(MODELS_DIR)/Qwen2.5-14B-Instruct-Q4_K_M.gguf
LLAMA_SERVER_BIN ?=
LLAMA_SERVER ?= $(if $(LLAMA_SERVER_BIN),$(LLAMA_SERVER_BIN),$(shell if command -v llama-server >/dev/null 2>&1; then command -v llama-server; elif [ -x /opt/homebrew/bin/llama-server ]; then echo /opt/homebrew/bin/llama-server; elif [ -x /usr/local/bin/llama-server ]; then echo /usr/local/bin/llama-server; elif [ -x /opt/homebrew/opt/llama.cpp/bin/llama-server ]; then echo /opt/homebrew/opt/llama.cpp/bin/llama-server; elif [ -x /usr/local/opt/llama.cpp/bin/llama-server ]; then echo /usr/local/opt/llama.cpp/bin/llama-server; fi))
LITELLM_PORT ?= 4000
MASTER_KEY   ?= sk-local-change-me

# ── Docker ────────────────────────────────────────────────────────────────────

up:
	docker compose up -d

down:
	docker compose down

restart:
	docker compose down && docker compose up -d

logs:
	docker compose logs -f litellm

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
	./scripts/download-models.sh all

download-fast:
	./scripts/download-models.sh fast

download-strong:
	./scripts/download-models.sh strong

ls-models:
	@ls -lh $(MODELS_DIR)/*.gguf 2>/dev/null || echo "Нет gguf файлов в $(MODELS_DIR)"

# ── llama-server (native, background via nohup) ───────────────────────────────

check-llama-server:
	@if [ -z "$(LLAMA_SERVER)" ]; then \
		echo "llama-server not found."; \
		echo "Install it with: brew install llama.cpp"; \
		echo "Or build from source with GGML_METAL=ON and set LLAMA_SERVER_BIN=/full/path/to/llama-server"; \
		exit 1; \
	fi

serve-fast: check-llama-server
	@echo "Запуск fast-сервера (GPU) на порту 8080..."
	nohup $(LLAMA_SERVER) \
	  -m $(FAST_MODEL) \
	  -c 4096 -ngl 999 -t 10 -b 512 \
	  --host 127.0.0.1 --port 8080 \
	  > logs/llama-fast.log 2>&1 & echo $$! > .pid-fast
	@echo "PID: $$(cat .pid-fast) | лог: logs/llama-fast.log"

serve-strong: check-llama-server
	@echo "Запуск strong-сервера (CPU) на порту 8081..."
	nohup $(LLAMA_SERVER) \
	  -m $(STRONG_MODEL) \
	  -c 3072 -ngl 0 -t 12 -b 256 \
	  --host 127.0.0.1 --port 8081 \
	  > logs/llama-strong.log 2>&1 & echo $$! > .pid-strong
	@echo "PID: $$(cat .pid-strong) | лог: logs/llama-strong.log"

serve-all: serve-fast serve-strong
	@echo "Оба сервера запущены."

stop-fast:
	@if [ -f .pid-fast ]; then kill $$(cat .pid-fast) && rm .pid-fast && echo "fast остановлен"; else echo "fast не запущен"; fi

stop-strong:
	@if [ -f .pid-strong ]; then kill $$(cat .pid-strong) && rm .pid-strong && echo "strong остановлен"; else echo "strong не запущен"; fi

stop-all: stop-fast stop-strong

logs-fast:
	tail -f logs/llama-fast.log

logs-strong:
	tail -f logs/llama-strong.log

# ── Полный старт (скачать + запустить серверы + поднять docker) ───────────────

bootstrap: download check-llama-server serve-all up
	@echo "=== bootstrap завершён ==="
	@echo "  llama fast  -> http://127.0.0.1:8080"
	@echo "  llama strong-> http://127.0.0.1:8081"
	@echo "  LiteLLM API -> http://127.0.0.1:$(LITELLM_PORT)"

.PHONY: up down restart logs ps health list-models \
        download download-fast download-strong ls-models \
        check-llama-server serve-fast serve-strong serve-all stop-fast stop-strong stop-all \
        logs-fast logs-strong bootstrap
