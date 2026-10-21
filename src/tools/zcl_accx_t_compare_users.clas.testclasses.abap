"! User group G: ZNEW (R_COMMON, R_ONLY_NEW; R_OLD expired), ZTPL (R_COMMON, R_DERIV until 2026-12-31 derived
"! from R_REF, composite R_COMPOSITE with R_CHILD, hidden R_HIDDEN, profile SAP_ALL assigned directly),
"! P1 (R_COMMON, R_DERIV), P2 (R_COMMON, R_X), PHID (hidden user); ZNOGRP without user group
CLASS ltd_user_repo DEFINITION FINAL FOR TESTING.
  PUBLIC SECTION.
    INTERFACES zif_accx_user_repo PARTIALLY IMPLEMENTED.
ENDCLASS.

CLASS ltd_user_repo IMPLEMENTATION.
  METHOD zif_accx_user_repo~exists.
    result = xsdbool( user = 'ZNEW' OR user = 'ZTPL' OR user = 'P1' OR user = 'P2' OR user = 'PHID' OR user = 'ZNOGRP' ).
  ENDMETHOD.
  METHOD zif_accx_user_repo~get_user.
    result = VALUE #( user = user full_name = |Name { user }| user_type = `Dialog` user_group = COND #( WHEN user <> 'ZNOGRP' THEN `G` ) ).
  ENDMETHOD.
  METHOD zif_accx_user_repo~get_role_assignments.
    CASE user.
      WHEN 'ZNEW'.
        result = VALUE #( ( role = 'R_COMMON' valid_to = '99991231' active = abap_true )
                          ( role = 'R_ONLY_NEW' description = `Only new` valid_to = '99991231' active = abap_true )
                          ( role = 'R_OLD' valid_to = '20200101' active = abap_false ) ).
      WHEN 'ZTPL'.
        result = VALUE #( ( role = 'R_COMMON' valid_to = '99991231' active = abap_true )
                          ( role = 'R_DERIV' valid_to = '20261231' active = abap_true )
                          ( role = 'R_COMPOSITE' valid_to = '99991231' active = abap_true )
                          ( role = 'R_CHILD' valid_to = '99991231' active = abap_true via_composite = abap_true )
                          ( role = 'R_HIDDEN' valid_to = '99991231' active = abap_true ) ).
    ENDCASE.
  ENDMETHOD.
  METHOD zif_accx_user_repo~get_group_members.
    IF user_group = 'G'.
      result = VALUE #( ( user = 'P1' ) ( user = 'P2' ) ( user = 'PHID' ) ( user = 'ZNEW' ) ( user = 'ZTPL' ) ).
    ENDIF.
  ENDMETHOD.
  METHOD zif_accx_user_repo~get_group_assignments.
    IF user_group = 'G'.
      result = VALUE #( ( user = 'P1' role = 'R_COMMON' ) ( user = 'P1' role = 'R_DERIV' )
                        ( user = 'P2' role = 'R_COMMON' ) ( user = 'P2' role = 'R_X' )
                        ( user = 'PHID' role = 'R_DERIV' )
                        ( user = 'ZNEW' role = 'R_COMMON' ) ( user = 'ZNEW' role = 'R_ONLY_NEW' )
                        ( user = 'ZTPL' role = 'R_COMMON' ) ( user = 'ZTPL' role = 'R_DERIV' ) ).
    ENDIF.
  ENDMETHOD.
ENDCLASS.

CLASS ltd_role_repo DEFINITION FINAL FOR TESTING.
  PUBLIC SECTION.
    INTERFACES zif_accx_role_repo PARTIALLY IMPLEMENTED.
ENDCLASS.

CLASS ltd_role_repo IMPLEMENTATION.
  METHOD zif_accx_role_repo~get_role_info.
    result = VALUE #( role = role description = |Text { role }| derived_from = COND #( WHEN role = 'R_DERIV' THEN 'R_REF' ) ).
  ENDMETHOD.
  METHOD zif_accx_role_repo~get_org_fields.
    result = VALUE #( ( `BUKRS` ) ).
  ENDMETHOD.
ENDCLASS.

CLASS ltd_origin DEFINITION FINAL FOR TESTING.
  PUBLIC SECTION.
    INTERFACES zif_accx_access_origin PARTIALLY IMPLEMENTED.
ENDCLASS.

CLASS ltd_origin IMPLEMENTATION.
  METHOD zif_accx_access_origin~get_user_sources.
    CASE user.
      WHEN 'ZNEW'.
        result = VALUE #( ( profile = 'P_COMMON' role = 'R_COMMON' ) ).
      WHEN 'ZTPL'.
        result = VALUE #( ( profile = 'P_COMMON' role = 'R_COMMON' ) ( profile = 'P_DERIV' role = 'R_DERIV' )
                          ( profile = 'P_HIDDEN' role = 'R_HIDDEN' ) ( profile = 'SAP_ALL' ) ).
    ENDCASE.
  ENDMETHOD.
  METHOD zif_accx_access_origin~get_profile_values.
    CASE profile.
      WHEN 'P_COMMON'.
        result = VALUE #( ( object = 'S_TCODE' auth = 'A1' field = 'TCD' low = 'SU01' )
                          ( object = 'F_BKPF_BUK' auth = 'A2' field = 'BUKRS' low = '1000' ) ).
      WHEN 'P_DERIV'.
        result = VALUE #( ( object = 'S_TCODE' auth = 'A3' field = 'TCD' low = 'SE16' )
                          ( object = 'F_BKPF_BUK' auth = 'A4' field = 'BUKRS' low = '2000' ) ).
      WHEN 'P_HIDDEN'.
        result = VALUE #( ( object = 'S_SECRET' auth = 'A5' field = 'ACTVT' low = '*' ) ).
      WHEN 'SAP_ALL'.
        result = VALUE #( ( object = 'S_DEVELOP' auth = 'A6' field = 'ACTVT' low = '*' ) ).
    ENDCASE.
    IF all_objects = abap_false.
      LOOP AT result INTO DATA(value).
        IF NOT line_exists( objects[ table_line = CONV string( value-object ) ] ).
          DELETE result.
        ENDIF.
      ENDLOOP.
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
      result = VALUE #( ( rule = 'SAP_DEV' text = `Development` ) ).
    ENDIF.
  ENDMETHOD.
ENDCLASS.

CLASS ltd_fiori DEFINITION FINAL FOR TESTING.
  PUBLIC SECTION.
    INTERFACES zif_accx_fiori_repo PARTIALLY IMPLEMENTED.
ENDCLASS.

CLASS ltd_fiori IMPLEMENTATION.
  METHOD zif_accx_fiori_repo~get_role_catalogs.
    LOOP AT roles INTO DATA(role).
      CASE role.
        WHEN 'R_COMMON'.
          APPEND VALUE #( role = role catalog = `CAT_C` ) TO result.
        WHEN 'R_REF'.
          APPEND VALUE #( role = role catalog = `CAT_A` ) TO result.
      ENDCASE.
    ENDLOOP.
  ENDMETHOD.
ENDCLASS.

CLASS ltd_evaluator DEFINITION FINAL FOR TESTING.
  PUBLIC SECTION.
    INTERFACES zif_accx_auth_evaluator PARTIALLY IMPLEMENTED.
ENDCLASS.

CLASS ltd_evaluator IMPLEMENTATION.
  METHOD zif_accx_auth_evaluator~object_exists.
    result = xsdbool( object <> 'S_NONE' ).
  ENDMETHOD.
ENDCLASS.

"! Hides user PHID, role R_HIDDEN and object S_SECRET
CLASS ltd_guard DEFINITION FINAL FOR TESTING.
  PUBLIC SECTION.
    INTERFACES zif_accx_caller_guard.
ENDCLASS.

CLASS ltd_guard IMPLEMENTATION.
  METHOD zif_accx_caller_guard~can_display_user.
    result = xsdbool( user <> 'PHID' ).
  ENDMETHOD.
  METHOD zif_accx_caller_guard~can_display_role.
    result = xsdbool( role <> 'R_HIDDEN' ).
  ENDMETHOD.
  METHOD zif_accx_caller_guard~can_display_profile.
    result = abap_true.
  ENDMETHOD.
  METHOD zif_accx_caller_guard~can_display_authorization.
    result = xsdbool( object <> 'S_SECRET' ).
  ENDMETHOD.
ENDCLASS.

CLASS ltc_compare_users DEFINITION FINAL FOR TESTING
  DURATION SHORT RISK LEVEL HARMLESS.

  PRIVATE SECTION.
    DATA cut TYPE REF TO zif_accx_tool.

    METHODS setup.
    METHODS teardown.
    METHODS run
      IMPORTING !user          TYPE string
                !compare_with  TYPE string OPTIONAL
                !peer_group    TYPE string OPTIONAL
                !scope         TYPE string OPTIONAL
                !object        TYPE string OPTIONAL
                !typical_share TYPE i OPTIONAL
      EXPORTING !result        TYPE zif_accx_types=>ty_result
                !payload       TYPE zcl_accx_t_compare_users=>ty_payload
      RAISING   zcx_accx_error.
    METHODS expect_error
      IMPORTING !user         TYPE string
                !compare_with TYPE string OPTIONAL
                !peer_group   TYPE string OPTIONAL
                !scope        TYPE string OPTIONAL
                !status       TYPE string.

    METHODS two_users_all     FOR TESTING RAISING zcx_accx_error.
    METHODS two_users_object  FOR TESTING RAISING zcx_accx_error.
    METHODS peer_group        FOR TESTING RAISING zcx_accx_error.
    METHODS refusals          FOR TESTING.
ENDCLASS.

CLASS ltc_compare_users IMPLEMENTATION.

  METHOD setup.
    zcl_accx_domain_factory=>inject( user_repo      = NEW ltd_user_repo( )
                                     role_repo      = NEW ltd_role_repo( )
                                     access_origin  = NEW ltd_origin( )
                                     critical_rules = NEW ltd_rules( )
                                     fiori_repo     = NEW ltd_fiori( )
                                     auth_evaluator = NEW ltd_evaluator( ) ).
    cut = NEW zcl_accx_t_compare_users( ).
  ENDMETHOD.

  METHOD teardown.
    zcl_accx_domain_factory=>reset( ).
  ENDMETHOD.

  METHOD run.
    FIELD-SYMBOLS <payload> TYPE zcl_accx_t_compare_users=>ty_payload.
    DATA(ctx) = NEW zcl_accx_context( profile  = `test/unit`
                                      max_rows = 50
                                      guard    = NEW ltd_guard( )
                                      privacy  = NEW zcl_accx_privacy_none( ) ).
    DATA(args) = NEW zcl_accx_args_map( ).
    args->set( name = `user` value = user ).
    IF compare_with IS NOT INITIAL.
      args->set( name = `compare_with` value = compare_with ).
    ENDIF.
    IF peer_group IS NOT INITIAL.
      args->set( name = `peer_group` value = peer_group ).
    ENDIF.
    IF scope IS NOT INITIAL.
      args->set( name = `scope` value = scope ).
    ENDIF.
    IF object IS NOT INITIAL.
      args->set( name = `object` value = object ).
    ENDIF.
    IF typical_share IS NOT INITIAL.
      args->set( name = `typical_share` value = |{ typical_share }| ).
    ENDIF.
    result = cut->execute( args = args ctx = ctx ).
    cut->render_summary( EXPORTING ctx = ctx CHANGING result = result ).
    ASSIGN result-data->* TO <payload>.
    payload = <payload>.
  ENDMETHOD.

  METHOD expect_error.
    TRY.
        run( user = user compare_with = compare_with peer_group = peer_group scope = scope ).
        cl_abap_unit_assert=>fail( |{ status } expected| ).
      CATCH zcx_accx_error INTO DATA(error).
        cl_abap_unit_assert=>assert_equals( exp = status act = error->status ).
    ENDTRY.
  ENDMETHOD.

  METHOD two_users_all.
    run( EXPORTING user = `znew` compare_with = `ztpl` scope = `all` IMPORTING result = DATA(result) payload = DATA(payload) ).
    cl_abap_unit_assert=>assert_equals( exp = 2 act = payload-user-roles ).
    cl_abap_unit_assert=>assert_equals( exp = 4 act = payload-other-roles ).
    cl_abap_unit_assert=>assert_equals( exp = 1 act = payload-roles_common ).
    cl_abap_unit_assert=>assert_equals( exp = `R_ONLY_NEW` act = payload-roles_only_user[ 1 ]-role ).
    cl_abap_unit_assert=>assert_equals( exp = 3 act = lines( payload-roles_only_other ) ).
    cl_abap_unit_assert=>assert_true( payload-roles_only_other[ role = `R_CHILD` ]-via_composite ).
    DATA(derived) = payload-roles_only_other[ role = `R_DERIV` ].
    cl_abap_unit_assert=>assert_equals( exp = `R_REF` act = derived-derived_from ).
    cl_abap_unit_assert=>assert_equals( exp = '20261231' act = derived-valid_to ).
    cl_abap_unit_assert=>assert_equals( exp = `assigned until 2026-12-31, derived from R_REF (organizational levels)` act = derived-personal ).
    cl_abap_unit_assert=>assert_initial( payload-roles_only_other[ role = `R_COMPOSITE` ]-personal ).
    " R_HIDDEN and object S_SECRET are left out
    cl_abap_unit_assert=>assert_equals( exp = 1 act = result-hidden_by_authorization ).
    cl_abap_unit_assert=>assert_equals( exp = VALUE string_table( ( `SAP_ALL` ) ) act = payload-profiles-only_b ).
    cl_abap_unit_assert=>assert_equals( exp = 1 act = payload-values-common ).
    cl_abap_unit_assert=>assert_equals( exp = VALUE string_table( ( `S_DEVELOP ACTVT=*` ) ( `S_TCODE TCD=SE16` ) ) act = payload-values-only_b ).
    cl_abap_unit_assert=>assert_initial( payload-values-only_a ).
    " both hold company code 1000 through R_COMMON, only ZTPL also 2000
    cl_abap_unit_assert=>assert_equals( exp = VALUE string_table( ( `F_BKPF_BUK BUKRS=2000` ) ) act = payload-org_values-only_b ).
    cl_abap_unit_assert=>assert_equals( exp = 1 act = payload-org_values-common ).
    cl_abap_unit_assert=>assert_equals( exp = VALUE string_table( ( `SAP_DEV: Development` ) ) act = payload-critical-only_b ).
    cl_abap_unit_assert=>assert_equals( exp = VALUE string_table( ( `CAT_A` ) ) act = payload-catalogs-only_b ).
    cl_abap_unit_assert=>assert_false( payload-identical ).
    cl_abap_unit_assert=>assert_char_cp( exp = `Users **ZNEW** (Name ZNEW, group G, 2 roles) and **ZTPL** (Name ZTPL, group G, 4 roles).*`
                                         act = result-summary ).
    cl_abap_unit_assert=>assert_char_cp( exp = `*only ZTPL: R_CHILD (via composite role), R_COMPOSITE, R_DERIV (personal: assigned until 2026-12-31*`
                                         act = result-summary ).
    cl_abap_unit_assert=>assert_char_cp( exp = `*Organizational level values (personal): 1 in both*only ZTPL: F_BKPF_BUK BUKRS=2000*`
                                         act = result-summary ).
    cl_abap_unit_assert=>assert_char_cp( exp = `To give ZNEW the access of ZTPL, request R_COMPOSITE, R_DERIV via*` act = result-next_steps[ 1 ] ).
    cl_abap_unit_assert=>assert_char_cp( exp = `Do not copy R_DERIV unchecked*` act = result-next_steps[ 2 ] ).
    cl_abap_unit_assert=>assert_char_cp( exp = `ZTPL holds profiles assigned directly (SAP_ALL)*` act = result-next_steps[ 3 ] ).
    cl_abap_unit_assert=>assert_char_cp( exp = `ZTPL holds critical authorizations*` act = result-next_steps[ 4 ] ).
  ENDMETHOD.

  METHOD two_users_object.
    " an object implies scope auth; roles only: no values
    run( EXPORTING user = `ZNEW` compare_with = `ZTPL` object = `s_tcode` IMPORTING result = DATA(result) payload = DATA(payload) ).
    cl_abap_unit_assert=>assert_equals( exp = `auth` act = payload-scope ).
    cl_abap_unit_assert=>assert_equals( exp = VALUE string_table( ( `S_TCODE TCD=SE16` ) ) act = payload-values-only_b ).
    cl_abap_unit_assert=>assert_initial( payload-critical ).
    cl_abap_unit_assert=>assert_char_cp( exp = `*, object S_TCODE only.*` act = result-summary ).

    run( EXPORTING user = `ZNEW` compare_with = `ZTPL` IMPORTING result = result payload = payload ).
    cl_abap_unit_assert=>assert_initial( payload-values ).
    cl_abap_unit_assert=>assert_char_cp( exp = `Use scope auth*` act = result-next_steps[ lines( result-next_steps ) ] ).
  ENDMETHOD.

  METHOD peer_group.
    " own user group by default; PHID hidden
    run( EXPORTING user = `ZNEW` IMPORTING result = DATA(result) payload = DATA(payload) ).
    cl_abap_unit_assert=>assert_equals( exp = `G` act = payload-peer_group ).
    cl_abap_unit_assert=>assert_equals( exp = 3 act = payload-peers ).
    cl_abap_unit_assert=>assert_equals( exp = 1 act = result-hidden_by_authorization ).
    cl_abap_unit_assert=>assert_equals( exp = 1 act = payload-roles_common ).
    cl_abap_unit_assert=>assert_equals( exp = 1 act = lines( payload-typical_missing ) ).
    cl_abap_unit_assert=>assert_equals( exp = VALUE zcl_accx_t_compare_users=>ty_peer_role( role = `R_DERIV` description = `Text R_DERIV` peers = 2 share = 67 )
                                        act = payload-typical_missing[ 1 ] ).
    cl_abap_unit_assert=>assert_equals( exp = VALUE zcl_accx_t_compare_users=>ty_peer_roles( ( role = `R_ONLY_NEW` description = `Only new` ) )
                                        act = payload-unusual ).
    cl_abap_unit_assert=>assert_char_cp( exp = `**ZNEW** (Name ZNEW) compared with the 3 other users of user group **G**: 2 roles today, 1 of them*`
                                         act = result-summary ).
    cl_abap_unit_assert=>assert_char_cp( exp = `*- R_DERIV (Text R_DERIV): 2 of 3 (67%)*- R_ONLY_NEW (Only new): 0 of 3*` act = result-summary ).
    cl_abap_unit_assert=>assert_char_cp( exp = `ZNEW lacks roles most colleagues in G hold (R_DERIV)*` act = result-next_steps[ 1 ] ).
    cl_abap_unit_assert=>assert_char_cp( exp = `Review whether ZNEW still needs R_ONLY_NEW*` act = result-next_steps[ 2 ] ).

    " lower threshold, explicit group, scope other than roles is only warned about
    run( EXPORTING user = `ZNEW` peer_group = `g` typical_share = 30 scope = `auth` IMPORTING result = result payload = payload ).
    cl_abap_unit_assert=>assert_equals( exp = 2 act = lines( payload-typical_missing ) ).
    cl_abap_unit_assert=>assert_equals( exp = `R_X` act = payload-typical_missing[ 2 ]-role ).
    cl_abap_unit_assert=>assert_char_cp( exp = `Against a user group only roles are compared*` act = result-warnings[ 1 ] ).

    run( EXPORTING user = `ZNEW` peer_group = `EMPTY` IMPORTING result = result payload = payload ).
    cl_abap_unit_assert=>assert_equals( exp = 0 act = payload-peers ).
    cl_abap_unit_assert=>assert_char_cp( exp = `User group EMPTY has no other users*` act = result-warnings[ 1 ] ).
  ENDMETHOD.

  METHOD refusals.
    expect_error( user = `ZNONE` status = zif_accx_types=>co_status-not_found ).
    expect_error( user = `ZNEW` compare_with = `PHID` status = zif_accx_types=>co_status-denied ).
    expect_error( user = `ZNEW` compare_with = `ZNEW` status = zif_accx_types=>co_status-invalid ).
    expect_error( user = `ZNEW` compare_with = `ZTPL` peer_group = `G` status = zif_accx_types=>co_status-invalid ).
    expect_error( user = `ZNEW` compare_with = `ZTPL` scope = `everything` status = zif_accx_types=>co_status-invalid ).
    expect_error( user = `ZNOGRP` status = zif_accx_types=>co_status-invalid ).
  ENDMETHOD.

ENDCLASS.
