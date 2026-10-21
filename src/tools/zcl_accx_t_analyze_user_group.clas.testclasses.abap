"! User group G: U_ADMIN (SAP_ALL assigned directly), U_IDLE (no logon for 200 days, hidden role R_SECRET),
"! U_NEW (never logged on, initial password, outlier role R_RARE), U_GONE (expired, no roles), U_LOCK (locked),
"! U_SYS (system user, never logged on), U_HID (hidden); group H only U_HID
CLASS ltd_user_repo DEFINITION FINAL FOR TESTING.
  PUBLIC SECTION.
    INTERFACES zif_accx_user_repo PARTIALLY IMPLEMENTED.
ENDCLASS.

CLASS ltd_user_repo IMPLEMENTATION.
  METHOD zif_accx_user_repo~get_group_members.
    DATA(today) = sy-datum.
    CASE user_group.
      WHEN 'G'.
        result = VALUE #( ( user = 'U_ADMIN' user_type_code = 'A' last_logon = today - 10 )
                          ( user = 'U_GONE'  user_type_code = 'A' valid_to = today - 1 )
                          ( user = 'U_HID'   user_type_code = 'A' )
                          ( user = 'U_IDLE'  user_type_code = 'A' last_logon = today - 200 )
                          ( user = 'U_LOCK'  user_type_code = 'A' last_logon = today - 300 locked = abap_true )
                          ( user = 'U_NEW'   user_type_code = 'A' initial_password = abap_true )
                          ( user = 'U_SYS'   user_type_code = 'B' ) ).
      WHEN 'H'.
        result = VALUE #( ( user = 'U_HID' user_type_code = 'A' ) ).
    ENDCASE.
  ENDMETHOD.
  METHOD zif_accx_user_repo~get_group_assignments.
    IF user_group = 'G'.
      result = VALUE #( ( user = 'U_ADMIN' role = 'R_A' ) ( user = 'U_HID' role = 'R_HIDONLY' )
                        ( user = 'U_IDLE' role = 'R_A' ) ( user = 'U_IDLE' role = 'R_SECRET' )
                        ( user = 'U_LOCK' role = 'R_A' )
                        ( user = 'U_NEW' role = 'R_A' ) ( user = 'U_NEW' role = 'R_RARE' )
                        ( user = 'U_SYS' role = 'R_A' ) ).
    ENDIF.
  ENDMETHOD.
  METHOD zif_accx_user_repo~get_group_direct_profiles.
    IF user_group = 'G'.
      result = VALUE #( ( user = 'U_ADMIN' profile = 'SAP_ALL' ) ).
    ENDIF.
  ENDMETHOD.
ENDCLASS.

"! Hides user U_HID and role R_SECRET
CLASS ltd_guard DEFINITION FINAL FOR TESTING.
  PUBLIC SECTION.
    INTERFACES zif_accx_caller_guard.
ENDCLASS.

CLASS ltd_guard IMPLEMENTATION.
  METHOD zif_accx_caller_guard~can_display_user.
    result = xsdbool( user <> 'U_HID' ).
  ENDMETHOD.
  METHOD zif_accx_caller_guard~can_display_role.
    result = xsdbool( role <> 'R_SECRET' ).
  ENDMETHOD.
  METHOD zif_accx_caller_guard~can_display_profile.
    result = abap_true.
  ENDMETHOD.
  METHOD zif_accx_caller_guard~can_display_authorization.
    result = abap_true.
  ENDMETHOD.
ENDCLASS.

CLASS ltc_analyze_user_group DEFINITION FINAL FOR TESTING
  DURATION SHORT RISK LEVEL HARMLESS.

  PRIVATE SECTION.
    DATA cut TYPE REF TO zif_accx_tool.

    METHODS setup.
    METHODS teardown.
    METHODS run
      IMPORTING !group         TYPE string
                !inactive_days TYPE i OPTIONAL
                !max_rows      TYPE i DEFAULT 50
      EXPORTING !result        TYPE zif_accx_types=>ty_result
                !payload       TYPE zcl_accx_t_analyze_user_group=>ty_payload
      RAISING   zcx_accx_error.

    METHODS findings_and_roles FOR TESTING RAISING zcx_accx_error.
    METHODS limits             FOR TESTING RAISING zcx_accx_error.
    METHODS refusals           FOR TESTING.
ENDCLASS.

CLASS ltc_analyze_user_group IMPLEMENTATION.

  METHOD setup.
    zcl_accx_domain_factory=>inject( user_repo = NEW ltd_user_repo( ) ).
    cut = NEW zcl_accx_t_analyze_user_group( ).
  ENDMETHOD.

  METHOD teardown.
    zcl_accx_domain_factory=>reset( ).
  ENDMETHOD.

  METHOD run.
    FIELD-SYMBOLS <payload> TYPE zcl_accx_t_analyze_user_group=>ty_payload.
    DATA(ctx) = NEW zcl_accx_context( profile  = `test/unit`
                                      max_rows = max_rows
                                      guard    = NEW ltd_guard( )
                                      privacy  = NEW zcl_accx_privacy_none( ) ).
    DATA(args) = NEW zcl_accx_args_map( ).
    args->set( name = `user_group` value = group ).
    IF inactive_days IS NOT INITIAL.
      args->set( name = `inactive_days` value = |{ inactive_days }| ).
    ENDIF.
    result = cut->execute( args = args ctx = ctx ).
    cut->render_summary( EXPORTING ctx = ctx CHANGING result = result ).
    ASSIGN result-data->* TO <payload>.
    payload = <payload>.
  ENDMETHOD.

  METHOD findings_and_roles.
    run( EXPORTING group = `g` IMPORTING result = DATA(result) payload = DATA(payload) ).
    cl_abap_unit_assert=>assert_equals( exp = 6 act = payload-members ).
    " user U_HID and role R_SECRET
    cl_abap_unit_assert=>assert_equals( exp = 2 act = result-hidden_by_authorization ).
    cl_abap_unit_assert=>assert_equals( exp = VALUE zcl_accx_t_analyze_user_group=>ty_counts( ( code = `Dialog` users = 5 ) ( code = `System` users = 1 ) )
                                        act = payload-user_types ).
    cl_abap_unit_assert=>assert_equals( exp = VALUE zcl_accx_t_analyze_user_group=>ty_counts(
                                                  ( code = `direct_profile` users = 1 ) ( code = `inactive` users = 1 )
                                                  ( code = `never_logged_on` users = 1 ) ( code = `initial_password` users = 1 )
                                                  ( code = `no_roles` users = 1 ) ( code = `expired` users = 1 ) ( code = `locked` users = 1 ) )
                                        act = payload-counts ).
    cl_abap_unit_assert=>assert_equals( exp = VALUE string_table( ( `U_ADMIN` ) ( `U_IDLE` ) ( `U_NEW` ) ( `U_GONE` ) ( `U_LOCK` ) )
                                        act = VALUE string_table( FOR u IN payload-users ( u-user ) ) ).
    " an expired user cannot log on: no logon findings, but no roles
    cl_abap_unit_assert=>assert_equals( exp = VALUE string_table( ( `no_roles` ) ( `expired` ) )
                                        act = payload-users[ user = `U_GONE` ]-finding_codes ).
    cl_abap_unit_assert=>assert_equals( exp = 2 act = payload-roles_total ).
    cl_abap_unit_assert=>assert_equals( exp = VALUE zcl_accx_t_analyze_user_group=>ty_role( role = `R_A` users = 5 share = 83 )
                                        act = payload-top_roles[ 1 ] ).
    cl_abap_unit_assert=>assert_equals( exp = VALUE zcl_accx_t_analyze_user_group=>ty_outliers( ( role = `R_RARE` user = `U_NEW` ) )
                                        act = payload-outliers ).
    cl_abap_unit_assert=>assert_char_cp( exp = `User group **G**: 6 users (5 Dialog, 1 System), 2 roles assigned today, **5 users with findings**.*`
                                         act = result-summary ).
    cl_abap_unit_assert=>assert_char_cp( exp = `*- **U_ADMIN** (Dialog): Profiles assigned directly: SAP_ALL.*- **U_IDLE** (Dialog): No logon for 200 days*`
                                         act = result-summary ).
    cl_abap_unit_assert=>assert_char_cp( exp = `*Most frequent roles: R_A (5, 83%), R_RARE (1, 17%)*Outliers** (role held by one member only): R_RARE (U_NEW)*`
                                         act = result-summary ).
    cl_abap_unit_assert=>assert_char_cp( exp = `Replace profiles assigned directly*` act = result-next_steps[ 1 ] ).
    cl_abap_unit_assert=>assert_char_cp( exp = `Lock or delete dialog users*` act = result-next_steps[ 2 ] ).
  ENDMETHOD.

  METHOD limits.
    run( EXPORTING group = `G` inactive_days = 300 max_rows = 2 IMPORTING result = DATA(result) payload = DATA(payload) ).
    cl_abap_unit_assert=>assert_false( xsdbool( line_exists( payload-counts[ code = `inactive` ] ) ) ).
    cl_abap_unit_assert=>assert_equals( exp = 2 act = lines( payload-users ) ).
    cl_abap_unit_assert=>assert_equals( exp = 4 act = result-total_count ).
    cl_abap_unit_assert=>assert_true( result-truncated ).
    cl_abap_unit_assert=>assert_char_cp( exp = `*Lists cut to max_rows (4 users with findings)*` act = result-summary ).
  ENDMETHOD.

  METHOD refusals.
    TRY.
        run( `NONE` ).
        cl_abap_unit_assert=>fail( `not_found expected` ).
      CATCH zcx_accx_error INTO DATA(error).
        cl_abap_unit_assert=>assert_equals( exp = zif_accx_types=>co_status-not_found act = error->status ).
    ENDTRY.
    TRY.
        run( `H` ).
        cl_abap_unit_assert=>fail( `denied expected` ).
      CATCH zcx_accx_error INTO error.
        cl_abap_unit_assert=>assert_equals( exp = zif_accx_types=>co_status-denied act = error->status ).
    ENDTRY.
  ENDMETHOD.

ENDCLASS.
