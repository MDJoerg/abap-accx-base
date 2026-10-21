"! F1: SAPUI5 app A-ui5 in C1 (reference lost) and C2; GUI: G-run (SE16) in C3, which no role contains;
"! MANY: 7 Web Dynpro apps in C4. Roles: C1 in R_A, C2 in R_B and R_HIDDEN, C4 in R_A
CLASS ltd_fiori DEFINITION FINAL FOR TESTING.
  PUBLIC SECTION.
    INTERFACES zif_accx_fiori_repo PARTIALLY IMPLEMENTED.
ENDCLASS.

CLASS ltd_fiori IMPLEMENTATION.
  METHOD zif_accx_fiori_repo~find_apps.
    CASE query.
      WHEN `F1`.
        result = VALUE #( app_type = zif_accx_fiori_repo=>co_app_type-ui5 intent = `A-ui5` target = `z.app` fiori_ids = `F1`
                          ( catalog = `C1` title = `Old title` state_text = `reference lost` )
                          ( catalog = `C2` title = `App` consistent = abap_true desktop = abap_true ) ).
      WHEN `GUI`.
        result = VALUE #( ( catalog = `C3` intent = `G-run` title = `Table` app_type = zif_accx_fiori_repo=>co_app_type-gui
                            target = `SE16` consistent = abap_true ) ).
      WHEN `MANY`.
        DO 7 TIMES.
          APPEND VALUE #( catalog = `C4` intent = |M-{ sy-index }| title = |Many { sy-index }| consistent = abap_true
                          app_type = zif_accx_fiori_repo=>co_app_type-wda target = |ZWDA{ sy-index }| ) TO result.
        ENDDO.
    ENDCASE.
  ENDMETHOD.
  METHOD zif_accx_fiori_repo~get_catalog_roles.
    DATA(all) = VALUE zif_accx_fiori_repo=>ty_role_catalogs( ( role = 'R_A' catalog = `C1` )
                                                             ( role = 'R_B' catalog = `C2` )
                                                             ( role = 'R_HIDDEN' catalog = `C2` )
                                                             ( role = 'R_A' catalog = `C4` ) ).
    LOOP AT all INTO DATA(entry).
      IF line_exists( catalogs[ table_line = entry-catalog ] ).
        APPEND entry TO result.
      ENDIF.
    ENDLOOP.
  ENDMETHOD.
  METHOD zif_accx_fiori_repo~get_app_services.
    result = VALUE #( ( name = `/Z/SRV` version = `0001` odata_version = `2.0` active = abap_true
                        hashes = VALUE #( ( object = `IWSG` hash = 'H1' obj_name = `/Z/SRV_0001` )
                                          ( object = `IWSV` hash = 'H2' obj_name = `/Z/SRV 0001` ) ) )
                      ( name = `/Z/OFF` version = `0001` odata_version = `2.0` active = abap_false )
                      ( name = `Z_V4` version = `0001` odata_version = `4.0` active = abap_undefined
                        hashes = VALUE #( ( object = `G4BA` hash = 'H4' obj_name = `Z_GROUP` ) ) ) ).
  ENDMETHOD.
ENDCLASS.

CLASS ltd_role_repo DEFINITION FINAL FOR TESTING.
  PUBLIC SECTION.
    INTERFACES zif_accx_role_repo PARTIALLY IMPLEMENTED.
ENDCLASS.

CLASS ltd_role_repo IMPLEMENTATION.
  METHOD zif_accx_role_repo~count_assigned_users.
    result = VALUE #( ( role = 'R_A' users = 3 ) ( role = 'R_B' users = 5 ) ).
  ENDMETHOD.
ENDCLASS.

CLASS ltd_evaluator DEFINITION FINAL FOR TESTING.
  PUBLIC SECTION.
    INTERFACES zif_accx_auth_evaluator PARTIALLY IMPLEMENTED.
ENDCLASS.

CLASS ltd_evaluator IMPLEMENTATION.
  METHOD zif_accx_auth_evaluator~get_transaction_checks.
    result = VALUE #( ( object = 'S_TCODE' fields = VALUE #( ( field = 'TCD' value = tcode ) ) reason = `start` ) ).
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
    result = xsdbool( role <> 'R_HIDDEN' ).
  ENDMETHOD.
  METHOD zif_accx_caller_guard~can_display_profile.
    result = abap_true.
  ENDMETHOD.
  METHOD zif_accx_caller_guard~can_display_authorization.
    result = abap_true.
  ENDMETHOD.
ENDCLASS.

CLASS ltc_find_fiori_app DEFINITION FINAL FOR TESTING
  DURATION SHORT RISK LEVEL HARMLESS.

  PRIVATE SECTION.
    DATA cut TYPE REF TO zif_accx_tool.
    DATA ctx TYPE REF TO zif_accx_context.

    METHODS setup.
    METHODS teardown.
    METHODS run
      IMPORTING !query   TYPE string
      EXPORTING !result  TYPE zif_accx_types=>ty_result
                !payload TYPE zcl_accx_t_find_fiori_app=>ty_payload
      RAISING   zcx_accx_error.

    METHODS ui5_app_merged_over_catalogs FOR TESTING RAISING zcx_accx_error.
    METHODS gui_app_without_role        FOR TESTING RAISING zcx_accx_error.
    METHODS details_for_first_apps      FOR TESTING RAISING zcx_accx_error.
    METHODS nothing_found_and_invalid   FOR TESTING RAISING zcx_accx_error.
ENDCLASS.

CLASS ltc_find_fiori_app IMPLEMENTATION.

  METHOD setup.
    zcl_accx_domain_factory=>inject( fiori_repo     = NEW ltd_fiori( )
                                     role_repo      = NEW ltd_role_repo( )
                                     auth_evaluator = NEW ltd_evaluator( ) ).
    cut = NEW zcl_accx_t_find_fiori_app( ).
    ctx = NEW zcl_accx_context( profile  = `test/unit`
                                max_rows = 50
                                guard    = NEW ltd_guard( )
                                privacy  = NEW zcl_accx_privacy_none( ) ).
  ENDMETHOD.

  METHOD teardown.
    zcl_accx_domain_factory=>reset( ).
  ENDMETHOD.

  METHOD run.
    FIELD-SYMBOLS <payload> TYPE zcl_accx_t_find_fiori_app=>ty_payload.
    DATA(args) = NEW zcl_accx_args_map( ).
    args->set( name = `query` value = query ).
    result = cut->execute( args = args ctx = ctx ).
    cut->render_summary( EXPORTING ctx = ctx CHANGING result = result ).
    ASSIGN result-data->* TO <payload>.
    payload = <payload>.
  ENDMETHOD.

  METHOD ui5_app_merged_over_catalogs.
    run( EXPORTING query = `F1` IMPORTING result = DATA(result) payload = DATA(payload) ).

    cl_abap_unit_assert=>assert_equals( exp = 1 act = lines( payload-apps ) ).
    DATA(app) = payload-apps[ 1 ].
    " the consistent target mapping represents the app
    cl_abap_unit_assert=>assert_equals( exp = `App` act = app-title ).
    cl_abap_unit_assert=>assert_true( app-consistent ).
    cl_abap_unit_assert=>assert_equals( exp = 2 act = lines( app-catalogs ) ).
    cl_abap_unit_assert=>assert_equals( exp = `reference lost` act = app-catalogs[ catalog = `C1` ]-state_text ).

    cl_abap_unit_assert=>assert_equals( exp = `R_B` act = app-roles[ 1 ]-role ).
    cl_abap_unit_assert=>assert_equals( exp = 5 act = app-roles[ 1 ]-assigned_users ).
    cl_abap_unit_assert=>assert_equals( exp = `R_A` act = app-roles[ 2 ]-role ).
    cl_abap_unit_assert=>assert_equals( exp = 1 act = app-hidden_roles ).
    cl_abap_unit_assert=>assert_equals( exp = 1 act = result-hidden_by_authorization ).

    cl_abap_unit_assert=>assert_equals( exp = 3 act = lines( app-services ) ).
    cl_abap_unit_assert=>assert_equals( exp = `S_SERVICE SRV_NAME=H1, SRV_TYPE=HT (IWSG /Z/SRV_0001)` act = app-services[ 1 ]-checks[ 1 ] ).
    cl_abap_unit_assert=>assert_equals( exp = `S_START AUTHPGMID=R3TR, AUTHOBJTYP=G4BA, AUTHOBJNAM=Z_GROUP` act = app-services[ 3 ]-checks[ 1 ] ).
    cl_abap_unit_assert=>assert_char_cp( exp = `OData service /Z/OFF*not activated*` act = result-next_steps[ 1 ] ).
    cl_abap_unit_assert=>assert_char_cp( exp = `*diagnose_fiori_app_access with app = A-ui5*` act = result-next_steps[ 2 ] ).
    cl_abap_unit_assert=>assert_char_cp( exp = `*R_B (5 users), R_A (3 users); 1 hidden*` act = result-summary ).
    cl_abap_unit_assert=>assert_char_cp( exp = `*/Z/OFF (version 0001) **not active**: no S_SERVICE value found*` act = result-summary ).
  ENDMETHOD.

  METHOD gui_app_without_role.
    run( EXPORTING query = `GUI` IMPORTING result = DATA(result) payload = DATA(payload) ).
    cl_abap_unit_assert=>assert_equals( exp = VALUE string_table( ( `S_TCODE TCD=SE16` ) )
                                        act = payload-apps[ 1 ]-start_authorization ).
    cl_abap_unit_assert=>assert_initial( payload-apps[ 1 ]-roles ).
    cl_abap_unit_assert=>assert_char_cp( exp = `No role contains a catalog of Table (C3)*draft_role_change*` act = result-next_steps[ 1 ] ).
  ENDMETHOD.

  METHOD details_for_first_apps.
    run( EXPORTING query = `MANY` IMPORTING result = DATA(result) payload = DATA(payload) ).
    cl_abap_unit_assert=>assert_equals( exp = 7 act = result-total_count ).
    cl_abap_unit_assert=>assert_true( payload-apps[ 5 ]-details ).
    cl_abap_unit_assert=>assert_false( payload-apps[ 6 ]-details ).
    cl_abap_unit_assert=>assert_equals( exp = `S_START AUTHPGMID=R3TR, AUTHOBJTYP=WDYA, AUTHOBJNAM=ZWDA1`
                                        act = payload-apps[ 1 ]-start_authorization[ 1 ] ).
    cl_abap_unit_assert=>assert_char_cp( exp = `7 apps match*` act = result-next_steps[ 1 ] ).
    " no per-app hint for several results
    cl_abap_unit_assert=>assert_equals( exp = 1 act = lines( result-next_steps ) ).
  ENDMETHOD.

  METHOD nothing_found_and_invalid.
    run( EXPORTING query = `NONE` IMPORTING result = DATA(result) payload = DATA(payload) ).
    cl_abap_unit_assert=>assert_initial( payload-apps ).
    cl_abap_unit_assert=>assert_char_cp( exp = `No Fiori app matches*` act = result-summary ).
    TRY.
        run( `  ` ).
        cl_abap_unit_assert=>fail( `invalid expected` ).
      CATCH zcx_accx_error INTO DATA(error).
        cl_abap_unit_assert=>assert_equals( exp = zif_accx_types=>co_status-invalid act = error->status ).
    ENDTRY.
  ENDMETHOD.

ENDCLASS.
