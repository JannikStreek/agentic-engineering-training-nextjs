FROM node:24 AS development

# -- Build arguments --------------------------------------------------------
ARG TZ=UTC
ARG GIT_VERSION=2.53.0
ARG DELTA_VERSION=0.18.2
ARG USERNAME=node

ENV TZ="$TZ"

# -- Layer 1: Build git from source (debian ships an older version) ---------
RUN apt-get update && \
    apt-get install -y --no-install-recommends \
        make gcc libssl-dev zlib1g-dev libcurl4-gnutls-dev \
        libexpat1-dev gettext autoconf ca-certificates curl && \
    cd /tmp && \
    curl -fsSL "https://github.com/git/git/archive/refs/tags/v${GIT_VERSION}.tar.gz" -o git.tar.gz && \
    tar -xzf git.tar.gz && \
    cd "git-${GIT_VERSION}" && \
    make prefix=/usr/local all -j"$(nproc)" && \
    make prefix=/usr/local install && \
    cd / && rm -rf /tmp/git* && \
    apt-get purge -y gcc autoconf make && \
    apt-get autoremove -y && \
    apt-get clean && rm -rf /var/lib/apt/lists/*

# -- Layer 2: System packages -----------------------------------------------
RUN apt-get update && \
    apt-get install -y --no-install-recommends \
        less procps sudo fzf zsh man-db unzip gnupg2 gh jq \
        postgresql-client g++ python3 vim bubblewrap socat wget && \
    apt-get clean && rm -rf /var/lib/apt/lists/*

# -- Layer 3: git-delta (parameterized version) -----------------------------
RUN ARCH="$(dpkg --print-architecture)" && \
    wget -q "https://github.com/dandavison/delta/releases/download/${DELTA_VERSION}/git-delta_${DELTA_VERSION}_${ARCH}.deb" && \
    dpkg -i "git-delta_${DELTA_VERSION}_${ARCH}.deb" && \
    rm "git-delta_${DELTA_VERSION}_${ARCH}.deb"

# -- Layer 4: Node global tools + directory setup ---------------------------
RUN npm install -g pnpm && \
    mkdir -p /usr/local/share/npm-global && \
    chown -R ${USERNAME}:${USERNAME} /usr/local/share && \
    mkdir -p /home/${USERNAME}/app /home/${USERNAME}/.claude && \
    chown -R ${USERNAME}:${USERNAME} /home/${USERNAME}/app /home/${USERNAME}/.claude && \
    mkdir /commandhistory && \
    touch /commandhistory/.bash_history && \
    chown -R ${USERNAME} /commandhistory

# -- Environment variables --------------------------------------------------
ENV DEVCONTAINER=true \
    APP_PATH=/home/${USERNAME}/app \
    NPM_CONFIG_PREFIX=/usr/local/share/npm-global \
    PATH=$PATH:/usr/local/share/npm-global/bin \
    SHELL=/bin/zsh

WORKDIR /home/node/app

# -- Switch to non-root user ------------------------------------------------
USER ${USERNAME}

# -- Layer 5: Zsh setup (runs as node) --------------------------------------
RUN sh -c "$(wget -qO- https://github.com/deluan/zsh-in-docker/releases/download/v1.2.0/zsh-in-docker.sh)" -- \
    -p git \
    -p fzf \
    -a "source /usr/share/doc/fzf/examples/key-bindings.zsh" \
    -a "source /usr/share/doc/fzf/examples/completion.zsh" \
    -a "export PROMPT_COMMAND='history -a' && export HISTFILE=/commandhistory/.bash_history" \
    -x

# -- Layer 6: Claude Code + sandbox runtime ---------------------------------
RUN curl -fsSL https://claude.ai/install.sh | bash && \
    echo 'export PATH="$HOME/.local/bin:$PATH"' >> ~/.zshrc && \
    npm install -g @anthropic-ai/sandbox-runtime

RUN npm i -g @openai/codex
RUN npm i -g agent-browser