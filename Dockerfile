FROM ghcr.io/getpaseo/paseo:latest

USER root
RUN npm install -g @openai/codex @anthropic-ai/claude-code opencode-ai
RUN npm install -g @github/copilot

RUN apt-get update && apt-get install -y curl gpg && \
    mkdir -p -m 755 /etc/apt/keyrings && \
    curl -fsSL https://cli.github.com/packages/githubcli-archive-keyring.gpg | tee /etc/apt/keyrings/githubcli-archive-keyring.gpg > /dev/null && \
    chmod go+r /etc/apt/keyrings/githubcli-archive-keyring.gpg && \
    echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/githubcli-archive-keyring.gpg] https://cli.github.com/packages stable main" | tee /etc/apt/sources.list.d/github-cli.list > /dev/null && \
    apt-get update && \
    apt-get install -y gh && \
    apt-get clean && rm -rf /var/lib/apt/lists/*

# Setup system-wide rules for GitHub connections
RUN mkdir -p /etc/ssh && \
    echo "Host github.com" >> /etc/ssh/ssh_config && \
    echo "    IdentityFile /workspace/mounted_keys/id_rsa" >> /etc/ssh/ssh_config && \
    echo "    StrictHostKeyChecking no" >> /etc/ssh/ssh_config && \
    echo "    IdentitiesOnly yes" >> /etc/ssh/ssh_config

# Ensure whatever random runtime user spins up can actually read the mounted path
RUN chmod 755 /etc/ssh/ssh_config

RUN useradd -u 1001 -m -s /bin/bash developer
USER developer