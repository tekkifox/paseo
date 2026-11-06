# paseo

Container image and compose service for the Paseo agent host.

- `Dockerfile` extends the upstream Paseo image with the agent toolchain
  (OpenCode, Codex, Claude Code, Copilot, Go, browsers, linters, and more).
- `docker-compose.yml` is the service definition deployed as the Paseo stack.
- `paseo-cron` is the crontab supervisor the container command starts beside
  the daemon.
- `.github/workflows/docker-publish.yml` builds both architectures, publishes
  the multi-arch image to GHCR, and redeploys the stack.
- `RUNNER.md` covers the CI runner setup.

## How the container starts

The image installs [supercronic](https://github.com/aptible/supercronic) and a
supervisor, `/usr/local/bin/paseo-cron`, and the compose service overrides the
image command so one container owns both the daemon and the schedule:

```sh
sh -c 'paseo-cron & exec /usr/local/bin/paseo-docker-entrypoint'
```

- `paseo-cron` runs `supercronic -passthrough-logs /home/paseo/crontab` in a
  restart loop with a fixed delay, logging each start and each exit (with its
  status) under a `[cron]` prefix. A crontab that dies cannot end the schedule
  permanently.
- A fresh home has no crontab yet. Rather than letting supercronic exit
  silently in the background, `paseo-cron` creates an empty, commented
  `/home/paseo/crontab` and logs that the map job is not installed in this home.
  It writes only under `/home/paseo`.
- `supercronic` runs the crontab that is mounted into the container; it is not
  baked into the image. Only the crontab file ships with the host data.
- `-passthrough-logs` sends each job's output to the container log instead of a
  syslog socket.
- `exec` replaces the shell with the daemon entrypoint, leaving the daemon under
  the image's `tini` init so signals and zombie reaping keep working.

Because the scheduler runs in the background, `ps` inside the container shows a
`paseo-cron` process and a `supercronic` process alongside the Paseo daemon.
That is expected, and `docker logs` shows the `[cron]` state directly.

## DNS

The service sets:

```yaml
dns:
  - 100.100.100.100
  - 1.1.1.1
```

`100.100.100.100` is the MagicDNS resolver, so tailnet names resolve from
inside the container; `1.1.1.1` remains as a fallback for public names.

Keep these settings in `docker-compose.yml` in sync with the deployed stack. A
redeploy re-applies the stack definition, so hand-editing the running container
or the stack without updating this file loses the change on the next deploy.
