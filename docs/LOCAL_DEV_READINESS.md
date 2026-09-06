# Local development readiness — 2026-09-06

Host: `dockerappvm01-dev`. Development domain: `localsplash.dev`.

The first implementation wave is built, tested and proposed in PRs. AidaAgent and AidaHandset now have real applications. The combined platform has **not** been deployed or validated with a real PBX/LiveKit/Android call. Existing Echo, Identity and NocoDB services and their data remain unchanged.

## Implementation PRs

| Repository / PR | Local reviewed source | Delivered |
| --- | --- | --- |
| [identity #18](https://github.com/localsplash/identity/pull/18) | `/opt/platform-work/identity`, `0ccd788` plus separately preserved deployed baseline | Central users/tenants/memberships/SSO and app sessions; actor directory APIs; PlatformConfig; mapping utilities |
| [AidaAdmin #32](https://github.com/localsplash/AidaAdmin/pull/32) | `/opt/aida/AidaAdmin`, `bacb7b7` | PostgreSQL removed; central sessions/directory; MySQL state/receipts/audit; voice profiles and runtime enrollment |
| [OfficePulse #11](https://github.com/localsplash/OfficePulseAidaIntegration/pull/11) | `/opt/aida/OfficePulseAidaIntegration`, `101a694` | Canonical tenants, scoped device APIs, public/private listeners, transactional commands/lifecycle/webhooks, per-DID offline fallback |
| [AidaAgent #8](https://github.com/localsplash/AidaAgent/pull/8) | `/opt/aida/AidaAgent`, `438e32d` | Python LiveKit worker, reliable live transcripts, bounded agent handoff |
| [AidaHandset #9](https://github.com/localsplash/AidaHandset/pull/9) | `/opt/aida/AidaHandset`, `a758866` | Android enrollment, encrypted credentials, assigned-call list, data-only transcript viewer, versioned takeover |
| [EchoDatabase #9](https://github.com/localsplash/EchoDatabase/pull/9) | `/opt/platform-work/EchoDatabase`, `ff4939c` | Additive historical organization/number/user mappings and dry-run importer |
| [EchoWeb #22](https://github.com/localsplash/EchoWeb/pull/22) | `/opt/platform-work/EchoWeb`, `b2ab311` | Central sessions, current memberships, business-number picker, scoped messaging proxy and SUPER_ADMIN carrier controls |
| [Platform architecture / deployment #17](https://github.com/localsplash/AidaInfrastructureSetupInstructions/pull/17) | `/opt/aida/AidaInfrastructureSetupInstructions`, `plan/unified-office-platform` | Master design, issue reconciliation, data standard and isolated development Compose |

GitHub commits have equivalent trees but different commit IDs from the local checkouts because publication used the authenticated GitHub API. Record the remote PR head SHAs when creating a release. All application PRs are draft proposals for coordinated rollout, not live deployment claims.

AidaControl remains deferred; OfficePulse owns voice orchestration. No replacement service is needed merely to fill that repository. EchoOrchestrator remains the existing Echo operational entry point; the small Aida composition in this repository prepares the additional containers without a monolithic installer or repository merge.

## Validation actually performed

| Component | Evidence |
| --- | --- |
| Identity | Node 22 build, 160 unit/contract tests and 13 real MySQL integration tests |
| AidaAdmin | Formatting/lint/typecheck/build, 155 server + 46 UI tests; five real MySQL tests; production image and non-root asset-directory write check |
| OfficePulse | Typecheck/build, 180 unit/HTTP/contract tests; 15 substantive MySQL scenarios (17 TAP tests including suite parents); production image and packaged-migration rerun |
| AidaAgent | Ruff, 82 tests, installed LiveKit Agents 1.8.0/Silero/inference checks and offline CLI validation; non-root runtime image |
| AidaHandset | 15 unit/HTTP tests, Android lint and real debug APK assembly |
| EchoWeb / EchoDatabase | 15 unit/HTTP tests plus four real MySQL migration/importer tests; production image |
| Development Compose | Synthetic `docker compose config --quiet`, port/trust/credential assertions, build-context checks and MySQL init-script validation |

All MySQL tests used disposable schemas/containers. Provider-facing Agent tests ran offline without paid calls. Local reports live under `/opt/platform-review`. GitHub CI was verified successful for Identity, AidaAdmin and AidaAgent at this point; other PR checks should be read from their latest heads before merge.

The installable handset debug artifact is `/opt/platform-review/aida-handset-debug.apk` (SHA-256 `63ef14f01cbe5b8d6e986e0859d2fd89470290e2b32e08f91893eec924e01abc`). It is not a signed production release and has not been exercised on the actual office handset.

## Planned NPM mappings

These ports are reserved by the prepared composition; **the services are not listening yet**.

| Hostname | Host port → container | Purpose |
| --- | --- | --- |
| `aida-admin.localsplash.dev` | `18086 → 3001` | Administration and Identity callback |
| `aida-api.localsplash.dev` | `18085 → 8086` | Handset APIs and signed LiveKit webhooks |

Agent has no public HTTP ingress. Android is installed as an APK. Private OfficePulse `8085` stays inside the Aida Docker network. FastAGI is a separate PBX-only TCP mapping. The Compose defaults bind published ports to loopback; select the actual private interface NPM/PBX can reach. See [the deployment runbook](DEV_DOCKER_DEPLOYMENT.md).

## Work before combined POC acceptance

1. Rehearse the Identity database/settings copy and canonical mappings while preserving users, provider identities and sessions. The deployed `/opt/identity` worktree was preserved in a separate source commit; it was not overwritten. Establish several canonical businesses and reviewed memberships before switching consumers. Legacy app cookies obtain a fresh central SSO handoff; account access and history are retained.
2. Bootstrap/import PlatformConfig voice profiles with explicit legacy tenant mappings. Keep remote Aida source stores available. No remote POC runtime was verified.
3. Select the PBX and provide its supported ARI/Realtime/LiveKit trunk configuration, a test DID, local fallback and an actual handset. Apply only supported integration configuration; leave vendor schemas upstream-owned.
4. Configure the isolated Aida composition and NPM, then run real login, enrollment, transcript, takeover, hangup and dependency-loss tests for two businesses and SUPER_ADMIN.
5. Complete EchoService and EchoMedia tenant-aware authorization/media delivery before claiming the entire messaging/media surface is isolated. EchoWeb's new boundary does not make existing direct service endpoints or public media URLs private. Per-business carrier-account administration and historic media ownership remain explicit follow-up work.
6. Verify existing Echo send/receive, media and logins after the coordinated cutover. Review the old Echo migration runner's ledger/baselining before applying new SQL to an existing volume. Take and restore-rehearse backups before retiring any source store.

## Superseded proposals and review packet

[Infra PR #16](https://github.com/localsplash/AidaInfrastructureSetupInstructions/pull/16) was closed in favor of #17. [EchoDatabase PR #3](https://github.com/localsplash/EchoDatabase/pull/3) was closed; its duplicate Identity schema creation and stale drops were not merged. No implementation PR has been merged in this development wave.

The original source review is retained in [the Aida review](reviews/aida-review.md), [Echo review](reviews/echo-review.md), [voice/client review](reviews/voice-clients-review.md) and [source inventory](reviews/source-inventory.json). Those describe the pre-implementation baseline. The current architecture and remaining acceptance gates are in the [master plan](PLATFORM_MASTER_PLAN.md), [data standard](PLATFORM_DATA_STANDARD.md) and [implementation sequence](POC_REPOSITORY_BUILD_SEQUENCE.md).
