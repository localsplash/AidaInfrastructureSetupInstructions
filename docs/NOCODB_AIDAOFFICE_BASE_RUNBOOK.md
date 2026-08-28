# Operator runbook — consolidating Aida's NocoDB tables into the `AidaOffice` base

Scope: the cross-project ordering, namespace, safety, verification, and rollback
rules for moving every Aida project's NocoDB tables into one base named
`AidaOffice`. Each project's own copy steps live in that project's repository;
this runbook owns only what no single project can own.

Canonical specification: [Aida Voice Platform technical specification](AIDA_VOICE_PLATFORM_TECHNICAL_SPECIFICATION.md),
§5.1, §5.6, and §6.3. This runbook is part of the NocoDB automation work tracked
in [#4](https://github.com/localsplash/AidaInfrastructureSetupInstructions/issues/4);
the scripts described there operate against the base this runbook establishes.

## Why one base

NocoDB link fields — its foreign-key equivalent — resolve only within a single
base. While Aida's tables are spread across one base per project, no
relationship can cross a project boundary. Consolidating into `AidaOffice`
makes those relationships expressible. Projects are then separated by table
name rather than by base.

## Before you start: confirm the data volume

Do this first, because it decides how much of the rest applies.

Count the rows in every table of every base being consolidated. For a POC
deployment the expected answer is few or no rows, and the whole procedure
collapses to: create `AidaOffice`, point every project at it, let each
project's schema automation create its own tables, retire the old bases.
No copy tooling is needed and none should be written.

Write copy tooling only if the counts show real data. If they do, the copy
rules in [Secret handling](#secret-handling) are mandatory.

## Participants and how each addresses the base

| Project | Tables owned | How it addresses the base |
|---|---|---|
| AidaControl | the 12 listed below | by identifier, `NOCODB_BASE_ID` |
| `id` | `oAuthConfig` | by title, `NOCODB_BASE_NAME`, find-or-create |
| AidaAdmin | `appConfig`, and reads `oAuthConfig` | by title, `NOCODB_BASE_NAME` |

AidaAdmin is the only project spanning two bases today, which is what the
consolidation removes.

## Ordering

The base must exist before any project is repointed at it.

1. **Create `AidaOffice` once.** Whichever project runs first creates it. Every
   other project must find that base, not create a second one.
2. **Verify the base exists and is unique** before repointing anything: list the
   bases and confirm exactly one is titled `AidaOffice`.
3. **Repoint projects one at a time**, confirming after each that no second base
   appeared.

This ordering guards a real failure mode rather than a theoretical one. `id`
creates the base on demand when it is absent (`settings.ts`, find-or-create), so
a typo in `NOCODB_BASE_NAME` produces a second, empty base and a split brain
instead of an error. The same is true for any find-or-create consumer. Treat the
base title as an exact-match deployment value: set it from one source, copy it
between environments rather than retyping it, and check the base list after
every project's first run against the new configuration.

AidaControl addresses the base by `NOCODB_BASE_ID` and so fails loudly on a bad
value. That is the safer addressing mode, and it is why AidaControl is a good
candidate to run first and create the base.

## Collision rule

With one base, table names are a shared namespace across all Aida projects.

A table name is claimed by exactly one project. Before adding a table, a project
checks the inventory below and extends it in the same change. Nothing collides
today.

Current inventory:

| Owner | Tables |
|---|---|
| AidaControl | `tenant`, `tenant_external_reference`, `platform_appearance`, `assistant_profile`, `assistant_profile_version`, `profile_draft`, `inbound_route`, `device`, `device_destination_binding`, `configuration_source`, `crm_import_record`, `audit_event` |
| `id` | `oAuthConfig` |
| AidaAdmin | `appConfig` |
| Cross-project | `aida_application`, `aida_system_setting` |

The two cross-project tables are read and written by every service. AidaControl's
versioned manifest is their single definition and no other project may create
them.

**Ownership runs to columns, not just to table names.** Two services that each
create the same table on demand will disagree about its columns, and whichever
loses the race then reads a column that is not there. That failure is silent at
startup and surfaces later as an authentication failure nobody can place. Before
pointing a service at the base, confirm it finds these tables rather than
creating them.

Generic names are the risk: a future `config`, `settings`, `user`, or `event`
table is far likelier to collide than any name in the list above. A project
whose natural table name is generic prefixes it with the project name.

## The service registration lock

`aida_system_setting` holds `application_registration_open` per environment. It
works like a domain transfer lock, and standing up or repointing a base is
exactly when it matters.

While the lock is open, any service that starts publishes its public key into
`aida_application` and every other service honours it immediately. That is what
makes first startup possible, and it also means anyone who can write to the base
can mint a credential the whole platform trusts. An open lock is a state to pass
through, not to sit in.

Order of operations:

1. Confirm the lock is open for the environment being worked on, and only that
   environment.
2. Start every service with its own `AIDA_APP_PRIVATE_KEY` set. Never let a
   service generate an ephemeral key outside development.
3. Read `aida_application` and confirm the rows present are exactly the expected
   applications, in the expected environment, and nothing else.
4. Close the lock.
5. Restart one service and confirm it still works with the lock closed. That
   proves its key is persistent rather than generated per process.

Keys do not expire, so there is nothing to schedule and no overlap window to
wait out. Replacing a key that was lost or is believed compromised is a
deliberate procedure: open the lock, restart that service with the new key,
confirm the row, close the lock. Peers refuse the service until their cached
copy of the old key turns over, which is expected rather than a fault.

To take one application out of service without touching the lock, untick
`enabled` on its row. That refuses that application everywhere and leaves every
other credential alone.

## Foreign projects must not be destructive

Every project's schema automation must be strictly additive within `AidaOffice`:
it creates and validates its own tables, and reports tables it does not
recognize rather than dropping or altering them.

AidaControl's automation already behaves this way. In a private base that was a
nicety; in a shared base it is load-bearing, because an automation that
reconciles the base against its own manifest would delete another project's
tables. Hold every future project to the same requirement before it is pointed
at the base.

## Secret handling

Both `oAuthConfig` and `appConfig` carry secret-bearing configuration.

If rows must be copied, copy them directly from base to base through the NocoDB
API, in one process, in memory. Never stage them through a file, an export, a
clipboard, a spreadsheet, a scratch table, a shell history entry, or a log line.
Do not print row contents on success or failure; log table names and row counts
only.

If a secret is exposed during the move, rotate it rather than deleting the
artifact that exposed it.

## Verification

Run all of these after repointing and before retiring anything.

- **Row counts per table.** Each table in `AidaOffice` holds the same count as
  its source table. For an empty POC base, confirm the expected tables exist and
  are empty rather than missing.
- **Sign-in end to end.** Complete a real sign-in through AidaAdmin against
  `id`. `id` is on the authentication path and reads `oAuthConfig`, so a wrong
  base or a missed row shows up here first.
- **AidaAdmin configuration reads.** Confirm AidaAdmin reads both `appConfig`
  and `oAuthConfig` from the one base.
- **Profile-version checksums.** AidaControl's `assistant_profile_version`
  checksums still validate, confirming the immutable JSON survived the move
  unaltered.
- **Schema validation.** Each project's NocoDB validate command reports no drift
  and no unexpected removals.
- **The registration lock is closed** for the environment, and `aida_application`
  holds exactly the expected rows and no others.

## Rollback

Retire the old bases by renaming them with a `retired-` prefix — for example
`retired-AidaControl` — rather than deleting them. Rollback is then a
configuration change: point the affected project's `NOCODB_BASE_ID` or
`NOCODB_BASE_NAME` back at the renamed base, restart it, and re-run the
verification steps.

Keep the retired bases for at least one full backup cycle after the
consolidation is confirmed good, then delete them deliberately as a separate,
announced step.

Renaming a base changes its title but not its identifier. A consumer addressing
a retired base by title stops finding it, which is the intended effect; a
find-or-create consumer will create a fresh empty base instead, so repoint such
consumers before renaming, not after.
