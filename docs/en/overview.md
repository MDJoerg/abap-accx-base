# Access Explorer (ACCX) – Overview: packages and MCP flow

*[Deutsch](../de/overview.md)*

This page shows two things: how the ABAP packages of ACCX fit together (and which of them
are options or variants), and what happens on the wire when an AI client talks to ACCX.
Details of each layer are in the [architecture](architecture.md), the tools in the
[user guide](user-guide.md).

## 1. Package structure

Every box is an ABAP package and an abapGit repository of its own. An arrow means "depends on".

```mermaid
flowchart TB
    TEST["<b>ZACCX_TEST</b><br/>abap-accx-test<br/>test roles and data – development and QA only"]

    subgraph options["Options – install if you need them"]
        ADMIN["<b>ZACCX_PLG_ADMIN</b><br/>abap-accx-plugin-admin<br/>write tools (plugin)"]
        GUI["<b>ZACCX_GUI</b><br/>abap-accx-gui<br/>profile maintenance report"]
    end

    subgraph adapters["Transport adapter – a variant: choose mcp2 or mcp1, or install both"]
        MCP2["<b>ZACCX_MCP2</b><br/>abap-accx-mcp2<br/>endpoint /zmcp2/"]
        MCP1["<b>ZACCX_MCP1</b><br/>abap-accx-mcp1<br/>endpoint /zmcp/"]
    end

    subgraph product["Product – always installed"]
        direction TB
        TOOLS["<b>ZACCX_TOOLS</b><br/>read-only tools, prompts, resources"]
        DOMAIN["<b>ZACCX_DOMAIN</b><br/>domain services (users, roles, Fiori, CDS, ...)"]
        CORE["<b>ZACCX_CORE</b><br/>contracts, runtime, registry, privacy, caller guard"]
        TOOLS --> DOMAIN --> CORE
    end

    subgraph sdk["MCP SDK – the one your adapter uses"]
        SDK2["abap-ai/mcp2<br/><b>ZMCP2</b>"]
        SDK1["abap-ai/mcp<br/><b>ZMCP1</b>"]
    end

    TEST --> ADMIN
    TEST --> product
    ADMIN --> product
    GUI --> product
    MCP2 --> product
    MCP1 --> product
    MCP2 --> SDK2
    MCP1 --> SDK1

    classDef required fill:#dbeafe,stroke:#1d4ed8,color:#111;
    classDef variant fill:#fef3c7,stroke:#b45309,color:#111;
    classDef option fill:#dcfce7,stroke:#15803d,color:#111;
    classDef dev fill:#f3f4f6,stroke:#6b7280,color:#111,stroke-dasharray: 4 3;
    classDef ext fill:#ede9fe,stroke:#6d28d9,color:#111;
    class TOOLS,DOMAIN,CORE required;
    class MCP1,MCP2 variant;
    class ADMIN,GUI option;
    class TEST dev;
    class SDK1,SDK2 ext;
```

| Colour | Meaning | Packages |
|---|---|---|
| Blue | Product, always installed. The core does not know any MCP SDK | `ZACCX` with `ZACCX_CORE`, `ZACCX_DOMAIN`, `ZACCX_TOOLS` |
| Yellow | **Variant**: the transport adapter for your MCP SDK. You need one; both can run side by side | `ZACCX_MCP2`, `ZACCX_MCP1` |
| Green | **Option**: install only if you need the function | `ZACCX_PLG_ADMIN` (writing), `ZACCX_GUI` (profile maintenance) |
| Grey, dashed | Development and QA only | `ZACCX_TEST` |
| Purple | External SDK, not part of ACCX | `ZMCP2`, `ZMCP1` |

Why the adapters are variants: both SDKs speak MCP, but they have different classes, ICF
nodes and registration tables. The tools never see them, so the same tools, prompts and
resources are served by either adapter. Installation order: SDK, `ZACCX`, adapter, then the
options.

## 2. How an AI client talks to ACCX

ACCX is an MCP server inside the ABAP system. The client (an "MCP host" such as Claude,
Microsoft Copilot Studio or your own agent) first asks what the server offers, and then
lets the model call the tools. Every call runs in the ABAP system **as the authenticated
user**.

```mermaid
sequenceDiagram
    autonumber
    actor U as User
    participant C as AI client (MCP host)<br/>e.g. Microsoft Copilot Studio
    participant L as Language model
    participant S as ACCX server<br/>(ABAP, ICF endpoint)
    participant R as ACCX runtime
    participant D as SAP data<br/>(users, roles, authorizations, ...)

    rect rgba(59,130,246,0.12)
    Note over C,S: Connect and discover (once per session)
    C->>S: initialize (protocol version, client capabilities)
    S-->>C: capabilities (tools, prompts, resources) and instructions
    C->>S: tools/list, prompts/list, resources/list
    S-->>C: only what this profile and this user may use
    end

    U->>C: "Why can the user not start SM37?"
    C->>L: question and tool descriptions
    L-->>C: call get_failed_authorization_checks(user)

    rect rgba(34,197,94,0.12)
    Note over C,D: Tool call
    C->>S: tools/call get_failed_authorization_checks
    S->>R: execute(profile, arguments)
    R->>R: usage authorization, check arguments, resolve pseudonyms
    R->>D: read as the calling user (display authorizations apply)
    D-->>R: data
    R->>R: privacy mode, write summary, audit log
    R-->>S: result (status, data, summary, next steps)
    S-->>C: structured content and text
    end

    C->>L: tool result
    L-->>C: next call check_user_access(...), then explain_missing_access(...)
    Note over L,C: the "next steps" of a result tell the model what to call next
    C-->>U: answer: missing authorization object, fields, roles that would close the gap

    opt Optional: prompts and resources
        U->>C: picks the prompt diagnose_access_problem
        C->>S: prompts/get
        S-->>C: step-by-step instruction for the model
        U->>C: attaches accx://tool-guide or accx://faq
        C->>S: resources/read
    end

    opt Only with the write plugin and a write profile
        L-->>C: assign_role(...) without plan_id
        C->>S: tools/call
        S-->>C: plan, nothing changed yet
        C-->>U: show the plan, ask for approval
        U->>C: approves exactly this plan
        C->>S: tools/call with plan_id and confirm = true
        S-->>C: result and verification
    end
```

What the diagram shows:

- **Discovery first.** The client learns the tool catalog, the prompts and the resources from
  the server. The catalog is already filtered: tool groups of the profile, write permission
  and usage authorization decide what is listed.
- **The model decides, ACCX executes.** The language model only sees tool descriptions and
  results. Execution, authorization checks, privacy and logging happen in ABAP.
- **Results guide the next call.** Each result carries "next steps" with the arguments of the
  sensible follow-up call, so a short chain of calls answers most questions.
- **Prompts and resources are optional.** Prompts are instructions a user picks; resources
  are background texts. Neither reads data from the system.
- **Writing is a two-step dialog.** A write tool returns a plan first. It is executed only
  with the plan id and a confirmation, after the user approved exactly that plan.

## 3. Example: Microsoft Copilot Studio

Microsoft Copilot Studio can use an MCP server as a tool source, so an agent in Microsoft
Teams or Microsoft Copilot can ask ACCX. In practice an API gateway such as Azure API
Management sits between the agent and the SAP system.

```mermaid
flowchart LR
    U["User<br/>Microsoft Teams, Microsoft Copilot"]
    A["Copilot Studio agent<br/>(MCP client)"]
    G["Azure API Management<br/>HTTPS, authentication, rate limits"]
    subgraph abap["SAP ABAP system"]
        ICF["ICF node<br/>/zmcp2/ or /zmcp/"]
        AD["ACCX adapter<br/>ZACCX_MCP2 or ZACCX_MCP1"]
        CO["ACCX core<br/>ZACCX"]
        DA[("SAP authorization<br/>and user data")]
        ICF --> AD --> CO --> DA
    end
    U -->|natural language| A
    A -->|"MCP over HTTPS"| G
    G -->|"HTTP, sap-client=..."| ICF
```

A tested walk-through of this setup (Copilot Studio agent, Azure API Management and an ABAP
MCP server built on the same abap-ai SDKs) is in
[hobru/mcp-with-copilot-studio](https://github.com/hobru/mcp-with-copilot-studio). For ACCX
the endpoint is `https://<host>/zmcp2/bc/access-support?sap-client=<client>` (or `/zmcp/...`
for the mcp1 adapter).

**One thing to decide before you connect an agent:** ACCX shows what the *calling SAP user*
may display, the way SUIM does. If the gateway injects one shared technical user, every
question runs with that user's authorizations. Prefer a named user per person (for example
through single sign-on), or a dedicated analysis user that has exactly the display
authorizations the agent should have, and consider a profile with privacy mode
`PSEUDONYMIZE` or `MINIMIZE` for agents that run in a cloud service.
