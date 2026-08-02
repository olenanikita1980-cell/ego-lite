# Railway deployment runbook

This runbook deploys the Linux host as a **single-owner persistent browser**
with a token-protected Selkies visual surface. It is suitable when Hermes,
Codex, and Claude Code execute inside the same container and call the local
`ego-browser` shim. Read [`SELKIES.md`](./SELKIES.md) before enabling a public
domain or human controller token.

It does not expose browser control over HTTP. Agents running in other Railway
services need the authenticated, client-isolated gateway described as a
blocked tranche in [`ARCHITECTURE.md`](./ARCHITECTURE.md). Never publish CDP
port 9222 or the Unix socket through a TCP proxy.

## Required Railway settings

1. Deploy the fork/branch with `Dockerfile.railway` and `railway.json`.
2. Attach exactly one Railway Volume at `/data`.
3. Keep the service at one replica and disable serverless sleep.
4. Set `RAILWAY_RUN_UID=0`. The root entrypoint prepares the root-owned Railway
   volume, then immediately execs the daemon and Chromium as uid 10001 (`ego`).
5. Set `RAILWAY_SHM_SIZE_BYTES=268435456` (256 MiB) or larger.
6. Allocate at least 1 GiB RAM; 2 GiB is the safer starting point for several
   tabs.
7. Keep Railway's public healthcheck at Selkies `/api/health`. The Ego host
   `/livez` and `/readyz` endpoints are loopback-only on the internal health
   port; `/readyz` additionally requires the local CDP endpoint and gates
   Selkies startup.
8. Use a static outbound IP when a target system allowlists source IPs.
9. Enable volume backups and prove a restore in staging before relying on them.
10. Set distinct strong `SELKIES_MASTER_TOKEN`,
    `EGO_VIEWER_CONTROLLER_TOKEN`, and optional
    `EGO_VIEWER_VIEWER_TOKEN` secrets (minimum 32 characters each).
11. Generate a public Railway domain only after token negative tests pass. The
    public route is Selkies, not CDP or the Unix socket.
12. Confirm the public `/api/health` probe and internal `/readyz` gate both
    recover after a staged restart before attaching a customer profile.
13. Allocate at least 2 vCPU / 4 GiB RAM for staging; 4 vCPU / 8 GiB is the
    safer 1080p/60 starting point for Chromium plus software H.264 encoding.

The image derives durable paths from Railway's injected volume mount:

```text
/data/ego-lite/profile     Chromium user-data-dir (cookies/settings/storage)
/data/ego-lite/spaces.json task-space metadata
/run/ego-lite/host.sock    runtime-only local RPC
/run/ego-lite/host.pid     runtime-only process identity
/run/ego-lite/host.lock    singleton ownership
/run/ego-lite/*.log        runtime-only Xvfb/Openbox/Pulse/Selkies logs
```

The image installs Debian's `chromium-sandbox` package and defaults to
`EGO_CHROME_NO_SANDBOX=0`, so Chromium keeps its internal sandbox while still
running as the unprivileged `ego` user. This requires a real staging smoke in
each target container runtime. If a runtime blocks the SUID sandbox, setting
`EGO_CHROME_NO_SANDBOX=1` is an explicit compatibility fallback with a material
security trade-off; it must not be enabled silently.

The image also installs a machine policy that suppresses Chromium's persistent
command-line security-warning banner. This is UI-only: it does not re-enable a
blocked sandbox or reduce the need to record `EGO_CHROME_NO_SANDBOX=1` as an
explicit runtime exception.

The 2026-08-02 Railway staging acceptance test exercised the safe default first.
Chromium exited with `SIGTRAP` in that runtime, so staging explicitly records
`EGO_CHROME_NO_SANDBOX=1`. The image itself still defaults to
`EGO_CHROME_NO_SANDBOX=0`; do not copy the staging exception to a different
runtime without reproducing the sandbox smoke test there.

## Controls

From a Railway shell in the running service:

```bash
cd /app/package/ego-linux-host
npm run host:status
npm run host:stop
```

The container start command is equivalent to:

```bash
npm run host:run --prefix /app/package/ego-linux-host
```

`stop` sends SIGTERM to the recorded owner. The daemon stops accepting work,
saves task-space metadata, asks Chromium to close through CDP, waits for its
process to exit, and only then uses bounded process termination if required.
Railway is configured with 15 seconds of drain time before SIGKILL.

## Persistence acceptance test

Do not use a real customer account for the first proof. Use a controlled login
fixture and record the deployment id plus volume id.

1. Write a persistent cookie, localStorage value, and IndexedDB value.
2. Record `host:status` and confirm `/readyz` returns HTTP 200.
3. Restart the service and assert all three values through the same profile.
4. Redeploy the same branch and repeat the assertions.
5. Restore a volume backup into staging and repeat the assertions.
6. Send SIGTERM during active browsing and verify Chromium exits before the
   container deadline and the profile starts without corruption warnings.

Website-owned sessions can still expire, be revoked, demand MFA, or reject a
datacenter IP. Persistent storage cannot guarantee permanent authentication.
The Selkies controller supplies visual input for reauthentication and CAPTCHA
recovery, but the automatic agent/human control lease is still required before
production concurrency.

The repository also includes an opt-in controlled-origin test at
`package/ego-linux-host/src/persistence-e2e.test.ts`. Its default mode restarts
Chromium in one environment. Its `write` and `read` phases can run in separate
containers with the same mounted profile, token, and fixed fixture port to
model a deployment replacement without using a customer account.
