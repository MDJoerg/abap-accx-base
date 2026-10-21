[Deutsche Version](../de/user-guide.md)

# Access Explorer (ACCX) – User Guide

**Audience:** SAP Basis, authorization administrators, IT owners and auditors

**Release:** 0.33.0, tested on ABAP Platform 2023 (SAP_BASIS 758) with the embedded Fiori launchpad

---

## Contents

1. [What ACCX is and what it is not](#1-what-accx-is-and-what-it-is-not)
2. [Security and operating principles](#2-security-and-operating-principles)
3. [Server profiles and endpoints](#3-server-profiles-and-endpoints)
4. [Tool reference](#4-tool-reference)
5. [How do I ...?](#5-how-do-i-)
6. [Limitations](#6-limitations)
7. [Prerequisites](#7-prerequisites)

---

## 1. What ACCX is and what it is not

Access Explorer (ACCX) is an **MCP server that runs inside the ABAP stack**. MCP (Model Context Protocol) is the open standard through which AI assistants such as Claude call tools in other systems. ACCX offers such an assistant **27 tools** (25 read-only, 2 writing). With them the assistant answers questions about users, roles, authorizations, the Fiori launchpad, OData services and CDS access control directly from the SAP system. It uses the same sources an administrator uses in SU01, PFCG, SUIM, SU53, STAUTHTRACE and /IWFND/MAINT_SERVICE.

Instead of calling transactions one after another and combining the results by hand, the administrator asks a question in natural language, for example:

> *"Why does user ACCX_T_MON1 get no authorization in SM37, and which role would fix it?"*

The assistant then calls the matching tools in sequence: the actual failed checks from SU53 and the user trace, the gap analysis, the criticality rating according to the SUIM rules and, if requested, a ready-made change request. Every answer names its sources (tables and SAP APIs), warnings and sensible next steps. The administrator does not need to know the tool names; the assistant picks them.

**Who benefits:**

| Role | Benefit |
|---|---|
| Basis support (1st/2nd level) | Diagnose authorization errors and Fiori problems quickly, without knowing every SUIM report |
| Authorization administration | Simulate role changes before making them (new values, open fields, critical authorizations, affected users, request text), then carry them out in a controlled way |
| Audit and security | Critical authorizations and combinations according to the SUIM rule set, each with its origin (role, composite role, profile, reference user); user hygiene and standard users; who changed what on roles and users, and when |
| IT owners | Traceable answers with sources, an audit log of every call, writing only with plan, confirmation and guard rails |

**What ACCX is not:**

- **Not a replacement for SAP GRC Access Control or an identity management system.** ACCX analyses, explains and prepares; approval stays in your existing process.
- **Not a generic table browser.** It offers only targeted, business-level tools, each filtered by the caller's authorizations.
- **Not an automation engine.** Nothing is changed automatically. Writing happens only after a plan and an explicit confirmation, and never in a production client.

---

## 2. Security and operating principles

ACCX is deliberately conservative.

**Reading is the default.** All core tools only read. The two writing tools (change a role, assign a role) come with the optional plugin ADMIN. They appear only in a server profile that explicitly allows writing, and never in a production client.

**Named users, own authorizations.** The assistant always works with the SAP user of the person asking. Every answer is filtered by that user's display authorizations in the same way SUIM does it: S_USER_GRP, S_USER_AGR, S_USER_PRO and S_USER_AUT with activity 03, and activity 08 for change documents. Anything the caller may not see is left out and only counted, so the answer states that something was hidden.

**Writing in two steps.**

1. The first call produces a **plan**: exactly what will change, which critical authorizations are added and who is affected. A plan is valid for 15 minutes.
2. Only after the user has explicitly approved it is exactly this plan executed.

If the role or the user's assignments changed in the meantime, the plan expires and must be created again.

**Critical changes only with consent.** A change through which a role or a user gains critical authorizations or critical combinations according to the SUIM rule set is refused. It goes through only if the user explicitly accepts the findings that were named.

**Like PFCG, not around it.** Changes use SAP's own functions: menu API, merge of proposals (expert mode), profile generation, user comparison, and passing changes on to derived roles. Change documents are written as usual, and the role can be recorded in a customizing request. After every execution ACCX verifies the result.

**Audit log.** Every call is logged in table ZACCX_LOG: caller, server profile, tool, status and duration. Arguments are stored only as a hash; for writing tools the result is stored as well.

**Fail closed.** An error in the authorization check, the privacy layer or a plugin leads to "denied", never to "everything visible".

**Privacy.** Colleagues used for comparisons (for example in role recommendations) are counted, not named. The privacy mode is configured per server profile; at present only "full display" is available.

**Extensible for customer rules.** A customer-specific usage authorization (for example a customer authorization object) can be plugged in through a class. The critical rule set comes from SUIM by default and can be replaced by a derived class, for example to use a GRC rule set or a security baseline.

---

## 3. Server profiles and endpoints

ACCX is reached through one or more **server profiles**. Each profile is an MCP endpoint in the SAP system and is configured in table ZACCX_PROFILE:

- which tool groups are visible (for example users, roles, Fiori, OData/CDS, audit, admin),
- the default row limit,
- the privacy mode,
- an optional customer class for the usage authorization,
- whether writing is allowed.

Typical profiles are:

| Profile | Purpose |
|---|---|
| `bc/access-support` | Support and analysis, read-only |
| `bc/access-admin` | Like support, plus the writing tools of plugin ADMIN (only if the plugin is installed and the client is not a production client) |

An audit profile that exposes the AUDIT tool group can be created in ZACCX_PROFILE in the same way. Any MCP-capable client (for example Claude Desktop, Claude Code or your own agents) connects to the profile's endpoint over an encrypted connection with a named SAP user. The concrete endpoint path and client configuration are described in the installation section of the README.

Every tool returns a structured result plus a short text summary. Most list-returning tools accept `max_rows` (1–500, default 50); results that are cut off say so.

---

## 4. Tool reference

Parameter values are case-insensitive unless stated otherwise. Patterns use `*` for any characters. Authorization values are given as `FIELD=VALUE` (for example `ACTVT=02`).

### 4.1 Users

#### `get_user_profile`
**Purpose:** 360-degree overview of one user. Use it first whenever a question concerns a specific user.

**Key parameters:** `user` (required), `max_rows`.

**Returns:** user type, user group, validity, lock status and reason, last logon, password state, assigned roles with validity and origin (direct or via a composite role), assigned profiles. Roles and profiles the caller may not display are counted.

#### `get_user_authorizations`
**Purpose:** all values a user holds for one authorization object, as the user master has them after the user comparison.

**Key parameters:** `user` (required), `object` (required, for example `S_TABU_NAM`), `field` (optional, only this field), `max_rows`.

**Returns:** every value with its **origin**: role, composite role, directly assigned profile such as SAP_ALL, reference user. Values are condensed per field and `*` (full authorization) is flagged. Also reports roles assigned today whose profile is not yet in the user master (user comparison pending) and locked or expired users.

#### `compare_users`
**Purpose:** compare a user with another user, or with the members of a user group.

**Key parameters:** `user` (required); `compare_with` (second user) or `peer_group` (user group; default: the user's own group); `scope` = `roles` (default), `auth` (plus authorization values and critical authorizations), `fiori` (plus launchpad catalogs) or `all`; `object` (only this object, implies `auth`); `typical_share` (percentage of colleagues from which a role counts as typical, default 50); `max_rows`.

**Returns:** for two users, the roles and directly assigned profiles only one of them holds and, depending on scope, the authorization values (business values separated from organizational level values), the critical authorizations and the launchpad catalogs only one of them has. **Personal parts** are flagged: time-limited assignments, derived roles carrying the holder's organizational levels, and roles that come only through a composite role. For a user group: the roles most colleagues hold that the user lacks, and the user's roles hardly any colleague holds.

#### `analyze_user_group`
**Purpose:** overview of one user group, for access reviews or to prepare a role concept.

**Key parameters:** `user_group` (required), `inactive_days` (default 90), `max_rows`.

**Returns:** members by user type; hygiene findings per user (directly assigned profiles such as SAP_ALL, no logon for `inactive_days`, never logged on, initial password, no roles, expired or not yet valid, locked); the most frequent roles and **outliers** (roles only one member holds).

#### `find_users`
**Purpose:** find users by complex criteria, like SUIM report RSUSR002.

**Key parameters:** any combination of `transaction`, `object` with `values`, `role`, `profile`, `user` (pattern), `user_group`; `exclude_locked` (default false), `valid_users_only` (default true), `max_rows`. All criteria must be met. At least one of transaction, object, role or profile is required. For `values`, a field may be given twice for alternatives.

**Returns:** matching users with name, type, group, validity, lock status and reference user. Users whose matching role assignment is not valid today are left out and counted.

### 4.2 Roles

#### `get_role_details`
**Purpose:** one PFCG role as PFCG shows it, with consistency findings.

**Key parameters:** `role` (required), `max_rows`.

**Returns:** type (single, composite, derived), reference and derived roles, composite roles, the menu with transactions and launchpad catalogs, groups and spaces, authorizations by maintenance status (standard, maintained, changed, manual, inactive), open fields, organizational levels, generated profile, creation and last change, number of users. **Findings:** profile not generated, open fields, empty organizational levels, user comparison pending, derived role not in sync with its reference role, empty composite role.

#### `get_role_authorizations`
**Purpose:** the authorization data of a single or derived role, as in the PFCG expert mode.

**Key parameters:** `role` (required), `object` (optional, only this object), `include_inactive` (default false), `max_rows`.

**Returns:** every authorization with object, text, maintenance status (standard, maintained, changed, manual), active or inactive, and all field values, including open fields and organizational level placeholders such as `$BUKRS`.

#### `compare_roles`
**Purpose:** compare two roles, for example a derived role with its reference, two candidate roles, or a copy with its template.

**Key parameters:** `role_a` and `role_b` (both required), `object` (optional), `max_rows` (per list and side).

**Returns:** the relationship (derived, same reference role, part of a composite role); authorization values only in A or only in B, per object and field and independent of how the authorizations are split; objects, menu transactions, launchpad catalogs, single roles and organizational levels that differ; and the **critical authorizations only one of the two grants**. Composite roles are compared by the union of their single roles.

#### `check_role_health`
**Purpose:** health check across many roles at once.

**Key parameters:** `role_pattern` (default `Z*`; `+` stands for one character), `max_rows`. At most 500 roles per call.

**Returns:** counts per finding type (the same findings as `get_role_details`, plus roles without menu and authorizations), the affected roles sorted with roles that have users first and then by severity, and the roles nobody holds today as cleanup candidates.

#### `find_roles`
**Purpose:** find roles by complex criteria, like SUIM report RSUSR070.

**Key parameters:** `role` (name or pattern), `description` (text), `transaction`, `object` with `values`, `assigned_to_user`, `role_type` (`single`, `composite`, `any`), `max_rows`. All criteria must be met.

**Returns:** matching roles, each with the number of users holding it today.

#### `draft_role_change`
**Purpose:** plan a role change **without changing anything**, also for a role that does not exist yet.

**Key parameters:** `role` (required); `add_transactions`, `remove_transactions`, `add_catalogs`, `remove_catalogs`; `object` with `values` for manual values; `add_roles`, `remove_roles` for composite roles; `create` with optional `copy_from` and `description` for a new single role in the customer namespace; `for_user` (user who needs the access); `reason` (for the request text).

**Returns:** the authorization values the change would add from SU24 proposals (for catalogs: the start authorizations of their apps), which values the role already allows, which fields stay open or need organizational levels, which critical authorizations or combinations the role would gain, the role that actually has to be changed (the reference role of a derived role), affected derived and composite roles and the number of users, the PFCG steps and a ready-made **change request text**.

### 4.3 Access diagnosis

#### `get_failed_authorization_checks`
**Purpose:** the authorization checks that really failed for a user.

**Key parameters:** `user` (required); `source` = `all` (default), `su53` or `trace`; `since_minutes` (default 1440 for SU53, 43200 for the user trace); `max_rows`. Reading the user trace requires S_ADMI_FCD with value STUR.

**Returns:** failed checks from the SU53 buffers of all application servers and from the user trace (STUSERTRACE), condensed with number of occurrences, newest first. Checks caused by ACCX's own simulations are filtered out. The result says whether the user trace is active. If nothing is found, the user should reproduce the error first.

#### `check_user_access`
**Purpose:** simulate for a user whether a transaction can be started or an authorization is held.

**Key parameters:** `user`, `target_type` (`transaction` or `authorization`), `target` (transaction code or authorization object), all required; `values` as `FIELD=VALUE` for authorizations (fields not given are not checked).

**Returns:** each simulated check with its outcome (for transactions: S_TCODE and the check object maintained in SE93), plus whether the user can log on at all (lock, validity). Note: failed simulated checks are also recorded in the SU53 buffer of the calling user.

#### `explain_missing_access`
**Purpose:** what is missing, and which existing role closes the gap best.

**Key parameters:** the same as `check_user_access`, plus `max_rows`.

**Returns:** the missing checks and the single roles whose active authorizations cover them, ranked: a previously assigned, expired role first; then roles already held by colleagues of the same user group; then roles without further critical authorizations; then roles without full wildcard; customer roles before SAP templates. Critical authorizations and wildcards of every candidate are named, and a less critical alternative is offered. Colleagues are only counted. If no role fits, the tool returns ready-made arguments for `draft_role_change` to extend one of the user's own roles; for the recommended role it returns the arguments for `assign_role`.

### 4.4 Fiori launchpad

#### `diagnose_fiori_app_access`
**Purpose:** why a user cannot see or start a Fiori app.

**Key parameters:** `user` and `app` (both required). The app can be given as intent (`SemanticObject-action`), Fiori ID, transaction of a GUI app, or words of the tile title.

**Returns:** the result of each step in the chain: app exists, catalog with target mapping, role of the user containing that catalog (valid, expired or missing), consistency and form factors of the target mapping, start authorization (S_TCODE for GUI apps, S_START for Web Dynpro), activation and S_SERVICE of every OData service of an SAPUI5 app. Proposes the role that closes the gap (ranked as in `explain_missing_access`, with criticality) or hands the fix to `draft_role_change`.

#### `find_fiori_app`
**Purpose:** find an app and see what it needs, independent of a user.

**Key parameters:** `query` (required; intent, Fiori ID, transaction or title words), `max_rows`.

**Returns:** type and target, form factors, catalogs with a target mapping (and whether it is consistent), roles containing such a catalog with user counts, the start authorization and, for SAPUI5 apps, every OData service with gateway activation and S_SERVICE values. Details are determined for the first five apps found.

#### `get_user_launchpad`
**Purpose:** what a user sees in the launchpad, and through which role.

**Key parameters:** `user` (required).

**Returns:** catalogs, groups, spaces and pages from the user's role menus; whether the home page uses spaces or groups; for every tile whether a role valid today brings its catalog (the launchpad hides it otherwise). Content from assignments not valid today and non-existing content are flagged. Missing catalogs are handed to `draft_role_change`. Shows role content, not personalization.

#### `get_catalog_details`
**Purpose:** one launchpad catalog with its usage and inconsistencies.

**Key parameters:** `catalog_id` (required), `with_defaults` (default false; also list the start authorizations PFCG adds with the catalog), `max_rows`.

**Returns:** tiles and target mappings; usage by roles (with user counts), pages, groups and other catalogs; inconsistencies such as tiles without target mapping, lost references, content errors and deprecated items. Items with problems come first.

### 4.5 OData and CDS

#### `simulate_cds_access`
**Purpose:** "What does user X see in CDS view Y?" The SAP runtime evaluates the access control for that user, as transaction SACMSEL does.

**Key parameters:** `user` (required), `cds_entity` (required), `count_rows` (default false).

**Returns:** full access, no access, or the WHERE condition with the user's values; the authorization objects used by the DCL roles together with the user's values and the roles they come from, and the objects the user lacks. Optionally the number of visible rows and of all rows (only for callers allowed to use the ADT data preview without access control; never row contents).

#### `get_cds_access_control`
**Purpose:** explain the access control of one CDS entity.

**Key parameters:** `cds_entity` (required), `max_rows`.

**Returns:** the `AccessControl.authorizationCheck` annotation value; the DCL roles with their conditions (which authorization object and field restricts which element, fixed values such as ACTVT, inherited conditions); whether the entity is **effectively protected** for reading; the authorization objects users need; and the OData services exposing it (service definition, binding, published as V2 or V4). Conditions are read from the DCL source, not evaluated for a user; use `simulate_cds_access` for that.

#### `get_service_access`
**Purpose:** the access side of one OData service.

**Key parameters:** `service` (required; `/NAMESPACE/NAME` for V2, or the service path below `/sap/opu/odata` or `/sap/opu/odata4`), `version` (V2, default 0001), `max_rows`.

**Returns:** whether the service is registered and active in the gateway, its system aliases, whether the ICF node is active, the S_SERVICE values a user needs (hashes of gateway and backend service), their SU24 proposals and the roles granting them with user counts, including roles that hold only one of the two hashes. If no role grants the service, a ready-made extension proposal follows.

### 4.6 Audit

#### `run_critical_access_check`
**Purpose:** users or roles with critical authorizations and combinations, exactly as SUIM report RSUSR008_009_NEW evaluates them.

**Key parameters:** `scope` = `users` (default) or `roles`; `variant` (SUIM variant, default all); for users `user`, `user_group`, `valid_users_only` (default true), `with_origin` (default true); for roles `role`; `max_rows`.

**Returns:** findings condensed per rule (holders, criticality from the SUIM color) and the individual findings. For users each finding names the **origin**: role, composite role, profile or reference user.

#### `get_user_hygiene_report`
**Purpose:** user hygiene across all users or selected user groups, for example for a quarterly review.

**Key parameters:** `checks` (default all: `direct_profile`, `inactive`, `never_logged_on`, `initial_password`, `expired`, `standard_users`), `user_group` (default all users), `inactive_days` (default 90), `max_rows`.

**Returns:** counts per check and per user group, the affected users by severity, and the state of the standard users SAP*, DDIC, SAPCPIC, EARLYWATCH and TMSADM (exists, locked, user type, profiles, group SUPER) together with the profile parameter `login/no_automatic_user_sapstar`. Whether standard users still have their default passwords is not visible to ACCX; the report refers to SAP report RSUSR003 for that.

#### `find_unprotected_cds_exposures`
**Purpose:** audit of OData exposure: which CDS entities are reachable through OData without effective access control.

**Key parameters:** `names` (service definitions or patterns, default `Z*` and `Y*`), `package`, `include_protected` (default false), `published_only` (default false), `max_rows`.

**Returns:** every exposed entity with its protection status: no DCL role, access control switched off, role granting without condition, fixed filters only, custom entity (the query class must check). Entities in published services come first; counts per status.

#### `get_authorization_changes`
**Purpose:** change documents for a period, summarized.

**Key parameters:** `from` (required, YYYY-MM-DD), `to` (default today), `user`, `role`, `changed_by` (patterns allowed), `scope` = `assignments`, `role_content`, `users` or `all` (default), `max_rows`. Without `user` or `role` the period is limited to 366 days.

**Returns:** role assignments (including changed validity), roles created and deleted, changed role content (values, organizational levels, authorizations, single roles, menu, reference role), user master changes (created, group, type, lock, validity, password set by an administrator) and directly assigned profiles. Changes from one save form one event. Counts per type and per person who made the change, newest first. **Critical events** are flagged: users changing their own assignments or user master, and SAP_ALL assigned directly. Reading change documents requires activity 08 in S_USER_GRP or S_USER_AGR, as in SUIM; without it the documents are hidden and counted.

### 4.7 Maintenance (plugin ADMIN, writing profile only)

Both tools follow the same pattern: the first call (without `plan_id`) creates a plan and returns a `plan_id`; the second call with `plan_id` and `confirm = true` executes exactly that plan, and only after the user has approved it. Critical additions require `accept_critical = true`, which may only be set after the user has explicitly accepted the named findings.

#### `apply_role_change`
**Purpose:** change a role or create a new one. **Writes to the system.**

**Key parameters:** `role`; `add_transactions`, `remove_transactions`, `add_catalogs`, `remove_catalogs`; `object` with `values` (manual values); `open_values` as `OBJECT-FIELD=VALUE` to fill open fields; `add_roles`, `remove_roles` for composite roles; `create` with `copy_from` and `description`; `transport` (customizing request); `reason`; `accept_critical`; `plan_id`; `confirm`.

**Returns:** in the planning call, what the role would gain or lose including critical authorizations, and the plan id; in the execution call, the result of each step and the post-execution verification. Execution works like PFCG: menu change, merge, manual values, profile generation. Open fields block generation and are reported; they are filled with `open_values` in a follow-up plan. Changes of a reference role are passed on to its derived roles. A new role is created in the customer namespace (Z or Y), empty or as a copy without users. Derived roles themselves and SAP template roles cannot be changed.

#### `assign_role`
**Purpose:** assign a role to a user, change the validity of a direct assignment, or remove it. **Writes to the system**, including the profile comparison.

**Key parameters:** `user`, `role`, `action` = `assign` (default) or `remove`, `valid_from` (default today), `valid_to` (default 9999-12-31), `reason`, `accept_critical`, `plan_id`, `confirm`.

**Returns:** in the planning call, the critical authorizations and combinations the user would gain across all of the user's roles, and the plan id; in the execution call, the result and its verification. The caller's own assignments are never changed. Assignments through composite roles cannot be removed with this tool.

---

## 5. How do I ...?

The examples show the question to the assistant and the tool chain behind it. You do not have to name the tools.

### 5.1 ... find out why a user gets "no authorization"?

*"ACCX_T_MON1 cannot call SE16. What is missing, and which role helps?"*

1. `get_failed_authorization_checks` shows the check that really failed (for example S_TCODE for SE16), without noise from simulations.
2. `explain_missing_access` names the missing values, ranks suitable existing roles, states the criticality of each (for example "also grants debugging with replace") and offers a less critical alternative.
3. If no role fits, it proposes extending one of the user's own roles. `draft_role_change` then provides the values, the open fields and the request text.
4. After approval: `assign_role` or `apply_role_change`, then `check_user_access` to confirm.

The result is a justified recommendation instead of "give him SAP_ALL", including a request text for your approval process.

### 5.2 ... find out why a Fiori app is missing or fails to start?

*"Why does user USER_A not see the app 'Manage Launchpad Pages'?"*

- `diagnose_fiori_app_access` checks the whole chain: does the app exist, is its catalog in a valid role of the user, is the target mapping consistent, are the start authorization and all S_SERVICE values of the OData services present?
- The result names the gap and the role that closes it (with criticality), or proposes extending one of the user's own roles.
- If the service itself returns 403 or 404, `get_service_access` shows whether it is active, its system alias, and which roles allow it.

### 5.3 ... find out where a user gets an authorization from?

*"Where does ACCX_T_DEV get the authorization to change development objects?"*

- `get_user_authorizations` with object S_DEVELOP lists every value with its origin, for example "ZACCX_T_DEVDISP via composite role ZACCX_T_C_COMBO" or "profile SAP_ALL".
- It also reports roles whose user comparison is still pending. Such roles are assigned but not yet effective, a common reason for "but the role is assigned!".

### 5.4 ... answer "who may ...?" questions?

*"Who may debug with replace?"*, *"Who has SAP_ALL?"*, *"Who may maintain tables of authorization group SC?"*

- `find_users` and `find_roles` answer single questions as SUIM does, with the number of users per role.
- `run_critical_access_check` evaluates the complete critical rule set (SUIM variants) for users or roles and names for every finding the role, composite role or profile it comes from, so it is clear where to act.

### 5.5 ... run a periodic user hygiene review?

*"How are our users doing? What about SAP* and DDIC?"*

`get_user_hygiene_report` checks all users at once (or selected groups) and summarizes how many users each check finds and in which groups, lists the users by severity (directly assigned profiles, long or never logged on, initial password, expired with roles), and reports the state of the standard users, including whether a deleted SAP* could log on again with its default password. Whether standard users still have default passwords cannot be seen by ACCX; use SAP report RSUSR003 for that.

### 5.6 ... find out who changed what?

*"Who changed role assignments or role contents last quarter?"*, *"What happened to user ACCX_T_EXPIR since Monday?"*

`get_authorization_changes` reads the change documents like SUIM but summarizes them: changes from one save become one event (for example "role created" with all values, or "role deleted" in one line); a new validity appears as "validity changed from ... to ..." instead of a deletion plus a new entry; counts per type and per person who made the change; critical events flagged. As in SUIM, the caller needs activity 08 (display change documents) in S_USER_GRP or S_USER_AGR.

### 5.7 ... check a role before changing it?

*"Check role Z_FI_AP_CLERK before we change it."*

`get_role_details` shows structure and state: derivation, composite roles, menu with Fiori content, how many authorizations are standard, maintained, changed or manual, profile status and users. Findings such as "profile not generated", "3 open fields", "organizational level $BUKRS empty", "user comparison pending for 4 users" or "not in sync with reference role" are listed directly. For details, `get_role_authorizations` shows each authorization with status and values, and `compare_roles` compares a derived role with its reference role, or a copy with its template, including critical authorizations gained or lost.

### 5.8 ... clean up roles?

*"Which of our Z roles are broken or unused?"*

`check_role_health` checks all roles matching a pattern in one call: counts per finding type, the affected roles (those with users first, then by severity) and the roles without users as cleanup candidates. From there, `get_role_details` leads to the single role and `compare_roles` to the deviation from the reference role.

### 5.9 ... give a new employee the same access as a colleague?

*"A new employee starts and should get the same access as USER_B. What exactly is that?"*

`compare_users` with `compare_with` compares both users:

- roles only the colleague has, with a note on which are **personal** (time-limited, derived role with the colleague's organizational levels) and which come only through a composite role; request the composite role, not its single roles;
- directly assigned profiles of the colleague, which should not be copied;
- with `scope=auth`, the authorization values separated into business values and organizational level values (company code, plant, ...), and the **critical authorizations** that would be copied along.

Without a second user, the tool compares with the user's own group: *"What do colleagues have that this user lacks?"*

### 5.10 ... get an overview of a user group?

*"Give me an overview of group SUPER."*

`analyze_user_group` returns the number of members and their types, hygiene findings per user by severity, the most frequent roles and the outliers. For an outlier, `compare_users` with the group continues the analysis.

### 5.11 ... extend a role safely?

*"Add SE16 to ZACCX_T_MONITOR. What does that mean?"*

1. `draft_role_change` shows which SU24 values would be added, which fields stay open (for example the table authorization group), whether a critical authorization would arise, and which users and composite roles are affected, with PFCG steps and request text.
2. With the writing profile, `apply_role_change` creates the plan. After the administrator confirms, ACCX executes it like PFCG: menu, merge, generation, and passing changes on to derived roles.
3. Open fields are filled with concrete values in a follow-up plan; the assistant proposes them.
4. The verification after execution confirms every change individually.

### 5.12 ... create a new role from an SAP template?

*"Create a copy of SAP_BC_ENDUSER as Z_ENDUSER."*

- `apply_role_change` with `create` and `copy_from` copies the role without user assignments, sets the description, merges and generates.
- Critical content of the template is reported before execution, so a copy of an administrator template cannot be created unnoticed.
- Then assign the users with `assign_role`.

### 5.13 ... extend or withdraw time-limited access?

*"Extend the expired role of ACCX_T_EXPIR until the end of the year."*

- `explain_missing_access` recognizes the expired assignment and hands over ready-made arguments.
- `assign_role` plans the new validity, checks the critical gain across all of the user's roles and, after confirmation, executes it with an immediate profile comparison. With `action = remove` the same flow withdraws a direct assignment.

### 5.14 ... clean up the launchpad?

*"Is catalog SAP_BASIS_TCR_T still consistent?"*, *"What does the user actually see?"*

- `get_catalog_details` reports lost references, tiles without target mapping, content errors, and the roles, pages and groups that use the catalog.
- `get_user_launchpad` shows what the user really sees and why tiles are missing, for example because a role brings the page but not the catalog.
- `apply_role_change` can remove catalogs that are no longer needed, together with their start authorizations, from roles.

### 5.15 ... find data our OData services expose without protection?

*"Which of our own Fiori apps read data without access control?"*, *"What does a user need to see rows of view I_BusinessUserBasic?"*, *"Why does USER_A see only some of the orders in the app?"*

- `find_unprotected_cds_exposures` checks all exposed views at once. For an unprotected view in a published service, S_SERVICE is the only barrier: whoever may call the service reads all rows.
- `get_cds_access_control` explains one view: which DCL role restricts which field with which authorization object (for example B_BUPA_GRP on the authorization group), and through which services the view can be reached.
- `simulate_cds_access` answers the question for a concrete user with the SAP runtime. Example: ACCX_T_DEV sees in I_AllOpenCustomizingRequests only requests of type PIEC or TASK, because S_TRANSPRT in role ZACCX_T_DEVDISP allows only these; a support user without any B_BUPA objects sees nothing in I_BusinessUserBasic.

Note: write access to CDS-based business objects is governed by the behavior definition, which is not part of this check.

### 5.16 ... find out who may call an OData service?

*"Which roles allow /UI2/PAGE_BUILDER_PERS, and is the service active?"*

`get_service_access` returns the registration status, the system alias and the ICF node; the two S_SERVICE hashes (gateway and backend service) with their SU24 proposals; and the roles allowing the service with user counts, including roles that hold only one of the two hashes. If no role allows the service, a ready-made extension proposal follows.

---

## 6. Limitations

- Embedded Fiori launchpad only; hub deployments are not supported.
- No Central User Administration (CUA), no HR organizational assignments.
- Organizational levels of derived roles are not maintained by the writing tools.
- Composite and derived roles are not created; only single roles can be created.
- Derived roles and SAP template roles cannot be changed directly (changes go through the reference role, or a copy is created).
- The CDS simulation does not support views with parameters or with an access control context. Rows are counted only if the condition can be expressed as a WHERE condition.
- Change history does not include archived change documents, deleted users, or address data, parameters and SNC data.
- The only privacy mode available is "full display"; pseudonymization is prepared but not yet available.
- Whether standard users still have their default passwords is not checked (see SAP report RSUSR003).
- Write access to CDS entities (behavior definitions) is not analyzed.

---

## 7. Prerequisites

- **Platform:** classic ABAP; tested on ABAP Platform 2023 (SAP_BASIS 758). ABAP Cloud is not supported.
- **MCP transport:** the ABAP MCP SDK `mcp2`. The business logic is decoupled from it; another transport only needs a new adapter.
- **abapGit repositories:**

  | Repository | Content | Installation |
  |---|---|---|
  | `ZACCX` | Core, business logic, tools | Required |
  | `ZACCX_MCP2` | Adapter to the MCP SDK | Required when using mcp2 |
  | `ZACCX_PLG_ADMIN` | Writing tools (plugin ADMIN) | Optional |
  | `ZACCX_TEST` | Test data | Development and QA only |

- **Configuration:** server profiles in ZACCX_PROFILE (see [section 3](#3-server-profiles-and-endpoints)).
- **Users:** each person works with a named SAP user that has the display authorizations needed for the questions asked (S_USER_GRP, S_USER_AGR, S_USER_PRO, S_USER_AUT, and activity 08 for change documents).
- **Client:** any MCP-capable client.

Detailed installation steps are in the [README](../../README.md#installation).
