# Railway persistent browser QA matrix

No tranche is production-ready until its required rows have fresh evidence.
The live rows below point to the token-free acceptance record in
[`evidence/2026-08-02-staging.md`](./evidence/2026-08-02-staging.md); authorized
reviewers must still re-query Railway for current state.

| Area | Required behavior | Verification | State |
| --- | --- | --- | --- |
| Profile | Cookie survives daemon restart | controlled fixture, restart, state assertion | passing locally (macOS Chrome + Linux Chromium) |
| Profile | Cookie survives Railway redeploy | volume-backed staging redeploy | passing live on Railway staging with a controlled origin |
| Profile | localStorage and IndexedDB survive | write, restart, read | passing locally, across two containers, and after live Railway replacement |
| Profile | failed shutdown does not silently reset profile | forced termination recovery test | pending |
| Lifecycle | SIGTERM closes Chrome gracefully | integration test observes `Browser.close` and process exit | passing unit + local container SIGTERM/profile re-open |
| Lifecycle | stop is idempotent | repeated stop leaves no PID/socket/listener/process | passing unit; live `host:stop` on Railway pending |
| Lifecycle | stop never signals an unverified PID | socket readiness and agreeing PID/lock are required | passing positive and negative unit tests |
| Lifecycle | stale socket cannot spawn two daemons | concurrent-start adversarial test | passing lock/live-owner unit tests |
| Lifecycle | stale Chromium singleton links do not block a replacement container | owner lock plus exact-link cleanup test; every unexpected non-symlink is preserved and fails closed | passing in CI owner-lock E2E and live Railway redeploy |
| Storage | task-space state write is atomic | injected write failure retains previous valid state | passing unit |
| Storage | backup restores usable profile | restore into staging and authenticate fixture | pending |
| Isolation | Hermes cannot switch Codex's selected space | concurrent two-client test | blocked |
| Isolation | CDP events only reach the owning client | adversarial event-routing test | blocked |
| Security | raw CDP is unreachable externally | network probe against public/private interfaces | loopback binding passes locally and live public `/json/version` returns 404; private-interface probe pending |
| Security | weak or missing Selkies secrets fail startup | local negative configuration test | passing locally |
| Security | missing/invalid viewer token is rejected | live WebSocket negative test | passing live; invalid token closed with code 4001 |
| Security | viewer token cannot send keyboard/mouse input | live role negative test | viewer role assignment passes live; input-negative assertion pending |
| Security | logs do not contain cookies or credentials | redaction scan | passing for final staging deployment token-value scan; cookie-content scan remains fixture-scoped |
| Human handoff | observer iframe sees the agent browser | authenticated Selkies iframe E2E | controller visual stream passes at 1920x1080; observer visual E2E pending |
| Human handoff | MFA task pauses and can be resumed | `handOffTaskSpace` + controller + `takeOverTaskSpace` E2E | pending |
| Human handoff | controller access automatically owns a task lease | gateway integration E2E | blocked |
| Operations | run/status/stop report the same process tree | fresh container smoke | passing local container for run/status/SIGTERM; Railway pending |
| Operations | healthcheck distinguishes daemon from browser readiness | internal Ego `/readyz` plus public Selkies `/api/health` probes | passing locally and on the final Railway staging deployment |
| Compatibility | existing ego-browser test suite passes | `npm test` in `package/ego-browser` | passing locally (311/311) |
| Compatibility | Linux-host unit suite passes | `npm test` in `package/ego-linux-host` | passing locally (118 pass, 2 opt-in E2E skipped) |
| Runtime | real Linux Chromium persistence smoke passes | controlled origin + persisted state | passing in built image, including two-container volume phases |
| Selkies | configuration, secret redaction, and port conflicts are checked | `bash scripts/test-railway-selkies.sh` | passing locally |
| Selkies | vendored pinned source builds for linux/amd64 | Docker/Railway build | passing GitHub Actions build and live Railway runtime |
| Selkies | 1080p interaction has acceptable latency and visual quality | browser iframe + stats capture | 1920x1080 visual and console check pass; quantitative latency pending |
| Railway | real staging deployment passes | build, health, volume, restart, redeploy evidence | passing for controlled staging deploy/redeploy and persistence; backup restore and production promotion pending |

## Promotion gates

- Persistence tranche: profile lifecycle, atomic state, and stop controls pass.
- Multi-agent tranche: client selection and CDP event isolation pass under
  concurrent Hermes/Codex/Claude-shaped clients.
- Railway tranche: authenticated gateway, health checks, persistent volume,
  static egress policy, backups, and human takeover are verified in staging.
- Upstream PR: diff is provider-neutral, existing tests pass, attribution is
  preserved, and no Railway credentials or customer browser data are included.
