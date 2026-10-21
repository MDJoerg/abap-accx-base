# ABAP Access Explorer (ACCX)

*[Deutsch](#deutsch) below.*

Access Explorer is an MCP server that runs **inside** an SAP ABAP system. It lets an AI
assistant answer the questions SAP Basis and authorization teams deal with every day:

- *Why does this user get "no authorization"?* What is missing, which role would close the
  gap, and how critical is that role?
- *Why is this Fiori app missing from the launchpad, or why does it fail to start?*
- *Where does this authorization come from?* Which role, composite role, reference user or profile.
- *Who may do X?* Critical authorizations, user hygiene, change history.
- *Which data do our OData services expose without protection?* What does a given user see
  in a CDS view?

ACCX reads the same sources as SUIM, PFCG, SU53, the Fiori launchpad and the CDS access
control runtime. It checks the authorizations of the **calling user** the way SUIM does. It
is read-only by default. Write tools for role maintenance and role assignment are in a
separate plugin and need a write profile, a stored plan and an explicit confirmation.

## Documentation

| | English | Deutsch |
|---|---|---|
| User guide (tools, scenarios, limits) | [docs/en/user-guide.md](docs/en/user-guide.md) | [docs/de/user-guide.md](docs/de/user-guide.md) |
| Architecture (layers, packages, security) | [docs/en/architecture.md](docs/en/architecture.md) | [docs/de/architecture.md](docs/de/architecture.md) |
| Change history | [CHANGELOG.md](CHANGELOG.md) | |

## Repositories

ACCX is split into abapGit repositories, one per ABAP package tree:

| Repository | ABAP package | Content | Required |
|---|---|---|---|
| [abap-accx-base](https://github.com/MDJoerg/abap-accx-base) (this one) | `ZACCX` (`ZACCX_CORE`, `ZACCX_DOMAIN`, `ZACCX_TOOLS`) | SDK-neutral core, domain services, read-only tools, documentation | yes |
| [abap-accx-mcp2](https://github.com/MDJoerg/abap-accx-mcp2) | `ZACCX_MCP2` | Adapter for the [abap-ai/mcp2](https://github.com/abap-ai/mcp2) MCP SDK | yes, to serve MCP |
| [abap-accx-plugin-admin](https://github.com/MDJoerg/abap-accx-plugin-admin) | `ZACCX_PLG_ADMIN` | Write tools: role maintenance and role assignment | optional |
| [abap-accx-test](https://github.com/MDJoerg/abap-accx-test) | `ZACCX_TEST` | Test roles and test data setup for integration tests | optional, not for production |

The core in `ZACCX` does not know the MCP SDK. Only `ZACCX_MCP2` depends on it, so the
transport layer can be replaced without touching the tools.

## Installation

Prerequisites: ABAP Platform 2023 (SAP_BASIS 758; older releases are not tested),
[abapGit](https://abapgit.org), and the [abap-ai/mcp2](https://github.com/abap-ai/mcp2) SDK.

1. Install the mcp2 SDK and follow its setup (ICF service for `/zmcp2/`).
2. Pull **abap-accx-base** into package `ZACCX` with abapGit. The folder logic is `PREFIX`.
3. Pull **abap-accx-mcp2** into package `ZACCX_MCP2`.
4. Run class `ZCL_ACCX_MCP2_SERVER` with F9 in ADT. It registers the read-only profile
   `bc/access-support` and every profile of table `ZACCX_PROFILE` (`<area>/<server>`, for
   example `bc/access-audit` with tool group AUDIT) in the mcp2 server table `ZMCP2_SERVERS`,
   and lists the visible tools per profile.
5. Optional, write tools: pull **abap-accx-plugin-admin** into `ZACCX_PLG_ADMIN`, run
   `ZCL_ACCX_ADMIN_PLUGIN` with F9 (activates plugin ADMIN and creates profile
   `bc/access-admin` with `ALLOW_WRITE`; refused in productive clients), then run
   `ZCL_ACCX_MCP2_SERVER` with F9 again.
6. Optional: schedule program `ZACCX_PLAN_CLEANUP` daily. It closes and deletes expired
   change plans.

Connect your MCP client to `https://<host>/zmcp2/bc/access-support?sap-client=<client>`
(ICF node `/zmcp2` with handler `ZCL_MCP2_HTTP_HANDLER`) with the user's own named account.
ACCX acts as that user and shows only what that user may display.

---

## Deutsch

Access Explorer ist ein MCP-Server, der **im** SAP-ABAP-System läuft. Ein KI-Assistent kann
damit typische Fragen von Basis- und Berechtigungsteams beantworten:

- Warum bekommt ein Benutzer „keine Berechtigung“, und welche Rolle würde die Lücke schließen?
- Warum fehlt eine Fiori-App im Launchpad?
- Woher stammt eine Berechtigung?
- Wer darf was? Dazu kritische Berechtigungen, Benutzerhygiene und Änderungshistorie.
- Welche Daten liefern OData-Services ungeschützt aus, und was sieht ein Benutzer in einer CDS-View?

ACCX prüft die Berechtigungen des aufrufenden Benutzers wie SUIM. Standardmäßig wird nur
gelesen. Schreibwerkzeuge liegen in einem eigenen Plugin und arbeiten nur mit Schreibprofil,
gespeichertem Plan und ausdrücklicher Bestätigung.

Dokumentation auf Deutsch: [Benutzerhandbuch](docs/de/user-guide.md) und
[Architektur](docs/de/architecture.md). Die Installationsschritte stehen oben unter
[Installation](#installation).
