SHELL := /bin/zsh

-include .env

MODELS_DIR := ./models
FAST_MODEL  := $(MODELS_DIR)/google_gemma-3-4b-it-Q4_K_M.gguf
LLAMA_SERVER_BIN ?=
LLAMA_SERVER ?= $(if $(LLAMA_SERVER_BIN),$(LLAMA_SERVER_BIN),$(shell if command -v llama-server >/dev/null 2>&1; then command -v llama-server; elif [ -x /opt/homebrew/bin/llama-server ]; then echo /opt/homebrew/bin/llama-server; elif [ -x /usr/local/bin/llama-server ]; then echo /usr/local/bin/llama-server; elif [ -x /opt/homebrew/opt/llama.cpp/bin/llama-server ]; then echo /opt/homebrew/opt/llama.cpp/bin/llama-server; elif [ -x /usr/local/opt/llama.cpp/bin/llama-server ]; then echo /usr/local/opt/llama.cpp/bin/llama-server; fi))
LITELLM_PORT ?= 4000
MASTER_KEY   ?= sk-local-change-me
FAST_NGL     ?= 0

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
	@echo "Запуск fast-сервера на порту 8080 (FAST_NGL=$(FAST_NGL))..."
	nohup $(LLAMA_SERVER) \
	  -m $(FAST_MODEL) \
	  -c 4096 -ngl $(FAST_NGL) -t 10 -b 512 \
	  --host 127.0.0.1 --port 8080 \
	  > logs/llama-fast.log 2>&1 & echo $$! > .pid-fast
	@echo "PID: $$(cat .pid-fast) | лог: logs/llama-fast.log"

serve-all: serve-fast
	@echo "Fast сервер запущен."

stop-fast:
	@if [ -f .pid-fast ]; then kill $$(cat .pid-fast) && rm .pid-fast && echo "fast остановлен"; else echo "fast не запущен"; fi

stop-all: stop-fast

check-process-files:
	@for pidfile in .pid-fast; do \
		if [ -f "$$pidfile" ]; then \
			pid=$$(cat "$$pidfile"); \
			if kill -0 "$$pid" 2>/dev/null; then \
				echo "$$pidfile -> PID $$pid жив"; \
			else \
				echo "$$pidfile -> PID $$pid мёртв"; \
			fi; \
		else \
			echo "$$pidfile -> файла нет"; \
		fi; \
	done

stop-process-files: check-process-files
	@for pidfile in .pid-fast; do \
		if [ -f "$$pidfile" ]; then \
			pid=$$(cat "$$pidfile"); \
			if kill -0 "$$pid" 2>/dev/null; then \
				kill "$$pid" && echo "остановлен $$pid (из $$pidfile)"; \
			else \
				echo "$$pidfile -> PID $$pid уже не существует"; \
			fi; \
			rm -f "$$pidfile"; \
		fi; \
	done

llama-processes: check-process-files
	@echo "== llama-server процессы =="
	@pgrep -af 'llama-server' || echo "Нет процессов llama-server"

status: llama-processes
	@echo "== docker compose =="
	@docker compose ps 2>/dev/null || echo "docker compose не запущен или недоступен"

logs-fast:
	tail -f logs/llama-fast.log

# ── Полный старт (скачать + запустить серверы + поднять docker) ───────────────

bootstrap: download check-llama-server serve-fast up-openwebui
	@echo "=== bootstrap завершён ==="
	@echo "  llama fast  -> http://127.0.0.1:8080"
	@echo "  OpenWebUI   -> http://127.0.0.1:3000"
	@echo "  LiteLLM     -> запускай отдельно: make up-litellm"

.PHONY: up up-all up-litellm up-openwebui \
	down down-litellm down-openwebui \
	restart restart-litellm restart-openwebui \
	logs logs-litellm logs-openwebui ps health list-models \
	download download-fast ls-models \
	check-llama-server serve-fast serve-all stop-fast stop-all \
	check-process-files stop-process-files llama-processes status \
	logs-fast bootstrap
