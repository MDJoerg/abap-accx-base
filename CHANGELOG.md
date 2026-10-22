# Changelog

All notable changes to Access Explorer (ACCX). Versions follow `MAJOR.MINOR.PATCH`; the
release of an installed system is `ZIF_ACCX_TYPES=>CO_RELEASE`. Repository columns:
**base** = abap-accx-base, **mcp2** = abap-accx-mcp2, **admin** = abap-accx-plugin-admin,
**test** = abap-accx-test.

## 0.35.0 – 2026-10-22

- New adapter package `ZACCX_MCP1` (repository abap-accx-mcp1) for the older
  [abap-ai/mcp](https://github.com/abap-ai/mcp) SDK, with tools, prompts and resources like
  the mcp2 adapter. It needs the SDK authorization object `ZMCP_SRV` for the callers.
- New optional package `ZACCX_GUI` (repository abap-accx-gui): report
  `ZACCX_PROFILE_MAINTAIN` to list, create, change and delete server profiles, with checks
  and a test run.
- Shared by both adapters, new in base: `ZCL_ACCX_RESULT_TEXT` (text of a result) and
  `ZCL_ACCX_SERVER_INFO` (server description and instructions).

- Prompts and resources for MCP clients (base, mcp2). A **prompt** is a ready-made
  instruction the user picks in the client; a **resource** is readable background text.
  New plugin contracts `ZIF_ACCX_PROMPT` and `ZIF_ACCX_RESOURCE`, optional plugin methods
  `get_prompts` and `get_resources` (existing plugins stay valid, the core API version is
  unchanged), and runtime methods `get_prompts`, `get_prompt`, `get_resources` and
  `read_resource`. The MCP2 adapter serves them as prompts/list, prompts/get, resources/list
  and resources/read.
- Prompts (CORE plugin): `diagnose_access_problem`, `fiori_app_not_working` and
  `quarterly_access_review`. A prompt is offered only where all tools it relies on are
  available to the caller. The texts are fixed and contain no system data; the only variable
  parts are the declared arguments (one line, at most 100 characters).
- Resources (CORE plugin): `accx://tool-guide` (which tool for which question, limited to the
  tools of the server), `accx://glossary` and `accx://faq`.

## 0.34.0 – 2026-10-22

- Privacy modes `PSEUDONYMIZE` and `MINIMIZE` (base), selected with `PRIVACY_MODE` in the
  server profile. User ids in results become stable pseudonyms (`U-` and eight hex
  characters, a keyed hash with a random key per client), person names and contact data are
  removed, and `MINIMIZE` also rounds the last logon to the month. User ids found in the data
  are replaced in all other text of the result as well. A pseudonym in a tool argument is
  turned back into the user, so a client can continue with what it was given. Revealing a
  pseudonym is possible only for people, with the new report `ZACCX_PSEUDONYM_RESOLVE`
  (display authorization for the user, logged). Table `ZACCX_PII` extends or switches off the
  rules for personal fields, table `ZACCX_SECRET` holds the key. Results that cannot be
  protected (sorted or hashed tables, serialized data) are withheld.
- `get_user_hygiene_report` and `analyze_user_group` return the last logon date per user.
- The messages of failed tool calls go through the privacy strategy as well.

## 0.33.0 – 2026-10-21

- New tool `simulate_cds_access` (base): evaluates the CDS access control of a CDS entity for
  a given user with the ACM runtime (the same evaluation as transaction SACMSEL). It returns
  full / restricted / no access, the WHERE condition with the user's values, the
  authorization objects with values and source roles, and missing objects. Optionally it
  counts visible and total rows (never row content). Counting requires the caller's
  authorization for a data preview without access control (S_DEVELOP).
- `get_cds_access_control` points to the simulation as next step.

## 0.32.0 – 2026-10-21

- New tools `get_cds_access_control` and `find_unprotected_cds_exposures` (base): DCL roles
  protecting an entity, authorization check annotation, PFCG objects used by the DCL
  conditions, and service definitions / bindings exposing entities without protection.

## 0.31.0

- New tools `get_user_hygiene_report` and `get_authorization_changes` (base): logon hygiene of
  users and standard users; role, assignment, profile and user-master changes from change
  documents.

## 0.30.0

- New tools `compare_users` and `analyze_user_group` (base).

## 0.29.0

- New tools `get_role_authorizations`, `compare_roles` and `check_role_health` (base);
  `get_role_details` reports findings, including derived roles out of sync.

## 0.28.0 – MVP complete

- New tools `get_role_details`, `get_user_authorizations` and `get_service_access` (base).

## 0.27.0

- `draft_role_change` / `apply_role_change`: create new single roles, empty or as a copy
  (base, admin).

## 0.26.0

- Changes to a reference role are passed on to its derived roles (admin).

## 0.25.0

- Composite roles: add and remove single roles (base, admin).

## 0.24.0

- Remove launchpad catalogs from roles (base, admin).

## 0.23.0

- Program `ZACCX_PLAN_CLEANUP` for expired and hanging change plans (base).

## 0.22.0 / 0.22.1

- `get_failed_authorization_checks` also reads the user authorization trace (STUSERTRACE).
- Checks caused by ACCX itself are filtered out.

## 0.21.0

- `diagnose_fiori_app_access` rates the criticality of granting roles.

## 0.20.0

- `explain_missing_access` and `diagnose_fiori_app_access` hand over ready-made arguments for
  `assign_role`.

## 0.19.0

- New write tool `assign_role` (admin): assign, re-date or remove a role assignment, with
  plan, confirmation and critical-access check.

## 0.18.0

- New write tool `apply_role_change` (admin): executes a stored role change plan after
  confirmation. Plans are stored in `ZACCX_PLAN` with a fingerprint.
- Write tools are hidden without write profile and refused in productive clients (base, mcp2).

## 0.17.0

- New tool `get_catalog_details` (base).

## 0.16.0

- New tool `find_fiori_app` (base).

## 0.15.0

- New tool `get_user_launchpad` (base).

## 0.14.0

- `draft_role_change` adds launchpad catalogs; OData V4 services are checked with S_START.

## 0.13.0

- The Fiori diagnosis hands all missing S_SERVICE values to one `draft_role_change` call.

## 0.12.0

- `explain_missing_access` ranks roles with wildcards and SAP template roles lower.

## 0.11.0

- New tool `diagnose_fiori_app_access` (base).

## 0.10.0

- `explain_missing_access` hands over to `draft_role_change` when no existing role fits.

## 0.9.0

- New tool `draft_role_change` (base): proposes a role change from SU24 proposals and checks
  it against critical authorizations. It writes nothing.

## 0.8.0

- New tools `find_users` and `find_roles` (base), based on the SUIM APIs.

## 0.7.0

- `run_critical_access_check` names the origin of each finding (role, composite role,
  reference user, profile).

## 0.6.0

- New tool `run_critical_access_check` (base), based on the SUIM critical authorizations and
  combinations.

## 0.5.0

- `explain_missing_access` flags critical candidate roles.

## 0.4.0

- New tool `get_failed_authorization_checks` (base), SU53 data.

## 0.3.0

- New tool `explain_missing_access` (base).
- Packages `ZACCX_PLG_ADMIN` and `ZACCX_TEST` created (admin, test).

## 0.2.0

- First tools `get_user_profile` and `check_user_access` (base).
- MCP adapter `ZCL_ACCX_MCP2_SERVER` (mcp2).

## 0.1.0

- Core: contracts, registry, runtime, caller guard, privacy layer, factory, logger and
  customizing tables (base).
