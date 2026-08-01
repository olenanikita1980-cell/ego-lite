# Railway persistent browser QA matrix

No tranche is production-ready until its required rows have fresh evidence.

| Area | Required behavior | Verification | State |
| --- | --- | --- | --- |
| Profile | Cookie survives daemon restart | login fixture, restart, authenticated assertion | pending |
| Profile | Cookie survives Railway redeploy | volume-backed staging redeploy | pending |
| Profile | localStorage and IndexedDB survive | write, restart, read | pending |
| Profile | failed shutdown does not silently reset profile | forced termination recovery test | pending |
| Lifecycle | SIGTERM closes Chrome gracefully | integration test observes `Browser.close` and process exit | pending |
| Lifecycle | stop is idempotent | repeated stop leaves no PID/socket/listener/process | pending |
| Lifecycle | stale socket cannot spawn two daemons | concurrent-start adversarial test | pending |
| Storage | task-space state write is atomic | injected write failure retains previous valid state | pending |
| Storage | backup restores usable profile | restore into staging and authenticate fixture | pending |
| Isolation | Hermes cannot switch Codex's selected space | concurrent two-client test | blocked |
| Isolation | CDP events only reach the owning client | adversarial event-routing test | blocked |
| Security | raw CDP is unreachable externally | network probe against public/private interfaces | pending |
| Security | missing/invalid gateway token is rejected | API negative tests | blocked |
| Security | logs do not contain cookies or credentials | redaction scan | pending |
| Human handoff | MFA task pauses and can be resumed | authenticated visual takeover E2E | blocked |
| Operations | run/status/stop report the same process tree | fresh container smoke | pending |
| Operations | healthcheck distinguishes daemon from browser readiness | HTTP health/readiness tests | blocked |
| Compatibility | existing ego-browser test suite passes | `npm test` in `package/ego-browser` | passing locally (299/299) |
| Compatibility | Linux-host unit suite passes | `npm test` in `package/ego-linux-host` | passing outside restricted socket sandbox (101 pass, 1 Chrome E2E skipped) |
| Runtime | real Linux Chromium smoke passes | title + snapshot + persisted state | pending |
| Railway | real staging deployment passes | build, health, volume, restart, redeploy evidence | pending |

## Promotion gates

- Persistence tranche: profile lifecycle, atomic state, and stop controls pass.
- Multi-agent tranche: client selection and CDP event isolation pass under
  concurrent Hermes/Codex/Claude-shaped clients.
- Railway tranche: authenticated gateway, health checks, persistent volume,
  static egress policy, backups, and human takeover are verified in staging.
- Upstream PR: diff is provider-neutral, existing tests pass, attribution is
  preserved, and no Railway credentials or customer browser data are included.
