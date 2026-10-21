"! ZR: single role, menu SM37 + ST22, 3 users, in composite ZC; ZDER: derived from ZREF (siblings ZDER, ZDER2);
"! ZC: composite with ZR, 4 users. ZR holds S_TCODE SM37/ST22/SE*, S_ABAPDUMP, S_DEVELOP OBJTYPE=DEBUG ACTVT=03, S_SERVICE H1.
"! ZADD: single role with S_ADMI_FCD, profile not generated, in composite ZCA (ZADD + ZR, 1 user); ZC2: composite.
CLASS ltd_role_repo DEFINITION FINAL FOR TESTING.
  PUBLIC SECTION.
    INTERFACES zif_accx_role_repo PARTIALLY IMPLEMENTED.
ENDCLASS.

CLASS ltd_role_repo IMPLEMENTATION.
  METHOD zif_accx_role_repo~exists.
    result = xsdbool( role = 'ZR' OR role = 'ZDER' OR role = 'ZREF' OR role = 'ZC' OR role = 'ZADD' OR role = 'ZC2' OR role = 'ZCA' ).
  ENDMETHOD.
  METHOD zif_accx_role_repo~get_role_info.
    result = VALUE #( role = role description = |Role { role }| ).
    CASE role.
      WHEN 'ZR'.
        result-parents   = VALUE #( ( `ZC` ) ( `ZCA` ) ).
        result-generated = abap_true.
      WHEN 'ZADD'.
        result-parents = VALUE #( ( `ZCA` ) ).
      WHEN 'ZC2'.
        result-composite = abap_true.
      WHEN 'ZCA'.
        result-composite = abap_true.
        result-children  = VALUE #( ( `ZADD` ) ( `ZR` ) ).
      WHEN 'ZDER'.
        result-derived_from = 'ZREF'.
      WHEN 'ZC'.
        result-composite = abap_true.
        result-children  = VALUE #( ( `ZR` ) ).
    ENDCASE.
  ENDMETHOD.
  METHOD zif_accx_role_repo~get_transactions.
    result = VALUE #( ( `SM37` ) ( `ST22` ) ).
  ENDMETHOD.
  METHOD zif_accx_role_repo~get_authorization_values.
    IF role = 'ZADD'.
      result = VALUE #( ( object = 'S_ADMI_FCD' auth = 'A1' field = 'S_ADMI_FCD' low = 'ST0R' ) ).
      RETURN.
    ENDIF.
    result = VALUE #( ( object = 'S_TCODE' auth = 'T1' field = 'TCD' low = 'SM37' )
                      ( object = 'S_TCODE' auth = 'T1' field = 'TCD' low = 'ST22' )
                      ( object = 'S_TCODE' auth = 'T1' field = 'TCD' low = 'SE*' )
                      ( object = 'S_ABAPDUMP' auth = 'D1' field = 'ACTVT' low = '03' )
                      ( object = 'S_DEVELOP' auth = 'V1' field = 'OBJTYPE' low = 'DEBUG' )
                      ( object = 'S_DEVELOP' auth = 'V1' field = 'ACTVT' low = '03' )
                      ( object = 'S_SERVICE' auth = 'S1' field = 'SRV_NAME' low = 'H1' )
                      ( object = 'S_SERVICE' auth = 'S1' field = 'SRV_TYPE' low = 'HT' ) ).
  ENDMETHOD.
  METHOD zif_accx_role_repo~get_derived_roles.
    IF role = 'ZREF'.
      result = VALUE #( ( 'ZDER' ) ( 'ZDER2' ) ).
    ENDIF.
  ENDMETHOD.
  METHOD zif_accx_role_repo~count_assigned_users.
    DATA(all) = VALUE zif_accx_role_repo=>ty_user_counts( ( role = 'ZC' users = 4 ) ( role = 'ZCA' users = 1 ) ( role = 'ZDER' users = 2 )
                                                          ( role = 'ZR' users = 3 ) ( role = 'ZREF' users = 1 ) ).
    LOOP AT all INTO DATA(count).
      IF line_exists( roles[ table_line = count-role ] ).
        INSERT count INTO TABLE result.
      ENDIF.
    ENDLOOP.
  ENDMETHOD.
ENDCLASS.

CLASS ltd_evaluator DEFINITION FINAL FOR TESTING.
  PUBLIC SECTION.
    INTERFACES zif_accx_auth_evaluator PARTIALLY IMPLEMENTED.
ENDCLASS.

CLASS ltd_evaluator IMPLEMENTATION.
  METHOD zif_accx_auth_evaluator~transaction_exists.
    result = xsdbool( tcode <> 'NOPE' ).
  ENDMETHOD.
  METHOD zif_accx_auth_evaluator~object_exists.
    result = abap_true.
  ENDMETHOD.
  METHOD zif_accx_auth_evaluator~get_transaction_checks.
    result = VALUE #( ( object = 'S_TCODE' fields = VALUE #( ( field = 'TCD' value = tcode ) ) reason = `start` ) ).
  ENDMETHOD.
ENDCLASS.

"! SE16: S_TABU_DIS ACTVT=03 + open DICBERCLS, S_ADMI_FCD=ST0R; ST22: S_ABAPDUMP; SM37: S_BTCH_JOB;
"! service hash H2: S_TABU_NAM ACTVT=03
CLASS ltd_proposals DEFINITION FINAL FOR TESTING.
  PUBLIC SECTION.
    INTERFACES zif_accx_proposal_source.
ENDCLASS.

CLASS ltd_proposals IMPLEMENTATION.
  METHOD zif_accx_proposal_source~get_for_transaction.
    CASE tcode.
      WHEN 'SE16'.
        result-objects = VALUE #( ( object = 'S_TABU_DIS' proposed = abap_true ) ( object = 'S_ADMI_FCD' proposed = abap_true ) ).
        result-values  = VALUE #( ( object = 'S_TABU_DIS' field = 'ACTVT' low = '03' )
                                  ( object = 'S_TABU_DIS' field = 'DICBERCLS' )
                                  ( object = 'S_ADMI_FCD' field = 'S_ADMI_FCD' low = 'ST0R' ) ).
      WHEN 'ST22'.
        result-objects = VALUE #( ( object = 'S_ABAPDUMP' proposed = abap_true ) ).
      WHEN 'SM37'.
        result-objects = VALUE #( ( object = 'S_BTCH_JOB' proposed = abap_true ) ).
    ENDCASE.
  ENDMETHOD.
  METHOD zif_accx_proposal_source~get_for_service.
    IF hash = 'H2'.
      result-objects = VALUE #( ( object = 'S_TABU_NAM' proposed = abap_true ) ).
      result-values  = VALUE #( ( object = 'S_TABU_NAM' field = 'ACTVT' low = '03' ) ).
    ENDIF.
  ENDMETHOD.
ENDCLASS.

"! Catalogs: C_ADMIN (5 apps; authorization defaults: transaction SE16, gateway service /Z/SRV_0001 = H1 with
"! backend H2, inactive /Z/OFF_0001 = H3, Web Dynpro ZWDA = HW), C_IN (in the menus of ZR and ZOTHER).
"! Menu of ZR: SM37 directly; below the node of C_IN: ST22, H1 (/Z/SRV_0001) and H2 (backend).
CLASS ltd_fiori DEFINITION FINAL FOR TESTING.
  PUBLIC SECTION.
    INTERFACES zif_accx_fiori_repo PARTIALLY IMPLEMENTED.
ENDCLASS.

CLASS ltd_fiori IMPLEMENTATION.
  METHOD zif_accx_fiori_repo~get_catalog.
    CASE to_upper( catalog ).
      WHEN `C_ADMIN`.
        result = VALUE #( catalog = `C_ADMIN` title = `Admin`
                          apps    = VALUE #( ( intent = `App-display` app_type = `UI5` target = `z.app` consistent = abap_true )
                                             ( intent = `App-change` app_type = `UI5` target = `z.app` consistent = abap_true )
                                             ( intent = `Table-display` app_type = `GUI` target = `SE16` consistent = abap_true )
                                             ( intent = `Wda-start` app_type = `WDA` target = `ZWDA` consistent = abap_true )
                                             ( intent = `Broken-run` app_type = `GUI` target = `SU01` consistent = abap_false ) ) ).
      WHEN `C_IN`.
        result = VALUE #( catalog = `C_IN` title = `Inside` apps = VALUE #( ( intent = `X-y` app_type = `GUI` target = `SM37` ) ) ).
    ENDCASE.
  ENDMETHOD.
  METHOD zif_accx_fiori_repo~get_catalog_defaults.
    IF catalog = `C_ADMIN`.
      result-defaults = VALUE #(
        ( type = `TR` name = `SE16` pgmid = `R3TR` object = `TRAN` obj_name = `SE16` active = abap_undefined )
        ( type = `HT` name = `H1` pgmid = `R3TR` object = `IWSG` obj_name = `/Z/SRV_0001` active = abap_true )
        ( type = `HT` name = `H2` pgmid = `R3TR` object = `IWSV` obj_name = `/Z/SRV 0001` active = abap_undefined )
        ( type = `HT` name = `H3` pgmid = `R3TR` object = `IWSG` obj_name = `/Z/OFF_0001` active = abap_false )
        ( type = `HT` name = `HW` pgmid = `R3TR` object = `WDYA` obj_name = `ZWDA` active = abap_undefined ) ).
    ENDIF.
  ENDMETHOD.
  METHOD zif_accx_fiori_repo~get_role_catalogs.
    IF line_exists( roles[ table_line = 'ZR' ] ).
      result = VALUE #( ( role = 'ZR' catalog = `C_IN` ) ).
    ENDIF.
  ENDMETHOD.
  METHOD zif_accx_fiori_repo~get_catalog_roles.
    IF line_exists( catalogs[ table_line = `C_IN` ] ).
      result = VALUE #( ( role = 'ZOTHER' catalog = `C_IN` ) ( role = 'ZR' catalog = `C_IN` ) ).
    ENDIF.
  ENDMETHOD.
  METHOD zif_accx_fiori_repo~get_role_menu_nodes.
    IF role = 'ZR'.
      result = VALUE #( ( node = `1` type = `TR` name = `SM37` )
                        ( node = `11` catalog = `C_IN` type = `TR` name = `ST22` )
                        ( node = `12` catalog = `C_IN` type = `HT` name = `H1` object = `IWSG` obj_name = `/Z/SRV_0001` )
                        ( node = `13` catalog = `C_IN` type = `HT` name = `H2` object = `IWSV` obj_name = `/Z/SRV 0001` ) ).
    ENDIF.
  ENDMETHOD.
ENDCLASS.

"! ADMIN: any S_ADMI_FCD; DEBUG: OBJTYPE=DEBUG and ACTVT=02 in one authorization; combination COMBO = ADMIN
CLASS ltd_critical DEFINITION FINAL FOR TESTING.
  PUBLIC SECTION.
    INTERFACES zif_accx_critical_rules PARTIALLY IMPLEMENTED.
ENDCLASS.

CLASS ltd_critical IMPLEMENTATION.
  METHOD zif_accx_critical_rules~evaluate.
    IF line_exists( values[ object = 'S_ADMI_FCD' ] ).
      APPEND VALUE #( rule = 'ADMIN' text = `Admin functions` level = zif_accx_critical_rules=>co_level-high ) TO result.
    ENDIF.
    LOOP AT values INTO DATA(value) WHERE object = 'S_DEVELOP' AND field = 'OBJTYPE' AND low = 'DEBUG'.
      IF line_exists( values[ object = 'S_DEVELOP' auth = value-auth field = 'ACTVT' low = '02' ] ).
        APPEND VALUE #( rule = 'DEBUG' text = `Debug replace` level = zif_accx_critical_rules=>co_level-high ) TO result.
        EXIT.
      ENDIF.
    ENDLOOP.
  ENDMETHOD.
  METHOD zif_accx_critical_rules~evaluate_combinations.
    IF line_exists( hits[ rule = 'ADMIN' ] ).
      result = VALUE #( ( rule = 'COMBO' text = `Admin combination` level = zif_accx_critical_rules=>co_level-medium ) ).
    ENDIF.
  ENDMETHOD.
ENDCLASS.

CLASS ltd_user_repo DEFINITION FINAL FOR TESTING.
  PUBLIC SECTION.
    INTERFACES zif_accx_user_repo PARTIALLY IMPLEMENTED.
ENDCLASS.

CLASS ltd_user_repo IMPLEMENTATION.
  METHOD zif_accx_user_repo~exists.
    result = xsdbool( user = 'U1' ).
  ENDMETHOD.
  METHOD zif_accx_user_repo~get_role_assignments.
    result = VALUE #( ( role = 'ZOTHER' active = abap_true ) ).
  ENDMETHOD.
ENDCLASS.

CLASS ltd_guard DEFINITION FINAL FOR TESTING.
  PUBLIC SECTION.
    INTERFACES zif_accx_caller_guard.
ENDCLASS.

CLASS ltd_guard IMPLEMENTATION.
  METHOD zif_accx_caller_guard~can_display_user.
    result = abap_true.
  ENDMETHOD.
  METHOD zif_accx_caller_guard~can_display_role.
    result = abap_true.
  ENDMETHOD.
  METHOD zif_accx_caller_guard~can_display_profile.
    result = abap_true.
  ENDMETHOD.
  METHOD zif_accx_caller_guard~can_display_authorization.
    result = abap_true.
  ENDMETHOD.
ENDCLASS.

CLASS ltc_draft_role_change DEFINITION FINAL FOR TESTING
  DURATION SHORT RISK LEVEL HARMLESS.

  PRIVATE SECTION.
    DATA cut TYPE REF TO zif_accx_tool.
    DATA ctx TYPE REF TO zif_accx_context.

    METHODS setup.
    METHODS teardown.
    METHODS run
      IMPORTING !args    TYPE REF TO zcl_accx_args_map
      EXPORTING !result  TYPE zif_accx_types=>ty_result
                !payload TYPE zcl_accx_t_draft_role_change=>ty_payload
      RAISING   zcx_accx_error.
    METHODS status_of
      IMPORTING !payload      TYPE zcl_accx_t_draft_role_change=>ty_payload
                !object       TYPE string
                !field        TYPE string
      RETURNING VALUE(result) TYPE string.

    METHODS add_transactions_planned   FOR TESTING RAISING zcx_accx_error.
    METHODS derived_role_changes_ref   FOR TESTING RAISING zcx_accx_error.
    METHODS removal_and_review         FOR TESTING RAISING zcx_accx_error.
    METHODS covered_values_count       FOR TESTING RAISING zcx_accx_error.
    METHODS composite_rejected         FOR TESTING.
    METHODS catalogs_planned           FOR TESTING RAISING zcx_accx_error.
    METHODS catalog_removal_planned    FOR TESTING RAISING zcx_accx_error.
    METHODS composite_roles_planned    FOR TESTING RAISING zcx_accx_error.
    METHODS new_role_planned           FOR TESTING RAISING zcx_accx_error.
    METHODS new_role_refused           FOR TESTING.
    "! Expects the draft to be refused as invalid with a message matching the pattern
    METHODS assert_invalid
      IMPORTING !args    TYPE REF TO zcl_accx_args_map
                !pattern TYPE string.
ENDCLASS.

CLASS ltc_draft_role_change IMPLEMENTATION.

  METHOD setup.
    zcl_accx_domain_factory=>inject( role_repo       = NEW ltd_role_repo( )
                                     auth_evaluator  = NEW ltd_evaluator( )
                                     proposal_source = NEW ltd_proposals( )
                                     critical_rules  = NEW ltd_critical( )
                                     user_repo       = NEW ltd_user_repo( )
                                     fiori_repo      = NEW ltd_fiori( ) ).
    cut = NEW zcl_accx_t_draft_role_change( ).
    ctx = NEW zcl_accx_context( profile  = `test/unit`
                                max_rows = 50
                                guard    = NEW ltd_guard( )
                                privacy  = NEW zcl_accx_privacy_none( ) ).
  ENDMETHOD.

  METHOD teardown.
    zcl_accx_domain_factory=>reset( ).
  ENDMETHOD.

  METHOD run.
    FIELD-SYMBOLS <payload> TYPE zcl_accx_t_draft_role_change=>ty_payload.
    result = cut->execute( args = args ctx = ctx ).
    cut->render_summary( EXPORTING ctx = ctx CHANGING result = result ).
    ASSIGN result-data->* TO <payload>.
    payload = <payload>.
  ENDMETHOD.

  METHOD status_of.
    result = VALUE #( payload-authorization_values[ object = object field = field ]-status OPTIONAL ).
  ENDMETHOD.

  METHOD add_transactions_planned.
    DATA(args) = NEW zcl_accx_args_map( ).
    args->set( name = `role` value = `zr` ).
    args->set_list( name = `add_transactions` values = VALUE #( ( `se16` ) ( `SM37` ) ( `NOPE` ) ) ).
    args->set( name = `for_user` value = `U1` ).
    args->set( name = `reason` value = `Table display` ).
    run( EXPORTING args = args IMPORTING result = DATA(result) payload = DATA(payload) ).

    cl_abap_unit_assert=>assert_equals( exp = `add` act = payload-transactions[ transaction = `SE16` ]-status ).
    cl_abap_unit_assert=>assert_equals( exp = `already_in_role` act = payload-transactions[ transaction = `SM37` ]-status ).
    cl_abap_unit_assert=>assert_equals( exp = `unknown` act = payload-transactions[ transaction = `NOPE` ]-status ).
    " SE16 is allowed by SE* already, but the menu entry still brings its proposals
    cl_abap_unit_assert=>assert_char_cp( exp = `*range or pattern*` act = payload-transactions[ transaction = `SE16` ]-note ).
    cl_abap_unit_assert=>assert_equals( exp = `covered` act = status_of( payload = payload object = `S_TCODE` field = `TCD` ) ).
    cl_abap_unit_assert=>assert_equals( exp = `add` act = status_of( payload = payload object = `S_TABU_DIS` field = `ACTVT` ) ).
    cl_abap_unit_assert=>assert_equals( exp = `open` act = status_of( payload = payload object = `S_TABU_DIS` field = `DICBERCLS` ) ).
    " critical authorization and the combination it completes
    cl_abap_unit_assert=>assert_equals( exp = 2 act = lines( payload-critical_added ) ).
    cl_abap_unit_assert=>assert_equals( exp = 'COMBO' act = payload-critical_added[ 2 ]-rule ).
    cl_abap_unit_assert=>assert_equals( exp = 3 act = payload-assigned_users ).
    cl_abap_unit_assert=>assert_false( payload-for_user_has_role ).
    cl_abap_unit_assert=>assert_true( xsdbool( line_exists( payload-steps[ table_line = `Assign role ZR to U1 with a validity period; the user does not hold it today.` ] ) ) ).
    cl_abap_unit_assert=>assert_char_cp( exp = `*Maintain the open fields (yellow lights): S_TABU_DIS-DICBERCLS.*` act = result-summary ).
    cl_abap_unit_assert=>assert_char_cp( exp = `*Have the change approved*Admin functions (ADMIN, high)*` act = result-summary ).
    cl_abap_unit_assert=>assert_char_cp( exp = `*Reason: Table display*Critical authorizations added (SUIM): Admin functions (ADMIN, high); Admin combination*`
                                         act = payload-request_text ).
    cl_abap_unit_assert=>assert_char_cp( exp = `*contained in composite roles ZC, ZCA*` act = payload-request_text ).
    cl_abap_unit_assert=>assert_char_cp( exp = `Transaction NOPE does not exist*` act = result-warnings[ 1 ] ).
  ENDMETHOD.

  METHOD derived_role_changes_ref.
    DATA(args) = NEW zcl_accx_args_map( ).
    args->set( name = `role` value = `ZDER` ).
    args->set_list( name = `add_transactions` values = VALUE #( ( `SE16` ) ) ).
    run( EXPORTING args = args IMPORTING result = DATA(result) payload = DATA(payload) ).
    cl_abap_unit_assert=>assert_equals( exp = `ZREF` act = payload-change_target ).
    cl_abap_unit_assert=>assert_equals( exp = 2 act = lines( payload-derived_roles ) ).
    " users of the reference role and its derived roles
    cl_abap_unit_assert=>assert_equals( exp = 3 act = payload-assigned_users ).
    cl_abap_unit_assert=>assert_char_cp( exp = `*change in reference role ZREF*` act = result-summary ).
    cl_abap_unit_assert=>assert_char_cp( exp = `*PFCG ZREF, tab Menu: add transaction SE16*` act = result-summary ).
    cl_abap_unit_assert=>assert_char_cp( exp = `*generate them: ZDER, ZDER2*` act = result-summary ).
    cl_abap_unit_assert=>assert_char_cp( exp = `ZDER is derived from ZREF*` act = result-warnings[ 1 ] ).
  ENDMETHOD.

  METHOD removal_and_review.
    DATA(args) = NEW zcl_accx_args_map( ).
    args->set( name = `role` value = `ZR` ).
    args->set_list( name = `remove_transactions` values = VALUE #( ( `ST22` ) ( `SU01` ) ( `SE38` ) ) ).
    run( EXPORTING args = args IMPORTING result = DATA(result) payload = DATA(payload) ).
    cl_abap_unit_assert=>assert_equals( exp = `remove` act = payload-transactions[ transaction = `ST22` ]-status ).
    cl_abap_unit_assert=>assert_equals( exp = `not_in_role` act = payload-transactions[ transaction = `SU01` ]-status ).
    cl_abap_unit_assert=>assert_equals( exp = `granted_by_value` act = payload-transactions[ transaction = `SE38` ]-status ).
    " S_ABAPDUMP was proposed only by ST22; S_BTCH_JOB of SM37 stays
    cl_abap_unit_assert=>assert_equals( exp = `review` act = status_of( payload = payload object = `S_ABAPDUMP` field = `` ) ).
    cl_abap_unit_assert=>assert_char_cp( exp = `*only ST22 proposed them: S_ABAPDUMP*` act = result-summary ).
    cl_abap_unit_assert=>assert_initial( payload-critical_added ).
  ENDMETHOD.

  METHOD covered_values_count.
    " OBJTYPE=DEBUG is allowed already (with 03), together with 02 the new authorization is critical
    DATA(args) = NEW zcl_accx_args_map( ).
    args->set( name = `role` value = `ZR` ).
    args->set( name = `object` value = `S_DEVELOP` ).
    args->set_list( name = `values` values = VALUE #( ( `OBJTYPE=DEBUG` ) ( `ACTVT=02` ) ) ).
    run( EXPORTING args = args IMPORTING result = DATA(result) payload = DATA(payload) ).
    cl_abap_unit_assert=>assert_equals( exp = `covered` act = status_of( payload = payload object = `S_DEVELOP` field = `OBJTYPE` ) ).
    cl_abap_unit_assert=>assert_equals( exp = `add` act = status_of( payload = payload object = `S_DEVELOP` field = `ACTVT` ) ).
    cl_abap_unit_assert=>assert_equals( exp = 'DEBUG' act = payload-critical_added[ 1 ]-rule ).
    cl_abap_unit_assert=>assert_char_cp( exp = `*Add the authorization manually*S_DEVELOP ACTVT=02*` act = result-summary ).
  ENDMETHOD.

  METHOD composite_rejected.
    DATA(args) = NEW zcl_accx_args_map( ).
    args->set( name = `role` value = `ZC` ).
    args->set_list( name = `add_transactions` values = VALUE #( ( `SE16` ) ) ).
    TRY.
        run( args ).
        cl_abap_unit_assert=>fail( `invalid expected` ).
      CATCH zcx_accx_error INTO DATA(error).
        cl_abap_unit_assert=>assert_equals( exp = zif_accx_types=>co_status-invalid act = error->status ).
        cl_abap_unit_assert=>assert_char_cp( exp = `*composite role*(ZR)*` act = error->message ).
    ENDTRY.
    " single roles are added to composite roles, not to single roles
    args = NEW zcl_accx_args_map( ).
    args->set( name = `role` value = `ZR` ).
    args->set_list( name = `add_roles` values = VALUE #( ( `ZADD` ) ) ).
    TRY.
        run( args ).
        cl_abap_unit_assert=>fail( `invalid expected` ).
      CATCH zcx_accx_error INTO error.
        cl_abap_unit_assert=>assert_char_cp( exp = `*ZR is a single role (contained in ZC, ZCA)*` act = error->message ).
    ENDTRY.
  ENDMETHOD.

  METHOD catalogs_planned.
    DATA(args) = NEW zcl_accx_args_map( ).
    args->set( name = `role` value = `ZR` ).
    args->set_list( name = `add_catalogs` values = VALUE #( ( `c_admin` ) ( `C_IN` ) ( `NOPE` ) ) ).
    run( EXPORTING args = args IMPORTING result = DATA(result) payload = DATA(payload) ).

    cl_abap_unit_assert=>assert_equals( exp = `add` act = payload-catalogs[ catalog = `C_ADMIN` ]-status ).
    cl_abap_unit_assert=>assert_equals( exp = `already_in_role` act = payload-catalogs[ catalog = `C_IN` ]-status ).
    cl_abap_unit_assert=>assert_equals( exp = `unknown` act = payload-catalogs[ catalog = `NOPE` ]-status ).
    DATA(admin) = payload-catalogs[ catalog = `C_ADMIN` ].
    " gateway services counted once, backend part only as value; Web Dynpro via S_START
    cl_abap_unit_assert=>assert_equals( exp = 2 act = lines( admin-services ) ).
    cl_abap_unit_assert=>assert_equals( exp = `/Z/OFF_0001` act = admin-inactive_services[ 1 ] ).
    cl_abap_unit_assert=>assert_equals( exp = `SE16` act = admin-transactions[ 1 ] ).
    cl_abap_unit_assert=>assert_equals( exp = `WDYA ZWDA` act = admin-start_objects[ 1 ] ).
    " H1 is in the role already, H2 and H3 are new; SU24 of the service and of SE16 count as well
    cl_abap_unit_assert=>assert_equals(
      exp = `covered` act = VALUE #( payload-authorization_values[ object = `S_SERVICE` value = `H1` ]-status OPTIONAL ) ).
    cl_abap_unit_assert=>assert_equals(
      exp = `add` act = VALUE #( payload-authorization_values[ object = `S_SERVICE` value = `H2` ]-status OPTIONAL ) ).
    cl_abap_unit_assert=>assert_equals( exp = `add` act = status_of( payload = payload object = `S_TABU_NAM` field = `ACTVT` ) ).
    cl_abap_unit_assert=>assert_equals(
      exp = `add` act = VALUE #( payload-authorization_values[ object = `S_START` value = `ZWDA` ]-status OPTIONAL ) ).
    cl_abap_unit_assert=>assert_equals( exp = 'ADMIN' act = payload-critical_added[ 1 ]-rule ).
    cl_abap_unit_assert=>assert_char_cp( exp = `*add launchpad catalog C_ADMIN (Insert node > Launchpad catalog)*` act = result-summary ).
    cl_abap_unit_assert=>assert_char_cp( exp = `*Activate the OData services /Z/OFF_0001 in /IWFND/MAINT_SERVICE*` act = result-summary ).
    cl_abap_unit_assert=>assert_char_cp(
      exp = `*Catalog C_ADMIN (Admin): 5 apps; authorization defaults: S_SERVICE for 2 OData services, transactions SE16, S_START for WDYA ZWDA; not active: /Z/OFF_0001*`
      act = result-summary ).
    cl_abap_unit_assert=>assert_char_cp( exp = `*Changes: add launchpad catalog C_ADMIN to the menu*OData services to activate: /Z/OFF_0001*`
                                         act = payload-request_text ).
    cl_abap_unit_assert=>assert_char_cp( exp = `Catalog NOPE is left out*` act = result-warnings[ 1 ] ).
  ENDMETHOD.

  METHOD catalog_removal_planned.
    DATA(args) = NEW zcl_accx_args_map( ).
    args->set( name = `role` value = `ZR` ).
    args->set_list( name = `remove_catalogs` values = VALUE #( ( `c_in` ) ( `C_ADMIN` ) ) ).
    run( EXPORTING args = args IMPORTING result = DATA(result) payload = DATA(payload) ).

    DATA(inside) = payload-catalogs[ catalog = `C_IN` ].
    cl_abap_unit_assert=>assert_equals( exp = `remove` act = inside-status ).
    cl_abap_unit_assert=>assert_equals( exp = `Inside` act = inside-title ).
    cl_abap_unit_assert=>assert_equals( exp = VALUE string_table( ( `ZOTHER` ) ) act = inside-other_roles ).
    cl_abap_unit_assert=>assert_equals( exp = VALUE string_table( ( `ST22` ) ) act = inside-transactions ).
    cl_abap_unit_assert=>assert_equals( exp = VALUE string_table( ( `/Z/SRV_0001` ) ) act = inside-services ).
    " C_ADMIN is not in the menu of ZR
    cl_abap_unit_assert=>assert_equals( exp = `not_in_role` act = payload-catalogs[ catalog = `C_ADMIN` ]-status ).
    cl_abap_unit_assert=>assert_char_cp( exp = `Catalog C_ADMIN is left out: the role menu does not contain the catalog*`
                                         act = result-warnings[ 1 ] ).
    " start authorizations only the catalog nodes bring; H2 is not in the role; S_ABAPDUMP was proposed by ST22 only
    cl_abap_unit_assert=>assert_equals(
      exp = `remove` act = VALUE #( payload-authorization_values[ object = `S_TCODE` value = `ST22` ]-status OPTIONAL ) ).
    cl_abap_unit_assert=>assert_equals(
      exp = `remove` act = VALUE #( payload-authorization_values[ object = `S_SERVICE` value = `H1` ]-status OPTIONAL ) ).
    cl_abap_unit_assert=>assert_false( xsdbool( line_exists( payload-authorization_values[ object = `S_SERVICE` value = `H2` ] ) ) ).
    cl_abap_unit_assert=>assert_equals( exp = `review` act = status_of( payload = payload object = `S_ABAPDUMP` field = `` ) ).
    cl_abap_unit_assert=>assert_initial( payload-critical_added ).
    cl_abap_unit_assert=>assert_char_cp( exp = `*0 transactions to add, 0 to remove, 1 catalog to remove; 3 users affected*` act = result-summary ).
    cl_abap_unit_assert=>assert_char_cp( exp = `*Catalog C_IN (Inside): remove (1 apps); nodes below it: S_SERVICE for 1 OData service, transactions ST22; users who also hold ZOTHER keep its apps*`
                                         act = result-summary ).
    cl_abap_unit_assert=>assert_char_cp( exp = `*Start authorizations leaving the role:** S_TCODE TCD=ST22, S_SERVICE SRV_NAME=H1.*` act = result-summary ).
    cl_abap_unit_assert=>assert_char_cp( exp = `*remove launchpad catalog C_IN together with*only C_IN proposed them: S_ABAPDUMP*` act = result-summary ).
    cl_abap_unit_assert=>assert_char_cp( exp = `*Changes: remove launchpad catalog C_IN from the menu*Start authorizations removed: S_TCODE TCD=ST22, S_SERVICE SRV_NAME=H1*Launchpad: C_IN: users who also hold ZOTHER keep its apps*`
                                         act = payload-request_text ).
  ENDMETHOD.

  METHOD composite_roles_planned.
    DATA(args) = NEW zcl_accx_args_map( ).
    args->set( name = `role` value = `zc` ).
    args->set_list( name = `add_roles` values = VALUE #( ( `zadd` ) ( `ZR` ) ( `ZC2` ) ( `NOPE` ) ) ).
    args->set_list( name = `remove_roles` values = VALUE #( ( `ZDER` ) ) ).
    run( EXPORTING args = args IMPORTING result = DATA(result) payload = DATA(payload) ).

    cl_abap_unit_assert=>assert_true( payload-composite ).
    cl_abap_unit_assert=>assert_equals( exp = `add` act = payload-roles[ role = `ZADD` ]-status ).
    cl_abap_unit_assert=>assert_equals( exp = `already_in_role` act = payload-roles[ role = `ZR` ]-status ).
    cl_abap_unit_assert=>assert_equals( exp = `composite` act = payload-roles[ role = `ZC2` ]-status ).
    cl_abap_unit_assert=>assert_equals( exp = `unknown` act = payload-roles[ role = `NOPE` ]-status ).
    cl_abap_unit_assert=>assert_equals( exp = `not_in_role` act = payload-roles[ role = `ZDER` ]-status ).
    cl_abap_unit_assert=>assert_equals( exp = 4 act = payload-assigned_users ).
    " ZADD brings S_ADMI_FCD and with it the combination
    cl_abap_unit_assert=>assert_equals( exp = 2 act = lines( payload-critical_added ) ).
    cl_abap_unit_assert=>assert_initial( payload-critical_removed ).
    cl_abap_unit_assert=>assert_char_cp( exp = `**Draft for composite role ZC**: 1 single role to add, 0 to remove; 4 users affected*`
                                         act = result-summary ).
    cl_abap_unit_assert=>assert_char_cp( exp = `*- ZADD (Role ZADD): add; also in ZCA; its profile is not generated*` act = result-summary ).
    cl_abap_unit_assert=>assert_char_cp( exp = `*PFCG ZC, tab Roles: add the single roles ZADD.*Generate the profile of ZADD*user comparison*4 users of ZC*`
                                         act = result-summary ).
    cl_abap_unit_assert=>assert_char_cp( exp = `*Changes: add single roles ZADD*Critical authorizations added (SUIM): Admin functions (ADMIN, high)*Impact: 4 users*`
                                         act = payload-request_text ).
    cl_abap_unit_assert=>assert_equals( exp = 3 act = lines( result-warnings ) ).

    " removing the only role with S_ADMI_FCD from ZCA
    args = NEW zcl_accx_args_map( ).
    args->set( name = `role` value = `ZCA` ).
    args->set_list( name = `remove_roles` values = VALUE #( ( `ZADD` ) ) ).
    run( EXPORTING args = args IMPORTING result = result payload = payload ).
    cl_abap_unit_assert=>assert_equals( exp = `remove` act = payload-roles[ role = `ZADD` ]-status ).
    cl_abap_unit_assert=>assert_char_cp( exp = `*only if the role is assigned to them directly*` act = payload-roles[ role = `ZADD` ]-note ).
    cl_abap_unit_assert=>assert_initial( payload-critical_added ).
    cl_abap_unit_assert=>assert_equals( exp = 'ADMIN' act = payload-critical_removed[ 1 ]-rule ).
    cl_abap_unit_assert=>assert_char_cp( exp = `*The composite role no longer grants:** Admin functions (ADMIN, high)*` act = result-summary ).
  ENDMETHOD.

  METHOD new_role_planned.
    " copy of ZR with SE16 added: values of ZR count as present, nobody holds the new role
    DATA(args) = NEW zcl_accx_args_map( ).
    args->set( name = `role` value = `znew` ).
    args->set( name = `create` value = `true` ).
    args->set( name = `copy_from` value = `zr` ).
    args->set( name = `description` value = `Table display` ).
    args->set_list( name = `add_transactions` values = VALUE #( ( `SE16` ) ) ).
    run( EXPORTING args = args IMPORTING result = DATA(result) payload = DATA(payload) ).
    cl_abap_unit_assert=>assert_true( payload-create ).
    cl_abap_unit_assert=>assert_equals( exp = `ZR` act = payload-copy_from ).
    cl_abap_unit_assert=>assert_equals( exp = `Table display` act = payload-description ).
    cl_abap_unit_assert=>assert_equals( exp = 0 act = payload-assigned_users ).
    cl_abap_unit_assert=>assert_initial( payload-composite_roles ).
    cl_abap_unit_assert=>assert_equals( exp = `covered` act = status_of( payload = payload object = `S_TCODE` field = `TCD` ) ).
    cl_abap_unit_assert=>assert_equals( exp = `PFCG: copy role ZR to ZNEW without user assignments, description "Table display".`
                                        act = payload-steps[ 1 ] ).
    cl_abap_unit_assert=>assert_false( xsdbool( line_exists( payload-steps[ table_line = `Run the user comparison (PFUD) so that the change reaches the 0 assigned users.` ] ) ) ).
    cl_abap_unit_assert=>assert_char_cp( exp = `Request for new role ZNEW*Copy of: ZR*Changes: create ZNEW as a copy of ZR; add SE16*`
                                         act = payload-request_text ).
    cl_abap_unit_assert=>assert_char_cp( exp = `**Draft for new role ZNEW** (copy of ZR)*` act = result-summary ).
    cl_abap_unit_assert=>assert_char_cp( exp = `*assign it with assign_role*` act = result-next_steps[ 1 ] ).

    " a copy of ZADD gains its critical authorization although nothing is added
    args = NEW zcl_accx_args_map( ).
    args->set( name = `role` value = `ZNEW2` ).
    args->set( name = `create` value = `true` ).
    args->set( name = `copy_from` value = `ZADD` ).
    run( EXPORTING args = args IMPORTING payload = payload ).
    cl_abap_unit_assert=>assert_equals( exp = 2 act = lines( payload-critical_added ) ).
    cl_abap_unit_assert=>assert_equals( exp = 'ADMIN' act = payload-critical_added[ 1 ]-rule ).
    cl_abap_unit_assert=>assert_equals( exp = `Role ZADD` act = payload-description ).

    " an empty new role allows nothing yet
    args = NEW zcl_accx_args_map( ).
    args->set( name = `role` value = `YEMPTY` ).
    args->set( name = `create` value = `true` ).
    args->set_list( name = `add_transactions` values = VALUE #( ( `SE16` ) ) ).
    run( EXPORTING args = args IMPORTING payload = payload ).
    cl_abap_unit_assert=>assert_equals( exp = `add` act = status_of( payload = payload object = `S_TCODE` field = `TCD` ) ).
    cl_abap_unit_assert=>assert_equals( exp = `PFCG: create single role YEMPTY.` act = payload-steps[ 1 ] ).
  ENDMETHOD.

  METHOD new_role_refused.
    DATA(args) = NEW zcl_accx_args_map( ).
    args->set( name = `role` value = `ZR` ).
    args->set( name = `create` value = `true` ).
    args->set_list( name = `add_transactions` values = VALUE #( ( `SE16` ) ) ).
    assert_invalid( args = args pattern = `Role ZR exists already*` ).
    args->set( name = `role` value = `SAP_NEW` ).
    assert_invalid( args = args pattern = `SAP_NEW is no customer role name*` ).
    args->set( name = `role` value = `Z-NEW` ).
    assert_invalid( args = args pattern = `Z-NEW is no customer role name*` ).
    args->set( name = `role` value = `ZNEW` ).
    args->set( name = `copy_from` value = `ZC` ).
    assert_invalid( args = args pattern = `ZC is a composite role*` ).
    args->set( name = `copy_from` value = `ZDER` ).
    assert_invalid( args = args pattern = `*copy the reference role ZREF instead.` ).
    args->set( name = `create` value = `false` ).
    assert_invalid( args = args pattern = `copy_from creates a new role*` ).
    args = NEW zcl_accx_args_map( ).
    args->set( name = `role` value = `ZNEW` ).
    args->set( name = `create` value = `true` ).
    args->set_list( name = `add_roles` values = VALUE #( ( `ZR` ) ) ).
    assert_invalid( args = args pattern = `New roles are single roles*` ).
  ENDMETHOD.

  METHOD assert_invalid.
    TRY.
        run( args ).
        cl_abap_unit_assert=>fail( |invalid expected: { pattern }| ).
      CATCH zcx_accx_error INTO DATA(error).
        cl_abap_unit_assert=>assert_equals( exp = zif_accx_types=>co_status-invalid act = error->status ).
        cl_abap_unit_assert=>assert_char_cp( exp = pattern act = error->message ).
    ENDTRY.
  ENDMETHOD.

ENDCLASS.
