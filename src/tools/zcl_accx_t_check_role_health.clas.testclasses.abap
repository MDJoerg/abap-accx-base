"! Z* matches ZBAD (profile not generated, open field, 1 user), ZHIDDEN (hidden), ZOK (2 users, no finding),
"! ZPEND (user comparison pending for 2 of 5 users), ZUNUSED (no users, open field)
CLASS ltd_role_repo DEFINITION FINAL FOR TESTING.
  PUBLIC SECTION.
    INTERFACES zif_accx_role_repo PARTIALLY IMPLEMENTED.
ENDCLASS.

CLASS ltd_role_repo IMPLEMENTATION.
  METHOD zif_accx_role_repo~find_by_pattern.
    IF pattern = `Z*`.
      result = VALUE #( ( 'ZBAD' ) ( 'ZHIDDEN' ) ( 'ZOK' ) ( 'ZPEND' ) ( 'ZUNUSED' ) ).
    ENDIF.
    IF lines( result ) > max_count.
      DELETE result FROM max_count + 1.
    ENDIF.
  ENDMETHOD.
  METHOD zif_accx_role_repo~exists.
    result = abap_true.
  ENDMETHOD.
  METHOD zif_accx_role_repo~get_role_info.
    result = VALUE #( role = role object_count = 3 generated = xsdbool( role <> 'ZBAD' ) ).
  ENDMETHOD.
  METHOD zif_accx_role_repo~get_derived_roles ##NEEDED.
  ENDMETHOD.
  METHOD zif_accx_role_repo~get_transactions.
    result = VALUE #( ( `SU01D` ) ).
  ENDMETHOD.
  METHOD zif_accx_role_repo~count_assigned_users.
    LOOP AT VALUE zif_accx_role_repo=>ty_user_counts( ( role = 'ZBAD' users = 1 ) ( role = 'ZOK' users = 2 ) ( role = 'ZPEND' users = 5 ) )
         INTO DATA(count).
      IF line_exists( roles[ table_line = count-role ] ).
        INSERT count INTO TABLE result.
      ENDIF.
    ENDLOOP.
  ENDMETHOD.
  METHOD zif_accx_role_repo~get_maintenance.
    CASE role.
      WHEN 'ZBAD'.
        result-open_fields = VALUE #( ( `S_TABU_DIS-DICBERCLS` ) ).
      WHEN 'ZPEND'.
        result-comparison_pending = 2.
      WHEN 'ZUNUSED'.
        result-open_fields = VALUE #( ( `S_TCODE-TCD` ) ).
    ENDCASE.
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

CLASS ltd_fiori DEFINITION FINAL FOR TESTING.
  PUBLIC SECTION.
    INTERFACES zif_accx_fiori_repo PARTIALLY IMPLEMENTED.
ENDCLASS.

CLASS ltd_fiori IMPLEMENTATION.
  METHOD zif_accx_fiori_repo~get_role_content ##NEEDED.
  ENDMETHOD.
ENDCLASS.

CLASS ltc_check_role_health DEFINITION FINAL FOR TESTING
  DURATION SHORT RISK LEVEL HARMLESS.

  PRIVATE SECTION.
    DATA cut TYPE REF TO zif_accx_tool.

    METHODS setup.
    METHODS teardown.
    METHODS run
      IMPORTING !pattern  TYPE string OPTIONAL
                !max_rows TYPE i DEFAULT 50
      EXPORTING !result   TYPE zif_accx_types=>ty_result
                !payload  TYPE zcl_accx_t_check_role_health=>ty_payload
      RAISING   zcx_accx_error.

    METHODS findings_by_severity FOR TESTING RAISING zcx_accx_error.
    METHODS row_limit            FOR TESTING RAISING zcx_accx_error.
    METHODS no_match             FOR TESTING RAISING zcx_accx_error.
    METHODS invalid_pattern      FOR TESTING.
ENDCLASS.

CLASS ltc_check_role_health IMPLEMENTATION.

  METHOD setup.
    zcl_accx_domain_factory=>inject( role_repo = NEW ltd_role_repo( ) fiori_repo = NEW ltd_fiori( ) ).
    cut = NEW zcl_accx_t_check_role_health( ).
  ENDMETHOD.

  METHOD teardown.
    zcl_accx_domain_factory=>reset( ).
  ENDMETHOD.

  METHOD run.
    FIELD-SYMBOLS <payload> TYPE zcl_accx_t_check_role_health=>ty_payload.
    DATA(ctx) = NEW zcl_accx_context( profile  = `test/unit`
                                      max_rows = max_rows
                                      guard    = NEW ltd_guard( )
                                      privacy  = NEW zcl_accx_privacy_none( ) ).
    DATA(args) = NEW zcl_accx_args_map( ).
    IF pattern IS NOT INITIAL.
      args->set( name = `role_pattern` value = pattern ).
    ENDIF.
    result = cut->execute( args = args ctx = ctx ).
    cut->render_summary( EXPORTING ctx = ctx CHANGING result = result ).
    ASSIGN result-data->* TO <payload>.
    payload = <payload>.
  ENDMETHOD.

  METHOD findings_by_severity.
    " default pattern Z*
    run( IMPORTING result = DATA(result) payload = DATA(payload) ).
    cl_abap_unit_assert=>assert_equals( exp = 4 act = payload-checked ).
    cl_abap_unit_assert=>assert_equals( exp = 1 act = result-hidden_by_authorization ).
    cl_abap_unit_assert=>assert_equals( exp = 3 act = payload-with_findings ).
    cl_abap_unit_assert=>assert_equals( exp = VALUE zcl_accx_t_check_role_health=>ty_counts(
                                                  ( code = `profile_not_generated` roles = 1 )
                                                  ( code = `open_fields` roles = 2 )
                                                  ( code = `user_comparison_pending` roles = 1 ) )
                                        act = payload-counts ).
    " the role whose profile is missing comes before the one with more users
    cl_abap_unit_assert=>assert_equals( exp = `ZBAD` act = payload-roles[ 1 ]-role ).
    cl_abap_unit_assert=>assert_equals( exp = 1 act = payload-roles[ 1 ]-severity ).
    cl_abap_unit_assert=>assert_equals( exp = `ZPEND` act = payload-roles[ 2 ]-role ).
    " a more severe finding of a role nobody holds comes last
    cl_abap_unit_assert=>assert_equals( exp = `ZUNUSED` act = payload-roles[ 3 ]-role ).
    cl_abap_unit_assert=>assert_equals( exp = VALUE string_table( ( `ZUNUSED` ) ) act = payload-unused ).
    cl_abap_unit_assert=>assert_char_cp( exp = `4 roles matching **Z*** checked: **3 with findings**, 1 without users today.*` act = result-summary ).
    cl_abap_unit_assert=>assert_char_cp( exp = `*- **ZBAD** (single, 1 users): 1 open field*Profile not generated*- **ZPEND** (single, 5 users): User comparison pending: 2 of 5*`
                                         act = result-summary ).
    cl_abap_unit_assert=>assert_char_cp( exp = `Use get_role_details with role ZBAD*` act = result-next_steps[ 1 ] ).
    cl_abap_unit_assert=>assert_char_cp( exp = `Run the user comparison (PFUD*` act = result-next_steps[ 2 ] ).
  ENDMETHOD.

  METHOD row_limit.
    run( EXPORTING max_rows = 1 IMPORTING result = DATA(result) payload = DATA(payload) ).
    cl_abap_unit_assert=>assert_equals( exp = 1 act = lines( payload-roles ) ).
    cl_abap_unit_assert=>assert_equals( exp = 3 act = result-total_count ).
    cl_abap_unit_assert=>assert_char_cp( exp = `*Showing 1 of 3 roles with findings*` act = result-summary ).
  ENDMETHOD.

  METHOD no_match.
    run( EXPORTING pattern = `ya*` IMPORTING result = DATA(result) payload = DATA(payload) ).
    cl_abap_unit_assert=>assert_equals( exp = `YA*` act = payload-role_pattern ).
    cl_abap_unit_assert=>assert_equals( exp = 0 act = payload-checked ).
    cl_abap_unit_assert=>assert_char_cp( exp = `0 roles matching **YA*** checked: no consistency findings*` act = result-summary ).
  ENDMETHOD.

  METHOD invalid_pattern.
    TRY.
        run( pattern = `*` ).
        cl_abap_unit_assert=>fail( `invalid expected` ).
      CATCH zcx_accx_error INTO DATA(error).
        cl_abap_unit_assert=>assert_equals( exp = zif_accx_types=>co_status-invalid act = error->status ).
    ENDTRY.
  ENDMETHOD.

ENDCLASS.
