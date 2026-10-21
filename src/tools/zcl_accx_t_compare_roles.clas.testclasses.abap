"! ZA: SE16 menu, catalog C1, S_TCODE SE16, S_TABU_DIS 03, PLOG $PLVAR (3 users);
"! ZB: derived from ZA, S_TABU_DIS 02 instead of 03, PLVAR 01 (organizational level, 1 user);
"! ZX: menu SE16 and SM37, S_TCODE SE16, S_DEVELOP 02 (critical rule DEV);
"! ZC: composite of ZA and the hidden ZHIDDEN
CLASS ltd_role_repo DEFINITION FINAL FOR TESTING.
  PUBLIC SECTION.
    INTERFACES zif_accx_role_repo PARTIALLY IMPLEMENTED.
ENDCLASS.

CLASS ltd_role_repo IMPLEMENTATION.
  METHOD zif_accx_role_repo~exists.
    result = xsdbool( role = 'ZA' OR role = 'ZB' OR role = 'ZX' OR role = 'ZC' OR role = 'ZHIDDEN' ).
  ENDMETHOD.
  METHOD zif_accx_role_repo~get_role_info.
    result = VALUE #( role = role ).
    CASE role.
      WHEN 'ZA'.
        result-parents = VALUE #( ( `ZC` ) ).
      WHEN 'ZB'.
        result-derived_from = 'ZA'.
      WHEN 'ZC'.
        result-composite = abap_true.
        result-children  = VALUE #( ( `ZA` ) ( `ZHIDDEN` ) ).
    ENDCASE.
  ENDMETHOD.
  METHOD zif_accx_role_repo~get_authorization_values.
    CASE role.
      WHEN 'ZA'.
        result = VALUE #( ( object = 'S_TCODE' auth = 'A1' field = 'TCD' low = 'SE16' )
                          ( object = 'S_TABU_DIS' auth = 'A2' field = 'ACTVT' low = '03' )
                          ( object = 'PLOG' auth = 'A3' field = 'PLVAR' low = '$PLVAR' ) ).
      WHEN 'ZB'.
        result = VALUE #( ( object = 'S_TCODE' auth = 'B1' field = 'TCD' low = 'SE16' )
                          ( object = 'S_TABU_DIS' auth = 'B2' field = 'ACTVT' low = '02' )
                          ( object = 'PLOG' auth = 'B3' field = 'PLVAR' low = '01' ) ).
      WHEN 'ZX'.
        result = VALUE #( ( object = 'S_TCODE' auth = 'X1' field = 'TCD' low = 'SE16' )
                          ( object = 'S_DEVELOP' auth = 'X2' field = 'ACTVT' low = '02' ) ).
      WHEN 'ZHIDDEN'.
        result = VALUE #( ( object = 'S_USER_GRP' auth = 'H1' field = 'ACTVT' low = '02' ) ).
    ENDCASE.
  ENDMETHOD.
  METHOD zif_accx_role_repo~get_transactions.
    CASE role.
      WHEN 'ZA'.
        result = VALUE #( ( `SE16` ) ).
      WHEN 'ZX'.
        result = VALUE #( ( `SE16` ) ( `SM37` ) ).
    ENDCASE.
  ENDMETHOD.
  METHOD zif_accx_role_repo~get_maintenance.
    IF role = 'ZB'.
      result-org_levels = VALUE #( ( level = `$PLVAR` low = `01` ) ).
    ENDIF.
  ENDMETHOD.
  METHOD zif_accx_role_repo~get_org_fields.
    result = VALUE #( ( `PLVAR` ) ).
  ENDMETHOD.
  METHOD zif_accx_role_repo~count_assigned_users.
    LOOP AT VALUE zif_accx_role_repo=>ty_user_counts( ( role = 'ZA' users = 3 ) ( role = 'ZB' users = 1 ) ) INTO DATA(count).
      IF line_exists( roles[ table_line = count-role ] ).
        INSERT count INTO TABLE result.
      ENDIF.
    ENDLOOP.
  ENDMETHOD.
ENDCLASS.

CLASS ltd_fiori DEFINITION FINAL FOR TESTING.
  PUBLIC SECTION.
    INTERFACES zif_accx_fiori_repo PARTIALLY IMPLEMENTED.
ENDCLASS.

CLASS ltd_fiori IMPLEMENTATION.
  METHOD zif_accx_fiori_repo~get_role_content.
    IF line_exists( roles[ table_line = 'ZA' ] ).
      result = VALUE #( ( role = 'ZA' type = zif_accx_fiori_repo=>co_content_type-catalog id = `C1` ) ).
    ENDIF.
  ENDMETHOD.
ENDCLASS.

CLASS ltd_rules DEFINITION FINAL FOR TESTING.
  PUBLIC SECTION.
    INTERFACES zif_accx_critical_rules PARTIALLY IMPLEMENTED.
ENDCLASS.

CLASS ltd_rules IMPLEMENTATION.
  METHOD zif_accx_critical_rules~evaluate.
    IF line_exists( values[ object = 'S_DEVELOP' ] ).
      result = VALUE #( ( rule = 'DEV' text = `Development` level = zif_accx_critical_rules=>co_level-high ) ).
    ENDIF.
  ENDMETHOD.
ENDCLASS.

"! Hides role ZHIDDEN
CLASS ltd_guard DEFINITION FINAL FOR TESTING.
  PUBLIC SECTION.
    INTERFACES zif_accx_caller_guard.
ENDCLASS.

CLASS ltd_guard IMPLEMENTATION.
  METHOD zif_accx_caller_guard~can_display_user.
    result = abap_true.
  ENDMETHOD.
  METHOD zif_accx_caller_guard~can_display_role.
    result = xsdbool( role <> 'ZHIDDEN' ).
  ENDMETHOD.
  METHOD zif_accx_caller_guard~can_display_profile.
    result = abap_true.
  ENDMETHOD.
  METHOD zif_accx_caller_guard~can_display_authorization.
    result = abap_true.
  ENDMETHOD.
ENDCLASS.

CLASS ltc_compare_roles DEFINITION FINAL FOR TESTING
  DURATION SHORT RISK LEVEL HARMLESS.

  PRIVATE SECTION.
    DATA cut TYPE REF TO zif_accx_tool.
    DATA ctx TYPE REF TO zif_accx_context.

    METHODS setup.
    METHODS teardown.
    METHODS run
      IMPORTING !role_a  TYPE string
                !role_b  TYPE string
                !object  TYPE string OPTIONAL
      EXPORTING !result  TYPE zif_accx_types=>ty_result
                !payload TYPE zcl_accx_t_compare_roles=>ty_payload
      RAISING   zcx_accx_error.

    METHODS derived_against_reference FOR TESTING RAISING zcx_accx_error.
    METHODS objects_menu_and_critical FOR TESTING RAISING zcx_accx_error.
    METHODS composite_with_object     FOR TESTING RAISING zcx_accx_error.
    METHODS refusals                  FOR TESTING.
ENDCLASS.

CLASS ltc_compare_roles IMPLEMENTATION.

  METHOD setup.
    zcl_accx_domain_factory=>inject( role_repo      = NEW ltd_role_repo( )
                                     fiori_repo     = NEW ltd_fiori( )
                                     critical_rules = NEW ltd_rules( ) ).
    cut = NEW zcl_accx_t_compare_roles( ).
    ctx = NEW zcl_accx_context( profile  = `test/unit`
                                max_rows = 50
                                guard    = NEW ltd_guard( )
                                privacy  = NEW zcl_accx_privacy_none( ) ).
  ENDMETHOD.

  METHOD teardown.
    zcl_accx_domain_factory=>reset( ).
  ENDMETHOD.

  METHOD run.
    FIELD-SYMBOLS <payload> TYPE zcl_accx_t_compare_roles=>ty_payload.
    DATA(args) = NEW zcl_accx_args_map( ).
    args->set( name = `role_a` value = role_a ).
    args->set( name = `role_b` value = role_b ).
    IF object IS NOT INITIAL.
      args->set( name = `object` value = object ).
    ENDIF.
    result = cut->execute( args = args ctx = ctx ).
    cut->render_summary( EXPORTING ctx = ctx CHANGING result = result ).
    ASSIGN result-data->* TO <payload>.
    payload = <payload>.
  ENDMETHOD.

  METHOD derived_against_reference.
    run( EXPORTING role_a = `za` role_b = `zb` IMPORTING result = DATA(result) payload = DATA(payload) ).
    cl_abap_unit_assert=>assert_equals( exp = `ZB is derived from ZA` act = payload-relation ).
    cl_abap_unit_assert=>assert_equals( exp = `derived` act = payload-role_b-role_type ).
    " the organizational level field PLVAR is compared as organizational level only
    cl_abap_unit_assert=>assert_equals( exp = VALUE string_table( ( `S_TABU_DIS ACTVT=03` ) ) act = payload-values-only_a ).
    cl_abap_unit_assert=>assert_equals( exp = VALUE string_table( ( `S_TABU_DIS ACTVT=02` ) ) act = payload-values-only_b ).
    cl_abap_unit_assert=>assert_equals( exp = 1 act = payload-values-common ).
    cl_abap_unit_assert=>assert_equals( exp = VALUE string_table( ( `$PLVAR=01` ) ) act = payload-org_levels-only_b ).
    " ZB shows the menu and catalogs of its reference role
    cl_abap_unit_assert=>assert_initial( payload-transactions-only_a ).
    cl_abap_unit_assert=>assert_initial( payload-catalogs-only_a ).
    cl_abap_unit_assert=>assert_false( payload-identical ).
    cl_abap_unit_assert=>assert_char_cp( exp = `Roles **ZA** (single, 3 users) and **ZB** (derived, 1 users): ZB is derived from ZA.*`
                                         act = result-summary ).
    cl_abap_unit_assert=>assert_char_cp( exp = `*- Authorization values: 1 in both*- only ZA: S_TABU_DIS ACTVT=03*- only ZB: S_TABU_DIS ACTVT=02*`
                                         act = result-summary ).
    cl_abap_unit_assert=>assert_char_cp( exp = `*- Menu transactions: no differences (1 in both)*` act = result-summary ).
    cl_abap_unit_assert=>assert_char_cp( exp = `ZB is not in sync with its reference role ZA*` act = result-next_steps[ 1 ] ).
  ENDMETHOD.

  METHOD objects_menu_and_critical.
    run( EXPORTING role_a = `ZA` role_b = `ZX` IMPORTING result = DATA(result) payload = DATA(payload) ).
    cl_abap_unit_assert=>assert_initial( payload-relation ).
    cl_abap_unit_assert=>assert_equals( exp = VALUE string_table( ( `PLOG` ) ( `S_TABU_DIS` ) ) act = payload-objects_only_a ).
    cl_abap_unit_assert=>assert_equals( exp = VALUE string_table( ( `S_DEVELOP` ) ) act = payload-objects_only_b ).
    cl_abap_unit_assert=>assert_equals( exp = VALUE string_table( ( `SM37` ) ) act = payload-transactions-only_b ).
    cl_abap_unit_assert=>assert_equals( exp = VALUE string_table( ( `C1` ) ) act = payload-catalogs-only_a ).
    cl_abap_unit_assert=>assert_equals( exp = VALUE string_table( ( `DEV: Development` ) ) act = payload-critical-only_b ).
    cl_abap_unit_assert=>assert_char_cp( exp = `*- **Critical authorizations**: 0 in both*- only ZX: DEV: Development*` act = result-summary ).
    cl_abap_unit_assert=>assert_char_cp( exp = `ZX grants critical authorizations ZA does not*` act = result-next_steps[ 2 ] ).
  ENDMETHOD.

  METHOD composite_with_object.
    run( EXPORTING role_a = `ZC` role_b = `ZA` object = `s_tcode` IMPORTING result = DATA(result) payload = DATA(payload) ).
    cl_abap_unit_assert=>assert_equals( exp = `ZA is part of composite role ZC` act = payload-relation ).
    cl_abap_unit_assert=>assert_true( payload-identical ).
    " ZHIDDEN is left out
    cl_abap_unit_assert=>assert_equals( exp = 1 act = result-hidden_by_authorization ).
    cl_abap_unit_assert=>assert_char_cp( exp = `*, object S_TCODE only. They grant the same authorization values (1).*` act = result-summary ).
  ENDMETHOD.

  METHOD refusals.
    TRY.
        run( role_a = `ZA` role_b = `za` ).
        cl_abap_unit_assert=>fail( `invalid expected` ).
      CATCH zcx_accx_error INTO DATA(error).
        cl_abap_unit_assert=>assert_equals( exp = zif_accx_types=>co_status-invalid act = error->status ).
    ENDTRY.
    TRY.
        run( role_a = `ZA` role_b = `ZNONE` ).
        cl_abap_unit_assert=>fail( `not_found expected` ).
      CATCH zcx_accx_error INTO error.
        cl_abap_unit_assert=>assert_equals( exp = zif_accx_types=>co_status-not_found act = error->status ).
    ENDTRY.
    TRY.
        run( role_a = `ZHIDDEN` role_b = `ZA` ).
        cl_abap_unit_assert=>fail( `denied expected` ).
      CATCH zcx_accx_error INTO error.
        cl_abap_unit_assert=>assert_equals( exp = zif_accx_types=>co_status-denied act = error->status ).
    ENDTRY.
  ENDMETHOD.

ENDCLASS.
