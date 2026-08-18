# usp-claude

[![docker-claude](https://github.com/united-software-platform/claude/actions/workflows/docker-claude.yml/badge.svg)](https://github.com/united-software-platform/claude/actions/workflows/docker-claude.yml)
[![Claude Code](https://img.shields.io/npm/v/%40anthropic-ai%2Fclaude-code?label=claude%20code&color=blue)](https://www.npmjs.com/package/@anthropic-ai/claude-code)
[![image](https://img.shields.io/badge/ghcr.io-united--software--platform%2Fclaude-blue?logo=docker&logoColor=white)](https://github.com/united-software-platform/claude/pkgs/container/claude)
[![platforms](https://img.shields.io/badge/platforms-linux%2Famd64%20%C2%B7%20linux%2Farm64-blue)](./docker/claude/Dockerfile)
[![license](https://img.shields.io/badge/license-MIT-green)](./LICENSE)

Окружение для изолированного запуска Claude Code в Docker-контейнере: агент работает только внутри
каталога проекта, под выбранным аккаунтом и с отдельным SSH-ключом. Окружение не привязано к языку
и стеку проекта — подключается к любому репозиторию парой файлов.

---

## Навигация

- [Зачем](#зачем)
- [Требования](#требования)
- [Подключение к проекту](#подключение-к-проекту)
- [Запуск из IDE](#запуск-из-ide)
- [Переменные окружения](#переменные-окружения)
- [Состав образа](#состав-образа)
- [Сборка образа](#сборка-образа)
- [Ограничения](#ограничения)
- [Лицензия](#лицензия)

---

## Зачем

- **Изоляция файловой системы.** В контейнер монтируется только рабочее дерево проекта. Домашний каталог
  хоста, соседние репозитории и системные настройки агенту недоступны.
- **Несколько аккаунтов без перелогина.** Каждый профиль хранит авторизацию и конфиг в своём каталоге
  `.claude-accounts/<профиль>`; личный и рабочий аккаунты живут параллельно, переключение — переменной
  в команде запуска.
- **Отдельный SSH-ключ на проект.** Ключ и `known_hosts` лежат в `.ssh/` проекта и монтируются
  в контейнер; ключи хоста не задействованы.
- **Файлы остаются вашими.** Контейнерный пользователь `claude` создаётся с UID/GID хоста, поэтому
  созданные агентом файлы не оказываются во владении `root`.

---

## Требования

Docker с плагином `docker compose` и `ssh-keygen`.

---

## Подключение к проекту

### 1. Создать compose-файл

В корень репозитория, к которому подключается агент, копируются `docker-compose.yml` и `.env.example`.
Сервис подключает готовый образ из GHCR — сборка для этого не нужна:

```yaml
services:
  claude:
    image: ghcr.io/united-software-platform/claude:latest
    profiles: ["claude"]
    command: claude
    working_dir: ${PROJECT_DIR:-/app}
    env_file: .env
    environment:
      CLAUDE_CONFIG_DIR: ${CLAUDE_CONFIG_DIR:-/home/claude/.claude}

    volumes:
      - .:${PROJECT_DIR:-/app}
      - ${CLAUDE_ACCOUNTS_DIR:-.claude-accounts}/${CLAUDE_PROFILE:?не задан профиль аккаунта Claude}:${CLAUDE_CONFIG_DIR:-/home/claude/.claude}
      - ${PROJECT_DIR:-/app}/${CLAUDE_ACCOUNTS_DIR:-.claude-accounts}
      - ${SSH_DIR:-.ssh}:${CONTAINER_SSH_DIR:-/home/claude/.ssh}
```

Смысл ключевых параметров:

- `image` — готовый мультиарх-образ из GHCR; тег `latest` указывает на последнюю опубликованную сборку,
  Docker скачивает его сам при первом запуске;
- `command: claude` — запуск без аргументов поднимает агента, аргумент после имени сервиса его заменяет
  (`bash`, `git`, `gh`);
- `profiles: ["claude"]` — сервис не поднимается вместе с сервисами окружения по `docker compose up`;
- `CLAUDE_CONFIG_DIR` — консолидирует весь конфиг (`.claude.json`, `.credentials.json`) в смонтированный
  каталог аккаунта, иначе авторизация слетает между запусками;
- анонимный том поверх `.claude-accounts` — прячет от агента чужие профили внутри контейнера.

Дальше создаётся `.env` — он подключён через `env_file`, поэтому обязателен:

```bash
cp .env.example .env    # проверьте CLAUDE_PROFILE
```

> **Примечание:** образ можно собрать и самому — это нужно в отдельных случаях: UID/GID хоста отличается
> от `1000:1000` в опубликованном образе, в образ требуются инструменты конкретного языка проекта
> или версия Claude Code закрепляется за проектом. Порядок — в разделе
> [Сборка образа](#сборка-образа); для обычного подключения сборка не требуется.

Актуальную версию Claude Code в образе показывает бейдж **claude code** в начале файла; список
опубликованных тегов — на [странице пакета](https://github.com/united-software-platform/claude/pkgs/container/claude).

### 2. Сгенерировать SSH-ключ

Ключ проекта лежит в `.ssh/` и монтируется в контейнер:

```bash
mkdir -p .ssh && chmod 700 .ssh
ssh-keygen -t ed25519 -N "" -C usp-claude -f .ssh/id_ed25519
cat .ssh/id_ed25519.pub    # добавьте ключ в GitHub/GitLab
```

Чтобы контейнер использовал именно этот ключ, создайте `.ssh/config`:

```text
Host github.com
    HostName github.com
    User git
    IdentityFile ~/.ssh/id_ed25519
    IdentitiesOnly yes
    StrictHostKeyChecking accept-new
    UserKnownHostsFile ~/.ssh/known_hosts
```

Пути в `config` указаны так, как они видны внутри контейнера: каталог монтируется в `/home/claude/.ssh`.

### 3. Запустить нужный профиль

Профиль — имя каталога с авторизацией внутри `.claude-accounts/`; профилей может быть сколько угодно,
имя выбирается произвольно. Каталог создаётся заранее: отсутствующий путь Docker создаст от имени
`root`, и агент не сможет сохранить авторизацию.

```bash
mkdir -p .claude-accounts/personal
CLAUDE_PROFILE=personal docker compose run --rm claude
```

Первый запуск попросит авторизоваться; авторизация сохранится в `.claude-accounts/personal` и переживёт
перезапуски контейнера. Тем же способом добавляется любой другой профиль:

```bash
mkdir -p .claude-accounts/work
CLAUDE_PROFILE=work docker compose run --rm claude        # другой аккаунт
CLAUDE_PROFILE=work docker compose run --rm claude bash   # shell в контейнере: авторизация gh, отладка
```

`CLAUDE_PROFILE` обязателен: без него compose не соберёт путь к каталогу аккаунта и остановится
с ошибкой. Значение перед командой перекрывает `.env`, поэтому при единственном аккаунте профиль
можно вписать в `.env` и запускать `docker compose run --rm claude` без переменной.

Сервисы окружения проекта (база, брокер, вспомогательные контейнеры) добавляются в тот же
`docker-compose.yml` и поднимаются обычным `docker compose up -d` — агент в compose-профиле `claude`
при этом не стартует, но, запущенный отдельно, попадает в сеть окружения и видит сервисы по именам.

---

## Запуск из IDE

В PhpStorm и PyCharm агент запускается конфигурацией `Shell Script` — по одной конфигурации на профиль
аккаунта, переключение между аккаунтами сводится к выбору конфигурации в панели запуска.

1. `Run` → `Edit Configurations…` → `+` → `Shell Script`.
2. `Name` — имя профиля, например `claude personal`.
3. `Execute` — переключить на `Script text`.
4. `Script text` — команда запуска:

```bash
CLAUDE_PROFILE=personal docker compose run --rm claude claude
```

![Конфигурация Shell Script в Run/Debug Configurations](./docs/images/console-cmd-in-ide-2.png)

Первое `claude` — имя сервиса из `docker-compose.yml`, второе — команда внутри контейнера. Для второго
аккаунта конфигурация копируется, в ней меняются `Name` и значение `CLAUDE_PROFILE`.

Готовая конфигурация выбирается в панели запуска и стартует кнопкой `Run`:

![Выбор конфигурации в панели запуска](./docs/images/console-cmd-in-ide-1.png)

> **Внимание:** агент интерактивен, поэтому конфигурация должна выполняться в терминале IDE — в окне
> `Run` без TTY ввод в диалог агента не попадёт. В настройках конфигурации `Shell Script` за это отвечает
> опция запуска в терминале; если её нет в вашей версии IDE, агент запускается из вкладки `Terminal`
> той же командой.

---

## Переменные окружения

Задаются в `.env` (образец — `.env.example`); значение перед командой перекрывает файл.

| Переменная | Назначение |
|------------|------------|
| `CLAUDE_PROFILE` | каталог аккаунта в `CLAUDE_ACCOUNTS_DIR`, обязателен |
| `PROJECT_DIR` | каталог проекта внутри контейнера |
| `CLAUDE_ACCOUNTS_DIR` | каталог с профилями аккаунтов на хосте |
| `CLAUDE_CONFIG_DIR` | путь конфига Claude внутри контейнера |
| `SSH_DIR` / `CONTAINER_SSH_DIR` | каталог ключей на хосте / в контейнере |

Переменные `USER_ID`, `GROUP_ID` и `CLAUDE_CODE_VERSION` относятся только к
[локальной сборке](#сборка-образа) и передаются в `docker build` как build-arg.

---

## Состав образа

Базовый образ `node:22-slim`, глобально установлен пакет `@anthropic-ai/claude-code`. Дополнительно:
`git`, `openssh-client`, `gh`, архиваторы (`zip`, `unzip`, `p7zip`, `tar`, `gzip`, `bzip2`, `xz`).

---

## Сборка образа

Обычное подключение обходится готовым образом из GHCR. Сборка нужна в отдельных случаях:

- UID/GID хоста отличается от `1000:1000` — иначе созданные агентом файлы окажутся чужими;
- в образ требуются инструменты конкретного языка проекта;
- версия Claude Code закрепляется за проектом.

Тогда в проект копируется каталог `docker/`, и образ собирается тем же `Dockerfile`, что использует CI:

```bash
docker build -f docker/claude/Dockerfile \
  --build-arg USER_ID="$(id -u)" \
  --build-arg GROUP_ID="$(id -g)" \
  -t usp-claude:local .
```

Собранный тег подставляется в `docker-compose.yml` вместо образа из GHCR:

```yaml
    image: usp-claude:local
```

Сам по себе образ не пересобирается: после правки `docker/claude/Dockerfile` сборку нужно повторить.

Пайплайн [docker-claude.yml](./.github/workflows/docker-claude.yml) собирает и публикует образ в GHCR
для `linux/amd64` и `linux/arm64` при изменениях в `docker/claude/`, ежедневно по расписанию
и по ручному запуску. Имя пакета — `ghcr.io/<владелец>/<репозиторий>`, для этого репозитория —
`ghcr.io/united-software-platform/claude`.

### Версионирование образа

Собственной нумерации у образа нет: его версия — это версия Claude Code внутри него. Пайплайн получает
номер из npm до сборки, передаёт его build-arg `CLAUDE_CODE_VERSION`, сверяет с выводом `claude --version`
в собранном образе и публикует два тега:

| Тег | Значение |
|-----|----------|
| `<версия CLI>` | версия Claude Code, установленная в этой сборке образа |
| `latest` | последняя опубликованная сборка из ветки по умолчанию |

Конкретный номер в README не дублируется: он меняется с каждым релизом CLI. Актуальное значение —
в бейдже **claude code** в начале файла, история тегов — на странице пакета GHCR.

```bash
docker pull ghcr.io/united-software-platform/claude:<версия CLI>
```

При локальной сборке версию задаёт build-arg `CLAUDE_CODE_VERSION` (по умолчанию `latest` — актуальная
версия CLI на момент сборки):

```bash
docker build -f docker/claude/Dockerfile --build-arg CLAUDE_CODE_VERSION=<версия CLI> -t usp-claude:local .
```

Новая версия Claude Code подхватывается ежедневной пересборкой (`schedule`, 03:17 UTC): новые версии CLI
приходят из npm, а не из коммитов, поэтому push-триггеры их не видят.

> **Внимание:** тег версии не является неизменяемым. Ежедневная сборка при неизменившейся версии CLI
> перезаписывает и `latest`, и тег текущей версии — так в образ попадают обновления базового образа
> и системных пакетов. Для воспроизводимости образ адресуется по digest (`@sha256:…`), а не по тегу.

---

## Ограничения

- Инструменты конкретного языка проекта в образ не входят — их добавляют в `docker/claude/Dockerfile`
  и собирают образ локально.
- В опубликованном в GHCR образе UID/GID пользователя `claude` фиксированы как `1000:1000`. При другом
  UID хоста созданные агентом файлы окажутся чужими — нужна локальная сборка.
- Пакет в GHCR создаётся приватным: до первого `pull` нужен `docker login ghcr.io` либо публичная
  видимость пакета в настройках репозитория.
- Файл `.env` обязателен: он подключён через `env_file`, а `CLAUDE_PROFILE` не имеет значения
  по умолчанию — при его отсутствии compose завершается с ошибкой.
- Каталоги `.claude-accounts/`, `.ssh/` и файл `.env` содержат секреты и перечислены в `.gitignore` —
  в репозиторий они попадать не должны.

---

## Лицензия

MIT — см. [LICENSE](./LICENSE).
