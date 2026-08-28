# Aida Voice Platform — Greenfield System Specification

Status: Draft for autonomous project implementation  
Telephony: OfficePulse / Asterisk 20.9.2  
Voice agent: LiveKit  
Handset: Grandstream GXV3450 / Android 11  
Existing integrations: LocalSplash CRM, LocalSplash `id` (identity), EchoService  
Optional realtime provider: Pusher Channels

## 1. Objective

The Aida Voice Platform screens inbound telephone calls with an AI voice assistant and lets an authorized handset user observe and control the conversation in real time.

OfficePulse/Asterisk owns the PSTN call from arrival through hangup. Aida joins through LiveKit as a temporary media participant. The Android Aida Handset displays call state, live transcription, suggested actions, and a **Take over** control. Take over rings the configured SIP destination and connects the human without cutting off Aida's current transfer statement.

OfficePulse owns call recording and plays the required English recording disclosure before Aida begins. The POC is English-only; language selection is deferred.

The system consists of independently buildable projects joined by versioned contracts. Each project must be generatable, testable, containerized where applicable, and deployable by an autonomous implementation agent without undocumented assumptions about another repository.

## 2. Existing systems and boundaries

- **OfficePulse** is the existing Asterisk SIP/PSTN platform. It remains authoritative for channels, bridges, endpoints, ringing, answer, and hangup.
- **OfficePulse call recording** remains authoritative for recording media, disclosure playback, file lifecycle, and any existing recording retention controls. Aida does not make a second recording.
- **LiveKit** supplies realtime media and voice-agent facilities. It is not the system of record for profiles or calls.
- **LocalSplash CRM** supplies onboarding defaults. CRM values retain source metadata and can be overridden by precise Aida configuration.
- **`id`** is the LocalSplash identity service at `id.localsplash.ai`. It owns user accounts, organizations, sign-in (including Google, Microsoft, and UISP), sessions, and revocation; no Aida component keeps a second password or identity database.
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

Ingress routes by hostname to internal services. Published contract artifacts (OpenAPI, AsyncAPI, JSON Schemas) are served under `api.aida.localsplash.ai/v1/contracts/...` — a path on the existing API hostname matching the `/v1` versioning scheme; there is deliberately no separate `contracts.aida.*` hostname or DNS entry. The `id` service is reached at its own apex-domain hostname and is not behind Aida's ingress. The POC and foreseeable deployment use LiveKit Cloud for media and realtime transcript/control data. Pusher provides call-arrival notifications. Aida does not operate a first-party WebSocket service and no `realtime.aida.localsplash.ai` DNS record is required.

A first-party realtime gateway is outside the planned system. It would be reconsidered only if Aida intentionally replaces LiveKit Data for application events because of a demonstrated requirement such as unsupported client behavior, contractual data-residency restrictions, or measured scale/cost constraints. Such a change requires a new architecture revision and is not implied by this specification.

### 4.2 Private OfficePulse API

Use **`officepulse-api.localsplash.ai`**. DNS names remain lowercase even though the product label is “OfficePulse API.”

This hostname resolves to a different private or tightly restricted IP from the public wildcard. Preferred connectivity is private networking, VPN, or an overlay. If Internet-routable, firewall rules allowlist OfficePulse egress addresses and both sides require mTLS. It exposes no browser UI, permissive CORS, user login, or public API explorer.

For the POC it uses public DNS and an independently firewalled web service limited to known internal server source addresses. Application-level service authentication remains mandatory because an IP allowlist alone is not identity.

Asterisk ARI remains bound to loopback or a private OfficePulse interface. Only OfficePulse API possesses ARI credentials.

## 5. Repositories and autonomous build contracts

Each repository must contain a README, architecture notes, `.env.example` without secrets, deterministic local startup, health/readiness endpoints where relevant, tests, lint/format commands, CI, container build where relevant, and pinned contract versions.

The implementation stack is fixed for the POC: TypeScript/Node.js for AidaControl and OfficePulseAidaIntegration, React/TypeScript for AidaAdmin, Python for AidaAgent, Kotlin for AidaHandset, Docker Compose for initial deployment, and GitHub Actions for CI. Interface contracts use OpenAPI 3.1, AsyncAPI, and JSON Schema.

### 5.1 `AidaControl`

Authoritative API and call orchestrator.

Responsibilities:

- tenants, profiles, routes, devices, platform appearance settings, permissions, and audit;
- DID resolution and immutable profile-version pinning;
- Call Session state machine and transactional command acceptance;
- LiveKit room/token lifecycle and agent dispatch;
- OfficePulse and agent event ingestion;
- transactional call-state/event persistence, replay, and LiveKit Data publication;
- LocalSplash CRM default import and override tracking;
- validation of staff-session tokens from a single configured issuer (self-issued by AidaAdmin, whose users authenticate against `id`);
- reconciliation of orphan/inconsistent resources.

AidaControl is also the source of truth for shared contracts and both Aida-owned data stores. Its repository contains:

- `/contracts/openapi` for public AidaControl endpoints;
- `/contracts/asyncapi` for LiveKit Data topics and payloads;
- `/contracts/schemas` for Profile, event, command, state, permission, and error definitions;
- `/contracts/fixtures` for normal, failure, retry, and takeover scenarios;
- `/generated-clients` or CI release artifacts for Kotlin, Python, and TypeScript consumers;
- `/nocodb/schema` with a versioned table manifest for the shared `AidaOffice` base (§6.3), which AidaControl shares with the other Aida projects rather than owning privately;
- `/nocodb/scripts` for create, validate, seed, upgrade, and backup checks.
- `/postgres/migrations` for hot-path transactional tables;
- `/postgres/seeds` and integration-test fixtures.

The OpenAPI definition includes the externally callable LiveKit webhook endpoint even though its authentication scheme is LiveKit signature verification rather than an Aida user token.

This is not a separate Contracts or Data service. AidaControl implements the interfaces and owns both data models. Other repositories consume versioned contract artifacts from AidaControl releases.

Postgres is AidaControl's alone: no other repository connects to it, ever. NocoDB is narrower than it once was. Aida's call-platform configuration — every table in §6.1, §6.2 and §6.3 except the two cross-project ones — is reached only through AidaControl's APIs, and no other repository reads or writes it directly. What other repositories may touch in `AidaOffice` is their own tables and the two cross-project tables named in §6.3, which exist precisely to be shared.

Postgres is exclusive to AidaControl and stores the live transactional path: `call_session`, `call_event`, and `control_command`. AidaControl uses database transactions, row-level locking, unique idempotency constraints, optimistic state versions, and per-call ordered event allocation to implement first-command-wins semantics safely.

NocoDB stores slow-moving, human-edited configuration: tenants, profile drafts/versions, inbound routes, devices/bindings, singleton appearance settings, CRM import records, per-field configuration-source metadata, and related audit/configuration metadata. These tables live in the shared `AidaOffice` base alongside other Aida projects' tables (§6.3), so AidaControl's schema automation is strictly additive: it creates and validates its own tables and reports unknown tables rather than dropping them. The automation uses environment-supplied URL, workspace/base identifiers, and API token. The existing NocoDB instance is assumed to be MySQL-backed, but AidaControl uses only the NocoDB API and avoids backend-specific SQL behavior.

Tests cover all legal/illegal state transitions, route resolution, profile pinning, tenant isolation, permissions, concurrent takeover races, duplicate idempotency keys, ordered sequence allocation, schema/example validation, generated-client compilation, contract compatibility, Postgres migrations, and NocoDB bootstrap/upgrade behavior. OfficePulse, LiveKit, Echo, CRM, Pusher, FCM, and NocoDB adapters have non-networked fakes; transactional integration tests run against disposable Postgres.

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

Tests use fake STT/LLM/TTS providers and cover profile validation, template rendering, transcripts, tool allowlists/timeouts, no-new-turn behavior, normal drain, and forced drain. Default tests incur no third-party charges.

LiveKit Cloud and the already functioning OfficePulse-to-LiveKit SIP trunk are the POC media path. Asterisk passes custom `X-Aida-*` SIP headers. The POC headers are `X-Aida-Call-Session` and `X-Aida-Route-Token`; the route token is opaque, short-lived, single-call, and validated by AidaControl.

The POC dispatches the predefined LiveKit Cloud agent **`aida-prime`**, agent ID **`CA_Lbh5CTq2Rxhd`**. Its LiveKit-managed STT/LLM/TTS/model defaults—including the currently intended Gemma-family model—remain inherited and are not sent by AidaControl. Per-session dispatch metadata contains only allowlisted dynamic settings, initially the pinned prompt/business context, call identifiers, behavior/tool overrides explicitly supported by the contract, and locale. An omitted override always means “use the predefined LiveKit agent default.”

Caller barge-in is enabled during ordinary screening. AidaAgent/LiveKit speech handling monitors caller voice activity while TTS is playing, cancels or attenuates the current agent playout according to the configured interruption threshold, and starts the caller turn. Once the destination answers, AidaAgent sets `acceptNewTurns=false`; caller speech can no longer interrupt the transfer statement, which is allowed to finish until the drain deadline.

### 5.3 `OfficePulseAidaIntegration`

Companion service and managed configuration layered onto the existing OfficePulse server. It does not fork, rebuild, or modify Asterisk source code. Its TypeScript/Node.js service is deployed adjacent to Asterisk and is externally addressed as OfficePulse API at `officepulse-api.localsplash.ai`.

Responsibilities:

- own ARI/Stasis connectivity and reconciliation;
- receive calls from a stable Aida dialplan context;
- manage caller, Aida media, and destination channels/bridges;
- originate typed destinations;
- report ringing, answer, failure, bridge, and hangup events;
- execute idempotent Control Plane commands;
- enforce local handoff/cleanup safety deadlines;
- optionally validate/deploy managed Asterisk includes.

Tests use mocked ARI events and commands and cover reconnect, duplicates, bridge membership, busy/reject/no-answer/answer, and forced Aida removal without dropping the human bridge. A disposable Asterisk 20.9.2 test validates dialplan fixtures where feasible.

The repository contains the companion ARI/Stasis service, a versioned `aida.conf` or `aida-managed.conf` dialplan include, required `extensions.conf` include instructions, ARI account configuration template, local audio assets, codec conversion/deployment scripts, system-service/container definition, firewall guidance, and validation/rollback scripts. Existing OfficePulse configuration is changed only through explicit includes and documented settings.

### 5.4 `AidaAdmin`

Responsive tenant/staff application at `app.aida.localsplash.ai`.

It manages profiles, publishing, routes, devices, retention, platform appearance settings, and permitted call views. It displays CRM defaults separately from effective overrides. It validates destinations through AidaControl and never accesses ARI or Asterisk configuration directly. It reaches Aida's call-platform configuration only through AidaControl's APIs; in `AidaOffice` it touches its own `appConfig`, reads `oAuthConfig`, and registers itself in the cross-project tables of §6.3.

AidaAdmin authenticates its users against the LocalSplash identity service (`id`, at `id.localsplash.ai`) using the flow in §13, holds its own persistent session, and self-issues the short-lived staff tokens AidaControl validates. It keeps no password store of its own.

Tests cover accessible components, keyboard navigation, validation/conflict/forbidden states, draft/publish/rollback, CRM override/reset, staff tenant context, cross-tenant leakage, and a minimal browser workflow with fake APIs.

### 5.5 `AidaHandset`

Android 11 application for Grandstream GXV3450.

Responsibilities:

- device/user enrollment and authentication;
- server-authorized device-to-SIP-destination binding;
- Pusher notification and LiveKit data-room subscription/recovery;
- active-call, transcript, suggestion, and command-progress display;
- idempotent Take over and later guided controls;
- recovery after app pause, network loss, and process restart.

Tests cover reducers/ViewModels, ordering/duplicates/gaps/replay, takeover debounce/idempotency, token expiry, forbidden calls, FCM fakes, UI states, and an Android 11 CI build.

The APK does not answer the SIP call. The Grandstream SIP application/endpoint answers; AidaHandset observes the server event. For the POC, the user manually enters the extension and an enrollment credential. The raw Asterisk SIP secret must not become the Aida credential. The OfficePulseAidaIntegration service verifies an extension-specific enrollment challenge and AidaControl issues a revocable device credential. SIP secrets are never stored in NocoDB, Pusher payloads, or ordinary APK preferences.

### 5.6 `AidaInfrastructureSetupInstructions`

Documentation-and-automation repository rather than an application service. It is the operator's single setup guide across all projects.

It contains:

- dependency/version matrix and supported deployment topology;
- complete environment-variable and secret inventory, including Postgres, LiveKit API key/secret, predefined LiveKit agent ID, Pusher, NocoDB (URL, API token, and the shared `AidaOffice` base of §6.3, which AidaControl addresses by identifier as `NOCODB_BASE_ID` while `id` and AidaAdmin address it by title as `NOCODB_BASE_NAME`), the `id` client registration for AidaAdmin, the persisted staff-token issuer/secret pair shared between AidaAdmin and AidaControl (never generated at boot), the per-service `AIDA_APP_PRIVATE_KEY` of §11.3 with its `AIDA_APPLICATION_NAME` and `AIDA_ENVIRONMENT` identity pair (one key per application per environment, generated by each service's key-generation command, never generated at boot and never stored in the registry), Firebase if used, CRM when enabled (`CRM_IMPORT_ENABLED` is pinned `false` for the POC in every deployment configuration, not left to a code default), and OfficePulse service credentials;
- public wildcard and private OfficePulse DNS, TLS, firewall, mTLS, and ingress instructions;
- Docker Compose orchestration referencing released project images;
- scripts that run AidaControl's Postgres migrations and invoke its NocoDB schema commands to create/validate/seed the shared `AidaOffice` base;
- the cross-project runbook for consolidating Aida's NocoDB tables into that base, covering ordering, the shared table namespace, secret handling, verification, and rollback;
- `id` client registration and configuration instructions for AidaAdmin;
- OfficePulse integration installation order and verification;
- health-check, smoke-test, backup, restore, upgrade, and rollback runbooks;
- LiveKit Cloud webhook creation, signing-key selection, test-delivery, rotation, and troubleshooting instructions;
- staging and production checklists with placeholders for site-specific values.

It does not duplicate application source or own data/API contracts. Its tests validate configuration files, required settings, scripts, TLS/hostname routing, absence of public ARI routes, mock-provider startup, and backup/restore commands.

There is no AidaSystemTest repository in the initial design. Every source repository owns its unit, contract, integration, and component tests. `AidaInfrastructureSetupInstructions` contains only a small cross-project deployment smoke test that verifies health and one simulated call flow; richer system testing may be designed later if actual operational needs justify it.

## 6. Core data model

### 6.1 Tenants and external references

- `tenant`: UUID, status, display name, timestamps.
- `tenant_external_reference`: tenant, system (`id`, `localsplash_crm`), external ID, metadata; unique by system/external ID.
- `platform_appearance`: singleton POC settings for brand name, agent display name, colors, uploaded logo/icon references, and support/legal URLs.

`id`'s organization identifier is an external reference, not Aida's primary key. There is deliberately no separate `uisp` system value: UISP sign-in flows through `id`, and `id`'s own user identifier (`iUserId`) supersedes a direct UISP linkage.

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

Every Aida project's NocoDB tables live in one shared base named **`AidaOffice`**. This is deliberate rather than incidental: NocoDB link fields, its foreign-key equivalent, resolve only within a single base, so relationships between projects' records are expressible only if those records share a base. Projects are separated by table name, not by base.

The table-naming rule that keeps projects from colliding in that shared namespace: a table name is claimed by exactly one project, and a project adding a table checks the current inventory first. AidaControl owns the snake_case call-platform tables listed below plus those in §6.1 and §6.2; `id` owns `oAuthConfig`; AidaAdmin owns `appConfig` and reads `oAuthConfig`. Nothing collides today. A project's schema automation is additive within the base — it never drops or alters a table it does not own, and reports unknown tables instead.

Two tables are **cross-project**, read and written by every Aida service rather than owned by one:

- `aida_application`: the service-credential registry of §11.3 — application name, environment, public key, enabled, and last-seen metadata, keyed on application name plus environment.
- `aida_system_setting`: platform switches held per environment, among them `application_registration_open`, the registration lock of §11.3.

Ownership of a shared table runs to its **columns**, not only its name. AidaControl's versioned manifest is the single definition of both cross-project tables. Every other project finds them and must not create them with columns of its own choosing: two services that each create the same table on demand will disagree about its shape, and the one that loses the race then reads a column that does not exist. A service that finds a cross-project table missing reports it and waits rather than inventing one. The operator procedure for consolidating existing bases into `AidaOffice` is the runbook in `docs/NOCODB_AIDAOFFICE_BASE_RUNBOOK.md`.

- `inbound_route`: tenant, DID, profile, typed destination, ring timeout, no-answer/failure policy, OfficePulse node, enabled, revision.
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

The LiveKit Data contract is defined in `AidaControl/contracts/asyncapi` and is normative for AidaControl, AidaAgent, and AidaHandset. Payloads use UTF-8 JSON. A durable AidaControl event has this envelope:

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

## 10. OfficePulse/Asterisk integration

### 10.1 Stable dialplan

Routine DID/profile/destination changes do not rewrite `extensions.conf`. One version-controlled Aida context hands calls to Stasis; AidaControl resolves data-driven routing.

```asterisk
[from-provider]
exten => _X!,1,NoOp(Aida inbound ${CALLERID(num)} -> ${EXTEN})
 same => n,Set(CHANNEL(hangup_handler_push)=aida-hangup,s,1)
 same => n,Stasis(aida-officepulse,${EXTEN},${CALLERID(num)})
 same => n,GotoIf($["${AIDA_DISPOSITION}"="BYPASS"]?legacy-inbound,${EXTEN},1)
 same => n,Hangup()

[aida-hangup]
exten => s,1,NoOp(Aida cleanup)
 same => n,Return()
```

The OfficePulseAidaIntegration service must adapt the final variables/fallback flow to installed modules and existing OfficePulse dialplan. No public HTTP call occurs synchronously from dialplan.

### 10.2 ARI/bridge rules

- Dedicated least-privilege ARI account and Stasis application.
- Only the OfficePulseAidaIntegration service holds ARI credentials.
- `callSessionId` is applied to related channels; `linkedid` remains diagnostic.
- Originate, bridge membership, removal, and termination are idempotent.
- The OfficePulseAidaIntegration service reconciles active resources after restart.
- A local deadline removes Aida after human answer if AidaControl is unreachable.
- That deadline can remove only Aida, never the caller-human bridge.

### 10.3 Managed configuration

Infrastructure-only changes may use a private typed deployment endpoint. It accepts desired configuration, never raw dialplan; validates contexts/endpoints; renders `aida-managed.conf`; validates Asterisk configuration; writes atomically; retains the prior revision; reloads and health-checks; audits; and rolls back on failure.

### 10.4 Local failure announcements

OfficePulse stores pre-rendered English audio assets locally so entry and fallback behavior work without LiveKit or AidaControl:

- recording disclosure: “Calls are recorded.”;
- caller failure prompt: Aida service is temporarily unavailable and the call will be routed directly;
- extension failure prompt: Aida screening was unavailable for this call.

These are project-owned recordings, not assumed Asterisk built-ins. `OfficePulseAidaIntegration` includes source WAV files and a deployment step that produces the codec/sample-rate variants required by the installed Asterisk channels (at minimum the site's negotiated narrowband format). OfficePulse always plays the normal recording disclosure first. If Aida is unavailable, it then plays the caller “circuits are busy” prompt, originates the configured extension, plays the extension-facing incident prompt after answer, and bridges the parties. Prompt version/checksum and deployment validation are documented in `AidaInfrastructureSetupInstructions`.

## 11. API boundaries

### 11.1 Public API at `api.aida.localsplash.ai`

- identity/permissions and device enrollment;
- profiles, drafts, versions, validation, publish, rollback;
- routes and test resolution;
- device/destination bindings;
- active/recent calls, replay, and commands;
- Pusher/realtime authorization;
- platform appearance and CRM import/status;
- staff tenant selection and operational views.
- `POST /v1/integrations/livekit/webhooks`, authenticated exclusively by LiveKit's signed webhook JWT and raw-body hash verification.

Writes use validation, tenant authorization, rate limiting, auditing, ETag/revision concurrency, and idempotency where appropriate. Browser cookie writes require CSRF protection. Handsets use short-lived tokens with revocation.

AidaAdmin's identity integration adds two endpoints of its own — the `POST /id/events` revocation-webhook receiver and the boot-time `GET /api/events?since=` catch-up client (§13) — and both belong to AidaAdmin's surface, not AidaControl's public API.

The LiveKit webhook route is the sole exception to Aida user/workload-token authentication on the public API. It accepts only `application/webhook+json`, preserves the raw body and `Authorization` header for `WebhookReceiver`, performs no CSRF check, and applies the verification, deduplication, and event rules in §9.3.

### 11.2 Private API at `officepulse-api.localsplash.ai`

- `POST /internal/v1/calls/bootstrap`
- `POST /internal/v1/calls/{id}/events`
- `POST /internal/v1/calls/{id}/commands/originate`
- `POST /internal/v1/calls/{id}/commands/remove-aida`
- `GET /internal/v1/destinations/{node}/{type}/{value}/validate`
- `POST /internal/v1/config/deploy`

Use mTLS and scoped workload credentials. Requests include timestamp, nonce/idempotency key, and correlation ID. Browser cookies and handset tokens are invalid here.

LiveKit tokens are short-lived and room/identity scoped. Handsets join as data-only participants and neither publish nor subscribe to media tracks. Prompts, secrets, PII, and reusable credentials are excluded from token metadata.

### 11.3 Service-to-service credentials

Aida services authenticate to one another with Ed25519 request signatures, keyed through a shared registry rather than pairwise configuration. With N services, pairwise secrets would mean N² values to distribute; the registry means each service publishes one key and fetches the rest.

**Key custody.** Each service holds one private key per environment, supplied through its environment as `AIDA_APP_PRIVATE_KEY` (base64 of the PKCS#8 DER, so it fits one line). A service never generates or persists a private key: a key file inside a container does not survive a rebuild without a volume, and a volume that must be correct in every environment forever fails silently when it is not. Supplying the key through the environment also makes replicas trivial — every replica reads the same value and publishes the same public key.

A missing key **in production is a startup failure** naming the variable. In development only, a service may generate an ephemeral key and warn; the environment guard is what keeps that off the production path. Each service ships a key-generation command so operators never improvise `openssl`.

**The registry.** The `aida_application` table in the shared `AidaOffice` base (§6.3) holds, per application per environment: the application name, environment, **public key**, an enabled flag, and last-seen metadata. There is no key version and no previous key, because keys do not expire. Identity is keyed on `application_name` + `environment`, never hostname — container hostnames are ephemeral, and keying on them would create a row per restart.

**No private key is ever stored in the registry.** Storing one there would make a single registry read sufficient to impersonate every service, which is precisely what this design exists to prevent given how widely the NocoDB API token is held.

**Signing.** A caller signs method, path, body hash, timestamp and nonce — the timestamp, nonce and correlation ID §11.2 already requires. A callee resolves the caller's public key from the registry and verifies, rejecting stale timestamps and replayed nonces. A bare bearer secret would be replayable by anyone who observed it; a signature over a timestamp and nonce is not.

**The wire format**, which every service must implement identically or nothing verifies. AidaControl is the reference implementation.

Five headers carry the credential: `x-aida-application`, `x-aida-environment`, `x-aida-timestamp` (Unix seconds), `x-aida-nonce`, and `x-aida-signature` (base64 Ed25519). There is deliberately no key-version header: an application has exactly one published key at a time. The signature covers these eight lines joined by a single newline, in this order:

```
AIDA-ED25519-V1
<method, uppercase>
<path including query string>
<lowercase hex SHA-256 of the request body, of the empty string when there is none>
<timestamp>
<nonce>
<application name>
<environment>
```

Three of those lines are there for a specific attack. The **scheme name** is first so a future v2 cannot be verified as a v1 by a peer that has not been upgraded. The **claimed identity** is inside the signature rather than only in the headers, so the identity headers cannot be swapped onto another application's registry row. The **query string** is inside it, so an observer cannot turn a captured `?limit=1` into `?limit=1000`.

Because the signature covers a hash of the bytes as sent, a signed request body must reach the verifier unparsed — the same constraint the LiveKit webhook receiver already has, and for the same reason: re-serialising JSON yields something semantically identical and byte-different. AidaControl gives signed routes the dedicated content type `application/aida-signed+json`, parsed as an untouched string.

Two further variables name the identity: `AIDA_APPLICATION_NAME` and `AIDA_ENVIRONMENT`. `AIDA_ENVIRONMENT` is deliberately separate from `NODE_ENV` or its equivalent, because they answer different questions — one selects code behaviour, the other names the deployment whose registry rows the process shares. Staging runs production code.

**Keys do not expire.** There is no scheduled rotation, no overlap window, and no retirement of an old key. A key is replaced only when it is lost or believed compromised, and replacing it is the deliberate operator procedure below rather than a routine the system runs on its own. This is a decision to keep the mechanism small: an expiry policy buys nothing here that closing the registration lock does not already buy, and every overlap window is a second key that verifies.

Revocation is the `enabled` flag on the application's row. Unticking it refuses that one application everywhere, immediately, without touching any other application or the lock.

**The registration lock.** Enrolment is governed by one switch, `application_registration_open` in the `aida_system_setting` table, held per environment. It behaves like a domain transfer lock.

While the lock is **open**, a service that starts publishes its public key, its registry row is created enabled, and it is immediately usable. No per-application approval step stands between a service starting and its peers honouring it.

While the lock is **closed**, the registry accepts no new application row, and accepts no change to the public key on an existing row. A refused write is logged naming the application, the environment and the row.

Closing the lock is the approval. An operator brings the services up with the lock open, confirms that the rows present are the applications they expect and no others, and closes it. From that point the set of credentials the platform honours is fixed until someone deliberately opens the lock again.

The lock defaults to open on a fresh base, and that default is load-bearing rather than a convenience. AidaAdmin's administrative interface reaches its data through AidaControl, so an administrator cannot reach any screen that would approve an application if AidaControl is already refusing that application's credential. A platform that required approval before its first service could talk could not start at all. The default is safe because it is visible: while the lock is open the administrative interface carries a standing notice saying so, since an open lock means anyone who can write to the base can mint a credential every service honours.

The flip is per environment. Closing staging must never close production, and closing production must never close staging.

Because keys never expire, a public key that changes while the lock is closed is either a service that lost its key or something impersonating one. The registry refuses the write in both cases and the difference is settled by a human, not by the software.

**Replacing a key** is therefore an explicit procedure and not a rotation: open the lock, restart the service with the new key, confirm the row, close the lock. Peers holding a cached copy of the old key refuse the service until their cache turns over, which is a bounded and expected part of the procedure rather than something an overlap window has to hide.

**Diagnostics.** A refused call is logged by both caller and callee, and reflected in readiness where it concerns the service's own registration, naming the application, environment, the registry row to inspect, and which check failed — unknown application, disabled, key mismatch, stale timestamp, or replayed nonce. These have different remedies and are not collapsed into a single "authentication failed". Over the wire the response stays generic: a caller learns that it was refused, never why, since disclosing the failing check hands a caller a probing oracle.

**Developer access is not this mechanism.** A person calling the API authenticates through the staff-session path of §13 and may exercise the API through the contract browser AidaControl serves at `/v1/contracts/docs`. The `aida_application` registry is for services only; a person's credential is never a peer-service credential.

## 12. Administration

Tenant administrators manage DIDs, profiles, destinations, failover, ring timeout, devices, retention, versions, and permitted call views. They see CRM imported values separately from effective overrides. Only a platform administrator manages the singleton platform appearance settings.

Route validation confirms normalized/unique DID, published profile, OfficePulse node reachability, and destination existence. Publishing creates an immutable version; active calls retain their pinned version.

Staff administration uses a separately initiated short-lived privileged session, explicit tenant selection, a persistent context banner, and full audit. Staff permission derives from a verified role/group or explicit allowlist—not an unverified email suffix.

## 13. Identity integration (`id`)

Identity for the Aida Voice Platform is the LocalSplash identity service, **`id`**, at `id.localsplash.ai` on the apex `localsplash.ai` domain — independent of Aida's wildcard DNS, certificate, and ingress (§4.1). `id` owns user accounts, organizations, sign-in (Google, Microsoft, UISP), sessions, and revocation. No Aida component keeps a second password or identity database.

### 13.1 AidaAdmin ↔ `id`

- **Registration.** AidaAdmin registers itself with `id` on boot as a client application, supplying its callback and webhook URLs. Registration is idempotent: a restart re-asserts the same registration rather than creating a new one.
- **Sign-in.** AidaAdmin sends the browser to `id`'s `/authorize`, receives an authorization code on its callback, and redeems it with `POST /api/token`. AidaAdmin then holds a persistent session for the user; `id` is not consulted on every request.
- **Revocation, two paths that must both exist.** `id` pushes revocation and identity-change events to AidaAdmin's `POST /id/events` webhook receiver. Because a webhook can be missed while AidaAdmin is down, AidaAdmin also calls `id`'s `GET /api/events?since=<cursor>` on boot to catch up on anything delivered while it was away, then resumes webhook consumption. A revoked user's AidaAdmin session and any outstanding staff tokens for it are invalidated.
- These two endpoints — the webhook receiver and the catch-up client — belong to **AidaAdmin's** surface, not AidaControl's public API (§11.1).

### 13.2 AidaAdmin → AidaControl

AidaAdmin self-issues the signed, short-lived staff token that AidaControl validates. AidaControl accepts exactly one configured issuer (`STAFF_TOKEN_ISSUER`) with a persisted shared secret (`STAFF_TOKEN_SECRET`) — a deployment credential that must survive restarts and is never generated at boot, or every restart would silently invalidate outstanding sessions and break the issuer pairing.

The token includes user, Aida tenant, permissions, session ID, issuer/audience, issue/expiry, and token ID. AidaControl validates the token and performs all Aida authorization itself; permissions such as `voice.routes.manage`, `voice.profiles.manage`, `voice.calls.control`, and `voice.calls.read` derive from verified role/group claims or an explicit allowlist, never from an email suffix.

### 13.3 Tenancy and data boundaries

- An Aida `tenantId` links to an `id` organization through `tenant_external_reference` with `system = id` (§6.1). `id`'s identifiers are external references, never Aida primary keys.
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

Uploaded files are validated for allowed type and size, assigned opaque names, and stored by the Aida deployment. They are served through the existing application origin under `https://app.aida.localsplash.ai/brand-assets/...`; no additional asset hostname or DNS record is required. AidaControl stores the settings and asset references, and AidaAdmin never accepts an arbitrary executable or remote asset URL as an upload substitute.

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

1. Clean-checkout local setup works.
2. Startup validates configuration; `.env.example` is complete.
3. Unit tests include dummy/fake external integrations and require no production credentials.
4. CI runs lint, format, unit, contract, integration, build, and security checks as applicable.
5. Consumers match a pinned AidaControl contract release.
6. Containers run non-root where applicable and expose health/readiness.
7. Logs are structured, correlated, and redacted.
8. Errors have stable codes and safe messages.
9. Database changes use tested migrations.
10. README documents architecture, commands, configuration, tests, deployment, rollback, and limitations.
11. CI produces a versioned release artifact.
12. Billable/provider smoke tests are separately tagged and disabled by default.

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

1. `AidaControl`, including contracts, Postgres migrations, NocoDB schema automation, and all integration fakes
2. `OfficePulseAidaIntegration`, including its ARI simulator and Asterisk deployment assets
3. `AidaAgent` with fake AI providers
4. `AidaHandset`
5. `AidaAdmin`
6. `AidaInfrastructureSetupInstructions`
7. Staging OfficePulse end-to-end integration using the setup repository's smoke test

AidaControl contracts and deterministic fakes are delivered first so the other projects can be built independently. OfficePulse is customized by installing the integration repository's service, include files, prompts, and configuration; Asterisk itself is never forked.

The six names above are the complete list of new GitHub repositories for the initial implementation. `id` is an existing LocalSplash service that AidaAdmin integrates with per §13; no Echo repository receives Aida-specific changes. EchoService remains an existing messaging integration and requires changes only if its own repository-specific implementation plan explicitly identifies one.
