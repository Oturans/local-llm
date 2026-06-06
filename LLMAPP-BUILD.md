llmapp сборки для моего ноута с дискретной графикой

Что это за файл
- Пошаговый гайд, как собрать и запустить локальный llmapp на MacBook Pro 16 2019 (Intel + AMD 5600M).
- Цель: максимальная скорость инференса через Metal на хосте и удобный единый API через Docker.

Машина и ограничения
- CPU: Intel i9-9980HK
- RAM: 64 GB
- GPU: AMD Radeon Pro 5600M, 8 GB HBM2
- Важно: на macOS Intel Docker обычно не дает полноценный GPU passthrough для llama.cpp.
- Вывод: llama.cpp запускаем нативно, Docker используем как API-шлюз.

Итоговая схема
- llama-server #1 (host, GPU): быстрая модель 8B
- llama-server #2 (host, CPU/partial GPU): более тяжелая модель
- LiteLLM (docker): один endpoint для клиентов

1) Подготовка системы
1. Подключи ноутбук к питанию.
2. Отключи Automatic graphics switching.
3. Проверь инструменты:

```bash
xcode-select -p
brew --version
docker --version
```

Если xcode-select не настроен:

```bash
xcode-select --install
```

2) Создай структуру проекта
Выполняй из папки local-llm:

```bash
mkdir -p models
mkdir -p config
```

Ожидаемо:
- models: GGUF файлы моделей
- config: конфиги LiteLLM

3) Установка llama.cpp
Вариант A (быстро): через brew

```bash
brew install llama.cpp
which llama-server
llama-server --help | head
```

Что это дает:
- Быстрая установка готового бинарника.
- На macOS Metal обычно уже включен в сборке.

Вариант B (полный контроль, рекомендовано если нужна 100% гарантия Metal)

```bash
git clone https://github.com/ggerganov/llama.cpp
cd llama.cpp
cmake -B build -DGGML_METAL=ON
cmake --build build -j
./build/bin/llama-server --help | head
```

Что это дает:
- Ты явно задаешь GGML_METAL=ON.
- Удобно для диагностики и воспроизводимой сборки.

4) Подготовка моделей
Положи GGUF-файлы в папку models.
Рекомендованные стартовые профили:
- Fast: 8B Instruct Q4_K_M
- Strong: 14B Instruct Q4_K_M (будет медленнее)

Пример имен:
- models/Llama-3.1-8B-Instruct-Q4_K_M.gguf
- models/Qwen2.5-14B-Instruct-Q4_K_M.gguf

5) Запуск двух нативных API-серверов
Терминал 1 (Fast, GPU):

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

Терминал 2 (Strong, стабильный):

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

Для чего:
- 8080: быстрые повседневные запросы.
- 8081: более сложные задачи с приоритетом качества.

6) Проверка, что серверы живы

```bash
curl http://127.0.0.1:8080/health
curl http://127.0.0.1:8081/health
```

Если health не поддерживается в твоем билде, проверь через chat/completions.

7) Подключаем Docker-шлюз (LiteLLM)
Создай файл config/litellm_config.yaml:

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

Создай docker-compose.yml в корне local-llm:

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

Запуск:

```bash
docker compose up -d
docker compose ps
```

8) Проверка единого API

```bash
curl http://127.0.0.1:4000/health
curl http://127.0.0.1:4000/v1/models \
  -H "Authorization: Bearer sk-local-master"
```

Тест local-fast:

```bash
curl http://127.0.0.1:4000/v1/chat/completions \
  -H "Authorization: Bearer sk-local-master" \
  -H "Content-Type: application/json" \
  -d '{
    "model": "local-fast",
    "messages": [{"role": "user", "content": "Сделай короткий план миграции"}],
    "temperature": 0.2,
    "max_tokens": 200
  }'
```

Тест local-strong:

```bash
curl http://127.0.0.1:4000/v1/chat/completions \
  -H "Authorization: Bearer sk-local-master" \
  -H "Content-Type: application/json" \
  -d '{
    "model": "local-strong",
    "messages": [{"role": "user", "content": "Сравни 2 архитектуры и риски"}],
    "temperature": 0.2,
    "max_tokens": 300
  }'
```

9) Тюнинг под твое железо
Порядок действий при проблемах:
1. Уменьшить context: 4096 -> 3072 -> 2048.
2. Уменьшить ngl на GPU-профиле.
3. Снизить batch (-b).
4. Перейти на более легкую квантовку/модель.

Практика:
- Не пытайся агрессивно грузить VRAM сразу двумя тяжелыми моделями.
- Для стабильности оставляй GPU в основном fast-профиле.

10) Как запускать каждый день
1. Запускаешь оба llama-server.
2. Поднимаешь docker compose.
3. Все клиенты отправляют запросы только на порт 4000.
4. Модель выбираешь по model: local-fast или local-strong.

11) Частые проблемы
- Медленно: проверь, что fast-модель действительно с ngl > 0.
- Падения/OOM: уменьши context и ngl.
- Docker не достучался до хоста: проверь host.docker.internal и порты 8080/8081.

12) Что считать успешной сборкой llmapp
- Оба llama-server стабильно отвечают.
- LiteLLM возвращает список моделей.
- Оба тестовых запроса проходят через единый endpoint на 4000.
- Система работает без постоянного swap и без вылетов.
