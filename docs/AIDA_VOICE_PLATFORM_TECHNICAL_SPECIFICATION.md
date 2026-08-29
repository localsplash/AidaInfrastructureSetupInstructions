# Aida Voice Platform — Greenfield System Specification

Status: Draft for autonomous project implementation  
Telephony: OfficePulse / Asterisk 22.10.1 Realtime
Voice agent: LiveKit  
Handset: Grandstream GXV3450 / Android 11  
Existing integrations: LocalSplash CRM, LocalSplash `id` (identity), EchoService  
Optional realtime provider: Pusher Channels

## 1. Objective

The Aida Voice Platform screens inbound telephone calls with an AI voice assistant and lets an authorized handset user observe and control the conversation in real time.

OfficePulse/Asterisk owns the PSTN call from arrival through hangup. Aida joins through LiveKit as a temporary media participant. The Android Aida Handset displays call state, live transcription, suggested actions, and a **Take over** control. Take over rings the configured SIP destination and connects the human without cutting off Aida's current transfer statement.

OfficePulse owns call recording and plays the required English recording disclosure before Aida begins. The POC is English-only; language selection is deferred.

The system consists of independently buildable projects joined by versioned contracts. Each project must be generatable, testable, containerized where applicable, and deployable by an autonomous implementation agent without undocumented assumptions about another repository. The concise [POC database and input-interface specification](AIDA_POC_DATABASE_AND_INTERFACE_SPECIFICATION.md) is normative for initial database ownership, configuration writes, FastAGI, provisioning, and method signatures.

## 2. Existing systems and boundaries

- **OfficePulse** is the existing Asterisk SIP/PSTN platform. It remains authoritative for channels, bridges, endpoints, ringing, answer, and hangup.
- **OfficePulse call recording** remains authoritative for recording media, disclosure playback, file lifecycle, and any existing recording retention controls. Aida does not make a second recording.
- **LiveKit** supplies realtime media and voice-agent facilities. It is not the system of record for profiles or calls.
- **LocalSplash CRM** supplies onboarding defaults. CRM values retain source metadata and can be overridden by precise Aida configuration.
- **`id`** is the LocalSplash identity service at `id.localsplash.ai` and is an in-scope Aida Office project. It owns the shared `id_db.id_tbl_User` person identifier, provider identities, sign-in (including Google, Microsoft, and UISP), sessions, and revocation. Aida stores only an `iUserId`-to-tenant role mapping and no duplicate person, password, name, email, or provider-identity record.
- **EchoService** is Echo's messaging service layer.
- **Pusher Channels** supplies lightweight call-arrival and call-state notifications. Live details and stream credentials come from AidaControl.

Live-call handling must not depend on Echo messaging availability. Aida owns its runtime data and voice routing.

## 3. Product language and identifiers

| Term | Definition |
|---|---|
| **Aida Voice Platform** | Complete screening, control, and administration system |
| **Aida Control Plane** | Authoritative application API and call orchestrator |
| **Assistant Profile** | Reusable prompt, voice, behavior, tools, and policy configuration |
| **Profile Version** | Immutable published Assistant Profile snapshot |
| **Inbound Route** | DID-to-profile and DID-to-destination configuration |
| **Call Session** | Durable state machine for one telephone call |
| **OfficePulse API** | Private Asterisk adapter/API |
| **Aida Handset** | Android data/control application associated with a SIP destination |

| Identifier | Format and purpose |
|---|---|
| `tenantId` | UUID; customer/organization security boundary |
| `assistantProfileId` | UUID; stable logical profile |
| `assistantProfileVersionId` | UUID; immutable published configuration |
| `inboundRouteId` | UUID; DID routing record |
| `callSessionId` | UUIDv7; cross-system call identifier |
| `commandId`, `eventId`, `deviceId` | UUIDs |
| `asteriskLinkedId` | Diagnostic Asterisk correlation value, never a public resource ID |

Telephone numbers are E.164 strings, such as `+12065551212`. Asterisk channel names and LiveKit participant SIDs are runtime references only.

## 4. DNS and network design

### 4.1 Public wildcard

All Aida-owned public services use `*.aida.localsplash.ai`. One wildcard DNS record points to one public ingress IP. TLS uses a wildcard certificate.

| Hostname | Service |
|---|---|
| `app.aida.localsplash.ai` | Administration application |
| `api.aida.localsplash.ai` | Browser/handset REST API, signed LiveKit webhook receiver, and published contract artifacts under `/v1/contracts/...` |
| `id.localsplash.ai` | LocalSplash identity service (`id`). Its `PARENT_DOMAIN` is the apex `localsplash.ai` — independent of Aida's wildcard DNS record, certificate, and ingress |

Ingress routes by hostname to internal services. Published contract artifacts (OpenAPI, AsyncAPI, JSON Schemas) are served under `api.aida.localsplash.ai/v1/contracts/...` — a path on the existing API hostname matching the `/v1` versioning scheme; there is deliberately no separate `contracts.aida.*` hostname or DNS entry. The `id` service is reached at its own apex-domain hostname. The POC and foreseeable deployment use LiveKit Cloud for media and realtime transcript/control data. Pusher provides call-arrival notifications. Aida does not operate a first-party WebSocket service and no `realtime.aida.localsplash.ai` DNS record is required.

A first-party realtime gateway is outside the planned system. It would be reconsidered only if Aida intentionally replaces LiveKit Data for application events because of a demonstrated requirement such as unsupported client behavior, contractual data-residency restrictions, or measured scale/cost constraints. Such a change requires a new architecture revision and is not implied by this specification.

### 4.2 Private OfficePulse API

Use **`officepulse-api.localsplash.ai`**. DNS names remain lowercase even though the product label is “OfficePulse API.”

This hostname resolves to a different private or tightly restricted IP from the public wildcard. Preferred connectivity is private networking, VPN, or an overlay. If Internet-routable, firewall rules allowlist OfficePulse egress addresses and both sides require mTLS. It exposes no browser UI, permissive CORS, user login, or public API explorer.

For the POC it uses public DNS and an independently firewalled web service limited to known internal server source addresses. Application-level service authentication remains mandatory because an IP allowlist alone is not identity.

Asterisk ARI remains bound to loopback or a private OfficePulse interface. Only OfficePulse API possesses ARI credentials.

## 5. Repositories and autonomous build contracts

Each repository must contain a README, architecture notes, `.env.example` without secrets, deterministic local startup, health/readiness endpoints where relevant, tests, lint/format commands, CI, container build where relevant, and pinned contract versions.

The implementation stack is fixed for the POC: TypeScript/Node.js for `id`, AidaControl, and OfficePulseAidaIntegration, React/TypeScript for AidaAdmin, Python for AidaAgent, Kotlin for AidaHandset, Docker Compose for initial deployment, and GitHub Actions for CI. Interface contracts use OpenAPI 3.1, AsyncAPI, and JSON Schema.

`localsplash/id` is the only application repository with pre-existing implementation code. `localsplash/new_AidaControl`, `localsplash/new_AidaAdmin`, `localsplash/OfficePulseAidaIntegration`, `localsplash/AidaAgent`, and `localsplash/AidaHandset` are greenfield builds. The deprecated `delme_AidaControl` and `delme_AidaAdmin` repositories are neither dependencies nor reference implementations. `localsplash/AidaInfrastructureSetupInstructions` is the canonical documentation and deployment-automation repository. The dependency-ordered implementation backlog is defined in [POC_REPOSITORY_BUILD_SEQUENCE.md](POC_REPOSITORY_BUILD_SEQUENCE.md).

### 5.0 `id`

`localsplash/id` is part of the POC application scope. It owns the shared MySQL
`id_db`, creates or resolves `id_tbl_User` during successful provider
authentication, returns `iUserId` through its one-time application-code flow,
and delivers revocation/identity events. AidaAdmin maps that UID to a tenant and
Aida role; it does not create another user/person row.

### 5.1 `AidaControl` (repository: `localsplash/new_AidaControl`)

Authoritative API and call orchestrator.

Responsibilities:

- read resolved tenants, profiles, routes, devices, and permissions from NocoDB for runtime decisions;
- DID resolution and immutable profile-version pinning;
- Call Session state machine and transactional command acceptance;
- LiveKit room/token lifecycle and agent dispatch;
- OfficePulse and agent event ingestion;
- transactional call-state/event persistence, replay, and LiveKit Data publication;
- future LocalSplash CRM default import and override tracking, disabled for the POC;
- validation of CIDR-trusted AidaAdmin staff/tenant/session context for runtime call views and commands;
- reconciliation of orphan/inconsistent resources.

AidaControl is the source of truth for shared runtime contracts and exclusively owns the transactional Postgres store. Its repository contains:

- `/contracts/openapi` for public AidaControl endpoints;
- `/contracts/asyncapi` for LiveKit Data topics and payloads;
- `/contracts/schemas` for Profile, event, command, state, permission, and error definitions;
- `/contracts/examples` for normal, failure, retry, and takeover payloads;
- `/generated-clients` or CI release artifacts for Kotlin, Python, and TypeScript consumers;
- `/postgres/migrations` for hot-path transactional tables;
- `/postgres/seeds` and versioned test datasets.

The OpenAPI definition includes the externally callable LiveKit webhook endpoint even though its authentication scheme is LiveKit signature verification rather than an Aida user token.

This is not a separate Contracts or Data service. AidaControl implements the runtime interfaces and exclusively owns Postgres. For the POC, AidaAdmin's server owns configuration writes and accesses NocoDB directly with a server-only credential; AidaControl reads that configuration for call bootstrap. Browser code and every other repository access neither NocoDB nor Postgres directly.

Postgres is exclusive to AidaControl and stores the live transactional path: `call_session`, `call_event`, and `control_command`. AidaControl uses database transactions, row-level locking, unique idempotency constraints, optimistic state versions, and per-call ordered event allocation to implement first-command-wins semantics safely.

NocoDB stores slow-moving, human-edited configuration: tenants, UID-to-tenant role mappings, extensions, ring groups/members, profiles, inbound routes, devices/bindings, singleton appearance settings, CRM import records, per-field configuration-source metadata, and related audit/configuration metadata. AidaAdmin's server writes it and AidaControl reads it using separate environment-supplied API credentials. The existing NocoDB instance is MySQL-backed, but clients use only the NocoDB API and avoid backend-specific SQL behavior.

AidaControl unit tests cover all legal/illegal state transitions, route resolution, profile pinning, tenant isolation, permissions, concurrent takeover races, duplicate idempotency keys, ordered sequence allocation, schema/example validation, generated-client compilation, and contract compatibility. Integration tests run against actual Postgres and NocoDB instances populated with versioned test records. POC acceptance uses the real configured OfficePulse, LiveKit Cloud, Pusher, identity, NocoDB, and handset integrations; an isolated substitute never satisfies an integration or acceptance gate.

### 5.2 `AidaAgent`

LiveKit worker for STT, reasoning, TTS, and approved tools.

Responsibilities:

- join only the assigned room with a short-lived token;
- retrieve the pinned Profile Version;
- enforce prompt, voice, model, disclosure, interruption, safety, and tool policies;
- publish transcript and speech lifecycle events;
- accept typed guidance and graceful-leave commands;
- accept no new caller turn after human answer;
- finish only the current utterance during handoff;
- terminate at the supplied deadline.

Unit tests may isolate provider interfaces while covering profile validation, template rendering, transcripts, tool allowlists/timeouts, no-new-turn behavior, normal drain, and forced drain. Integration and POC acceptance tests dispatch the deployed `aida-prime` agent through LiveKit Cloud and use its configured STT/LLM/TTS services. Provider-backed test runs are required before a release is accepted.

LiveKit Cloud and the already functioning OfficePulse-to-LiveKit SIP trunk are the POC media path. Asterisk passes custom `X-Aida-*` SIP headers. The POC headers are `X-Aida-Call-Session` and `X-Aida-Route-Token`; the route token is opaque, short-lived, single-call, and validated by AidaControl.

The POC dispatches the predefined LiveKit Cloud agent **`aida-prime`**, agent ID **`CA_Lbh5CTq2Rxhd`**. Its LiveKit-managed STT/LLM/TTS/model defaults—including the currently intended Gemma-family model—remain inherited and are not sent by AidaControl. Per-session dispatch metadata contains only allowlisted dynamic settings, initially the pinned prompt/business context, call identifiers, behavior/tool overrides explicitly supported by the contract, and locale. An omitted override always means “use the predefined LiveKit agent default.”

Caller barge-in is enabled during ordinary screening. AidaAgent/LiveKit speech handling monitors caller voice activity while TTS is playing, cancels or attenuates the current agent playout according to the configured interruption threshold, and starts the caller turn. Once the destination answers, AidaAgent sets `acceptNewTurns=false`; caller speech can no longer interrupt the transfer statement, which is allowed to finish until the drain deadline.

### 5.3 `OfficePulseAidaIntegration`

Companion service and managed configuration layered onto the existing OfficePulse server. It does not fork, rebuild, or modify Asterisk source code. Its TypeScript/Node.js service runs on `LSAidaOffice01` and reaches Asterisk across the private LAN. It is addressed as OfficePulse API at `officepulse-api.localsplash.ai`.

Responsibilities:

- listen for FastAGI on the private LAN and translate `/bootstrap` into AidaControl's authenticated call-bootstrap request;
- expose the private extension, ring-group, DID, and SIP-secret provisioning API used by AidaAdmin;
- write Asterisk 22.10.1 Realtime `ps_endpoints`, `ps_auths`, `ps_aors`, and `extensions` rows;
- own ARI/Stasis connectivity and reconciliation;
- receive calls from a stable Aida dialplan context;
- manage caller, Aida media, and destination channels/bridges;
- originate typed destinations;
- report ringing, answer, failure, bridge, and hangup events;
- execute idempotent Control Plane commands;
- enforce local handoff/cleanup safety deadlines;
- optionally validate/deploy managed Asterisk includes.

Unit tests cover ARI event handling, reconnect, duplicates, bridge membership, busy/reject/no-answer/answer, and forced Aida removal without dropping the human bridge. Integration and POC acceptance tests use the actual OfficePulse Asterisk 22.10.1, ARI, Realtime MySQL, FastAGI service, managed dialplan, and provisioned endpoints.

The repository contains the companion ARI/Stasis service, a versioned `aida.conf` or `aida-managed.conf` dialplan include, required `extensions.conf` include instructions, ARI account configuration template, local audio assets, codec conversion/deployment scripts, system-service/container definition, firewall guidance, and validation/rollback scripts. Existing OfficePulse configuration is changed only through explicit includes and documented settings.

### 5.4 `AidaAdmin` (repository: `localsplash/new_AidaAdmin`)

Responsive tenant/staff application at `app.aida.localsplash.ai`.

It manages tenants, UID-to-tenant roles, extensions, ring groups, profiles, routes, devices, retention, platform appearance settings, and permitted call views. For the POC its server writes NocoDB directly and invokes OfficePulseAidaIntegration's private provisioning API; browser code receives neither credential. It never accesses ARI or Asterisk MySQL directly. AidaControl is not in the POC configuration-write path.

AidaAdmin authenticates its users against the LocalSplash identity service (`id`, at `id.localsplash.ai`) using the flow in §13 and holds its own persistent session. For runtime call views and commands, its backend calls AidaControl from an allowlisted server CIDR and supplies verified user/tenant/role/session context. It keeps no password store and issues no AidaControl staff JWT in the POC.

Unit and component tests cover accessibility, keyboard navigation, validation/conflict/forbidden states, draft/publish/rollback, CRM override/reset, staff tenant context, and cross-tenant leakage. POC browser acceptance runs against the deployed `id`, NocoDB, AidaControl, and OfficePulse integration services with dedicated non-production records.

### 5.5 `AidaHandset`

Android 11 application for Grandstream GXV3450.

Responsibilities:

- device/user enrollment and authentication;
- server-authorized device-to-SIP-destination binding;
- Pusher notification and LiveKit data-room subscription/recovery;
- active-call, transcript, suggestion, and command-progress display;
- idempotent Take over and later guided controls;
- recovery after app pause, network loss, and process restart.

Unit tests cover reducers/ViewModels, ordering/duplicates/gaps/replay, takeover debounce/idempotency, token expiry, forbidden calls, notification handling, and UI states. Device acceptance uses the actual Grandstream GXV3450, provisioning service, Pusher channel, LiveKit Cloud room, and OfficePulse extension.

The APK does not answer the SIP call. The Grandstream SIP application/endpoint answers; AidaHandset observes the server event. For the POC, the existing HTTPS provisioning service supplies the handset MAC address and enrollment bootstrap data. AidaControl validates the MAC-to-device/extension binding from NocoDB, consumes the one-time enrollment credential, and issues a revocable device credential. Android does not attempt to read a restricted hardware MAC address, and the raw Asterisk SIP secret never becomes an Aida credential. SIP secrets are never stored in NocoDB, Pusher payloads, or ordinary APK preferences.

### 5.6 `AidaInfrastructureSetupInstructions`

Documentation-and-automation repository rather than an application service. It is the operator's single setup guide across all projects.

It contains:

- dependency/version matrix and supported deployment topology;
- complete environment-variable, CIDR, and secret inventory, including Postgres, LiveKit API key/secret, predefined LiveKit agent ID, Pusher, NocoDB, `ID_TRUSTED_APP_CIDRS`, `ID_EVENT_SOURCE_CIDRS`, `AIDACONTROL_TRUSTED_SERVER_CIDRS`, trusted-proxy CIDRs, Firebase if used, CRM when enabled (`CRM_IMPORT_ENABLED` is pinned `false` for the POC in every deployment configuration, not left to a code default), and OfficePulse service credentials;
- public wildcard and private OfficePulse DNS, TLS, firewall, mTLS, and ingress instructions;
- Docker Compose orchestration referencing released project images;
- scripts that run AidaControl's Postgres migrations and invoke AidaAdmin's NocoDB schema commands to create, validate, and seed the configuration base;
- `id` client registration and configuration instructions for AidaAdmin;
- OfficePulse integration installation order and verification;
- health-check, smoke-test, backup, restore, upgrade, and rollback runbooks;
- LiveKit Cloud webhook creation, signing-key selection, test-delivery, rotation, and troubleshooting instructions;
- staging and production checklists with placeholders for site-specific values.

It does not duplicate application source or own data/API contracts. Its tests validate configuration files, required settings, scripts, TLS/hostname routing, absence of public ARI routes, connectivity to the configured providers, and backup/restore commands.

There is no AidaSystemTest repository in the initial design. Every source repository owns its unit, contract, integration, and component tests. `AidaInfrastructureSetupInstructions` contains a cross-project deployment smoke test that verifies health and completes one real non-production telephone call through OfficePulse, LiveKit Cloud, Pusher, and a provisioned handset; richer system testing may be designed later if actual operational needs justify it.

## 6. Core data model

### 6.1 Tenants and external references

- `tenant`: UUID, status, display name, timestamps.
- `tenant_user`: tenant (nullable only for platform Super Admin), shared `id_db.id_tbl_User.iUserId`, Aida role, enabled state, timestamps; unique by tenant/user.
- `tenant_external_reference`: tenant, system (`localsplash_crm`), external ID, metadata; unique by system/external ID.
- `platform_appearance`: singleton POC settings for brand name, agent display name, colors, uploaded logo/icon references, and support/legal URLs.

`id_db.id_tbl_User.iUserId` is the shared person identifier. Aida does not duplicate name, email, password, or provider identity. Aida's `tenant_user` is only the UID-to-tenant authorization mapping. There is deliberately no separate `uisp` system value: UISP sign-in flows through `id`, and `iUserId` supersedes a direct UISP linkage.

### 6.2 Profiles and inherited configuration

- `assistant_profile`: tenant, name, status, published version, revision.
- `assistant_profile_version`: profile, increasing number, immutable JSON, schema version, checksum, publisher/time.
- `profile_draft`: editable JSON, revision, editor/time.

Effective values resolve in this order:

1. explicit Aida override;
2. LocalSplash CRM imported default;
3. Aida platform default.

Publishing materializes the entire effective configuration into an immutable Profile Version. CRM changes never mutate a published version or active call. An administrator may override a field or clear its override to resume inheritance on a later draft.

The POC locale is fixed to English (`en-US`). Profile configuration includes English prompt assets and per-session prompt/business/behavior settings, but does not duplicate or transmit the predefined LiveKit agent's base model/STT/TTS configuration. The schema should remain evolvable so explicitly approved overrides and additional locales can be added later without changing call identifiers or API shapes.

### 6.3 NocoDB configuration records

- `extension`: tenant, optional shared identity UID, extension number, context, display/caller-ID settings, provisioning profile, enabled.
- `ring_group`: tenant, virtual extension, context, `RING_ALL` strategy, timeout, music-on-hold class, caller-ID settings, enabled.
- `ring_group_member`: ring group, extension, sort order, enabled.
- `inbound_route`: tenant, DID, profile, typed `EXTENSION` or `RING_GROUP` destination, failure policy, OfficePulse node, enabled, revision.
- `device`: tenant, label, platform, credential/public-key reference, enabled, last seen.
- `device_destination_binding`: device, optional user, node, destination type/value, permissions.
- `configuration_source`: tenant, target type/ID, field path, source system, external record ID/version, imported normalized value JSON, source-updated time, import time, API overwrite policy, and latest import result; unique on the applicable target/field/source tuple.
- `audit_event`: tenant, actor, action, target, correlation, before/after references, timestamp.

### 6.4 Postgres transactional records

- `call_session`: call ID, tenant/route/profile-version references, Asterisk references, LiveKit room name, stable agent participant identity, current agent participant SID, caller/called numbers, state, `state_version`, next event sequence, timestamps, terminal reason.
- `call_event`: call ID, per-call sequence allocated transactionally, globally unique event ID, type, actor, payload, timestamp; unique on `(call_session_id, sequence)`.
- `control_command`: command ID, call ID, idempotency key, expected call version, actor user/device, type, payload, status/result, timestamps; unique on the applicable actor/call/idempotency scope.

The first valid takeover is accepted by locking the Call Session row, verifying `expectedCallVersion`, inserting the idempotent command, changing state/version, and allocating its event sequence in one transaction. Competing commands return the already accepted command or a stable conflict without producing another originate operation.

Secrets are secret-manager references. Partial and final transcripts are live-only in the POC. Aida retains only the minimum in-memory buffer needed to recover a live connection; it offers no historical transcript retrieval. Historical conversations are marked “Coming soon.” LiveKit's post-session transcript email remains an external stop-gap and is not ingested into Aida.

## 7. Assistant Profile schema

The versioned schema covers:

- identity, disclosure, locale, timezone, pronunciation, and greeting;
- system prompt and safe template variables;
- prompt, business context, interruption/behavior settings, and only those LiveKit agent overrides explicitly allowed for per-session dispatch;
- business facts/hours and information-gathering goals;
- tool allowlist, input schemas, secret references, timeouts, and retries;
- suggestions and escalation/takeover language;
- handoff drain deadline, default 10 seconds and platform-bounded;
- transcript, recording, redaction, consent, and retention;
- safety and prohibited actions.

Unknown schema versions are rejected. Raw API secrets are prohibited. Every call uses one pinned version for its duration.

The POC supports English (`en-US`) only. The locale is attached to the Call Session and selects the English prompt, STT, LLM instruction, and TTS voice preset. Additional languages are future work.

## 8. Call state and behavior

Canonical states:

`RECEIVED → RESOLVING → AIDA_CONNECTING → AIDA_ACTIVE → TAKEOVER_REQUESTED → DESTINATION_RINGING → DESTINATION_ANSWERED → AIDA_DRAINING → HUMAN_ACTIVE → TERMINATING → ENDED`

AidaControl owns canonical state/version. Asterisk bridge membership is authoritative for actual media participation. Stable terminal reasons include route/profile unavailable, LiveKit/agent failure, busy, rejected, no-answer, caller/destination hangup, forced drain, and timeout.

### 8.1 Screening

1. OfficePulse receives the DID, answers according to existing inbound policy, and starts its normal call recording.
2. OfficePulse always plays the locally stored disclosure: “Calls are recorded.”
3. OfficePulse enters the Aida Stasis context.
4. The OfficePulseAidaIntegration service creates `callSessionId` and bootstraps AidaControl with DID, caller ID, linked ID, node ID, `en-US` locale, and authenticated request data.
5. AidaControl resolves the route, pins a published Profile Version, creates the Call Session, and returns disposition/LiveKit instructions.
6. OfficePulse adds the custom Aida SIP correlation headers and retains the caller while bridging it to the Aida media leg through the existing LiveKit trunk.
7. AidaAgent acknowledges readiness and conducts screening in English.
8. Events are published to authorized handsets; transcript text is live-only for the POC.
9. Bootstrap failure invokes the configured direct-to-extension fallback.

### 8.2 Take over

```http
POST /v1/calls/{callSessionId}/commands
Authorization: Bearer <access-token>
Idempotency-Key: <uuid>
Content-Type: application/json

{"type":"takeover","expectedCallVersion":12}
```

The API returns `202 Accepted` with `commandId`. The same idempotency key returns the original result.

1. AidaControl atomically accepts the first authorized command.
2. AidaAgent stops new questions and starts the configured transfer statement.
3. In parallel, the OfficePulseAidaIntegration service originates the destination and reports ringing.
4. Before answer, the caller remains connected to Aida through completion of the transfer statement. If ringing continues after the statement, OfficePulse mutes/parks the Aida media leg and supplies the configured hold treatment until answer or timeout.
5. On answer, the OfficePulseAidaIntegration service immediately joins the human and blocks Aida from receiving another caller turn.
6. AidaControl sends `graceful_leave` with `finishCurrentUtterance=true`, `acceptNewTurns=false`, and a deadline of `answeredAt + 10 seconds` by default.
7. Aida finishes only the utterance in progress and acknowledges speech/leave completion.
8. The OfficePulseAidaIntegration service removes Aida after acknowledgement or forcibly at the deadline.
9. The caller-human bridge remains active regardless of Aida/LiveKit cleanup.
10. The session ends when OfficePulse reports final telephone hangup.

Ringing does not wait for the transfer statement. Aida is not removed merely because ringing begins. The POC destination is the one PJSIP endpoint associated with the extension enrolled on that Grandstream handset. The default ring timeout is 20 seconds. Once Aida's transfer statement finishes, any remaining ring time uses a platform-default hold treatment, which the organization may replace with an approved audio asset. If the endpoint is busy, rejects, or times out, OfficePulse stops the hold treatment, restores Aida's media, and Aida apologizes that the transfer failed and offers to take a message. The state returns to `AIDA_ACTIVE` in message-taking mode.

Failed transfer attempts emit a durable `transfer.failed` operational event containing call ID, tenant, destination reference, reason code, attempt time, and whether Aida resumed. The POC does not send a separate alert or escalation notification. AidaAdmin exposes these events in an error/event log so customizable alert policies can be added later. Transcript email remains LiveKit's independent behavior.

### 8.3 Guided controls

Suggestions contain an ID, label, typed action, constrained parameters, expiry, and expected call version. Handsets select suggestions; arbitrary prompt text is disabled by default. Invalid, stale, expired, consumed, or unauthorized suggestions have no side effects.

## 9. Realtime delivery and Pusher

The LiveKit Data contract is defined in `new_AidaControl/contracts/asyncapi` and is normative for AidaControl, AidaAgent, and AidaHandset. Payloads use UTF-8 JSON. A durable AidaControl event has this envelope:

```json
{
  "eventId":"uuid",
  "callSessionId":"uuid",
  "sequence":42,
  "producer":"aida-control",
  "type":"call.state",
  "occurredAt":"2026-08-23T12:00:00Z",
  "actor":"caller",
  "payload":{}
}
```

### 9.1 Publishers and transport

- **AidaControl → room:** AidaControl uses the LiveKit server SDK `RoomServiceClient.sendData()` authenticated by its LiveKit API key/secret workload credential. It never joins the room as a participant. It targets the current AidaAgent participant SID for agent-only commands and omits `destinationSids` for broadcasts intended for all data participants.
- **AidaAgent → room:** AidaAgent publishes transcript and speech-lifecycle payloads through its existing joined participant connection.
- **AidaHandset ← room:** each call tab joins as a data-only participant, publishes no media, and receives the applicable topics over the room data channel.

The LiveKit API secret exists only in AidaControl's secret store. It is never sent through NocoDB, Pusher, a Profile, the handset, or room metadata.

Implementation reference: [LiveKit JavaScript `RoomServiceClient`](https://docs.livekit.io/reference/server-sdk-js/classes/RoomServiceClient.html). The equivalent server RPC is also documented in the [LiveKit Go server SDK](https://pkg.go.dev/github.com/livekit/server-sdk-go).

### 9.2 Required topic names

| Topic | Producer | Audience | Delivery | Purpose |
|---|---|---|---|---|
| `aida.command.graceful_leave` | AidaControl | Targeted AidaAgent SID | Reliable | Finish current utterance, reject new turns, leave by deadline |
| `aida.command.guide` | AidaControl | Targeted AidaAgent SID | Reliable | Apply an authorized structured conversation action |
| `aida.event.call_state` | AidaControl | Broadcast | Reliable | Canonical call-state/version update |
| `aida.event.command_status` | AidaControl | Broadcast | Reliable | Control acceptance, progress, completion, or failure |
| `aida.event.suggestion` | Producer fixed by its message schema | Broadcast | Reliable | Typed handset suggestion |
| `aida.event.transcript.partial` | AidaAgent | Broadcast | Lossy | Ephemeral partial transcript |
| `aida.event.transcript.final` | AidaAgent | Broadcast | Reliable | Live final transcript; not historically stored in the POC |
| `aida.event.speech_lifecycle` | AidaAgent | Broadcast | Reliable | Speech started/finished and agent drain acknowledgements |
| `aida.event.agent_ready` | AidaAgent | Broadcast | Reliable | Stable agent identity and current participant SID |

Topic strings, payload schema references, producer, allowed audience, delivery kind/reliability choice, maximum payload size, and versioning rules are explicit AsyncAPI fields. Consumers filter on topics and still validate every payload.

### 9.3 LiveKit webhook receiver

AidaControl exposes exactly one LiveKit Cloud callback:

```http
POST https://api.aida.localsplash.ai/v1/integrations/livekit/webhooks
Content-Type: application/webhook+json
Authorization: <LiveKit-signed JWT>
```

This route is publicly reachable through the existing Aida API ingress because LiveKit Cloud must call it. It does not accept Aida browser sessions, handset tokens, cookies, or CSRF credentials. The ingress permits `POST` only, imposes a conservative body-size limit, preserves the `Authorization` header, and passes the request body to AidaControl byte-for-byte without JSON parsing or transformation.

AidaControl uses the Node `livekit-server-sdk` `WebhookReceiver` with a dedicated signing API key and secret. It passes the raw posted body and complete `Authorization` header to `WebhookReceiver.receive()`. Verification must remain enabled: the signed JWT and its SHA-256 body hash must validate before the JSON event is trusted or processed. Invalid/missing signatures, changed bodies, unsupported content types, excessive bodies, and unknown projects are rejected without side effects.

The required POC webhook events are `participant_joined`, `participant_left`, `participant_connection_aborted`, `room_started`, and `room_finished`. AidaControl validates that the room maps to an active Call Session and that an agent participant has the stable identity expected for `aida-prime`. For an agent `participant_joined`, it transactionally updates the current participant SID. Departure/abort clears that SID only if it still matches the departing SID, preventing a delayed webhook from clearing a newer reconnect.

LiveKit webhook `id` is the deduplication key. AidaControl records processed webhook IDs or their resulting external event IDs under a unique Postgres constraint. A retry returns success without repeating side effects. The handler acknowledges accepted deliveries promptly and processes state changes transactionally. Because LiveKit webhooks are retried but not guaranteed indefinitely, `RoomServiceClient.listParticipants()` remains the reconciliation fallback before a targeted `sendData()` command.

Configuration variables are:

- `LIVEKIT_WEBHOOK_URL=https://api.aida.localsplash.ai/v1/integrations/livekit/webhooks` for setup/documentation;
- `LIVEKIT_WEBHOOK_API_KEY` for the Signing API key selected in LiveKit Cloud;
- `LIVEKIT_WEBHOOK_API_SECRET` for verification, stored only in AidaControl's secret store.

These webhook credentials may be distinct from AidaControl's `sendData()` workload key and should be separate when LiveKit key management permits. Rotation supports an overlap window in which the current and next signing keys can both verify deliveries.

In LiveKit Cloud, the operator opens **Settings → Webhooks**, creates a webhook named `AidaControl`, enters the callback URL above, selects the signing API key, saves it, and sends a test event. `AidaInfrastructureSetupInstructions` verifies public TLS reachability, raw-body handling, signature validation, test-event receipt, duplicate delivery behavior, and Postgres persistence. See the [LiveKit webhook configuration and verification documentation](https://docs.livekit.io/intro/basics/rooms-participants-tracks/webhooks-events/) and [JavaScript `WebhookReceiver`](https://docs.livekit.io/reference/server-sdk-js/classes/WebhookReceiver.html).

### 9.4 Agent participant SID lifecycle

The LiveKit participant SID is not available merely because a token was created or an agent was dispatched. After joining, AidaAgent publishes `aida.event.agent_ready` for room participants. Independently, AidaControl receives and verifies LiveKit's participant-joined webhook (or queries `RoomServiceClient.listParticipants()` by stable agent identity) and stores the identity/current SID on the Postgres Call Session. AidaControl does not need to join the room or consume its data channel to learn the SID.

Agent-only delivery resolves `destinationSids` from that stored current SID. If no ready SID exists, delivery waits/retries within the command deadline. If the agent reconnects, its SID may change; the new ready/webhook event replaces the stored SID transactionally. Before retrying a failed targeted command, AidaControl may resolve the stable identity through LiveKit room participant lookup and update the SID. Stale SIDs are never assumed valid for the life of the call.

### 9.5 Ordering, deduplication, and replay

AidaControl-published call and command events use the durable Postgres per-call `sequence`. The handset ignores duplicate `eventId` values, detects Control Plane sequence gaps, and replays those durable events with `GET /v1/calls/{id}/events?afterSequence=41`.

AidaAgent transcript events do not share the Postgres sequence because they are published directly and are not stored historically. They carry `producer="aida-agent"`, stable agent identity, participant SID, and a monotonically increasing `streamSequence` for the current agent connection. A reconnect starts a new participant SID/stream epoch. The handset tracks transcript order by `(participantSid, streamSequence)`, ignores duplicates, and marks unrecoverable live transcript gaps rather than requesting historical transcript data that does not exist.

Pusher is the POC notification layer, not the transcript stream. A device subscribes to a private device channel authorized by AidaControl. A call-arrival payload contains only `eventId`, `callSessionId`, event type, and timestamp—never a DID, transcript, prompt, SIP secret, or LiveKit token.

On notification, AidaHandset requests `GET /v1/calls/{callSessionId}`. AidaControl verifies the device/extension binding and returns permitted call details plus a short-lived, data-only LiveKit token. The handset joins that call's LiveKit room without publishing or subscribing to audio and receives transcript/control events over LiveKit data.

Each simultaneous call has its own tab, state reducer, LiveKit data connection, sequence cursor, and command state. On startup and reconnect, the app also calls `GET /v1/calls?status=active&assignedToDevice=true`, so a missed Pusher notification cannot hide an active call.

Pusher may send low-rate state hints, but the app re-fetches authoritative details. FCM may be used only if required for reliable Android background wake; it carries no sensitive content or reusable token. LiveKit Data is the specified transcript/control stream.

Pusher private-channel authorization is served by AidaControl at `POST /v1/realtime/pusher/auth`. The handset authenticates with its device bearer token and may subscribe only to `private-aida-device-{deviceId}` for its own device ID. Channel names contain no tenant ID, extension, DID, or caller data.

## 10. OfficePulse/Asterisk integration

### 10.1 Stable dialplan

Routine DID/profile/destination changes do not rewrite `extensions.conf`. Asterisk Realtime contains the managed DID entry, which invokes OfficePulseAidaIntegration over FastAGI. AidaControl resolves the data-driven route and prewarms `aida-prime`; the dialplan then connects the caller to the returned LiveKit SIP destination.

```asterisk
[from-provider]
exten => _X!,1,NoOp(Aida inbound ${CALLERID(num)} -> ${EXTEN})
 same => n,Set(CHANNEL(hangup_handler_push)=aida-hangup,s,1)
 same => n,Playback(aida/calls-are-recorded)
 same => n,AGI(agi://aida-integration.internal:4573/bootstrap)
 same => n,GotoIf($["${AIDA_DISPOSITION}"="SCREEN"]?screen:fallback)
 same => n(screen),Dial(PJSIP/${AIDA_SIP_DESTINATION}@livekit)
 same => n,Hangup()
 same => n(fallback),Playback(aida/circuits-are-busy)
 same => n,Goto(${AIDA_FALLBACK_CONTEXT},${AIDA_FALLBACK_EXTENSION},1)
 same => n,Hangup()

[aida-hangup]
exten => s,1,NoOp(Aida cleanup)
 same => n,Return()
```

The OfficePulseAidaIntegration service must adapt the final variables, header injection, and fallback flow to the installed trunk and modules. FastAGI is a private TCP connection; Asterisk does not call AidaControl or any public HTTP endpoint directly.

### 10.2 ARI/bridge rules

- Dedicated least-privilege ARI account and Stasis application.
- Only the OfficePulseAidaIntegration service holds ARI credentials.
- `callSessionId` is applied to related channels; `linkedid` remains diagnostic.
- Originate, bridge membership, removal, and termination are idempotent.
- The OfficePulseAidaIntegration service reconciles active resources after restart.
- A local deadline removes Aida after human answer if AidaControl is unreachable.
- That deadline can remove only Aida, never the caller-human bridge.

### 10.3 Realtime provisioning

AidaAdmin's server calls OfficePulseAidaIntegration's private typed provisioning endpoints. OfficePulseAidaIntegration validates the desired extension, ring group, or DID and writes the installed Asterisk 22.10.1 Realtime tables. It generates SIP secrets, stores them only in `ps_auths`, and returns a new secret once. The POC has no sync or reconciliation job; a failed write is returned immediately and a later operational discrepancy is a runtime error.

### 10.4 Local failure announcements

OfficePulse stores pre-rendered English audio assets locally so entry and fallback behavior work without LiveKit or AidaControl:

- recording disclosure: “Calls are recorded.”;
- caller failure prompt: Aida service is temporarily unavailable and the call will be routed directly;
- extension failure prompt: Aida screening was unavailable for this call.

These are project-owned recordings, not assumed Asterisk built-ins. `OfficePulseAidaIntegration` includes source WAV files and a deployment step that produces the codec/sample-rate variants required by the installed Asterisk channels (at minimum the site's negotiated narrowband format). OfficePulse always plays the normal recording disclosure first. If Aida is unavailable, it then plays the caller “circuits are busy” prompt, originates the configured extension, plays the extension-facing incident prompt after answer, and bridges the parties. Prompt version/checksum and deployment validation are documented in `AidaInfrastructureSetupInstructions`.

## 11. API boundaries

### 11.1 Public API at `api.aida.localsplash.ai`

- device enrollment;
- active/recent calls, replay, and commands;
- Pusher/realtime authorization;
- permitted operational call views;
- `POST /v1/integrations/livekit/webhooks`, authenticated exclusively by LiveKit's signed webhook JWT and raw-body hash verification.

Profiles, tenants, users, extensions, ring groups, routes, appearance, and CRM configuration APIs are not AidaControl endpoints in the POC. AidaAdmin supplies its own same-origin administration routes, writes NocoDB server-side, and invokes the private provisioning API. Handsets use short-lived tokens with revocation.

AidaAdmin's identity integration adds two endpoints of its own — the `POST /id/events` revocation-webhook receiver and the boot-time `GET /api/events?since=` catch-up client (§13) — and both belong to AidaAdmin's surface, not AidaControl's public API.

The LiveKit webhook route is the sole exception to Aida user/workload-token authentication on the public API. It accepts only `application/webhook+json`, preserves the raw body and `Authorization` header for `WebhookReceiver`, performs no CSRF check, and applies the verification, deduplication, and event rules in §9.3.

### 11.2 Private API at `officepulse-api.localsplash.ai`

- FastAGI `agi://aida-integration.internal:4573/bootstrap`
- `POST /v1/provisioning/extensions`
- `PUT /v1/provisioning/extensions/{extensionId}`
- `POST /v1/provisioning/extensions/{extensionId}/rotate-secret`
- `PUT /v1/provisioning/ring-groups/{ringGroupId}`
- `PUT /v1/provisioning/dids/{didRouteId}`
- `POST /internal/v1/calls/{id}/events`
- `POST /internal/v1/calls/{id}/commands/originate`
- `POST /internal/v1/calls/{id}/commands/remove-aida`

Use mTLS and scoped workload credentials. Requests include timestamp, nonce/idempotency key, and correlation ID. Browser cookies and handset tokens are invalid here.

LiveKit tokens are short-lived and room/identity scoped. Handsets join as data-only participants and neither publish nor subscribe to media tracks. Prompts, secrets, PII, and reusable credentials are excluded from token metadata.

## 12. Administration

Tenant administrators manage DIDs, profiles, destinations, failover, ring timeout, devices, retention, versions, and permitted call views. They see CRM imported values separately from effective overrides. Only a platform administrator manages the singleton platform appearance settings.

Route validation confirms normalized/unique DID, published profile, OfficePulse node reachability, and destination existence. Publishing creates an immutable version; active calls retain their pinned version.

Staff administration uses a separately initiated short-lived privileged session, explicit tenant selection, a persistent context banner, and full audit. Staff permission derives from a verified role/group or explicit allowlist—not an unverified email suffix.

## 13. Identity integration (`id`)

Identity for the Aida Voice Platform is the in-scope LocalSplash identity service, **`id`**, at `id.localsplash.ai` on the apex `localsplash.ai` domain. `id` owns shared people in `id_db.id_tbl_User`, provider identities, sign-in (Google, Microsoft, UISP), sessions, and revocation. Aida owns tenants and stores only `iUserId`-to-tenant role mappings; no Aida component keeps a second person, password, name, email, or provider-identity record.

### 13.1 AidaAdmin ↔ `id`

- **Registration.** AidaAdmin registers itself with `id` on boot as a client application, supplying its callback and webhook URLs. Registration is idempotent: a restart re-asserts the same registration rather than creating a new one.
- **Sign-in.** AidaAdmin sends the browser to `id`'s `/authorize`, receives an authorization code on its callback, and redeems it with `POST /api/token`. AidaAdmin then holds a persistent session for the user; `id` is not consulted on every request.
- **Shared UID.** The token response supplies `user.iUserId`, `email`, `displayName`, and `superAdmin`. AidaAdmin uses `iUserId` to resolve `tenant_user`. `superAdmin=true` permits a platform session without a tenant mapping; any other user must already have an enabled tenant mapping.
- **Revocation, two paths that must both exist.** `id` pushes revocation and identity-change events to AidaAdmin's `POST /id/events` webhook receiver. Because a webhook can be missed while AidaAdmin is down, AidaAdmin also calls `id`'s `GET /api/events?since=<cursor>` on boot to catch up on anything delivered while it was away, then resumes webhook consumption. A revoked user's AidaAdmin session is invalidated immediately and can no longer proxy AidaControl operations.
- These two endpoints — the webhook receiver and the catch-up client — belong to **AidaAdmin's** surface, not AidaControl's public API (§11.1).

The `id` application handoff remains generic for configured `PARENT_DOMAIN`
(`X.TLD`); `localsplash.ai` is the POC deployment value rather than a protocol
constant. For the POC, server-to-server `id` trust uses TLS plus IPv4/CIDR
allowlists and no application shared secret or webhook HMAC. `id` protects
token redemption, application registration, event catch-up, and user-directory
routes with `ID_TRUSTED_APP_CIDRS`; AidaAdmin protects `/id/events` with
`ID_EVENT_SOURCE_CIDRS`. Both ingress and application code enforce the policy.
Forwarded client addresses are honored only from `ID_TRUSTED_PROXY_CIDRS`.
This authenticates a controlled first-party server/network, not an individual
application process, and is not sufficient for unrelated customer-hosted apps.

### 13.2 AidaAdmin configuration and AidaControl authorization

For the POC, AidaAdmin's server writes configuration to NocoDB directly and calls OfficePulseAidaIntegration's private provisioning API. Its NocoDB token and provisioning credential never enter browser code. AidaControl reads configuration during call bootstrap and is not in the configuration-write path.

For runtime call views and commands, the browser calls AidaAdmin only.
AidaAdmin resolves the current `id` user, selected tenant, Aida role, and session,
then proxies an allowlisted operation to AidaControl from a source IPv4 in
`AIDACONTROL_TRUSTED_SERVER_CIDRS`. It sends trusted `X-Aida-*` context headers
and strips any such headers supplied by the browser. AidaControl honors them
only on CIDR-trusted connections and still enforces tenant, role, call, and
command authorization. No `STAFF_TOKEN_SECRET`, shared application secret, or
self-issued AidaAdmin staff JWT exists in the POC.

This CIDR mode applies only to controlled server traffic. AidaHandset requires
its device token, LiveKit webhooks require LiveKit signature verification, and
AidaAgent requires a one-time call-scoped credential; none of those callers can
gain trust from an allowlisted server CIDR.

### 13.3 Tenancy and data boundaries

- Aida owns `tenantId`. A `tenant_user` record maps the shared identity `iUserId` to that tenant and an Aida role. The shared UID is a foreign identifier, not an Aida person record.
- Echo's SMS business-phone table is not Aida voice routing. It may seed suggested DIDs with source references, but Aida supports multiple DIDs and owns voice configuration. A selected business number in any UI is context, not sufficient authorization.

## 14. LocalSplash CRM integration

The CRM adapter imports versioned defaults such as business name, location, timezone, hours, inbound numbers, destination, greeting facts, services, and contacts. It does not change the POC platform brand.

Each field records source system, external record/version, source/import times, and normalized value. The future integration is push-based: LocalSplash calls an authenticated, idempotent AidaControl endpoint. CRM is not wired into the initial POC; administrators enter the same values in AidaAdmin.

Every configurable field or logical configuration group carries an API update policy: `allowApiOverwrite` or `protectLocalOverride`. AidaAdmin visibly warns when the most recent value came from an API push and shows its source/time. With overwrite allowed, a later CRM push updates the draft/default layer; with protection enabled, the push is recorded as pending/ignored and does not change the effective value. No push mutates a published Profile Version or active Call Session.

Imports are idempotent and support preview. Missing/malformed values create warnings and use platform defaults; they do not erase working configuration.

## 15. POC appearance and future white-labeling

The POC has one Aida platform brand across all organizations. It does not support reseller brands, organization-specific application skins, custom domains, separate APK identities, or separate Firebase projects.

AidaAdmin provides a simple settings page for the single platform brand:

- product and agent display names;
- primary/secondary colors;
- support and legal URLs;
- logo, icon, and related image upload.

Uploaded files are validated for allowed type and size, assigned opaque names, and stored by the Aida deployment. They are served through the existing application origin under `https://app.aida.localsplash.ai/brand-assets/...`; no additional asset hostname or DNS record is required. AidaAdmin stores the settings and asset references in NocoDB and never accepts an arbitrary executable or remote asset URL as an upload substitute.

Organization-specific white-labeling is deferred until after consultation. The data/API design may avoid choices that make future multi-brand support impossible, but no multi-brand UI, routing, custom-domain resolution, or reseller behavior is implemented or tested in the POC.

## 16. Security, reliability, and observability

- The POC Aida-unavailable behavior is deterministic: OfficePulse first plays the normal recording disclosure, then a caller-facing “circuits are busy” prompt, rings the configured extension, and after answer plays a brief extension-facing incident prompt before joining caller and extension. If the extension does not answer, normal OfficePulse no-answer handling applies.
- Public/private ingress and all provider credentials are separately scoped and rotated.
- Operational logs use call IDs and redact phone numbers/transcripts.
- Profile, route, device, CRM import, staff context, transcript access, and command actions are audited.
- OfficePulse records every inbound POC call and plays the recording disclosure before Aida. Recording retention, access, deletion, export, and jurisdiction-specific consent remain OfficePulse/tenant policies subject to legal review.
- Reconciliation detects orphan rooms/channels, incomplete commands, and missing terminal events.
- Metrics include bootstrap/first-audio/transcript latency, takeover-to-ring/answer, answer-to-Aida-removal, forced drains, reconnects, gaps, and orphans.
- Liveness and readiness are distinct.
- No dependency failure may destroy an established caller-human bridge.

## 17. Definition of done per repository

1. A clean checkout starts successfully after the documented non-production service credentials are supplied.
2. Startup validates configuration; `.env.example` is complete.
3. Unit tests may isolate external interfaces and require no production credentials; they do not count as provider-integration or POC acceptance tests.
4. CI runs lint, format, unit, contract, integration, build, and security checks as applicable.
5. Consumers match a pinned AidaControl contract release.
6. Containers run non-root where applicable and expose health/readiness.
7. Logs are structured, correlated, and redacted.
8. Errors have stable codes and safe messages.
9. Database changes use tested migrations.
10. README documents architecture, commands, configuration, tests, deployment, rollback, and limitations.
11. CI produces a versioned release artifact.
12. Provider-backed smoke tests use dedicated non-production accounts/data, are separately tagged, and must pass before a release is accepted.

## 18. System acceptance criteria

1. DID resolves to the correct tenant, published profile, and destination.
2. CRM defaults initialize values; Aida overrides survive synchronization.
3. OfficePulse starts call recording, always plays the English disclosure, and passes `en-US` into the Call Session.
4. Asterisk owns the caller throughout screening.
5. Assigned handset receives the live English transcript stream and recovers live gaps.
6. Retried Take over produces one command and originate.
7. Ringing begins while Aida delivers the English transfer statement.
8. On answer, the human joins immediately and Aida accepts no new caller turn.
9. Aida finishes the current utterance and leaves normally or forcibly within about 10 seconds.
10. Caller-human audio and OfficePulse recording survive Aida/LiveKit removal.
11. Busy, reject, no-answer, caller hangup, provider failure, and restarts have deterministic outcomes.
12. Changes are authorized, validated, versioned, and audited.
13. Public services expose no ARI credentials, private commands, cross-tenant data, or reusable LiveKit credentials.

## 19. Final GitHub project list and build order

1. `localsplash/id` — existing identity application; complete the Aida integration requirements without rebuilding it
2. `localsplash/new_AidaControl` — greenfield runtime control plane, contracts, and Postgres migrations
3. `localsplash/new_AidaAdmin` — greenfield administration and staff operations application, including NocoDB schema automation
4. `localsplash/OfficePulseAidaIntegration` — greenfield FastAGI/ARI/provisioning service and Asterisk deployment assets
5. `localsplash/AidaAgent` — greenfield LiveKit Cloud worker validated against the configured LiveKit agent and AI providers
6. `localsplash/AidaHandset` — greenfield Android 11 application
7. `localsplash/AidaInfrastructureSetupInstructions` — canonical documentation, setup automation, and deployment smoke tests

AidaControl contracts and deterministic unit tests are delivered before dependent integrations so the projects can be built independently against stable interfaces. Cross-repository integration and acceptance use the real configured POC services and records. OfficePulse is customized by installing the integration repository's service, include files, prompts, and configuration; Asterisk itself is never forked.

The five application repositories identified as greenfield plus the documentation/automation repository are the complete set of new builds for the POC. `id` is the sole existing application codebase and AidaAdmin integrates with it per §13. No Echo repository receives Aida-specific changes. EchoService remains an existing messaging integration and requires changes only if a later, repository-specific implementation plan explicitly identifies one.
