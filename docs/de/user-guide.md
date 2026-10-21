[English version](../en/user-guide.md)

# Access Explorer (ACCX) – Benutzerhandbuch

**Zielgruppe:** SAP-Basis, Berechtigungsadministration, IT-Verantwortliche und Audit

**Release:** 0.33.0, getestet auf ABAP Platform 2023 (SAP_BASIS 758) mit Embedded Fiori Launchpad

---

## Inhalt

1. [Was ACCX ist und was nicht](#1-was-accx-ist-und-was-nicht)
2. [Sicherheits- und Betriebsprinzipien](#2-sicherheits--und-betriebsprinzipien)
3. [Serverprofile und Endpunkte](#3-serverprofile-und-endpunkte)
4. [Werkzeugreferenz](#4-werkzeugreferenz)
5. [Wie mache ich ...?](#5-wie-mache-ich-)
6. [Grenzen](#6-grenzen)
7. [Voraussetzungen](#7-voraussetzungen)

---

## 1. Was ACCX ist und was nicht

Access Explorer (ACCX) ist ein **MCP-Server, der im ABAP-Stack läuft**. MCP (Model Context Protocol) ist der offene Standard, über den KI-Assistenten wie Claude Werkzeuge in anderen Systemen aufrufen. ACCX stellt einem solchen Assistenten **27 Werkzeuge** bereit (25 lesende, 2 schreibende). Mit ihnen beantwortet der Assistent Fragen zu Benutzern, Rollen, Berechtigungen, Fiori Launchpad, OData-Services und CDS-Zugriffskontrolle direkt aus dem SAP-System. Er nutzt dieselben Quellen, die ein Administrator in SU01, PFCG, SUIM, SU53, STAUTHTRACE und /IWFND/MAINT_SERVICE verwendet.

Statt Transaktionen nacheinander aufzurufen und die Ergebnisse von Hand zusammenzusetzen, stellt der Administrator eine Frage in natürlicher Sprache, zum Beispiel:

> *„Warum bekommt Benutzer ACCX_T_MON1 in SM37 keine Berechtigung, und welche Rolle würde das lösen?"*

Der Assistent ruft dann die passenden Werkzeuge nacheinander auf: die tatsächlich fehlgeschlagenen Prüfungen aus SU53 und dem Benutzer-Trace, die Lückenanalyse, die Kritikalitätsbewertung nach den SUIM-Regeln und auf Wunsch einen fertigen Änderungsantrag. Jede Antwort nennt ihre Quellen (Tabellen und SAP-APIs), Warnungen und sinnvolle nächste Schritte. Der Administrator muss die Werkzeugnamen nicht kennen; der Assistent wählt sie selbst.

**Wer profitiert:**

| Rolle | Nutzen |
|---|---|
| Basis-Support (1st/2nd Level) | Berechtigungsfehler und Fiori-Probleme schnell diagnostizieren, ohne alle SUIM-Reports zu kennen |
| Berechtigungsadministration | Rollenänderungen vorher durchspielen (neue Werte, offene Felder, kritische Berechtigungen, betroffene Benutzer, Antragstext) und danach kontrolliert ausführen |
| Audit und Security | Kritische Berechtigungen und Kombinationen nach SUIM-Regelwerk, jeweils mit Herkunft (Rolle, Sammelrolle, Profil, Referenzbenutzer); Benutzerhygiene und Standardbenutzer; wer wann was an Rollen und Benutzern geändert hat |
| IT-Verantwortliche | Nachvollziehbare Antworten mit Quellenangabe, Protokoll jedes Aufrufs, Schreiben nur mit Plan, Bestätigung und Leitplanken |

**Was ACCX nicht ist:**

- **Kein Ersatz für SAP GRC Access Control oder ein Identity-Management-System.** ACCX analysiert, begründet und bereitet vor; die Genehmigung bleibt in Ihrem bestehenden Prozess.
- **Kein generischer Tabellenbrowser.** Es gibt nur gezielte, fachliche Werkzeuge, jeweils gefiltert nach den Berechtigungen des Aufrufers.
- **Keine Automatisierung.** Nichts wird automatisch geändert. Geschrieben wird nur nach Plan und ausdrücklicher Bestätigung, und nie in einem Produktivmandanten.

---

## 2. Sicherheits- und Betriebsprinzipien

ACCX ist bewusst konservativ gebaut.

**Lesen ist Standard.** Alle Kernwerkzeuge lesen nur. Die beiden schreibenden Werkzeuge (Rolle ändern, Rolle zuordnen) gehören zum optionalen Plugin ADMIN. Sie erscheinen nur in einem Serverprofil, das Schreiben ausdrücklich erlaubt, und nie in einem Produktivmandanten.

**Benannte Benutzer, eigene Berechtigungen.** Der Assistent arbeitet immer mit dem SAP-Benutzer des Anfragenden. Jede Antwort ist nach dessen Anzeigeberechtigungen gefiltert, genauso wie in SUIM: S_USER_GRP, S_USER_AGR, S_USER_PRO und S_USER_AUT mit Aktivität 03, für Änderungsbelege Aktivität 08. Was der Aufrufer nicht sehen darf, wird ausgeblendet und nur gezählt; die Antwort weist also darauf hin, dass etwas verborgen wurde.

**Schreiben in zwei Schritten.**

1. Der erste Aufruf erzeugt einen **Plan**: was genau geändert wird, welche kritischen Berechtigungen hinzukommen und wen es betrifft. Ein Plan ist 15 Minuten gültig.
2. Erst nach ausdrücklicher Zustimmung des Benutzers wird genau dieser Plan ausgeführt.

Haben sich die Rolle oder die Zuordnungen des Benutzers in der Zwischenzeit geändert, verfällt der Plan und muss neu erstellt werden.

**Kritisches nur mit Zustimmung.** Eine Änderung, durch die eine Rolle oder ein Benutzer kritische Berechtigungen oder kritische Kombinationen nach dem SUIM-Regelwerk erhält, wird abgelehnt. Sie geht nur durch, wenn der Benutzer die genannten Befunde ausdrücklich akzeptiert.

**Wie PFCG, nicht daran vorbei.** Änderungen laufen über die SAP-eigenen Funktionen: Menü-API, Mischmodus (Expertenmodus), Profilgenerierung, Benutzerabgleich und Weitergabe an abgeleitete Rollen. Änderungsbelege entstehen wie gewohnt, und die Rolle kann in einem Customizing-Auftrag aufgezeichnet werden. Nach jeder Ausführung prüft ACCX das Ergebnis.

**Protokoll.** Jeder Aufruf wird in der Tabelle ZACCX_LOG protokolliert: Aufrufer, Serverprofil, Werkzeug, Status und Dauer. Die Argumente werden nur als Hash gespeichert, bei Schreibwerkzeugen zusätzlich das Ergebnis.

**Fail closed.** Ein Fehler in der Berechtigungsprüfung, der Datenschutzschicht oder einem Plugin führt zu „verweigert", nie zu „alles sichtbar".

**Datenschutz.** Kollegen, die für Vergleiche herangezogen werden (etwa bei Rollenempfehlungen), werden gezählt, nicht genannt. Der Datenschutzmodus wird pro Serverprofil eingestellt; derzeit ist nur „vollständige Anzeige" verfügbar.

**Erweiterbar für Kundenregeln.** Eine kundeneigene Verwendungsberechtigung (zum Beispiel ein Kunden-Berechtigungsobjekt) lässt sich per Klasse einhängen. Das kritische Regelwerk kommt standardmäßig aus SUIM und lässt sich durch eine abgeleitete Klasse ersetzen, etwa durch ein GRC-Regelwerk oder eine Security-Baseline.

---

## 3. Serverprofile und Endpunkte

ACCX wird über ein oder mehrere **Serverprofile** erreicht. Jedes Profil ist ein MCP-Endpunkt im SAP-System und wird in der Tabelle ZACCX_PROFILE konfiguriert:

- welche Werkzeuggruppen sichtbar sind (zum Beispiel Benutzer, Rollen, Fiori, OData/CDS, Audit, Admin),
- das Standard-Zeilenlimit,
- der Datenschutzmodus,
- eine optionale Kundenklasse für die Verwendungsberechtigung,
- ob Schreiben erlaubt ist.

Typische Profile sind:

| Profil | Zweck |
|---|---|
| `bc/access-support` | Support und Analyse, nur lesen |
| `bc/access-admin` | Wie Support, zusätzlich die Schreibwerkzeuge des Plugins ADMIN (nur wenn das Plugin installiert ist und der Mandant kein Produktivmandant ist) |

Ein Audit-Profil mit der Werkzeuggruppe AUDIT lässt sich in ZACCX_PROFILE auf dieselbe Weise anlegen. Jeder MCP-fähige Client (zum Beispiel Claude Desktop, Claude Code oder eigene Agenten) verbindet sich über eine verschlüsselte Verbindung mit einem benannten SAP-Benutzer mit dem Endpunkt des Profils. Den konkreten Endpunktpfad und die Client-Konfiguration beschreibt der Installationsabschnitt der README.

Jedes Werkzeug liefert ein strukturiertes Ergebnis und eine kurze Textzusammenfassung. Die meisten Werkzeuge mit Listenergebnis akzeptieren `max_rows` (1–500, Standard 50); abgeschnittene Ergebnisse weisen darauf hin.

---

## 4. Werkzeugreferenz

Parameterwerte sind unabhängig von Groß- und Kleinschreibung, sofern nicht anders angegeben. Muster verwenden `*` für beliebige Zeichen. Berechtigungswerte werden als `FELD=WERT` angegeben (zum Beispiel `ACTVT=02`).

### 4.1 Benutzer

#### `get_user_profile`
**Zweck:** 360-Grad-Sicht auf einen Benutzer. Der erste Aufruf, wann immer es um einen bestimmten Benutzer geht.

**Wichtige Parameter:** `user` (Pflicht), `max_rows`.

**Liefert:** Benutzertyp, Benutzergruppe, Gültigkeit, Sperrstatus und Sperrgrund, letzte Anmeldung, Kennwortstatus, zugeordnete Rollen mit Gültigkeit und Herkunft (direkt oder über eine Sammelrolle), zugeordnete Profile. Rollen und Profile, die der Aufrufer nicht anzeigen darf, werden gezählt.

#### `get_user_authorizations`
**Zweck:** alle Werte eines Benutzers zu einem Berechtigungsobjekt, so wie der Benutzerstamm sie nach dem Benutzerabgleich enthält.

**Wichtige Parameter:** `user` (Pflicht), `object` (Pflicht, zum Beispiel `S_TABU_NAM`), `field` (optional, nur dieses Feld), `max_rows`.

**Liefert:** jeden Wert mit seiner **Herkunft**: Rolle, Sammelrolle, direkt zugeordnetes Profil wie SAP_ALL, Referenzbenutzer. Die Werte werden pro Feld verdichtet, `*` (volle Berechtigung) wird hervorgehoben. Meldet außerdem heute zugeordnete Rollen, deren Profil noch nicht im Benutzerstamm steht (Benutzerabgleich ausstehend), sowie gesperrte oder abgelaufene Benutzer.

#### `compare_users`
**Zweck:** einen Benutzer mit einem anderen Benutzer oder mit den Mitgliedern einer Benutzergruppe vergleichen.

**Wichtige Parameter:** `user` (Pflicht); `compare_with` (zweiter Benutzer) oder `peer_group` (Benutzergruppe; Standard: die eigene Gruppe des Benutzers); `scope` = `roles` (Standard), `auth` (zusätzlich Berechtigungswerte und kritische Berechtigungen), `fiori` (zusätzlich Launchpad-Kataloge) oder `all`; `object` (nur dieses Objekt, impliziert `auth`); `typical_share` (Anteil der Kollegen in Prozent, ab dem eine Rolle als typisch gilt, Standard 50); `max_rows`.

**Liefert:** bei zwei Benutzern die Rollen und direkt zugeordneten Profile, die nur einer von beiden hat, und je nach Scope die Berechtigungswerte (fachliche Werte getrennt von Org-Ebenen-Werten), die kritischen Berechtigungen und die Launchpad-Kataloge, die nur einer hat. **Personenbezogene Anteile** werden markiert: befristete Zuordnungen, abgeleitete Rollen mit den Org-Ebenen ihres Inhabers und Rollen, die nur über eine Sammelrolle kommen. Bei einer Benutzergruppe: die Rollen, die die meisten Kollegen haben und dem Benutzer fehlen, und die Rollen des Benutzers, die kaum ein Kollege hat.

#### `analyze_user_group`
**Zweck:** Überblick über eine Benutzergruppe, für Zugriffsüberprüfungen oder zur Vorbereitung eines Rollenkonzepts.

**Wichtige Parameter:** `user_group` (Pflicht), `inactive_days` (Standard 90), `max_rows`.

**Liefert:** Mitglieder nach Benutzertyp; Hygienebefunde pro Benutzer (direkt zugeordnete Profile wie SAP_ALL, keine Anmeldung seit `inactive_days`, nie angemeldet, Initialkennwort, keine Rollen, abgelaufen oder noch nicht gültig, gesperrt); die häufigsten Rollen und **Ausreißer** (Rollen, die nur ein Mitglied hat).

#### `find_users`
**Zweck:** Benutzer nach komplexen Kriterien finden, wie SUIM-Report RSUSR002.

**Wichtige Parameter:** beliebige Kombination aus `transaction`, `object` mit `values`, `role`, `profile`, `user` (Muster), `user_group`; `exclude_locked` (Standard false), `valid_users_only` (Standard true), `max_rows`. Alle Kriterien müssen erfüllt sein. Mindestens eines von Transaktion, Objekt, Rolle oder Profil ist nötig. Bei `values` kann ein Feld für Alternativen zweimal angegeben werden.

**Liefert:** passende Benutzer mit Name, Typ, Gruppe, Gültigkeit, Sperrstatus und Referenzbenutzer. Benutzer, deren passende Rollenzuordnung heute nicht gültig ist, werden ausgelassen und gezählt.

### 4.2 Rollen

#### `get_role_details`
**Zweck:** eine PFCG-Rolle so, wie PFCG sie zeigt, mit Konsistenzbefunden.

**Wichtige Parameter:** `role` (Pflicht), `max_rows`.

**Liefert:** Typ (Einzel-, Sammel-, abgeleitete Rolle), Referenz- und abgeleitete Rollen, Sammelrollen, das Menü mit Transaktionen und Launchpad-Katalogen, -Gruppen und -Spaces, Berechtigungen nach Pflegestatus (Standard, gepflegt, verändert, manuell, inaktiv), offene Felder, Org-Ebenen, generiertes Profil, Anlage und letzte Änderung, Anzahl der Benutzer. **Befunde:** Profil nicht generiert, offene Felder, leere Org-Ebenen, Benutzerabgleich ausstehend, abgeleitete Rolle nicht synchron mit der Referenzrolle, leere Sammelrolle.

#### `get_role_authorizations`
**Zweck:** die Berechtigungsdaten einer Einzel- oder abgeleiteten Rolle wie im PFCG-Expertenmodus.

**Wichtige Parameter:** `role` (Pflicht), `object` (optional, nur dieses Objekt), `include_inactive` (Standard false), `max_rows`.

**Liefert:** jede Berechtigung mit Objekt, Text, Pflegestatus (Standard, gepflegt, verändert, manuell), aktiv oder inaktiv, und allen Feldwerten, einschließlich offener Felder und Org-Ebenen-Platzhaltern wie `$BUKRS`.

#### `compare_roles`
**Zweck:** zwei Rollen vergleichen, etwa eine abgeleitete Rolle mit ihrer Referenzrolle, zwei Kandidaten oder eine Kopie mit ihrer Vorlage.

**Wichtige Parameter:** `role_a` und `role_b` (beide Pflicht), `object` (optional), `max_rows` (pro Liste und Seite).

**Liefert:** die Beziehung (abgeleitet, gleiche Referenzrolle, Teil einer Sammelrolle); Berechtigungswerte nur in A oder nur in B, pro Objekt und Feld und unabhängig vom Zuschnitt der Berechtigungen; abweichende Objekte, Menütransaktionen, Launchpad-Kataloge, Einzelrollen und Org-Ebenen; und die **kritischen Berechtigungen, die nur eine der beiden gewährt**. Sammelrollen werden über die Vereinigung ihrer Einzelrollen verglichen.

#### `check_role_health`
**Zweck:** Gesundheitscheck über viele Rollen auf einmal.

**Wichtige Parameter:** `role_pattern` (Standard `Z*`; `+` steht für genau ein Zeichen), `max_rows`. Höchstens 500 Rollen pro Aufruf.

**Liefert:** Zählung pro Befundart (dieselben Befunde wie `get_role_details`, zusätzlich Rollen ohne Menü und Berechtigungen), die betroffenen Rollen, zuerst die mit Benutzern und darin nach Schwere, und die Rollen, die heute niemand hat, als Kandidaten zum Aufräumen.

#### `find_roles`
**Zweck:** Rollen nach komplexen Kriterien finden, wie SUIM-Report RSUSR070.

**Wichtige Parameter:** `role` (Name oder Muster), `description` (Text), `transaction`, `object` mit `values`, `assigned_to_user`, `role_type` (`single`, `composite`, `any`), `max_rows`. Alle Kriterien müssen erfüllt sein.

**Liefert:** passende Rollen, jeweils mit der Anzahl der Benutzer, die sie heute haben.

#### `draft_role_change`
**Zweck:** eine Rollenänderung durchspielen, **ohne etwas zu ändern**, auch für eine Rolle, die es noch nicht gibt.

**Wichtige Parameter:** `role` (Pflicht); `add_transactions`, `remove_transactions`, `add_catalogs`, `remove_catalogs`; `object` mit `values` für manuelle Werte; `add_roles`, `remove_roles` für Sammelrollen; `create` mit optional `copy_from` und `description` für eine neue Einzelrolle im Kundennamensraum; `for_user` (Benutzer, der den Zugriff braucht); `reason` (für den Antragstext).

**Liefert:** die Berechtigungswerte, die die Änderung aus den SU24-Vorschlägen hinzufügen würde (bei Katalogen die Startberechtigungen ihrer Apps), welche Werte die Rolle schon erlaubt, welche Felder offen bleiben oder Org-Ebenen brauchen, welche kritischen Berechtigungen oder Kombinationen die Rolle erhielte, die Rolle, die tatsächlich zu ändern ist (bei einer abgeleiteten Rolle deren Referenzrolle), betroffene abgeleitete und Sammelrollen und die Zahl der Benutzer, die PFCG-Schritte und einen fertigen **Antragstext**.

### 4.3 Zugriffsdiagnose

#### `get_failed_authorization_checks`
**Zweck:** die Berechtigungsprüfungen, die für einen Benutzer wirklich fehlgeschlagen sind.

**Wichtige Parameter:** `user` (Pflicht); `source` = `all` (Standard), `su53` oder `trace`; `since_minutes` (Standard 1440 für SU53, 43200 für den Benutzer-Trace); `max_rows`. Das Lesen des Benutzer-Trace erfordert S_ADMI_FCD mit dem Wert STUR.

**Liefert:** fehlgeschlagene Prüfungen aus den SU53-Puffern aller Applikationsserver und aus dem Benutzer-Trace (STUSERTRACE), verdichtet mit Anzahl, neueste zuerst. Prüfungen aus den Simulationen von ACCX selbst werden herausgefiltert. Das Ergebnis sagt, ob der Benutzer-Trace aktiv ist. Wird nichts gefunden, sollte der Benutzer den Fehler zuerst nachstellen.

#### `check_user_access`
**Zweck:** für einen Benutzer simulieren, ob er eine Transaktion starten darf oder eine Berechtigung hat.

**Wichtige Parameter:** `user`, `target_type` (`transaction` oder `authorization`), `target` (Transaktionscode oder Berechtigungsobjekt), alle Pflicht; `values` als `FELD=WERT` bei Berechtigungen (nicht angegebene Felder werden nicht geprüft).

**Liefert:** jede simulierte Prüfung mit ihrem Ergebnis (bei Transaktionen S_TCODE und das in SE93 gepflegte Prüfobjekt) sowie, ob der Benutzer sich überhaupt anmelden kann (Sperre, Gültigkeit). Hinweis: Fehlgeschlagene simulierte Prüfungen landen auch im SU53-Puffer des aufrufenden Benutzers.

#### `explain_missing_access`
**Zweck:** Was fehlt, und welche vorhandene Rolle schließt die Lücke am besten?

**Wichtige Parameter:** wie bei `check_user_access`, zusätzlich `max_rows`.

**Liefert:** die fehlenden Prüfungen und die Einzelrollen, deren aktive Berechtigungen sie abdecken, in einer Rangfolge: eine früher zugeordnete, abgelaufene Rolle zuerst; dann Rollen, die Kollegen derselben Benutzergruppe schon haben; dann Rollen ohne weitere kritische Berechtigungen; dann Rollen ohne vollen Stern; Kundenrollen vor SAP-Vorlagen. Kritische Berechtigungen und Sterne jedes Kandidaten werden genannt, eine weniger kritische Alternative wird angeboten. Kollegen werden nur gezählt. Passt keine Rolle, liefert das Werkzeug fertige Argumente für `draft_role_change`, um eine eigene Rolle des Benutzers zu erweitern; für die empfohlene Rolle liefert es die Argumente für `assign_role`.

### 4.4 Fiori Launchpad

#### `diagnose_fiori_app_access`
**Zweck:** warum ein Benutzer eine Fiori-App nicht sieht oder nicht starten kann.

**Wichtige Parameter:** `user` und `app` (beide Pflicht). Die App kann als Intent (`SemanticObject-action`), Fiori-ID, Transaktion einer GUI-App oder Wörter des Kacheltitels angegeben werden.

**Liefert:** das Ergebnis jedes Schritts der Kette: App vorhanden, Katalog mit Target Mapping, Rolle des Benutzers mit diesem Katalog (gültig, abgelaufen oder fehlend), Konsistenz und Formfaktoren des Target Mappings, Startberechtigung (S_TCODE bei GUI-Apps, S_START bei Web Dynpro), Aktivierung und S_SERVICE jedes OData-Services einer SAPUI5-App. Schlägt die Rolle vor, die die Lücke schließt (Rangfolge wie bei `explain_missing_access`, mit Kritikalität), oder übergibt die Lösung an `draft_role_change`.

#### `find_fiori_app`
**Zweck:** eine App finden und sehen, was sie braucht, unabhängig von einem Benutzer.

**Wichtige Parameter:** `query` (Pflicht; Intent, Fiori-ID, Transaktion oder Titelwörter), `max_rows`.

**Liefert:** Typ und Ziel, Formfaktoren, Kataloge mit Target Mapping (und ob es konsistent ist), Rollen mit einem solchen Katalog samt Benutzerzahl, die Startberechtigung und bei SAPUI5-Apps jeden OData-Service mit Gateway-Aktivierung und S_SERVICE-Werten. Die Details werden für die ersten fünf gefundenen Apps ermittelt.

#### `get_user_launchpad`
**Zweck:** was ein Benutzer im Launchpad sieht und über welche Rolle.

**Wichtige Parameter:** `user` (Pflicht).

**Liefert:** Kataloge, Gruppen, Spaces und Pages aus den Rollenmenüs des Benutzers; ob die Startseite Spaces oder Gruppen verwendet; für jede Kachel, ob eine heute gültige Rolle ihren Katalog mitbringt (sonst blendet das Launchpad sie aus). Inhalte aus heute nicht gültigen Zuordnungen und nicht existierende Inhalte werden markiert. Fehlende Kataloge werden an `draft_role_change` übergeben. Zeigt Rolleninhalte, keine Personalisierung.

#### `get_catalog_details`
**Zweck:** ein Launchpad-Katalog mit Verwendung und Inkonsistenzen.

**Wichtige Parameter:** `catalog_id` (Pflicht), `with_defaults` (Standard false; listet zusätzlich die Startberechtigungen, die PFCG mit dem Katalog hinzufügt), `max_rows`.

**Liefert:** Kacheln und Target Mappings; Verwendung in Rollen (mit Benutzerzahl), Pages, Gruppen und anderen Katalogen; Inkonsistenzen wie Kacheln ohne Target Mapping, verlorene Referenzen, Inhaltsfehler und veraltete Elemente. Elemente mit Problemen stehen vorne.

### 4.5 OData und CDS

#### `simulate_cds_access`
**Zweck:** „Was sieht Benutzer X in CDS-View Y?" Die SAP-Laufzeit wertet die Zugriffskontrolle für diesen Benutzer aus, wie Transaktion SACMSEL.

**Wichtige Parameter:** `user` (Pflicht), `cds_entity` (Pflicht), `count_rows` (Standard false).

**Liefert:** voller Zugriff, kein Zugriff oder die WHERE-Bedingung mit den Werten des Benutzers; die Berechtigungsobjekte der DCL-Rollen mit den Werten des Benutzers und den Rollen, aus denen sie stammen, sowie die Objekte, die dem Benutzer fehlen. Optional die Zahl der sichtbaren und aller Zeilen (nur für Aufrufer, die die ADT-Datenvorschau ohne Zugriffskontrolle nutzen dürfen; nie Zeileninhalte).

#### `get_cds_access_control`
**Zweck:** die Zugriffskontrolle einer CDS-Entität erklären.

**Wichtige Parameter:** `cds_entity` (Pflicht), `max_rows`.

**Liefert:** den Wert der Annotation `AccessControl.authorizationCheck`; die DCL-Rollen mit ihren Bedingungen (welches Berechtigungsobjekt mit welchem Feld welches Element einschränkt, feste Werte wie ACTVT, geerbte Bedingungen); ob die Entität beim Lesen **wirksam geschützt** ist; die Berechtigungsobjekte, die Benutzer brauchen; und die OData-Services, die sie exponieren (Service-Definition, Binding, veröffentlicht als V2 oder V4). Die Bedingungen werden aus der DCL-Quelle gelesen, nicht für einen Benutzer ausgewertet; dafür gibt es `simulate_cds_access`.

#### `get_service_access`
**Zweck:** die Berechtigungsseite eines OData-Services.

**Wichtige Parameter:** `service` (Pflicht; `/NAMESPACE/NAME` für V2 oder der Servicepfad unterhalb von `/sap/opu/odata` bzw. `/sap/opu/odata4`), `version` (V2, Standard 0001), `max_rows`.

**Liefert:** ob der Service im Gateway registriert und aktiv ist, seine System-Aliase, ob der ICF-Knoten aktiv ist, die S_SERVICE-Werte, die ein Benutzer braucht (Hashes von Gateway- und Backend-Service), ihre SU24-Vorschläge und die Rollen, die sie gewähren, mit Benutzerzahl, einschließlich Rollen, die nur einen der beiden Hashes haben. Erlaubt keine Rolle den Service, folgt ein fertiger Erweiterungsvorschlag.

### 4.6 Audit

#### `run_critical_access_check`
**Zweck:** Benutzer oder Rollen mit kritischen Berechtigungen und Kombinationen, genau wie SUIM-Report RSUSR008_009_NEW sie auswertet.

**Wichtige Parameter:** `scope` = `users` (Standard) oder `roles`; `variant` (SUIM-Variante, Standard alle); für Benutzer `user`, `user_group`, `valid_users_only` (Standard true), `with_origin` (Standard true); für Rollen `role`; `max_rows`.

**Liefert:** Befunde verdichtet pro Regel (Inhaber, Kritikalität aus der SUIM-Farbe) und die einzelnen Befunde. Bei Benutzern nennt jeder Befund die **Herkunft**: Rolle, Sammelrolle, Profil oder Referenzbenutzer.

#### `get_user_hygiene_report`
**Zweck:** Benutzerhygiene über alle Benutzer oder ausgewählte Benutzergruppen, etwa für die Quartalsprüfung.

**Wichtige Parameter:** `checks` (Standard alle: `direct_profile`, `inactive`, `never_logged_on`, `initial_password`, `expired`, `standard_users`), `user_group` (Standard alle Benutzer), `inactive_days` (Standard 90), `max_rows`.

**Liefert:** Zählung pro Prüfung und pro Benutzergruppe, die betroffenen Benutzer nach Schwere und den Zustand der Standardbenutzer SAP*, DDIC, SAPCPIC, EARLYWATCH und TMSADM (vorhanden, gesperrt, Benutzertyp, Profile, Gruppe SUPER) samt dem Profilparameter `login/no_automatic_user_sapstar`. Ob Standardbenutzer noch ihr Standardkennwort haben, kann ACCX nicht sehen; dafür verweist das Ergebnis auf den SAP-Report RSUSR003.

#### `find_unprotected_cds_exposures`
**Zweck:** Audit der OData-Exposition: welche CDS-Entitäten über OData ohne wirksame Zugriffskontrolle erreichbar sind.

**Wichtige Parameter:** `names` (Service-Definitionen oder Muster, Standard `Z*` und `Y*`), `package`, `include_protected` (Standard false), `published_only` (Standard false), `max_rows`.

**Liefert:** jede exponierte Entität mit ihrem Schutzstatus: keine DCL-Rolle, Zugriffskontrolle abgeschaltet, Rolle ohne Bedingung, nur feste Filter, benutzerdefinierte Entität (die Query-Klasse muss prüfen). Entitäten in veröffentlichten Services stehen vorne; Zählung pro Status.

#### `get_authorization_changes`
**Zweck:** Änderungsbelege eines Zeitraums, zusammengefasst.

**Wichtige Parameter:** `from` (Pflicht, JJJJ-MM-TT), `to` (Standard heute), `user`, `role`, `changed_by` (Muster erlaubt), `scope` = `assignments`, `role_content`, `users` oder `all` (Standard), `max_rows`. Ohne `user` oder `role` ist der Zeitraum auf 366 Tage begrenzt.

**Liefert:** Rollenzuordnungen (auch geänderte Gültigkeit), angelegte und gelöschte Rollen, geänderte Rolleninhalte (Werte, Org-Ebenen, Berechtigungen, Einzelrollen, Menü, Referenzrolle), Änderungen am Benutzerstamm (angelegt, Gruppe, Typ, Sperre, Gültigkeit, Kennwort durch Administrator gesetzt) und direkt zugeordnete Profile. Änderungen eines Speichervorgangs bilden ein Ereignis. Zählung pro Art und pro Änderer, neueste zuerst. **Kritische Vorgänge** werden markiert: Benutzer, die ihre eigenen Zuordnungen oder ihren Benutzerstamm ändern, und direkt zugeordnetes SAP_ALL. Für die Belege braucht der Aufrufer wie in SUIM die Aktivität 08 in S_USER_GRP bzw. S_USER_AGR; ohne sie werden die Belege ausgeblendet und gezählt.

### 4.7 Pflege (Plugin ADMIN, nur mit Schreibprofil)

Beide Werkzeuge folgen demselben Muster: Der erste Aufruf (ohne `plan_id`) erzeugt einen Plan und liefert eine `plan_id`; der zweite Aufruf mit `plan_id` und `confirm = true` führt genau diesen Plan aus, und zwar erst, nachdem der Benutzer ihn genehmigt hat. Kritischer Zuwachs erfordert `accept_critical = true`, das erst gesetzt werden darf, wenn der Benutzer die genannten Befunde ausdrücklich akzeptiert hat.

#### `apply_role_change`
**Zweck:** eine Rolle ändern oder neu anlegen. **Schreibt ins System.**

**Wichtige Parameter:** `role`; `add_transactions`, `remove_transactions`, `add_catalogs`, `remove_catalogs`; `object` mit `values` (manuelle Werte); `open_values` als `OBJEKT-FELD=WERT` zum Füllen offener Felder; `add_roles`, `remove_roles` für Sammelrollen; `create` mit `copy_from` und `description`; `transport` (Customizing-Auftrag); `reason`; `accept_critical`; `plan_id`; `confirm`.

**Liefert:** im Planungsaufruf, was die Rolle gewinnen oder verlieren würde, einschließlich kritischer Berechtigungen, und die Plan-ID; im Ausführungsaufruf das Ergebnis jedes Schritts und die Prüfung nach der Ausführung. Die Ausführung läuft wie in PFCG: Menüänderung, Mischen, manuelle Werte, Profilgenerierung. Offene Felder blockieren die Generierung und werden gemeldet; sie werden in einem Folgeplan mit `open_values` gefüllt. Änderungen an einer Referenzrolle gehen an ihre abgeleiteten Rollen. Eine neue Rolle entsteht im Kundennamensraum (Z oder Y), leer oder als Kopie ohne Benutzer. Abgeleitete Rollen selbst und SAP-Vorlagerollen können nicht geändert werden.

#### `assign_role`
**Zweck:** einem Benutzer eine Rolle zuordnen, die Gültigkeit einer direkten Zuordnung ändern oder sie entfernen. **Schreibt ins System**, einschließlich Profilabgleich.

**Wichtige Parameter:** `user`, `role`, `action` = `assign` (Standard) oder `remove`, `valid_from` (Standard heute), `valid_to` (Standard 9999-12-31), `reason`, `accept_critical`, `plan_id`, `confirm`.

**Liefert:** im Planungsaufruf die kritischen Berechtigungen und Kombinationen, die der Benutzer über alle seine Rollen hinweg hinzugewinnen würde, und die Plan-ID; im Ausführungsaufruf das Ergebnis und seine Prüfung. Eigene Zuordnungen des Aufrufers werden nie geändert. Zuordnungen über Sammelrollen lassen sich mit diesem Werkzeug nicht entfernen.

---

## 5. Wie mache ich ...?

Die Beispiele zeigen die Frage an den Assistenten und die Werkzeugkette dahinter. Sie müssen die Werkzeuge nicht nennen.

### 5.1 ... herausfinden, warum ein Benutzer „Keine Berechtigung" bekommt?

*„ACCX_T_MON1 kann SE16 nicht aufrufen. Was fehlt, und welche Rolle hilft?"*

1. `get_failed_authorization_checks` zeigt die tatsächlich fehlgeschlagene Prüfung (zum Beispiel S_TCODE für SE16), ohne Rauschen aus Simulationen.
2. `explain_missing_access` nennt die fehlenden Werte, ordnet passende vorhandene Rollen, nennt deren Kritikalität (zum Beispiel „gewährt zusätzlich Debugging mit Replace") und bietet eine weniger kritische Alternative an.
3. Passt keine Rolle, schlägt es vor, eine eigene Rolle des Benutzers zu erweitern. `draft_role_change` liefert dazu Werte, offene Felder und den Antragstext.
4. Nach Genehmigung: `assign_role` oder `apply_role_change`, danach `check_user_access` zur Bestätigung.

Das Ergebnis ist eine begründete Empfehlung statt „gib ihm SAP_ALL", inklusive Antragstext für Ihren Genehmigungsprozess.

### 5.2 ... herausfinden, warum eine Fiori-App fehlt oder mit Fehler startet?

*„Warum sieht Benutzer USER_A die App ‚Manage Launchpad Pages' nicht?"*

- `diagnose_fiori_app_access` prüft die ganze Kette: Gibt es die App, ist ihr Katalog in einer gültigen Rolle des Benutzers, ist das Target Mapping konsistent, sind Startberechtigung und alle S_SERVICE-Werte der OData-Services vorhanden?
- Das Ergebnis nennt die Lücke und die Rolle, die sie schließt (mit Kritikalität), oder schlägt die Erweiterung einer eigenen Rolle vor.
- Liefert der Service selbst 403 oder 404, zeigt `get_service_access`, ob er aktiv ist, welchen System-Alias er hat und welche Rollen ihn erlauben.

### 5.3 ... herausfinden, woher ein Benutzer eine Berechtigung hat?

*„Woher darf ACCX_T_DEV Entwicklungsobjekte ändern?"*

- `get_user_authorizations` mit dem Objekt S_DEVELOP listet jeden Wert mit Herkunft, zum Beispiel „ZACCX_T_DEVDISP über Sammelrolle ZACCX_T_C_COMBO" oder „Profil SAP_ALL".
- Zusätzlich meldet es Rollen, deren Benutzerabgleich noch aussteht. Solche Rollen sind zugeordnet, wirken aber noch nicht, ein häufiger Grund für „Die Rolle ist doch zugeordnet!".

### 5.4 ... „Wer darf ...?"-Fragen beantworten?

*„Wer darf Debugging mit Replace?"*, *„Wer hat SAP_ALL?"*, *„Wer darf Tabellen der Berechtigungsgruppe SC pflegen?"*

- `find_users` und `find_roles` beantworten Einzelfragen wie SUIM, mit Benutzerzahl je Rolle.
- `run_critical_access_check` wertet das komplette kritische Regelwerk (SUIM-Varianten) für Benutzer oder Rollen aus und nennt pro Befund die Rolle, Sammelrolle oder das Profil, aus dem er stammt. So ist sofort klar, wo man ansetzt.

### 5.5 ... eine regelmäßige Prüfung der Benutzerhygiene durchführen?

*„Wie steht es um unsere Benutzer? Was ist mit SAP* und DDIC?"*

`get_user_hygiene_report` prüft alle Benutzer auf einmal (oder ausgewählte Gruppen) und fasst zusammen, wie viele Benutzer jede Prüfung findet und in welchen Gruppen, listet die Benutzer nach Schwere (direkt zugeordnete Profile, lange oder nie angemeldet, Initialkennwort, abgelaufen mit Rollen) und meldet den Zustand der Standardbenutzer, einschließlich der Frage, ob ein gelöschter SAP* sich mit Standardkennwort wieder anmelden könnte. Ob Standardbenutzer noch ihr Standardkennwort haben, kann ACCX nicht sehen; dafür gibt es den SAP-Report RSUSR003.

### 5.6 ... herausfinden, wer was geändert hat?

*„Wer hat im letzten Quartal Rollenzuordnungen oder Rolleninhalte geändert?"*, *„Was ist seit Montag mit dem Benutzer ACCX_T_EXPIR passiert?"*

`get_authorization_changes` liest die Änderungsbelege wie SUIM, fasst sie aber zusammen: Änderungen eines Speichervorgangs werden ein Ereignis (etwa „Rolle angelegt" mit allen Werten oder „Rolle gelöscht" in einer Zeile); eine neue Gültigkeit erscheint als „Gültigkeit geändert von … auf …" statt als Löschung plus Neuanlage; Zählung pro Art und pro Änderer; kritische Vorgänge sind markiert. Wie in SUIM braucht der Aufrufer die Aktivität 08 (Änderungsbelege anzeigen) in S_USER_GRP bzw. S_USER_AGR.

### 5.7 ... eine Rolle vor einer Änderung prüfen?

*„Prüf die Rolle Z_FI_AP_CLERK, bevor wir sie ändern."*

`get_role_details` zeigt Aufbau und Zustand: Ableitung, Sammelrollen, Menü mit Fiori-Inhalten, wie viele Berechtigungen auf Standard stehen und wie viele gepflegt, verändert oder manuell sind, Profilstatus und Benutzer. Befunde wie „Profil nicht generiert", „3 offene Felder", „Org-Ebene $BUKRS leer", „Benutzerabgleich für 4 Benutzer ausstehend" oder „nicht synchron mit der Referenzrolle" stehen direkt darunter. Für Details zeigt `get_role_authorizations` jede Berechtigung mit Status und Werten, und `compare_roles` stellt eine abgeleitete Rolle ihrer Referenzrolle gegenüber oder eine Kopie ihrer Vorlage, einschließlich kritischer Berechtigungen, die dazukommen oder wegfallen.

### 5.8 ... Rollen aufräumen?

*„Welche unserer Z-Rollen sind kaputt oder werden nicht genutzt?"*

`check_role_health` prüft alle Rollen eines Namensmusters in einem Aufruf: Zählung pro Befundart, die betroffenen Rollen (zuerst die mit Benutzern, darin nach Schwere) und die Rollen ohne Benutzer als Kandidaten zum Aufräumen. Von dort führt `get_role_details` zur einzelnen Rolle und `compare_roles` zur Abweichung von der Referenzrolle.

### 5.9 ... einem neuen Mitarbeiter dieselben Rechte wie einem Kollegen geben?

*„Ein neuer Mitarbeiter fängt an und soll dasselbe dürfen wie USER_B. Was genau ist das?"*

`compare_users` mit `compare_with` stellt beide Benutzer gegenüber:

- Rollen, die nur der Kollege hat, mit Hinweis, welche **personenbezogen** sind (befristet, abgeleitete Rolle mit den Org-Ebenen des Kollegen) und welche nur über eine Sammelrolle kommen; beantragt wird die Sammelrolle, nicht ihre Einzelrollen;
- direkt zugeordnete Profile des Kollegen, die nicht kopiert werden sollten;
- mit `scope=auth` die Berechtigungswerte, getrennt nach fachlichen Werten und Org-Ebenen-Werten (Buchungskreis, Werk …), sowie die **kritischen Berechtigungen**, die beim Kopieren mitkämen.

Ohne zweiten Benutzer vergleicht das Werkzeug mit der eigenen Benutzergruppe: *„Was haben die Kollegen, das diesem Benutzer fehlt?"*

### 5.10 ... einen Überblick über eine Benutzergruppe bekommen?

*„Gib mir einen Überblick über die Gruppe SUPER."*

`analyze_user_group` liefert Anzahl und Typen der Mitglieder, Hygienebefunde pro Benutzer nach Schwere, die häufigsten Rollen und die Ausreißer. Für einen Ausreißer führt `compare_users` mit der Gruppe weiter.

### 5.11 ... eine Rolle sicher erweitern?

*„Nimm SE16 in ZACCX_T_MONITOR auf. Was bedeutet das?"*

1. `draft_role_change` zeigt, welche SU24-Werte hinzukämen, welche Felder offen bleiben (zum Beispiel die Tabellenberechtigungsgruppe), ob eine kritische Berechtigung entstünde und welche Benutzer und Sammelrollen betroffen sind, mit PFCG-Schritten und Antragstext.
2. Mit Schreibprofil erzeugt `apply_role_change` den Plan. Nach Bestätigung durch den Administrator führt ACCX ihn aus wie PFCG: Menü, Mischen, Generierung und Weitergabe an abgeleitete Rollen.
3. Offene Felder werden in einem Folgeplan mit konkreten Werten gefüllt; der Assistent schlägt sie vor.
4. Die Prüfung nach der Ausführung bestätigt jede Änderung einzeln.

### 5.12 ... eine neue Rolle auf Basis einer SAP-Vorlage anlegen?

*„Leg eine Kopie von SAP_BC_ENDUSER als Z_ENDUSER an."*

- `apply_role_change` mit `create` und `copy_from` kopiert die Rolle ohne Benutzerzuordnungen, setzt die Beschreibung, mischt und generiert.
- Kritisches in der Vorlage wird vor der Ausführung gemeldet; die Kopie einer Admin-Vorlage entsteht also nicht unbemerkt.
- Danach ordnen Sie die Benutzer mit `assign_role` zu.

### 5.13 ... befristeten Zugriff verlängern oder entziehen?

*„Verlängere die abgelaufene Rolle von ACCX_T_EXPIR bis Jahresende."*

- `explain_missing_access` erkennt die abgelaufene Zuordnung und übergibt fertige Argumente.
- `assign_role` plant die neue Gültigkeit, prüft den kritischen Zuwachs über alle Rollen des Benutzers und führt nach Bestätigung mit sofortigem Profilabgleich aus. Mit `action = remove` entzieht derselbe Ablauf eine direkte Zuordnung.

### 5.14 ... das Launchpad aufräumen?

*„Ist der Katalog SAP_BASIS_TCR_T noch konsistent?"*, *„Was sieht der Benutzer eigentlich?"*

- `get_catalog_details` meldet verlorene Referenzen, Kacheln ohne Target Mapping, Inhaltsfehler sowie Rollen, Pages und Gruppen, die den Katalog verwenden.
- `get_user_launchpad` zeigt, was der Benutzer wirklich sieht und warum Kacheln fehlen, etwa weil eine Rolle die Page bringt, aber nicht den Katalog.
- `apply_role_change` kann nicht mehr benötigte Kataloge samt ihren Startberechtigungen aus Rollen entfernen.

### 5.15 ... Daten finden, die unsere OData-Services ungeschützt ausliefern?

*„Welche unserer eigenen Fiori-Apps lesen Daten ohne Zugriffskontrolle?"*, *„Was braucht ein Benutzer, um Zeilen der View I_BusinessUserBasic zu sehen?"*, *„Warum sieht USER_A in der App nur einen Teil der Aufträge?"*

- `find_unprotected_cds_exposures` prüft alle exponierten Views auf einmal. Bei einer ungeschützten View in einem veröffentlichten Service ist S_SERVICE die einzige Hürde: Wer den Service aufrufen darf, liest alle Zeilen.
- `get_cds_access_control` erklärt eine View: welche DCL-Rolle mit welchem Berechtigungsobjekt welches Feld einschränkt (zum Beispiel B_BUPA_GRP auf die Berechtigungsgruppe) und über welche Services die View erreichbar ist.
- `simulate_cds_access` beantwortet die Frage für einen konkreten Benutzer mit der SAP-Laufzeit. Beispiel: ACCX_T_DEV sieht in I_AllOpenCustomizingRequests nur Aufträge vom Typ PIEC oder TASK, weil S_TRANSPRT in der Rolle ZACCX_T_DEVDISP nur diese erlaubt; ein Support-Benutzer ohne jedes B_BUPA-Objekt sieht in I_BusinessUserBasic nichts.

Hinweis: Schreibzugriffe auf CDS-basierte Business-Objekte regelt die Verhaltensdefinition (Behavior Definition); sie ist nicht Teil dieser Prüfung.

### 5.16 ... herausfinden, wer einen OData-Service aufrufen darf?

*„Welche Rollen erlauben /UI2/PAGE_BUILDER_PERS, und ist der Service aktiv?"*

`get_service_access` liefert den Registrierungsstatus, den System-Alias und den ICF-Knoten; die beiden S_SERVICE-Hashes (Gateway- und Backend-Service) mit ihren SU24-Vorschlägen; und die erlaubenden Rollen mit Benutzerzahl, einschließlich Rollen, die nur einen der beiden Hashes haben. Erlaubt keine Rolle den Service, folgt ein fertiger Erweiterungsvorschlag.

---

## 6. Grenzen

- Nur Embedded Fiori Launchpad; Hub-Deployments werden nicht unterstützt.
- Keine Zentrale Benutzerverwaltung (CUA), keine HR-Org-Zuordnungen.
- Organisationsebenen abgeleiteter Rollen werden von den Schreibwerkzeugen nicht gepflegt.
- Sammel- und abgeleitete Rollen werden nicht neu angelegt; neu anlegen lassen sich nur Einzelrollen.
- Abgeleitete Rollen und SAP-Vorlagerollen lassen sich nicht direkt ändern (Änderungen laufen über die Referenzrolle, oder es wird eine Kopie angelegt).
- Die CDS-Simulation unterstützt keine Views mit Parametern oder mit Access-Control-Kontext. Zeilen werden nur gezählt, wenn sich die Bedingung als WHERE-Bedingung darstellen lässt.
- Archivierte Änderungsbelege, gelöschte Benutzer sowie Adressdaten, Parameter und SNC-Daten erscheinen nicht in der Änderungshistorie.
- Als Datenschutzmodus ist nur „vollständige Anzeige" verfügbar; Pseudonymisierung ist vorbereitet, aber noch nicht verfügbar.
- Ob Standardbenutzer noch ihr Standardkennwort haben, wird nicht geprüft (siehe SAP-Report RSUSR003).
- Schreibzugriffe auf CDS-Entitäten (Verhaltensdefinitionen) werden nicht analysiert.

---

## 7. Voraussetzungen

- **Plattform:** klassisches ABAP; getestet auf ABAP Platform 2023 (SAP_BASIS 758). ABAP Cloud wird nicht unterstützt.
- **MCP-Transport:** das ABAP-MCP-SDK `mcp2`. Die Fachlogik ist davon entkoppelt; ein anderer Transport braucht nur einen neuen Adapter.
- **abapGit-Repositories:**

  | Repository | Inhalt | Installation |
  |---|---|---|
  | `ZACCX` | Kern, Fachlogik, Werkzeuge | Pflicht |
  | `ZACCX_MCP2` | Adapter zum MCP-SDK | Pflicht bei Transport über mcp2 |
  | `ZACCX_PLG_ADMIN` | Schreibwerkzeuge (Plugin ADMIN) | Optional |
  | `ZACCX_TEST` | Testdaten | Nur Entwicklung und QA |

- **Konfiguration:** Serverprofile in ZACCX_PROFILE (siehe [Abschnitt 3](#3-serverprofile-und-endpunkte)).
- **Benutzer:** Jede Person arbeitet mit einem benannten SAP-Benutzer, der die für ihre Fragen nötigen Anzeigeberechtigungen hat (S_USER_GRP, S_USER_AGR, S_USER_PRO, S_USER_AUT, für Änderungsbelege Aktivität 08).
- **Client:** jeder MCP-fähige Client.

Die ausführliche Installationsanleitung steht in der [README](../../README.md#installation).
