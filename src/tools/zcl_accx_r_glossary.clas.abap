"! <p class="shorttext synchronized">Access Explorer resource: accx://glossary</p>
"! Fixed text, no system data.
CLASS zcl_accx_r_glossary DEFINITION PUBLIC FINAL CREATE PUBLIC.

  PUBLIC SECTION.
    INTERFACES zif_accx_resource.

ENDCLASS.

CLASS zcl_accx_r_glossary IMPLEMENTATION.

  METHOD zif_accx_resource~get_descriptor.
    result = VALUE #( uri         = `accx://glossary`
                      name        = `glossary`
                      title       = `Access Explorer glossary`
                      description = `Terms of SAP authorizations, roles and the Fiori launchpad as the Access Explorer tools use them.`
                      mime_type   = `text/markdown` ).
  ENDMETHOD.

  METHOD zif_accx_resource~read.
    DATA(lines) = VALUE string_table(
        ( |# Access Explorer glossary| )
        ( `` )
        ( |## Authorizations| )
        ( |- **Authorization object**: a protected capability with a set of fields, for example S_TCODE (start transactions) or S_TABU_DIS (table access). | &&
            |Programs check an object with concrete field values.| )
        ( |- **Authorization**: one instance of an object in a role, with a value or value range per field. An access check succeeds if one authorization of the | &&
            |user covers all checked field values.| )
        ( |- **ACTVT**: the activity field of many objects, for example 01 create, 02 change, 03 display, 06 delete.| )
        ( |- **Wildcard**: the value * in an authorization field; it allows every value of that field. Full wildcards on powerful objects are what makes an | &&
            |authorization critical.| )
        ( |- **Critical authorization**: an authorization or combination of authorizations listed in the SUIM variants of critical authorizations (report | &&
            |RSUSR008_009_NEW). Access Explorer does not define criticality itself, it reports what the system defines.| )
        ( |- **SU53**: shows the last failed authorization check of the logged-on user. Access Explorer reads the SU53 buffers of all application servers; they | &&
            |hold only recent failures and are lost on a restart.| )
        ( |- **User trace (STUSERTRACE)**: records every distinct authorization check of a user while the trace is switched on (profile parameter | &&
            |auth/auth_user_trace).| )
        ( |- **SU24**: maintains the proposals (objects and values) that PFCG offers for a transaction or app. Open fields are proposal fields without a value.| )
        ( |- **SUIM**: the user information system with the standard reports for users, roles, authorizations and change documents. Several Access Explorer | &&
            |tools use the same APIs and show only what the caller may display.| )
        ( `` )
        ( |## Users and roles| )
        ( |- **Single role**: a role with a menu and authorizations. **Composite role**: a collection of single roles without own authorizations. **Derived | &&
            |role**: inherits the menu and the authorization structure of a reference role and only differs in organizational values.| )
        ( |- **Profile**: the generated technical form of the authorizations of a role. **Profile assigned directly**: a profile such as SAP_ALL put into the | &&
            |user master (SU01), bypassing roles.| )
        ( |- **User comparison**: the PFCG step that transfers the profiles of the roles into the user master. While it is pending, users do not yet have the | &&
            |latest changes of the role.| )
        ( |- **User type**: dialog, system, communication, service or reference. Only dialog users are expected to log on interactively.| )
        ( |- **User group**: the field in the user master that SUIM and user administration use to restrict who may see or change a user. Access Explorer | &&
            |applies the same restriction to its callers.| )
        ( `` )
        ( |## Fiori launchpad| )
        ( |- **Catalog**: a collection of tiles and target mappings that a role makes available. A user can start an app only if one of their roles contains a | &&
            |catalog with a target mapping for the app.| )
        ( |- **Tile** and **target mapping**: the tile is what the user sees, the target mapping connects the intent (SemanticObject-action) to the app and its | &&
            |start parameters.| )
        ( |- **Group, space and page**: ways to arrange tiles for display. They are assigned through roles as well; a catalog alone does not put a tile on a | &&
            |page.| )
        ( |- **S_START**: start authorization of Web Dynpro and SAPUI5 applications. **S_SERVICE**: start authorization of an OData service, with the hash of | &&
            |the service name as value.| )
        ( |- **Gateway service**: an OData service registered and activated in /IWFND/MAINT_SERVICE; the ICF node and the system alias must also be active.| )
        ( `` )
        ( |## Access Explorer| )
        ( |- **Profile of the server**: the endpoint (for example bc/access-support) with its tool groups, privacy mode and write permission, maintained in | &&
            |table ZACCX_PROFILE.| )
        ( |- **Pseudonym**: a stable identifier of the form U- followed by eight hexadecimal characters that replaces a user name when the server runs with | &&
            |privacy mode PSEUDONYMIZE or MINIMIZE. Pass it as the user argument; the server resolves it.| )
        ( |- **Plan**: what a write tool returns before it changes anything. The change runs only after the user approved exactly this plan.| )
        ( |- **Next steps**: suggestions at the end of a tool result, with the arguments of the follow-up call.| )
        ).
    result = concat_lines_of( table = lines sep = |\n| ).
  ENDMETHOD.

ENDCLASS.

