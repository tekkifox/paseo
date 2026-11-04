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

ARG MONGOSH_VERSION=2.14.1
RUN npm install -g mongosh@${MONGOSH_VERSION} && \
    mongosh --version

ARG LIGHTHOUSE_VERSION=13.6.0
RUN npm install -g lighthouse@${LIGHTHOUSE_VERSION} && \
    lighthouse --version

ARG LHCI_CLI_VERSION=0.16.0
RUN npm install -g @lhci/cli@${LHCI_CLI_VERSION} && \
    lhci --version

ARG PA11Y_VERSION=10.0.0
RUN npm install -g pa11y@${PA11Y_VERSION} && \
    pa11y --version

ARG HTML_VALIDATE_VERSION=11.18.0
RUN npm install -g html-validate@${HTML_VALIDATE_VERSION} && \
    html-validate --version

RUN apt-get update && apt-get install -y \
        curl gpg unzip python3 python3-venv make git \
        jq shellcheck yamllint python3-pip dnsutils iproute2 iputils-ping sqlite3 lsof wget && \
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

# actionlint and Terraform both use amd64/arm64 release archives fetched to
# /tmp, extracted, then deleted together so the image keeps no tarballs.
ARG ACTIONLINT_VERSION=1.7.12
ARG TERRAFORM_VERSION=1.17.1
RUN set -eux && \
    case "$(dpkg --print-architecture)" in \
        amd64) tools_arch=amd64 ;; \
        arm64) tools_arch=arm64 ;; \
        *) echo "Unsupported architecture for actionlint/terraform: $(dpkg --print-architecture)" >&2; exit 1 ;; \
    esac && \
    curl -fsSL -o /tmp/actionlint.tar.gz \
        "https://github.com/rhysd/actionlint/releases/download/v${ACTIONLINT_VERSION}/actionlint_${ACTIONLINT_VERSION}_linux_${tools_arch}.tar.gz" && \
    tar -C /usr/local/bin -xzf /tmp/actionlint.tar.gz actionlint && \
    curl -fsSL -o /tmp/terraform.zip \
        "https://releases.hashicorp.com/terraform/${TERRAFORM_VERSION}/terraform_${TERRAFORM_VERSION}_linux_${tools_arch}.zip" && \
    unzip -o /tmp/terraform.zip terraform -d /usr/local/bin && \
    rm -f /tmp/actionlint.tar.gz /tmp/terraform.zip && \
    chmod +x /usr/local/bin/actionlint /usr/local/bin/terraform && \
    actionlint --version && \
    terraform version

RUN curl -fsSL https://composio.dev/install | sh

# Install the Oracle Cloud (OCI) CLI into a pinned virtual environment (PEP 668-safe)
RUN python3 -m venv /opt/oci-cli && \
    /opt/oci-cli/bin/pip install --no-cache-dir --disable-pip-version-check oci-cli==3.95.1 && \
    ln -sf /opt/oci-cli/bin/oci /usr/local/bin/oci

RUN oci --version

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

# Install both browsers here. The base image (ghcr.io/getpaseo/paseo) ships no
# Playwright browsers at all, so neither Chromium nor Firefox is available unless
# we install them. Install into the user-home cache that Playwright uses by
# default ($HOME/.cache/ms-playwright). This runs as root only because the base
# image owns /home/paseo as `paseo`; the cache is handed to the runtime user
# (uid 1001) afterwards.
RUN mkdir -p /home/paseo/.cache/ms-playwright && \
    PLAYWRIGHT_BROWSERS_PATH=/home/paseo/.cache/ms-playwright \
    npm_config_cache=/tmp/playwright-npm-cache \
    npm exec --yes --package=playwright@${PLAYWRIGHT_VERSION} -- playwright install chromium firefox && \
    chown -R developer:developer /home/paseo/.cache/ms-playwright && \
    rm -rf /tmp/playwright-npm-cache

# Lighthouse and pa11y need a Chromium binary. Resolve the binary at build time
# instead of pinning Playwright's build-numbered directory name, and expose a
# stable path for CHROME_PATH. Use find with a bounded depth so a future
# Playwright layout change fails loudly instead of silently breaking the build.
RUN set -eux && \
    mapfile -t chrome_bins < <(find /home/paseo/.cache/ms-playwright -maxdepth 5 -type f -name chrome -perm -111) && \
    [ "${#chrome_bins[@]}" -eq 1 ] || { echo "Expected exactly one executable Chromium binary under /home/paseo/.cache/ms-playwright, found ${#chrome_bins[@]}" >&2; printf '%s\n' "${chrome_bins[@]}" >&2; exit 1; } && \
    chrome_bin="${chrome_bins[0]}" && \
    ln -sfn "$chrome_bin" /usr/local/bin/chrome && \
    [ -x /usr/local/bin/chrome ] && test "$(readlink -f /usr/local/bin/chrome)" = "$chrome_bin" && \
    /usr/local/bin/chrome --version

# Lighthouse reads CHROME_PATH; the symlink keeps it valid across base-image
# Playwright bumps. ENV applies to this and every later layer, so the
# developer user inherits it.
ENV CHROME_PATH=/usr/local/bin/chrome

# hadolint: Dockerfile linter, pinned to the upstream release. The release
# assets use different spellings from dpkg's architecture names, so any
# unsupported architecture fails the build instead of fetching a wrong binary.
ARG HADOLINT_VERSION=v2.15.1
RUN set -eux && \
    case "$(dpkg --print-architecture)" in \
        amd64) hadolint_arch=x86_64 ;; \
        arm64) hadolint_arch=arm64 ;; \
        *) echo "Unsupported architecture for hadolint: $(dpkg --print-architecture)" >&2; exit 1 ;; \
    esac && \
    curl -fsSL -o /usr/local/bin/hadolint \
        "https://github.com/hadolint/hadolint/releases/download/${HADOLINT_VERSION}/hadolint-linux-${hadolint_arch}" && \
    chmod +x /usr/local/bin/hadolint && \
    hadolint --version

# The agent runtime uses /tmp/opencode for scratch files; the runtime user must be able to write there.
RUN install -d -m 1777 /tmp/opencode

USER developer

# Put the developer user's local bin (where lopper installs) on PATH
ENV PATH="/home/developer/.local/bin:${PATH}"

RUN curl -fsSL https://lopper.dev/install.sh | LOPPER_INSTALL_DIR=/home/developer/.local/bin sh && \
    lopper --version

# Enable TUI interactivity
ENV TERM=xterm-256color
