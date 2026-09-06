# Unified Platform POC Implementation Sequence

The [master plan](PLATFORM_MASTER_PLAN.md) and
[data standard](PLATFORM_DATA_STANDARD.md) define the target architecture.
This sequence replaces the previous greenfield AidaControl build order.

## 1. Baseline and boundaries

The development target is `dockerappvm01-dev` with `localsplash.dev`;
production uses `localsplash.ai`. Application protocols use configurable
`X.TLD` values.

Echo is working and its data and access must survive this work. Identity works
independently for Echo and Aida and requires deliberate consolidation.
AidaAdmin and OfficePulseAidaIntegration contain application code. AidaControl
is empty; AidaAgent and AidaHandset currently have no deployable application
baseline in their repositories. Existing POC artifacts on another server may
be reused after their source and version are located and validated.

OfficePulseAidaIntegration remains the sole call orchestrator and runtime
writer. AidaControl is deferred. Transfer its necessary contract, concurrency,
device and recovery requirements into the existing runtime's backlog instead
of creating another service.

Several businesses are required immediately. A platform Super Admin sees and
administers all businesses; tenant administrators and users operate within
their authorized businesses. Selected business/DID UI context does not itself
grant access.

Asterisk's vendor database remains outside this platform's schema ownership.
Keep its tables unchanged and provision through the supported integration.
Platform people and membership are reached through identity APIs.

## 2. Dependency matrix

| Workstream | Deliverable | Dependency | Gate |
| --- | --- | --- | --- |
| Operations / EchoOrchestrator | Host/store inventory, verified backups, isolated Aida composition, pinned releases | Current host | Existing Echo services, data and ports preserved |
| Platform contract | Canonical IDs, scoped settings, API/event contracts, migration mappings | Current-code review | One runtime owner and consistent contract |
| identity | `platform_db`, tenant/membership directory, `PlatformConfig` bootstrap, authorization/events | Contract; identity data inventory | Login continuity, explicit ID mapping, multi-business isolation |
| AidaAdmin | Reuse UI/BFF; directory-only platform data access; config ownership; MySQL session/state/receipts | identity contract/bootstrap | Scoped administration, provisioning feedback, durable sessions/events |
| OfficePulseAidaIntegration | Adapt existing runtime; complete lifecycle, concurrency, device and viewer API | Contract; Admin configuration | One runtime; real screening and fallback |
| AidaAgent | Reuse verified POC source or implement deployable worker | Runtime and LiveKit contract | Real agent, live transcript, handoff acknowledgment |
| AidaHandset | Reuse verified source or implement enrollment, notifications, data-only viewer and takeover | Runtime device API; agent events | Physical Android handset completes real workflow |
| EchoDatabase / EchoWeb / EchoService / EchoMedia | Compatible identity/tenant/config adoption in two waves | identity contract; Echo mappings | Existing access and messaging pass before retirement |
| Composed acceptance | Pinned deployment and actual cross-app smoke test | Required capabilities above | Several businesses, Super Admin, voice, messaging and recovery proven |

Source preparation, image builds, UI adapters and contract tests may proceed
in parallel. Documentation is not evidence that an integration is implemented.

## 3. Implementation gates

### A. Preserve and inventory

1. Record source SHAs, images, volumes, ports, networks, proxy routes, identity
   issuers, configuration bases and database schemas.
2. Inventory users, businesses and memberships in both identity deployments and
   Echo. Persist explicit legacy-source-to-canonical mappings; equal numeric
   IDs in independent stores do not identify the same person.
3. Verify backups before migration. Preserve existing Echo data and access.
4. Prepare Aida in an isolated local composition with non-conflicting ports and
   explicit volumes. Do not label unfinished endpoints production-ready.

### B. Establish the contract

1. Fix identity ownership of people, tenants and memberships. Define verified
   actor context for directory administrative writes and privilege changes.
2. Define settings scopes/precedence, bootstrap, required keys, overrides and
   secret visibility. One logical base need not use one unrestricted token.
3. Name every SQL owner, including Admin's sessions, login state and identity
   receipts. Replace the existing Admin PostgreSQL store explicitly; the
   MySQL-only target does not make that implementation disappear.
4. Pin compatible call, event, command, enrollment, token, transcript and error
   contracts in the runtime repository. Preserve existing wire fields.
5. Define expand/backfill/cutover/retire stages and event replay progress.
   Renames, type changes and deletion are not inherently rollback-safe.

### C. Migrate identity and administration

1. Bootstrap settings and additive identity data/directory work. Check existing
   Echo login before switching application consumers.
2. Map every current business and membership to canonical identifiers. Exercise
   at least two businesses and a user who must not see the other business.
3. Adapt Admin people/tenant/membership operations to identity APIs; remove
   direct platform-user editing through a second NocoDB base.
4. Backfill Aida tenant UUID references to canonical `iTenantId`, validate all
   configuration references, and keep source rows and mappings for rollback.
5. Migrate Admin's durable session/state/event store under its MySQL owner.
   Preserve the chosen session policy deliberately.
6. Retain required appearance and device configuration. Put consumable
   enrollment credentials and runtime state with the runtime owner. SIP secrets
   remain in Asterisk only.
7. Make provisioning partial failure explicit and retryable with stable
   idempotency. Saved intent is not confirmed PBX state.

### D. Complete one voice path

1. Adapt the existing FastAGI/ARI/LiveKit runtime to canonical tenant/config
   references without changing vendor schemas.
2. Complete state transitions and lifecycle delivery, atomic
   `expectedCallVersion` acceptance, idempotency and retries.
3. Supply handset enrollment/refresh, private notification authorization,
   active-call listing and data-only LiveKit viewer-token endpoints.
4. Align runtime dispatch with Agent one-time bootstrap, prompt delivery,
   readiness and handoff acknowledgments.
5. Supply a deployable Agent and Android application, reusing verified POC
   source where available. Repository stubs cannot satisfy “verify only.”
6. Demonstrate DID → disclosure → LiveKit screening → Android transcript →
   physical SIP-endpoint takeover → graceful agent drain.
7. Test failed-transfer resume, duplicate commands/webhooks, reconnect and
   deterministic fallback. Established calls retain pinned configuration
   during NocoDB outages.

### E. Adopt shared configuration in Echo

1. Introduce scoped readers and canonical mappings with verified compatibility
   for existing data and business access.
2. Validate Web login, business visibility, inbound/outbound messages, webhook
   delivery and media access.
3. Switch every consumer before retiring old settings/identity paths. Delete
   legacy data only in a later explicit retirement step after rollback checks.

## 4. Operations composition

Port EchoOrchestrator's executable operations foundation into this repository,
which owns the target architecture, runbooks and release composition. Keep the
existing Echo entry point until parity is proven. Deliver one Compose composition with
optional profiles, pinned artifacts, health/readiness checks, bootstrap/migration
commands and backup/restore instructions. Separate application containers may
share a physical host and SQL server with independent databases and grants.

A large installer, second control plane, generic synchronization platform and
separate system-test application are unnecessary for this POC. A repeatable
runbook and smoke test are required. Configure remote PBX coordinates explicitly.

## 5. Completion criteria

Local tests and image builds must pass but are insufficient alone. The composed
non-production deployment must demonstrate:

- Preserved Echo data and existing user access.
- Shared identity and canonical memberships for several businesses.
- Super Admin access to all businesses and tenant isolation for others.
- Real DID routing, disclosure, agent screening and live Android transcripts.
- Exactly one accepted takeover under contention, SIP answer, graceful agent
  drain and correct failed-transfer recovery.
- Enrollment/refresh revocation, signed webhooks, durable replay and retries.
- Deterministic fallback, usable readiness diagnostics and tested restore.

Use dedicated non-production records with actual configured PBX, identity,
database, LiveKit, notification and handset services for acceptance.
Credential-free substitutes remain appropriate for repository-local tests.
