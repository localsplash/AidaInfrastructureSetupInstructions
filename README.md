# AidaInfrastructureSetupInstructions

Be the operator single source for setup, deployment, validation, backup, upgrade, and rollback.

## Responsibilities

- Maintain the canonical system specification
- Inventory every URL, API key, secret, DNS, TLS, firewall, and identity setting
- Orchestrate released images with Docker Compose
- Run Postgres migrations and NocoDB initialization
- Install HostedPulse assets and configure/test the signed LiveKit webhook

## Stack

Markdown, PowerShell/shell automation, Docker Compose, GitHub Actions

## System specification

[Canonical Aida Voice Platform specification](https://github.com/localsplash/AidaInfrastructureSetupInstructions/blob/main/docs/AIDA_VOICE_PLATFORM_TECHNICAL_SPECIFICATION.md)

## Project invariant

This is documentation and automation, not a long-running application service.
