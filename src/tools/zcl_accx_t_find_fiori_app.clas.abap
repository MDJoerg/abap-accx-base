"! <p class="shorttext synchronized">Access Explorer tool: find_fiori_app</p>
"! Finds Fiori launchpad apps by intent, Fiori ID, transaction or title words
"! and shows, independent of a user, what an app needs: the catalogs with a
"! target mapping for it, the roles containing such a catalog (with the number
"! of users holding them today), the start authorization of its target and,
"! for SAPUI5 apps, the OData services with activation and S_SERVICE values.
"! Embedded launchpad only.
"! <p class="shorttext synchronized">Access Explorer tool: find_fiori_app</p>
"! Finds Fiori launchpad apps by intent, Fiori ID, transaction or title words
"! and shows, independent of a user, what an app needs: the catalogs with a
"! target mapping for it, the roles containing such a catalog (with the number
"! of users holding them today), the start authorization of its target and,
"! for SAPUI5 apps, the OData services with activation and S_SERVICE values.
"! Embedded launchpad only.
CLASS zcl_accx_t_find_fiori_app DEFINITION PUBLIC FINAL CREATE PUBLIC
  INHERITING FROM zcl_accx_tool_base.

  PUBLIC SECTION.
    CONSTANTS co_name TYPE string VALUE `find_fiori_app`.

    TYPES: BEGIN OF ty_catalog,
             catalog    TYPE string,
             title      TYPE string,
             "! target mapping consistent in this catalog
             consistent TYPE abap_bool,
             state_text TYPE string,
           END OF ty_catalog,
           ty_catalogs TYPE STANDARD TABLE OF ty_catalog WITH EMPTY KEY.

    TYPES: BEGIN OF ty_role,
             role           TYPE string,
             catalog        TYPE string,
             "! users holding the role today (directly or through a composite role)
             assigned_users TYPE i,
           END OF ty_role,
           ty_roles TYPE STANDARD TABLE OF ty_role WITH EMPTY KEY.

    TYPES: BEGIN OF ty_service,
             name          TYPE string,
             version       TYPE string,
             odata_version TYPE string,
             "! X active, space not active, - not checked (OData V4)
             active        TYPE abap_bool,
             "! start checks: S_SERVICE with the hash of the gateway and backend part, S_START for an OData V4 group
             checks        TYPE string_table,
           END OF ty_service,
           ty_services TYPE STANDARD TABLE OF ty_service WITH EMPTY KEY.

    TYPES: BEGIN OF ty_app,
             intent              TYPE string,
             title               TYPE string,
             app_type            TYPE string,
             target              TYPE string,
             fiori_ids           TYPE string,
             desktop             TYPE abap_bool,
             tablet              TYPE abap_bool,
             phone               TYPE abap_bool,
             "! consistent in at least one catalog
             consistent          TYPE abap_bool,
             catalogs            TYPE ty_catalogs,
             "! roles, start authorization and services determined (only for the first apps)
             details             TYPE abap_bool,
             "! roles containing one of the catalogs, most users first
             roles               TYPE ty_roles,
             "! roles containing one of the catalogs the caller may not display
             hidden_roles        TYPE i,
             "! checks at start of the target: transaction or S_START of the Web Dynpro application
             start_authorization TYPE string_table,
             services            TYPE ty_services,
           END OF ty_app,
           ty_apps TYPE STANDARD TABLE OF ty_app WITH EMPTY KEY.

    TYPES: BEGIN OF ty_payload,
             query TYPE string,
             apps  TYPE ty_apps,
           END OF ty_payload.

    "! apps with roles, start authorization and services
    CONSTANTS co_detail_apps TYPE i VALUE 5.
    CONSTANTS co_roles_shown TYPE i VALUE 5.

    METHODS zif_accx_tool~get_descriptor REDEFINITION.
    METHODS zif_accx_tool~execute        REDEFINITION.
    METHODS zif_accx_tool~render_summary REDEFINITION.

  PRIVATE SECTION.
    "! Roles with catalogs, start authorization and OData services of one app
    METHODS add_details
      IMPORTING !ctx    TYPE REF TO zif_accx_context
      CHANGING  !app    TYPE ty_app
                !result TYPE zif_accx_types=>ty_result.

    METHODS check_text
      IMPORTING !check        TYPE zif_accx_auth_evaluator=>ty_check
      RETURNING VALUE(result) TYPE string.

ENDCLASS.

CLASS zcl_accx_t_find_fiori_app IMPLEMENTATION.

  METHOD zif_accx_tool~get_descriptor.
    result = VALUE #(
      name        = co_name
      title       = `Find Fiori app`
      description = |Finds Fiori launchpad apps by intent (SemanticObject-action), Fiori ID (e.g. F4512), transaction of | &&
                    |a GUI app or words of the tile title, and shows what an app needs, independent of a user: type and | &&
                    |target, form factors, the catalogs with a target mapping for it (and whether the mapping is consistent), | &&
                    |the roles containing such a catalog with the number of users holding them today, the start | &&
                    |authorization of the target (transaction start, S_START for Web Dynpro) and, for SAPUI5 apps, every OData | &&
                    |service with its gateway activation and S_SERVICE values (S_START for OData V4 groups). Roles, start | &&
                    |authorization and services are determined for the first { co_detail_apps } apps. For one user, use | &&
                    |diagnose_fiori_app_access.|
      group       = zif_accx_types=>co_group-fiori
      read_only   = abap_true
      idempotent  = abap_true
      sensitivity = zif_accx_types=>co_sensitivity-normal
      output_type = `\CLASS=ZCL_ACCX_T_FIND_FIORI_APP\TYPE=TY_PAYLOAD`
      params      = VALUE #( ( param( name        = `query`
                                      description = |Intent (e.g. FLPPage-manage), Fiori ID (e.g. F4512), transaction of a GUI | &&
                                                    |app, or words of the tile title (all words must occur).|
                                      required    = abap_true
                                      maximum     = 100 ) )
                             ( max_rows_param( ) ) ) ).
  ENDMETHOD.

  METHOD zif_accx_tool~execute.
    DATA(query) = condense( args->get_string( `query` ) ).
    IF query IS INITIAL.
      RAISE EXCEPTION NEW zcx_accx_error( status = zif_accx_types=>co_status-invalid message = `Give an intent, Fiori ID, transaction or title words.` ).
    ENDIF.

    DATA(payload) = NEW ty_payload( query = query ).
    result-data = payload.
    result-sources = VALUE #( ( `/UI2/FDM_PUBLIC_API (launchpad catalogs, target mappings)` ) ).

    " one entry per intent, with all catalogs containing it
    LOOP AT zcl_accx_domain_factory=>fiori_repo( )->find_apps( query ) INTO DATA(found).
      READ TABLE payload->apps ASSIGNING FIELD-SYMBOL(<app>) WITH KEY intent = found-intent.
      IF sy-subrc <> 0.
        APPEND VALUE #( intent = found-intent ) TO payload->apps ASSIGNING <app>.
      ENDIF.
      IF <app>-consistent = abap_false AND ( found-consistent = abap_true OR <app>-title IS INITIAL ).
        <app>-title      = found-title.
        <app>-app_type   = found-app_type.
        <app>-target     = found-target.
        <app>-fiori_ids  = found-fiori_ids.
        <app>-desktop    = found-desktop.
        <app>-tablet     = found-tablet.
        <app>-phone      = found-phone.
        <app>-consistent = found-consistent.
      ENDIF.
      IF NOT line_exists( <app>-catalogs[ catalog = found-catalog ] ).
        APPEND VALUE #( catalog    = found-catalog
                        title      = found-catalog_title
                        consistent = found-consistent
                        state_text = found-state_text ) TO <app>-catalogs.
      ENDIF.
    ENDLOOP.

    result-total_count = lines( payload->apps ).
    IF payload->apps IS INITIAL.
      APPEND |No launchpad catalog contains a target mapping for "{ query }"; try other title words, the Fiori ID or the | &&
             |intent from the Fiori apps library.| TO result-next_steps.
      RETURN.
    ENDIF.
    SORT payload->apps BY title intent.
    IF lines( payload->apps ) > ctx->max_rows( ).
      DELETE payload->apps FROM ctx->max_rows( ) + 1.
      result-truncated = abap_true.
    ENDIF.

    LOOP AT payload->apps ASSIGNING <app> TO co_detail_apps.
      add_details( EXPORTING ctx = ctx CHANGING app = <app> result = result ).
    ENDLOOP.
    APPEND `AGR_HIER, AGR_BUFFI (catalogs in role menus), AGR_USERS (users holding the roles)` TO result-sources.

    IF result-total_count = 1.
      DATA(app) = payload->apps[ 1 ].
      IF app-roles IS INITIAL AND app-hidden_roles = 0.
        APPEND |No role contains a catalog of { app-title } ({ concat_lines_of( sep = `, ` table = VALUE string_table(
                                                                  FOR c IN app-catalogs ( c-catalog ) ) ) }); to offer the app, | &&
               |plan adding a catalog to a role with draft_role_change (add_catalogs).| TO result-next_steps.
      ENDIF.
      APPEND |To check a user, run diagnose_fiori_app_access with app = { app-intent }.| TO result-next_steps.
    ELSEIF result-total_count > co_detail_apps.
      APPEND |{ result-total_count } apps match; roles, start authorization and services are shown for the first | &&
             |{ co_detail_apps }. Call again with the intent or Fiori ID of the app meant.| TO result-next_steps.
    ENDIF.
  ENDMETHOD.

  METHOD add_details.
    DATA names TYPE zif_accx_role_repo=>ty_roles.

    app-details = abap_true.
    DATA(fiori_repo) = zcl_accx_domain_factory=>fiori_repo( ).
    DATA(catalog_ids) = VALUE string_table( FOR c IN app-catalogs ( c-catalog ) ).

    " roles containing a catalog of the app
    LOOP AT fiori_repo->get_catalog_roles( catalog_ids ) INTO DATA(role_catalog).
      IF line_exists( app-roles[ role = CONV string( role_catalog-role ) ] ).
        CONTINUE.
      ENDIF.
      IF ctx->guard( )->can_display_role( role_catalog-role ) = abap_false.
        app-hidden_roles += 1.
        CONTINUE.
      ENDIF.
      APPEND VALUE #( role = role_catalog-role catalog = role_catalog-catalog ) TO app-roles.
      APPEND role_catalog-role TO names.
    ENDLOOP.
    result-hidden_by_authorization += app-hidden_roles.
    DATA(counts) = zcl_accx_domain_factory=>role_repo( )->count_assigned_users( names ).
    LOOP AT app-roles ASSIGNING FIELD-SYMBOL(<role>).
      <role>-assigned_users = VALUE #( counts[ role = CONV agr_name( <role>-role ) ]-users OPTIONAL ).
    ENDLOOP.
    SORT app-roles BY assigned_users DESCENDING role ASCENDING.

    " start authorization of the target
    CASE app-app_type.
      WHEN zif_accx_fiori_repo=>co_app_type-gui.
        LOOP AT zcl_accx_domain_factory=>auth_evaluator( )->get_transaction_checks( CONV #( app-target ) ) INTO DATA(check).
          APPEND check_text( check ) TO app-start_authorization.
        ENDLOOP.
      WHEN zif_accx_fiori_repo=>co_app_type-wda.
        APPEND |S_START AUTHPGMID=R3TR, AUTHOBJTYP=WDYA, AUTHOBJNAM={ app-target }| TO app-start_authorization.
      WHEN zif_accx_fiori_repo=>co_app_type-ui5.
        TRY.
            DATA(services) = fiori_repo->get_app_services( app-target ).
          CATCH zcx_accx_error INTO DATA(error).
            APPEND |OData services of { app-target } not determined: { error->message }| TO result-warnings.
        ENDTRY.
        IF NOT line_exists( result-sources[ table_line = `UI5 app index (data sources), /IWFND/I_MED_SRH, USOBHASH (S_SERVICE)` ] ).
          APPEND `UI5 app index (data sources), /IWFND/I_MED_SRH, USOBHASH (S_SERVICE)` TO result-sources.
        ENDIF.
        LOOP AT services INTO DATA(service).
          DATA(entry) = VALUE ty_service( name = service-name version = service-version odata_version = service-odata_version
                                          active = service-active ).
          LOOP AT service-hashes INTO DATA(hash).
            APPEND COND string( WHEN hash-object = 'G4BA'
                                THEN |S_START AUTHPGMID=R3TR, AUTHOBJTYP=G4BA, AUTHOBJNAM={ hash-obj_name }|
                                ELSE |S_SERVICE SRV_NAME={ hash-hash }, SRV_TYPE=HT ({ hash-object } { hash-obj_name })| )
              TO entry-checks.
          ENDLOOP.
          IF service-active = abap_false.
            APPEND |OData service { service-name } (version { service-version }) of { app-title } is not activated: | &&
                   |activate it in /IWFND/MAINT_SERVICE.| TO result-next_steps.
          ENDIF.
          APPEND entry TO app-services.
        ENDLOOP.
    ENDCASE.
  ENDMETHOD.

  METHOD check_text.
    result = |{ check-object } { concat_lines_of( table = VALUE string_table( FOR f IN check-fields ( |{ f-field }={ f-value }| ) )
                                                  sep = `, ` ) }|.
  ENDMETHOD.

  METHOD zif_accx_tool~render_summary.
    FIELD-SYMBOLS <payload> TYPE ty_payload.
    IF result-data IS NOT BOUND OR result-summary IS NOT INITIAL.
      super->zif_accx_tool~render_summary( EXPORTING ctx = ctx CHANGING result = result ).
      RETURN.
    ENDIF.
    ASSIGN result-data->* TO <payload>.

    IF <payload>-apps IS INITIAL.
      result-summary = |No Fiori app matches "{ <payload>-query }".|.
      RETURN.
    ENDIF.
    result-summary = |**{ result-total_count }** { COND #( WHEN result-total_count = 1 THEN `app matches` ELSE `apps match` ) } | &&
                     |"{ <payload>-query }"{ COND #( WHEN result-truncated = abap_true THEN | (first { lines( <payload>-apps ) } listed)| ) }:|.
    LOOP AT <payload>-apps INTO DATA(app).
      DATA(form_factors) = VALUE string_table( ).
      IF app-desktop = abap_true.
        APPEND `desktop` TO form_factors.
      ENDIF.
      IF app-tablet = abap_true.
        APPEND `tablet` TO form_factors.
      ENDIF.
      IF app-phone = abap_true.
        APPEND `phone` TO form_factors.
      ENDIF.
      result-summary = |{ result-summary }\n\n**{ app-title }** ({ app-intent }{ COND #( WHEN app-fiori_ids IS NOT INITIAL
                                                                                        THEN |, Fiori ID { app-fiori_ids }| ) }): | &&
                       |{ app-app_type } { app-target }| &&
                       |{ COND #( WHEN form_factors IS NOT INITIAL THEN |, { concat_lines_of( table = form_factors sep = `, ` ) }| ) }| &&
                       |{ COND #( WHEN app-consistent = abap_false THEN ` - **target mapping inconsistent in every catalog**` ) }| &&
                       |\n- Catalogs: { concat_lines_of( sep = `, ` table = VALUE string_table(
                                          FOR c IN app-catalogs ( |{ c-catalog }{ COND #( WHEN c-consistent = abap_false
                                                                                          THEN | ({ c-state_text })| ) }| ) ) ) }|.
      IF app-details = abap_false.
        CONTINUE.
      ENDIF.
      IF app-roles IS INITIAL.
        result-summary = |{ result-summary }\n- Roles: none{ COND #( WHEN app-hidden_roles > 0
                                                                      THEN | you may display ({ app-hidden_roles } hidden)| ) }|.
      ELSE.
        DATA(role_texts) = VALUE string_table( ).
        LOOP AT app-roles INTO DATA(role) TO co_roles_shown.
          APPEND |{ role-role } ({ role-assigned_users } { COND #( WHEN role-assigned_users = 1 THEN `user` ELSE `users` ) })|
            TO role_texts.
        ENDLOOP.
        IF lines( app-roles ) > co_roles_shown.
          APPEND |... { lines( app-roles ) - co_roles_shown } more| TO role_texts.
        ENDIF.
        result-summary = |{ result-summary }\n- Roles ({ lines( app-roles ) }, most users first): | &&
                         |{ concat_lines_of( table = role_texts sep = `, ` ) }| &&
                         |{ COND #( WHEN app-hidden_roles > 0 THEN |; { app-hidden_roles } hidden| ) }|.
      ENDIF.
      IF app-start_authorization IS NOT INITIAL.
        result-summary = |{ result-summary }\n- Start authorization: { concat_lines_of( table = app-start_authorization sep = `; ` ) }|.
      ENDIF.
      LOOP AT app-services INTO DATA(service).
        result-summary = |{ result-summary }\n- OData { service-odata_version } service { service-name } (version { service-version }) | &&
                         |{ SWITCH string( service-active WHEN abap_true THEN `active` WHEN abap_false THEN `**not active**`
                                                           ELSE `publication not checked` ) }| &&
                         |{ COND #( WHEN service-checks IS NOT INITIAL
                                    THEN |: { concat_lines_of( table = service-checks sep = `; ` ) }|
                                    ELSE `: no S_SERVICE value found (USOBHASH)` ) }|.
      ENDLOOP.
    ENDLOOP.
    IF result-hidden_by_authorization > 0.
      result-summary = |{ result-summary }\n\n{ result-hidden_by_authorization } roles hidden due to missing display authorization.|.
    ENDIF.
  ENDMETHOD.

ENDCLASS.
