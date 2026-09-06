# Platform Data Standard

Status: agreed design and first implementation wave for the Echo/Aida office platform, 2026-09-06. See [actual PR/build status](LOCAL_DEV_READINESS.md); unimplemented target requirements below remain acceptance work. Read with [the master plan](PLATFORM_MASTER_PLAN.md). This supersedes conflicting storage/ownership recommendations in the older Aida documents for the POC. It does not mandate changes to unrelated LocalSplash applications or upstream vendor products on the same host.

## 1. Ownership and stores

| Store | Contents | Schema authority |
| --- | --- | --- |
| MySQL `platform_db` | Users, identities, Identity SSO/application sessions and handoff codes, tenants, membership, Identity registry/events/delivery | identity |
| MySQL `echo_db` | Messaging, carriers, canonical-ID projections | EchoDatabase; named Echo services receive domain-specific runtime grants |
| MySQL `aida_db` | Call sessions/events/commands, device sessions, voice provisioning runtime | OfficePulseAidaIntegration for the POC |
| MySQL `aida_admin_db` | AidaAdmin OAuth state, event processing and operation audit | AidaAdmin |
| NocoDB base `PlatformConfig` | Deployment settings and slow-changing application desired configuration | identity creates base/settings schema; each owning app migrates its own tables |
| Upstream Asterisk stores | Vendor realtime, dialplan, CDR/CEL and SIP authentication | Upstream Asterisk/OfficePulse; no platform-owned vendor schema migrations |

One DDL owner per database does not mean only one process may write any row. EchoDatabase is a migration repository, not a message-processing API. EchoWeb and EchoService retain explicitly bounded runtime write responsibilities. This distinction must be present in grants and ownership documentation.

Central tenant membership is never independently writable in Echo or Aida. Application databases may keep mappings, bounded caches and historical snapshots, identified as such. They contain no second authoritative provider identity or global role directory.

NocoDB's own metadata/backing database and system columns are vendor data. Back them up with the platform configuration. Their engine/names are not an excuse to rewrite vendor schemas or unrelated PostgreSQL services on this host.

## 2. Configuration contract

### 2.1 Bootstrap versus settings

For application servers that directly read NocoDB, the normal operator-supplied settings-store bootstrap consists of:

```
NOCODB_BASE_URL
NOCODB_API_TOKEN
```

This is not an absolute ban on every other environment variable. The deployment layer must also declare container ports, volume paths, runtime mode and infrastructure bootstrap. MySQL/NocoDB, reverse proxy, PBX and SDK-managed workers cannot universally discover their own startup prerequisites from a store that has not started. Approved environment overrides and operator-rendered secret files are supported.

Keep deployment topology in the versioned release manifest/Compose. Initialize infrastructure credentials outside the application store, start NocoDB, create `PlatformConfig`, populate application settings and only then start dependent applications. Persist generated store credentials once; never generate a new password merely because an existing volume is being reused. Runtime application passwords can be stored in `cfg_tbl_Setting`, while infrastructure retains the credentials needed to initialize/restore itself.

The Android app and browsers never receive NocoDB tokens, DB passwords, LiveKit API secrets or provider credentials. AidaAgent obtains allowlisted call context through the runtime's server-authenticated LiveKit dispatch metadata, bound to the call/room. It does not query platform stores. Worker process/provider secrets may be rendered from the operator-owned settings into the worker's private startup environment, with explicit restart semantics. OfficePulse reads the settings/configuration it needs as the merged POC runtime; a future separate PBX adapter would receive a restricted configuration projection.

### 2.2 Table shape and resolution

`cfg_tbl_Setting` has application-owned fields `app`, `settingKey`, `settingValue`, `description`, `bSecret`, `dtCreated`, `dtUpdated`, plus vendor-required NocoDB columns. Enforce uniqueness of `(app, settingKey)` in the supported backing store/schema, or reject duplicates deterministically if the selected NocoDB setup cannot provide that constraint. Do not implement silent last-row-wins behavior.

Resolution is: nonblank environment override, exact application scope, declared shared parent scope if any, then global `*`; otherwise unset. Blank seeded rows count as unset. Disabling a feature requires its documented enabled/disabled setting rather than treating an empty secret row as a special override.

| Application | Exact scope | Explicit shared parent |
| --- | --- | --- |
| identity | `identity` | none |
| EchoWeb | `echo-web` | `echo` |
| EchoService | `echo-service` | `echo` |
| EchoMedia | `echo-media` | `echo` |
| AidaAdmin | `aida-admin` | `aida` |
| OfficePulseAidaIntegration | `officepulse` | `aida` |

This parent map is fixed by the contract, not guessed by splitting names. Global `*` includes `PARENT_DOMAIN` and `trustedCIDR`; per-service database names/passwords and privileged provider keys must not be casually promoted to the global scope. Shared scopes contain only values intentionally shared by those consumers. Separate service DB users should normally use exact service scopes.

An environment override is shown as read-only in the owning admin UI and is never copied into the store. Public APIs mask secret values. `bSecret` is metadata for handling/display, not encryption or access control. Distinct NocoDB tokens do not by themselves establish row-level isolation inside one settings table. Verify the deployed NocoDB edition/token permissions; only controlled first-party server processes and platform operators may access this base. Business users and TENANT_ADMIN work through application APIs that enforce their authority.

Legacy Identity settings currently use API fields `Key`, `Value`, `Description` (and underlying column names that differ). Legacy Echo SQL uses its own scope/key/value schema. The migration maps names and scopes explicitly; renaming a base/table alone is insufficient.

### 2.3 Discovery, refresh and failure

Resolve the base by the unique configured convention `PlatformConfig`, then resolve the expected table. Identity settings and metadata use a 30-second refresh. The first Admin/OfficePulse implementation loads connection/provider settings at startup; those changes require restart. Desired voice configuration is read per operation, with runtime metadata IDs refreshed after 30 seconds. A future hot-settings feature must declare which clients/pools it can replace safely. Duplicate matching bases/tables/keys are errors. Invalidate after writes and failed reads; a failed refresh does not advance the cache timestamp or silently preserve an apparently healthy cache.

Initialize missing objects only in an explicit bootstrap/migration phase. Ordinary runtime reads must not silently create a new empty base because the configured base was renamed or lost.

At application startup, a configuration read failure retries once after five seconds, then reports an actionable error and fails readiness; whether the process exits or remains in setup mode is an explicit per-service bootstrap policy. A running process exposes configuration-independent `/healthz` and a dependency-aware readiness endpoint. Requests that require fresh unavailable configuration fail explicitly. Database connection changes require a restart unless a safe pool-replacement implementation is present.

An admitted call uses a validated, versioned configuration snapshot for its lifetime. No setting refresh may overwrite the resolved tenant or route of an active call. Local Asterisk fallback must survive loss of NocoDB, the runtime process and cloud connectivity where the configured fallback is local. Distinguish this call continuity rule from fallback to arbitrary default configuration.

## 3. Identity and tenant contract

`identity_tbl_User.iUserId` and `identity_tbl_Tenant.iTenantId` identify central people and businesses. Tenant memberships link these keys and carry tenant roles and enablement. Recommended POC schema uses non-null `iTenantId` for memberships and tenant roles `TENANT_ADMIN`/`USER`; global SUPER ADMIN remains Identity session authority under its existing provenance rule. A later explicit global-grant table/API is a distinct feature.

The proposed `UNIQUE(iTenantId, iUserId)` on a nullable tenant column does not prevent repeated global-grant rows: MySQL permits multiple NULL values in a unique index. Do not rely on it for global-role uniqueness. If a future contract retains nullable global-role rows, add a separately enforceable uniqueness/check design and tests. [MySQL unique index behavior](https://dev.mysql.com/doc/refman/8.4/en/create-index.html).

Identity owns tenant create/update/disable and membership APIs. AidaAdmin validates the current actor's tenant administration permission before invoking server-only directory writes. CIDR trust admits a server; it does not prove which office user is acting. A claimed tenant ID or role in a browser request is not authority. SUPER ADMIN can inspect every business, but every mutation records the actor and the target business.

The implemented Identity v2 tenant endpoint creates by unique slug and returns 409 for duplicates; it is not an ensure/idempotency endpoint. Consumers list and select the existing tenant explicitly. User-directory idempotency retains its existing keys and rejects changed intent. The existing `identity_tbl_DirectoryKey` has a mandatory user FK and must not be reused for future tenant idempotency without an additive redesign.

Do not silently change the existing `/api/token` wire types or `superAdmin` calculation while renaming database columns. Numeric IDs accepted by JavaScript clients must be safe integers; any future decimal-string representation requires an explicit versioned contract change. Session tokens retain their existing entropy and width even if their columns are renamed. A `uid` prefix does not justify converting an existing 64-character session credential to UUIDv4.

## 4. Cross-store integrity and events

No platform-owned foreign key crosses a database boundary, even when both databases share one MySQL server. Cross-store IDs are values validated through the owning API and maintained through events/reconciliation. Same-database foreign keys and uniqueness constraints remain useful.

| Event / change | Required effect |
| --- | --- |
| `session.revoked` | Revoke corresponding application/device authorization under the agreed scope |
| `user.merged` | Repoint application mappings safely, reconcile conflicts and revoke retired-user sessions |
| `tenant.disabled` | Deny normal tenant service and new work; apply a documented active-call policy |
| Membership disabled or role changed | Invalidate authorization for existing sessions; specify a durable event or bounded online check |
| `tenant.merged` | Reserved until conflict/reconciliation behavior is implemented across all consumers; no partial POC merge UI |

For tenant/membership authorization, the implemented POC uses fresh online Identity session/tenant checks; no tenant/membership event feed or cached authorization fallback is implemented. Existing Identity user events retain their supported consumer flow. Where durable events are used, the producer writes its authoritative change and event/outbox in one database transaction. Consumers durably apply effects and record deduplication/cursor state atomically before returning 2xx. Retry/catch-up must tolerate duplicates and ordering changes. Only advance the ordered catch-up cursor over the stream actually read and handled; receiving a later webhook cannot skip earlier unseen changes. Boot catch-up follows all pages, and reconciliation is available for abandoned deliveries.

For calls, `UNIQUE(uidCallSession, iSequenceNumber)` only prevents duplicates; it does not allocate an ordered gap-free sequence. Allocate the next sequence under a call-row lock or equivalent transaction, then persist state/event/outbox together. Command claiming must be idempotent and compare `expectedCallVersion` before side effects. Provider operations are not part of the SQL transaction, so persist intent/results and reconcile interrupted work instead of claiming exactly-once network effects.

Live transcripts have a separate producer/connection sequence and event IDs. They are transient for this POC. A handset marks a lost transcript segment and resumes; durable call-event replay cannot reconstruct unpersisted transcript text.

## 5. Naming and schema migration

Use MySQL 8 for new platform-owned SQL stores; pin an exact supported release/digest per platform release. Use lowercase database names and `<domain>_tbl_<PascalSingular>` for new tables. New columns use `i` for numeric IDs/integers, `uid` for opaque app identifiers, `dt` for timestamps, `b` for booleans, `j` for JSON, `n` for decimals, and no prefix for ordinary strings. New mutable rows have creation/update timestamps as appropriate. Use UUIDs for newly minted call/command/device-visible opaque IDs where the contract calls for them; preserve stable legacy identifiers.

These conventions do not require rewriting existing Echo `sms_tbl_*`/`auth_tbl_*` names or vendor tables to reach the POC. Enumerate deliberate compatibility exceptions. Do not rename JSON fields, headers or existing tokens as a side effect of database naming changes.

Each schema owner supplies ordered, append-only named migrations and a history ledger. New ledger names follow `<prefix>_tbl_SchemaMigration`. Existing histories are adopted explicitly with compatibility for any deployed old reader. Never edit a released migration or mark unknown migrations as applied merely because one table exists. Validate expected schema fingerprints/checksums, serialize concurrent migration runners and keep each migration restartable after partial application.

An additive migration is not a universal rollback guarantee. New application writes may depend on new columns, constraints or meanings; DDL may commit separately from the migration ledger. For every release, record supported old/new reader/writer combinations and the recovery behavior for a failed intermediate step. [MySQL implicit commits](https://dev.mysql.com/doc/refman/8.4/en/implicit-commit.html).

Use expand, backfill, compatible reader/writer cutover, verify, then contract in a later release. Column alias migrations must dual-write or otherwise keep both active column versions coherent during the transition. Renaming the migration ledger in the same release without compatibility can cause old code to create a fresh ledger and replay history.

Creating `platform_db` and changing `DB_NAME` does not migrate the current Identity data. Use a rehearsed export/import or an explicitly qualified table move with all vendor restrictions checked, then restore grants and validate IDs/counts/constraints/routines before switching writers. Cross-database table moves have restrictions for triggers/views and require grant review. [MySQL RENAME TABLE](https://dev.mysql.com/doc/refman/8.4/en/rename-table.html).

Before live migration, take a consistent MySQL dump including routines and required triggers/events, an export/backup of NocoDB configuration and backing metadata, relevant media volumes, and a deployment secret/config backup. Restore the backups in isolation before relying on them. Cross-store migration requires a write freeze or resumable change-capture/reconciliation boundary; unrelated point-in-time dumps alone do not make a distributed snapshot.

The tenant conversion manifest is immutable provenance: source system, source tenant/user ID, target central ID, status and verification result. Backfill references without destroying source data. Archive source tables only after every dependent reader/writer and active session has crossed the release boundary. Restoring a pre-deploy dump may lose later writes; state that recovery point explicitly.

## 6. Asterisk, provisioning and media

Asterisk's schema and database naming are upstream-owned. OfficePulse may provision approved realtime rows and deployment include files, generated contexts and prompts. Its migrations target its own runtime database only. Generated records have stable ownership markers and tenant-safe namespaces; reconciliation does not delete unrelated upstream records.

The existing OfficePulse runtime database is conventionally `aida_officepulse`. Its current provisioning implementation also uses owned companion tables `aida_object`, `aida_device`, and `aida_provisioning_request` beside vendor realtime tables. Adopt/relocate only those owned records into the integration-owned target, preserving endpoint IDs, legacy tenant mappings and provisioning idempotency history. Do not run the current companion-table `deploy/sql/schema.sql` against the PBX as though it were the new platform migration plan. Keep supported provisioning writes to vendor tables through the adapter, with explicit cross-store reconciliation after relocation.

SIP authentication secrets persist only in the approved Asterisk authentication store. On creation/rotation, deliver the secret once through the authenticated provisioning channel; never place it in NocoDB, runtime snapshots, admin audit, logs or source. Record provisioning status and reference IDs separately. The adapter must not offer readback of previously stored SIP secrets.

Normalize telephone numbers at API boundaries to an explicit canonical format while retaining legacy Echo storage/IDs through adapters. Number reassignment must not transfer historical conversations, recordings or message access to a new tenant. Routing ownership, historical ownership and service enablement are separate facts.

User-facing media access checks business ownership. Provider media retrieval uses a deliberately narrow mechanism compatible with carrier callbacks/fetches. Disk paths, public URL configuration and signed/capability access are part of the release contract. Do not make internal recordings or all attachments globally readable merely because file names are hard to guess.

## 7. Configuration migration release sequence

1. Export/restore-rehearse the legacy settings and record every current reader/writer, including local changes outside GitHub main.
2. Deploy compatibility readers for Identity and Echo before renaming `IdentityBase` or `auth_tbl_Settings`. Keep the existing working credential and shared-file path until replacements are exercised.
3. Add/map setting columns and scopes, create `PlatformConfig` deliberately, reconcile duplicates and copy existing values without logging secrets. During transition, select one authoritative write path and synchronize any required legacy view explicitly.
4. Switch readers and admin writes to `cfg_tbl_Setting`; verify login, directory calls, inbound/outbound SMS/MMS, media and voice configuration under actual private/proxy networking.
5. Only then reduce app environment/bootstrap volume dependencies. Keep the host/store secrets required to start and restore MySQL/NocoDB. Remove legacy settings/table/column access in a later release after usage evidence confirms retirement.

No part of this standard authorizes a blind in-place database rename, removal of a working Docker volume, or deletion of historical tenant mappings. Migration evidence, not a string-search result, determines whether a compatibility path can be retired.
