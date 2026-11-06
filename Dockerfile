FROM ghcr.io/getpaseo/paseo:latest

ARG OPENCODE_VERSION=latest
ARG GO_VERSION=1.27.3
ARG VERCEL_CLI_VERSION=65.2.0
# Playwright's Firefox build is version-locked: 1.58.2 ships Firefox 146.0.1
# (Playwright build 1509). Keep this in sync with the @playwright/test version
# used by the agent projects.
ARG PLAYWRIGHT_VERSION=1.58.2
ARG SUPERCRONIC_VERSION=0.2.51

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

# supercronic runs a container's own crontab without a cron daemon, a
# root-owned spool, or the host's scheduler/timer. A service opts in by using
# it as its container command, e.g.
#   supercronic -passthrough-logs /path/to/crontab
# It is a static Go binary, pinned by version and checksum for each supported
# architecture; the release asset names match dpkg's amd64/arm64 values.
RUN set -eux; \
    case "$(dpkg --print-architecture)" in \
      amd64) asset="supercronic-linux-amd64"; sha256="cc232108374e8e2b537045f2d5eaa1229f619db314c3ba6a14d38b35dc0aa123" ;; \
      arm64) asset="supercronic-linux-arm64"; sha256="4ae22576a78223d8ccdf5f3b3660a5cbb5288416bf0ca96afc4a36d195932b94" ;; \
      *) echo "unsupported architecture: $(dpkg --print-architecture)" >&2; exit 1 ;; \
    esac; \
    curl -fsSL --proto '=https' -o /usr/local/bin/supercronic \
      "https://github.com/aptible/supercronic/releases/download/v${SUPERCRONIC_VERSION}/${asset}"; \
    echo "${sha256}  /usr/local/bin/supercronic" | sha256sum -c -; \
    chmod 0755 /usr/local/bin/supercronic; \
    supercronic -version

# Prove the scheduler actually fires jobs in this image. Under cronexpr a
# six-field expression is minutes + year, so the smoke test uses the seven-field
# form (seconds + five standard fields + year) to run every second; a few
# seconds is then enough to see the appended line.
RUN set -eux; \
    tmp="$(mktemp -d)"; \
    trap 'rm -rf "$tmp"' EXIT; \
    printf '* * * * * * * echo fired >> %s/proof\n' "$tmp" > "$tmp/crontab"; \
    supercronic -passthrough-logs "$tmp/crontab" & \
    pid=$!; \
    fired=0; \
    for _ in $(seq 1 20); do \
      if [ -s "$tmp/proof" ]; then fired=1; break; fi; \
      sleep 0.5; \
    done; \
    kill "$pid" 2>/dev/null || true; \
    wait "$pid" 2>/dev/null || true; \
    if [ "$fired" -ne 1 ]; then \
      echo "supercronic smoke test failed: scheduled job never ran" >&2; \
      exit 1; \
    fi; \
    echo "supercronic smoke test: $(head -n 1 "$tmp/proof")"

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
        fonts-dejavu-core \
        fonts-liberation \
        imagemagick \
        python3-pil && \
    apt-get clean && rm -rf /var/lib/apt/lists/*

RUN useradd -u 1001 -m -s /bin/bash developer

# Browsers live outside $HOME because /home/paseo is a bind mount at runtime
# and shadows the image. Install both browsers here. The base image
# (ghcr.io/getpaseo/paseo) ships no Playwright browsers at all, so neither
# Chromium nor Firefox is available unless we install them. Install into
# /opt/ms-playwright so the bind mount cannot
# shadow them; the cache is handed to the runtime user (uid 1001) afterwards.
ENV PLAYWRIGHT_BROWSERS_PATH=/opt/ms-playwright
RUN mkdir -p /opt/ms-playwright && \
    PLAYWRIGHT_BROWSERS_PATH=/opt/ms-playwright \
    npm_config_cache=/tmp/playwright-npm-cache \
    npm exec --yes --package=playwright@${PLAYWRIGHT_VERSION} -- playwright install chromium firefox && \
    chown -R developer:developer /opt/ms-playwright && \
    rm -rf /tmp/playwright-npm-cache

# Lighthouse and pa11y need a Chromium binary. Resolve the binary at build time
# instead of pinning Playwright's build-numbered directory name, and expose a
# stable path for CHROME_PATH. Use find with a bounded depth so a future
# Playwright layout change fails loudly instead of silently breaking the build.
RUN set -eu; \
    chrome_count=$(find /opt/ms-playwright -maxdepth 5 -type f -name chrome -perm -111 | wc -l); \
    [ "$chrome_count" -eq 1 ] || { echo "Expected exactly one executable Chromium binary under /opt/ms-playwright, found $chrome_count" >&2; find /opt/ms-playwright -maxdepth 5 -type f -name chrome >&2; exit 1; }; \
    chrome_bin=$(find /opt/ms-playwright -maxdepth 5 -type f -name chrome -perm -111 -print -quit); \
    ln -sfn "$chrome_bin" /usr/local/bin/chrome; \
    [ -x /usr/local/bin/chrome ]; \
    [ "$(readlink -f /usr/local/bin/chrome)" = "$chrome_bin" ]

# Lighthouse reads CHROME_PATH; the symlink keeps it valid across base-image
# Playwright bumps. ENV applies to this and every later layer, so the
# developer user inherits it.
ENV CHROME_PATH=/usr/local/bin/chrome

# Mermaid diagram tooling. mmdc renders through the Chromium installed above,
# so skip Puppeteer's own browser download and keep a single browser in the
# image. Install into /opt/mermaid rather than npm's default /usr/local prefix:
# a global install there would place the real mmdc binary in /usr/local/bin,
# where the wrapper below lives.
ARG MERMAID_CLI_VERSION=12.2.0
RUN PUPPETEER_SKIP_DOWNLOAD=true npm install -g --prefix /opt/mermaid \
        @mermaid-js/mermaid-cli@${MERMAID_CLI_VERSION} && \
    /opt/mermaid/bin/mmdc --version

# Puppeteer config for mmdc. executablePath points at the stable Chromium
# symlink created above; /usr/local/bin/mmdc re-resolves the actual binary at
# run time so a Playwright upgrade cannot leave a stale path behind.
RUN install -d -m 755 /opt/mermaid && \
    printf '%s\n' \
        '{' \
        '  "executablePath": "/usr/local/bin/chrome",' \
        '  "args": ["--no-sandbox", "--disable-dev-shm-usage"]' \
        '}' > /opt/mermaid/puppeteer.json && \
    cat /opt/mermaid/puppeteer.json

# Thin mmdc wrapper. The Chromium directory is build-numbered, so resolve the
# newest matching binary on every invocation instead of baking a path in at
# build time. Playwright also uses different internal directory names for
# linux-x64 (chrome-linux64) and linux-arm64 (chrome-linux), and both are
# accepted here so the same image definition works on either architecture.
RUN printf '%s\n' \
        '#!/usr/bin/env bash' \
        '# Render Mermaid diagrams with the Playwright Chromium in this image.' \
        'set -euo pipefail' \
        '' \
        'shopt -s nullglob' \
        'browsers=(' \
        '  /opt/ms-playwright/chromium-*/chrome-linux64/chrome' \
        '  /opt/ms-playwright/chromium-*/chrome-linux/chrome' \
        ')' \
        'if [ "${#browsers[@]}" -eq 0 ]; then' \
        '  echo "mmdc: no Playwright Chromium found under /opt/ms-playwright" >&2' \
        '  exit 1' \
        'fi' \
        '' \
        '# Newest chromium-<build> wins; sort -V orders the build numbers.' \
        'chrome="$(printf "%s\n" "${browsers[@]}" | sort -V | tail -n 1)"' \
        'if [ ! -x "$chrome" ]; then' \
        '  echo "mmdc: resolved Chromium is not executable: $chrome" >&2' \
        '  exit 1' \
        'fi' \
        '' \
        '# Materialise the config with the run-time path. /opt is read-only for' \
        '# the runtime user, so the effective config lives in a temp file.' \
        'config="$(mktemp "${TMPDIR:-/tmp}/mmdc-puppeteer.XXXXXX.json")"' \
        'trap '"'"'rm -f "$config"'"'"' EXIT' \
        'jq --arg chrome "$chrome" '"'"'.executablePath = $chrome'"'"' /opt/mermaid/puppeteer.json > "$config"' \
        '' \
        '/opt/mermaid/bin/mmdc --puppeteerConfigFile "$config" "$@"' \
        > /usr/local/bin/mmdc && \
    chmod 755 /usr/local/bin/mmdc && \
    cat /usr/local/bin/mmdc

# Fail the build if mmdc cannot produce both output formats. Run as root here,
# which is why the config above passes --no-sandbox.
RUN set -eux; \
    printf 'graph TD\n    A[Mermaid] --> B[Toolchain]\n' > /tmp/mermaid-smoke.mmd; \
    mmdc --version; \
    mmdc -i /tmp/mermaid-smoke.mmd -o /tmp/mermaid-smoke.svg; \
    mmdc -i /tmp/mermaid-smoke.mmd -o /tmp/mermaid-smoke.png; \
    for f in /tmp/mermaid-smoke.svg /tmp/mermaid-smoke.png; do \
        [ -s "$f" ] || { echo "Mermaid smoke render produced an empty $f" >&2; exit 1; }; \
        ls -l "$f"; \
    done; \
    rm -f /tmp/mermaid-smoke.mmd /tmp/mermaid-smoke.svg /tmp/mermaid-smoke.png

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
