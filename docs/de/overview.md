# Access Explorer (ACCX) – Überblick: Pakete und MCP-Ablauf

*[English](../en/overview.md)*

Diese Seite zeigt zweierlei: wie die ABAP-Pakete von ACCX zusammenhängen (und welche davon
Optionen oder Varianten sind) und was passiert, wenn ein KI-Client mit ACCX spricht. Die
Einzelheiten der Schichten stehen in der [Architektur](architecture.md), die Werkzeuge im
[Benutzerhandbuch](user-guide.md).

## 1. Paketstruktur

Jeder Kasten ist ein ABAP-Paket und ein eigenes abapGit-Repository. Ein Pfeil heißt „hängt ab von“.

```mermaid
flowchart TB
    TEST["<b>ZACCX_TEST</b><br/>abap-accx-test<br/>Testrollen und -daten – nur Entwicklung und QS"]

    subgraph options["Optionen – installieren, wenn Sie sie brauchen"]
        ADMIN["<b>ZACCX_PLG_ADMIN</b><br/>abap-accx-plugin-admin<br/>Schreibwerkzeuge (Plugin)"]
        GUI["<b>ZACCX_GUI</b><br/>abap-accx-gui<br/>Report zur Profilpflege"]
    end

    subgraph adapters["Transport-Adapter – eine Variante: mcp2 oder mcp1 wählen, oder beide installieren"]
        MCP2["<b>ZACCX_MCP2</b><br/>abap-accx-mcp2<br/>Endpunkt /zmcp2/"]
        MCP1["<b>ZACCX_MCP1</b><br/>abap-accx-mcp1<br/>Endpunkt /zmcp/"]
    end

    subgraph product["Produkt – immer installiert"]
        direction TB
        TOOLS["<b>ZACCX_TOOLS</b><br/>lesende Tools, Prompts, Ressourcen"]
        DOMAIN["<b>ZACCX_DOMAIN</b><br/>Domänen-Services (Benutzer, Rollen, Fiori, CDS, ...)"]
        CORE["<b>ZACCX_CORE</b><br/>Verträge, Runtime, Registry, Privacy, Caller-Guard"]
        TOOLS --> DOMAIN --> CORE
    end

    subgraph sdk["MCP-SDK – das, das Ihr Adapter nutzt"]
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

| Farbe | Bedeutung | Pakete |
|---|---|---|
| Blau | Produkt, immer installiert. Der Kern kennt kein MCP-SDK | `ZACCX` mit `ZACCX_CORE`, `ZACCX_DOMAIN`, `ZACCX_TOOLS` |
| Gelb | **Variante**: der Transport-Adapter für Ihr MCP-SDK. Einen brauchen Sie; beide können nebeneinander laufen | `ZACCX_MCP2`, `ZACCX_MCP1` |
| Grün | **Option**: nur installieren, wenn Sie die Funktion brauchen | `ZACCX_PLG_ADMIN` (Schreiben), `ZACCX_GUI` (Profilpflege) |
| Grau, gestrichelt | Nur Entwicklung und QS | `ZACCX_TEST` |
| Lila | Externes SDK, nicht Teil von ACCX | `ZMCP2`, `ZMCP1` |

Warum die Adapter Varianten sind: Beide SDKs sprechen MCP, haben aber andere Klassen,
ICF-Knoten und Registrierungstabellen. Die Werkzeuge sehen sie nie, deshalb liefert jeder
Adapter dieselben Werkzeuge, Prompts und Ressourcen. Installationsreihenfolge: SDK, `ZACCX`,
Adapter, dann die Optionen.

## 2. Wie ein KI-Client mit ACCX spricht

ACCX ist ein MCP-Server im ABAP-System. Der Client (ein „MCP-Host“ wie Claude, Microsoft
Copilot Studio oder ein eigener Agent) fragt zuerst, was der Server anbietet, und lässt dann
das Modell die Werkzeuge aufrufen. Jeder Aufruf läuft im ABAP-System **als der angemeldete
Benutzer**.

```mermaid
sequenceDiagram
    autonumber
    actor U as Benutzer
    participant C as KI-Client (MCP-Host)<br/>z. B. Microsoft Copilot Studio
    participant L as Sprachmodell
    participant S as ACCX-Server<br/>(ABAP, ICF-Endpunkt)
    participant R as ACCX-Runtime
    participant D as SAP-Daten<br/>(Benutzer, Rollen, Berechtigungen, ...)

    rect rgba(59,130,246,0.12)
    Note over C,S: Verbinden und Entdecken (einmal je Sitzung)
    C->>S: initialize (Protokollversion, Fähigkeiten des Clients)
    S-->>C: Fähigkeiten (Tools, Prompts, Ressourcen) und Anweisungen
    C->>S: tools/list, prompts/list, resources/list
    S-->>C: nur, was dieses Profil und dieser Benutzer nutzen darf
    end

    U->>C: „Warum kann der Benutzer SM37 nicht starten?“
    C->>L: Frage und Tool-Beschreibungen
    L-->>C: Aufruf get_failed_authorization_checks(user)

    rect rgba(34,197,94,0.12)
    Note over C,D: Tool-Aufruf
    C->>S: tools/call get_failed_authorization_checks
    S->>R: execute(Profil, Argumente)
    R->>R: Verwendungsberechtigung, Argumente prüfen, Pseudonyme auflösen
    R->>D: lesen als aufrufender Benutzer (Anzeigeberechtigungen gelten)
    D-->>R: Daten
    R->>R: Datenschutzmodus, Zusammenfassung schreiben, Audit-Log
    R-->>S: Ergebnis (Status, Daten, Zusammenfassung, nächste Schritte)
    S-->>C: strukturierter Inhalt und Text
    end

    C->>L: Tool-Ergebnis
    L-->>C: nächster Aufruf check_user_access(...), dann explain_missing_access(...)
    Note over L,C: die „nächsten Schritte“ eines Ergebnisses sagen dem Modell, was als Nächstes kommt
    C-->>U: Antwort: fehlendes Berechtigungsobjekt, Felder, Rollen, die die Lücke schließen

    opt Optional: Prompts und Ressourcen
        U->>C: wählt den Prompt diagnose_access_problem
        C->>S: prompts/get
        S-->>C: Schritt-für-Schritt-Anweisung für das Modell
        U->>C: hängt accx://tool-guide oder accx://faq an
        C->>S: resources/read
    end

    opt Nur mit Schreib-Plugin und Schreibprofil
        L-->>C: assign_role(...) ohne plan_id
        C->>S: tools/call
        S-->>C: Plan, noch nichts geändert
        C-->>U: Plan zeigen, um Freigabe bitten
        U->>C: gibt genau diesen Plan frei
        C->>S: tools/call mit plan_id und confirm = true
        S-->>C: Ergebnis und Verifikation
    end
```

Was das Diagramm zeigt:

- **Zuerst das Entdecken.** Der Client erfährt Werkzeugkatalog, Prompts und Ressourcen vom
  Server. Der Katalog ist schon gefiltert: Werkzeuggruppen des Profils, Schreiberlaubnis und
  Verwendungsberechtigung bestimmen, was aufgeführt wird.
- **Das Modell entscheidet, ACCX führt aus.** Das Sprachmodell sieht nur Werkzeugbeschreibungen
  und Ergebnisse. Ausführung, Berechtigungsprüfungen, Datenschutz und Protokoll laufen in ABAP.
- **Ergebnisse führen zum nächsten Aufruf.** Jedes Ergebnis enthält „nächste Schritte“ mit den
  Argumenten des sinnvollen Folgeaufrufs; so beantwortet eine kurze Kette die meisten Fragen.
- **Prompts und Ressourcen sind optional.** Prompts sind Anweisungen, die der Benutzer wählt;
  Ressourcen sind Hintergrundtexte. Keines von beiden liest Daten aus dem System.
- **Schreiben ist ein Zwei-Schritt-Dialog.** Ein Schreibwerkzeug liefert zuerst einen Plan. Er
  wird nur mit Plan-ID und Bestätigung ausgeführt, nachdem der Benutzer genau diesen Plan
  freigegeben hat.

## 3. Beispiel: Microsoft Copilot Studio

Microsoft Copilot Studio kann einen MCP-Server als Werkzeugquelle nutzen; so kann ein Agent in
Microsoft Teams oder Microsoft Copilot ACCX fragen. In der Praxis steht zwischen Agent und
SAP-System ein API-Gateway wie Azure API Management.

```mermaid
flowchart LR
    U["Benutzer<br/>Microsoft Teams, Microsoft Copilot"]
    A["Copilot-Studio-Agent<br/>(MCP-Client)"]
    G["Azure API Management<br/>HTTPS, Authentifizierung, Ratenbegrenzung"]
    subgraph abap["SAP-ABAP-System"]
        ICF["ICF-Knoten<br/>/zmcp2/ oder /zmcp/"]
        AD["ACCX-Adapter<br/>ZACCX_MCP2 oder ZACCX_MCP1"]
        CO["ACCX-Kern<br/>ZACCX"]
        DA[("SAP-Berechtigungs-<br/>und Benutzerdaten")]
        ICF --> AD --> CO --> DA
    end
    U -->|natürliche Sprache| A
    A -->|"MCP über HTTPS"| G
    G -->|"HTTP, sap-client=..."| ICF
```

Eine getestete Schritt-für-Schritt-Anleitung für diesen Aufbau (Copilot-Studio-Agent, Azure
API Management und ein ABAP-MCP-Server auf denselben abap-ai-SDKs) steht in
[hobru/mcp-with-copilot-studio](https://github.com/hobru/mcp-with-copilot-studio). Für ACCX
lautet der Endpunkt `https://<host>/zmcp2/bc/access-support?sap-client=<client>` (oder `/zmcp/...`
beim mcp1-Adapter).

**Vor dem Anbinden eines Agenten zu entscheiden:** ACCX zeigt, was der *aufrufende SAP-Benutzer*
anzeigen darf, wie SUIM. Setzt das Gateway einen gemeinsamen technischen Benutzer ein, läuft
jede Frage mit dessen Berechtigungen. Besser ist ein namentlicher Benutzer je Person (zum
Beispiel über Single Sign-on) oder ein eigener Analysebenutzer mit genau den
Anzeigeberechtigungen, die der Agent haben soll; für Agenten in einem Cloud-Dienst lohnt ein
Profil mit Datenschutzmodus `PSEUDONYMIZE` oder `MINIMIZE`.
