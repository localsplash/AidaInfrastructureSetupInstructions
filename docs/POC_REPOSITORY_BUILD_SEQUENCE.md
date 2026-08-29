# Aida Voice POC Repository Build Sequence

## 1. Baseline

`localsplash/id` is the only application repository with pre-existing code. The following application repositories are greenfield builds:

- `localsplash/new_AidaControl`
- `localsplash/new_AidaAdmin`
- `localsplash/OfficePulseAidaIntegration`
- `localsplash/AidaAgent`
- `localsplash/AidaHandset`

`localsplash/AidaInfrastructureSetupInstructions` owns canonical specifications, environment setup, deployment automation, and cross-project smoke tests. The deprecated `delme_AidaControl` and `delme_AidaAdmin` repositories must not be used as dependencies or reference implementations.

Every numbered GitHub issue is a bounded autonomous build task. An agent must complete its acceptance criteria and repository-local tests before the next dependent phase begins. Each application repository owns its unit, contract, and integration tests; no separate system-test application is part of the POC. Unit tests may isolate external interfaces, but every POC integration and acceptance gate uses actual deployed services and dedicated non-production records. An isolated substitute for a provider, PBX, database, notification channel, identity service, or handset cannot satisfy POC completion.

## 2. Repository issue order

| Repository | Ordered implementation issues |
| --- | --- |
| `new_AidaControl` | #11 bootstrap; #12 contracts/Postgres; #13 NocoDB reads/DID resolution; #14 call bootstrap/LiveKit; #8 SIP route token; #9 handset enrollment/call API/Pusher; #15 commands/takeover/recovery; #10 trust boundary |
| `new_AidaAdmin` | #10 bootstrap; #8 identity; #11 NocoDB schema; #12 tenants/users/extensions/ring groups/provisioning; #13 profiles/routes/appearance; #9 AidaControl runtime proxy; #14 live operations UI |
| `OfficePulseAidaIntegration` | #1 bootstrap; #2 Asterisk Realtime provisioning; #3 FastAGI/LiveKit SIP routing; #4 ARI takeover; #5 disclosure/fallback/recording/hold; #6 MAC provisioning; #7 hardening/deployment |
| `AidaAgent` | #1 bootstrap; #2 dispatch metadata/route token/prompt; #3 voice session/transcript lifecycle; #4 barge-in/failed-transfer/graceful handoff; #5 guidance/tools; #6 deployment/reconnect/observability |
| `AidaHandset` | #1 bootstrap; #2 MAC enrollment; #3 Pusher/recovery; #4 LiveKit transcript UI; #5 Take over; #6 simultaneous calls/lifecycle; #7 GXV3450 release hardening |
| `AidaInfrastructureSetupInstructions` | #1 repository/environment matrix; #13 existing id deployment; #2 networking; #3 Postgres; #4 NocoDB; #5 LiveKit/Pusher/provisioning; #6 OfficePulse; #7 release composition/smoke test/operations |

The issue body in GitHub is authoritative for deliverables, acceptance criteria, tests, and direct dependencies.

## 3. Cross-repository dependency gates

1. Start each repository's bootstrap issue and Infrastructure issue #1 in parallel.
2. Complete AidaControl #12 before Agent, Handset, OfficePulse, or Admin implement an AidaControl contract consumer.
3. Complete AidaAdmin #11 before AidaControl #13 is finalized; both must use the same versioned NocoDB schema and generated identifiers.
4. Complete AidaControl #14 and #8 before integrating AidaAgent #2 or OfficePulse #3.
5. Complete AidaControl #9 and #15 before finalizing Handset #2–#5 or OfficePulse #4.
6. Complete application hardening, then execute Infrastructure #7 against pinned release artifacts.

## 4. POC completion gate

The POC is complete only when repository-local CI passes for every release, the setup repository can deploy pinned artifacts without application source checkouts, and its smoke test proves DID resolution, disclosure, LiveKit screening, live handset transcript, one-endpoint takeover, Aida graceful drain, failed-transfer resume, and deterministic fallback.
