# Local development readiness — 2026-09-06

Host: `dockerappvm01-dev`. Development domain: `localsplash.dev`.

The Aida repositories have been obtained locally and the implemented applications build. The consolidated platform is not yet deployed. This readiness report records work actually executed, separately from the target in the [master plan](PLATFORM_MASTER_PLAN.md).

## Local source and builds

| Repository | Local path | Result |
| --- | --- | --- |
| AidaInfrastructureSetupInstructions | `/opt/aida/AidaInfrastructureSetupInstructions` | Proposed corrected plan on local branch `plan/unified-office-platform` |
| AidaAdmin | `/opt/aida/AidaAdmin` | Node 22 typecheck, production build and 204 tests passed; 8 live integration tests skipped |
| OfficePulseAidaIntegration | `/opt/aida/OfficePulseAidaIntegration` | Node 22 typecheck, production build and 163 tests passed |
| AidaAgent | `/opt/aida/AidaAgent` | README only; no worker source/build |
| AidaHandset | `/opt/aida/AidaHandset` | README only; no Android source/APK |
| AidaControl | `/opt/aida/AidaControl` | Empty repository; separate service deferred by owner decision |

The application checkouts are unchanged. The local host's Node 18 is below the implemented applications' Node 22 requirement, so validation used isolated Docker builds. Tests used repository fixtures/fakes; there were no live PBX/LiveKit/device calls or database migration rehearsals in this review.

| Image | ID | Purpose |
| --- | --- | --- |
| `aida-admin:review-98d63ba` | `sha256:f13b1f7ba49a962f1650cdbfad4c2069b0924f0bdb678d1a5d162ef66d7efb95` | AidaAdmin repository production Dockerfile build |
| `aida-admin:validation-98d63ba` | `sha256:2ca25b934964dec664d181e1ec1f8af22cecfddb2f97fb0091af923adc39a825` | Admin typecheck/tests/build |
| `aida-officepulse-validation:291e2d9` | `sha256:57abf5ae70628cb776583be93233f06fd108fc9f5ccb2bf738159d42c8d0cfa8` | OfficePulse typecheck/tests/build; not a deployment image |

Validation recipes are in [`validation/`](../validation/officepulse-validation.Dockerfile). They intentionally install development dependencies and run tests; use application production Dockerfiles for released services. Reproduce from the recorded source commits, with each repository as the build context:

```bash
docker build -f /opt/aida/AidaInfrastructureSetupInstructions/validation/aida-admin-validation.Dockerfile -t aida-admin:validation-98d63ba /opt/aida/AidaAdmin
docker build -f /opt/aida/AidaInfrastructureSetupInstructions/validation/officepulse-validation.Dockerfile -t aida-officepulse-validation:291e2d9 /opt/aida/OfficePulseAidaIntegration
```

## Existing local baseline

Docker reported healthy EchoWeb, EchoService, EchoMedia, Echo MySQL, Identity and Identity MySQL containers. NocoDB is also running. This was read-only process inspection; it does not validate business workflows. Their volumes and deployed configuration were not migrated.

The Identity worktree contains local setup/configuration/deployment changes absent from GitHub main, including `src/localConfig.ts`. Preserve and reconcile those changes before rebuilding Identity from a remote branch. Echo repositories were clean at inventory time; EchoOrchestrator was on `feat/echo-service-log-volume`. [Source inventory](reviews/source-inventory.json).

Other services share the host, including unrelated PostgreSQL workloads. The telephony MySQL standard does not apply to those services. The existing port 3001 is already in use on the host, so AidaAdmin's default must not be published there in the local composition.

## Deployment prerequisites and implementation gaps

1. Select the existing PBX target versus a separate local PBX and configure only its supported adapter endpoints/credentials. The remote POC was not accessed. Do not assume an Asterisk instance exists on this development host.
2. Reconcile Identity/configuration compatibility and central tenants before connecting Admin to the working platform stores. Current Admin can migrate its legacy stores and register Identity callbacks on startup, so starting it with copied credentials is already a state-changing integration action.
3. Migrate Admin's PostgreSQL sessions/state/receipts to its owned MySQL store. Its current reader uses legacy NocoDB bases; the compiled image does not implement the proposed PlatformConfig contract yet.
4. Complete OfficePulse's canonical tenant mapping, handset auth/tokens, active-call discovery, command concurrency, call lifecycle and per-DID offline fallback. Preserve existing provisioned SIP identifiers during tenant conversion.
5. Supply Agent and Handset implementations, or obtain and validate their actual source from the other POC. Current GitHub repositories cannot produce either application.
6. Configure reviewed LiveKit/provider/notification details, a test DID, two businesses, authorized users, extensions and actual Android handset access. Keep credentials in server-side configuration; do not paste them into issue bodies or the review packet.
7. Produce the isolated Compose/profile and proxy configuration against these corrected interfaces, using non-conflicting ports/volumes and pinned artifacts. Run the [combined acceptance gates](PLATFORM_MASTER_PLAN.md#combined-poc-acceptance).

## Review packet

- [Master architecture and issue-by-issue reconciliation](PLATFORM_MASTER_PLAN.md)
- [Corrected data/configuration/migration standard](PLATFORM_DATA_STANDARD.md)
- [Dependency-ordered implementation sequence](POC_REPOSITORY_BUILD_SEQUENCE.md)
- [Aida architecture and PR16 review](reviews/aida-review.md)
- [Echo code, migration and access review](reviews/echo-review.md)
- [Voice runtime, Agent and Handset review](reviews/voice-clients-review.md)
- [Admin configuration/build details](reviews/aida-admin-readiness.md)

These are local proposed changes. GitHub issues and pull requests have not been modified, merged or closed. Infra PR #16 should be corrected to this agreed runtime direction; EchoDatabase PR #3 should not be merged with its stale Identity schema/drop operations. The master plan states the intended disposition for every linked item.
