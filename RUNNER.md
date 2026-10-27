# Self-hosted arm64 runner

The Docker workflow (`.github/workflows/docker-publish.yml`) builds `linux/amd64`
on GitHub-hosted `ubuntu-latest` and `linux/arm64` on a self-hosted runner on this
VPS. Building arm64 natively avoids the slow and fragile QEMU emulation that the
old single-job workflow used.

The arm64 job selects the runner with:

```yaml
runs-on: [self-hosted, linux, arm64]
```

All three labels must match, so the runner **must** be registered with them.

## Why the runner has to be on the host

The runner must run directly on the VPS host, as a normal systemd service, not
inside the Paseo agent container. The agent container has no Docker daemon
mounted, so a runner inside it cannot build images. The Docker daemon, its
socket, and the build cache all live on the host.

Run the commands below on the host (over SSH), not in an agent terminal.

## Prerequisites

- `aarch64`/arm64 Linux host.
- Docker Engine installed and running: `docker info` succeeds.
- Outbound HTTPS access to `github.com`, `api.github.com`, `ghcr.io`, and the
  GitHub Actions cache endpoints. The runner does not need an inbound port.
- Git installed.
- A dedicated unprivileged user for the runner is recommended. The examples use
  `github-runner`; substitute another user if you prefer.

```bash
sudo useradd --create-home --shell /bin/bash github-runner
sudo usermod -aG docker github-runner
```

Group membership only applies to new sessions, so log in as that user (or
restart the service after installing it) before testing:

```bash
sudo -iu github-runner docker info
```

Give the user access to a directory with enough free space. Image builds and the
BuildKit cache are several GB; keep at least **40–50 GB** free and monitor it:

```bash
df -h /
docker system df
```

## Register the runner

1. Open **GitHub → the `tekkifox/paseo` repository → Settings → Actions →
   Runners → New self-hosted runner**.
2. Choose **Linux** and **ARM64**. That page shows the download commands and a
   registration token.
3. The registration token is **short-lived (one hour)**. If configuration fails
   with an expired-token error, generate a new token on the same page; never
   commit it or paste it into a workflow.

As `github-runner`:

```bash
sudo -iu github-runner
mkdir -p ~/actions-runner && cd ~/actions-runner

RUNNER_VERSION=2.338.2
RUNNER_SHA256=670adb2f268fe21dcbb58b3db0e0aa9d5b3bddfe2c651481336e561ff86de945

curl -fsSLO "https://github.com/actions/runner/releases/download/v${RUNNER_VERSION}/actions-runner-linux-arm64-${RUNNER_VERSION}.tar.gz"
echo "${RUNNER_SHA256}  actions-runner-linux-arm64-${RUNNER_VERSION}.tar.gz" | sha256sum -c -
tar xzf "actions-runner-linux-arm64-${RUNNER_VERSION}.tar.gz"

./config.sh \
  --url https://github.com/tekkifox/paseo \
  --token <registration-token> \
  --labels self-hosted,linux,arm64 \
  --name vps-arm64
```

`vps-arm64` is only a display name; use whatever identifies the box. If you are
re-registering a runner with the same name, add `--replace` to `config.sh`.

The checksum above is the published SHA-256 for runner `2.338.2`. When
upgrading, take the matching checksum from that release's notes:
<https://github.com/actions/runner/releases>.

## Install as a service

Install the runner as a systemd service so it survives reboots and reconnects
after network interruptions. From `~/actions-runner`:

```bash
sudo ./svc.sh install github-runner
sudo ./svc.sh start
sudo ./svc.sh status
```

`svc.sh install` creates the service for the user you pass (defaults to the
invoking user). After adding the user to the `docker` group, restart the service
so it picks up the new group:

```bash
sudo ./svc.sh stop
sudo ./svc.sh start
```

The runner appears under **Settings → Actions → Runners** as **Idle** when it is
ready. The service logs are available via `journalctl`/`systemctl status` for the
generated `actions.runner.*` unit if it does not come online.

## Verify it can build

From the host, as the runner user, confirm Docker works without `sudo`:

```bash
sudo -iu github-runner docker run --rm hello-world
```

Then check **Settings → Actions → Runners** shows the runner **Idle** with the
`self-hosted`, `linux`, and `arm64` labels. The next push to `main` will use it
for the `Build (arm64)` job. You can also re-run a queued/failed Docker workflow
from the Actions tab once the runner is online.

## What happens before a runner exists

This is an operational trap worth knowing:

- GitHub does **not** fail a job when no matching self-hosted runner exists. The
  `Build (arm64)` job stays **Queued** indefinitely, and because `merge` needs
  it, the merge job and the Portainer webhooks never run.
- `timeout-minutes` does **not** help here. GitHub starts that clock only when a
  runner picks the job up, not while it is queued. The workflow sets
  `timeout-minutes: 180` on each build to cancel a wedged build that has already
  started; it cannot fail a job with no runner.
- The safe consequence is that the published tag is not rewritten: the old
  multi-arch image remains live and Portainer is not notified. The bad
  consequence is that the workflow silently stops updating the image.
- Watch the Actions tab after enabling this workflow. A run stuck on
  `Build (arm64) — Queued` means the runner is missing, stopped, or has the
  wrong labels. Check the runner service and its labels first.

Until the runner is registered, expect the first `main` push to queue rather
than succeed.

## Cache

Both architectures use `type=gha` with platform-specific scopes
(`build-amd64`, `build-arm64`). The GitHub Actions cache service is accessible
from self-hosted runners using the job's runtime token, so the arm64 build gets
the same caching behaviour as the hosted amd64 build; the scopes keep the two
architectures from overwriting each other's cache entries.

The repository cache is capped (currently 10 GB), and `mode=max` on both builds
can evict older entries. If the self-hosted host cannot reach the cache service,
the alternative is `type=registry` cache exported to GHCR (or `type=local` on
the host, which cannot be shared with the amd64 job). Local disk use by the
BuildKit builder can be reclaimed with:

```bash
docker buildx prune -af
```

## Security notes

- Self-hosted runners execute code from the workflows that select them. This
  workflow only triggers on **push to `main`**, not on pull requests, so fork PR
  code does not run here. Keep it that way, and keep the host and runner patched.
- Treat the registration token as a secret; it is only valid for about an hour.
- To remove the runner: stop and uninstall the service
  (`sudo ./svc.sh stop && sudo ./svc.sh uninstall`) and remove it under
  **Settings → Actions → Runners**, or run
  `./config.sh remove --token <removal-token>`.
