FROM ghcr.io/getpaseo/paseo:latest

ARG OPENCODE_VERSION=latest
ARG GO_VERSION=1.27.3
ARG VERCEL_CLI_VERSION=65.2.0
# Playwright's Firefox build is version-locked: 1.58.2 ships Firefox 146.0.1
# (Playwright build 1509). Keep this in sync with the @playwright/test version
# used by the agent projects.
ARG PLAYWRIGHT_VERSION=1.58.2

WORKDIR /workspace

USER root
RUN npm install -g --unsafe-perm @opencode/cli@${OPENCODE_VERSION}
RUN npm install -g pnpm
RUN npm install -g @openai/codex @anthropic-ai/claude-code
RUN npm install -g @github/copilot
RUN npm install -g vercel@${VERCEL_CLI_VERSION}

RUN apt-get update && apt-get install -y curl gpg unzip python3 make git && \
    mkdir -p -m 755 /etc/apt/keyrings && \
    curl -fsSL https://cli.github.com/packages/githubcli-archive-keyring.gpg | tee /etc/apt/keyrings/githubcli-archive-keyring.gpg > /dev/null && \
    chmod go+r /etc/apt/keyrings/githubcli-archive-keyring.gpg && \
    echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/githubcli-archive-keyring.gpg] https://cli.github.com/packages stable main" | tee /etc/apt/sources.list.d/github-cli.list > /dev/null && \
    apt-get update && \
    apt-get install -y gh && \
    apt-get clean && rm -rf /var/lib/apt/lists/*

# Install a pinned Go toolchain from the official tarball. The architecture
# matches Go's own naming (amd64/arm64), so dpkg's value is used directly.
RUN curl -fsSL -o /tmp/go.tar.gz "https://go.dev/dl/go${GO_VERSION}.linux-$(dpkg --print-architecture).tar.gz" && \
    tar -C /usr/local -xzf /tmp/go.tar.gz && \
    rm /tmp/go.tar.gz && \
    /usr/local/go/bin/go version

ENV PATH="/usr/local/go/bin:${PATH}"

RUN curl -fsSL https://composio.dev/install | sh

# Setup system-wide rules for GitHub connections
RUN mkdir -p /etc/ssh && \
    echo "Host github.com" >> /etc/ssh/ssh_config && \
    echo "    IdentityFile /workspace/mounted_keys/id_rsa" >> /etc/ssh/ssh_config && \
    echo "    StrictHostKeyChecking no" >> /etc/ssh/ssh_config && \
    echo "    IdentitiesOnly yes" >> /etc/ssh/ssh_config

# Ensure whatever random runtime user spins up can actually read the mounted path
RUN chmod 755 /etc/ssh/ssh_config

# Visual verification tooling: Playwright's Chromium and Firefox runtime
# libraries (the Debian 12 sets that `playwright install-deps` uses, plus the
# X11/vulkan extras Chromium dlopens), real fonts so text does not render as
# boxes, ImageMagick for `compare`/`convert` screenshot diffs, and Pillow
# (python3-pil) for Python-based image work. The second group is the extra
# GTK/X11 stack Firefox needs; without libgtk-3-0 its libmozgtk.so fails to
# load even in headless mode.
RUN apt-get update && apt-get install -y --no-install-recommends \
        libglib2.0-0 \
        libnss3 \
        libnspr4 \
        libatk1.0-0 \
        libatk-bridge2.0-0 \
        libatspi2.0-0 \
        libcups2 \
        libdrm2 \
        libdbus-1-3 \
        libxkbcommon0 \
        libxcomposite1 \
        libxdamage1 \
        libxfixes3 \
        libxrandr2 \
        libgbm1 \
        libpango-1.0-0 \
        libcairo2 \
        libasound2 \
        libx11-6 \
        libxcb1 \
        libxext6 \
        libxi6 \
        libxtst6 \
        libxss1 \
        libvulkan1 \
        libcairo-gobject2 \
        libdbus-glib-1-2 \
        libfontconfig1 \
        libfreetype6 \
        libgdk-pixbuf-2.0-0 \
        libgtk-3-0 \
        libharfbuzz0b \
        libpangocairo-1.0-0 \
        libx11-xcb1 \
        libxcb-shm0 \
        libxcursor1 \
        libxrender1 \
        fonts-liberation \
        imagemagick \
        python3-pil && \
    apt-get clean && rm -rf /var/lib/apt/lists/*

RUN useradd -u 1001 -m -s /bin/bash developer

# Firefox for Playwright. Install it next to Chromium in the user-home cache
# that Playwright uses by default ($HOME/.cache/ms-playwright), and leave
# PLAYWRIGHT_BROWSERS_PATH unset so existing Chromium resolution is unchanged.
# This runs as root only because the base image owns /home/paseo as `paseo`;
# the cache is handed to the runtime user (uid 1001) afterwards.
RUN mkdir -p /home/paseo/.cache/ms-playwright && \
    PLAYWRIGHT_BROWSERS_PATH=/home/paseo/.cache/ms-playwright \
    npm_config_cache=/tmp/playwright-npm-cache \
    npm exec --yes --package=playwright@${PLAYWRIGHT_VERSION} -- playwright install firefox && \
    chown -R developer:developer /home/paseo/.cache/ms-playwright && \
    rm -rf /tmp/playwright-npm-cache

USER developer

# Put the developer user's local bin (where lopper installs) on PATH
ENV PATH="/home/developer/.local/bin:${PATH}"

RUN curl -fsSL https://lopper.dev/install.sh | LOPPER_INSTALL_DIR=/home/developer/.local/bin sh && \
    lopper --version

# Enable TUI interactivity
ENV TERM=xterm-256color
