# Voice clients and OfficePulse integration review

Reviewed 2026-09-06 using GitHub issues, complete main trees, available branches/PRs, implementation files, and CI metadata. Subsequently cloned the three repositories and validated OfficePulse locally as described below. No live services were changed, no calls placed, and no real-device acceptance was performed.

## Local development preparation completed

- Clean source checkout: `/opt/aida/OfficePulseAidaIntegration`, commit `291e2d927590da84d52bb2127186bda4e37e3598`.
- Clean source checkouts: `/opt/aida/AidaAgent` and `/opt/aida/AidaHandset`; both remain README-only upstream repositories.
- Existing OfficePulse `npm run verify` passed locally: TypeScript checks and all **163 tests passed**, zero failures/skips. Existing `npm run build` also passed.
- Validation used Node 22 in a Docker build because host Node is 18 and the repository requires Node >=22. Recipe: `/opt/platform-review/officepulse-validation.Dockerfile`. Validation image: `aida-officepulse-validation:291e2d9`, image ID `sha256:57abf5ae70628cb776583be93233f06fd108fc9f5ccb2bf738159d42c8d0cfa8`.
- No credentials, databases, telephony endpoints, numbers or running services were attached to the validation. This proves checkout/build/fake-provider tests, not live voice readiness.
- The user subsequently confirmed retaining OfficePulse as the POC runtime, supporting a few tenants immediately and SUPER ADMIN visibility across them. The local app repositories are now available for implementation; the missing Agent/Handset source must still be located or built.

## Recommendation

Keep OfficePulseAidaIntegration as the POC's sole voice runtime owner and Asterisk adapter. It already implements substantial orchestration; restoring a separate AidaControl now adds another application and ownership migration before a working vertical slice exists. AidaControl can remain a future extraction boundary. Preserve separate public device/user API and private provisioning/ARI boundaries even if implemented as modules in one process.

The current three issues are materially underscoped. OfficePulse #10 is more than settings/type alignment; AidaAgent #7 and AidaHandset #8 cannot be verification-only because those repositories contain no implementation.

## Source and implementation inventory

| Repository / issue | Inspected current state | Implication |
|---|---|---|
| [OfficePulseAidaIntegration #10](https://github.com/localsplash/OfficePulseAidaIntegration/issues/10) | Main commit `291e2d927590da84d52bb2127186bda4e37e3598`; merged [PR #8](https://github.com/localsplash/OfficePulseAidaIntegration/pull/8); one leftover implementation branch. TypeScript service, Dockerfile, systemd/deployment scripts, fake-provider unit tests. | Reuse implementation, correct missing contracts. |
| [OfficePulse #9](https://github.com/localsplash/OfficePulseAidaIntegration/issues/9) | Explicitly removed AidaControl and made this service sole orchestrator; closed after code merge. | Contradicts new #10's instruction to read an AidaControl base URL. |
| [AidaAgent #7](https://github.com/localsplash/AidaAgent/issues/7) | Main `235375de0eb29c48f44fb935cc002ff3839f58c8` contains [README.md](https://github.com/localsplash/AidaAgent/tree/235375de0eb29c48f44fb935cc002ff3839f58c8) only; no other branches or PRs returned. | No repository implementation to verify. A deployed Cloud agent could exist elsewhere; obtain/export its actual source/config before replacing a working POC. |
| [AidaHandset #8](https://github.com/localsplash/AidaHandset/issues/8) | Main `a04e6db44da07bb797d1a3a63d25f9d5747ac435` contains [README.md](https://github.com/localsplash/AidaHandset/tree/a04e6db44da07bb797d1a3a63d25f9d5747ac435) only; no other branches or PRs returned. | No Android implementation, build, APK, or tests in this repository. Existing device app on another server must be located or built. |
| OfficePulse tests | [Main CI run 33613231709](https://github.com/localsplash/OfficePulseAidaIntegration/actions/runs/33613231709) is successful; [workflow](https://github.com/localsplash/OfficePulseAidaIntegration/blob/291e2d927590da84d52bb2127186bda4e37e3598/.github/workflows/ci.yml) runs typecheck, tests, container build/non-root check. [Issue #9 closeout](https://github.com/localsplash/OfficePulseAidaIntegration/issues/9#issuecomment-5507297500) reports 163 fake-provider tests and explicitly defers real-environment acceptance until deployment. | Evidence of code/unit checks, not proof that live calls, SIP writes, transcription, or Android currently work. |

## Current voice path

Implemented server path:

1. Provisioned Asterisk DID dialplan plays disclosure, invokes FastAGI, then enters a static post-bootstrap include.
2. OfficePulse reads the old NocoDB `AidaAdmin` base's `tenant`, `did_route`, `assistant_profile`, `extension`, and `ring_group` configuration; pins IDs/revisions into a locally generated UUID call session in `aida_officepulse`.
3. It creates a LiveKit room, dispatches `aida-prime`, and publishes a minimal Pusher call-arrival notification for a directly assigned extension's device.
4. ARI originates the SIP leg to LiveKit and bridges it with the caller. Audio travels Asterisk ↔ LiveKit.
5. The private command API can initiate takeover. ARI rings the configured extension/ring group, bridges the human immediately on answer, and removes only the LiveKit leg after a timer or drain acknowledgement.

Sources: [callOrchestrator.ts](https://github.com/localsplash/OfficePulseAidaIntegration/blob/291e2d927590da84d52bb2127186bda4e37e3598/src/orchestrator/callOrchestrator.ts), [takeoverManager.ts](https://github.com/localsplash/OfficePulseAidaIntegration/blob/291e2d927590da84d52bb2127186bda4e37e3598/src/takeover/takeoverManager.ts), [dialplan](https://github.com/localsplash/OfficePulseAidaIntegration/blob/291e2d927590da84d52bb2127186bda4e37e3598/asterisk/extensions_aida.conf).

Planned remaining path: authenticated handset learns about call → receives authorized call details and data-only room token → joins LiveKit Data → renders Agent transcript topics → submits authorized version-checked takeover → receives authoritative lifecycle updates. The inspected repositories do not currently complete that path.

## Existing and missing API surface

All current routes except the signed LiveKit webhook are CIDR gated. CIDR gating is private service trust, not user/device authorization.

| Current route | Implemented behavior | Missing required behavior |
|---|---|---|
| `POST /v1/provisioning/extensions` | Create SIP endpoint/AOR/auth and dialplan; return generated secret once. | Integer tenant mapping / current platform schema contract. |
| `PUT /v1/provisioning/extensions/:extensionId` | Update extension and collision checks. | Current platform ID contract. |
| `POST /v1/provisioning/extensions/:extensionId/rotate-secret` | Rotate once; replay returns already applied without secret. | None established by this review beyond platform alignment. |
| `PUT /v1/provisioning/ring-groups/:ringGroupId` | Provision virtual extension and members. | Current platform ID contract; handset alert audience for members. |
| `PUT /v1/provisioning/dids/:didRouteId` | Provision DID and optional runtime fallback projection. | Required fallback data; standalone Asterisk fallback when integration is down. |
| `POST /v1/provisioning/handsets` | Send provisioning payload to existing provisioning server. | This is not handset enrollment/authentication. |
| `GET /v1/calls/:callSessionId` | Return raw runtime session. | Device/tenant/extension checks; `{callSession, liveKitUrl, participantToken}` response. |
| `GET /v1/calls/:callSessionId/events` | Return all persisted events. | Device authorization and cursor recovery contract. |
| `POST /v1/calls/:callSessionId/commands` | TAKEOVER / DRAIN_ACK; unique session/idempotency-key command claim. | Actor auth/scopes, `expectedCallVersion` check, durable atomic state transition, agent-specific authorization for DRAIN_ACK. |
| `POST /v1/integrations/livekit/webhooks` | Raw-body signature/hash verification and delivery deduplication. | Reliable application/retry semantics and correct separation of media-room vs telephone-call lifecycle. |
| `/healthz`, `/readyz` | Process health / per-dependency readiness. | Real environment results remain unverified. |
| Absent | — | Device enrollment/refresh/revoke; private Pusher channel authorization; `GET /v1/calls?status=active&assignedToDevice=true`; agent bootstrap endpoint if token-based dispatch chosen. |

Sources: [complete routes.ts](https://github.com/localsplash/OfficePulseAidaIntegration/blob/291e2d927590da84d52bb2127186bda4e37e3598/src/http/routes.ts), [HTTP auth middleware](https://github.com/localsplash/OfficePulseAidaIntegration/blob/291e2d927590da84d52bb2127186bda4e37e3598/src/http/httpServer.ts), [current normative POC API requirements](https://github.com/localsplash/AidaInfrastructureSetupInstructions/blob/main/docs/AIDA_POC_DATABASE_AND_INTERFACE_SPECIFICATION.md).

## Specific POC blockers and contradictions

### 1. Dispatch contract is not unchanged

Agent #7 claims unchanged `{callSessionId, bootstrapToken}`. Current OfficePulse [CallMetadata and dispatch](https://github.com/localsplash/OfficePulseAidaIntegration/blob/291e2d927590da84d52bb2127186bda4e37e3598/src/livekit/client.ts#L18) send call ID, string tenant ID, business name, prompt/behavior overrides, locale and DID inline. There is no bootstrap token. Select and version one contract before implementing Agent.

Recommended final contract is a call-scoped, expiring bootstrap credential that retrieves the pinned configuration from the sole runtime owner; no direct DB/NocoDB access from Agent. If exporting the working Cloud POC reveals only inline metadata support, a documented, versioned inline allowlist can be the first POC bridge. Do not pretend the two shapes are compatible or silently accept both forever. Agent must inherit the configured model/STT/TTS/voice; the predefined agent name and Cloud ID belong in deployment config, not open-source code.

### 2. Handset API and authorization are absent

The complete current route table has none of enrollment, refresh, Pusher auth, active-call discovery, or room-token issuance. GET call is a raw database row behind IP trust. An Android implementation alone cannot repair these missing server capabilities. Add device credentials scoped to tenant + extension/device; verify assignment on every read and command. Keep existing private provisioning endpoints unavailable to handset tokens.

Only device credential/bootstrap state and active-call UI state should live locally; no copied tenant directory, NocoDB configuration database, SIP secret, or historical transcript store. A blanket “no configuration copy” must still allow server URL, branding presentation cache, enrollment identity and secure refresh credential, or the app cannot bootstrap.

### 3. Telephone lifecycle and Agent lifecycle are disconnected

[RuntimeCallEventSink](https://github.com/localsplash/OfficePulseAidaIntegration/blob/291e2d927590da84d52bb2127186bda4e37e3598/src/runtime/callEventSink.ts#L19) appends ARI takeover events but does not update `call_session.state` or publish LiveKit control data. [index.ts](https://github.com/localsplash/OfficePulseAidaIntegration/blob/291e2d927590da84d52bb2127186bda4e37e3598/src/index.ts#L123) wires this sink into takeover without a LiveKit command publisher. The LiveKit publish helper exists, but this event flow does not use it. Thus the local drain timer works independently of the specified Agent transfer/drain speech protocol.

[Webhook handler](https://github.com/localsplash/OfficePulseAidaIntegration/blob/291e2d927590da84d52bb2127186bda4e37e3598/src/livekit/webhookHandler.ts#L95) marks the call ended on `room_finished`. That must not define telephone call end after human takeover: ARI/caller-human state is authoritative. Call state/version and durable events need coordinated transitions; room status needs its own field. Agent-only commands must target the current Agent SID, and Agent lifecycle acknowledgements need an authenticated inbound path.

### 4. expectedCallVersion is ignored

[Command route](https://github.com/localsplash/OfficePulseAidaIntegration/blob/291e2d927590da84d52bb2127186bda4e37e3598/src/http/routes.ts#L122) validates commandType and idempotencyKey but never examines expectedCallVersion. The current row version increments for ordinary runtime updates, and the command claim is separate from state/version mutation. Implement atomic expected-version validation + accepted command + next state/version + event sequence before claiming the issue verified. Handset simply echoes the server's version and uses a stable key for retries.

### 5. Claimed service-down DID fallback is not actually provisioned

The README promises correct DID-specific fallback even when the whole service is down. But [didDialplanRows](https://github.com/localsplash/OfficePulseAidaIntegration/blob/291e2d927590da84d52bb2127186bda4e37e3598/src/provisioning/dids.ts#L45) only sets instance/linked ID, plays disclosure, calls AGI and jumps into the static include. It does not set `AIDA_FALLBACK_CONTEXT` or `AIDA_FALLBACK_EXTENSION`. [The include](https://github.com/localsplash/OfficePulseAidaIntegration/blob/291e2d927590da84d52bb2127186bda4e37e3598/asterisk/extensions_aida.conf) uses deployment-wide defaults when those variables are absent.

The runtime DB projection helps only while the integration can execute. At provisioning time, resolve and tenant-check the fallback destination and project it into the supported Asterisk dialplan customization so a stopped process and inaccessible runtime DB cannot route to the wrong tenant or strand the call. Fallback fields must be required for enabled POC routes. Verify this with two tenants and the integration stopped.

### 6. Database and settings changes exceed “no schema change”

Current [configRepository.ts](https://github.com/localsplash/OfficePulseAidaIntegration/blob/291e2d927590da84d52bb2127186bda4e37e3598/src/nocodb/configRepository.ts) queries old unprefixed NocoDB tables and string tenant IDs. [Extension provisioning](https://github.com/localsplash/OfficePulseAidaIntegration/blob/291e2d927590da84d52bb2127186bda4e37e3598/src/provisioning/extensions.ts#L104) explicitly rejects non-UUID tenants; [validate.ts](https://github.com/localsplash/OfficePulseAidaIntegration/blob/291e2d927590da84d52bb2127186bda4e37e3598/src/provisioning/validate.ts) hashes the tenant ID into the SIP username. Changing the tenant ID without a mapping could create a different endpoint name. Preserve existing provisioned SIP IDs and map legacy tenants explicitly.

[Runtime schema](https://github.com/localsplash/OfficePulseAidaIntegration/blob/291e2d927590da84d52bb2127186bda4e37e3598/deploy/sql/runtime-schema.sql) uses string tenant references; [bookkeeping schema](https://github.com/localsplash/OfficePulseAidaIntegration/blob/291e2d927590da84d52bb2127186bda4e37e3598/deploy/sql/schema.sql) adds `aida_object`, `aida_device`, `aida_provisioning_request` beside the Asterisk vendor tables. It does not alter vendor table definitions. If “Asterisk DB untouched” excludes companion tables too, relocate only these owned tables into an integration-owned database and adjust queries/transactions. Never rename vendor `ps_*`, CDR, CEL or dialplan table schemas to the platform standard.

The runtime schema also declares `provisioning_operation`, but current [MysqlRealtimeStore](https://github.com/localsplash/OfficePulseAidaIntegration/blob/291e2d927590da84d52bb2127186bda4e37e3598/src/provisioning/mysqlStore.ts#L144) still uses `aida_provisioning_request`. Choose one actual provisioning-idempotency owner; do not infer a completed migration from SQL comments.

### 7. Notifications/recovery are incomplete for simultaneous calls

[resolveDeviceIds](https://github.com/localsplash/OfficePulseAidaIntegration/blob/291e2d927590da84d52bb2127186bda4e37e3598/src/orchestrator/callOrchestrator.ts#L272) returns no devices for ring-group routes. The first POC can deliberately target one extension and handset, but multi-member group alerts require member resolution and authorization. Missed Pusher alerts also require the absent active-call discovery endpoint. Transcripts stay on LiveKit Data; Pusher remains minimal notification only.

### 8. Restart during drain needs a specific acceptance test

[reconcile()](https://github.com/localsplash/OfficePulseAidaIntegration/blob/291e2d927590da84d52bb2127186bda4e37e3598/src/takeover/takeoverManager.ts#L458) reconstructs live channel/bridge roles and command keys but does not restore a drain timer/deadline for an already answered human. Persist the takeover/drain deadline and reestablish bounded Agent removal without touching the caller-human bridge.

## Minimal integration contract to freeze

- Identity owns integer tenant IDs and user membership. Voice references those IDs; migration retains explicit legacy-ID mapping.
- AidaAdmin owns its desired voice configuration tables in the NocoDB `PlatformConfig` base; OfficePulse reads published configuration and pins its revision per call. `platform_db` holds Identity-owned people, tenants, memberships and identity state. PlatformConfig's `cfg_tbl_Setting` holds typed deployment settings, including runtime secrets marked for protected handling, under explicit service/shared scopes. Infrastructure bootstrap credentials and operator-rendered worker secrets retain explicit startup/restore handling. `bSecret` is handling metadata, not encryption or row-level access control.
- OfficePulse owns call sessions, state versions, commands, operational events, device credentials if this runtime exposes the public device API, local fallback projections and Asterisk provisioning mappings. The target runtime store is `aida_db`; current code uses `aida_officepulse` and also keeps companion `aida_object`, `aida_device` and `aida_provisioning_request` tables beside upstream PBX tables. New platform-owned tables belong in the integration-owned database; migrate or explicitly adopt the existing companion records while preserving source mappings, SIP endpoint IDs and provisioning idempotency history. Shared identity user auth does not replace device enrollment.
- Asterisk remains the independent telephone/media system; only supported provisioning data and custom dialplan/ARI integration are managed.
- AidaAgent owns live transcription and AI speech behaviors, has no direct database credentials, and speaks the published room-data contract.
- AidaHandset is a data/control APK. The Grandstream SIP application answers audio; the APK never handles SIP passwords or audio tracks.
- LiveKit carries SIP/AI audio plus room data; Pusher only alerts. Live transcripts are not persisted by default. Historical transcripts are a separate explicitly scoped feature.

## End-to-end POC acceptance

1. Start one configured tenant, one DID, one extension/Grandstream handset and one assistant. Shared login authorizes the admin; a second tenant cannot access any of the first tenant's resources.
2. Provision extension/DID through AidaAdmin → private integration API; inspect expected supported Asterisk rows and retain existing endpoint IDs across tenant-ID migration. Retry provisioning/rotation and confirm secrets are never replayed.
3. Enroll the real APK using a one-time bootstrap. Repeat use fails; token refresh rotates; revocation blocks calls, Pusher auth and commands.
4. Dial the DID. Hear disclosure before screening. Show one call session/room/dispatch despite duplicate FastAGI bootstrap; caller hears the expected assistant.
5. Receive minimal Pusher notification; authorized GET call returns scoped room token. APK joins without audio publish/subscribe and shows partial/final live transcript with speaker and ordering; no database transcript record is created.
6. Place a second simultaneous call. Both appear independently with correct transcript/state; missed notifications recover through active-call discovery.
7. Tap Take over. A repeated request produces one originate; stale version receives a stable conflict/current state. The Grandstream SIP application rings and answers; caller-human audio bridges immediately. Agent receives transfer/drain controls and leaves within the agreed deadline.
8. Human hangup during drain does not strand the caller. Busy/reject/timeout restores assistant behavior and emits a durable failure event.
9. Stop NocoDB/LiveKit and separately stop the integration process. Each DID reaches its own tenant-checked fallback with disclosure/failure prompts; run this against at least two tenants.
10. Restart integration during ringing, during drain and after human bridge. No duplicate originates; drain remains bounded; the established human call continues; final telephone hangup sets ended state exactly once.
11. Reconnect APK/network mid-call. Refresh authorized details/tokens; recover durable lifecycle and live transcript buffer with bounded memory; show an explicit gap when live-only transcript replay is unavailable.
12. Export build/deployment evidence: server image digest and config version, Agent version/source, installable APK, real call traces correlated by callSessionId, and results for the above checks. Passing fake tests alone does not close this acceptance.

## Proposed issue revisions

- OfficePulse #10: retain sole runtime owner; align platform IDs/tables/settings; add authenticated handset API and atomic state/command handling; fix offline fallback/lifecycle/drain recovery. Break implementation into a few reviewable slices rather than claim verify-only.
- AidaAgent #7: locate/export deployed POC, then implement versioned bootstrap/dispatch and transcript/speech/control contract with fakes and live acceptance.
- AidaHandset #8: locate/export existing APK source or implement Kotlin Android app against completed device API; add pairing, active call discovery, data-only LiveKit transcript display and takeover/recovery. Define the supported Grandstream device/Android version.
- Infra canonical document: supersede the AidaControl-dependent merge sequence and explicitly name the above sole runtime owner, bootstrap contract, database ownership and end-to-end acceptance.

Unresolved operator facts worth asking after this review: where the working/partial Agent and Android source/APK live; which LiveKit Cloud project/agent and SIP trunk are authoritative; whether the current OfficePulse server remains separate; whether the first demo needs one extension only or ring-group handset fan-out. These cannot be established from the inspected GitHub repositories.
