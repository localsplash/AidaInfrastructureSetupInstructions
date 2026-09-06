# Aida Office POC — Database and Input Interface Specification

Status: Normative for the initial POC
Platform domain: `localsplash.ai`  PBX: OfficePulse / Asterisk 22.10.1 Realtime
Media and voice agent: LiveKit Cloud / `aida-prime`

This document is the concise build contract for the POC. Where the broader
technical specification describes a later or more general configuration API,
this document controls the initial POC.

Object naming, storage tiers, migration rules, and secret handling are governed
by [`PLATFORM_DATA_STANDARD.md`](./PLATFORM_DATA_STANDARD.md). This document
does not restate them; it applies them.

## 0. What changed from the previous revision

| Was | Now | Why |
| --- | --- | --- |
| Former runtime store on the alternate SQL engine | `aida_db` on MySQL 8 | One engine, one dialect, one backup procedure; that engine cannot hold the column naming standard without quoting every identifier |
| `tenant` and `tenant_user` in NocoDB | `identity_tbl_Tenant` and `identity_tbl_TenantUser` in `platform_db` | A business client is platform master data referenced by every application, not Aida configuration |
| Former split NocoDB configuration bases | One base, `PlatformConfig` | Two "only base on the platform" claims contradicted each other; one base means one token, one backup, one name-resolution rule |
| Former Echo database settings table | `cfg_tbl_Setting` rows scoped to `echo` | Every application's environment is now only the NocoDB URL and token |
| Mixed `snake_case` / `iUserId` / `sSessionId` | The single standard, `uid` prefix for our own identifiers | Three dialects across four stores |
| Former identity database and table prefixes | `platform_db`, `identity_tbl_*` | The short form `id` reads as "identifier" in an application whose primary key is one |

## 1. Database specifications

### 1.1 `platform_db`

| Property | Value |
| --- | --- |
| Database type | MySQL 8 |
| Server home | `LSAidaOffice01` |
| Owning application | `localsplash/identity` (sole schema owner and sole writer) |
| Purpose | Shared platform identity, business clients, authentication sessions, application handoff codes, and revocation events |

`identity_tbl_User.iUserId` is the single platform-wide person identifier and
`identity_tbl_Tenant.iTenantId` is the single platform-wide business-client
identifier. No other application creates a second user or tenant record, and
none duplicates a person's name, email, credentials, or provider identities.

Applications reach this database only through the CIDR-trusted directory API in
section 2.1. No application other than `identity` holds MySQL credentials for it.

#### `identity_tbl_User`

| Column | Type | Requirement |
| --- | --- | --- |
| `iUserId` | BIGINT | Primary key, auto-increment |
| `email` | VARCHAR(255) | Nullable |
| `displayName` | VARCHAR(255) | Nullable |
| `dtCreated` | DATETIME(3) | Required |
| `dtLastLogin` | DATETIME(3) | Nullable |

#### `identity_tbl_Identity`

| Column | Type | Requirement |
| --- | --- | --- |
| `iIdentityId` | BIGINT | Primary key, auto-increment |
| `iUserId` | BIGINT | FK to `identity_tbl_User` |
| `provider` | VARCHAR(32) | Required |
| `subject` | VARCHAR(255) | Required |
| `email` | VARCHAR(255) | Nullable |
| `dtCreated` | DATETIME(3) | Required |

Unique: `(provider, subject)`.

#### `identity_tbl_Session`

| Column | Type | Requirement |
| --- | --- | --- |
| `uidSession` | CHAR(64) | Primary key |
| `iUserId` | BIGINT | FK to `identity_tbl_User` |
| `bSuperAdmin` | BOOLEAN | Required |
| `provider` | VARCHAR(32) | Nullable |
| `subject` | VARCHAR(255) | Nullable |
| `dtCreated` | DATETIME(3) | Required |
| `dtLastSeen` | DATETIME(3) | Nullable |
| `dtRevoked` | DATETIME(3) | Nullable |

Sessions do not expire. A login ends when the user signs out, signs out
everywhere, or a Super System Admin revokes their sessions. Applications follow
the same model for their own local sessions.

#### `identity_tbl_Tenant`

The business client. New in this revision.

| Column | Type | Requirement |
| --- | --- | --- |
| `iTenantId` | BIGINT | Primary key, auto-increment |
| `name` | VARCHAR(255) | Required |
| `slug` | VARCHAR(64) | Required, unique |
| `bEnabled` | BOOLEAN | Default `true` |
| `dtCreated` | DATETIME(3) | Required |
| `dtUpdated` | DATETIME(3) | Required |

This table holds only what every application agrees on. Application-specific
tenant attributes — Aida's Asterisk context and caller ID defaults — live in
`aida_tbl_TenantProfile` (section 1.2), keyed by `iTenantId`.

#### `identity_tbl_TenantUser`

The membership and platform role record.

| Column | Type | Requirement |
| --- | --- | --- |
| `iTenantUserId` | BIGINT | Primary key, auto-increment |
| `iTenantId` | BIGINT | FK to `identity_tbl_Tenant`; nullable only for `SUPER_ADMIN` |
| `iUserId` | BIGINT | FK to `identity_tbl_User` |
| `role` | ENUM | `SUPER_ADMIN`, `TENANT_ADMIN`, or `USER` |
| `bEnabled` | BOOLEAN | Default `true` |
| `dtCreated` | DATETIME(3) | Required |
| `dtUpdated` | DATETIME(3) | Required |

Unique: `(iTenantId, iUserId)`. A Super Admin may hold one record with
`iTenantId = NULL`. Name and email are returned by the directory API and are
never copied here or into any application.

#### Remaining tables

`identity_tbl_AuthCode`, `identity_tbl_SsoNonce`, `identity_tbl_App`,
`identity_tbl_Event`, `identity_tbl_Delivery`, `identity_tbl_DirectoryKey`, and
`identity_tbl_SchemaMigration` retain their existing schemas, renamed to the
standard.

### 1.2 `PlatformConfig`

| Property | Value |
| --- | --- |
| Database type | NocoDB cloud base, MySQL-backed |
| Server home | Existing cloud NocoDB service at `nocodb.localsplash.ai` |
| Base resolution | By name at runtime; never by an ID in a file |
| Purpose | All deployment settings for every application, plus Aida's slow-moving telephony and prompt configuration |

Only server-side code holds the NocoDB API token. Browser code, AidaHandset,
AidaAgent, OfficePulse, and Asterisk never reach NocoDB.

Table ownership within the base: `identity` owns `cfg_tbl_Setting`; the
AidaAdmin server owns every `aida_tbl_*` table here and is their sole writer;
AidaControl reads them at call bootstrap.

#### `cfg_tbl_Setting`

| Column | Type | Requirement |
| --- | --- | --- |
| `iSettingId` | INTEGER | Primary key, auto-increment |
| `app` | VARCHAR(32) | Required; `*`, `identity`, `aida`, `echo`, `echo-web`, `echo-service`, `echo-media` |
| `settingKey` | VARCHAR(128) | Required |
| `settingValue` | TEXT | Nullable; blank counts as unset |
| `description` | VARCHAR(512) | Nullable |
| `bSecret` | BOOLEAN | Default `false` |
| `dtUpdated` | DATETIME(3) | Required |

Unique: `(app, settingKey)`. An application reads its own `app` row in
preference to the `*` row for the same key. Adding a setting is a row, never a
new table.

Keys carried here include the platform-wide `trustedCIDR` and `PARENT_DOMAIN`;
per-application database coordinates (`DB_HOST`, `DB_PORT`, `DB_USER`,
`DB_PASSWORD`, `DB_NAME`); public URLs; and the Google, Microsoft, and UISP
credentials. On first boot every known key is seeded empty with a description,
so the menu of settings is visible without guessing.

#### `aida_tbl_TenantProfile`

Aida's per-tenant telephony attributes. One row per tenant Aida serves; a tenant
with no row is a tenant Aida does not serve.

| Column | Type | Requirement |
| --- | --- | --- |
| `iTenantId` | BIGINT | Primary key; `platform_db.identity_tbl_Tenant.iTenantId` |
| `asteriskContext` | String | Required, unique |
| `callerIdName` | String | Nullable |
| `callerIdNumber` | E.164 String | Nullable |
| `bEnabled` | BOOLEAN | Default `true` |
| `dtCreated` | Timestamp | Required |
| `dtUpdated` | Timestamp | Required |

#### `aida_tbl_Extension`

| Column | Type | Requirement |
| --- | --- | --- |
| `uidExtension` | CHAR(36) | Primary key |
| `iTenantId` | BIGINT | Required |
| `iUserId` | BIGINT | Nullable; assignee in `identity_tbl_User` |
| `extensionNumber` | String | Required |
| `displayName` | String | Required |
| `callerIdName` | String | Nullable; tenant default when absent |
| `callerIdNumber` | E.164 String | Nullable; tenant default when absent |
| `asteriskContext` | String | Required |
| `provisioningProfile` | String | Nullable |
| `bEnabled` | BOOLEAN | Default `true` |
| `dtCreated` | Timestamp | Required |
| `dtUpdated` | Timestamp | Required |

Unique: `(iTenantId, extensionNumber)`. One user may hold several extensions;
one extension has zero or one user. SIP secrets never enter NocoDB.

#### `aida_tbl_RingGroup`

| Column | Type | Requirement |
| --- | --- | --- |
| `uidRingGroup` | CHAR(36) | Primary key |
| `iTenantId` | BIGINT | Required |
| `name` | String | Required |
| `virtualExtension` | String | Required |
| `asteriskContext` | String | Required |
| `ringStrategy` | Enum | POC value `RING_ALL` |
| `iRingTimeoutSeconds` | INTEGER | Default `20` |
| `musicOnHoldClass` | String | Nullable |
| `callerIdName` | String | Nullable |
| `callerIdNumber` | E.164 String | Nullable |
| `bEnabled` | BOOLEAN | Default `true` |
| `dtCreated` | Timestamp | Required |
| `dtUpdated` | Timestamp | Required |

Unique: `(iTenantId, virtualExtension)`.

#### `aida_tbl_RingGroupMember`

| Column | Type | Requirement |
| --- | --- | --- |
| `uidRingGroupMember` | CHAR(36) | Primary key |
| `uidRingGroup` | CHAR(36) | Required |
| `uidExtension` | CHAR(36) | Required |
| `iSortOrder` | INTEGER | Required |
| `bEnabled` | BOOLEAN | Default `true` |

Unique: `(uidRingGroup, uidExtension)`.

#### `aida_tbl_AssistantProfile`

| Column | Type | Requirement |
| --- | --- | --- |
| `uidAssistantProfile` | CHAR(36) | Primary key |
| `iTenantId` | BIGINT | Required |
| `name` | String | Required |
| `businessName` | String | Required |
| `prompt` | Long text | Required |
| `tone` | String | Nullable |
| `objective` | Long text | Nullable |
| `openingStatement` | Long text | Nullable |
| `transferStatement` | Long text | Nullable |
| `failedTransferStatement` | Long text | Nullable |
| `bEnabled` | BOOLEAN | Default `true` |
| `dtCreated` | Timestamp | Required |
| `dtUpdated` | Timestamp | Required |

LiveKit model, STT, TTS, and voice defaults are inherited from the predefined
agent `aida-prime`; they are neither stored nor sent for the POC.

#### `aida_tbl_DidRoute`

| Column | Type | Requirement |
| --- | --- | --- |
| `uidDidRoute` | CHAR(36) | Primary key |
| `iTenantId` | BIGINT | Required |
| `didE164` | E.164 String | Required, unique |
| `uidAssistantProfile` | CHAR(36) | Required |
| `destinationType` | Enum | `EXTENSION` or `RING_GROUP` |
| `uidDestinationExtension` | CHAR(36) | Nullable |
| `uidDestinationRingGroup` | CHAR(36) | Nullable |
| `bScreeningEnabled` | BOOLEAN | Default `true` |
| `bEnabled` | BOOLEAN | Default `true` |
| `dtCreated` | Timestamp | Required |
| `dtUpdated` | Timestamp | Required |

Exactly one destination reference matches `destinationType`. The destination is
used for takeover and for failure fallback. Normal inbound order is always:

```
DID -> recording disclosure -> Aida/LiveKit screening -> destination on takeover
```

### 1.3 `aida_db`

| Property | Value |
| --- | --- |
| Database type | MySQL 8 |
| Server home | `LSAidaOffice01` |
| Owning application | AidaControl exclusively (sole schema owner and sole writer) |
| Purpose | Transactional active-call state, ordered events, and commands |

#### `aida_tbl_CallSession`

| Column | Type | Requirement |
| --- | --- | --- |
| `uidCallSession` | CHAR(36) | Primary key |
| `asteriskLinkedId` | VARCHAR(128) | Required, unique |
| `iTenantId` | BIGINT | Required |
| `uidDidRoute` | CHAR(36) | Required |
| `uidAssistantProfile` | CHAR(36) | Required |
| `jProfileSnapshot` | JSON | Required |
| `callerNumber` | VARCHAR(32) | Nullable |
| `roomName` | VARCHAR(128) | Required, unique |
| `agentParticipantSid` | VARCHAR(64) | Nullable |
| `destinationType` | VARCHAR(16) | Required |
| `uidDestination` | CHAR(36) | Required |
| `state` | VARCHAR(32) | Required |
| `iVersion` | INTEGER | Required |
| `dtCreated` | DATETIME(3) | Required |
| `dtEnded` | DATETIME(3) | Nullable |

`iVersion` is the optimistic-concurrency token. Every state transition is a
compare-and-set on `(uidCallSession, iVersion)` and increments it.

#### `aida_tbl_CallEvent`

| Column | Type | Requirement |
| --- | --- | --- |
| `uidCallEvent` | CHAR(36) | Primary key |
| `uidCallSession` | CHAR(36) | Required |
| `iSequenceNumber` | INTEGER | Required |
| `eventType` | VARCHAR(64) | Required |
| `jPayload` | JSON | Required |
| `dtCreated` | DATETIME(3) | Required |

Unique: `(uidCallSession, iSequenceNumber)`.

#### `aida_tbl_ControlCommand`

| Column | Type | Requirement |
| --- | --- | --- |
| `uidControlCommand` | CHAR(36) | Primary key |
| `uidCallSession` | CHAR(36) | Required |
| `idempotencyKey` | VARCHAR(128) | Required |
| `commandType` | VARCHAR(64) | Required |
| `iExpectedCallVersion` | INTEGER | Required |
| `jPayload` | JSON | Required |
| `status` | VARCHAR(32) | Required |
| `dtCreated` | DATETIME(3) | Required |
| `dtCompleted` | DATETIME(3) | Nullable |

Unique: `(uidCallSession, idempotencyKey)`. Pending commands are claimed with
`SELECT ... FOR UPDATE SKIP LOCKED`.

#### `aida_tbl_SchemaMigration`

The applied-migration ledger. Concurrent boots serialise on a `GET_LOCK()`
advisory lock.

### 1.4 OfficePulse Asterisk Realtime database

| Property | Value |
| --- | --- |
| Database type | MySQL |
| Server home | `OfficePulse` |
| Owning application | OfficePulse / Asterisk 22.10.1 |
| Writer | OfficePulseAidaIntegration provisioning API |
| Purpose | Operational PJSIP endpoints, authentication, realtime dialplan, CDR, and CEL |

Vendor schema. Table and column names are Asterisk's and are not renamed.

| Table | POC use |
| --- | --- |
| `ps_endpoints` | Endpoint identity, context, caller ID, transport, codecs |
| `ps_auths` | Generated SIP authentication secret |
| `ps_aors` | Address-of-record and registration configuration |
| `extensions` | Realtime extension, ring-group, and DID-to-FastAGI dialplan rows |
| `cdr` | Asterisk call-detail records |
| `cel` | Asterisk channel-event records |

The SIP secret is stored only in `ps_auths`, returned once to AidaAdmin after
creation or rotation, and optionally passed to the existing provisioning server.
It never enters NocoDB, `aida_db`, browser storage, or logs.

No configuration sync or reconciliation job exists in the POC. AidaAdmin saves
the intended record and immediately invokes OfficePulseAidaIntegration to write
the corresponding Asterisk realtime rows. Provisioning failures are returned to
the administrator; later discrepancies surface as explicit runtime errors.

### 1.5 `echo_db`

| Property | Value |
| --- | --- |
| Database type | MySQL |
| Server home | `proxy.wisp.net` |
| Owning application | `localsplash/EchoDatabase` |
| Purpose | Echo domain data only |

The former Echo database settings table is retired. Echo settings are `cfg_tbl_Setting` rows scoped
to `echo`, `echo-web`, `echo-service`, and `echo-media`. Echo services no longer
read NocoDB coordinates from a shared identity volume; they carry
`NOCODB_BASE_URL` and `NOCODB_API_TOKEN` like every other application, which
also removes the container start-order dependency and the uid-100 invariant.

## 2. Application input interface specifications

JSON field names and HTTP parameters stay camelCase without type prefixes. The
naming standard governs database objects, not wire contracts.

### 2.1 `identity`

Server-only endpoints (`/api/token`, `/api/apps/register`, `/api/events`, and
everything under `/api/directory/`) are admitted by network trust: the resolved
IPv4 peer must sit inside `trustedCIDR`. Browser authorization stays public.

#### Application login

```
Name: authorizeApplication
Interface: HTTP GET https://identity.localsplash.ai/authorize
Parameters:
  redirect_uri: HTTPS URL under localsplash.ai
  state: opaque CSRF value
Result:
  HTTP redirect to redirect_uri with code and state
```

#### Redeem application code

```
Name: redeemApplicationCode
Interface: HTTP POST https://identity.localsplash.ai/api/token
Parameters:
  code: string
  redirect_uri: string
Result:
  user.iUserId: integer
  user.email: string
  user.displayName: string
  user.superAdmin: boolean
  identity.provider: string
  identity.subject: string
  identities[]: provider, subject, email
```

Codes are single-use, expire in five minutes, and are bound to the exact
`redirect_uri` they were minted for. `user.superAdmin` is session-scoped and is
never stored on the user row; redemption returns the consumed code's value and
never recalculates privilege from the email.

`identity` creates or resolves `identity_tbl_User` during successful provider
authentication. AidaAdmin uses `user.iUserId` to look up tenant membership via
the directory API. A Super Admin may enter without a tenant mapping when
`user.superAdmin = true`. A non-Super-Admin with no enabled membership is denied
during the POC.

#### User directory

```
Name: ensureDirectoryUser
Interface: HTTP POST /api/directory/users
Parameters: email, displayName?, idempotencyKey?
Result: iUserId, email, displayName, claimed

Name: getDirectoryUser
Interface: HTTP GET /api/directory/users/{iUserId}

Name: listDirectoryUsers
Interface: HTTP GET /api/directory/users?query=&limit=25&cursor=
```

The ensure is idempotent and concurrency-safe. A pre-created user is
`claimed: false` until a trusted-provider login with a matching verified email
attaches an identity. Responses never carry identities, sessions, codes, or
OAuth credentials.

#### Tenant directory

New in this revision. Replaces the NocoDB `tenant` and `tenant_user` tables.

```
Name: ensureDirectoryTenant
Interface: HTTP POST /api/directory/tenants
Parameters: name, slug, idempotencyKey?
Result: iTenantId, name, slug, enabled

Name: getDirectoryTenant
Interface: HTTP GET /api/directory/tenants/{iTenantId}

Name: listDirectoryTenants
Interface: HTTP GET /api/directory/tenants?query=&limit=25&cursor=

Name: saveDirectoryTenant
Interface: HTTP PUT /api/directory/tenants/{iTenantId}
Parameters: name, slug, enabled

Name: listTenantMembership
Interface: HTTP GET /api/directory/tenants/{iTenantId}/users
Result: [ { iUserId, email, displayName, role, enabled } ]

Name: saveTenantMembership
Interface: HTTP PUT /api/directory/tenants/{iTenantId}/users/{iUserId}
Parameters: role: TENANT_ADMIN | USER, enabled: boolean

Name: listUserMembership
Interface: HTTP GET /api/directory/users/{iUserId}/tenants
Result: [ { iTenantId, name, slug, role, enabled } ]

Name: grantSuperAdmin
Interface: HTTP PUT /api/directory/super-admins/{iUserId}
Parameters: enabled: boolean
Restriction: the authenticated caller must already be SUPER_ADMIN
```

Ensures are idempotent on `slug` or `idempotencyKey`.

#### Register application webhook

```
Name: registerApplicationWebhook
Interface: HTTP POST https://identity.localsplash.ai/api/apps/register
Parameters:
  name: AidaAdmin
  webhook_url: https://app.aida.localsplash.ai/id/events
Result:
  origin: string
  events: string[]
```

#### Receive identity events

```
Name: receiveIdentityEvent
Interface: HTTP POST https://app.aida.localsplash.ai/id/events
Headers:
  X-Id-Event
  X-Id-Event-Id
  X-Id-Timestamp
Body:
  id: integer
  type: ping | session.revoked | user.merged
      | tenant.disabled | tenant.merged
      | identity.linked | identity.unlinked
  occurredAt: timestamp
  data: object
```

`tenant.disabled` carries `{ iTenantId }`; `tenant.merged` carries
`{ fromTenantId, toTenantId }`. Receivers allowlist identity's egress CIDRs at
their ingress, deduplicate on event `id`, and answer 2xx only once the event is
durably handled. Retries back off at 0s, 30s, 2m, 10m, 1h, 6h.

#### Catch up identity events

```
Name: listIdentityEvents
Interface: HTTP GET https://identity.localsplash.ai/api/events
Parameters:
  since: last durably processed event ID
```

### 2.2 AidaAdmin server

The browser calls only same-origin AidaAdmin endpoints. The server writes
NocoDB directly, calls the identity directory API for tenants and membership,
and invokes OfficePulseAidaIntegration for provisioning. AidaControl is not in
the POC configuration-write path.

Tenant and membership writes are proxied to identity, not stored locally:

```
Name: saveTenant
Interface: HTTP PUT /admin/tenants/{iTenantId}
Parameters: name, slug, enabled
Behaviour: proxies to saveDirectoryTenant

Name: saveTenantUser
Interface: HTTP PUT /admin/tenants/{iTenantId}/users/{iUserId}
Parameters: role: TENANT_ADMIN | USER, enabled: boolean
Behaviour: proxies to saveTenantMembership

Name: grantSuperAdmin
Interface: HTTP PUT /admin/super-admins/{iUserId}
Parameters: enabled: boolean
Behaviour: proxies to identity; caller must already be SUPER_ADMIN
```

Aida-owned configuration is written to NocoDB:

```
Name: saveTenantProfile
Interface: HTTP PUT /admin/tenants/{iTenantId}/profile
Parameters: asteriskContext, callerIdName?, callerIdNumber?, enabled

Name: createExtension
Interface: HTTP POST /admin/extensions
Parameters:
  tenantId, userId?, extensionNumber, displayName,
  callerIdName?, callerIdNumber?, provisioningProfile?
Result:
  extensionId, extensionNumber, sipUsername, sipSecret, provisioningResult?

Name: updateExtension
Interface: HTTP PUT /admin/extensions/{extensionId}
Parameters:
  userId?, displayName, callerIdName?, callerIdNumber?,
  provisioningProfile?, enabled

Name: rotateSipSecret
Interface: HTTP POST /admin/extensions/{extensionId}/rotate-secret
Parameters: reprovisionDevice: boolean
Result: sipSecret, provisioningResult?

Name: saveRingGroup
Interface: HTTP PUT /admin/ring-groups/{ringGroupId}
Parameters:
  tenantId, name, virtualExtension, ringTimeoutSeconds,
  musicOnHoldClass?, callerIdName?, callerIdNumber?,
  memberExtensionIds[], enabled

Name: saveAssistantProfile
Interface: HTTP PUT /admin/profiles/{profileId}
Parameters:
  tenantId, name, businessName, prompt, tone?, objective?,
  openingStatement?, transferStatement?, failedTransferStatement?, enabled

Name: saveDidRoute
Interface: HTTP PUT /admin/did-routes/{didRouteId}
Parameters:
  tenantId, didE164, assistantProfileId,
  destinationType: EXTENSION | RING_GROUP,
  destinationId, screeningEnabled, enabled
```

### 2.3 OfficePulseAidaIntegration provisioning API

Private LAN API. Only AidaAdmin's server may call it.

```
Name: provisionExtension
Interface: HTTP POST /v1/provisioning/extensions
Parameters:
  requestId, tenantId, extensionId, extensionNumber, context,
  displayName, callerIdName?, callerIdNumber?, provisioningProfile?
Result: sipUsername, sipSecret, provisioningResult?

Name: updateProvisionedExtension
Interface: HTTP PUT /v1/provisioning/extensions/{extensionId}
Parameters:
  extensionNumber, context, displayName, callerIdName?,
  callerIdNumber?, provisioningProfile?, enabled

Name: rotateProvisionedExtensionSecret
Interface: HTTP POST /v1/provisioning/extensions/{extensionId}/rotate-secret
Parameters: requestId, reprovisionDevice
Result: sipSecret, provisioningResult?

Name: provisionRingGroup
Interface: HTTP PUT /v1/provisioning/ring-groups/{ringGroupId}
Parameters:
  tenantId, virtualExtension, context, memberExtensions[],
  ringTimeoutSeconds, musicOnHoldClass?, callerIdName?,
  callerIdNumber?, enabled

Name: provisionDid
Interface: HTTP PUT /v1/provisioning/dids/{didRouteId}
Parameters: didE164, context, fastAgiPath=/bootstrap, enabled
```

### 2.4 OfficePulseAidaIntegration FastAGI

```
Name: bootstrapInboundCall
Interface: FastAGI TCP agi://aida-integration.internal:4573/bootstrap
Inputs from Asterisk:
  agi_uniqueid
  agi_channel
  agi_callerid
  agi_extension
  ASTERISK_LINKEDID
  OFFICEPULSE_INSTANCE_ID
Outputs set as Asterisk channel variables:
  AIDA_DISPOSITION: SCREEN | FALLBACK | REJECT
  AIDA_CALL_SESSION_ID
  AIDA_ROOM_NAME
  AIDA_SIP_DESTINATION
  AIDA_ROUTE_TOKEN
  AIDA_FALLBACK_CONTEXT
  AIDA_FALLBACK_EXTENSION
```

### 2.5 AidaControl

```
Name: bootstrapCall
Interface: HTTP POST /v1/integrations/officepulse/calls/bootstrap
Parameters:
  officePulseInstanceId, asteriskLinkedId, callerNumber?, didE164
Result:
  disposition: SCREEN | FALLBACK | REJECT
  callSessionId?, roomName?, sipDestination?, routeToken?,
  destinationType?, destinationId?
```

`bootstrapCall` reads NocoDB, snapshots the resolved profile into
`aida_tbl_CallSession.jProfileSnapshot`, dispatches `aida-prime`, waits for
readiness, and returns the LiveKit SIP room destination. Agent dispatch creates
the room if it does not exist.

```
Name: submitCallCommand
Interface: HTTP POST /v1/calls/{callSessionId}/commands
Parameters: commandType, expectedCallVersion, idempotencyKey, payload?

Name: receiveLiveKitWebhook
Interface: HTTP POST /v1/integrations/livekit/webhooks
Authentication: LiveKit signed webhook over the raw request body
```

### 2.6 AidaControl to LiveKit Cloud

```
Name: dispatchAidaPrime
Interface: LiveKit AgentDispatchService.CreateDispatch
Parameters: room, agentName=aida-prime,
            metadata={callSessionId, bootstrapToken}

Name: publishRoomData
Interface: LiveKit RoomServiceClient.sendData
Parameters: room, payload, kind=reliable, topic, destinationSids?
```

### 2.7 AidaHandset

```
Name: receiveCallAlert
Interface: Pusher private-channel event aida.call.started
Parameters: eventId, callSessionId, occurredAt

Name: getActiveCall
Interface: HTTP GET /v1/calls/{callSessionId}
Result: callSession, liveKitUrl, participantToken

Name: requestTakeover
Interface: HTTP POST /v1/calls/{callSessionId}/commands
Parameters: commandType=TAKEOVER, expectedCallVersion, idempotencyKey
```

AidaHandset holds no local copy of tenant, user, or configuration data and never
reaches NocoDB or any database directly.

## 3. POC application scope

1. `localsplash/identity`
2. `localsplash/AidaAdmin`
3. `localsplash/AidaControl`
4. `localsplash/OfficePulseAidaIntegration`
5. `localsplash/AidaAgent`
6. `localsplash/AidaHandset`
7. `localsplash/AidaInfrastructureSetupInstructions`

No database synchronization service, configuration-write API in AidaControl,
queue implementation, first-party WebSocket service, or cross-project system
test repository is part of the POC.
