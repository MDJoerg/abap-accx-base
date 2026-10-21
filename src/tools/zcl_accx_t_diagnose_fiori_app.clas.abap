"! <p class="shorttext synchronized">Access Explorer tool: diagnose_fiori_app_access</p>
"! Why can a user not see or start a Fiori app? Walks the launchpad chain like
"! /UI2/FLIA, but from public APIs: app (intent) -> catalogs with a target
"! mapping -> roles of the user containing such a catalog (valid today, expired)
"! -> consistency of the target mapping -> start authorization (transaction,
"! S_START for Web Dynpro, S_SERVICE and activation of the OData services of a
"! SAPUI5 app). Embedded deployment only. The fix is handed over to
"! draft_role_change: the missing catalog for one of the user's roles, or all
"! missing S_SERVICE values for the role that brings the catalog.
CLASS zcl_accx_t_diagnose_fiori_app DEFINITION PUBLIC FINAL CREATE PUBLIC
  INHERITING FROM zcl_accx_tool_base.

  PUBLIC SECTION.
    CONSTANTS co_name TYPE string VALUE `diagnose_fiori_app_access`.

    CONSTANTS: BEGIN OF co_state,
                 ok      TYPE string VALUE `ok`,
                 problem TYPE string VALUE `problem`,
                 info    TYPE string VALUE `info`,
               END OF co_state.

    TYPES: BEGIN OF ty_step,
             "! app, catalog, content, start, service
             step  TYPE string,
             state TYPE string,
             text  TYPE string,
           END OF ty_step,
           ty_steps TYPE STANDARD TABLE OF ty_step WITH EMPTY KEY.

    TYPES: BEGIN OF ty_role,
             role           TYPE string,
             catalog        TYPE string,
             "! colleagues of the user group holding the role today
             peers          TYPE i,
             "! at least one colleague of the user group holds the role
             held_by_peers  TYPE abap_bool,
             assigned_users TYPE i,
             "! critical authorizations the role grants (SUIM definitions), as text
             critical       TYPE string,
             "! ranking weight of critical: high 100, medium 10, low 1 per rule
             critical_score TYPE i,
           END OF ty_role,
           ty_roles TYPE STANDARD TABLE OF ty_role WITH EMPTY KEY.

    TYPES: BEGIN OF ty_service_check,
             service TYPE string,
             version TYPE string,
             "! X active, space not active, - not checked (OData V4)
             active  TYPE abap_bool,
             "! IWSG, IWSV or G4BA
             object  TYPE string,
             hash    TYPE string,
             granted TYPE abap_bool,
           END OF ty_service_check,
           ty_service_checks TYPE STANDARD TABLE OF ty_service_check WITH EMPTY KEY.

    TYPES: BEGIN OF ty_payload,
             user                 TYPE string,
             query                TYPE string,
             "! the app can be found and started by the user (as far as checked)
             launchable           TYPE abap_bool,
             intent               TYPE string,
             title                TYPE string,
             app_type             TYPE string,
             target               TYPE string,
             fiori_ids            TYPE string,
             "! several apps match the query: intent - title (type)
             matches              TYPE string_table,
             "! catalogs containing a target mapping for the intent
             catalogs             TYPE string_table,
             "! role (catalog) of the user that makes the app available
             entitled_by          TYPE string_table,
             "! the user had the catalog through a role whose assignment is not valid today
             assignment_expired   TYPE abap_bool,
             "! critical authorizations of the expired role whose renewal is proposed
             renew_critical       TYPE string,
             "! roles containing such a catalog, if the user has none
             granting_roles       TYPE ty_roles,
             "! less critical role with the catalog, if the proposed role grants critical authorizations
             less_critical_option TYPE string,
             "! arguments for assign_role (plugin ADMIN, JSON object) once approved: renew the user's direct
             "! assignment that brought the catalog, or assign the proposed catalog role (not an unused SAP role)
             assign_arguments     TYPE string,
             start_checks         TYPE zif_accx_auth_evaluator=>ty_check_results,
             services             TYPE ty_service_checks,
             "! all missing S_SERVICE values as FIELD=VALUE (SRV_NAME per hash, SRV_TYPE=HT)
             service_values       TYPE string_table,
             "! role to change: the user's own role for a missing catalog, the catalog role for missing services
             draft_role           TYPE string,
             "! catalog to add to draft_role (empty: only S_SERVICE values are added)
             draft_catalog        TYPE string,
             "! why that role was chosen
             draft_reason         TYPE string,
             "! arguments for draft_role_change (JSON object)
             draft_arguments      TYPE string,
             steps                TYPE ty_steps,
           END OF ty_payload.

    CONSTANTS co_matches_shown TYPE i VALUE 15.
    CONSTANTS co_roles_shown   TYPE i VALUE 10.

    METHODS zif_accx_tool~get_descriptor REDEFINITION.
    METHODS zif_accx_tool~execute        REDEFINITION.
    METHODS zif_accx_tool~render_summary REDEFINITION.

  PRIVATE SECTION.
    "! Catalog entitlement: active, expired and missing roles; roles granting the catalog are rated
    "! by their critical authorizations
    METHODS check_catalogs
      IMPORTING !ctx     TYPE REF TO zif_accx_context
                !apps    TYPE zif_accx_fiori_repo=>ty_apps
      CHANGING  !payload TYPE ty_payload
                !result  TYPE zif_accx_types=>ty_result.

    "! Start authorization of the app's target
    METHODS check_start
      IMPORTING !app     TYPE zif_accx_fiori_repo=>ty_app
      CHANGING  !payload TYPE ty_payload
                !result  TYPE zif_accx_types=>ty_result
      RAISING   zcx_accx_error.

    "! Hands the fix over to draft_role_change: a missing catalog goes into one of the user's own roles
    "! (its authorization defaults bring the services); missing S_SERVICE values go into the role
    "! that brings the catalog
    METHODS plan_change
      IMPORTING !ctx     TYPE REF TO zif_accx_context
      CHANGING  !payload TYPE ty_payload
                !result  TYPE zif_accx_types=>ty_result.

    "! The user's own single role most used in the user group (as explain_missing_access chooses it)
    METHODS own_role
      IMPORTING !ctx    TYPE REF TO zif_accx_context
                !user   TYPE string
      EXPORTING !role   TYPE agr_name
                !reason TYPE string.

    "! Critical authorizations of a role (all rules it meets) and their weight
    METHODS rate_critical
      IMPORTING !role  TYPE csequence
      EXPORTING !text  TYPE string
                !score TYPE i.

    "! Does an S_SERVICE authorization of the values allow the service name?
    METHODS grants_service
      IMPORTING !values       TYPE zif_accx_critical_rules=>ty_auth_values
                !hash         TYPE csequence
      RETURNING VALUE(result) TYPE abap_bool.

    "! Usable as change target: displayable for the caller and not a composite role
    METHODS changeable
      IMPORTING !ctx          TYPE REF TO zif_accx_context
                !role         TYPE csequence
      RETURNING VALUE(result) TYPE abap_bool.

    METHODS simulate
      IMPORTING !user         TYPE syuname
                !check        TYPE zif_accx_auth_evaluator=>ty_check
      CHANGING  !payload      TYPE ty_payload
      RETURNING VALUE(result) TYPE zif_accx_auth_evaluator=>ty_check_result.

    METHODS logon_issue
      IMPORTING !user         TYPE syuname
      RETURNING VALUE(result) TYPE string.

    METHODS json_string
      IMPORTING !value        TYPE csequence
      RETURNING VALUE(result) TYPE string.

ENDCLASS.

CLASS zcl_accx_t_diagnose_fiori_app IMPLEMENTATION.

  METHOD zif_accx_tool~get_descriptor.
    result = VALUE #(
      name        = co_name
      title       = `Diagnose Fiori app access`
      description = |Explains why a user cannot see or start a Fiori launchpad app. The app is given as intent | &&
                    |(SemanticObject-action), Fiori ID (e.g. F4512), transaction of a GUI app, or words of the tile title. | &&
                    |The tool checks the chain step by step: catalogs containing a target mapping for the app, roles of the | &&
                    |user containing such a catalog (valid today, expired or missing - with roles that would grant it), | &&
                    |consistency and form factors of the target mapping, and the start authorization: transaction for GUI | &&
                    |apps, S_START for Web Dynpro apps, activation and S_SERVICE of every OData service of an SAPUI5 app. | &&
                    |Roles that would grant the catalog are ranked like in explain_missing_access: held by colleagues of the | &&
                    |user group first, then fewest critical authorizations (as defined in SUIM), customer roles before SAP | &&
                    |roles; their critical authorizations are named and a less critical alternative is offered. | &&
                    |The fix is handed over to draft_role_change: a missing catalog for one of the user's own roles, or all | &&
                    |missing S_SERVICE values for the role that brings the catalog. Renewing an expired assignment or | &&
                    |assigning the proposed catalog role is handed over to assign_role (plugin ADMIN) once approved. | &&
                    |Embedded launchpad only. Note: failed simulated checks are also recorded in the SU53 buffer of the | &&
                    |calling user.|
      group       = zif_accx_types=>co_group-fiori
      read_only   = abap_true
      idempotent  = abap_true
      sensitivity = zif_accx_types=>co_sensitivity-security
      output_type = `\CLASS=ZCL_ACCX_T_DIAGNOSE_FIORI_APP\TYPE=TY_PAYLOAD`
      params      = VALUE #( ( param( name        = `user`
                                      description = `User ID of the person who cannot use the app.`
                                      required    = abap_true
                                      maximum     = 12 ) )
                             ( param( name        = `app`
                                      description = |Intent (e.g. FLPPage-manage), Fiori ID (e.g. F4512), transaction of a GUI | &&
                                                    |app, or words of the tile title.|
                                      required    = abap_true
                                      maximum     = 100 ) ) ) ).
  ENDMETHOD.

  METHOD zif_accx_tool~execute.
    DATA(user)  = CONV syuname( to_upper( condense( args->get_string( `user` ) ) ) ).
    DATA(query) = condense( args->get_string( `app` ) ).

    DATA(user_repo) = zcl_accx_domain_factory=>user_repo( ).
    IF user_repo->exists( user ) = abap_false.
      RAISE EXCEPTION NEW zcx_accx_error( status = zif_accx_types=>co_status-not_found message = |User { user } does not exist.| ).
    ENDIF.
    IF ctx->guard( )->can_display_user( user ) = abap_false.
      RAISE EXCEPTION NEW zcx_accx_error( status = zif_accx_types=>co_status-denied message = |You may not display user { user }.| ).
    ENDIF.

    DATA(payload) = NEW ty_payload( user = user query = query ).
    result-data = payload.
    result-sources = VALUE #( ( `/UI2/FDM_PUBLIC_API (launchpad catalogs, target mappings)` )
                              ( `AGR_HIER, AGR_BUFFI (catalogs in role menus), AGR_USERS` ) ).

    " 1 - the app
    DATA(apps) = zcl_accx_domain_factory=>fiori_repo( )->find_apps( query ).
    IF apps IS INITIAL.
      APPEND VALUE #( step = `app` state = co_state-problem
                      text = |No launchpad catalog contains a target mapping for "{ query }" (searched as intent, Fiori ID, | &&
                             |transaction and tile title). The app is not available in this system's launchpad content.| )
        TO payload->steps.
      APPEND `Check the intent in the launchpad content manager (/UI2/FLPCM_CUST) or the Fiori apps library.` TO result-next_steps.
      RETURN.
    ENDIF.

    DATA(intents) = VALUE string_table( ).
    LOOP AT apps INTO DATA(found).
      IF NOT line_exists( intents[ table_line = found-intent ] ).
        APPEND found-intent TO intents.
        APPEND |{ found-intent } - { found-title } ({ found-app_type })| TO payload->matches.
      ENDIF.
    ENDLOOP.
    IF lines( intents ) > 1.
      APPEND VALUE #( step = `app` state = co_state-info
                      text = |{ lines( intents ) } apps match "{ query }"; call again with the intent of the one meant.| )
        TO payload->steps.
      APPEND |Call diagnose_fiori_app_access again with app = { intents[ 1 ] } (or another intent from the list).| TO result-next_steps.
      RETURN.
    ENDIF.
    CLEAR payload->matches.

    " the consistent target mapping represents the app; all catalogs count
    DATA(app) = VALUE #( apps[ consistent = abap_true ] DEFAULT apps[ 1 ] ).
    payload->intent    = app-intent.
    payload->title     = app-title.
    payload->app_type  = app-app_type.
    payload->target    = app-target.
    payload->fiori_ids = app-fiori_ids.
    LOOP AT apps INTO found.
      IF NOT line_exists( payload->catalogs[ table_line = found-catalog ] ).
        APPEND found-catalog TO payload->catalogs.
      ENDIF.
    ENDLOOP.
    APPEND VALUE #( step = `app` state = co_state-ok
                    text = |{ app-title } ({ app-intent }, { app-app_type } { app-target }| &&
                           |{ COND #( WHEN app-fiori_ids IS NOT INITIAL THEN |, Fiori ID { app-fiori_ids }| ) }) is in | &&
                           |{ lines( payload->catalogs ) } { COND #( WHEN lines( payload->catalogs ) = 1 THEN `catalog` ELSE `catalogs` ) }: | &&
                           |{ concat_lines_of( table = payload->catalogs sep = `, ` ) }.| ) TO payload->steps.

    " 2 - catalogs in the user's roles
    check_catalogs( EXPORTING ctx = ctx apps = apps CHANGING payload = payload->* result = result ).

    " 3 - target mapping content and form factors
    IF NOT line_exists( apps[ consistent = abap_true ] ).
      APPEND VALUE #( step = `content` state = co_state-problem
                      text = |The target mapping is broken in every catalog: { app-state_text }. The launchpad cannot resolve | &&
                             |the intent; repair it in the launchpad content manager.| ) TO payload->steps.
    ELSEIF app-desktop = abap_false.
      APPEND VALUE #( step = `content` state = co_state-info
                      text = |The app is not released for desktop devices (tablet { COND #( WHEN app-tablet = abap_true THEN `yes` ELSE `no` ) }, | &&
                             |phone { COND #( WHEN app-phone = abap_true THEN `yes` ELSE `no` ) }); on a desktop it is not offered.| )
        TO payload->steps.
    ENDIF.

    " 4 - start authorization; the fix as one role change
    check_start( EXPORTING app = app CHANGING payload = payload->* result = result ).
    plan_change( EXPORTING ctx = ctx CHANGING payload = payload->* result = result ).

    DATA(issue) = logon_issue( user ).
    IF issue IS NOT INITIAL.
      APPEND VALUE #( step = `user` state = co_state-problem text = |{ user } cannot log on: { issue }.| ) TO payload->steps.
    ENDIF.

    payload->launchable = xsdbool( NOT line_exists( payload->steps[ state = co_state-problem ] ) ).
    result-total_count = lines( payload->steps ).
    IF line_exists( payload->start_checks[ granted = abap_false ] ) OR line_exists( payload->services[ granted = abap_false ] ).
      APPEND |Failed simulated checks are also recorded in the SU53 buffer of the calling user { ctx->caller( ) }, not of { user }.|
        TO result-warnings.
    ENDIF.
  ENDMETHOD.

  METHOD check_catalogs.
    TYPES: BEGIN OF ty_ranked,
             held_by_peers  TYPE abap_bool,
             critical_score TYPE i,
             sap_template   TYPE abap_bool,
             peers          TYPE i,
             assigned_users TYPE i,
             role           TYPE string,
             entry          TYPE ty_role,
           END OF ty_ranked.
    DATA user_roles TYPE zif_accx_role_repo=>ty_roles.
    DATA ranked     TYPE STANDARD TABLE OF ty_ranked WITH EMPTY KEY.

    DATA(fiori_repo) = zcl_accx_domain_factory=>fiori_repo( ).
    DATA(role_repo)  = zcl_accx_domain_factory=>role_repo( ).
    DATA(user_repo)  = zcl_accx_domain_factory=>user_repo( ).
    DATA(assignments) = user_repo->get_role_assignments( CONV #( payload-user ) ).
    LOOP AT assignments INTO DATA(assignment).
      APPEND assignment-role TO user_roles.
    ENDLOOP.

    DATA(expired) = VALUE string_table( ).
    DATA(renew) = VALUE agr_name( ).
    LOOP AT fiori_repo->get_role_catalogs( user_roles ) INTO DATA(role_catalog).
      IF NOT line_exists( payload-catalogs[ table_line = role_catalog-catalog ] ).
        CONTINUE.
      ENDIF.
      IF line_exists( assignments[ role = role_catalog-role active = abap_true ] ).
        APPEND |{ role_catalog-role } ({ role_catalog-catalog })| TO payload-entitled_by.
      ELSE.
        DATA(assignment_of) = assignments[ role = role_catalog-role ].
        APPEND |{ role_catalog-role } ({ role_catalog-catalog }) - assignment | &&
               |{ COND #( WHEN assignment_of-valid_to < sy-datum THEN |expired on { assignment_of-valid_to DATE = ISO }|
                          ELSE |valid only from { assignment_of-valid_from DATE = ISO }| ) }| TO expired.
        " a direct assignment can be renewed with assign_role; one through a composite role is renewed there
        IF renew IS INITIAL AND line_exists( assignments[ role = role_catalog-role via_composite = abap_false ] ).
          renew = role_catalog-role.
        ENDIF.
      ENDIF.
    ENDLOOP.

    IF payload-entitled_by IS NOT INITIAL.
      APPEND VALUE #( step = `catalog` state = co_state-ok
                      text = |Available through { concat_lines_of( table = payload-entitled_by sep = `, ` ) }.| ) TO payload-steps.
      RETURN.
    ENDIF.

    DATA(explain) = NEW zcl_accx_t_explain_missing( ).
    IF expired IS NOT INITIAL.
      payload-assignment_expired = abap_true.
      APPEND VALUE #( step = `catalog` state = co_state-problem
                      text = |The user had the app through { concat_lines_of( table = expired sep = `, ` ) }.| ) TO payload-steps.
      IF renew IS NOT INITIAL.
        rate_critical( EXPORTING role = renew IMPORTING text = payload-renew_critical ).
        payload-assign_arguments = explain->assign_arguments(
          user   = payload-user
          role   = renew
          reason = |Fiori app { payload-title } ({ payload-intent }): renew role { renew }, found by diagnose_fiori_app_access| ).
        IF payload-renew_critical IS NOT INITIAL.
          APPEND |Renewing role { renew } gives { payload-user } critical authorizations again: { payload-renew_critical }.|
            TO result-warnings.
        ENDIF.
      ENDIF.
      APPEND |Extend the role assignment ({ concat_lines_of( table = expired sep = `; ` ) }) via the access request process| &&
             |{ COND #( WHEN payload-assign_arguments IS NOT INITIAL
                        THEN |; once approved, with write access (plugin ADMIN): assign_role { payload-assign_arguments }| ) }| &&
             |{ COND #( WHEN payload-renew_critical IS NOT INITIAL
                        THEN ` (refused for the critical authorizations unless accept_critical is set)` ) }.|
        TO result-next_steps.
    ELSE.
      APPEND VALUE #( step = `catalog` state = co_state-problem
                      text = `None of the user's roles contains a catalog with this app, so the launchpad does not offer it.` )
        TO payload-steps.
    ENDIF.

    " roles that would grant it, rated like explain_missing_access: practice in the user group first, then the
    " least critical, customer roles before SAP roles, then by colleagues and users in total
    DATA(group) = CONV xuclass( user_repo->get_user( CONV #( payload-user ) )-user_group ).
    DATA(names) = VALUE zif_accx_role_repo=>ty_roles( ).
    LOOP AT fiori_repo->get_catalog_roles( payload-catalogs ) INTO role_catalog.
      IF line_exists( payload-granting_roles[ role = CONV string( role_catalog-role ) ] ).
        CONTINUE.
      ENDIF.
      IF ctx->guard( )->can_display_role( role_catalog-role ) = abap_false.
        result-hidden_by_authorization += 1.
        CONTINUE.
      ENDIF.
      DATA(granting) = VALUE ty_role( role    = role_catalog-role
                                      catalog = role_catalog-catalog
                                      peers   = role_repo->count_holders( role = role_catalog-role user_group = group
                                                                          exclude_user = CONV #( payload-user ) ) ).
      granting-held_by_peers = xsdbool( granting-peers > 0 ).
      rate_critical( EXPORTING role = role_catalog-role IMPORTING text = granting-critical score = granting-critical_score ).
      APPEND granting TO payload-granting_roles.
      APPEND role_catalog-role TO names.
    ENDLOOP.
    DATA(counts) = role_repo->count_assigned_users( names ).
    LOOP AT payload-granting_roles INTO granting.
      granting-assigned_users = VALUE #( counts[ role = CONV agr_name( granting-role ) ]-users OPTIONAL ).
      APPEND VALUE #( held_by_peers  = granting-held_by_peers
                      critical_score = granting-critical_score
                      sap_template   = xsdbool( granting-role CP 'SAP_*' )
                      peers          = granting-peers
                      assigned_users = granting-assigned_users
                      role           = granting-role
                      entry          = granting ) TO ranked.
    ENDLOOP.
    SORT ranked BY held_by_peers  DESCENDING
                   critical_score ASCENDING
                   sap_template   ASCENDING
                   peers          DESCENDING
                   assigned_users DESCENDING
                   role           ASCENDING.
    payload-granting_roles = VALUE #( FOR r IN ranked ( r-entry ) ).
    IF payload-granting_roles IS NOT INITIAL OR renew IS NOT INITIAL.
      APPEND `USCRAUTHID, USCRAUTH (SUIM critical authorizations)` TO result-sources.
    ENDIF.

    IF payload-granting_roles IS NOT INITIAL AND expired IS INITIAL.
      DATA(best) = payload-granting_roles[ 1 ].
      DATA(usage) = COND string( WHEN best-peers > 0 THEN |held by { best-peers } colleagues of the user group|
                                 ELSE |held by { best-assigned_users } users, none of the user group| ).
      DATA(template) = xsdbool( best-role CP 'SAP_*' AND best-held_by_peers = abap_false ).
      " less critical role outside the user group's practice (sorted by score within that part)
      IF best-critical_score > 0.
        LOOP AT payload-granting_roles INTO DATA(option) WHERE held_by_peers = abap_false.
          IF option-critical_score < best-critical_score.
            payload-less_critical_option = option-role.
          ENDIF.
          EXIT.
        ENDLOOP.
        APPEND |The proposed role { best-role } grants critical authorizations: { best-critical }.| TO result-warnings.
      ENDIF.
      " an SAP role nobody in the user group holds is a template to copy, not to assign
      IF template = abap_false.
        payload-assign_arguments = explain->assign_arguments(
          user   = payload-user
          role   = best-role
          reason = |Fiori app { payload-title } ({ payload-intent }) is in catalog { best-catalog }, | &&
                   |found by diagnose_fiori_app_access| ).
      ENDIF.
      APPEND COND string(
        WHEN template = abap_true
        THEN |Copy the SAP role { best-role } (catalog { best-catalog }, { usage }) to a customer role and request that | &&
             |for { payload-user }. Or add catalog { best-catalog } to one of the user's roles.|
        ELSE |Request role { best-role } (catalog { best-catalog }, { usage }) for { payload-user }| &&
             |; once approved, with write access (plugin ADMIN): assign_role { payload-assign_arguments }| &&
             |{ COND #( WHEN best-critical IS NOT INITIAL
                        THEN ` (refused for the critical authorizations unless accept_critical is set)` ) }| &&
             |. Or add catalog { best-catalog } to one of the user's roles.| ) TO result-next_steps.
      IF payload-less_critical_option IS NOT INITIAL.
        APPEND |If the critical authorizations of { best-role } are not acceptable, request the less critical role | &&
               |{ payload-less_critical_option } instead (not yet used in the user group| &&
               |{ COND #( WHEN payload-less_critical_option CP 'SAP_*' THEN `; an SAP role, to be copied first` ) }).|
          TO result-next_steps.
      ENDIF.
    ELSEIF payload-granting_roles IS INITIAL AND expired IS INITIAL.
      APPEND |No role you may display contains catalog { concat_lines_of( table = payload-catalogs sep = `, ` ) }: add the | &&
             |catalog to a role of the user in PFCG.| TO result-next_steps.
    ENDIF.
  ENDMETHOD.

  METHOD check_start.
    DATA(user) = CONV syuname( payload-user ).
    CASE app-app_type.
      WHEN zif_accx_fiori_repo=>co_app_type-gui.
        LOOP AT zcl_accx_domain_factory=>auth_evaluator( )->get_transaction_checks( CONV #( app-target ) ) INTO DATA(check).
          APPEND simulate( EXPORTING user = user check = check CHANGING payload = payload ) TO payload-start_checks.
        ENDLOOP.
        APPEND `TSTC, TSTCA (start authorization of the transaction)` TO result-sources.
      WHEN zif_accx_fiori_repo=>co_app_type-wda.
        APPEND simulate( EXPORTING user  = user
                                   check = VALUE #( object = 'S_START' reason = `start of the Web Dynpro application`
                                                    fields = VALUE #( ( field = 'AUTHPGMID'  value = `R3TR` )
                                                                      ( field = 'AUTHOBJTYP' value = `WDYA` )
                                                                      ( field = 'AUTHOBJNAM' value = app-target ) ) )
                         CHANGING  payload = payload ) TO payload-start_checks.
      WHEN zif_accx_fiori_repo=>co_app_type-ui5.
        TRY.
            DATA(services) = zcl_accx_domain_factory=>fiori_repo( )->get_app_services( app-target ).
          CATCH zcx_accx_error INTO DATA(error).
            APPEND VALUE #( step = `service` state = co_state-info
                            text = |OData services of { app-target } not determined: { error->message }| ) TO payload-steps.
            RETURN.
        ENDTRY.
        APPEND `UI5 app index (data sources), /IWFND/I_MED_SRH, USOBHASH (S_SERVICE)` TO result-sources.
        IF services IS INITIAL.
          APPEND VALUE #( step = `service` state = co_state-info
                          text = |The UI5 app index lists no OData service for { app-target }.| ) TO payload-steps.
        ENDIF.
        LOOP AT services INTO DATA(service).
          IF service-active = abap_false.
            APPEND VALUE #( step = `service` state = co_state-problem
                            text = |OData service { service-name } (version { service-version }) is not activated in the | &&
                                   |gateway; the app cannot load its data.| ) TO payload-steps.
            APPEND |Activate { service-name } in /IWFND/MAINT_SERVICE.| TO result-next_steps.
          ENDIF.
          IF service-hashes IS INITIAL.
            APPEND VALUE #( service = service-name version = service-version active = service-active granted = abap_undefined )
              TO payload-services.
            APPEND VALUE #( step = `service` state = co_state-info
                            text = |S_SERVICE value of { service-name } not found (USOBHASH); not checked.| ) TO payload-steps.
          ENDIF.
          LOOP AT service-hashes INTO DATA(hash).
            " OData V2: S_SERVICE with the hash; OData V4: S_START for the service group
            DATA(outcome) = simulate(
              EXPORTING user  = user
                        check = COND #( WHEN hash-object = 'G4BA'
                                        THEN VALUE #( object = 'S_START'
                                                      reason = |OData V4 service group { hash-obj_name }|
                                                      fields = VALUE #( ( field = 'AUTHPGMID'  value = `R3TR` )
                                                                        ( field = 'AUTHOBJTYP' value = `G4BA` )
                                                                        ( field = 'AUTHOBJNAM' value = hash-obj_name ) ) )
                                        ELSE VALUE #( object = 'S_SERVICE'
                                                      reason = |OData service { service-name } ({ hash-object })|
                                                      fields = VALUE #( ( field = 'SRV_NAME' value = hash-hash )
                                                                        ( field = 'SRV_TYPE' value = `HT` ) ) ) )
              CHANGING  payload = payload ).
            APPEND VALUE #( service = service-name version = service-version active = service-active object = hash-object
                            hash    = COND #( WHEN hash-object = 'G4BA' THEN hash-obj_name ELSE CONV string( hash-hash ) )
                            granted = outcome-granted ) TO payload-services.
          ENDLOOP.
        ENDLOOP.
        DATA(denied) = REDUCE i( INIT n = 0 FOR s IN payload-services WHERE ( granted = abap_false ) NEXT n = n + 1 ).
        IF denied > 0.
          DATA(objects) = COND string( WHEN line_exists( payload-services[ granted = abap_false object = `G4BA` ] )
                                       THEN `S_SERVICE or S_START (OData V4)` ELSE `S_SERVICE` ).
          APPEND VALUE #( step = `start` state = co_state-problem
                          text = |{ objects } is missing for { denied } of { lines( payload-services ) } service checks: | &&
                                 |{ concat_lines_of( table = VALUE string_table( FOR s IN payload-services WHERE ( granted = abap_false )
                                                                                 ( |{ s-service } ({ s-object } { s-hash })| ) )
                                                     sep = `, ` ) }.| ) TO payload-steps.
        ELSEIF payload-services IS NOT INITIAL.
          APPEND VALUE #( step = `start` state = co_state-ok
                          text = |S_SERVICE granted for all { lines( payload-services ) } service checks.| ) TO payload-steps.
        ENDIF.
        RETURN.
      WHEN OTHERS.
        APPEND VALUE #( step = `start` state = co_state-info
                        text = |{ app-app_type } target: no start authorization check by the launchpad.| ) TO payload-steps.
        RETURN.
    ENDCASE.

    DATA(missing) = VALUE string_table( FOR c IN payload-start_checks WHERE ( granted = abap_false )
                                        ( |{ c-object } ({ c-condition })| ) ).
    IF missing IS INITIAL.
      APPEND VALUE #( step = `start` state = co_state-ok
                      text = |Start authorization for { app-target } granted.| ) TO payload-steps.
    ELSE.
      APPEND VALUE #( step = `start` state = co_state-problem
                      text = |Start authorization for { app-target } missing: { concat_lines_of( table = missing sep = `, ` ) }.| )
        TO payload-steps.
      APPEND COND string( WHEN app-app_type = zif_accx_fiori_repo=>co_app_type-gui
                          THEN |Run explain_missing_access for { payload-user } with transaction { app-target }.|
                          ELSE |Run explain_missing_access for { payload-user } with target_type authorization, target S_START, | &&
                               |values AUTHPGMID=R3TR, AUTHOBJTYP=WDYA, AUTHOBJNAM={ app-target }.| ) TO result-next_steps.
    ENDIF.
  ENDMETHOD.

  METHOD plan_change.
    DATA role TYPE agr_name.

    " OData V4 service groups are started with S_START, not with a catalog's S_SERVICE values
    LOOP AT payload-services INTO DATA(group) WHERE granted = abap_false AND object = `G4BA`.
      APPEND |Run explain_missing_access for { payload-user } with target_type authorization, target S_START, values | &&
             |AUTHPGMID=R3TR, AUTHOBJTYP=G4BA, AUTHOBJNAM={ group-hash } (OData V4 service group of { group-service }).|
        TO result-next_steps.
    ENDLOOP.

    DATA(names) = VALUE string_table( ).
    LOOP AT payload-services INTO DATA(service) WHERE granted = abap_false AND object <> `G4BA`.
      IF NOT line_exists( names[ table_line = service-hash ] ).
        APPEND service-hash TO names.
      ENDIF.
    ENDLOOP.
    IF names IS NOT INITIAL.
      payload-service_values = VALUE #( FOR n IN names ( |SRV_NAME={ n }| ) ).
      APPEND `SRV_TYPE=HT` TO payload-service_values.
    ENDIF.
    DATA(explain_step) = COND string(
      WHEN names IS NOT INITIAL
      THEN |To look for existing roles instead, run explain_missing_access for { payload-user } with target_type | &&
           |authorization, target S_SERVICE, values SRV_NAME={ names[ 1 ] }, SRV_TYPE=HT (one value per call; the app | &&
           |needs all { lines( names ) }).| ).

    IF payload-entitled_by IS NOT INITIAL.
      " the catalog is there, its role lacks service values (PFCG proposes them with the catalog)
      IF names IS INITIAL.
        RETURN.
      ENDIF.
      SPLIT payload-entitled_by[ 1 ] AT ` ` INTO DATA(entitled) DATA(catalog_note) ##NEEDED.
      role = entitled.
      payload-draft_reason = |the user's role that brings the app's catalog should also grant its services|.
      IF changeable( ctx = ctx role = role ) = abap_false.
        own_role( EXPORTING ctx = ctx user = payload-user IMPORTING role = role reason = payload-draft_reason ).
      ENDIF.
      IF role IS NOT INITIAL.
        payload-draft_role = role.
        payload-draft_arguments =
          |\{"role":{ json_string( role ) },"object":"S_SERVICE","values":[| &&
          |{ concat_lines_of( table = VALUE string_table( FOR v IN payload-service_values ( json_string( v ) ) ) sep = `,` ) }]| &&
          |,"for_user":{ json_string( payload-user ) }| &&
          |,"reason":{ json_string( |Fiori app { payload-title } ({ payload-intent }) needs the S_SERVICE values of its | &&
                                    |OData services, found by diagnose_fiori_app_access| ) }\}|.
        APPEND |Plan adding all { lines( names ) } missing S_SERVICE values to role { role } ({ payload-draft_reason }) with | &&
               |draft_role_change { payload-draft_arguments }| TO result-next_steps.
      ELSE.
        CLEAR payload-draft_reason.
      ENDIF.
      APPEND explain_step TO result-next_steps.
      RETURN.
    ENDIF.

    IF payload-assignment_expired = abap_true.
      " renewing the assignment brings the catalog back
      IF explain_step IS NOT INITIAL.
        APPEND explain_step TO result-next_steps.
      ENDIF.
      RETURN.
    ENDIF.

    " the catalog is missing: does the proposed catalog role bring the services as well?
    DATA(closes_services) = abap_false.
    DATA(catalog) = payload-catalogs[ 1 ].
    IF payload-granting_roles IS NOT INITIAL.
      DATA(best) = payload-granting_roles[ 1 ].
      catalog = best-catalog.
      IF names IS NOT INITIAL.
        DATA(values) = zcl_accx_domain_factory=>role_repo( )->get_authorization_values( CONV #( best-role ) ).
        DATA(granted) = REDUCE i( INIT g = 0 FOR n IN names
                                  NEXT g = g + COND i( WHEN grants_service( values = values hash = n ) = abap_true THEN 1 ) ).
        IF granted = lines( names ).
          closes_services = abap_true.
          APPEND |Role { best-role } also grants all { lines( names ) } missing S_SERVICE values; requesting it closes the | &&
                 |catalog and the service gap.| TO result-next_steps.
        ENDIF.
      ENDIF.
    ENDIF.

    " alternative: the catalog with its authorization defaults in one of the user's own roles - the way around
    " the critical authorizations of the proposed role; draft_role_change rates the catalog's own defaults
    own_role( EXPORTING ctx = ctx user = payload-user IMPORTING role = role reason = payload-draft_reason ).
    IF role IS NOT INITIAL.
      payload-draft_role    = role.
      payload-draft_catalog = catalog.
      payload-draft_arguments =
        |\{"role":{ json_string( role ) },"add_catalogs":[{ json_string( catalog ) }]| &&
        |,"for_user":{ json_string( payload-user ) }| &&
        |,"reason":{ json_string( |Fiori app { payload-title } ({ payload-intent }) is in catalog { catalog }, | &&
                                  |found by diagnose_fiori_app_access| ) }\}|.
      APPEND |{ COND #( WHEN best-critical IS NOT INITIAL
                        THEN |To avoid the critical authorizations of { best-role }, plan adding|
                        ELSE `Or plan adding` ) } catalog { catalog } to the user's role { role } | &&
             |({ payload-draft_reason }); its authorization defaults bring the start authorizations of all its apps| &&
             |{ COND #( WHEN names IS NOT INITIAL THEN `, including this app's services` ) }| &&
             |{ COND #( WHEN best-critical IS NOT INITIAL THEN ` (draft_role_change rates their criticality)` ) }: | &&
             |draft_role_change { payload-draft_arguments }| TO result-next_steps.
    ELSE.
      CLEAR payload-draft_reason.
    ENDIF.
    IF closes_services = abap_false AND explain_step IS NOT INITIAL.
      APPEND explain_step TO result-next_steps.
    ENDIF.
  ENDMETHOD.

  METHOD own_role.
    DATA(user_repo) = zcl_accx_domain_factory=>user_repo( ).
    NEW zcl_accx_t_explain_missing( )->own_role_to_extend(
      EXPORTING ctx         = ctx
                assignments = user_repo->get_role_assignments( CONV #( user ) )
                user_group  = CONV #( user_repo->get_user( CONV #( user ) )-user_group )
                user        = CONV #( user )
      IMPORTING role        = role
                peers       = DATA(peers) ).
    reason = |one of the user's own roles, held by { peers } | &&
             |{ COND #( WHEN peers = 1 THEN `colleague` ELSE `colleagues` ) } of the user group|.
  ENDMETHOD.

  METHOD grants_service.
    LOOP AT values INTO DATA(value) WHERE object = 'S_SERVICE' AND field = 'SRV_NAME'.
      IF zcl_accx_auth_value=>covers( value = hash low = value-low high = value-high ) = abap_true.
        result = abap_true.
        RETURN.
      ENDIF.
    ENDLOOP.
  ENDMETHOD.

  METHOD changeable.
    result = xsdbool( ctx->guard( )->can_display_role( CONV #( role ) ) = abap_true
                      AND zcl_accx_domain_factory=>role_repo( )->get_role_info( CONV #( role ) )-composite = abap_false ).
  ENDMETHOD.

  METHOD simulate.
    result = zcl_accx_domain_factory=>auth_evaluator( )->simulate( user = user check = check ).
  ENDMETHOD.

  METHOD logon_issue.
    DATA(master) = zcl_accx_domain_factory=>user_repo( )->get_user( user ).
    IF master-locked = abap_true.
      result = |locked: { master-lock_reasons }|.
    ELSEIF master-valid_from IS NOT INITIAL AND sy-datum < master-valid_from.
      result = |user valid only from { master-valid_from DATE = ISO }|.
    ELSEIF master-valid_to IS NOT INITIAL AND sy-datum > master-valid_to.
      result = |user validity expired on { master-valid_to DATE = ISO }|.
    ENDIF.
  ENDMETHOD.

  METHOD json_string.
    result = |"{ escape( val = value format = cl_abap_format=>e_json_string ) }"|.
  ENDMETHOD.

  METHOD zif_accx_tool~render_summary.
    FIELD-SYMBOLS <payload> TYPE ty_payload.
    IF result-data IS NOT BOUND OR result-summary IS NOT INITIAL.
      super->zif_accx_tool~render_summary( EXPORTING ctx = ctx CHANGING result = result ).
      RETURN.
    ENDIF.
    ASSIGN result-data->* TO <payload>.

    IF <payload>-matches IS NOT INITIAL.
      result-summary = |**{ lines( <payload>-matches ) } apps** match "{ <payload>-query }"; name the intent of the one meant:|.
      LOOP AT <payload>-matches INTO DATA(match) TO co_matches_shown.
        result-summary = |{ result-summary }\n- { match }|.
      ENDLOOP.
      IF lines( <payload>-matches ) > co_matches_shown.
        result-summary = |{ result-summary }\n- ...|.
      ENDIF.
      RETURN.
    ENDIF.

    DATA(app) = COND string( WHEN <payload>-intent IS NOT INITIAL THEN |**{ <payload>-title }** ({ <payload>-intent })|
                             ELSE |"{ <payload>-query }"| ).
    result-summary = COND #( WHEN <payload>-launchable = abap_true
                             THEN |User **{ <payload>-user }** can find and start { app } - no problem found in the launchpad chain.|
                             ELSE |User **{ <payload>-user }** cannot use { app }:| ).
    LOOP AT <payload>-steps INTO DATA(step).
      result-summary = |{ result-summary }\n- { SWITCH string( step-state WHEN co_state-ok THEN `OK` WHEN co_state-problem THEN `**PROBLEM**`
                                                                ELSE `Note` ) } ({ step-step }): { step-text }|.
    ENDLOOP.
    IF <payload>-renew_critical IS NOT INITIAL.
      result-summary = |{ result-summary }\n\n**Renewing the expired role gives critical authorizations again:** | &&
                       |{ <payload>-renew_critical }.|.
    ENDIF.
    IF <payload>-granting_roles IS NOT INITIAL.
      result-summary = |{ result-summary }\n\nRoles containing a catalog with the app (practice in the user group, then | &&
                       |least critical first):|.
      LOOP AT <payload>-granting_roles INTO DATA(role) TO co_roles_shown.
        result-summary = |{ result-summary }\n- { role-role } (catalog { role-catalog }): { role-peers } | &&
                         |{ COND #( WHEN role-peers = 1 THEN `colleague` ELSE `colleagues` ) }, { role-assigned_users } users in total| &&
                         |{ COND #( WHEN role-critical IS NOT INITIAL THEN |, **critical:** { role-critical }|
                                    ELSE `, no critical authorizations` ) }|.
      ENDLOOP.
      IF lines( <payload>-granting_roles ) > co_roles_shown.
        result-summary = |{ result-summary }\n- ... { lines( <payload>-granting_roles ) - co_roles_shown } more|.
      ENDIF.
      IF <payload>-less_critical_option IS NOT INITIAL.
        result-summary = |{ result-summary }\n\n**Less critical alternative:** role **{ <payload>-less_critical_option }** | &&
                         |(not held by colleagues of the user group| &&
                         |{ COND #( WHEN <payload>-less_critical_option CP 'SAP_*' THEN `; SAP role, to be copied first` ) }).|.
      ENDIF.
    ENDIF.
    IF <payload>-draft_catalog IS NOT INITIAL.
      result-summary = |{ result-summary }\n\n**Role change instead of a new role:** add catalog **{ <payload>-draft_catalog }** | &&
                       |to role **{ <payload>-draft_role }** ({ <payload>-draft_reason }); draft_role_change shows all apps, | &&
                       |authorizations, critical authorizations and users affected before anything is changed.|.
    ELSEIF <payload>-draft_role IS NOT INITIAL.
      result-summary = |{ result-summary }\n\n**Services:** add all { lines( <payload>-service_values ) - 1 } missing S_SERVICE | &&
                       |values to role **{ <payload>-draft_role }** ({ <payload>-draft_reason }); draft_role_change shows the | &&
                       |change and all users affected before anything is changed.|.
    ENDIF.
    IF result-hidden_by_authorization > 0.
      result-summary = |{ result-summary }\n\n{ result-hidden_by_authorization } further roles contain the catalog but you may not display them.|.
    ENDIF.
  ENDMETHOD.

  METHOD rate_critical.
    CLEAR: text, score.
    LOOP AT zcl_accx_domain_factory=>critical_rules( )->evaluate_role( CONV #( role ) ) INTO DATA(hit).
      text = |{ text }{ COND #( WHEN text IS NOT INITIAL THEN `; ` ) }{ hit-text } ({ hit-rule }, { hit-level })|.
      " same weights as explain_missing_access
      score += SWITCH i( hit-level
                         WHEN zif_accx_critical_rules=>co_level-high   THEN 100
                         WHEN zif_accx_critical_rules=>co_level-medium THEN 10
                         ELSE 1 ).
    ENDLOOP.
  ENDMETHOD.
ENDCLASS.
