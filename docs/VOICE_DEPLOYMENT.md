# Deploy the voice POC with an existing OfficePulse PBX

This is the current operator guide for the unified platform. It supplements
[the running local inventory](DEV_LOCAL_STATUS.md) and replaces the historical
pre-launch assumptions in DEV_DOCKER_DEPLOYMENT.md. Use the reviewed `main`
revisions together; keep the environment and image digests with the release.

## Where each part runs

| Location | Components and responsibility |
| --- | --- |
| Platform server, currently dockerappvm01-dev | Identity, MySQL, NocoDB PlatformConfig, AidaAdmin, OfficePulseAidaIntegration, AidaAgent, and Echo containers |
| Existing OfficePulse/Asterisk server | Carrier/SIP trunks, extensions, RTP media, ARI, existing Realtime database, Aida dialplan includes and audio prompts |
| LiveKit project | Rooms, SIP integration, agent dispatch, audio/data transport; hosted inference for the current worker |
| Office handset | AidaHandset Android application plus the existing phone/SIP configuration |

OfficePulseAidaIntegration is already running on this platform server as
`officepulse-local`. It is the orchestrator and PBX adapter. A second copy on
the PBX is unnecessary. It could instead run on a private host near the PBX,
but then private routing, source allowlists, advertised FastAGI address and
Admin's runtime database read connection must follow it. Run one active
orchestrator per PBX integration for this POC. AidaControl is deferred.

## Current state on dockerappvm01-dev

Admin and Identity sign-in, role management and device enrollment have been
verified. The runtime is deliberately configured with `VOICE_ENABLED=false`;
its `/healthz` is healthy and `/readyz` returns 503 until voice is enabled.
AidaAgent uses its status-only `preview` command and is not accepting LiveKit
jobs. The command is historical terminology; container names remain `-local`.
No real PBX/LiveKit/Android call has been validated on this deployment.

The persistent compositions are under `/opt/platform-local/`:

- `identity/compose.yaml`: Identity, shared local MySQL and NocoDB.
- `admin/compose.yaml`: AidaAdmin; private runtime URL is
  `http://officepulse-private-local:8085`.
- `aida/compose.yaml`: OfficePulse integration; settings overrides in `runtime.env`.
- `agent/compose.yaml`: local Agent; needs real worker settings before activation.

Preserve their named volumes. Rebuilding a container does not migrate data to a
new server. Back up and restore-rehearse `platform_db`, `aida_db`,
`aida_admin_db`, `echo_db`, NocoDB data/configuration, and Admin/media assets for
a server move. Preserve provider identities, sessions, tenant mappings and
application secrets. The development cookie bridge is host-local and should
not be copied as a production authentication design.

## 1. Prepare the existing PBX

Use the files in [OfficePulseAidaIntegration](https://github.com/localsplash/OfficePulseAidaIntegration):

1. Check the existing Asterisk version, loaded ARI/Stasis and Realtime modules,
   SIP transport, live trunks and database schema against this adapter. The
   shipped templates target the existing Asterisk 22.10.1 integration. Keep
   Asterisk vendor tables and their migration ownership unchanged.
2. Merge `asterisk/http.conf.template` and `asterisk/ari.conf.template` into
   the PBX's supported configuration. Create a dedicated ARI account and bind
   ARI to a private interface. Configure `ARI_URL`, `ARI_USERNAME`,
   `ARI_PASSWORD`, and `ARI_APP=aida` for the integration.
3. Review `asterisk/extconfig.conf.template` against the PBX's existing
   Realtime mapping. Supply a dedicated adapter SQL account using the reviewed
   `deploy/sql/grants.sql`. Apply `deploy/sql/schema.sql` only to create the
   integration-owned bookkeeping tables next to the existing Realtime data.
   It does not create or alter Asterisk's vendor tables. Set `MYSQL_*` to this
   existing PBX database, not to `aida_db`.
4. Install the reviewed `asterisk/extensions_aida.conf` include through the
   PBX's supported custom-include mechanism, and configure the MOH template as
   needed. Preserve the existing dialplan and recording integration.
5. Generate or provide the three audio prompts in `prompts/manifest.json`,
   populate their checksum pins, validate with `npm run validate:prompts`, and
   deploy with the reviewed `scripts/deploy-prompts.sh`. The repository's
   unfilled checksum entries are not deployment-ready audio assets.
6. Verify an existing LiveKit SIP trunk endpoint, matching LiveKit inbound SIP
   configuration/dispatch, and required `X-Aida-*` header handling. Set
   `LIVEKIT_TRUNK_ENDPOINT` and `LIVEKIT_SIP_HOST`. Match `LIVEKIT_AGENT_NAME`
   with the worker name. Verify carrier/SIP/RTP reachability using the site's
   actual network policy.

Back up the PBX configuration and integration bookkeeping before changes.
The integration provisions desired rows via supported APIs; it does not own
Asterisk upgrades. Do not run the historical `runtime-schema.sql` manually on
the PBX: runtime migrations belong to the separately configured `aida_db` and
are packaged in the integration Docker image. Prefer the Docker path here;
the older systemd installer comments predate the packaged migration contract.

## 2. Connect the private network

| From | To | Port/purpose |
| --- | --- | --- |
| PBX | Platform integration | TCP 4573, FastAGI bootstrap |
| Integration | PBX | Private ARI HTTP/WebSocket (normally 8088), MySQL 3306 |
| AidaAdmin | Integration | Private HTTP 8085, provisioning and staff commands |
| NPM | Integration | Public listener 8086, handset APIs and signed LiveKit webhooks |
| Platform services | Identity, NocoDB, runtime MySQL | Private authorization/configuration/data connections |
| Integration, worker, handset, PBX SIP path | LiveKit | Project-specific control, media and data ports |

The current `aida/compose.yaml` exposes only public HTTP on host loopback
18085; FastAGI is not published. Add a TCP mapping on the actual private
PBX-facing host address, for example this template under `ports`:

```yaml
- "<PBX-facing-private-IP>:4573:4573"
```

Replace the placeholder; admit only the PBX source address. Set
`FASTAGI_ADVERTISED_HOST` to the private DNS name/IP the PBX can resolve and
reach, and keep the advertised port consistent. FastAGI is not an NPM HTTP
proxy host. Retain the existing separate private/public listener bindings and
source allowlists. Keep ARI, SQL and 8085 off public ingress.

The existing NPM mappings stay:

- `aida-admin.localsplash.dev` → `aida-admin-local:3001`.
- `aida-api.localsplash.dev` → `officepulse-local:8086`.
- `identity.localsplash.dev` → `identity-local:3200`.

Use the equivalent chosen hostnames under `localsplash.ai` for production and
update Identity's allowed origins/provider callbacks. An Agent hostname is not
needed. Cross-server NPM routing must use a reachable private address rather
than Docker DNS names from another machine.

## 3. Configure runtime, LiveKit and the worker

Application bootstrap is the NocoDB URL and server API token. Runtime settings
can live in `PlatformConfig/cfg_tbl_Setting`, scoped `officepulse` → `aida` →
`*`. Nonblank environment overrides win; inspect the protected local
`runtime.env` for overrides before editing a row. Restart after connection or
provider setting changes. Required categories are:

- Existing PBX: `OFFICEPULSE_INSTANCE_ID`, `ARI_*`, `MYSQL_*`, FastAGI address,
  trunk endpoint and codec/transport choices.
- Owned runtime: `RUNTIME_MYSQL_*` pointing at the existing `aida_db`. Keep
  Admin's separate runtime reader account. Startup applies locked additive
  migrations to that database only.
- Platform: Identity base URL and admitted server source; read access to the
  canonical NocoDB voice tables; actual server/proxy CIDRs.
- LiveKit: `LIVEKIT_URL`, `LIVEKIT_API_KEY`, `LIVEKIT_API_SECRET`,
  `LIVEKIT_SIP_HOST`, `LIVEKIT_TRUNK_ENDPOINT`, `LIVEKIT_AGENT_NAME`.
- Optional integrations: Pusher public/private values and the site's existing
  phone provisioning service. Verify those separately if enabled.

Configure LiveKit's signed webhook delivery to
`https://aida-api.localsplash.dev/v1/integrations/livekit/webhooks` and use the
corresponding production URL there. NPM must pass the raw request body.

For the Agent, use [AidaAgent's .env.example](https://github.com/localsplash/AidaAgent/blob/main/.env.example)
as the key inventory. Create protected `/opt/platform-local/agent/agent.env`,
reference it with `env_file: agent.env` in its Compose service, and replace
`command: [preview]` with `command: [start]`. Supply LiveKit credentials plus
explicit `AIDA_LLM_MODEL`, `AIDA_STT_MODEL`, `AIDA_TTS_MODEL`, `AIDA_TTS_VOICE`
and `AIDA_AGENT_NAME`. The current worker uses LiveKit Inference; self-hosted
LiveKit alone does not supply that hosted inference service.

Use the same dispatch name on both sides, such as `aida-prime-dev`, to avoid
competing with an existing cloud worker. Agent needs no database or NocoDB
credentials and no public ingress. Set `VOICE_ENABLED=true` only once the PBX,
project, prompts, routing and worker configuration are ready.

## 4. Start and prove a call

Validate the existing compositions without printing expanded secrets, then
recreate only the integration and worker:

```sh
docker compose -f /opt/platform-local/aida/compose.yaml config --quiet
docker compose -f /opt/platform-local/agent/compose.yaml config --quiet
docker compose -f /opt/platform-local/aida/compose.yaml up -d
docker compose -f /opt/platform-local/agent/compose.yaml up -d
```

In AidaAdmin create/review the business voice profile, extension, ring group,
assistant profile and test DID route. Give every DID an enabled destination in
the same business for local fallback; provision/re-provision the DID after its
fallback changes. Verify desired records actually provision into the PBX after
voice activation, including records saved while voice was disabled.

Install the AidaHandset APK on the supported Android handset. Enroll it using
AidaAdmin's one-time extension enrollment grant and the public API URL. Device
enrollment does not configure SIP audio: retain/configure the handset's normal
PBX/SIP account separately. The app's LiveKit connection is data-only for live
transcripts; the telephone handles call audio.

Require `/readyz` success and a real inbound test: disclosure, caller/agent
audio, live Android transcript, successful and unanswered takeover, hangup in
both directions, device revocation, and dependency-loss fallback. Repeat for
two businesses and verify Super Admin visibility. A connected human call must
survive Agent/runtime failure. Until these pass, the external voice POC remains
unvalidated even when all containers are healthy.

Echo carrier sends remain disabled on this local deployment. Enabling real
SMS/MMS is a separate carrier/configuration/network cutover. This release merge
does not enable carrier traffic or reconfigure the remote PBX automatically.
