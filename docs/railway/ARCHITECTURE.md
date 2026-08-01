# Railway persistent browser architecture

Status: planning gate locked for the persistence tranche. Remote multi-agent
execution remains blocked until the client-isolation and gateway gates below
are implemented and verified.

## Goal

Run one long-lived Chromium profile on Railway so authorized Hermes, Codex,
and Claude Code clients can reuse browser settings and still-valid login state
across tasks, process restarts, and deployments.

Persistence means that the browser's `user-data-dir` survives infrastructure
lifecycle events. It does not mean that a website cannot expire or revoke its
own server-side session. MFA, CAPTCHA, device approval, and sensitive actions
must support a human handoff.

## Runtime shape

```text
authorized agent clients
        |
        v
authenticated task gateway (not raw CDP)
        |
        v
ego Linux host daemon ---- health/status/stop controls
        |
        v
one Chromium process
        |
        v
Railway volume mounted at /data
  /data/profile       Chromium user-data-dir
  /data/spaces.json   durable task-space metadata
```

Runtime-only files such as the Unix socket and PID file must live outside the
persistent volume. Persisting them creates stale ownership artifacts after a
container replacement.

## Locked decisions

1. One Railway service replica owns one profile volume. Chromium profile
   directories are single-writer resources.
2. Chromium runs as a non-root user; raw CDP listens on loopback only.
3. Browser state lives under `/data/profile`; deployment/runtime state does not.
4. Shutdown drains new work, persists task-space state atomically, asks Chrome
   to close through CDP, and uses process termination only as a bounded fallback.
5. The public gateway never exposes port 9222 or arbitrary unauthenticated CDP.
6. The existing `ego-browser` helper interface remains stable. The Linux host is
   a separate adapter for the open `globalThis.ego` seam.
7. The original PR #134 commits retain their original author metadata.

## Architecture findings in PR #134

### P0: global task-space selection is not client-isolated

`SpaceManager.selectedId` is process-global. If Hermes and Codex execute at the
same time, one client can change the selected space while another request is
in flight. Remote multi-agent access is blocked until selection is bound to a
client lease or task session and CDP events are routed only to that owner.

### P0: no authenticated remote gateway

The implementation has a local Unix-socket RPC interface. Railway clients
outside the container cannot use it, and publishing CDP directly would expose
all logged-in sessions. A narrow authenticated task interface is required.

### P0: container shutdown does not close Chromium

The daemon closes its socket and CDP transport but intentionally leaves Chrome
running. Container termination can therefore kill Chrome while profile files
are open. The persistence tranche must close Chrome gracefully and verify a
restart against the same profile.

### P1: task-space persistence is non-atomic

`spaces.json` is written directly. A crash during a write can replace valid
state with partial JSON. Writes must use a sibling temporary file, sync, and
atomic rename.

### P1: stale socket recovery can create a competing daemon

A failed ping causes the CLI to unlink the socket and start another daemon.
The recovery path must check a PID/ownership record and use a startup lock
before replacing a possibly slow but live host.

### P1: spaces are tab sets, not isolated browser contexts

PR #134 deliberately shares one cookie jar. This preserves logins but does not
match native Ego Spaces isolation. Concurrent tasks can affect shared cookies,
local storage, service workers, and account selection. The gateway must expose
this limitation and serialize conflicting account/domain work unless a future
BrowserContext adapter is added.

### P1: no human takeover surface on Railway

The local implementation assumes a headed Linux display. Railway needs a
private, authenticated visual-control surface before MFA/CAPTCHA recovery can
be considered usable.

## Contribution strategy

Upstream changes should remain small and provider-neutral:

1. lifecycle and persistence correctness;
2. Linux host contract tests;
3. client-scoped task-space selection;
4. generic authenticated transport hooks;
5. Railway deployment documentation as a separate contribution.

Railway-specific policy, secrets, and remote UI should remain in the fork until
the generic host is stable and maintainers agree on the upstream seam.
