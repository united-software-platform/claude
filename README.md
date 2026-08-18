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
- [Переменные окружения](#переменные-окружения)
- [Состав образа](#состав-образа)
- [Сборка образа](#сборка-образа)
- [Ограничения](#ограничения)
- [Лицензия](#лицензия)
- [Версионирование](#версионирование)

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

В корень репозитория, к которому подключается агент, копируются `docker-compose.yml`, `.env.example`
и каталог `docker/`. Содержимое сервиса:

```yaml
services:
  claude:
    build:
      context: .
      dockerfile: docker/claude/Dockerfile
      args:
        PROJECT_DIR: ${PROJECT_DIR:-/app}
        USER_ID: ${USER_ID:-1000}
        GROUP_ID: ${GROUP_ID:-1000}
    image: ${IMAGE:?не задан тег образа}
    pull_policy: never
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

- `command: claude` — запуск без аргументов поднимает агента, аргумент после имени сервиса его заменяет
  (`bash`, `git`, `gh`);
- `profiles: ["claude"]` — сервис не поднимается вместе с сервисами окружения по `docker compose up`;
- `pull_policy: never` — тег локальный, pull из registry его не найдёт, а `build` пересобирал бы образ
  на каждый запуск;
- `CLAUDE_CONFIG_DIR` — консолидирует весь конфиг (`.claude.json`, `.credentials.json`) в смонтированный
  каталог аккаунта, иначе авторизация слетает между запусками;
- анонимный том поверх `.claude-accounts` — прячет от агента чужие профили внутри контейнера.

Дальше создаётся `.env` — без него compose не стартует (`IMAGE` не имеет значения по умолчанию):

```bash
cp .env.example .env    # проверьте IMAGE, USER_ID и GROUP_ID
```

### 2. Получить образ

Локальная сборка — единственный способ получить образ с UID/GID своего хоста:

```bash
docker compose build
```

Готовый образ из GHCR (мультиарх, UID/GID `1000:1000`) скачивается вручную, после чего его тег
указывается в `.env` переменной `IMAGE`:

```bash
docker pull ghcr.io/united-software-platform/claude:latest
```

Тег `latest` всегда указывает на последнюю опубликованную сборку. Актуальный номер версии показывает
бейдж **claude code** в начале файла — он равен версии Claude Code в образе; полный список
опубликованных тегов доступен на [странице пакета](https://github.com/united-software-platform/claude/pkgs/container/claude).

### 3. Сгенерировать SSH-ключ

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

### 4. Запустить нужный профиль

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

## Переменные окружения

Задаются в `.env` (образец — `.env.example`); значение перед командой перекрывает файл.

| Переменная | Назначение |
|------------|------------|
| `IMAGE` | тег образа, свой у каждого проекта |
| `PROJECT_DIR` | каталог проекта внутри контейнера |
| `CLAUDE_CODE_VERSION` | версия Claude Code при локальной сборке: `latest` или конкретный номер |
| `CLAUDE_PROFILE` | каталог аккаунта в `CLAUDE_ACCOUNTS_DIR`, обязателен |
| `CLAUDE_ACCOUNTS_DIR` | каталог с профилями аккаунтов на хосте |
| `CLAUDE_CONFIG_DIR` | путь конфига Claude внутри контейнера |
| `SSH_DIR` / `CONTAINER_SSH_DIR` | каталог ключей на хосте / в контейнере |
| `USER_ID`, `GROUP_ID` | UID/GID пользователя `claude` в образе |

---

## Состав образа

Базовый образ `node:22-slim`, глобально установлен пакет `@anthropic-ai/claude-code`. Дополнительно:
`git`, `openssh-client`, `gh`, архиваторы (`zip`, `unzip`, `p7zip`, `tar`, `gzip`, `bzip2`, `xz`).

---

## Сборка образа

Локальная сборка идёт из `docker/claude/Dockerfile` — тем же файлом, что использует CI:

```bash
docker compose build           # тег и UID/GID берутся из .env
```

Образ не пересобирается автоматически (`pull_policy: never`): после правки `docker/claude/Dockerfile`
нужен явный `docker compose build`.

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

При локальной сборке версия берётся из переменной `CLAUDE_CODE_VERSION` в `.env` (по умолчанию `latest` —
актуальная версия CLI на момент сборки):

```bash
CLAUDE_CODE_VERSION=<версия CLI> docker compose build
```

Новая версия Claude Code подхватывается ежедневной пересборкой (`schedule`, 03:17 UTC): новые версии CLI
приходят из npm, а не из коммитов, поэтому push-триггеры их не видят.

> **Внимание:** тег версии не является неизменяемым. Ежедневная сборка при неизменившейся версии CLI
> перезаписывает и `latest`, и тег текущей версии — так в образ попадают обновления базового образа
> и системных пакетов. Для воспроизводимости образ адресуется по digest (`@sha256:…`), а не по тегу.

---

## Ограничения

- Инструменты конкретного языка проекта в образ не входят — их добавляют в `docker/claude/Dockerfile`
  под задачи проекта.
- В опубликованном в GHCR образе UID/GID пользователя `claude` фиксированы как `1000:1000`. При другом
  UID хоста созданные агентом файлы окажутся чужими — нужна локальная сборка.
- Пакет в GHCR создаётся приватным: до первого `pull` нужен `docker login ghcr.io` либо публичная
  видимость пакета в настройках репозитория.
- Файл `.env` обязателен: он подключён через `env_file`, а `IMAGE` и `CLAUDE_PROFILE` не имеют значений
  по умолчанию — при их отсутствии compose завершается с ошибкой.
- Каталоги `.claude-accounts/`, `.ssh/` и файл `.env` содержат секреты и перечислены в `.gitignore` —
  в репозиторий они попадать не должны.

---

## Лицензия

MIT — см. [LICENSE](./LICENSE).

---

## Версионирование

| Версия | Дата | Задача | Агент | Модель | Описание изменений |
|--------|------|--------|-------|--------|--------------------|
| 1.0.0 | 2026-08-17 | Запрос пользователя: создать README с описанием назначения и порядка использования | Claude Code | Claude Opus 5 | Начальное создание: назначение окружения, быстрый старт, команды `make`, алиасы `.bashrc`, подключение к стороннему проекту, переменные окружения, состав образа, ограничения |
| 1.1.0 | 2026-08-17 | Запрос пользователя: упростить подключение к проекту, убрать `.bashrc` | Claude Code | Claude Opus 5 | Подключение через `compose.claude.yml` с готовым образом из GHCR и профилем в переменной запуска; раздел «Короткие алиасы» заменён на «Запуск без make»; удалены упоминания `.bashrc`; ограничения дополнены UID образа и видимостью пакета GHCR |
| 2.0.0 | 2026-08-17 | Запрос пользователя: убрать `make`, оставить инструкцию по генерации SSH-ключа | Claude Code | Claude Opus 5 | Удалены `Makefile`, `docker-compose.yml`, `.env.example` и их описания; единственный способ подключения — `compose.claude.yml` в порядке «создать compose-файл → сгенерировать ключ → запустить профиль»; добавлен раздел «Сборка образа» с CI-публикацией и локальной сборкой |
| 3.0.0 | 2026-08-17 | Запрос пользователя: вернуть `docker-compose.yml` и `.env.example`, удалить `compose.claude.yml` | Claude Code | Claude Opus 5 | Подключение описано через `docker-compose.yml` и `.env` в порядке «создать compose-файл → получить образ → сгенерировать ключ → запустить профиль»; сборка переведена с `make rebuild` на `docker compose build`; таблица переменных приведена к составу `.env.example` |
| 3.0.1 | 2026-08-17 | Запрос пользователя: разобраться с дублированием `claude-claude` в имени образа GHCR | Claude Code | Claude Opus 5 | Имя пакета GHCR приведено к `ghcr.io/<владелец>/<репозиторий>` (для этого репозитория — `ghcr.io/united-software-platform/claude`); устаревший пример `ghcr.io/alexgaib/usp-claude-claude:latest` в команде `docker pull` заменён на актуальный |
| 3.1.0 | 2026-08-17 | Запрос пользователя: версионирование образа по версии Claude CLI, теги `latest` и версия CLI | Claude Code | Claude Opus 5 | Добавлен раздел «Версионирование образа»: версия образа равна версии Claude Code, публикуются теги `<версия CLI>` и `latest`; в таблицу переменных добавлена `CLAUDE_CODE_VERSION` для локальной сборки; зафиксировано ограничение — выход новой версии CLI сам по себе пайплайн не запускает |
| 3.1.1 | 2026-08-17 | Запрос пользователя: добавить ежедневную пересборку образа | Claude Code | Claude Opus 5 | Описан триггер `schedule` (ежедневно, 03:17 UTC) как способ подхватывать новые версии Claude Code и обновления базового образа; ограничение о неавтоматическом обновлении заменено на предупреждение об изменяемости тега версии и адресации по digest |
| 3.2.0 | 2026-08-18 | Запрос пользователя: добавить бейджи и актуальную версию образа | Claude Code | Claude Opus 5 | Добавлен блок бейджей после заголовка: статус пайплайна `docker-claude`, версия Claude Code (`shields.io` по npm-пакету `@anthropic-ai/claude-code` — она же версия образа), имя образа в GHCR, поддерживаемые платформы, лицензия. Актуальная версия образа не фиксируется в тексте, а показывается бейджем: в разделе «Получить образ» добавлено пояснение о теге `latest` и ссылка на страницу пакета GHCR, в разделе «Версионирование образа» выдуманные примеры `2.1.234` заменены на плейсхолдер `<версия CLI>` |
