# Запуск Claude в Docker-контейнере с раздельными аккаунтами.
# Подключение: source .bashrc (из корня проекта)
#
# Каждый профиль хранит авторизацию и конфиг в своём каталоге:
#   .claude-accounts/<profile>
#
# Создание нового профиля:
#   claude-profile-add <profile>

# Корень проекта определяется по расположению этого файла.
PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

if [ -f "$PROJECT_ROOT/.env" ]; then
  set -a
  # shellcheck disable=SC1091
  . "$PROJECT_ROOT/.env"
  set +a
fi

_usp_claude_require_env() {
  local name="$1"

  if [ -z "${!name:-}" ]; then
    echo "Не задана переменная $name. Проверьте $PROJECT_ROOT/.env" >&2
    return 1
  fi
}

for name in IMAGE PROJECT_DIR CLAUDE_CONFIG_DIR CLAUDE_ACCOUNTS_DIR CONTAINER_SSH_DIR SSH_DIR; do
  _usp_claude_require_env "$name" || return 1
done

# Базовый запуск контейнера под выбранным аккаунтом.
# Использование: _claude_docker_run <account> <команда...>
#
# Запуск идёт через сервис `claude` из docker-compose.yml, поэтому контейнер
# попадает в сеть окружения и видит остальные сервисы по их именам.
# Состав монтирований и переменных описан в docker-compose.yml; здесь
# передаётся только выбор аккаунта через CLAUDE_PROFILE.
#
_claude_docker_run() {
  local account="$1"
  shift
  local account_dir="$PROJECT_ROOT/$CLAUDE_ACCOUNTS_DIR/$account"
  local project_ssh_dir="$PROJECT_ROOT/$SSH_DIR"

  if [ ! -d "$account_dir" ]; then
    echo "Каталог аккаунта не найден: $account_dir" >&2
    return 1
  fi

  if [ ! -d "$project_ssh_dir" ]; then
    echo "Каталог SSH не найден: $project_ssh_dir" >&2
    echo "Сначала выполните: make ssh-key" >&2
    return 1
  fi

  CLAUDE_PROFILE="$account" docker compose \
    --project-directory "$PROJECT_ROOT" \
    -f "$PROJECT_ROOT/docker-compose.yml" \
    run --rm claude "$@"
}

# Создание каталога нового профиля Claude.
# Использование: claude-profile-add <profile>
claude-profile-add() {
  local profile="$1"

  if [ -z "$profile" ]; then
    echo "Укажите имя профиля: claude-profile-add <profile>" >&2
    return 1
  fi

  if [[ ! "$profile" =~ ^[A-Za-z0-9_-]+$ ]]; then
    echo "Имя профиля может содержать только латиницу, цифры, _ и -" >&2
    return 1
  fi

  mkdir -p "$PROJECT_ROOT/$CLAUDE_ACCOUNTS_DIR/$profile"
}

# Запуск claude под выбранным аккаунтом.
# Использование: claude-docker <account>   (по умолчанию work)
claude-docker() {
  _claude_docker_run "${1:-work}" claude
}

# Заход в shell контейнера под выбранным аккаунтом — для авторизации GitLab,
# отладки и ручных команд. Доступны claude, ssh, git.
# Использование: claude-shell <account>    (по умолчанию work)
claude-shell() {
  _claude_docker_run "${1:-work}" bash
}

# Короткие алиасы под все каталоги профилей:
#   claude-<profile>
#   claude-shell-<profile>
_usp_claude_register_profile_aliases() {
  local account_dir profile

  for account_dir in "$PROJECT_ROOT/$CLAUDE_ACCOUNTS_DIR"/*; do
    [ -d "$account_dir" ] || continue
    profile="${account_dir##*/}"

    if [[ "$profile" =~ ^[A-Za-z0-9_-]+$ ]]; then
      alias "claude-$profile=claude-docker $profile"
      alias "claude-shell-$profile=claude-shell $profile"
    fi
  done
}

_usp_claude_register_profile_aliases
