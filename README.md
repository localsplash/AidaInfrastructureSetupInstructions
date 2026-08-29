# AidaInfrastructureSetupInstructions

Be the operator single source for setup, deployment, validation, backup, upgrade, and rollback.

## Responsibilities

- Maintain the canonical system specification
- Inventory every URL, API key, secret, DNS, TLS, firewall, and identity setting
- Orchestrate released images with Docker Compose
- Run Postgres migrations and NocoDB initialization
- Install OfficePulse assets and configure/test the signed LiveKit webhook

## Stack

Markdown, PowerShell/shell automation, Docker Compose, GitHub Actions

## System specification

[Canonical Aida Voice Platform specification](https://github.com/localsplash/AidaInfrastructureSetupInstructions/blob/main/docs/AIDA_VOICE_PLATFORM_TECHNICAL_SPECIFICATION.md)

[Normative POC database and input-interface specification](https://github.com/localsplash/AidaInfrastructureSetupInstructions/blob/main/docs/AIDA_POC_DATABASE_AND_INTERFACE_SPECIFICATION.md)

[Dependency-ordered POC repository build sequence](https://github.com/localsplash/AidaInfrastructureSetupInstructions/blob/main/docs/POC_REPOSITORY_BUILD_SEQUENCE.md)

## Project invariant

This is documentation and automation, not a long-running application service.
