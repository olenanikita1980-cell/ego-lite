# Railway persistent browser architecture

Status: the single-container persistence tranche is implemented and under
verification. Remote multi-agent execution remains blocked until the
client-isolation and gateway gates below are implemented and verified.

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
supported now (one container)

Hermes / Codex / Claude Code
        |
        v
ego-browser shim -> local Unix socket -> ego Linux host daemon
                                            |
                                            v
                                      one Chromium process
                                            |
                                            v
                                  Railway volume mounted at /data
                                    /data/ego-lite/profile
                                    /data/ego-lite/spaces.json

future multi-service mode

authorized clients -> authenticated, client-isolated task gateway -> daemon
                      (not implemented; never raw CDP)
```

Runtime-only files such as the Unix socket and PID file must live outside the
persistent volume. Persisting them creates stale ownership artifacts after a
container replacement.

## Locked decisions

1. One Railway service replica owns one profile volume. Chromium profile
   directories are single-writer resources.
2. Chromium runs as a non-root user; raw CDP listens on loopback only.
3. Browser state lives under `/data/ego-lite/profile`; deployment/runtime state does not.
4. Shutdown persists task-space state atomically, asks Chrome to close through
   CDP, and uses process termination only as a bounded fallback. Draining
   in-flight RPC is still a required lifecycle gate.
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

### Resolved in this branch: container shutdown did not close Chromium

PR #134 closed its socket and CDP transport but intentionally left Chrome
running. This branch saves task-space state, sends `Browser.close`, waits for
process exit, and uses bounded process-group termination only as a fallback.
The opt-in persistence E2E restarts a new browser process against the same
profile and checks cookie, localStorage, and IndexedDB state.

### Resolved in this branch: task-space persistence was non-atomic

PR #134 wrote `spaces.json` directly. This branch writes a restricted sibling
temporary file, syncs it, atomically renames it, and syncs the parent directory.
An injected rename failure test proves the previous valid file remains intact.

### Mitigated in this branch: stale socket recovery could create a competing daemon

PR #134 unlinked the socket after a failed ping. This branch separates runtime
files from the persistent volume, uses an exclusive owner lock, and refuses to
unlink a socket when the recorded owner is still alive. `stop` now fails closed:
it signals only a ready socket whose PID and lock records agree, and refuses a
live but unverified PID. A brief starting daemon must become ready before the
CLI stop command will signal it; container-level SIGTERM remains available.

### P1: shutdown does not drain in-flight RPC

The daemon stops the listener and destroys connected clients before closing
Chromium. Long-running work can therefore be interrupted during Railway's
SIGTERM window. A bounded reject-new-work/drain-active-work phase is required
before this can be promoted beyond serialized single-owner use.

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
