"! Group G1: U_ADMIN (SAP_ALL assigned directly), U_IDLE (no logon for 200 days), U_NEW (never logged on,
"! initial password), U_GONE (expired, 3 roles), U_GONE2 (expired, no roles), U_LOCK (locked, no roles);
"! group G2: U_OK; group HIDDEN: U_HID. Standard users SAP* (dialog, SUPER, SAP_ALL, not locked) and
"! DDIC (system, SUPER, locked) - or none with sapstar_missing.
CLASS ltd_user_repo DEFINITION FINAL FOR TESTING.
  PUBLIC SECTION.
    INTERFACES zif_accx_user_repo PARTIALLY IMPLEMENTED.
    DATA sapstar_missing TYPE abap_bool.
ENDCLASS.

CLASS ltd_user_repo IMPLEMENTATION.
  METHOD zif_accx_user_repo~get_users.
    DATA(today) = sy-datum.
    DATA(all) = VALUE zif_accx_user_repo=>ty_members(
      ( user = 'U_ADMIN' user_type_code = 'A' user_group = 'G1' last_logon = today - 5 )
      ( user = 'U_GONE'  user_type_code = 'A' user_group = 'G1' valid_to = today - 1 )
      ( user = 'U_GONE2' user_type_code = 'A' user_group = 'G1' valid_to = today - 1 )
      ( user = 'U_HID'   user_type_code = 'A' user_group = 'HIDDEN' )
      ( user = 'U_IDLE'  user_type_code = 'A' user_group = 'G1' last_logon = today - 200 )
      ( user = 'U_LOCK'  user_type_code = 'A' user_group = 'G1' last_logon = today - 300 locked = abap_true )
      ( user = 'U_NEW'   user_type_code = 'A' user_group = 'G1' initial_password = abap_true )
      ( user = 'U_OK'    user_type_code = 'A' user_group = 'G2' last_logon = today ) ).
    result = VALUE #( FOR m IN all WHERE ( user_group IN user_groups ) ( m ) ).
  ENDMETHOD.
  METHOD zif_accx_user_repo~get_role_counts.
    result = VALUE #( ( user = 'U_GONE' roles = 3 ) ( user = 'U_IDLE' roles = 2 ) ( user = 'U_NEW' roles = 1 ) ( user = 'U_OK' roles = 1 ) ).
  ENDMETHOD.
  METHOD zif_accx_user_repo~get_direct_profiles.
    result = VALUE #( ( user = 'U_ADMIN' profile = 'SAP_ALL' ) ).
  ENDMETHOD.
  METHOD zif_accx_user_repo~get_profile_parameter.
    result = COND #( WHEN sapstar_missing = abap_true THEN `0` ELSE `1` ).
  ENDMETHOD.
  METHOD zif_accx_user_repo~exists.
    result = xsdbool( sapstar_missing = abap_false AND ( user = 'SAP*' OR user = 'DDIC' ) ).
  ENDMETHOD.
  METHOD zif_accx_user_repo~get_user.
    CASE user.
      WHEN 'SAP*'.
        result = VALUE #( user = user user_type = `Dialog` user_type_code = 'A' user_group = `SUPER` last_logon = `2026-01-02 10:00:00` ).
      WHEN 'DDIC'.
        result = VALUE #( user = user user_type = `System` user_type_code = 'B' user_group = `SUPER` locked = abap_true ).
    ENDCASE.
  ENDMETHOD.
  METHOD zif_accx_user_repo~get_profile_assignments.
    IF user = 'SAP*'.
      result = VALUE #( ( profile = 'SAP_ALL' ) ).
    ENDIF.
  ENDMETHOD.
ENDCLASS.

"! Hides user group HIDDEN
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
  METHOD zif_accx_caller_guard~can_display_group.
    result = xsdbool( user_group <> 'HIDDEN' ).
  ENDMETHOD.
ENDCLASS.

CLASS ltc_user_hygiene DEFINITION FINAL FOR TESTING
  DURATION SHORT RISK LEVEL HARMLESS.

  PRIVATE SECTION.
    DATA cut TYPE REF TO zif_accx_tool.
    DATA repo TYPE REF TO ltd_user_repo.

    METHODS setup.
    METHODS teardown.
    METHODS run
      IMPORTING !checks   TYPE string_table OPTIONAL
                !group    TYPE string OPTIONAL
                !max_rows TYPE i DEFAULT 50
      EXPORTING !result   TYPE zif_accx_types=>ty_result
                !payload  TYPE zcl_accx_t_user_hygiene=>ty_payload
      RAISING   zcx_accx_error.

    METHODS all_checks      FOR TESTING RAISING zcx_accx_error.
    METHODS selected_checks FOR TESTING RAISING zcx_accx_error.
    METHODS sapstar_missing FOR TESTING RAISING zcx_accx_error.
    METHODS refusals        FOR TESTING.
ENDCLASS.

CLASS ltc_user_hygiene IMPLEMENTATION.

  METHOD setup.
    repo = NEW ltd_user_repo( ).
    zcl_accx_domain_factory=>inject( user_repo = repo ).
    cut = NEW zcl_accx_t_user_hygiene( ).
  ENDMETHOD.

  METHOD teardown.
    zcl_accx_domain_factory=>reset( ).
  ENDMETHOD.

  METHOD run.
    FIELD-SYMBOLS <payload> TYPE zcl_accx_t_user_hygiene=>ty_payload.
    DATA(ctx) = NEW zcl_accx_context( profile  = `test/unit`
                                      max_rows = max_rows
                                      guard    = NEW ltd_guard( )
                                      privacy  = NEW zcl_accx_privacy_none( ) ).
    DATA(args) = NEW zcl_accx_args_map( ).
    IF checks IS NOT INITIAL.
      args->set_list( name = `checks` values = checks ).
    ENDIF.
    IF group IS NOT INITIAL.
      args->set( name = `user_group` value = group ).
    ENDIF.
    result = cut->execute( args = args ctx = ctx ).
    cut->render_summary( EXPORTING ctx = ctx CHANGING result = result ).
    ASSIGN result-data->* TO <payload>.
    payload = <payload>.
  ENDMETHOD.

  METHOD all_checks.
    run( IMPORTING result = DATA(result) payload = DATA(payload) ).
    cl_abap_unit_assert=>assert_equals( exp = `all users` act = payload-scope ).
    cl_abap_unit_assert=>assert_equals( exp = 7 act = payload-users_checked ).
    cl_abap_unit_assert=>assert_equals( exp = 1 act = result-hidden_by_authorization ).
    cl_abap_unit_assert=>assert_equals( exp = VALUE zcl_accx_t_user_hygiene=>ty_counts(
                                                  ( code = `direct_profile` users = 1 ) ( code = `inactive` users = 1 )
                                                  ( code = `never_logged_on` users = 1 ) ( code = `initial_password` users = 1 )
                                                  ( code = `expired` users = 1 ) )
                                        act = payload-counts ).
    " expired without roles, locked and users without roles are no findings of this report
    cl_abap_unit_assert=>assert_equals( exp = VALUE string_table( ( `U_ADMIN` ) ( `U_IDLE` ) ( `U_NEW` ) ( `U_GONE` ) )
                                        act = VALUE string_table( FOR u IN payload-users ( u-user ) ) ).
    DATA(yesterday) = CONV d( sy-datum - 1 ).
    cl_abap_unit_assert=>assert_equals( exp = VALUE string_table( ( |Valid until { yesterday DATE = ISO }. Still holds 3 roles.| ) )
                                        act = payload-users[ user = `U_GONE` ]-findings ).
    cl_abap_unit_assert=>assert_equals( exp = VALUE zcl_accx_t_user_hygiene=>ty_group( user_group = `G1` users = 6 with_findings = 4 )
                                        act = payload-user_groups[ 1 ] ).
    cl_abap_unit_assert=>assert_equals( exp = `1` act = payload-sapstar_parameter ).
    cl_abap_unit_assert=>assert_equals( exp = 5 act = lines( payload-standard_users ) ).
    DATA(sapstar) = payload-standard_users[ user = `SAP*` ].
    cl_abap_unit_assert=>assert_equals( exp = 2 act = lines( sapstar-findings ) ).
    cl_abap_unit_assert=>assert_char_cp( exp = `Has profiles (SAP_ALL)*` act = sapstar-findings[ 2 ] ).
    cl_abap_unit_assert=>assert_initial( payload-standard_users[ user = `DDIC` ]-findings ).
    cl_abap_unit_assert=>assert_false( payload-standard_users[ user = `TMSADM` ]-exists ).
    cl_abap_unit_assert=>assert_char_cp( exp = `User hygiene for all users (7 users checked): **4 users with findings**.*`
                                         act = result-summary ).
    cl_abap_unit_assert=>assert_char_cp( exp = `*User groups with findings: G1 4 of 6.*- **SAP*** (Dialog, not locked, last logon 2026-01-02 10:00:00): Not locked.*- DDIC (System, locked): ok*`
                                         act = result-summary ).
    cl_abap_unit_assert=>assert_char_cp( exp = `*- **U_ADMIN** (Dialog, G1): Profiles assigned directly: SAP_ALL.*`
                                         act = result-summary ).
    cl_abap_unit_assert=>assert_true( xsdbool( line_exists( result-next_steps[ table_line = `This tool cannot see whether standard users still have their default passwords - check that with report RSUSR003.` ] ) ) ).
    cl_abap_unit_assert=>assert_char_cp( exp = `analyze_user_group G1*` act = result-next_steps[ lines( result-next_steps ) ] ).
  ENDMETHOD.

  METHOD selected_checks.
    run( EXPORTING checks = VALUE #( ( `Inactive` ) ( `inactive` ) ) group = `g*`
         IMPORTING result = DATA(result) payload = DATA(payload) ).
    cl_abap_unit_assert=>assert_equals( exp = `user groups G*` act = payload-scope ).
    cl_abap_unit_assert=>assert_equals( exp = VALUE string_table( ( `inactive` ) ) act = payload-checks ).
    cl_abap_unit_assert=>assert_equals( exp = 7 act = payload-users_checked ).
    cl_abap_unit_assert=>assert_equals( exp = VALUE string_table( ( `U_IDLE` ) ) act = VALUE string_table( FOR u IN payload-users ( u-user ) ) ).
    cl_abap_unit_assert=>assert_initial( payload-standard_users ).
    cl_abap_unit_assert=>assert_false( xsdbool( line_exists( result-next_steps[ table_line = `This tool cannot see whether standard users still have their default passwords - check that with report RSUSR003.` ] ) ) ).

    run( EXPORTING group = `G1` max_rows = 2 IMPORTING result = result payload = payload ).
    cl_abap_unit_assert=>assert_equals( exp = 6 act = payload-users_checked ).
    cl_abap_unit_assert=>assert_equals( exp = 2 act = lines( payload-users ) ).
    cl_abap_unit_assert=>assert_equals( exp = 4 act = result-total_count ).
    cl_abap_unit_assert=>assert_true( result-truncated ).
  ENDMETHOD.

  METHOD sapstar_missing.
    repo->sapstar_missing = abap_true.
    run( EXPORTING checks = VALUE #( ( `standard_users` ) ) IMPORTING payload = DATA(payload) ).
    cl_abap_unit_assert=>assert_initial( payload-users ).
    cl_abap_unit_assert=>assert_equals( exp = `0` act = payload-sapstar_parameter ).
    cl_abap_unit_assert=>assert_char_cp( exp = `Does not exist and login/no_automatic_user_sapstar is 0*`
                                         act = payload-standard_users[ user = `SAP*` ]-findings[ 1 ] ).
    cl_abap_unit_assert=>assert_initial( payload-standard_users[ user = `DDIC` ]-findings ).
  ENDMETHOD.

  METHOD refusals.
    TRY.
        run( checks = VALUE #( ( `passwords` ) ) ).
        cl_abap_unit_assert=>fail( `invalid expected` ).
      CATCH zcx_accx_error INTO DATA(error).
        cl_abap_unit_assert=>assert_equals( exp = zif_accx_types=>co_status-invalid act = error->status ).
    ENDTRY.
    TRY.
        run( group = `NONE` ).
        cl_abap_unit_assert=>fail( `not_found expected` ).
      CATCH zcx_accx_error INTO error.
        cl_abap_unit_assert=>assert_equals( exp = zif_accx_types=>co_status-not_found act = error->status ).
    ENDTRY.
    TRY.
        run( group = `HIDDEN` ).
        cl_abap_unit_assert=>fail( `denied expected` ).
      CATCH zcx_accx_error INTO error.
        cl_abap_unit_assert=>assert_equals( exp = zif_accx_types=>co_status-denied act = error->status ).
    ENDTRY.
  ENDMETHOD.

ENDCLASS.
