# AidaInfrastructureSetupInstructions

Architecture and operator documentation for one self-hosted voice and messaging
platform. The development target is `dockerappvm01-dev`, with separate
application containers and explicit database ownership. OfficePulse/Asterisk
remains an independently managed PBX.

## Accepted POC decisions

- Preserve working Echo data and access throughout consolidation.
- Support several businesses immediately. A platform Super Admin can administer
  all businesses; other access remains tenant-scoped.
- Keep OfficePulseAidaIntegration as the sole Aida call orchestrator. AidaControl
  is deferred; no second runtime service or call database is built.
- Use identity-owned `platform_db` for people, tenants and memberships,
  `PlatformConfig` for settings and slow-moving application configuration,
  and owner-specific MySQL application stores.
- Preserve Asterisk's vendor schema. Customize through supported provisioning,
  deployment includes and PBX configuration.
- Configure the host domain as `X.TLD`: `localsplash.dev` in development and
  `localsplash.ai` in production.

## Current specification

Read these documents in order. They control the corrected POC architecture and
supersede conflicting historical documents and issue instructions:

1. [Platform master plan](docs/PLATFORM_MASTER_PLAN.md)
2. [Platform data standard](docs/PLATFORM_DATA_STANDARD.md)
3. [Implementation and validation sequence](docs/POC_REPOSITORY_BUILD_SEQUENCE.md)

The [running preview status](docs/DEV_PREVIEW_STATUS.md) records the launched
containers, exact NPM destinations, preserved data and remaining voice setup.
The [earlier readiness report](docs/LOCAL_DEV_READINESS.md) retains the initial
implementation/build evidence and source reviews.

The [original voice technical specification](docs/AIDA_VOICE_PLATFORM_TECHNICAL_SPECIFICATION.md)
and [original POC database/interface specification](docs/AIDA_POC_DATABASE_AND_INTERFACE_SPECIFICATION.md)
remain historical references. Their greenfield AidaControl architecture, database
inventory and tenant ownership statements do not override the current documents.
Issue acceptance criteria remain useful where consistent; obsolete ownership and
dependency instructions require correction before implementation.

## Operations ownership

Consolidate executable deployment responsibilities in this repository, porting
the working [EchoOrchestrator](https://github.com/localsplash/EchoOrchestrator)
foundation: one pinned release composition, service/endpoint inventory,
configuration bootstrap, backup/restore procedure and cross-application smoke
test. EchoOrchestrator remains the compatibility entry point until deployment
parity is proven. This repository owns both the architecture and the target
operator workflow. A reviewed Compose composition and small documented commands
are sufficient for the POC.

Inventory DNS, TLS, network trust, store ownership, secrets, image versions,
persistent volumes and remote PBX connections. Bootstrap `PlatformConfig`
before dependent applications, then run each store owner's migration. Keep
legacy stores and mappings through a verified rollback window; documentation
changes alone do not migrate them.

## Validation

A checkout, image build or fake-provider unit test is preparation. Completion
requires actual business-scoped Echo and voice workflows, including Android live
transcripts, takeover, failed-transfer recovery, deterministic fallback and
tested data preservation. See the implementation sequence for the gates.

This repository is documentation and automation, not a long-running service.
