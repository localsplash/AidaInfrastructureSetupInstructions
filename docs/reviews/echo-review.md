# Echo consolidation review

Reviewed 2026-09-06. Read-only review of the five requested Echo issues, the actual EchoDatabase PR #3, local source under `/opt/echo`, and selected GitHub default-branch source. No repository, database, service, or GitHub mutation was performed. The user-provided second PR link points to AidaInfrastructureSetupInstructions #16; the actual [EchoDatabase PR #3](https://github.com/localsplash/EchoDatabase/pull/3) exists and is open.

## Executive recommendation

Reuse the working Echo runtime. Its messaging/webhook/media workflows already exist. Consolidate shared identity, tenant identifiers, configuration, and deployment contracts around it; a messaging rewrite would add unnecessary POC risk. Keep EchoDatabase responsible for Echo schema migrations, but remove its ownership of identity/NocoDB bootstrap. Make one deployment repository authoritative for shared Compose services, networks, volumes, hostnames, and release versions; EchoOrchestrator is the practical starting point because it already runs the working stack. AidaInfrastructureSetupInstructions should become the design/runbook companion, not a second independently maintained installer.

The requested issues describe settings consolidation, but do not yet implement a unified tenant/security model for Echo. The current merge sequence also contains immediate outage paths. Resolve those before treating the issues as an executable release plan.

## What exists today

| Repository | Local branch / commit | Observed role and current state |
|---|---|---|
| EchoOrchestrator | `feat/echo-service-log-volume` / `75ba414` | Compose for MySQL 8.4, one-shot migrations, EchoService, EchoWeb, EchoMedia; media/log volumes; shared identity bootstrap volume; environment overlays. Local worktree was clean. |
| EchoDatabase | `main` / `552b236` | `echo_db`; `sms_*` messaging/carrier/media tables and procedures; `auth_*` Echo user/org/member/session projections; `echo_tbl_Settings`; SQL init files through 011. Local worktree was clean. |
| EchoWeb | `main` / `3855a60` | Express/TypeScript BFF and UI; brokers login through identity; owns local user/provider/org/session records; injects current business number when calling EchoService. Local worktree was clean. |
| EchoService | `main` / `8d292e7` | Express/JavaScript messaging API, carrier hooks, attachments, operator/log pages, network policy. Local worktree was clean. |
| EchoMedia | `main` / `20c358c` | Small Express static-file server; shared media volume mounted read-only. No database or NocoDB reader. Local worktree was clean. |

These are source observations, not a claim that running containers use exactly these images or that every advertised workflow has been exercised. EchoOrchestrator uses `master` on GitHub; the other checked defaults use `main`. Git blob hashes matched between local files and fetched defaults for Orchestrator Compose/migration script, EchoDatabase settings SQL, EchoMedia server, EchoService server, and EchoWeb auth helpers. EchoWeb `src/settings.ts` and `src/app.ts` differ from fetched default only in explanatory comments; their reviewed executable behavior is the same. This is a targeted comparison, not a claim of whole-repository equality.

Sources: [Compose](https://github.com/localsplash/EchoOrchestrator/blob/master/docker-compose.yml), [Echo schema](https://github.com/localsplash/EchoDatabase/blob/main/init/001_schema.sql), [Echo auth schema](https://github.com/localsplash/EchoDatabase/blob/main/init/005_auth.sql), [EchoWeb login flow](https://github.com/localsplash/EchoWeb/blob/main/src/app.ts#L429), [EchoService](https://github.com/localsplash/EchoService/blob/main/src/server.js), [EchoMedia](https://github.com/localsplash/EchoMedia/blob/main/src/server.js).

## Corrections required in the active plan

### 1. The identity-first settings rename breaks existing Echo readers

[identity #16](https://github.com/localsplash/identity/issues/16) renames `IdentityBase` to `PlatformConfig` and `auth_tbl_Settings` to `cfg_tbl_Setting`, with compatibility code specified for identity. Current EchoWeb and EchoService both discover the exact legacy base/table names. EchoWeb needs `PARENT_DOMAIN` and `IDENTITY_CLIENT_SECRET`; EchoService needs `trustedCIDR`. Keeping the shared `/data/config.json` volume alive does not preserve those old names. EchoWeb refreshes configuration per request after its 30-second cache expires, so a rename can break the live messaging UI before the later Echo PRs land.

Deploy compatibility readers in every consumer before either rename, or create the new config structure additively and preserve the legacy structure during the bounded transition. Avoid uncoordinated dual writers. Verify all old consumers have moved before removing the legacy structure.

Sources: [EchoWeb settings](https://github.com/localsplash/EchoWeb/blob/main/src/settings.ts), [EchoWeb config refresh](https://github.com/localsplash/EchoWeb/blob/main/src/config.ts), [EchoService settings](https://github.com/localsplash/EchoService/blob/main/src/settings.js).

### 2. Compose cannot remove database variables before applications learn the new bootstrap order

[EchoOrchestrator #11](https://github.com/localsplash/EchoOrchestrator/issues/11) removes application `DB_*` environment values, but the listed sequence places it before [EchoWeb #21](https://github.com/localsplash/EchoWeb/issues/21) and [EchoService #10](https://github.com/localsplash/EchoService/issues/10). Both current applications construct their MySQL pools from those environment variables. EchoWeb constructs its pool before its first settings read. New boot order must be NocoDB coordinates → resolve and validate PlatformConfig → create MySQL pool → verify migrations → enable application routes.

Ship compatible application readers first and reduce Compose environment afterwards, or deploy application images and matching Compose changes as one pinned release. A standalone configuration-only Compose deploy is unsafe. If database coordinates change at runtime, the memoized pools also need an explicit reconnect/restart contract; a 30-second settings cache alone does not reconnect MySQL.

Sources: [EchoWeb startup](https://github.com/localsplash/EchoWeb/blob/main/src/server.ts), [EchoWeb pool](https://github.com/localsplash/EchoWeb/blob/main/src/db.ts), [EchoService pool configuration](https://github.com/localsplash/EchoService/blob/main/src/server.js#L76).

### 3. Settings scopes have two incompatible definitions

Current `echo_tbl_Settings` uses `sApp` values `*`, `web`, `service`, and `media`, with nonblank service rows overriding general rows. The new issues describe `echo-web`, `echo-service`, and `echo-media` as if these were existing scopes. Migrate them explicitly; do not copy names unchanged.

There is also a new grouping mismatch: Orchestrator #11 puts `DB_*` under `app='echo'`, but identity #16 defines only caller's exact app → `*` → unset. An `echo-web` reader following that contract cannot see `echo` rows. Choose one documented resolution rule. For the existing proposal, use explicit service → family → platform resolution (`echo-web` → `echo` → `*`, similarly for EchoService), then environment overrides where deliberately supported. Alternatively duplicate the small DB coordinate set into exact service scopes. Do not silently invent scope inheritance in individual readers.

Migration mapping:

| Legacy source | New source | Notes |
|---|---|---|
| Echo `sApp='*'` | `app='echo'` | Echo-common values must not become platform-wide simply because the old table called them `*`. |
| Echo `sApp='web'` | `app='echo-web'` | Remove stale provider OAuth settings after confirming no live consumers. |
| Echo `sApp='service'` | `app='echo-service'` | Carrier fallback credentials and webhook settings stay backend-only. |
| Echo `sApp='media'` | `app='echo-media'` | No existing reader; only move meaningful new settings. |
| Identity `trustedCIDR`, `PARENT_DOMAIN` | `app='*'` | Platform-owned. |
| Identity `IDENTITY_CLIENT_SECRET` | Explicit authorized client scope | identity #16 otherwise moves it under `identity`, making it invisible to the EchoWeb reader. Prefer a client credential belonging to EchoWeb. |
| Compose application `DB_*` | Explicit Echo family/service scope | Read before constructing a DB pool. Database-container bootstrap credentials remain outside the store. |

Freeze canonical column names as part of this contract: current Echo uses `sApp/sKey/sValue`, current NocoDB readers expect `Key/Value`, and the issue introduces `app/settingKey/bSecret`. Document value-column migration too. Preserve blank-as-unset semantics and enforce `(app, settingKey)` uniqueness. `bSecret` is a classification flag, not access control; a shared table/API token must not unintentionally grant every app every provider credential.

Sources: [legacy schema/scopes](https://github.com/localsplash/EchoDatabase/blob/main/init/009_settings.sql), [EchoWeb reader](https://github.com/localsplash/EchoWeb/blob/main/src/settings.ts), [identity #16](https://github.com/localsplash/identity/issues/16), [Orchestrator #11](https://github.com/localsplash/EchoOrchestrator/issues/11).

### 4. “Preserve no fallback” is not an accurate description of the running design

EchoWeb and EchoService already support nonblank environment overrides for selected runtime settings. EchoService also supports an environment-pinned trusted network. It intentionally retains its last trusted-CIDR value on a transient settings read failure, and its `networkPolicy` layer loads policy once until an operator reloads it. With no known policy it denies gated requests while preserving diagnostic/setup access; it can start in setup mode if NocoDB coordinates are missing. That behavior differs from the blanket fail/exit rule in the issues.

Explicitly define separate behavior for initial required configuration, ordinary mutable settings, and authorization policy. Preserve known intended availability behavior until it is deliberately replaced; do not accidentally make a NocoDB outage kill the messaging API by calling that “unchanged.” A failed new policy must never widen access. Distinguish environment overrides from fallback to another database/source.

Sources: [EchoService retained CIDR](https://github.com/localsplash/EchoService/blob/main/src/settings.js#L200), [held network policy](https://github.com/localsplash/EchoService/blob/main/src/networkPolicy.js), [EchoService setup startup](https://github.com/localsplash/EchoService/blob/main/src/server.js#L1467), [EchoWeb overrides](https://github.com/localsplash/EchoWeb/blob/main/src/config.ts).

### 5. EchoMedia #1 should be narrowed instead of creating a needless dependency

EchoMedia has only `PORT` and `MEDIA_ROOT`, read from environment, and no settings/table/cache/startup retry implementation. [EchoMedia #1](https://github.com/localsplash/EchoMedia/issues/1) cannot literally replace its existing settings reader. For the fastest POC, retain its fixed deployment mount/port and verify that it has no dependency on the retiring table. Add PlatformConfig only for an actual need such as media authorization settings. Removing a UID pin also requires checking ownership of existing writable media/log volumes; the old pin may now matter beyond the shared identity file.

Source: [entire media server](https://github.com/localsplash/EchoMedia/blob/main/src/server.js), [Compose media mount](https://github.com/localsplash/EchoOrchestrator/blob/master/docker-compose.yml).

### 6. Preserve database bootstrap and validate the migration ledger

Removing application database secrets from `.env` does not remove the MySQL container/migration job's need for bootstrap credentials. A fresh install still needs generated or operator-supplied `MYSQL_*` secrets and a functioning NocoDB metadata store before any application can fetch configuration. NocoDB cannot bootstrap its own metadata/database credentials from itself. Existing MySQL volume passwords must be preserved; changing environment values does not rotate existing database users.

The current migration runner is useful but has limitations that matter during consolidation:

- It only runs `*.sql`, so the `.sh` bootstrap step in stale PR #3 would not run on an existing volume.
- When a database contains `sms_tbl_Message` but has no ledger, it records every present file as applied without verifying the schema. An unapplied historical migration can therefore be marked successful.
- It records filenames without checksums; edited historical files are not replayed or detected.
- SQL files explicitly `USE echo_db`. Setting `MYSQL_DATABASE=platform_db` cannot migrate Echo tables there and can cause schema/ledger placement to disagree.
- MySQL DDL implicitly commits, and a failed file may be partially applied; restoring a dump is not equivalent to an atomic SQL rollback.

Keep `echo_tbl_SchemaMigration`, inspect the actual schema/routines against its entries before migration, add new migrations only, and make release migration preconditions explicit. Do not move or rename Echo's entire database simply to unify branding; a shared physical MySQL instance can host independently owned logical schemas. Shared identity/tenant tables in `platform_db` do not require SMS stored procedures to be rewritten for the POC.

Sources: [runner](https://github.com/localsplash/EchoOrchestrator/blob/master/scripts/migrate.sh), [bootstrap installer](https://github.com/localsplash/EchoOrchestrator/blob/master/scripts/install.sh), [SQL schema](https://github.com/localsplash/EchoDatabase/blob/main/init/001_schema.sql), [EchoDatabase #8 backup/sequencing requirements](https://github.com/localsplash/EchoDatabase/issues/8).

## EchoDatabase PR #3 disposition

Do not merge it as written. [The actual PR](https://github.com/localsplash/EchoDatabase/pull/3) is open, based on an older identity split and the old `localsplash/id` project. It creates `id_db` and `nocodb_db`, grants both to the Echo application user, duplicates identity schema/boot ownership, and drops Echo `auth_tbl_Identity` and `auth_tbl_SsoNonce`. Current EchoWeb still calls `auth_tbl_Identity` on sign-in and account-management paths, so that drop breaks current code. Its nullable/nonexpiring session design also differs from current EchoWeb queries, which require `dtExpires > NOW(3)`.

Replace the PR with small new migrations against the accepted design. Salvage the idea of explicit identity-user mapping and a durable event cursor if needed, but let identity own its schema and event contract. Do not copy the proposed `id_tbl_*` SQL into EchoDatabase. Retain historical migrations and data until their deployed consumers have moved. The user authorized correction/trashing conceptually, but this review made no external PR changes.

Sources: [PR #3](https://github.com/localsplash/EchoDatabase/pull/3), [current Echo session query](https://github.com/localsplash/EchoWeb/blob/main/src/auth.ts#L90), [current identity projection calls](https://github.com/localsplash/EchoWeb/blob/main/src/app.ts#L294).

## Missing work for a unified business platform

### Canonical identity and tenant mapping

Echo already delegates login via `/authorize` and `/api/token`; do not rebuild working SSO. However the returned canonical `user.iUserId` is not used as Echo's projection key. The callback extracts provider/subject/email and performs Echo-local user/org/member provisioning. Echo sessions retain their own role and business number; there is no identity event/revocation consumer in the reviewed current source. Identity consolidation must add canonical user and tenant mapping plus synchronization of disabled/merged users and tenants, memberships, and session revocation. Do not merge people solely because email strings or old integer IDs match.

POC bridge: retain Echo org IDs for historical rows, add a unique canonical tenant reference to each org, add a canonical identity user reference to each local user, and backfill through verified provider/UISP links. Use an explicit mapping report for ambiguous accounts; never assume Echo org ID equals platform tenant ID. Identity owns membership/tenant enablement; Echo retains messaging-specific assignments and caches/projections.

Sources: [EchoWeb token claim](https://github.com/localsplash/EchoWeb/blob/main/src/auth.ts#L835), [callback ignoring canonical user ID](https://github.com/localsplash/EchoWeb/blob/main/src/app.ts#L496), [local org/member schema](https://github.com/localsplash/EchoDatabase/blob/main/init/005_auth.sql).

### Phone number ownership must be modeled independently of the phone number

Echo currently authorizes many messaging requests using a business number cached in the session. `sms_tbl_BusinessPhone` has a number primary key and carrier-application link, but no canonical tenant ID; `auth_tbl_Org` stores one optional business number. The broader platform should model tenant → assigned numbers, with a canonical string E.164 number and clear voice/messaging capabilities. Preserve current US number behavior with a boundary adapter for the POC: despite schema comments saying E.164, EchoService normalizes numbers to the last 10 US digits and outbound formatting adds `+1`. Do not silently import those numeric values as full international E.164 identifiers.

When numbers can be reassigned, storing only the current number→tenant association can accidentally transfer historical conversations. Capture tenant ownership on the historical record or define an immutable assignment link/effective-time migration. A POC can limit number reassignment until this rule is implemented, but the master design must specify it.

Sources: [business phone schema](https://github.com/localsplash/EchoDatabase/blob/main/init/003_carrier.sql), [message schema](https://github.com/localsplash/EchoDatabase/blob/main/init/001_schema.sql), [US normalization](https://github.com/localsplash/EchoService/blob/main/src/server.js#L177).

### Concrete authorization gaps relevant to shared tenancy

Current EchoWeb's `proxyDirect` allows any session with a business number, or a super-admin, to reach carrier settings APIs. `/api/carrier-applications` list/read/create/update routes all use it. EchoService's matching endpoints do not accept/check a tenant or caller role, and the stored procedure returns all carrier rows including `jsonSettings`, which holds provider credentials. The trusted internal network gate does not supply end-user authorization. For POC, make carrier-application administration platform-admin-only and redact secret responses; grant business users access only to assigned nonsecret phone/config data. Add tenant ownership if customers will own their carrier applications.

EchoMedia is expressly public with wildcard CORS and day-long public cache headers. That may serve carrier-fetchable MMS URLs, but it is not suitable as the default privacy boundary for office message attachments, recordings, or transcripts. Define separate authenticated employee media access and limited signed carrier-fetch URLs before sharing tenants or voice recordings on this service. CORS is not access control.

These findings are established from code, not by making unauthorized live requests.

Sources: [EchoWeb broad proxy gate](https://github.com/localsplash/EchoWeb/blob/main/src/app.ts#L62), [carrier routes](https://github.com/localsplash/EchoWeb/blob/main/src/app.ts#L1017), [EchoService carrier endpoints](https://github.com/localsplash/EchoService/blob/main/src/server.js#L1026), [carrier procedure with jsonSettings](https://github.com/localsplash/EchoDatabase/blob/main/init/003_carrier.sql), [public media delivery](https://github.com/localsplash/EchoMedia/blob/main/src/server.js#L11).

### White-label configuration is partly implemented, partly overridden

EchoWeb derives `echo.<parent>`, `media-echo.<parent>`, and `identity.<parent>` from `PARENT_DOMAIN`, which is reusable. Existing dev/prod Compose overlays pin old `MEDIA_BASE_URL` domains; production examples and nginx files use `wisp.net`; EchoService's CORS allowlist explicitly trusts that domain. Replace these deployment-specific defaults with a single rendered hostname manifest for `localsplash.dev` and `localsplash.ai`. Keep hostname labels consistent across OAuth redirect registrations, browser URLs, carrier webhook URLs, media URLs, certificates, and Compose overlays. Internal URLs stay Docker DNS names and do not need public DNS round trips.

Sources: [domain derivation](https://github.com/localsplash/EchoWeb/blob/main/src/config.ts), [local dev overlay](/opt/echo/EchoOrchestrator/docker-compose.devserver.yml), [production overlay](https://github.com/localsplash/EchoOrchestrator/blob/master/docker-compose.prod.yml), [CORS domain logic](https://github.com/localsplash/EchoService/blob/main/src/server.js#L125).

## POC release order and acceptance evidence

1. Freeze a concise contract: canonical tenant/user IDs, settings columns and scope precedence, membership authority, bootstrap exceptions, hostname manifest, media access policy. Correct the issues and supersede PR #3 before implementation follows stale instructions.
2. Record baseline working Echo flows and deployment artifacts. Inspect schema/routine/ledger consistency; create the requested MySQL dump including routines, NocoDB export, and media backup; prove restoration into an isolated environment. Preserve existing volume names and passwords.
3. Deploy additive identity/PlatformConfig and reader compatibility without renaming anything consumed by old Echo. Establish separately provisioned app read access, seed/populate real values from legacy sources, compare resolved settings without logging secrets, and keep only one writer for each value during the transition.
4. Build/deploy new EchoWeb and EchoService bootstrap readers against the new store with valid values before removing DB variables/shared identity config. Verify setup/health diagnostics, required key failure, cache refresh, pagination, missing/ambiguous base/table, invalid token, and interrupted NocoDB connectivity. Treat pool coordinates as restart-required initially.
5. Add Echo canonical identity/tenant projections and minimal authorization restrictions while preserving all existing Echo records and access. The user requires several tenants immediately: demonstrate at least two ordinary tenants, denied cross-tenant reads/writes/media, and an explicitly authenticated SUPER_ADMIN who can view all tenants. Verify session revocation and tenant disable/merge behavior across Echo and Aida. Do not enable the new paths until reconciliation proves every existing Echo org/user/number has its intended canonical mapping; ambiguous mappings are reported and resolved without deleting or silently reassociating records.
6. Deploy one pinned shared-host Compose release for identity/NocoDB/Echo plus Aida services in dependency order, with Asterisk treated as an external owned system. Do not block the voice vertical slice on a complete Echo rewrite or installer framework.
7. Exercise real inbound/outbound SMS, delivery callbacks and replay handling, MMS upload and media retrieval, existing conversation history, login/logout, provider/UISP login links, and client permissions. Repeat under the `localsplash.dev` hostname plan. Separately execute the Aida call/transcript/Android vertical slice.
8. After all legacy readers are demonstrably retired, rename/retire legacy config structures, remove the shared identity bootstrap volume and obsolete UID dependency, then drop `echo_tbl_Settings` in a later release as required by EchoDatabase #8. Keep `echo_tbl_SchemaMigration` permanently. Table drop is not a POC success prerequisite.

No application tests were run for this review because no application code changed. The concrete authorization, migration, cache, and inter-service contract changes above require meaningful tests when implemented. Existing EchoWeb exposes `npm test` and TypeScript build; EchoService and EchoMedia currently expose only start scripts, so their migration acceptance will need a small integration harness rather than claiming a nonexistent test suite passes.
