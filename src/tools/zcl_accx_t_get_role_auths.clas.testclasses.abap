"! ZR: S_TABU_DIS standard with open field, S_TCODE maintained, F_BKPF_BUK manual with org level $BUKRS,
"! S_SECRET (hidden object), S_DEVELOP inactive; ZD derived from ZR; ZC composite of ZR
CLASS ltd_role_repo DEFINITION FINAL FOR TESTING.
  PUBLIC SECTION.
    INTERFACES zif_accx_role_repo PARTIALLY IMPLEMENTED.
ENDCLASS.

CLASS ltd_role_repo IMPLEMENTATION.
  METHOD zif_accx_role_repo~exists.
    result = xsdbool( role = 'ZR' OR role = 'ZD' OR role = 'ZC' OR role = 'ZSECRET' ).
  ENDMETHOD.
  METHOD zif_accx_role_repo~get_role_info.
    result = VALUE #( role = role ).
    CASE role.
      WHEN 'ZD'.
        result-derived_from = 'ZR'.
      WHEN 'ZC'.
        result-composite = abap_true.
        result-children  = VALUE #( ( `ZR` ) ).
    ENDCASE.
  ENDMETHOD.
  METHOD zif_accx_role_repo~get_authorizations.
    result = VALUE #(
      ( object = 'S_TABU_DIS' auth = 'A1' text = `Table display` status = 'S'
        values = VALUE #( ( object = 'S_TABU_DIS' auth = 'A1' field = 'ACTVT' low = '03' )
                          ( object = 'S_TABU_DIS' auth = 'A1' field = 'DICBERCLS' ) ) )
      ( object = 'S_TCODE' auth = 'A2' status = 'G'
        values = VALUE #( ( object = 'S_TCODE' auth = 'A2' field = 'TCD' low = 'SE16' )
                          ( object = 'S_TCODE' auth = 'A2' field = 'TCD' low = 'SM30' high = 'SM37' ) ) )
      ( object = 'F_BKPF_BUK' auth = 'A3' status = 'U'
        values = VALUE #( ( object = 'F_BKPF_BUK' auth = 'A3' field = 'ACTVT' low = '03' )
                          ( object = 'F_BKPF_BUK' auth = 'A3' field = 'BUKRS' low = '$BUKRS' ) ) )
      ( object = 'S_SECRET' auth = 'A4' status = 'S'
        values = VALUE #( ( object = 'S_SECRET' auth = 'A4' field = 'ACTVT' low = '*' ) ) )
      ( object = 'S_DEVELOP' auth = 'A5' status = 'M' inactive = abap_true
        values = VALUE #( ( object = 'S_DEVELOP' auth = 'A5' field = 'ACTVT' low = '02' ) ) ) ).
    IF object IS NOT INITIAL.
      DELETE result WHERE object <> object.
    ENDIF.
  ENDMETHOD.
ENDCLASS.

"! Hides role ZSECRET and object S_SECRET
CLASS ltd_guard DEFINITION FINAL FOR TESTING.
  PUBLIC SECTION.
    INTERFACES zif_accx_caller_guard.
ENDCLASS.

CLASS ltd_guard IMPLEMENTATION.
  METHOD zif_accx_caller_guard~can_display_user.
    result = abap_true.
  ENDMETHOD.
  METHOD zif_accx_caller_guard~can_display_role.
    result = xsdbool( role <> 'ZSECRET' ).
  ENDMETHOD.
  METHOD zif_accx_caller_guard~can_display_profile.
    result = abap_true.
  ENDMETHOD.
  METHOD zif_accx_caller_guard~can_display_authorization.
    result = xsdbool( object <> 'S_SECRET' ).
  ENDMETHOD.
ENDCLASS.

CLASS ltc_get_role_auths DEFINITION FINAL FOR TESTING
  DURATION SHORT RISK LEVEL HARMLESS.

  PRIVATE SECTION.
    DATA cut TYPE REF TO zif_accx_tool.

    METHODS setup.
    METHODS teardown.
    METHODS run
      IMPORTING !role             TYPE string
                !object           TYPE string OPTIONAL
                !include_inactive TYPE abap_bool DEFAULT abap_false
                !max_rows         TYPE i DEFAULT 50
      EXPORTING !result           TYPE zif_accx_types=>ty_result
                !payload          TYPE zcl_accx_t_get_role_auths=>ty_payload
      RAISING   zcx_accx_error.

    METHODS status_values_and_findings FOR TESTING RAISING zcx_accx_error.
    METHODS object_inactive_and_limit  FOR TESTING RAISING zcx_accx_error.
    METHODS derived_role               FOR TESTING RAISING zcx_accx_error.
    METHODS refusals                   FOR TESTING.
ENDCLASS.

CLASS ltc_get_role_auths IMPLEMENTATION.

  METHOD setup.
    zcl_accx_domain_factory=>inject( role_repo = NEW ltd_role_repo( ) ).
    cut = NEW zcl_accx_t_get_role_auths( ).
  ENDMETHOD.

  METHOD teardown.
    zcl_accx_domain_factory=>reset( ).
  ENDMETHOD.

  METHOD run.
    FIELD-SYMBOLS <payload> TYPE zcl_accx_t_get_role_auths=>ty_payload.
    DATA(ctx) = NEW zcl_accx_context( profile  = `test/unit`
                                      max_rows = max_rows
                                      guard    = NEW ltd_guard( )
                                      privacy  = NEW zcl_accx_privacy_none( ) ).
    DATA(args) = NEW zcl_accx_args_map( ).
    args->set( name = `role` value = role ).
    IF object IS NOT INITIAL.
      args->set( name = `object` value = object ).
    ENDIF.
    IF include_inactive = abap_true.
      args->set( name = `include_inactive` value = `true` ).
    ENDIF.
    result = cut->execute( args = args ctx = ctx ).
    cut->render_summary( EXPORTING ctx = ctx CHANGING result = result ).
    ASSIGN result-data->* TO <payload>.
    payload = <payload>.
  ENDMETHOD.

  METHOD status_values_and_findings.
    run( EXPORTING role = `zr` IMPORTING result = DATA(result) payload = DATA(payload) ).
    " S_SECRET hidden, S_DEVELOP inactive: counted, not listed
    cl_abap_unit_assert=>assert_equals( exp = 3 act = lines( payload-authorizations ) ).
    cl_abap_unit_assert=>assert_equals( exp = 1 act = result-hidden_by_authorization ).
    cl_abap_unit_assert=>assert_equals( exp = 1 act = payload-standard ).
    cl_abap_unit_assert=>assert_equals( exp = 1 act = payload-maintained ).
    cl_abap_unit_assert=>assert_equals( exp = 1 act = payload-manual ).
    cl_abap_unit_assert=>assert_equals( exp = 1 act = payload-inactive ).
    cl_abap_unit_assert=>assert_equals( exp = VALUE string_table( ( `S_TABU_DIS-DICBERCLS` ) ) act = payload-open_fields ).
    cl_abap_unit_assert=>assert_equals( exp = VALUE string_table( ( `$BUKRS` ) ) act = payload-org_levels ).
    cl_abap_unit_assert=>assert_equals( exp = VALUE string_table( ( `SE16` ) ( `SM30-SM37` ) )
                                        act = payload-authorizations[ object = `S_TCODE` ]-fields[ 1 ]-values ).
    cl_abap_unit_assert=>assert_char_cp( exp = `Role **ZR**: 3 active authorizations (1 standard, 1 maintained, 0 changed, 1 manual), 1 inactive. **1 open fields**. Organizational levels: $BUKRS.*`
                                         act = result-summary ).
    cl_abap_unit_assert=>assert_char_cp( exp = `*- S_TABU_DIS (A1, standard): ACTVT=03; DICBERCLS=(open)*- S_TCODE (A2, maintained): TCD=SE16,SM30-SM37*`
                                         act = result-summary ).
    cl_abap_unit_assert=>assert_char_cp( exp = `*hidden due to missing display authorization*` act = result-summary ).
    cl_abap_unit_assert=>assert_char_cp( exp = `Fill the open fields (1)*` act = result-next_steps[ 1 ] ).
  ENDMETHOD.

  METHOD object_inactive_and_limit.
    run( EXPORTING role = `ZR` object = `s_develop` include_inactive = abap_true IMPORTING result = DATA(result) payload = DATA(payload) ).
    cl_abap_unit_assert=>assert_equals( exp = 1 act = lines( payload-authorizations ) ).
    cl_abap_unit_assert=>assert_false( payload-authorizations[ 1 ]-active ).
    cl_abap_unit_assert=>assert_equals( exp = `changed` act = payload-authorizations[ 1 ]-status ).
    cl_abap_unit_assert=>assert_char_cp( exp = `*- S_DEVELOP (A5, changed, **inactive**): ACTVT=02*` act = result-summary ).

    run( EXPORTING role = `ZR` object = `S_USER_GRP` IMPORTING result = result ).
    cl_abap_unit_assert=>assert_char_cp( exp = `Role ZR has no authorization for object S_USER_GRP.` act = result-warnings[ 1 ] ).

    run( EXPORTING role = `ZR` max_rows = 2 IMPORTING result = result payload = payload ).
    cl_abap_unit_assert=>assert_true( result-truncated ).
    cl_abap_unit_assert=>assert_equals( exp = 3 act = result-total_count ).
    cl_abap_unit_assert=>assert_char_cp( exp = `*Showing 2 of 3 authorizations*` act = result-summary ).
  ENDMETHOD.

  METHOD derived_role.
    run( EXPORTING role = `ZD` IMPORTING result = DATA(result) ).
    cl_abap_unit_assert=>assert_char_cp( exp = `Role **ZD** (derived from ZR):*` act = result-summary ).
    cl_abap_unit_assert=>assert_char_cp( exp = `The values are maintained in the reference role ZR*` act = result-next_steps[ 2 ] ).
  ENDMETHOD.

  METHOD refusals.
    TRY.
        run( `ZNONE` ).
        cl_abap_unit_assert=>fail( `not_found expected` ).
      CATCH zcx_accx_error INTO DATA(error).
        cl_abap_unit_assert=>assert_equals( exp = zif_accx_types=>co_status-not_found act = error->status ).
    ENDTRY.
    TRY.
        run( `ZSECRET` ).
        cl_abap_unit_assert=>fail( `denied expected` ).
      CATCH zcx_accx_error INTO error.
        cl_abap_unit_assert=>assert_equals( exp = zif_accx_types=>co_status-denied act = error->status ).
    ENDTRY.
    TRY.
        run( role = `ZR` object = `S_SECRET` ).
        cl_abap_unit_assert=>fail( `denied expected` ).
      CATCH zcx_accx_error INTO error.
        cl_abap_unit_assert=>assert_equals( exp = zif_accx_types=>co_status-denied act = error->status ).
    ENDTRY.
    TRY.
        run( `ZC` ).
        cl_abap_unit_assert=>fail( `invalid expected` ).
      CATCH zcx_accx_error INTO error.
        cl_abap_unit_assert=>assert_char_cp( exp = `ZC is a composite role*: ZR.` act = error->message ).
    ENDTRY.
  ENDMETHOD.

ENDCLASS.
