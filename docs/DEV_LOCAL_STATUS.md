# Running local development

The local development deployment is **launched** on `dockerappvm01-dev`. Nine containers
are running, using isolated copied databases and scoped application users.
Existing Echo, Identity, NocoDB and unrelated services remain unchanged; existing
Echo media is mounted read-only. This report supersedes the earlier
[pre-deployment readiness snapshot](LOCAL_DEV_READINESS.md) for deployment status.
A complete PBX/LiveKit/Android call has not yet been validated.

## Public entry points

Nginx Proxy Manager entries remain user-managed. Existing `echo.localsplash.dev`,
`identity.localsplash.dev` and `nocodb.localsplash.dev` routes still target the
older containers until their upstreams are changed to the destinations below.
Use HTTPS on the browser hostname and HTTP to the listed Docker destination on
`npm_network`. Loopback listeners support local checks; NPM should use the Docker
name rather than its own `127.0.0.1`.

| Development hostname | NPM HTTP destination | Host loopback listener |
| --- | --- | --- |
| `identity.localsplash.dev` | `identity-local:3200` | `127.0.0.1:13200` |
| `aida-admin.localsplash.dev` | `aida-admin-local:3001` | `127.0.0.1:18086` |
| `aida-api.localsplash.dev` | `officepulse-local:8086` **public listener only** | `127.0.0.1:18085` |
| `echo.localsplash.dev` | `echo-web-local:3160` | `127.0.0.1:18160` |
| `nocodb.localsplash.dev` | `platform-nocodb-local:8080` | `127.0.0.1:18087` |

`localsplash.dev` is this host's configured `X.TLD`; other deployments substitute
their own domain and configured public origins. Never proxy OfficePulse's
private `8085` listener or publish it as a public application API.

## Internal services and repository roles

The shared `platform-mysql-local:3306` engine has separate `platform_db`,
`echo_db`, `aida_db` and `aida_admin_db` schemas and application-scoped users.
It has no host port. OfficePulse's private API, Agent, EchoService and EchoMedia
stay internal. Agent's explicit status-only command returns health 200 and
readiness 503; it imports no voice SDK and does not register for jobs or contact
providers. Authenticated media delivery enters through EchoWeb.

All twelve repositories have a `dev` branch: AidaInfrastructureSetupInstructions,
identity, AidaControl, AidaAdmin, OfficePulseAidaIntegration, AidaAgent,
AidaHandset, EchoOrchestrator, EchoMedia, EchoDatabase, EchoWeb and EchoService.
The branches support coordinated development and do not imply twelve server UIs.

- OfficePulse owns orchestration; there is no AidaControl container.
- Infrastructure, EchoOrchestrator and EchoDatabase provide deployment/schema
  artifacts and have no UI container of their own.
- AidaHandset is an Android app. Its debug APK is available to the host operator
  at `/opt/platform-review/aida-handset-debug.apk`; it is not a production release
  and has not completed acceptance on the physical office handset.

## Data and authentication verified

Identity's copied user, provider identity and eight source sessions were
preserved before its additive migration. Exact Echo provider/subject
reconciliation established five canonical users, three businesses and three
owner memberships as `TENANT_ADMIN`. No email matching or new `SUPER_ADMIN`
grants were used. The existing verified platform administrator can see all
three businesses. Real central session handoff/introspection and authenticated
AidaAdmin access have been exercised against the running local deployment.

Echo preserves 45 messages and 17 media records in the copied database. Its
running conversation/message reads and owned attachment streaming passed;
anonymous attachment access returned 401 and a different selected business
received 404 for the same attachment. Three organization and five user mappings
connect these historical records to central Identity.

The local development deployment has a separate NocoDB instance with `PlatformConfig/cfg_tbl_Setting`
and the eight canonical Aida voice tables. Live Identity settings were read and
copied with isolated database, endpoint and trust values. Real voice routing
configuration remains to be supplied. Development credentials, bootstrap files,
session tokens, mapping source records and SQL snapshots are protected host
artifacts and are not part of this repository.

A documented local cookie bridge can adopt an existing browser SSO
cookie only when it matches a nonrevoked SSO row in the copied store. It retains
verified provider/admin provenance and writes a unique host-only local cookie.
This is snapshot authentication: later live logins or revocations do not
synchronize into the local deployment, and local logout does not affect live sessions.
Fresh OAuth login uses the natural development callback, for example
`https://identity.localsplash.dev/auth/google/callback`, which must be allowed by
the provider configuration. Retarget NPM to the local Identity service before
validating browser login. Secure browser cookies require those configured HTTPS origins.

## Remaining acceptance work

Supply the selected PBX and supported adapter settings, LiveKit project and
credentials, model/voice choices, test DID and fallback, and physical handset.
OfficePulse currently has voice disabled; Agent is explicitly status-only.
No Asterisk vendor schema has been changed. Test actual inbound audio, live
transcripts, takeover, failed transfer, hangup and dependency loss across two
businesses and `SUPER_ADMIN` before declaring the voice POC complete.

Echo outbound carrier sends are intentionally disabled in this local deployment: copied
carrier credentials were removed and EchoService runs on an internal network
without an external route. Existing media is mounted read-only. Copied Identity
webhook URLs and pending deliveries were disabled before launch. A healthy
container is not evidence of external voice or carrier acceptance.

The earlier [Aida deployment template](DEV_DOCKER_DEPLOYMENT.md) remains a
portable preparation recipe. The running local deployment uses its own host-local
compositions and one shared local MySQL engine; that template does not describe
the deployed topology. Preserve local volumes and source snapshots during
rebuilds, and coordinate shared database restarts across the local apps.


## Local naming and branch source

The `-local` suffix identifies the containers on this development server. Public
hostnames use the natural `*.localsplash.dev` names; Git branches remain `dev`.
The rename reuses the existing databases, assets, media and secret values.
Existing Docker volume and external-network resource names retain their original
identifiers and are explicitly referenced in Compose so the rename cannot create
empty replacement data stores. The runtime image trees match the coordinated
`dev` source; Identity adds the documented host-local cookie bridge.

Host-local deployment files are in `/opt/platform-local/`, with an inventory and
restart instructions in `/opt/platform-local/README.md`. The former
`/opt/platform-preview/` location has been renamed. Operator credentials, copied
SQL, and validation tokens are excluded from this repository.
