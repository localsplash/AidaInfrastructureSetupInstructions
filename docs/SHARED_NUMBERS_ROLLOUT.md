# Shared tenant numbers and call-store rollout

Identity owns users, organizations/tenants, memberships, sessions, and the canonical phone-number registry in `platform_db`. AidaAdmin manages that registry under each tenant’s **Numbers** page. Echo reads it through Identity session introspection. Every number supports voice and messaging and explicitly grants access to all enabled tenant members. Regular USER members can use Echo; only Tenant Admins and Super Admins can use AidaAdmin. Super Admins see all tenants.

A DID route references the same immutable E.164 number. Routing details stay in NocoDB, while message/media history stays in `echo_db`. Legacy Echo user/organization mapping tables retain history and provenance; they are no longer a separate authorization source. Multiple numbers per tenant are supported. Number/tenant reassignment is not supported because it could expose historical conversations to a different business. Current Echo storage supports +1 ten-digit numbers.

## Existing installation

1. Back up Identity, Echo and call databases, configuration, and media. Preserve provider identities and existing SSO sessions. Compare source and consolidated Echo history before redirecting traffic.
2. Deploy Identity with additive migration `0005_shared_phone_numbers`. Existing applications can ignore the added `numbers` session field.
3. Review each existing tenant-number assignment. Use Identity’s `IMPORT_ACTOR_USER_ID=... PLATFORM_DB_URL=... node scripts/import-phone-numbers.mjs manifest.json` to dry-run the import, then append `--apply`. Manifest entries contain `iTenantId`, `phoneNumber` (E.164), and `label`. Conflicting ownership aborts; existing rows are preserved. Do not infer ownership from matching numeric IDs or carrier inventory alone.
4. Deploy AidaAdmin and EchoWeb together. Echo now requires the new session field. No-number accounts can sign in and see a message to contact their Tenant Admin. Adding a number does not provision a carrier or PBX route. Disabling the registry record revokes Echo access on the next request; disable an existing PBX DID route separately.
5. Point the natural Echo development URL to `echo-web-local`. Verify both NPM’s saved upstream and its generated nginx configuration, then test nginx before reload. Keep application cookies host-only; the Identity SSO redirect supplies the shared login.
6. Verify existing Super Admin and Tenant Admin login through AidaAdmin and then Echo, ordinary USER access, no-number warnings, tenant isolation, DID number selection, and preserved message/media history. Local tests do not replace real carrier/PBX call and messaging validation.

## `aidacalls_db`

OfficePulseAidaIntegration owns and writes `aidacalls_db`; AidaAdmin currently reads it with SELECT-only credentials. `aida_admin_db` remains separate application state. Ideally place Integration and its calls database beside Asterisk on a private network, with AidaAdmin able to reach the read-only database endpoint. Keeping them on the central development host is supported. Asterisk/vendor schema is unchanged.

MySQL cannot rename a database in place. Stop Integration and Admin during the switch; dump the old `aida_db` consistently with routines/triggers, create `aidacalls_db`, restore it, and verify all tables, rows and the migration ledger. Grant the runtime account its previous DDL/DML rights on the new database and the Admin reader SELECT only. Update `RUNTIME_MYSQL_DATABASE`, `OFFICEPULSE_RUNTIME_DATABASE_URL`, and any scoped PlatformConfig values or nonblank environment overrides. Restart and check health/readiness/runtime diagnostics. Retain the old database and backup for recovery; do not run two runtime writers. For rollback, stop writers first and reconcile any new runtime records before restoring the old configuration.

Released baseline SQL files retain historical names/checksums; the migration runner targets the configured database. Fresh deployment defaults and grants use `aidacalls_db`.

## Local verification on 2026-09-07

The three reviewed existing tenant assignments were imported, and every preserved Echo message/media/draft/user/session row matched the source copy. Identity’s MySQL suite passed (181 tests). Browser checks passed for the existing Super Admin and Dave’s Tenant Admin: AidaAdmin → Echo reused Identity SSO without another sign-in; Wisp’s Tenant Admin saw only Wisp’s number. NPM’s saved Echo target and generated file were reconciled. The local calls database was copied byte-for-byte at the row-dump level to `aidacalls_db`; `aida_db` was retained.

Carrier delivery remains blocked in the local Echo services, OfficePulse voice is disabled pending PBX configuration, and the Agent remains in status-only mode. These checks validate platform login/configuration and data preservation, not a completed live call or SMS.
