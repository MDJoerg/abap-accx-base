"! U1 (locked: no) holds profile P_R (role ZR, directly), P_C (role ZCHILD via composite ZCOMP), SAP_ALL
"! (profile), P_H (hidden role ZHIDDEN); role ZPEND is assigned today but its profile is missing.
"! U2 is locked.
CLASS ltd_user_repo DEFINITION FINAL FOR TESTING.
  PUBLIC SECTION.
    INTERFACES zif_accx_user_repo PARTIALLY IMPLEMENTED.
ENDCLASS.

CLASS ltd_user_repo IMPLEMENTATION.
  METHOD zif_accx_user_repo~exists.
    result = xsdbool( user = 'U1' OR user = 'U2' ).
  ENDMETHOD.
  METHOD zif_accx_user_repo~get_user.
    result = VALUE #( user = user locked = xsdbool( user = 'U2' ) ).
  ENDMETHOD.
  METHOD zif_accx_user_repo~get_role_assignments.
    IF user = 'U1'.
      result = VALUE #( ( role = 'ZR' active = abap_true ) ( role = 'ZPEND' active = abap_true )
                        ( role = 'ZOLD' active = abap_false ) ( role = 'ZCOMP' active = abap_true ) ).
    ENDIF.
  ENDMETHOD.
ENDCLASS.

CLASS ltd_role_repo DEFINITION FINAL FOR TESTING.
  PUBLIC SECTION.
    INTERFACES zif_accx_role_repo PARTIALLY IMPLEMENTED.
ENDCLASS.

CLASS ltd_role_repo IMPLEMENTATION.
  METHOD zif_accx_role_repo~get_role_info.
    result = VALUE #( role = role generated = abap_true composite = xsdbool( role = 'ZCOMP' ) ).
  ENDMETHOD.
ENDCLASS.

CLASS ltd_origin DEFINITION FINAL FOR TESTING.
  PUBLIC SECTION.
    INTERFACES zif_accx_access_origin PARTIALLY IMPLEMENTED.
ENDCLASS.

CLASS ltd_origin IMPLEMENTATION.
  METHOD zif_accx_access_origin~get_user_sources.
    IF user = 'U1' OR user = 'U2'.
      result = VALUE #( ( profile = 'P_R' role = 'ZR' )
                        ( profile = 'P_C' role = 'ZCHILD' via = `composite role ZCOMP` )
                        ( profile = 'SAP_ALL' )
                        ( profile = 'P_H' role = 'ZHIDDEN' )
                        ( profile = 'P_X' role = 'ZOTHER' ) ).
    ENDIF.
  ENDMETHOD.
  METHOD zif_accx_access_origin~get_profile_values.
    CASE profile.
      WHEN 'P_R'.
        result = VALUE #( ( object = 'S_TABU_NAM' auth = 'A1' field = 'ACTVT' low = '03' )
                          ( object = 'S_TABU_NAM' auth = 'A1' field = 'TABLE' low = 'T000' )
                          ( object = 'S_TABU_NAM' auth = 'A1' field = 'TABLE' low = 'TADIR' high = 'TADIZ' ) ).
      WHEN 'P_C'.
        result = VALUE #( ( object = 'S_TABU_NAM' auth = 'A2' field = 'ACTVT' low = '02' )
                          ( object = 'S_TABU_NAM' auth = 'A2' field = 'TABLE' low = 'T000' ) ).
      WHEN 'SAP_ALL' OR 'P_H'.
        result = VALUE #( ( object = 'S_TABU_NAM' auth = '&_SAP_ALL' field = 'ACTVT' low = '*' )
                          ( object = 'S_TABU_NAM' auth = '&_SAP_ALL' field = 'TABLE' low = '*' ) ).
    ENDCASE.
  ENDMETHOD.
ENDCLASS.

CLASS ltd_evaluator DEFINITION FINAL FOR TESTING.
  PUBLIC SECTION.
    INTERFACES zif_accx_auth_evaluator PARTIALLY IMPLEMENTED.
ENDCLASS.

CLASS ltd_evaluator IMPLEMENTATION.
  METHOD zif_accx_auth_evaluator~object_exists.
    result = xsdbool( object = 'S_TABU_NAM' OR object = 'S_SECRET' ).
  ENDMETHOD.
ENDCLASS.

"! Hides role ZHIDDEN and authorizations of S_SECRET
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
    result = xsdbool( object <> 'S_SECRET' ).
  ENDMETHOD.
ENDCLASS.

CLASS ltc_get_user_auths DEFINITION FINAL FOR TESTING
  DURATION SHORT RISK LEVEL HARMLESS.

  PRIVATE SECTION.
    DATA cut TYPE REF TO zif_accx_tool.
    DATA ctx TYPE REF TO zif_accx_context.

    METHODS setup.
    METHODS teardown.
    METHODS run
      IMPORTING !user    TYPE string
                !object  TYPE string DEFAULT `S_TABU_NAM`
                !field   TYPE string OPTIONAL
      EXPORTING !result  TYPE zif_accx_types=>ty_result
                !payload TYPE zcl_accx_t_get_user_auths=>ty_payload
      RAISING   zcx_accx_error.

    METHODS values_with_origin   FOR TESTING RAISING zcx_accx_error.
    METHODS field_filter         FOR TESTING RAISING zcx_accx_error.
    METHODS locked_user          FOR TESTING RAISING zcx_accx_error.
    METHODS refusals             FOR TESTING.
ENDCLASS.

CLASS ltc_get_user_auths IMPLEMENTATION.

  METHOD setup.
    zcl_accx_domain_factory=>inject( user_repo      = NEW ltd_user_repo( )
                                     role_repo      = NEW ltd_role_repo( )
                                     access_origin  = NEW ltd_origin( )
                                     auth_evaluator = NEW ltd_evaluator( ) ).
    cut = NEW zcl_accx_t_get_user_auths( ).
    ctx = NEW zcl_accx_context( profile  = `test/unit`
                                max_rows = 50
                                guard    = NEW ltd_guard( )
                                privacy  = NEW zcl_accx_privacy_none( ) ).
  ENDMETHOD.

  METHOD teardown.
    zcl_accx_domain_factory=>reset( ).
  ENDMETHOD.

  METHOD run.
    FIELD-SYMBOLS <payload> TYPE zcl_accx_t_get_user_auths=>ty_payload.
    DATA(args) = NEW zcl_accx_args_map( ).
    args->set( name = `user` value = user ).
    args->set( name = `object` value = object ).
    IF field IS NOT INITIAL.
      args->set( name = `field` value = field ).
    ENDIF.
    result = cut->execute( args = args ctx = ctx ).
    cut->render_summary( EXPORTING ctx = ctx CHANGING result = result ).
    ASSIGN result-data->* TO <payload>.
    payload = <payload>.
  ENDMETHOD.

  METHOD values_with_origin.
    run( EXPORTING user = `u1` object = `s_tabu_nam` IMPORTING result = DATA(result) payload = DATA(payload) ).
    " P_R, P_C and SAP_ALL; the hidden role is counted, ZOTHER has no value of the object
    cl_abap_unit_assert=>assert_equals( exp = 3 act = payload-authorizations ).
    cl_abap_unit_assert=>assert_equals( exp = VALUE string_table( ( `ZR` ) ( `ZCHILD` ) ( `SAP_ALL` ) ) act = payload-sources ).
    cl_abap_unit_assert=>assert_equals( exp = 1 act = result-hidden_by_authorization ).
    cl_abap_unit_assert=>assert_equals( exp = 7 act = lines( payload-values ) ).
    DATA(table) = payload-fields[ field = `TABLE` ].
    cl_abap_unit_assert=>assert_true( table-full ).
    cl_abap_unit_assert=>assert_equals( exp = VALUE string_table( ( `*` ) ( `T000` ) ( `TADIR-TADIZ` ) ) act = table-values ).
    cl_abap_unit_assert=>assert_equals( exp = `composite role ZCOMP` act = payload-values[ source = `ZCHILD` ]-via ).
    cl_abap_unit_assert=>assert_equals( exp = `profile` act = payload-values[ source = `SAP_ALL` ]-source_type ).
    " ZPEND is assigned and generated, but its profile is not in the user master; composite and expired roles are not
    cl_abap_unit_assert=>assert_equals( exp = VALUE string_table( ( `ZPEND` ) ) act = payload-comparison_pending ).
    cl_abap_unit_assert=>assert_true( payload-usable ).
    cl_abap_unit_assert=>assert_char_cp( exp = `**U1** holds 3 authorizations for **S_TABU_NAM** from ZR, ZCHILD, SAP_ALL:*` act = result-summary ).
    cl_abap_unit_assert=>assert_char_cp( exp = `*- TABLE: **all values (*)**; T000, TADIR-TADIZ*` act = result-summary ).
    cl_abap_unit_assert=>assert_char_cp( exp = `*Assigned through: ZCHILD via composite role ZCOMP.*` act = result-summary ).
    cl_abap_unit_assert=>assert_char_cp( exp = `User comparison pending for ZPEND*` act = result-warnings[ 1 ] ).
  ENDMETHOD.

  METHOD field_filter.
    run( EXPORTING user = `U1` field = `actvt` IMPORTING payload = DATA(payload) ).
    cl_abap_unit_assert=>assert_equals( exp = 1 act = lines( payload-fields ) ).
    cl_abap_unit_assert=>assert_equals( exp = VALUE string_table( ( `*` ) ( `02` ) ( `03` ) ) act = payload-fields[ 1 ]-values ).
    cl_abap_unit_assert=>assert_equals( exp = 3 act = lines( payload-values ) ).
  ENDMETHOD.

  METHOD locked_user.
    run( EXPORTING user = `U2` IMPORTING result = DATA(result) payload = DATA(payload) ).
    cl_abap_unit_assert=>assert_false( payload-usable ).
    cl_abap_unit_assert=>assert_char_cp( exp = `U2 is locked*` act = result-warnings[ 1 ] ).
  ENDMETHOD.

  METHOD refusals.
    TRY.
        run( user = `NOBODY` ).
        cl_abap_unit_assert=>fail( `not_found expected` ).
      CATCH zcx_accx_error INTO DATA(error).
        cl_abap_unit_assert=>assert_equals( exp = zif_accx_types=>co_status-not_found act = error->status ).
    ENDTRY.
    TRY.
        run( user = `U1` object = `S_NOPE` ).
        cl_abap_unit_assert=>fail( `not_found expected` ).
      CATCH zcx_accx_error INTO error.
        cl_abap_unit_assert=>assert_char_cp( exp = `*S_NOPE does not exist*` act = error->message ).
    ENDTRY.
    TRY.
        run( user = `U1` object = `S_SECRET` ).
        cl_abap_unit_assert=>fail( `denied expected` ).
      CATCH zcx_accx_error INTO error.
        cl_abap_unit_assert=>assert_equals( exp = zif_accx_types=>co_status-denied act = error->status ).
    ENDTRY.
  ENDMETHOD.

ENDCLASS.
