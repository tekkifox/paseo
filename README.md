# paseo

Container image and compose service for the Paseo agent host.

- `Dockerfile` extends the upstream Paseo image with the agent toolchain
  (OpenCode, Codex, Claude Code, Copilot, Go, browsers, linters, and more).
- `docker-compose.yml` is the service definition deployed as the Paseo stack.
- `.github/workflows/docker-publish.yml` builds both architectures, publishes
  the multi-arch image to GHCR, and redeploys the stack.
- `RUNNER.md` covers the CI runner setup.

## How the container starts

The image installs [supercronic](https://github.com/aptible/supercronic), and the
compose service overrides the image command so one container owns both the
daemon and the schedule:

```sh
supercronic -passthrough-logs /home/paseo/infra-map/crontab & \
  exec /usr/local/bin/paseo-docker-entrypoint
```

- `supercronic` runs the crontab that is mounted into the container; it is not
  baked into the image. Only the crontab file ships with the host data, so a
  missing file makes supercronic exit while the daemon keeps running.
- `-passthrough-logs` sends each job's output to the container log instead of a
  syslog socket.
- `exec` replaces the shell with the daemon entrypoint, leaving the daemon under
  the image's `tini` init so signals and zombie reaping keep working.

Because the scheduler runs in the background, `ps` inside the container shows a
`supercronic` process alongside the Paseo daemon. That is expected.

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
