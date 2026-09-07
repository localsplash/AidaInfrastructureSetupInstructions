# AidaAdmin local build and deployment readiness

Reviewed checkout: `/opt/aida/AidaAdmin`, main commit
`98d63ba6e2bfe8f322995180199a9521ecbb8fb4`.
No repository files were changed. No AidaAdmin service was started.
No AGENTS.md was found under `/opt/aida` or at `/opt/AGENTS.md`/`/AGENTS.md`.

## Verified

- Production Docker image built successfully using the repository Dockerfile:
  `aida-admin:review-98d63ba`.
- Image ID:
  `sha256:f13b1f7ba49a962f1650cdbfad4c2069b0924f0bdb678d1a5d162ef66d7efb95`.
- An isolated Node 22 validation image passed TypeScript checks, **204 tests**
  (158 server + 46 UI), and the production build. **8 live integration tests
  were skipped** because dedicated PostgreSQL/NocoDB connections were absent.
- Validation image: `aida-admin:validation-98d63ba`;
  image ID `sha256:2ca25b934964dec664d181e1ec1f8af22cecfddb2f97fb0091af923adc39a825`.
- Validation Dockerfile: `/opt/platform-review/aida-admin-validation.Dockerfile`.
- Host Node is `v18.19.0`, below the repository's `>=22` requirement.
  Use the verified Node 22 Docker build for local deployment.
- Dependency installation reported one moderate advisory. No dependency
  upgrades or automatic audit fixes were applied during this baseline review.

## Configuration still required for a functional deployment

There is no local `.env` in the checkout. Current production startup requires
all of the following keys. This inventory lists names, not secret values:

| Purpose | Keys |
| --- | --- |
| Public application and signed cookie | `PUBLIC_BASE_URL`, `SESSION_SECRET` |
| Current Admin persistence | `AIDA_ADMIN_DATABASE_URL` (PostgreSQL today) |
| Identity origin and trust | `ID_BASE_URL`, `ID_PARENT_DOMAIN`, `ID_TRUSTED_APP_CIDRS`, `ID_EVENT_SOURCE_CIDRS`, `ID_TRUSTED_PROXY_CIDRS` |
| Existing configuration reader/writer | `NOCODB_BASE_URL`, `NOCODB_API_TOKEN` |
| PBX/runtime integration | `OFFICEPULSE_PROVISIONING_BASE_URL`, `OFFICEPULSE_RUNTIME_DATABASE_URL` (SELECT-only MySQL grant) |
| Handset enrollment delivery | `HANDSET_PROVISIONING_URL` |

Set persistent writable asset storage for the non-root container, a
non-conflicting local port, and the intended reverse-proxy callback origin.
The default listener is port 3001. `ID_REGISTER_WEBHOOK` controls webhook
registration; configure it deliberately.

## Why the built image is not yet the consolidated application

The current code still discovers/creates the NocoDB base `AidaAdmin`, reads
and writes legacy snake_case config tables, and optionally accesses platform
users through `AidaIdentity`. It does not yet implement `PlatformConfig`,
the identity-only directory ownership rule, or the new tenant ID mapping.
Its own durable session/event store is PostgreSQL, which requires the separate
MySQL migration identified in the review.

On startup the code applies PostgreSQL schema changes before serving and can
create/upgrade its NocoDB schema after listening. It also attempts identity
event catch-up and optional webhook registration. A real configuration should
therefore be connected only through the reviewed staging/migration composition,
not copied casually from the working Echo deployment.

Credential-free development mode can render a shell with memory stores; that
does not validate identity, persistence, telephony or a functional POC.
The tests above validate the checked-in implementation and its fakes, not
integration with the real configured PBX, identity or handset.

## Local documentation changes

Only these Infra files were edited by this review agent:

- `/opt/aida/AidaInfrastructureSetupInstructions/README.md`
- `/opt/aida/AidaInfrastructureSetupInstructions/docs/POC_REPOSITORY_BUILD_SEQUENCE.md`

They preserve Echo, adopt the accepted OfficePulse runtime and multi-business
POC, link the new master plan/data standard, and label older architecture as
historical. `git diff --check` passed.

The full architecture review and PR16 replacement plan is
`/opt/platform-review/aida-review.md`.
