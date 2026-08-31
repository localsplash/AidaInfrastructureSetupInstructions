# Aida Office POC — Database and Input Interface Specification

Status: Normative for the initial POC
Platform domain: `localsplash.ai`
PBX: OfficePulse / Asterisk 22.10.1 Realtime
Media and voice agent: LiveKit Cloud / `aida-prime`

This document is the concise build contract for the POC. Where the broader
technical specification describes a later or more general configuration API,
this document controls the initial POC.

## 1. Database specifications

### 1.1 `id_db`

| Property | Value |
|---|---|
| Database type | MySQL |
| Server home | `LSAidaOffice01` |
| Owning application | `localsplash/id` |
| Purpose | Shared platform identity, authentication sessions, application handoff codes, and revocation events |

`id_tbl_User.iUserId` is the single platform-wide person identifier. Aida does
not create a second user/person record and does not duplicate the person's
name, email, password, or provider identities.

Existing `localsplash/id` tables:

#### `id_tbl_User`

| Column | Type | Requirement |
|---|---|---|
| `iUserId` | BIGINT | Primary key, auto-increment |
| `email` | VARCHAR(255) | Nullable |
| `displayName` | VARCHAR(255) | Nullable |
| `dtCreated` | DATETIME(3) | Required |
| `dtLastLogin` | DATETIME(3) | Nullable |

#### `id_tbl_Identity`

| Column | Type | Requirement |
|---|---|---|
| `iIdentityId` | BIGINT | Primary key |
| `iUserId` | BIGINT | FK to `id_tbl_User` |
| `provider` | VARCHAR(32) | Required |
| `subject` | VARCHAR(255) | Required |
| `email` | VARCHAR(255) | Nullable |
| `dtCreated` | DATETIME(3) | Required |

Unique: `(provider, subject)`.

#### `id_tbl_Session`

| Column | Type | Requirement |
|---|---|---|
| `sSessionId` | CHAR(64) | Primary key |
| `iUserId` | BIGINT | FK to `id_tbl_User` |
| `bSuperAdmin` | BOOLEAN | Required |
| `sProvider` | VARCHAR(32) | Nullable |
| `sSubject` | VARCHAR(255) | Nullable |
| `dtCreated` | DATETIME(3) | Required |
| `dtLastSeen` | DATETIME(3) | Nullable |
| `dtRevoked` | DATETIME(3) | Nullable |

`id_tbl_AuthCode`, `id_tbl_SsoNonce`, `id_tbl_App`, `id_tbl_Event`, and
`id_tbl_Delivery` retain their schemas and ownership from `localsplash/id`.

### 1.2 `AidaAdmin`

| Property | Value |
|---|---|
| Database type | NocoDB cloud base, MySQL-backed implementation |
| Server home | Existing cloud NocoDB service |
| Owning application | AidaAdmin server |
| Runtime reader | AidaControl |
| Purpose | Slow-moving tenant, telephony intent, DID routing, and prompt configuration |

Only server-side AidaAdmin code holds the NocoDB API token. Browser code,
AidaHandset, OfficePulse, and Asterisk never access NocoDB directly.

#### `tenant`

| Column | Type | Requirement |
|---|---|---|
| `id` | UUID | Primary key |
| `name` | String | Required |
| `slug` | String | Required, unique |
| `asterisk_context` | String | Required, unique |
| `caller_id_name` | String | Nullable |
| `caller_id_number` | E.164 String | Nullable |
| `enabled` | Boolean | Default `true` |
| `created_at` | Timestamp | Required |
| `updated_at` | Timestamp | Required |

#### `tenant_user`

This is a UID mapping and Aida authorization record, not another user record.

| Column | Type | Requirement |
|---|---|---|
| `id` | UUID | Primary key |
| `tenant_id` | UUID | Nullable only for `SUPER_ADMIN` |
| `identity_user_id` | BIGINT | Required; `id_db.id_tbl_User.iUserId` |
| `role` | Enum | `SUPER_ADMIN`, `TENANT_ADMIN`, or `USER` |
| `enabled` | Boolean | Default `true` |
| `created_at` | Timestamp | Required |
| `updated_at` | Timestamp | Required |

Unique: `(tenant_id, identity_user_id)`. A Super Admin may have one record with
`tenant_id = null`. Name and email are returned by `id` at login and are not
copied here.

#### `extension`

| Column | Type | Requirement |
|---|---|---|
| `id` | UUID | Primary key |
| `tenant_id` | UUID | Required |
| `identity_user_id` | BIGINT | Nullable; assignee in `id_tbl_User` |
| `extension_number` | String | Required |
| `display_name` | String | Required |
| `caller_id_name` | String | Nullable; tenant default when absent |
| `caller_id_number` | E.164 String | Nullable; tenant default when absent |
| `asterisk_context` | String | Required |
| `provisioning_profile` | String | Nullable |
| `device_id` | UUID | Nullable, unique; one managed handset per extension for the POC |
| `provisioning_mac` | CHAR(12) | Nullable, unique; uppercase hexadecimal without separators |
| `enrollment_token_hash` | String | Nullable; hash only, never the issued token |
| `enrollment_expires_at` | Timestamp | Nullable |
| `enrollment_consumed_at` | Timestamp | Nullable |
| `device_credential_version` | Integer | Default `1`; increment to revoke issued device credentials |
| `enabled` | Boolean | Default `true` |
| `created_at` | Timestamp | Required |
| `updated_at` | Timestamp | Required |

Unique: `(tenant_id, extension_number)`. One user may have multiple extensions;
one extension has zero or one user and, for the POC, zero or one managed
handset. SIP secrets never enter NocoDB. A MAC address selects the device's
provisioning record but is not an authentication secret.

#### `ring_group`

| Column | Type | Requirement |
|---|---|---|
| `id` | UUID | Primary key |
| `tenant_id` | UUID | Required |
| `name` | String | Required |
| `virtual_extension` | String | Required |
| `asterisk_context` | String | Required |
| `ring_strategy` | Enum | POC value `RING_ALL` |
| `ring_timeout_seconds` | Integer | Default `20` |
| `music_on_hold_class` | String | Nullable |
| `caller_id_name` | String | Nullable |
| `caller_id_number` | E.164 String | Nullable |
| `enabled` | Boolean | Default `true` |
| `created_at` | Timestamp | Required |
| `updated_at` | Timestamp | Required |

Unique: `(tenant_id, virtual_extension)`.

#### `ring_group_member`

| Column | Type | Requirement |
|---|---|---|
| `id` | UUID | Primary key |
| `ring_group_id` | UUID | Required |
| `extension_id` | UUID | Required |
| `sort_order` | Integer | Required |
| `enabled` | Boolean | Default `true` |

Unique: `(ring_group_id, extension_id)`.

#### `assistant_profile`

| Column | Type | Requirement |
|---|---|---|
| `id` | UUID | Primary key |
| `tenant_id` | UUID | Required |
| `name` | String | Required |
| `business_name` | String | Required |
| `prompt` | Long text | Required |
| `tone` | String | Nullable |
| `objective` | Long text | Nullable |
| `opening_statement` | Long text | Nullable |
| `transfer_statement` | Long text | Nullable |
| `failed_transfer_statement` | Long text | Nullable |
| `enabled` | Boolean | Default `true` |
| `created_at` | Timestamp | Required |
| `updated_at` | Timestamp | Required |

LiveKit model, STT, TTS, and voice defaults are inherited from predefined agent
`aida-prime`; they are not stored or sent for the POC.

#### `did_route`

| Column | Type | Requirement |
|---|---|---|
| `id` | UUID | Primary key |
| `tenant_id` | UUID | Required |
| `did_e164` | E.164 String | Required, unique |
| `assistant_profile_id` | UUID | Required |
| `destination_type` | Enum | `EXTENSION` or `RING_GROUP` |
| `destination_extension_id` | UUID | Nullable |
| `destination_ring_group_id` | UUID | Nullable |
| `screening_enabled` | Boolean | Default `true` |
| `enabled` | Boolean | Default `true` |
| `created_at` | Timestamp | Required |
| `updated_at` | Timestamp | Required |

Exactly one destination FK matches `destination_type`. The destination is used
for takeover and failure fallback. Normal inbound order is always:

```text
DID -> recording disclosure -> Aida/LiveKit screening -> destination on takeover
```

### 1.3 `aida_runtime`

| Property | Value |
|---|---|
| Database type | PostgreSQL |
| Server home | `LSAidaOffice01` |
| Owning application | AidaControl exclusively |
| Purpose | Transactional active-call state, ordered events, and commands |

#### `call_session`

| Column | Type | Requirement |
|---|---|---|
| `id` | UUID | Primary key |
| `asterisk_linked_id` | String | Required, unique |
| `tenant_id` | UUID | Required |
| `did_route_id` | UUID | Required |
| `assistant_profile_id` | UUID | Required |
| `profile_snapshot` | JSONB | Required |
| `caller_number` | String | Nullable |
| `room_name` | String | Required, unique |
| `agent_participant_sid` | String | Nullable |
| `destination_type` | String | Required |
| `destination_id` | UUID | Required |
| `state` | String | Required |
| `version` | Integer | Required |
| `created_at` | Timestamp | Required |
| `ended_at` | Timestamp | Nullable |

#### `call_event`

| Column | Type | Requirement |
|---|---|---|
| `id` | UUID | Primary key |
| `call_session_id` | UUID | Required |
| `sequence_number` | Integer | Required |
| `event_type` | String | Required |
| `payload` | JSONB | Required |
| `created_at` | Timestamp | Required |

Unique: `(call_session_id, sequence_number)`.

#### `control_command`

| Column | Type | Requirement |
|---|---|---|
| `id` | UUID | Primary key |
| `call_session_id` | UUID | Required |
| `idempotency_key` | String | Required |
| `command_type` | String | Required |
| `expected_call_version` | Integer | Required |
| `payload` | JSONB | Required |
| `status` | String | Required |
| `created_at` | Timestamp | Required |
| `completed_at` | Timestamp | Nullable |

Unique: `(call_session_id, idempotency_key)`.

### 1.4 OfficePulse Asterisk Realtime database

| Property | Value |
|---|---|
| Database type | MySQL |
| Server home | `OfficePulse` |
| Owning application | OfficePulse / Asterisk 22.10.1 |
| Writer | OfficePulseAidaIntegration provisioning API |
| Purpose | Operational PJSIP endpoints, authentication, realtime dialplan, CDR, and CEL |

Use the installed Asterisk 22.10.1 schemas:

| Table | POC use |
|---|---|
| `ps_endpoints` | Endpoint identity, context, caller ID, transport, and codecs |
| `ps_auths` | Generated SIP authentication secret |
| `ps_aors` | Endpoint address-of-record and registration configuration |
| `extensions` | Realtime extension, ring-group, and DID-to-FastAGI dialplan rows |
| `cdr` | Asterisk call-detail records |
| `cel` | Asterisk channel-event records |

The SIP secret is stored only in `ps_auths`, returned once to AidaAdmin after
creation/rotation, and optionally passed to the existing provisioning server.
It is never stored in NocoDB, Postgres, browser storage, or logs.

No configuration sync or reconciliation job exists in the POC. AidaAdmin saves
the intended record and immediately invokes OfficePulseAidaIntegration to write
the corresponding Asterisk realtime rows. Provisioning failures are returned to
the administrator; later discrepancies surface as explicit runtime errors.

## 2. Application input interface specifications

### 2.1 `id`

#### Application login

```text
Name: authorizeApplication
Interface: HTTP GET https://id.localsplash.ai/authorize
Parameters:
  redirect_uri: HTTPS URL under configured PARENT_DOMAIN (X.TLD)
  state: opaque CSRF value
Result:
  HTTP redirect to redirect_uri with code and state
```

#### Redeem application code

```text
Name: redeemApplicationCode
Interface: HTTP POST https://id.localsplash.ai/api/token
Parameters:
  code: string
  redirect_uri: string
Network authorization:
  source IPv4 must match ID_TRUSTED_APP_CIDRS
Result:
  user.iUserId: integer
  user.email: string
  user.displayName: string
  user.superAdmin: boolean
  identity.provider: string
  identity.subject: string
  identities[]: provider, subject, email
```

`id` creates/resolves `id_tbl_User` during successful provider authentication.
AidaAdmin uses `user.iUserId` to find `tenant_user`. A Super Admin may enter
without a tenant mapping when `user.superAdmin = true`. A non-Super-Admin with
no enabled `tenant_user` record is denied during the POC.

`user.superAdmin` is session-scoped, not a property of `id_tbl_User`. For an
existing SSO session, `/authorize` copies `id_tbl_Session.bSuperAdmin` into the
single-use `id_tbl_AuthCode`; `/api/token` returns that consumed code value. On
a fresh provider login, `id` calculates the value once and writes the same value
to both the new Session and Auth Code. Token redemption never recalculates
Super Admin status from the email address.

#### Register AidaAdmin revocation webhook

```text
Name: registerApplicationWebhook
Interface: HTTP POST https://id.localsplash.ai/api/apps/register
Parameters:
  name: AidaAdmin
  webhook_url: https://app.aida.localsplash.ai/id/events
Network authorization:
  source IPv4 must match ID_TRUSTED_APP_CIDRS
Result:
  origin: string
  events: string[]
```

#### Receive identity events

```text
Name: receiveIdentityEvent
Interface: HTTP POST https://app.aida.localsplash.ai/id/events
Headers:
  X-Id-Event
  X-Id-Event-Id
  X-Id-Timestamp
Network authorization:
  source IPv4 must match ID_EVENT_SOURCE_CIDRS
Body:
  id: integer
  type: ping | session.revoked | user.merged | identity.linked | identity.unlinked
  occurredAt: timestamp
  data: object
```

#### Catch up identity events

```text
Name: listIdentityEvents
Interface: HTTP GET https://id.localsplash.ai/api/events
Parameters:
  since: last durably processed event ID
Network authorization:
  source IPv4 must match ID_TRUSTED_APP_CIDRS
```

#### `id` server-to-server trust

The POC uses TLS plus IPv4/CIDR allowlisting for `id` application-server
traffic and uses no `ID_CLIENT_SECRET` or per-application webhook HMAC secret.
`GET /authorize` and provider callbacks remain public browser endpoints. The
server-only `/api/token`, `/api/apps/register`, `/api/events`, and
`/api/directory/users*` routes require the resolved source IPv4 to match
`ID_TRUSTED_APP_CIDRS`. AidaAdmin's `/id/events` receiver requires the source
IPv4 to match `ID_EVENT_SOURCE_CIDRS`.

Both ingress and application code enforce the CIDR policy. Application code
uses the TCP socket peer by default. It honors a forwarded client address only
when the direct peer belongs to `ID_TRUSTED_PROXY_CIDRS`; arbitrary
`X-Forwarded-For` is never trusted. Production startup/readiness fails when the
required allowlists are empty. Event IDs remain durable and idempotent, but
there is no webhook signature in the POC.

CIDR authorization proves that a request came through an approved
server/network, not which process sent it. Applications sharing an allowed
egress address can call the same protected endpoints. This is accepted for the
first-party POC on controlled `LSAidaOffice01`; it is not a trust model for
unrelated or customer-hosted applications. The `id` redirect contract itself
remains generic for any configured `X.TLD`; `localsplash.ai` is only the POC
deployment value.

### 2.2 AidaAdmin server

The browser calls only same-origin AidaAdmin endpoints. The server writes
NocoDB directly and invokes OfficePulseAidaIntegration for provisioning.
AidaControl is not in the POC configuration-write path.

For runtime call views and commands, AidaAdmin is the browser/session boundary
and proxies only the supported operations to AidaControl. The AidaAdmin backend
originates from an IPv4 in `AIDACONTROL_TRUSTED_SERVER_CIDRS` and sends verified
`X-Aida-Identity-User-Id`, `X-Aida-Tenant-Id`, `X-Aida-Role`,
`X-Aida-Session-Id`, and `X-Aida-Correlation-Id` context. It strips any
browser-supplied `X-Aida-*` trust headers. There is no AidaAdmin-to-AidaControl
shared secret or self-issued staff JWT in the POC.

```text
Name: saveTenant
Interface: HTTP PUT /admin/tenants/{tenantId}
Parameters:
  name, slug, asteriskContext, callerIdName?, callerIdNumber?, enabled
```

```text
Name: saveTenantUser
Interface: HTTP PUT /admin/tenants/{tenantId}/users/{identityUserId}
Parameters:
  role: TENANT_ADMIN | USER
  enabled: boolean
```

```text
Name: grantSuperAdmin
Interface: HTTP PUT /admin/super-admins/{identityUserId}
Parameters:
  enabled: boolean
Restriction:
  authenticated caller must already be SUPER_ADMIN
```

```text
Name: createExtension
Interface: HTTP POST /admin/extensions
Parameters:
  tenantId, identityUserId?, extensionNumber, displayName,
  callerIdName?, callerIdNumber?, provisioningProfile?
Result:
  extensionId, extensionNumber, sipUsername, sipSecret, provisioningResult?
```

```text
Name: updateExtension
Interface: HTTP PUT /admin/extensions/{extensionId}
Parameters:
  identityUserId?, displayName, callerIdName?, callerIdNumber?,
  provisioningProfile?, enabled
```

```text
Name: rotateSipSecret
Interface: HTTP POST /admin/extensions/{extensionId}/rotate-secret
Parameters:
  reprovisionDevice: boolean
Result:
  sipSecret, provisioningResult?
```

```text
Name: issueHandsetEnrollment
Interface: HTTP POST /admin/extensions/{extensionId}/handset-enrollment
Parameters:
  provisioningMac: 12 uppercase hexadecimal characters
  ttlSeconds: integer, default 900
Result:
  deviceId: UUID
  enrollmentToken: one-time random value, returned once
  expiresAt: timestamp
Side effects:
  store only enrollmentToken hash in NocoDB
  send deviceId and plaintext enrollmentToken to the HTTPS provisioning server
```

```text
Name: saveRingGroup
Interface: HTTP PUT /admin/ring-groups/{ringGroupId}
Parameters:
  tenantId, name, virtualExtension, ringTimeoutSeconds,
  musicOnHoldClass?, callerIdName?, callerIdNumber?,
  memberExtensionIds[], enabled
```

```text
Name: saveAssistantProfile
Interface: HTTP PUT /admin/profiles/{profileId}
Parameters:
  tenantId, name, businessName, prompt, tone?, objective?,
  openingStatement?, transferStatement?, failedTransferStatement?, enabled
```

```text
Name: saveDidRoute
Interface: HTTP PUT /admin/did-routes/{didRouteId}
Parameters:
  tenantId, didE164, assistantProfileId,
  destinationType: EXTENSION | RING_GROUP,
  destinationId, screeningEnabled, enabled
```

### 2.3 OfficePulseAidaIntegration provisioning API

Private LAN API. Only AidaAdmin's server may call it.

```text
Name: provisionExtension
Interface: HTTP POST /v1/provisioning/extensions
Parameters:
  requestId, tenantId, extensionId, extensionNumber, context,
  displayName, callerIdName?, callerIdNumber?, provisioningProfile?
Result:
  sipUsername, sipSecret, provisioningResult?
```

```text
Name: updateProvisionedExtension
Interface: HTTP PUT /v1/provisioning/extensions/{extensionId}
Parameters:
  extensionNumber, context, displayName, callerIdName?,
  callerIdNumber?, provisioningProfile?, enabled
```

```text
Name: rotateProvisionedExtensionSecret
Interface: HTTP POST /v1/provisioning/extensions/{extensionId}/rotate-secret
Parameters:
  requestId, reprovisionDevice
Result:
  sipSecret, provisioningResult?
```

```text
Name: provisionRingGroup
Interface: HTTP PUT /v1/provisioning/ring-groups/{ringGroupId}
Parameters:
  tenantId, virtualExtension, context, memberExtensions[],
  ringTimeoutSeconds, musicOnHoldClass?, callerIdName?,
  callerIdNumber?, enabled
```

```text
Name: provisionDid
Interface: HTTP PUT /v1/provisioning/dids/{didRouteId}
Parameters:
  didE164, context, fastAgiPath=/bootstrap, enabled
```

### 2.4 OfficePulseAidaIntegration FastAGI

```text
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

`routeToken` / `AIDA_ROUTE_TOKEN` is a one-time opaque bearer value minted by
AidaControl during `bootstrapCall`. It proves that AidaControl authorized this
OfficePulse inbound SIP leg for exactly one `callSessionId` and LiveKit room.
AidaControl stores only its hash, binds it to the Call Session, room,
OfficePulse instance, and Asterisk linked ID, and expires it after 120 seconds.
OfficePulseAidaIntegration places it in `X-Aida-Route-Token`; the LiveKit SIP
trunk maps that header into a SIP-participant attribute. AidaAgent submits the
token and observed SIP participant identity to AidaControl before beginning the
conversation. AidaControl atomically consumes it. Missing, expired, reused, or
mismatched tokens reject the media leg and trigger the local fallback. It is
not a handset credential, LiveKit API credential, or reusable room token.

### 2.5 AidaControl

#### AidaControl trust boundary

AidaControl uses different trust mechanisms by caller; CIDR trust is not a
universal substitute for authentication:

| Caller | POC trust mechanism |
|---|---|
| AidaAdmin backend | Source IPv4 in `AIDACONTROL_TRUSTED_SERVER_CIDRS` plus verified staff/tenant/session context headers |
| OfficePulseAidaIntegration | Source IPv4 in `AIDACONTROL_TRUSTED_SERVER_CIDRS` plus call identifiers and idempotency controls |
| AidaHandset | Device access token; CIDR alone is never accepted |
| LiveKit webhook | LiveKit signature over the raw body |
| AidaAgent in LiveKit Cloud | One-time call-scoped bootstrap/route credential |
| AidaControl to LiveKit | LiveKit workload API key/secret |

AidaControl uses the TCP socket peer unless the direct peer belongs to
`AIDACONTROL_TRUSTED_PROXY_CIDRS`; only then may it resolve a forwarded client
IPv4. Both ingress and application enforce allowlists. Production readiness
fails when required CIDR configuration is empty. CIDR trust establishes the
approved server/network, not an individual process, so AidaControl still
enforces tenant, role, call, and device scope.

```text
Name: bootstrapCall
Interface: HTTP POST /v1/integrations/officepulse/calls/bootstrap
Parameters:
  officePulseInstanceId, asteriskLinkedId, callerNumber?, didE164
Result:
  disposition: SCREEN | FALLBACK | REJECT
  callSessionId?, roomName?, sipDestination?, routeToken?,
  destinationType?, destinationId?
```

`bootstrapCall` reads NocoDB, snapshots the resolved profile into Postgres,
dispatches `aida-prime`, waits for readiness, and returns the LiveKit SIP room
destination. Agent dispatch creates the room if it does not exist.

```text
Name: submitCallCommand
Interface: HTTP POST /v1/calls/{callSessionId}/commands
Parameters:
  commandType, expectedCallVersion, idempotencyKey, payload?
```

```text
Name: receiveLiveKitWebhook
Interface: HTTP POST /v1/integrations/livekit/webhooks
Authentication:
  LiveKit signed webhook over the raw request body
```

```text
Name: enrollHandset
Interface: HTTP POST /v1/devices/enroll
Authentication: none before enrollment; strict rate limiting applies
Parameters:
  deviceId: UUID
  provisioningMac: 12 uppercase hexadecimal characters
  enrollmentToken: one-time token supplied by the provisioning server
  appInstanceId: UUID generated by AidaHandset
Result:
  deviceAccessToken: short-lived bearer token
  deviceRefreshToken: rotating bearer token, returned once
  accessTokenExpiresAt: timestamp
```

```text
Name: refreshHandsetCredential
Interface: HTTP POST /v1/devices/token/refresh
Parameters:
  deviceId: UUID
  deviceRefreshToken: string
  appInstanceId: UUID
Result:
  deviceAccessToken
  deviceRefreshToken: rotated value
  accessTokenExpiresAt
```

The MAC address locates the intended extension/device record; it never proves
identity. Enrollment succeeds only with the unexpired one-time token delivered
through the HTTPS provisioning service. AidaControl verifies the token hash,
MAC, device ID, extension state, and app instance, consumes the token, and
issues credentials scoped to that device, tenant, and extension.

```text
Name: authorizePusherPrivateChannel
Interface: HTTP POST /v1/realtime/pusher/auth
Authentication: deviceAccessToken bearer
Parameters:
  socket_id: Pusher socket ID
  channel_name: private-aida-device-{deviceId}
Result:
  auth: Pusher channel authorization signature
```

Only the authenticated device whose token contains that `deviceId` may
subscribe. Tenant IDs and extension numbers do not appear in channel names.
Every simultaneous call assigned to the device is announced on the same
private device channel; payloads contain only event ID, callSessionId, type, and
timestamp.

### 2.6 AidaControl to LiveKit Cloud

```text
Name: dispatchAidaPrime
Interface: LiveKit AgentDispatchService.CreateDispatch
Parameters:
  room, agentName=aida-prime,
  metadata={callSessionId, bootstrapToken}
```

```text
Name: publishRoomData
Interface: LiveKit RoomServiceClient.sendData
Parameters:
  room, payload, kind=reliable, topic, destinationSids?
```

### 2.7 AidaHandset

Initial configuration is delivered by the existing HTTPS provisioning server
using the Grandstream MAC-address provisioning record. The provisioned values
are `deviceId`, normalized MAC, AidaControl URL, Pusher application key/cluster,
and the one-time enrollment token. The MAC is public identification data and is
never accepted by itself as authentication.

```text
Name: receiveCallAlert
Interface: Pusher private-channel event aida.call.started
Parameters:
  eventId, callSessionId, occurredAt
```

```text
Name: getActiveCall
Interface: HTTP GET /v1/calls/{callSessionId}
Result:
  callSession, liveKitUrl, participantToken
```

```text
Name: requestTakeover
Interface: HTTP POST /v1/calls/{callSessionId}/commands
Parameters:
  commandType=TAKEOVER, expectedCallVersion, idempotencyKey
```

## POC application scope

The repositories in scope are:

1. `localsplash/id`
2. `localsplash/new_AidaAdmin`
3. `localsplash/new_AidaControl`
4. `localsplash/OfficePulseAidaIntegration`
5. `localsplash/AidaAgent`
6. `localsplash/AidaHandset`
7. `localsplash/AidaInfrastructureSetupInstructions`

No database synchronization service, configuration-write API in AidaControl,
queue implementation, first-party WebSocket service, or cross-project system
test repository is part of the POC.
