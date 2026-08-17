FROM node:22-slim

ARG PROJECT_DIR=/app
ARG USER_ID=1000
ARG GROUP_ID=1000
# Версия Claude Code = версия образа. При сборке в CI подставляется конкретный
# номер: он же становится тегом публикации, поэтому тег и содержимое совпадают
ARG CLAUDE_CODE_VERSION=latest

WORKDIR ${PROJECT_DIR}

# git, openssh-client и gh — работа с репозиторием и авторизацией.
RUN apt-get update \
    && apt-get install -y --no-install-recommends \
        git openssh-client ca-certificates wget \
        zip unzip p7zip-full tar gzip bzip2 xz-utils \
    && mkdir -p -m 755 /etc/apt/keyrings /etc/apt/sources.list.d \
    && wget -nv -O /etc/apt/keyrings/githubcli-archive-keyring.gpg \
        https://cli.github.com/packages/githubcli-archive-keyring.gpg \
    && chmod go+r /etc/apt/keyrings/githubcli-archive-keyring.gpg \
    && echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/githubcli-archive-keyring.gpg] https://cli.github.com/packages stable main" \
        > /etc/apt/sources.list.d/github-cli.list \
    && apt-get update \
    && apt-get install -y --no-install-recommends gh \
    && rm -rf /var/lib/apt/lists/*
RUN npm install -g npm@latest \
    && npm install -g "@anthropic-ai/claude-code@${CLAUDE_CODE_VERSION}" \
    && node "$(npm root -g)/@anthropic-ai/claude-code/install.cjs"

RUN set -eux; \
    if getent group node > /dev/null; then \
        groupmod --new-name claude node; \
    elif ! getent group claude > /dev/null; then \
        groupadd --gid "${GROUP_ID}" claude; \
    fi; \
    if [ "$(getent group claude | cut -d: -f3)" != "${GROUP_ID}" ]; then \
        groupmod --gid "${GROUP_ID}" claude; \
    fi; \
    if id node > /dev/null 2>&1; then \
        usermod --login claude --home /home/claude --move-home node; \
    elif ! id claude > /dev/null 2>&1; then \
        useradd --uid "${USER_ID}" --gid claude --create-home --shell /bin/bash claude; \
    fi; \
    if [ "$(id -u claude)" != "${USER_ID}" ]; then \
        usermod --uid "${USER_ID}" claude; \
    fi; \
    chown -R claude:claude "${PROJECT_DIR}" /home/claude

USER claude
