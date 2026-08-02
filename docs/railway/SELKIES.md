# Selkies visual-control surface

Status: running in the Railway `staging` environment. The immutable
`linux/amd64` image built from `3ae4f294997db92cf2cc016c2feadf2e59a427ba`
is deployed as digest
`sha256:39c399b958f8a172ee265523da0e31cbe964b3962455f7e38efe962d3fccb734`.
This is staging evidence, not a production promotion.

## What this surface shows

This repository contains the open `ego-browser` harness and Linux host, not the
closed-source Ego Lite desktop application. On Railway, Selkies therefore
streams the headed Chromium session owned by the Linux host. Hermes, Codex, and
Claude Code continue to operate the same process through the local Ego/CDP
adapter. Selkies does not replace the browser or expose CDP.

```text
OnixDesk iframe -> HTTPS/WSS -> Selkies -> Xvfb/Openbox -> Chromium
                                                    ^
                                                    |
agent -> ego-browser -> Unix socket -> Linux host -> local CDP

/data/ego-lite/profile -> the same Chromium user-data-dir
```

The persistent profile, cookies, local storage, IndexedDB, and settings remain
under `/data/ego-lite/profile`. The visual runtime, X11 socket, process ids, and
logs stay under `/run/ego-lite` and are recreated with every container.

Chromium also writes three Linux singleton symlinks inside the profile. They
contain container-local host/socket ownership and are not durable browser data.
The Railway entrypoint removes only those stale symlinks before Chromium starts;
it preserves the rest of the profile and refuses to remove an unexpected
non-symlink at the same names. It first acquires a persistent advisory owner
lock and holds that lock for the full container lifetime, preventing a second
cooperating container from reclaiming a profile that is still active.

## Railway transport choice

The Railway image locks Selkies to its WebSocket/WebCodecs transport. It uses a
single public TCP port and works behind Railway's TLS proxy. WebRTC remains a
future dedicated-VM option because high-quality WebRTC needs public UDP or a
reviewed TURN service; silently falling back to an arbitrary public TURN relay
is not acceptable for authenticated browser sessions.

The external port is `PORT` (default `8080`). Ego host health moves to the
loopback-only `EGO_INTERNAL_HEALTH_PORT` (default `8082`), with
`EGO_HEALTH_HOST=127.0.0.1`. Railway probes the
unauthenticated Selkies liveness endpoint `/api/health`; the supervisor starts
Selkies only after Ego host `/readyz` confirms the Unix socket and local CDP are
ready. If Xvfb, Openbox, PulseAudio, Ego host, or Selkies exits, the supervisor
terminates the container so Railway can replace it.

## Required secrets

Set all tokens as Railway secrets. Each must be at least 32 characters, strong,
and distinct:

```text
SELKIES_MASTER_TOKEN           server-only control-plane secret
EGO_VIEWER_CONTROLLER_TOKEN    human keyboard/mouse controller
EGO_VIEWER_VIEWER_TOKEN        optional read-only observer
```

The bootstrap helper provisions the two browser roles through Selkies'
loopback token API. It never prints token values. Never expose the master token
to OnixDesk or place any token in Git, build arguments, logs, screenshots, or
analytics.

For the current single-owner staging proof, the iframe URL is:

```text
https://<railway-domain>/?token=<viewer-or-controller-token>
```

Query-string credentials can leak through browser history or infrastructure
logs. Production OnixDesk integration must exchange an authenticated OnixDesk
session for a short-lived Selkies token server-side and set `Referrer-Policy:
no-referrer`; a static token URL must not be placed in a frontend bundle.

## Human and agent control

Selkies can enforce viewer versus controller permissions among visual clients,
but it cannot pause an agent that drives local CDP. The current safe procedure
is explicit:

1. The agent calls `handOffTaskSpace` and stops page-changing CDP work.
2. OnixDesk loads or enables a controller token for the human.
3. The human completes MFA, CAPTCHA, login recovery, or manual work.
4. OnixDesk removes controller access.
5. The agent calls `takeOverTaskSpace` and resumes.

Automating that lease is a separate gateway tranche. Until it exists, do not
allow the human controller and agent to send concurrent input. The viewer token
is safe for observation while the agent works.

## Live staging evidence

The controlled Railway acceptance run on 2026-08-02 UTC recorded:

- deployment `880116fe-3b5a-47af-a2e1-57ef35450ab4` reached `SUCCESS` with one
  replica, `overlapSeconds=0`, health path `/api/health`, and the volume mounted
  at `/data`;
- public `/api/health` returned 200, while `POST /api/tokens` without the master
  credential returned 401;
- an invalid streaming token was closed with WebSocket code 4001, and the two
  provisioned client tokens were reported as `controller` and `viewer`;
- a controlled-origin cookie, localStorage item, and IndexedDB record written
  before container replacement were all read from the final deployment;
- a 1920x1080 Playwright capture showed the streamed headed Chromium, with zero
  browser-console errors and warnings;
- a safe log scan found no master, controller, or viewer token value or fatal
  startup marker, and confirmed disabled gamepad initialization was skipped.

The token-free command transcript and immutable identifiers are recorded in
[`evidence/2026-08-02-staging.md`](./evidence/2026-08-02-staging.md).

The live browser used a controlled fixture only. No customer account or
customer authentication data was used. Viewer-role input denial, backup
restore, automatic human/agent leases, quantitative latency, and forced-kill
profile recovery remain separate gates.

## Security defaults

- raw CDP stays on `127.0.0.1` and is never routed publicly;
- Selkies Basic Auth and self-generated sharing links are disabled;
- the master-token API provisions explicit controller/viewer roles;
- Selkies command execution, file transfer, microphone, and gamepad are off;
- Chromium remains the only writer of the persistent profile;
- the container remains one replica with one attached volume;
- HTTPS is terminated by Railway; Selkies itself listens on internal HTTP;
- the 1920x1080 display is fixed and software-encoded for Railway's CPU-only
  runtime; the iframe scales that stream without resizing the persistent
  browser process;
- the upstream Selkies source is vendored at an exact commit, its frontend
  dependencies are locked, and provenance is documented in
  `THIRD_PARTY_NOTICES.md`.

Railway staging currently needs the explicit `EGO_CHROME_NO_SANDBOX=1`
compatibility fallback after its runtime terminated sandboxed Chromium with
`SIGTRAP`. The image default remains sandboxed. The managed Chromium policy
only removes the persistent warning banner; it does not restore sandboxing or
reduce this exception's security impact.

Clipboard and audio remain enabled for normal browsing. Disable clipboard with
`SELKIES_ENABLE_CLIPBOARD=false` if the target environment has stricter data
loss prevention requirements.

## Local verification

Configuration and negative tests:

```bash
bash scripts/test-railway-selkies.sh
```

Target image build (the vendored Selkies source is built for `linux/amd64`):

```bash
docker build --platform linux/amd64 -f Dockerfile.railway \
  -t ego-lite-selkies:local .
```

A live acceptance test must then prove:

1. `/api/health` returns 200 without exposing master/controller/viewer tokens.
2. No token and an invalid token cannot open a streaming connection.
3. The viewer token cannot send keyboard or mouse input.
4. The controller token can click and type after `handOffTaskSpace`.
5. The agent can observe the exact same tab through Ego helpers.
6. Cookie, localStorage, and IndexedDB survive restart and redeploy.
7. SIGTERM closes Chromium before the Railway deadline without profile
   corruption.
8. A test iframe loads from the intended OnixDesk origin with no console,
   WebSocket, CSP, mixed-content, or authentication errors.

Do not use a real customer account until every negative test passes in staging.
