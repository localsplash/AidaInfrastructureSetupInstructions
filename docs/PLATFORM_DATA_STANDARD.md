# Platform Data Standard

Status: Normative for every `localsplash` application repository.
Supersedes any per-repo naming or storage convention.

## 1. Storage tiers

Every application answers the same three questions the same way.

| Tier | Store | Contains | Sole writer |
| --- | --- | --- | --- |
| Configuration | NocoDB base `PlatformConfig` | Deployment settings, credentials, public endpoints, slow-moving application configuration | The owning application's server-side admin code |
| Platform master data | MySQL `platform_db` | People and business clients: users, identities, sessions, tenants, tenant membership | `localsplash/identity` only |
| Application data | The application's own MySQL database | Domain tables: call state, messages, events | That one application only |

### 1.1 Environment files

An application's environment file carries exactly two values:

```
NOCODB_BASE_URL
NOCODB_API_TOKEN
```

Everything else — database coordinates, public URLs, OAuth credentials, trusted
network — is a row in `cfg_tbl_Setting`. The only exception is a container that
hosts a store and therefore cannot read its own credentials out of it (the MySQL
container's `MYSQL_*` variables).

Any setting key may be overridden by an environment variable of the same name.
An overridden key is read-only in the admin UI and is never copied into the
store. Blank counts as unset. This is an escape hatch, not the normal path.

### 1.2 The base is found by name

The NocoDB base ID is resolved from the name `PlatformConfig` at runtime and
never written to a configuration file, where it would survive a rename and
outlive a restore. Two bases sharing the name is a configuration error that no
application guesses its way past.

Settings are cached in-process for 30 seconds, along with the resolved base and
table IDs. A failed read drops the cache. A write through an admin UI
invalidates immediately.

### 1.3 Failure is loud

There is no fallback to defaults. If NocoDB is unreachable, the token is
rejected, or no base named `PlatformConfig` exists: retry once after 5 seconds
at startup, then exit non-zero naming which of the three failed. At runtime,
requests needing settings answer `503`. `/healthz` needs no settings and keeps
answering, so "the process is up" stays distinguishable from "the process cannot
read its configuration."

## 2. Cross-store rule

**No foreign key ever crosses a database boundary.**

Cross-store references are values, not constraints. `iUserId` and `iTenantId`
appear in application databases and in NocoDB as plain columns. Integrity is
maintained by the identity event stream, not by the engine:

| Event | Receiving application must |
| --- | --- |
| `session.revoked` | End its own sessions for that user |
| `user.merged` | Repoint local rows from `fromUserId` to `toUserId` |
| `tenant.disabled` | Stop serving that tenant |
| `tenant.merged` | Repoint local rows from `fromTenantId` to `toTenantId` |
| `identity.linked` / `identity.unlinked` | Usually nothing |

Receivers are idempotent on event id, answer 2xx only once the event is durably
handled, and catch up at boot with `GET /api/events?since=<lastId>`.

## 3. Naming

The standard governs **database objects**. It does not govern JSON field names,
HTTP parameters, environment variable keys, or Docker service names — those stay
in their existing conventions and do not churn.

### 3.1 Databases

`snake_lower`: `platform_db`, `aida_db`, `echo_db`.

### 3.2 Tables

`<prefix>_tbl_<PascalSingular>`

- `identity_tbl_User`, `identity_tbl_Tenant`
- `aida_tbl_CallSession`, `aida_tbl_DidRoute`
- `echo_tbl_Message`
- `cfg_tbl_Setting`

The prefix names the owning domain, not the physical database, so a table keeps
its name if it moves between stores.

### 3.3 Columns

Type prefix, then a PascalCase descriptive name. String columns carry no prefix.

| Prefix | Type | Example |
| --- | --- | --- |
| `i` | integer, bigint | `iUserId`, `iRingTimeoutSeconds` |
| `uid` | a unique identifier of our own definition | `uidCallSession`, `uidExtension` |
| `dt` | datetime | `dtCreated`, `dtRevoked` |
| `b` | boolean | `bEnabled`, `bSuperAdmin` |
| `j` | JSON | `jPayload`, `jProfileSnapshot` |
| `n` | decimal / numeric | `nMonthlyRate` |
| *(none)* | any string type | `email`, `displayName`, `asteriskContext` |

A `uid` column names an identifier already, so it takes no `Id` suffix:
`uidCallSession`, never `uidCallSessionId`.

`iUserId` keeps its established spelling. It is the platform-wide person
identifier and already appears in the identity OpenAPI contract, every event
payload, and every application's mapping rows; renaming it buys nothing.

### 3.4 Choosing `i` versus `uid`

- **`i` (BIGINT AUTO_INCREMENT)** for master data joined only within our own
  systems: users, identities, tenants, tenant membership.
- **`uid` (CHAR(36), UUIDv4)** where the identifier is minted outside a single
  database, spans stores, or is handed to something untrusted: call sessions,
  control commands, extensions, DID routes, assistant profiles, and anything the
  handset, the agent, or Asterisk can observe.

### 3.5 Standard columns

Every table we own carries `dtCreated`. Mutable tables carry `dtUpdated`.
Tables representing something that can be switched off carry `bEnabled`
defaulting to true. Prefer disabling to deleting.

### 3.6 Third-party schemas

Vendor-defined schemas keep their own naming, untouched and unwrapped. This is a
recorded decision, not drift:

- Asterisk 22.10.1 realtime: `ps_endpoints`, `ps_auths`, `ps_aors`,
  `extensions`, `cdr`, `cel`
- NocoDB system columns on every base table

Our own tables inside a NocoDB base follow the standard. Anything NocoDB adds
does not.

## 4. Engine

MySQL 8 everywhere we own the schema. One engine means one dialect, one driver,
one backup and restore procedure, one migration runner, and one naming rule.

The alternate SQL engine is not used. It folds unquoted identifiers to lowercase, which would
silently turn `dtCreated` into `dtcreated` unless every reference in every
hand-written migration is quoted — a rule that will be broken eventually and
fails quietly when it is.

MySQL 8 covers what the runtime stores need:

| Need | MySQL 8 mechanism |
| --- | --- |
| Structured event payloads | `JSON` columns |
| Ordered, gap-free events | `UNIQUE (uidCallSession, iSequenceNumber)` |
| Optimistic concurrency | `iVersion` column, compare-and-set on update |
| Work claiming | `SELECT ... FOR UPDATE SKIP LOCKED` |
| Serialised concurrent boots | `GET_LOCK()` advisory lock |

## 5. Migrations

Each database has exactly one schema owner, named in the table below, and that
repository is the only source of its DDL.

| Database | Schema owner |
| --- | --- |
| `platform_db` | `localsplash/identity` |
| `aida_db` | `localsplash/AidaControl` |
| `echo_db` | `localsplash/EchoDatabase` |
| `PlatformConfig` (NocoDB) | `localsplash/identity` creates the base and `cfg_tbl_Setting`; each application creates and owns its own `<prefix>_tbl_*` tables within it |
| OfficePulse Asterisk realtime | Asterisk; we do not migrate it |

Migrations are an ordered, append-only list of named, additive changes, each
recorded in a `<prefix>_tbl_SchemaMigration` ledger and applied at boot. A fresh
database gets everything; an existing one gets only what it has not seen; a
second run is a no-op. Never edit, rename, or reorder a released migration.

Because migrations are additive, rolling the application back is always safe.
Rolling the schema back means restoring the dump taken before the deploy, which
is why the dump comes first.

## 6. Secrets

| Secret | Lives in | Never in |
| --- | --- | --- |
| NocoDB API token | The environment file | Anywhere else |
| Database passwords, OAuth client secrets, UISP keys | `cfg_tbl_Setting`, rows flagged `bSecret` | Application databases, logs |
| SIP authentication secrets | Asterisk `ps_auths` only | NocoDB, `aida_db`, browser storage, logs |

A SIP secret is returned exactly once to the caller that created or rotated it,
and is never read back.

`trustedCIDR` is one value for the whole platform, spelled once as an
application-scope `*` row in `cfg_tbl_Setting`, and enforced at both the edge
and the application layer.
