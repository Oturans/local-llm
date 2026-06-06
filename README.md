llmapp сборки для моего ноута с дискретной графикой

Цель
- Поднять локальный LLM API на macOS Intel с максимальной производительностью за счет нативного запуска llama.cpp через Metal.
- Использовать Docker для маршрутизации и единого API endpoint, а не для GPU-инференса.

Мой ноутбук
- MacBook Pro 16 (2019)
- CPU: Intel Core i9-9980HK
- RAM: 64 GB
- GPU: AMD Radeon Pro 5600M (8 GB HBM2)

Почему именно такая схема
- На macOS Intel Docker-контейнеры обычно не дают стабильный GPU passthrough для llama.cpp.
- Нативный запуск llama.cpp на хосте позволяет задействовать Metal и дискретную графику.
- Docker при этом удобен для оркестрации: один endpoint, несколько моделей, изоляция обвязки.

Рекомендуемая архитектура
- llama-server #1 на хосте: быстрая 7B/8B модель с GPU offload.
- llama-server #2 на хосте: более тяжелая модель (14B) в CPU-only или с частичным offload.
- LiteLLM в Docker: единая точка входа для клиентов и роутинг по model_name.

Быстрый старт
1. Установить llama.cpp (через brew или сборку из исходников с GGML_METAL=ON).
2. Подготовить GGUF-модели в локальной папке.
3. Запустить два llama-server процесса на разных портах (например, 8080 и 8081).
4. Поднять LiteLLM в Docker на порту 4000.
5. Отправлять запросы на один endpoint и выбирать модель полем model.

Стартовые параметры (профиль)
- Fast (GPU): 8B Q4_K_M, context 4096, ngl 999.
- Strong (стабильный): 14B Q4_K_M, context 3072, ngl 0..40 по стабильности.

Тюнинг стабильности
- При OOM сначала уменьшать context: 4096 -> 3072 -> 2048.
- Если не помогло, снижать ngl.
- Затем переходить на более легкую квантовку или меньшую модель.
- Всегда держать ноутбук на питании и отключить auto graphics switching.

Проверка после запуска
- Проверить health каждого llama-server.
- Проверить список моделей на API шлюзе.
- Выполнить 1-2 тестовых chat/completions запроса с разными model_name.

Что это дает
- Максимум производительности на твоей дискретной графике.
- Параллельный запуск нескольких моделей.
- Удобная интеграция с IDE, скриптами и локальными сервисами через единый API.

Что уже подготовлено в репозитории
- docker-compose.yml: запуск LiteLLM на порту 4000.
- config/litellm_config.yaml: роутинг на два локальных llama-server endpoint.
- .env.example: шаблон переменных окружения.
- .gitignore: исключение локальных моделей и .env.
- Makefile: команды up/down/logs/health/models.

Быстрый запуск LiteLLM
1. Подними локальные llama-server на 8080 и 8081.
2. Запусти LiteLLM:

```bash
make up
```

3. Проверка:

```bash
make health
make list-models
```

Порядок проверки, если связка не работает
1. Сначала проверяй fast-модель напрямую на llama-server (без LiteLLM).
2. Только после этого проверяй LiteLLM на 4000.
3. Если напрямую работает, а через LiteLLM нет, проблема в proxy/DB/config.

Проверка llama-server напрямую (обязательно)
1. Health:

```bash
curl -sS http://127.0.0.1:8080/health
```

2. Тест RU:

```bash
curl -sS http://127.0.0.1:8080/v1/chat/completions \
	-H "Content-Type: application/json" \
	-d '{
		"model": "local-fast",
		"messages": [
			{"role": "system", "content": "Отвечай коротко."},
			{"role": "user", "content": "Ответь по-русски одной фразой: как тебя зовут?"}
		],
		"temperature": 0.2,
		"max_tokens": 80
	}'
```

3. Тест EN:

```bash
curl -sS http://127.0.0.1:8080/v1/chat/completions \
	-H "Content-Type: application/json" \
	-d '{
		"model": "local-fast",
		"messages": [
			{"role": "system", "content": "Answer briefly."},
			{"role": "user", "content": "Reply in one short English sentence: what is your name?"}
		],
		"temperature": 0.2,
		"max_tokens": 80
	}'
```

Проверка через LiteLLM (порт 4000)
1. Health:

```bash
curl -sS http://127.0.0.1:4000/health
```

2. Список моделей:

```bash
curl -sS http://127.0.0.1:4000/v1/models \
	-H "Authorization: Bearer sk-local-change-me"
```

3. Chat через proxy:

```bash
curl -sS http://127.0.0.1:4000/v1/chat/completions \
	-H "Authorization: Bearer sk-local-change-me" \
	-H "Content-Type: application/json" \
	-d '{
		"model": "local-fast",
		"messages": [{"role": "user", "content": "Коротко ответь по-русски: проверка через LiteLLM"}],
		"temperature": 0.2,
		"max_tokens": 80
	}'
```

Если видишь Empty reply from server на 4000
1. Проверь контейнеры:

```bash
docker compose ps
```

2. Проверь, что Postgres healthy.
3. Проверь env в контейнере LiteLLM:

```bash
docker exec litellm env | grep -E "DATABASE_URL|LITELLM_MASTER_KEY|UI_USERNAME|UI_PASSWORD"
```

4. Проверь процессы внутри контейнера:

```bash
docker exec litellm sh -lc 'ps -ef; netstat -ltnp 2>/dev/null | head -30'
```

5. Проверь логи:

```bash
docker logs litellm | tail -100
```

6. Если 8080 напрямую отвечает, а 4000 нет, перезапусти proxy-стек:

```bash
make down
make up
```

7. Если проблема повторяется, проверь корректность DATABASE_URL и config/litellm_config.yaml.

Важно по безопасности
- Перед внешним доступом поменяй ключ в config/litellm_config.yaml (master_key).
- Не коммить .env и GGUF-модели в репозиторий.
