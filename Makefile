-include .env

PROJECT_PREFIX ?= $(shell basename "$(CURDIR)" | tr '[:upper:]' '[:lower:]' | sed 's/[^a-z0-9][^a-z0-9]*/-/g; s/^-//; s/-$$//')
IMAGE ?= $(PROJECT_PREFIX)-claude:latest
PROJECT_DIR ?= /app
DOCKERFILE ?= docker/claude/Dockerfile
USER_ID ?= $(shell id -u)
GROUP_ID ?= $(shell id -g)
CLAUDE_ACCOUNTS_DIR ?= .claude-accounts
CLAUDE_CONFIG_DIR ?= /home/claude/.claude
CONTAINER_SSH_DIR ?= /home/claude/.ssh
SSH_DIR ?= .ssh
SSH_KEY ?= $(SSH_DIR)/id_ed25519
SSH_CONFIG ?= $(SSH_DIR)/config
SSH_KNOWN_HOSTS ?= $(SSH_DIR)/known_hosts
SSH_COMMENT ?= $(PROJECT_PREFIX)-claude@$(shell hostname)
GIT_REMOTE_URL ?= $(shell git remote get-url origin 2>/dev/null)
GIT_HOST ?= $(shell printf '%s\n' "$(GIT_REMOTE_URL)" | sed -n 's#.*@\([^:/]*\).*#\1#p; s#https\?://\([^/]*\).*#\1#p' | head -n 1)
GIT_USER ?= git
COMPOSE ?= docker compose
# Интерполяция compose выполняется для всего файла до применения профилей,
# поэтому команды, не запускающие сервис `claude`, всё равно требуют
# CLAUDE_PROFILE. Заглушка ничего не монтирует: сервис при этом не стартует.
COMPOSE_WITHOUT_CLAUDE ?= CLAUDE_PROFILE=- $(COMPOSE)
CLAUDE_SERVICE ?= claude
CLAUDE_SHELL ?= bash

# Значения передаются в docker compose: сервис `claude` берёт из них
# тег образа, аргументы сборки, точки монтирования и выбранный аккаунт.
export IMAGE PROJECT_DIR USER_ID GROUP_ID
export CLAUDE_ACCOUNTS_DIR CLAUDE_CONFIG_DIR SSH_DIR CONTAINER_SSH_DIR CLAUDE_PROFILE

.PHONY: help ssh-key ssh-pub rebuild up down restart claude claude-shell

help:
	@printf '%s\n' 'Доступные команды:'
	@printf '%s\n' '  make ssh-key             # создать SSH-ключ в SSH_KEY'
	@printf '%s\n' '  make ssh-pub             # вывести публичный ключ'
	@printf '%s\n' '  make rebuild             # собрать образ Claude Code (единственная сборка образа)'
	@printf '%s\n' '  make claude CLAUDE_PROFILE=<профиль>        # запустить Claude Code в сети окружения'
	@printf '%s\n' '  make claude-shell CLAUDE_PROFILE=<профиль>  # войти в shell контейнера Claude Code'
	@printf '%s\n' '  make up                  # поднять окружение в фоне'
	@printf '%s\n' '  make down                # остановить окружение и удалить контейнеры'
	@printf '%s\n' '  make restart             # пересоздать окружение (down + up)'
	@printf '%s\n' ''
	@printf '%s\n' 'Переменные:'
	@printf '%s\n' '  PROJECT_PREFIX           # префикс проекта для тегов и ключей'
	@printf '%s\n' '  IMAGE                    # тег Docker-образа'
	@printf '%s\n' '  SSH_KEY                  # путь к приватному ключу проекта'
	@printf '%s\n' '  COMPOSE                  # команда docker compose'
	@printf '%s\n' '  CLAUDE_SERVICE           # имя сервиса Claude Code в docker-compose.yml'
	@printf '%s\n' '  CLAUDE_PROFILE           # каталог аккаунта в CLAUDE_ACCOUNTS_DIR, обязателен'
	@printf '%s\n' '  CLAUDE_SHELL             # оболочка для входа в контейнер Claude Code'

ssh-key:
	@for dir in "$(SSH_DIR)" "$$(dirname "$(SSH_KEY)")" "$$(dirname "$(SSH_CONFIG)")" "$$(dirname "$(SSH_KNOWN_HOSTS)")"; do \
		if [ -n "$$dir" ] && [ "$$dir" != "." ]; then \
			mkdir -p "$$dir"; \
			chmod 700 "$$dir"; \
		fi; \
	done
	@for file in "$(SSH_KEY)" "$(SSH_KEY).pub" "$(SSH_CONFIG)" "$(SSH_KNOWN_HOSTS)"; do \
		if [ -L "$$file" ] && [ ! -e "$$file" ]; then \
			unlink "$$file"; \
		fi; \
	done
	@touch "$(SSH_KNOWN_HOSTS)"
	@chmod 600 "$(SSH_KNOWN_HOSTS)"
	@if [ -f "$(SSH_KEY)" ]; then \
		printf '%s\n' "Ключ уже существует: $(SSH_KEY)"; \
	else \
		ssh-keygen -t ed25519 -N "" -C "$(SSH_COMMENT)" -f "$(SSH_KEY)"; \
		chmod 600 "$(SSH_KEY)"; \
		chmod 644 "$(SSH_KEY).pub"; \
	fi
	@if [ ! -f "$(SSH_CONFIG)" ] && [ -n "$(GIT_HOST)" ]; then \
		{ \
			printf 'Host %s\n' "$(GIT_HOST)"; \
			printf '    HostName %s\n' "$(GIT_HOST)"; \
			printf '    User %s\n' "$(GIT_USER)"; \
			printf '    IdentityFile ~/.ssh/%s\n' "$$(basename "$(SSH_KEY)")"; \
			printf '    IdentitiesOnly yes\n'; \
			printf '    StrictHostKeyChecking accept-new\n'; \
			printf '    UserKnownHostsFile ~/.ssh/%s\n' "$$(basename "$(SSH_KNOWN_HOSTS)")"; \
		} > "$(SSH_CONFIG)"; \
		chmod 600 "$(SSH_CONFIG)"; \
	elif [ ! -f "$(SSH_CONFIG)" ]; then \
		printf '%s\n' "GIT_HOST не определён, SSH config не создан"; \
	fi
	@printf '%s\n' "Публичный ключ:"
	@cat "$(SSH_KEY).pub"

ssh-pub:
	@if [ ! -f "$(SSH_KEY).pub" ]; then \
		printf '%s\n' "Публичный ключ не найден. Сначала выполните: make ssh-key" >&2; \
		exit 1; \
	fi
	@cat "$(SSH_KEY).pub"

# Образы собираются только явно: в docker-compose.yml у сервисов с локальным тегом
# стоит pull_policy: never, поэтому `run` и `up` берут готовый образ и не пересобирают
# его. После правки Dockerfile пересборку нужно запускать этой целью.
rebuild:
	docker build \
		--build-arg USER_ID="$(USER_ID)" \
		--build-arg GROUP_ID="$(GROUP_ID)" \
		--build-arg PROJECT_DIR="$(PROJECT_DIR)" \
		-t "$(IMAGE)" \
		-f "$(DOCKERFILE)" \
		.

claude:
	$(COMPOSE) run --rm "$(CLAUDE_SERVICE)" claude

claude-shell:
	$(COMPOSE) run --rm "$(CLAUDE_SERVICE)" "$(CLAUDE_SHELL)"

up:
	$(COMPOSE_WITHOUT_CLAUDE) up -d

down:
	$(COMPOSE_WITHOUT_CLAUDE) down

restart:
	$(MAKE) down
	$(MAKE) up

