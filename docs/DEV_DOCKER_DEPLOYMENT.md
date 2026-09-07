# Planned Aida development deployment

> Historical preparation document. The isolated preview has since launched; see
> [running preview status](DEV_PREVIEW_STATUS.md) for its actual topology and current limits.

Status: **prepared and configuration-validated; services have not been started**.
This composition adds Aida to `dockerappvm01-dev`. The existing Echo, Identity,
NocoDB, and unrelated containers remain under their existing deployment owners.

## Prerequisites before startup

1. Deploy and rehearse [Identity PR #18](https://github.com/localsplash/identity/pull/18)
   and the canonical `PlatformConfig` settings/tenant projection. Preserve working
   Identity data and access. The Aida applications require the central sessions
   and tenant APIs; the older deployed Identity is not sufficient.
2. Check out the reviewed application PRs in sibling directories:
   `AidaInfrastructureSetupInstructions`, `AidaAdmin`, `OfficePulseAidaIntegration`,
   and `AidaAgent` under `/opt/aida`. Record their exact commit SHAs for the release.
   This composition relies on OfficePulse's separate **public 8086** and
   **private 8085** listeners, plus Admin's writable non-root asset directory.
3. Select the actual PBX target and supported adapter credentials. Configure its
   existing LiveKit SIP trunk, disclosure, fallback destinations, and reachability
   from this development server. This stack does not install Asterisk or change
   its vendor schema. Never use the Aida runtime database as the PBX database.
4. Prepare scoped NocoDB tokens and the appropriate source/proxy trust settings
   for Identity. Validate central tenants and memberships with two businesses
   and a SUPER ADMIN. Do not treat a configured CIDR as user authorization.
5. Select the LiveKit project and model/voice settings. The worker name defaults
   to `aida-prime-dev` in both runtime and Agent to avoid sharing dispatch with
   the existing cloud worker. The old Cloud deployment's settings are not inherited.

## Containers and planned ports

| Service | Proposed host mapping | Purpose |
| --- | --- | --- |
| AidaAdmin | `18086 → 3001` | Browser administration, sign-in callback, asset serving |
| OfficePulse public HTTP | `18085 → 8086` | Device enrollment/calls/control and signed LiveKit webhooks |
| OfficePulse private HTTP | **No host port**, `officepulse:8085` inside Aida network | Admin provisioning and administrative commands |
| OfficePulse FastAGI | PBX-facing IP, `4573 → 4573` by default | Raw TCP from the selected Asterisk adapter |
| AidaAgent | **No host port** | Outbound LiveKit agent registration/media |
| Aida MySQL | **No host port** | New `aida_db` and `aida_admin_db` only |

NPM should eventually map `aida-admin.localsplash.dev` to host port **18086** and
`aida-api.localsplash.dev` to **18085**, using HTTP upstreams with HTTPS at NPM.
Point all API paths at 18085: private routes are absent from its listener.
Never proxy or publish 8085. AidaAgent and Android need no hosted UI domain.

Both HTTP host bindings default to `127.0.0.1` for local checks. Containerized
NPM cannot reach another container's or host's loopback address. Before NPM
mapping, set `AIDA_PROXY_BIND_IP` to the server's private interface address that
NPM can reach, and restrict inbound access to the NPM source. Set
`AIDA_TRUSTED_PROXY_CIDRS` to the actual NPM peers as seen by these containers;
do not accept arbitrary client-supplied forwarding headers.

FastAGI likewise defaults to loopback. Set `AIDA_PBX_BIND_IP` to the private
PBX-facing interface and admit only the PBX source. Set
`AIDA_FASTAGI_ADVERTISED_HOST` to the hostname/address the PBX resolves to this
server. A custom `AIDA_FASTAGI_PORT` is used on both sides of the mapping and in
OfficePulse's projected AGI address. FastAGI is not an NPM HTTP proxy host.

The Aida bridge defaults to `172.30.88.0/24`. Check for collisions with existing
Docker/VPN/LAN routes. If it changes, update its subnet and all four static IPs
together. OfficePulse trusts only the configured Admin container's `/32` on
the private listener. Identity source trust is a separate operator setting.

## Configuration and storage

```sh
cd /opt/aida/AidaInfrastructureSetupInstructions
cp deploy/.env.example deploy/.env
chmod 600 deploy/.env
```

Fill the reviewed values in `deploy/.env`. Generate every new Aida database
password independently with `openssl rand -hex 32`. Application passwords must
be exactly 64 hex characters, which makes SQL initialization and URL embedding
unambiguous. Use another long independent value for `AIDA_ADMIN_SESSION_SECRET`.
Do not copy or rotate existing Echo/Identity database passwords for this stack.

The `aida-dev` project creates only its own MySQL and Admin asset named volumes.
The fresh-MySQL initialization script creates:

| Database account | Grants |
| --- | --- |
| `aida_runtime` | Owns `aida_db` schema/data and runs OfficePulse migrations |
| `aida_admin` | Owns `aida_admin_db` OAuth state, event receipts and audit storage |
| `aida_runtime_reader` | `SELECT` only on `aida_db`, supplied only to Admin |

Identity's `platform_db` and Echo's `echo_db` are not created, renamed, or mounted
by this composition. Asterisk adapter values point to the existing PBX database;
the Aida initialization script never touches it. Admin gets no LiveKit server
secret, and Agent gets no Identity, NocoDB, or database credentials. Admin assets
use a persistent directory owned by the image's `node` user.

Initialization runs only for a fresh MySQL data directory. Changing `.env`
passwords later does not change accounts in an existing volume. Rotate accounts
deliberately and update dependent services together. Keep existing Aida volumes
when rebuilding; do not use `docker compose down -v` as an upgrade procedure.

NocoDB still provides `PlatformConfig`; explicit environment overrides here
make the first deployment reviewable. Keep the scoped configuration rows in
sync with chosen deployment values before retiring those overrides. Admin's
automatic Identity webhook registration is initially disabled; review the
public callback and event-source policy before enabling registration separately.

## Validate, build, then start

After filling the file, validate without printing rendered secrets:

```sh
docker compose --env-file deploy/.env -f deploy/docker-compose.dev.yml config --quiet
docker compose --env-file deploy/.env -f deploy/docker-compose.dev.yml build
```

Do not publish the full output of `docker compose config`: it expands passwords
and tokens. The preparation check used synthetic placeholders only and did not
load real environment values or connect to services.

Only after the prerequisites and NPM/PBX ingress are ready:

```sh
docker compose --env-file deploy/.env -f deploy/docker-compose.dev.yml up -d
docker compose --env-file deploy/.env -f deploy/docker-compose.dev.yml ps
```

Startup performs migrations in the two new Aida stores and connects OfficePulse
to the selected PBX/LiveKit project. These are deliberate integration actions;
the preparation work did not execute them. Process health checks do not prove
working providers, business isolation, or carrier audio. Check Admin `/readyz`
and runtime `/readyz` in addition to process health.

Then verify sign-in and tenant access, configure a test DID and extension, enroll
the Android application against `aida-api.localsplash.dev`, and complete one
inbound call with live transcript, caller interruption, successful takeover,
failed takeover, and human hangup. Repeat with another business and test SUPER
ADMIN visibility. Use the master plan's acceptance criteria to record remaining
failures; a green Docker health status alone is not combined-POC acceptance.

## Rebuild and rollback

Record repository SHAs and built image IDs alongside the deployment environment
revision. The default `:dev` tags and `mysql:8.4` are development conveniences;
pin tested images/digests for a released deployment. Review schema compatibility
before reverting application images. Snapshot the new Aida database/asset volumes
and rehearse restoring them independently of the existing Echo and Identity
volumes. Stop or rebuild only the `aida-dev` project during this rollout.
