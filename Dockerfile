FROM debian:trixie

RUN apt-get update && apt-get install -y \
    curl \
    wget \
    ca-certificates \
    git \
    build-essential \
    unzip \
    gnupg \
    ripgrep \
    fd-find \
    bat \
    jq \
    universal-ctags \
    nano \
    vim \
    tmux \
    fzf \
    gh \
    sudo \
    netcat-traditional \
    iputils-ping \
    file \
    poppler-utils

# install postgresql client 18
RUN curl -fsSL https://www.postgresql.org/media/keys/ACCC4CF8.asc | gpg --dearmor -o /usr/share/keyrings/postgresql-keyring.gpg && \
    echo "deb [signed-by=/usr/share/keyrings/postgresql-keyring.gpg] https://apt.postgresql.org/pub/repos/apt trixie-pgdg main" > /etc/apt/sources.list.d/pgdg.list && \
    apt-get update && \
    apt-get install -y postgresql-client-18

# install nodejs & friends
RUN curl -fsSL https://deb.nodesource.com/setup_24.x | bash - && \
    apt-get install -y nodejs \
    && npm install --global npm@latest \
    && npm install --global yarn \
    && npm install --global pnpm@latest-10


# install nice tooling for NPM
RUN npm install --force --global @ast-grep/cli

# better naming for bat and fd because of debian clash
RUN ln -s /usr/bin/batcat /usr/local/bin/bat \
    && ln -s /usr/bin/fdfind /usr/local/bin/fd

# install golang
ARG GO_VERSION=1.25.5
ARG TARGETARCH
RUN GOARCH=$([ "$TARGETARCH" = "arm64" ] && echo "arm64" || echo "amd64") && \
    curl -fsSL "https://go.dev/dl/go${GO_VERSION}.linux-${GOARCH}.tar.gz" | tar -C /usr/local -xz
ENV PATH="/usr/local/go/bin:${PATH}"

# prepare user for the running agent
ARG USER_ID=1001
ARG USER_NAME=agent
# now add user with name agent and given id
RUN addgroup --system --gid ${USER_ID} ${USER_NAME} && \
    adduser --system --uid ${USER_ID} ${USER_NAME};
# add user to sudoers
RUN echo "${USER_NAME} ALL=(ALL) NOPASSWD:ALL" >> /etc/sudoers;

# now add home dir for agent and fix permissions
RUN mkdir -p /home/${USER_NAME} \
    && chown ${USER_NAME}:${USER_NAME} /home/${USER_NAME} \
    && chown -R ${USER_NAME}:${USER_NAME} /usr/local/bin /usr/lib/node_modules/ /usr/bin/
ENV HOME="/home/${USER_NAME}"
WORKDIR /home/${USER_NAME}
USER ${USER_NAME}

# install uv and python
RUN curl -LsSf https://astral.sh/uv/install.sh | sh
# Disable development dependencies for UV
ENV UV_NO_DEV=1

# now install claude code
RUN curl -fsSL https://claude.ai/install.sh | bash
# claude settings
ENV DISABLE_TELEMETRY=1
# and register claude
ENV PATH="~/.claude/bin:/home/${USER_NAME}/.local/bin:${PATH}"
RUN echo 'export PATH="$HOME/.local/bin:$PATH"' >> "/home/${USER_NAME}/.bashrc"

# install copilot
RUN curl -fsSL https://gh.io/copilot-install | bash

# install opencode
RUN curl -fsSL https://opencode.ai/install | bash

# install codex
RUN npm i -g @openai/codex
