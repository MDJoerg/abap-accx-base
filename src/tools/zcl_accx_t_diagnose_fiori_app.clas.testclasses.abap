"! Apps: Sales-display (UI5 z.sales, catalog C_SALES), Sales-change (UI5, for the ambiguous title search),
"! Report-run (GUI ZREP, C_REP), Wda-start (WDA ZWDA, broken, C_REP), Group-show (UI5 z.v4, OData V4, C_REP).
"! Role catalogs: R_FIORI and R_HIDDEN -> C_SALES, R_REP -> C_REP; R_SAFE -> C_SALES if alternative is set.
"! Services of z.sales: /Z/ACTIVE_SRV (hashes HA1, HA2), /Z/OFF_SRV (inactive, hash HOFF); z.v4: /Z/V4_SRV in
"! service group ZV4_GROUP
CLASS ltd_fiori DEFINITION FINAL FOR TESTING.
  PUBLIC SECTION.
    INTERFACES zif_accx_fiori_repo PARTIALLY IMPLEMENTED.
    CLASS-DATA alternative TYPE abap_bool.
    CLASS-METHODS role_catalogs RETURNING VALUE(result) TYPE zif_accx_fiori_repo=>ty_role_catalogs.
ENDCLASS.

CLASS ltd_fiori IMPLEMENTATION.
  METHOD role_catalogs.
    result = VALUE #( ( role = 'R_FIORI' catalog = `C_SALES` )
                      ( role = 'R_HIDDEN' catalog = `C_SALES` )
                      ( role = 'R_REP' catalog = `C_REP` ) ).
    IF alternative = abap_true.
      APPEND VALUE #( role = 'R_SAFE' catalog = `C_SALES` ) TO result.
    ENDIF.
  ENDMETHOD.
  METHOD zif_accx_fiori_repo~find_apps.
    DATA(all) = VALUE zif_accx_fiori_repo=>ty_apps(
      ( catalog = `C_SALES` intent = `Sales-display` title = `Display Sales` app_type = `UI5` target = `z.sales`
        fiori_ids = `F0001` desktop = abap_true consistent = abap_true )
      ( catalog = `C_SALES` intent = `Sales-change` title = `Change Sales` app_type = `UI5` target = `z.sales.change`
        desktop = abap_true consistent = abap_true )
      ( catalog = `C_REP` intent = `Report-run` title = `Run Report` app_type = `GUI` target = `ZREP`
        desktop = abap_true consistent = abap_true )
      ( catalog = `C_REP` intent = `Wda-start` title = `Start WDA` app_type = `WDA` target = `ZWDA`
        phone = abap_true consistent = abap_false state_text = `reference lost` )
      ( catalog = `C_REP` intent = `Group-show` title = `Show Group` app_type = `UI5` target = `z.v4`
        desktop = abap_true consistent = abap_true ) ).
    LOOP AT all INTO DATA(app).
      IF app-intent = query OR app-fiori_ids = query OR app-title CS query.
        APPEND app TO result.
      ENDIF.
    ENDLOOP.
  ENDMETHOD.
  METHOD zif_accx_fiori_repo~get_role_catalogs.
    LOOP AT role_catalogs( ) INTO DATA(entry).
      IF line_exists( roles[ table_line = entry-role ] ).
        APPEND entry TO result.
      ENDIF.
    ENDLOOP.
  ENDMETHOD.
  METHOD zif_accx_fiori_repo~get_catalog_roles.
    LOOP AT role_catalogs( ) INTO DATA(entry).
      IF line_exists( catalogs[ table_line = entry-catalog ] ).
        APPEND entry TO result.
      ENDIF.
    ENDLOOP.
  ENDMETHOD.
  METHOD zif_accx_fiori_repo~get_app_services.
    result = VALUE #( ( name = `/Z/ACTIVE_SRV` version = `0001` active = abap_true
                        hashes = VALUE #( ( object = `IWSG` hash = 'HA1' ) ( object = `IWSV` hash = 'HA2' ) ) )
                      ( name = `/Z/OFF_SRV` version = `0001` active = abap_false
                        hashes = VALUE #( ( object = `IWSG` hash = 'HOFF' ) ) ) ).
    CASE component.
      WHEN `z.sales`.
        DELETE result WHERE name = `/Z/OFF_SRV`.
      WHEN `z.v4`.
        " OData V4: started with S_START for the service group
        result = VALUE #( ( name = `/Z/V4_SRV` version = `0001` active = abap_undefined
                            hashes = VALUE #( ( object = `G4BA` hash = 'HG4' obj_name = `ZV4_GROUP` ) ) ) ).
    ENDCASE.
  ENDMETHOD.
ENDCLASS.

"! OK: R_FIORI and R_REP active, all granted; NOROLE: no roles; EXPIR: R_FIORI expired; LOCKED: R_FIORI and R_REP,
"! locked; OWNER: only R_OWN (no catalog)
CLASS ltd_user_repo DEFINITION FINAL FOR TESTING.
  PUBLIC SECTION.
    INTERFACES zif_accx_user_repo PARTIALLY IMPLEMENTED.
ENDCLASS.

CLASS ltd_user_repo IMPLEMENTATION.
  METHOD zif_accx_user_repo~exists.
    result = xsdbool( user <> 'NOBODY' ).
  ENDMETHOD.
  METHOD zif_accx_user_repo~get_user.
    result = VALUE #( user = user user_group = `TEST` locked = xsdbool( user = 'LOCKED' ) lock_reasons = `administrator` ).
  ENDMETHOD.
  METHOD zif_accx_user_repo~get_role_assignments.
    CASE user.
      WHEN 'OK' OR 'LOCKED'.
        result = VALUE #( ( role = 'R_FIORI' active = abap_true ) ( role = 'R_REP' active = abap_true ) ).
      WHEN 'EXPIR'.
        result = VALUE #( ( role = 'R_FIORI' valid_from = '20250101' valid_to = '20260101' active = abap_false ) ).
      WHEN 'OWNER'.
        result = VALUE #( ( role = 'R_OWN' active = abap_true ) ).
    ENDCASE.
  ENDMETHOD.
ENDCLASS.

"! R_FIORI grants S_SERVICE SRV_NAME HA1 (HA* if all_services is set) and is a composite role if composite is set
CLASS ltd_role_repo DEFINITION FINAL FOR TESTING.
  PUBLIC SECTION.
    INTERFACES zif_accx_role_repo PARTIALLY IMPLEMENTED.
    CLASS-DATA all_services TYPE abap_bool.
    CLASS-DATA composite    TYPE abap_bool.
ENDCLASS.

CLASS ltd_role_repo IMPLEMENTATION.
  METHOD zif_accx_role_repo~count_holders.
    result = SWITCH #( role WHEN 'R_FIORI' THEN 2 ELSE 0 ).
  ENDMETHOD.
  METHOD zif_accx_role_repo~count_assigned_users.
    result = VALUE #( ( role = 'R_FIORI' users = 5 ) ).
  ENDMETHOD.
  METHOD zif_accx_role_repo~get_role_info.
    result = VALUE #( role = role generated = abap_true composite = xsdbool( role = 'R_FIORI' AND composite = abap_true ) ).
  ENDMETHOD.
  METHOD zif_accx_role_repo~get_authorization_values.
    IF role = 'R_FIORI'.
      result = VALUE #( ( object = 'S_SERVICE' auth = 'S1' field = 'SRV_NAME'
                          low = COND #( WHEN all_services = abap_true THEN 'HA*' ELSE 'HA1' ) )
                        ( object = 'S_SERVICE' auth = 'S1' field = 'SRV_TYPE' low = 'HT' ) ).
    ENDIF.
  ENDMETHOD.
ENDCLASS.

"! R_FIORI meets the high rule ADMIN if fiori_critical is set; no other role is critical
CLASS ltd_critical DEFINITION FINAL FOR TESTING.
  PUBLIC SECTION.
    INTERFACES zif_accx_critical_rules PARTIALLY IMPLEMENTED.
    CLASS-DATA fiori_critical TYPE abap_bool.
ENDCLASS.

CLASS ltd_critical IMPLEMENTATION.
  METHOD zif_accx_critical_rules~evaluate_role.
    IF role = 'R_FIORI' AND fiori_critical = abap_true.
      result = VALUE #( ( rule = 'ADMIN' text = `Admin functions` level = zif_accx_critical_rules=>co_level-high ) ).
    ENDIF.
  ENDMETHOD.
ENDCLASS.

"! Users OK and LOCKED hold everything except HA2 and S_START for LOCKED; others nothing
CLASS ltd_evaluator DEFINITION FINAL FOR TESTING.
  PUBLIC SECTION.
    INTERFACES zif_accx_auth_evaluator PARTIALLY IMPLEMENTED.
    DATA last_check TYPE zif_accx_auth_evaluator=>ty_check.
ENDCLASS.

CLASS ltd_evaluator IMPLEMENTATION.
  METHOD zif_accx_auth_evaluator~get_transaction_checks.
    result = VALUE #( ( object = 'S_TCODE' fields = VALUE #( ( field = 'TCD' value = tcode ) ) reason = `start` ) ).
  ENDMETHOD.
  METHOD zif_accx_auth_evaluator~simulate.
    last_check = check.
    DATA(granted) = xsdbool( user = 'OK'
                             OR ( user = 'LOCKED' AND NOT line_exists( check-fields[ value = `HA2` ] )
                                  AND NOT line_exists( check-fields[ value = `G4BA` ] ) ) ).
    result = VALUE #( object    = check-object
                      condition = concat_lines_of( table = VALUE string_table( FOR f IN check-fields ( |{ f-field }={ f-value }| ) )
                                                   sep = `, ` )
                      granted   = granted
                      outcome   = COND #( WHEN granted = abap_true THEN `granted` ELSE `missing` )
                      fields    = check-fields ).
  ENDMETHOD.
ENDCLASS.

CLASS ltd_guard DEFINITION FINAL FOR TESTING.
  PUBLIC SECTION.
    INTERFACES zif_accx_caller_guard.
ENDCLASS.

CLASS ltd_guard IMPLEMENTATION.
  METHOD zif_accx_caller_guard~can_display_user.
    result = xsdbool( user <> 'SECRET' ).
  ENDMETHOD.
  METHOD zif_accx_caller_guard~can_display_role.
    result = xsdbool( role <> 'R_HIDDEN' ).
  ENDMETHOD.
  METHOD zif_accx_caller_guard~can_display_profile.
    result = abap_true.
  ENDMETHOD.
  METHOD zif_accx_caller_guard~can_display_authorization.
    result = abap_true.
  ENDMETHOD.
ENDCLASS.

CLASS ltc_diagnose_fiori_app DEFINITION FINAL FOR TESTING
  DURATION SHORT RISK LEVEL HARMLESS.

  PRIVATE SECTION.
    DATA cut       TYPE REF TO zif_accx_tool.
    DATA ctx       TYPE REF TO zif_accx_context.
    DATA evaluator TYPE REF TO ltd_evaluator.

    METHODS setup.
    METHODS teardown.
    METHODS run
      IMPORTING !user    TYPE string
                !app     TYPE string
      EXPORTING !result  TYPE zif_accx_types=>ty_result
                !payload TYPE zcl_accx_t_diagnose_fiori_app=>ty_payload
      RAISING   zcx_accx_error.
    METHODS state_of
      IMPORTING !payload      TYPE zcl_accx_t_diagnose_fiori_app=>ty_payload
                !step         TYPE string
      RETURNING VALUE(result) TYPE string.

    METHODS launchable_ui5_app          FOR TESTING RAISING zcx_accx_error.
    METHODS catalog_and_service_missing FOR TESTING RAISING zcx_accx_error.
    METHODS catalog_to_own_role         FOR TESTING RAISING zcx_accx_error.
    METHODS services_to_catalog_role    FOR TESTING RAISING zcx_accx_error.
    METHODS request_closes_service_gap  FOR TESTING RAISING zcx_accx_error.
    METHODS odata_v4_needs_s_start      FOR TESTING RAISING zcx_accx_error.
    METHODS expired_assignment          FOR TESTING RAISING zcx_accx_error.
    METHODS gui_start_and_locked_user   FOR TESTING RAISING zcx_accx_error.
    METHODS broken_wda_mapping          FOR TESTING RAISING zcx_accx_error.
    METHODS ambiguous_title             FOR TESTING RAISING zcx_accx_error.
    METHODS unknown_app_and_user        FOR TESTING RAISING zcx_accx_error.
    METHODS critical_catalog_role       FOR TESTING RAISING zcx_accx_error.
    METHODS critical_renewal_and_draft  FOR TESTING RAISING zcx_accx_error.
ENDCLASS.

CLASS ltc_diagnose_fiori_app IMPLEMENTATION.

  METHOD setup.
    evaluator = NEW ltd_evaluator( ).
    zcl_accx_domain_factory=>inject( fiori_repo     = NEW ltd_fiori( )
                                     user_repo      = NEW ltd_user_repo( )
                                     role_repo      = NEW ltd_role_repo( )
                                     auth_evaluator = evaluator
                                     critical_rules = NEW ltd_critical( ) ).
    cut = NEW zcl_accx_t_diagnose_fiori_app( ).
    ctx = NEW zcl_accx_context( profile  = `test/unit`
                                max_rows = 50
                                guard    = NEW ltd_guard( )
                                privacy  = NEW zcl_accx_privacy_none( ) ).
  ENDMETHOD.

  METHOD teardown.
    zcl_accx_domain_factory=>reset( ).
    ltd_role_repo=>all_services = abap_false.
    ltd_role_repo=>composite = abap_false.
    ltd_fiori=>alternative = abap_false.
    ltd_critical=>fiori_critical = abap_false.
  ENDMETHOD.

  METHOD run.
    FIELD-SYMBOLS <payload> TYPE zcl_accx_t_diagnose_fiori_app=>ty_payload.
    DATA(args) = NEW zcl_accx_args_map( ).
    args->set( name = `user` value = user ).
    args->set( name = `app` value = app ).
    result = cut->execute( args = args ctx = ctx ).
    cut->render_summary( EXPORTING ctx = ctx CHANGING result = result ).
    ASSIGN result-data->* TO <payload>.
    payload = <payload>.
  ENDMETHOD.

  METHOD state_of.
    LOOP AT payload-steps INTO DATA(entry) WHERE step = step.
      " a problem wins over other states of the same step
      IF result IS INITIAL OR entry-state = zcl_accx_t_diagnose_fiori_app=>co_state-problem.
        result = entry-state.
      ENDIF.
    ENDLOOP.
  ENDMETHOD.

  METHOD launchable_ui5_app.
    run( EXPORTING user = `ok` app = `F0001` IMPORTING result = DATA(result) payload = DATA(payload) ).
    cl_abap_unit_assert=>assert_true( payload-launchable ).
    cl_abap_unit_assert=>assert_equals( exp = `Sales-display` act = payload-intent ).
    cl_abap_unit_assert=>assert_equals( exp = `R_FIORI (C_SALES)` act = payload-entitled_by[ 1 ] ).
    cl_abap_unit_assert=>assert_equals( exp = 2 act = lines( payload-services ) ).
    cl_abap_unit_assert=>assert_equals( exp = 'S_SERVICE' act = evaluator->last_check-object ).
    cl_abap_unit_assert=>assert_char_cp( exp = `User **OK** can find and start **Display Sales** (Sales-display)*`
                                         act = result-summary ).
    cl_abap_unit_assert=>assert_char_cp( exp = `*OK (start): S_SERVICE granted for all 2 service checks.*` act = result-summary ).
    cl_abap_unit_assert=>assert_initial( result-warnings ).
    cl_abap_unit_assert=>assert_initial( payload-draft_arguments ).
  ENDMETHOD.

  METHOD catalog_and_service_missing.
    run( EXPORTING user = `NOROLE` app = `Sales-change` IMPORTING result = DATA(result) payload = DATA(payload) ).
    cl_abap_unit_assert=>assert_false( payload-launchable ).
    cl_abap_unit_assert=>assert_equals( exp = zcl_accx_t_diagnose_fiori_app=>co_state-problem
                                        act = state_of( payload = payload step = `catalog` ) ).
    " hidden role counted, visible one proposed with colleagues and users
    cl_abap_unit_assert=>assert_equals( exp = 1 act = lines( payload-granting_roles ) ).
    cl_abap_unit_assert=>assert_equals( exp = 2 act = payload-granting_roles[ 1 ]-peers ).
    cl_abap_unit_assert=>assert_equals( exp = 5 act = payload-granting_roles[ 1 ]-assigned_users ).
    cl_abap_unit_assert=>assert_equals( exp = 1 act = result-hidden_by_authorization ).
    cl_abap_unit_assert=>assert_char_cp( exp = `*R_FIORI (catalog C_SALES): 2 colleagues, 5 users in total, no critical authorizations*`
                                         act = result-summary ).
    " inactive service and missing S_SERVICE
    cl_abap_unit_assert=>assert_char_cp( exp = `*/Z/OFF_SRV (version 0001) is not activated*` act = result-summary ).
    cl_abap_unit_assert=>assert_char_cp( exp = `*S_SERVICE is missing for 3 of 3 service checks*` act = result-summary ).
    " the proposed catalog role is handed over to assign_role
    cl_abap_unit_assert=>assert_char_cp( exp = `{"user":"NOROLE","role":"R_FIORI","reason":"Fiori app * is in catalog C_SALES,*`
                                         act = payload-assign_arguments ).
    cl_abap_unit_assert=>assert_char_cp( exp = `Request role R_FIORI (catalog C_SALES, held by 2 colleagues*; once approved, ` &&
                                               `with write access (plugin ADMIN): assign_role {"user":"NOROLE"*}. Or add catalog C_SALES*`
                                         act = result-next_steps[ 1 ] ).
    cl_abap_unit_assert=>assert_true( xsdbool( line_exists( result-next_steps[ table_line = `Activate /Z/OFF_SRV in /IWFND/MAINT_SERVICE.` ] ) ) ).
    " all three values are named; the user has no own role to take the catalog
    cl_abap_unit_assert=>assert_equals( exp = 4 act = lines( payload-service_values ) ).
    cl_abap_unit_assert=>assert_initial( payload-draft_role ).
    cl_abap_unit_assert=>assert_char_cp( exp = `*explain_missing_access*S_SERVICE*SRV_NAME=HA1, SRV_TYPE=HT (one value per call; the app needs all 3)*`
                                         act = result-next_steps[ lines( result-next_steps ) ] ).
    cl_abap_unit_assert=>assert_char_cp( exp = `*SU53 buffer*` act = result-warnings[ 1 ] ).
  ENDMETHOD.

  METHOD catalog_to_own_role.
    run( EXPORTING user = `OWNER` app = `Sales-display` IMPORTING result = DATA(result) payload = DATA(payload) ).
    " R_FIORI would bring the catalog but grants only HA1: the catalog goes into the user's own role
    cl_abap_unit_assert=>assert_equals( exp = `R_OWN` act = payload-draft_role ).
    cl_abap_unit_assert=>assert_equals( exp = `C_SALES` act = payload-draft_catalog ).
    cl_abap_unit_assert=>assert_char_cp( exp = `{"role":"R_OWN","add_catalogs":["C_SALES"],"for_user":"OWNER",*`
                                         act = payload-draft_arguments ).
    cl_abap_unit_assert=>assert_char_cp( exp = `Or plan adding catalog C_SALES to the user's role R_OWN*including this app's services*`
                                         act = result-next_steps[ lines( result-next_steps ) - 1 ] ).
    cl_abap_unit_assert=>assert_char_cp( exp = `To look for existing roles instead*` act = result-next_steps[ lines( result-next_steps ) ] ).
    cl_abap_unit_assert=>assert_char_cp( exp = `*Role change instead of a new role:** add catalog **C_SALES** to role **R_OWN***`
                                         act = result-summary ).
  ENDMETHOD.

  METHOD services_to_catalog_role.
    run( EXPORTING user = `LOCKED` app = `Sales-display` IMPORTING result = DATA(result) payload = DATA(payload) ).
    " the catalog comes with R_FIORI, the backend service value is missing: R_FIORI is to be extended
    cl_abap_unit_assert=>assert_equals( exp = `R_FIORI` act = payload-draft_role ).
    cl_abap_unit_assert=>assert_initial( payload-draft_catalog ).
    cl_abap_unit_assert=>assert_char_cp( exp = `*brings the app's catalog*` act = payload-draft_reason ).
    cl_abap_unit_assert=>assert_char_cp( exp = `{"role":"R_FIORI","object":"S_SERVICE","values":["SRV_NAME=HA2","SRV_TYPE=HT"],*`
                                         act = payload-draft_arguments ).
    cl_abap_unit_assert=>assert_char_cp( exp = `*Services:** add all 1 missing S_SERVICE values to role **R_FIORI***`
                                         act = result-summary ).

    " a composite role has no authorizations of its own: the user's own single role instead
    ltd_role_repo=>composite = abap_true.
    run( EXPORTING user = `LOCKED` app = `Sales-display` IMPORTING payload = payload ).
    cl_abap_unit_assert=>assert_equals( exp = `R_REP` act = payload-draft_role ).
    cl_abap_unit_assert=>assert_char_cp( exp = `one of the user's own roles, held by 0 colleagues*` act = payload-draft_reason ).
  ENDMETHOD.

  METHOD request_closes_service_gap.
    ltd_role_repo=>all_services = abap_true.
    run( EXPORTING user = `NOROLE` app = `Sales-display` IMPORTING result = DATA(result) payload = DATA(payload) ).
    " the role bringing the catalog grants HA1 and HA2 (HA*): requesting it is enough
    cl_abap_unit_assert=>assert_initial( payload-draft_role ).
    cl_abap_unit_assert=>assert_equals( exp = 3 act = lines( payload-service_values ) ).
    cl_abap_unit_assert=>assert_char_cp( exp = `Role R_FIORI also grants all 2 missing S_SERVICE values*`
                                         act = result-next_steps[ lines( result-next_steps ) ] ).
  ENDMETHOD.

  METHOD odata_v4_needs_s_start.
    run( EXPORTING user = `LOCKED` app = `Group-show` IMPORTING result = DATA(result) payload = DATA(payload) ).
    " the service group is checked with S_START, not with S_SERVICE, and is not handed over as S_SERVICE value
    cl_abap_unit_assert=>assert_equals( exp = 'S_START' act = evaluator->last_check-object ).
    cl_abap_unit_assert=>assert_equals( exp = `ZV4_GROUP` act = evaluator->last_check-fields[ field = 'AUTHOBJNAM' ]-value ).
    cl_abap_unit_assert=>assert_char_cp( exp = `*S_SERVICE or S_START (OData V4) is missing for 1 of 1 service checks: /Z/V4_SRV (G4BA ZV4_GROUP)*`
                                         act = result-summary ).
    cl_abap_unit_assert=>assert_initial( payload-service_values ).
    cl_abap_unit_assert=>assert_char_cp( exp = `*target S_START, values AUTHPGMID=R3TR, AUTHOBJTYP=G4BA, AUTHOBJNAM=ZV4_GROUP*`
                                         act = result-next_steps[ 1 ] ).
  ENDMETHOD.

  METHOD expired_assignment.
    run( EXPORTING user = `EXPIR` app = `Sales-display` IMPORTING result = DATA(result) payload = DATA(payload) ).
    cl_abap_unit_assert=>assert_initial( payload-entitled_by ).
    cl_abap_unit_assert=>assert_true( payload-assignment_expired ).
    cl_abap_unit_assert=>assert_char_cp( exp = `*through R_FIORI (C_SALES) - assignment expired on 2026-01-01*`
                                         act = result-summary ).
    " the direct assignment is renewed with assign_role
    cl_abap_unit_assert=>assert_char_cp( exp = `{"user":"EXPIR","role":"R_FIORI","reason":"Fiori app *: renew role R_FIORI,*`
                                         act = payload-assign_arguments ).
    cl_abap_unit_assert=>assert_char_cp( exp = `Extend the role assignment*; once approved*assign_role {"user":"EXPIR"*`
                                         act = result-next_steps[ 1 ] ).
    cl_abap_unit_assert=>assert_initial( payload-renew_critical ).
    " renewing is the fix: no role change proposed
    cl_abap_unit_assert=>assert_initial( payload-draft_arguments ).
  ENDMETHOD.

  METHOD gui_start_and_locked_user.
    run( EXPORTING user = `LOCKED` app = `Report-run` IMPORTING result = DATA(result) payload = DATA(payload) ).
    " entitled and authorized, but locked
    cl_abap_unit_assert=>assert_equals( exp = `ok` act = state_of( payload = payload step = `start` ) ).
    cl_abap_unit_assert=>assert_equals( exp = 'TCD' act = evaluator->last_check-fields[ 1 ]-field ).
    cl_abap_unit_assert=>assert_false( payload-launchable ).
    cl_abap_unit_assert=>assert_char_cp( exp = `*LOCKED cannot log on: locked: administrator*` act = result-summary ).

    run( EXPORTING user = `NOROLE` app = `Report-run` IMPORTING result = result payload = payload ).
    cl_abap_unit_assert=>assert_char_cp( exp = `*Start authorization for ZREP missing: S_TCODE (TCD=ZREP)*` act = result-summary ).
    cl_abap_unit_assert=>assert_char_cp( exp = `Run explain_missing_access for NOROLE with transaction ZREP.`
                                         act = result-next_steps[ 2 ] ).
  ENDMETHOD.

  METHOD broken_wda_mapping.
    run( EXPORTING user = `OK` app = `Wda-start` IMPORTING result = DATA(result) payload = DATA(payload) ).
    cl_abap_unit_assert=>assert_equals( exp = zcl_accx_t_diagnose_fiori_app=>co_state-problem
                                        act = state_of( payload = payload step = `content` ) ).
    cl_abap_unit_assert=>assert_char_cp( exp = `*broken in every catalog: reference lost*` act = result-summary ).
    cl_abap_unit_assert=>assert_equals( exp = 'S_START' act = evaluator->last_check-object ).
    cl_abap_unit_assert=>assert_equals( exp = `ZWDA` act = evaluator->last_check-fields[ field = 'AUTHOBJNAM' ]-value ).
  ENDMETHOD.

  METHOD ambiguous_title.
    run( EXPORTING user = `OK` app = `Sales` IMPORTING result = DATA(result) payload = DATA(payload) ).
    cl_abap_unit_assert=>assert_equals( exp = 2 act = lines( payload-matches ) ).
    cl_abap_unit_assert=>assert_initial( payload-intent ).
    cl_abap_unit_assert=>assert_char_cp( exp = `**2 apps** match "Sales"*- Sales-display - Display Sales (UI5)*` act = result-summary ).
  ENDMETHOD.

  METHOD unknown_app_and_user.
    run( EXPORTING user = `OK` app = `Nope-none` IMPORTING result = DATA(result) payload = DATA(payload) ).
    cl_abap_unit_assert=>assert_false( payload-launchable ).
    cl_abap_unit_assert=>assert_char_cp( exp = `*No launchpad catalog contains a target mapping for "Nope-none"*` act = result-summary ).
    TRY.
        run( user = `NOBODY` app = `Sales-display` ).
        cl_abap_unit_assert=>fail( `not_found expected` ).
      CATCH zcx_accx_error INTO DATA(error).
        cl_abap_unit_assert=>assert_equals( exp = zif_accx_types=>co_status-not_found act = error->status ).
    ENDTRY.
    TRY.
        run( user = `SECRET` app = `Sales-display` ).
        cl_abap_unit_assert=>fail( `denied expected` ).
      CATCH zcx_accx_error INTO error.
        cl_abap_unit_assert=>assert_equals( exp = zif_accx_types=>co_status-denied act = error->status ).
    ENDTRY.
  ENDMETHOD.

  METHOD critical_catalog_role.
    ltd_critical=>fiori_critical = abap_true.
    ltd_fiori=>alternative = abap_true.
    run( EXPORTING user = `NOROLE` app = `Sales-change` IMPORTING result = DATA(result) payload = DATA(payload) ).
    " practice in the user group first: R_FIORI stays proposed, the uncritical R_SAFE is the alternative
    cl_abap_unit_assert=>assert_equals( exp = `R_FIORI` act = payload-granting_roles[ 1 ]-role ).
    cl_abap_unit_assert=>assert_equals( exp = 100 act = payload-granting_roles[ 1 ]-critical_score ).
    cl_abap_unit_assert=>assert_equals( exp = `R_SAFE` act = payload-granting_roles[ 2 ]-role ).
    cl_abap_unit_assert=>assert_equals( exp = `R_SAFE` act = payload-less_critical_option ).
    cl_abap_unit_assert=>assert_char_cp( exp = `The proposed role R_FIORI grants critical authorizations: Admin functions (ADMIN, high).`
                                         act = result-warnings[ 1 ] ).
    cl_abap_unit_assert=>assert_char_cp( exp = `Request role R_FIORI*assign_role {"user":"NOROLE","role":"R_FIORI"*} ` &&
                                               `(refused for the critical authorizations unless accept_critical is set). Or add*`
                                         act = result-next_steps[ 1 ] ).
    cl_abap_unit_assert=>assert_char_cp( exp = `If the critical authorizations of R_FIORI are not acceptable, request the less critical role R_SAFE*`
                                         act = result-next_steps[ 2 ] ).
    cl_abap_unit_assert=>assert_char_cp( exp = `*R_FIORI (catalog C_SALES): 2 colleagues*critical:** Admin functions (ADMIN, high)*` &&
                                               `R_SAFE (catalog C_SALES): 0 colleagues*no critical authorizations*` &&
                                               `Less critical alternative:** role **R_SAFE***`
                                         act = result-summary ).

    " uncritical: the order by colleagues is kept and no alternative is named
    ltd_critical=>fiori_critical = abap_false.
    run( EXPORTING user = `NOROLE` app = `Sales-change` IMPORTING payload = payload ).
    cl_abap_unit_assert=>assert_equals( exp = `R_FIORI` act = payload-granting_roles[ 1 ]-role ).
    cl_abap_unit_assert=>assert_initial( payload-less_critical_option ).
  ENDMETHOD.

  METHOD critical_renewal_and_draft.
    ltd_critical=>fiori_critical = abap_true.
    " renewing a critical role is flagged
    run( EXPORTING user = `EXPIR` app = `Sales-display` IMPORTING result = DATA(result) payload = DATA(payload) ).
    cl_abap_unit_assert=>assert_equals( exp = `Admin functions (ADMIN, high)` act = payload-renew_critical ).
    cl_abap_unit_assert=>assert_char_cp( exp = `Renewing role R_FIORI gives EXPIR critical authorizations again*`
                                         act = result-warnings[ 1 ] ).
    cl_abap_unit_assert=>assert_char_cp( exp = `Extend the role assignment*unless accept_critical is set).`
                                         act = result-next_steps[ 1 ] ).
    cl_abap_unit_assert=>assert_char_cp( exp = `*Renewing the expired role gives critical authorizations again:** Admin functions*`
                                         act = result-summary ).

    " the catalog in the user's own role is the way around the critical catalog role
    run( EXPORTING user = `OWNER` app = `Sales-display` IMPORTING result = result payload = payload ).
    cl_abap_unit_assert=>assert_initial( payload-less_critical_option ).
    cl_abap_unit_assert=>assert_char_cp( exp = `To avoid the critical authorizations of R_FIORI, plan adding catalog C_SALES to ` &&
                                               `the user's role R_OWN*(draft_role_change rates their criticality): draft_role_change*`
                                         act = result-next_steps[ lines( result-next_steps ) - 1 ] ).
  ENDMETHOD.

ENDCLASS.
