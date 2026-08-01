# Railway deployment runbook

This runbook deploys the Linux host as a **single-owner persistent browser**.
It is suitable when Hermes, Codex, and Claude Code execute inside the same
container and call the local `ego-browser` shim.

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
7. Keep the healthcheck at `/readyz`. `/livez` only proves that the control
   process is alive; `/readyz` additionally requires the local CDP endpoint.
8. Use a static outbound IP when a target system allowlists source IPs.
9. Enable volume backups and prove a restore in staging before relying on them.
10. Do not generate a public domain for this same-container-only service. The
    health listener must be reachable by Railway's deployment healthcheck, but
    it is not an authenticated browser-control interface.

The image derives durable paths from Railway's injected volume mount:

```text
/data/ego-lite/profile     Chromium user-data-dir (cookies/settings/storage)
/data/ego-lite/spaces.json task-space metadata
/run/ego-lite/host.sock    runtime-only local RPC
/run/ego-lite/host.pid     runtime-only process identity
/run/ego-lite/host.lock    singleton ownership
```

The image defaults to `EGO_CHROME_NO_SANDBOX=1` because managed containers
usually do not expose the kernel facilities Chromium needs for its own sandbox.
Chromium still runs as the unprivileged `ego` user, but disabling its internal
sandbox is a real security trade-off. The minimal image does not install the
optional Debian `chromium-sandbox` package; enabling Chromium's internal
sandbox therefore requires a separately reviewed image change and a staging
smoke, not only changing this environment variable.

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
A private visual takeover surface is still required for reauthentication and
CAPTCHA recovery.

The repository also includes an opt-in controlled-origin test at
`package/ego-linux-host/src/persistence-e2e.test.ts`. Its default mode restarts
Chromium in one environment. Its `write` and `read` phases can run in separate
containers with the same mounted profile, token, and fixed fixture port to
model a deployment replacement without using a customer account.
