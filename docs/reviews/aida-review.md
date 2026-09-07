# Aida architecture review and Infra PR #16 correction plan

Reviewed 2026-09-06 through the GitHub connector and an isolated local checkout. No running services or GitHub conversations were changed. AidaAdmin was cloned to `/opt/aida/AidaAdmin`; its Docker image was built, and local Infra README/build-sequence corrections were prepared. This is source/build review, not deployed-system validation.

## Accepted owner decisions during review

Preserve Echo data and access. Support a few businesses immediately, with a Super Admin able to administer all of them and tenant-scoped ordinary access. Keep OfficePulseAidaIntegration as the POC runtime and defer AidaControl. Obtain the Aida application source on local `dockerappvm01-dev`; development uses `localsplash.dev`.

## Sources and observed implementation

- [Infra issue #15](https://github.com/localsplash/AidaInfrastructureSetupInstructions/issues/15) asks for the platform data standard and MySQL/PlatformConfig migration.
- [Infra PR #16](https://github.com/localsplash/AidaInfrastructureSetupInstructions/pull/16) is open, not merged. Reviewed head `9c5b2af57644b5108d34d672693dd6b23baeb0af`; main was `e3dab5cbb37e3998fb5d167ccc6851cb4d481ed4`. Main contains only README plus three Markdown documents; no deployment automation or Compose exists there.
- [AidaControl #16](https://github.com/localsplash/AidaControl/issues/16) asks to migrate a PostgreSQL implementation to MySQL, while [#12](https://github.com/localsplash/AidaControl/issues/12) explicitly says greenfield and owns the target contracts/schema. The repository's Git trees endpoint returned HTTP 409, “Git Repository is empty.” There is no current Control implementation in this repository to port.
- AidaAdmin main is substantial code at `98d63ba6e2bfe8f322995180199a9521ecbb8fb4`: React UI, Express BFF, identity login/event processing, NocoDB schema and telephony configuration, OfficePulse provisioning and MySQL runtime reads, tests and Dockerfile. [README at reviewed commit](https://github.com/localsplash/AidaAdmin/blob/98d63ba6e2bfe8f322995180199a9521ecbb8fb4/README.md).
- [AidaAdmin #29](https://github.com/localsplash/AidaAdmin/issues/29) explicitly decided **there is no AidaControl service for the POC**; OfficePulseAidaIntegration orchestrates calls and owns `aida_officepulse` MySQL. Admin's [configuration source](https://github.com/localsplash/AidaAdmin/blob/98d63ba6e2bfe8f322995180199a9521ecbb8fb4/server/src/config.ts) and [dependency wiring](https://github.com/localsplash/AidaAdmin/blob/98d63ba6e2bfe8f322995180199a9521ecbb8fb4/server/src/deps.ts) implement that decision.
- [AidaAdmin #31](https://github.com/localsplash/AidaAdmin/issues/31) plans identity-directory tenant migration but does not resolve the runtime ownership reversal, Admin PostgreSQL, direct identity edits, or session-policy change.

## Recommendation

Keep AidaAdmin's implemented UI/BFF and retain a single call orchestrator in OfficePulseAidaIntegration for the first coherent POC, as accepted by the owner. Defer AidaControl as a separate deployment and repository build. Move its necessary contract and state-machine requirements into the existing runtime owner's backlog. Do not operate two orchestration engines or two authoritative call-session databases.

This is a POC simplification, not an endorsement that the existing runtime works end-to-end. Test real call screening, transcript display and takeover before declaring it functional. Separate runtime orchestration from the PBX adapter internally so a later extraction can reuse code without changing client contracts.

Merge infrastructure **responsibilities** into one platform operations home: use the existing EchoOrchestrator deployment foundation, retain the Infra documents as canonical architecture/runbooks or move them with redirects. One release manifest, one Compose composition, one backup/restore runbook, one configuration bootstrap. A large installer is unnecessary.

## Concrete blocking conflicts

| Finding | Evidence | Required correction |
| --- | --- | --- |
| New spec assigns runtime ownership to empty AidaControl, while implemented Admin depends on OfficePulse runtime | Admin #29; `config.ts`; `deps.ts`; Control repository empty | Record one POC runtime owner. Rewrite Control #12/#16 as deferred/extraction or transfer essential requirements into OfficePulse work. |
| MySQL-only inventory omits Admin's real PostgreSQL database | Admin `server/src/db/postgres.ts`, dependency `pg` in `server/package.json` | Add explicit MySQL migration for Admin sessions, state and identity receipts. Name an independent database/schema owner; proposed `aida_admin_db`, sole owner/writer AidaAdmin. |
| Identity sole-writer rule is already violated by an implemented path | Admin `server/src/nocodb/identity.ts:updateDisplayName` writes `id_tbl_User` through `AidaIdentity`; Admin directory route allows it | Remove `AidaIdentity` source dependency. Add authorized display-name update to identity API or omit editing for POC. All platform people/tenant/membership operations use identity APIs. |
| PR16 technical spec still says Aida owns tenants | Technical spec §§6.1, 13, 13.1, 13.3 at PR head | Replace all Aida tenant/membership ownership statements, not just database strings. Identity owns platform tenants/membership; Aida owns `TenantProfile` and telephony references. |
| “Exactly two environment values for every application” conflicts with “Agent/OfficePulse never reach NocoDB” | Standard §1.1 vs POC §1.2 | Define bootstrap and deployment injection separately from application configuration. Server apps may consume scoped NocoDB settings; runtime/agent receive only required settings through a documented startup path. Device/browser never hold NocoDB credentials. |
| The one `aida` settings scope collides across Admin and runtime | POC `cfg_tbl_Setting` plus Admin's own SQL store and OfficePulse runtime | Use component scope precedence: component → optional domain → platform. E.g. `aida-admin`, `officepulse-integration`, `aida-agent`; a generic `DB_NAME` must not select two owners' stores. |
| Single base/token claim does not specify actual write boundaries | POC says identity owns `cfg_tbl_Setting`, standard says owning app admin writes config, and every app gets a token | Identity/bootstrap owns shared schema; designate which UI edits which scopes. Scope service credentials where supported and enforce scope in APIs. One base does not require one all-powerful token. |
| Standard promises additive rollback safety while issue #31 performs type changes and deletion | Standard §5 vs Admin #31 migration note | Use expand → backfill/map → validate → switch → retire. Preserve old rows and mapping until rollback window closes; deletion is an explicit later release. “Application rollback is always safe” must be removed. |
| PR16 rejects NocoDB startup failure but seeds all settings empty and has no first-run setup path | Standard §1.3 and POC `cfg_tbl_Setting` | Document a bootstrap command/admin recovery path that can create base/schema and seed configuration before dependent apps start. Distinguish required settings from optional/unset settings. |
| Global `trustedCIDR` erases currently distinct trust contexts | Standard §6 vs Admin event source / trusted proxy / trusted caller settings; technical spec §§11.2, 13 | Retain explicit caller and proxy trust roles, even if same CIDR in this deployment. Define verified actor context for directory tenant writes and grants; CIDR only proves a peer network, not which signed-in admin is acting. |

Detailed source links: [Admin PostgreSQL](https://github.com/localsplash/AidaAdmin/blob/98d63ba6e2bfe8f322995180199a9521ecbb8fb4/server/src/db/postgres.ts), [dependencies](https://github.com/localsplash/AidaAdmin/blob/98d63ba6e2bfe8f322995180199a9521ecbb8fb4/server/package.json), [identity direct edit](https://github.com/localsplash/AidaAdmin/blob/98d63ba6e2bfe8f322995180199a9521ecbb8fb4/server/src/nocodb/identity.ts), [admin routes](https://github.com/localsplash/AidaAdmin/blob/98d63ba6e2bfe8f322995180199a9521ecbb8fb4/server/src/admin/routes.ts), [proposed standard](https://github.com/localsplash/AidaInfrastructureSetupInstructions/blob/9c5b2af57644b5108d34d672693dd6b23baeb0af/docs/PLATFORM_DATA_STANDARD.md), [proposed POC spec](https://github.com/localsplash/AidaInfrastructureSetupInstructions/blob/9c5b2af57644b5108d34d672693dd6b23baeb0af/docs/AIDA_POC_DATABASE_AND_INTERFACE_SPECIFICATION.md), [proposed technical spec](https://github.com/localsplash/AidaInfrastructureSetupInstructions/blob/9c5b2af57644b5108d34d672693dd6b23baeb0af/docs/AIDA_VOICE_PLATFORM_TECHNICAL_SPECIFICATION.md).

## Additional gaps that affect a working POC

### Admin identity and session migration

Current Admin persists `admin_session`, `auth_state`, `identity_event`, `identity_event_checkpoint` in PostgreSQL, including email and display-name snapshots and an eight-hour sliding session TTL. The new POC spec says applications' sessions never expire and prohibits identity copies. This is a substantive behavior change that #31 does not mention. Keep current bounded session behavior until an intentional platform session policy is chosen; avoid accidentally changing it during naming/engine work. Permit transient profile display caches explicitly or stop persisting those profile fields. [Session store](https://github.com/localsplash/AidaAdmin/blob/98d63ba6e2bfe8f322995180199a9521ecbb8fb4/server/src/auth/session-store.ts), [PostgreSQL implementation](https://github.com/localsplash/AidaAdmin/blob/98d63ba6e2bfe8f322995180199a9521ecbb8fb4/server/src/db/postgres.ts).

Implement Admin-owned MySQL migrations with a ledger and lock, preserving atomic single-use state consumption and receipt/effects/checkpoint transactions. Provide a one-shot export/import if preserving active sessions matters; otherwise explicitly invalidate Admin local sessions at cutover while retaining the working identity service. No Admin DDL in identity's `platform_db` or OfficePulse's runtime database.

Current `user.merged` handler only merges sessions and contains a TODO for tenant-user mappings; no `tenant.disabled`/`tenant.merged` handlers exist. The receipt store advances checkpoint with the maximum event ID received, so an out-of-order webhook can advance past a missing lower event before boot catch-up. Define replay progress separately from webhook receipt IDs or maintain contiguous sequence coverage. Migration to identity membership removes one local mapping, but extension user IDs, tenant profiles, runtime authorizations and disabled-tenant handling still require explicit effects. Do not acknowledge an event until all required effects have durable progress. [Event handlers](https://github.com/localsplash/AidaAdmin/blob/98d63ba6e2bfe8f322995180199a9521ecbb8fb4/server/src/id/events.ts), [receipt/checkpoint implementation](https://github.com/localsplash/AidaAdmin/blob/98d63ba6e2bfe8f322995180199a9521ecbb8fb4/server/src/db/postgres.ts).

The proposed directory API lists `grantSuperAdmin` as restricted to an authenticated SUPER_ADMIN while only documenting CIDR admission for directory endpoints. Add a server-verified actor/authorization contract. Also settle whether `identity_tbl_TenantUser` SUPER_ADMIN membership grants future login privilege, and how revocation affects previously issued `superAdmin` sessions. The spec currently combines a persisted grant with session-scoped handoff privilege without a clear rule. [POC §2.1](https://github.com/localsplash/AidaInfrastructureSetupInstructions/blob/9c5b2af57644b5108d34d672693dd6b23baeb0af/docs/AIDA_POC_DATABASE_AND_INTERFACE_SPECIFICATION.md).

### Runtime/config boundary and reliability

Admin's actual NocoDB schema includes `configuration_source`, `appearance`, `audit_log`, enrollment-token hash/expiry/consumption/version and optimistic revision fields. PR16's replacement schema omits these despite a working UI and enrollment flow using them. Enumerate retain/move/drop decisions. Suggested: retain appearance/source configuration; place enrollment credential consumption and durable audit/operation records in the appropriate MySQL runtime store; keep only slow-moving MAC/extension/profile binding in NocoDB. [Current schema](https://github.com/localsplash/AidaAdmin/blob/98d63ba6e2bfe8f322995180199a9521ecbb8fb4/server/src/nocodb/schema.ts), [enrollment route](https://github.com/localsplash/AidaAdmin/blob/98d63ba6e2bfe8f322995180199a9521ecbb8fb4/server/src/admin/routes.ts).

NocoDB uniqueness and revision checks are implemented as read-then-write. Two concurrent editors can pass both checks; comments claiming the revision still detects lost updates are too strong. At POC scale, single administrative writer plus serialized mutation handling may suffice; critical unique DID/enrollment/call semantics need atomic persistence or explicit checks and fail-closed bootstrap behavior. A unique SQL index cannot be assumed to exist just because it appears in a Markdown table. [NocoStore](https://github.com/localsplash/AidaAdmin/blob/98d63ba6e2bfe8f322995180199a9521ecbb8fb4/server/src/nocodb/repos.ts).

NocoDB-to-Asterisk provisioning is explicitly save-first, then immediate API invocation, with no reconciliation. Keep this simple but expose pending/failed/applied operation state and a stable idempotency key for retry. Do not show the stored intent as confirmed PBX state after a partial failure. A small durable operations table in the existing runtime is sufficient; no queue service or generic synchronization platform is required.

The proposed webhook table says duplicates are rejected by a unique insert. Define duplicate success responses for already-processed events and retry behavior for failed/pending receipts. A unique key alone does not prove the effects happened. Likewise a unique `(call, sequence)` index prevents duplicate sequence values but does not create gap-free allocation; transitions, events and command acceptance must commit atomically.

At runtime, a NocoDB outage must not unnecessarily terminate an established call whose configuration was snapshotted. Missing required configuration can fail new bootstrap deterministically and invoke PBX fallback; existing calls should continue using their pinned state and initialized dependencies. Provide `/healthz` liveness and meaningful `/readyz` separately.

### Exact PR #16 file corrections

1. **`docs/PLATFORM_DATA_STANDARD.md`** — keep three storage tiers, identity-owned master data, one PlatformConfig logical base, one SQL owner per database and untouched Asterisk tables. Correct:
   - Distinguish logical schema ownership from physical store location; a single physical MySQL server can host separate databases/users.
   - Add `aida_admin_db` owned by Admin and `aida_db` owned by OfficePulseAidaIntegration for the POC; inventory legacy `aida_officepulse` as a migration source, not a second target runtime.
   - Define bootstrap inputs and per-service configuration injection, settings scopes/precedence, typed required keys, secret visibility and admin rights. Preserve environment override escape hatch but remove literal universal “exactly two values.”
   - Make new naming apply to new first-party objects and explicitly staged migrations of existing objects; preserve wire fields and Asterisk/vendor schemas.
   - Replace “additive implies always safe rollback” with the staged migration/compatibility rule.
   - Define durable event receipt vs replay cursor; require idempotent effects and authorization invalidation.
   - Resolve missing standard columns: current POC tables omit `dtCreated`/`dtUpdated` in places despite “every table” language. Avoid decorative churn where a semantic issued/received timestamp suffices.
   - State that changing a global trust CIDR cannot replace distinct trusted-proxy and application-caller rules.

2. **`docs/AIDA_POC_DATABASE_AND_INTERFACE_SPECIFICATION.md`** — rewrite as the executable POC contract:
   - Replace production hostnames/server names with `X.TLD` examples plus one explicit deployment table for `localsplash.dev` and `localsplash.ai`.
   - Adopt one POC runtime owner, OfficePulseAidaIntegration. Preserve existing compatible API paths while documenting public device/agent/signed-webhook endpoints vs private provisioning/admin operations.
   - Rename §1.3 ownership and align schema to actual runtime tables; include missing operation/outbox/receipt/device records only when needed by accepted POC flows, with source migration mappings.
   - Add Admin-owned MySQL session/auth-state/identity-receipt store and migration path.
   - Add directory user-edit endpoint or explicitly disable that feature; define trusted actor context and role revocation semantics.
   - Complete NocoDB schema coverage for implemented UI and enrollment or list deliberate retired fields and how consumers migrate.
   - Replace universal NocoDB prohibition for OfficePulse with a precise rule for the runtime configuration reader. Browser and handset remain prohibited.
   - Preserve Asterisk schema boundary: approved provisioning DML through the adapter, no DDL, table renames, triggers or ownership of vendor migrations.
   - List actual POC scope: single deployment brand with configurable domain/assets, one tenant first and a second isolation test tenant, existing Echo messaging, Aida voice/transcript/takeover, identity consolidation. Keep CRM, reseller/custom-domain brands and generic installer out of first acceptance.

3. **`docs/AIDA_VOICE_PLATFORM_TECHNICAL_SPECIFICATION.md`** — update ownership and architecture, not global text substitutions:
   - Title/objective and §§5.1, 5.3–5.6: implemented Admin/runtime baseline, deferred Control extraction, single operations owner.
   - §§6.1, 13, 13.1, 13.3: identity owns tenants/memberships; Aida owns profile/configuration and references.
   - §§6.3–6.4: PlatformConfig + real runtime + Admin session database.
   - §§8–11: direct OfficePulse orchestration, actual bootstrap/enrollment/takeover/webhook API owner and consistent authentication.
   - §11.2 currently calls for mTLS/workload credentials while §13 declares CIDR-only POC trust. Record the actual POC mechanism and identify which routes remain token/signature authenticated.
   - §§12–13: consistent session policy and platform grant behavior.
   - §15: deployment white-labeling allowed now through `PARENT_DOMAIN` and brand settings; multi-reseller skin/custom-domain orchestration remains future scope.
   - §19: remove claims “identity is the only pre-existing code,” “five greenfield apps,” and unrelated historical rebuild order.

4. **`docs/POC_REPOSITORY_BUILD_SEQUENCE.md`** — replace old greenfield task ordering:
   - Inventory current release SHAs and data/store mappings; freeze one ownership/API/config contract.
   - Implement identity directory/platform data + config bootstrap; run additive migrations and directory tests.
   - Migrate Admin identity/tenant/config adapter and session store; retain working UI.
   - Adapt existing OfficePulse runtime to the canonical tenant/config contracts and fill missing handset/agent endpoints.
   - Verify/update Agent and Handset against generated/pinned contracts; they are not automatically “verify only.”
   - Integrate Echo configuration/tenant mapping in compatible waves; protect working messaging.
   - One composed staging deployment and real end-to-end acceptance, then retire legacy data/schema only after validation.
   - Replace obsolete issue numbers/directions with one dependency matrix; no action should depend on an empty service.

5. **`README.md`** — state architecture and deploy/runbook ownership consistently; link canonical platform standard and concise POC contract. Clarify the repository currently contains documents only and where executable composition lives. Remove promises that PostgreSQL removal or Compose updates have already occurred merely because wording changed.

6. **New small `docs/PLATFORM_DECISIONS.md` or ADR** — record (a) one runtime in OfficePulse for POC; (b) independent Admin SQL owner; (c) identity sole writer; (d) unchanged Asterisk schema; (e) one operations home, small Compose composition; (f) source precedence: accepted ADR/POC contract > broader future architecture > stale issues. Link superseded issues without silently deleting their unresolved functional acceptance criteria.

PR16 should be corrected/replaced in place; throwing away its useful storage/ownership baseline is unnecessary. Do not merge it as “docs only” while it prescribes an implementation opposite to current code.

## Minimal acceptance gates for the corrected plan

1. Identity handoff remains working for Echo and Admin; one platform user/tenant mapping is used; disabled memberships lose access and replay works after a missed/out-of-order event.
2. Admin can list/edit permitted users through identity API, create tenant/profile/extension/route, provision PBX, and show explicit failure/retry state. A tenant admin cannot act on another tenant.
3. Runtime resolves a configured DID, snapshots configuration, starts the existing agent, exposes a real Android enrollment/call session, streams live transcript, and completes takeover on the physical handset.
4. Two commands at one call version produce one accepted effect; duplicate bootstrap/token/webhook/command delivery does not duplicate external actions.
5. NocoDB unavailable at bootstrap invokes documented fallback; established calls survive; restarting Admin retains/revokes sessions and catches up receipts according to the chosen policy.
6. Existing Echo send/receive and identity flow still work after consolidation.
7. Backup/restore is exercised for platform, Admin, runtime and NocoDB data before any destructive retirement. Asterisk vendor schema remains unchanged.

## Decisions to resolve with the platform owner

- Which existing identity population is canonical when the two independent deployments contain overlapping people or identifiers? Preserve an explicit old-system/user/tenant mapping; do not infer identical integers mean the same record.
- What exact POC voice completion demo is required (physical Android handset, LiveKit cloud agent, inbound number and takeover destination)?
- Does the current independent Aida POC contain data/sessions worth preserving, or may its disposable app data be recreated while preserving PBX configuration?
- Accepted: OfficePulseAidaIntegration remains call owner and AidaControl is deferred.
- Which server hosts the PBX and which runtime endpoints are reachable from the shared Docker host? Keep the deployment manifest configurable for both local and remote PBX.

Most other implementation choices can proceed from the explicit standard and current code without asking the user.

## Local build follow-through

AidaAdmin was cloned to `/opt/aida/AidaAdmin`; the production Docker image `aida-admin:review-98d63ba` built successfully. The isolated Node 22 validation image passed typecheck, 204 tests (158 server + 46 UI), and production build; 8 PostgreSQL/NocoDB integration tests were skipped without live services. No service was started. See [local readiness report](aida-admin-readiness.md) for exact image IDs, required configuration names and remaining migration work. Infra README and build sequence were corrected locally as assigned; `git diff --check` passed.
