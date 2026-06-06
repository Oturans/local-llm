SHELL := /bin/zsh

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

health:
	curl -sS http://127.0.0.1:$${LITELLM_PORT:-4000}/health | cat

models:
	curl -sS http://127.0.0.1:$${LITELLM_PORT:-4000}/v1/models \
	  -H "Authorization: Bearer sk-local-change-me" | cat
