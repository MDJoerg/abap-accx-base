"! Entities: ZI_A protected by role ZR_A (Z_OBJ field F), ZI_N without role (NOT_REQUIRED), ZI_CE custom.
"! Runtime: U_PART sees ZI_A rows with F = 'A', U_NONE none, everybody all of ZI_N.
CLASS ltd_cds DEFINITION FINAL FOR TESTING.
  PUBLIC SECTION.
    INTERFACES zif_accx_cds_access.
    DATA evaluated TYPE string_table.
    DATA counted TYPE string_table.
ENDCLASS.

CLASS ltd_cds IMPLEMENTATION.
  METHOD zif_accx_cds_access~get_entities.
    DATA(all) = VALUE zif_accx_cds_access=>ty_entities(
      ( name = `ZI_A` kind = `VIEWENTITY` authorization_check = `CHECK` description = `Protected` )
      ( name = `ZI_N` kind = `VIEWENTITY` authorization_check = `NOT_REQUIRED` )
      ( name = `ZI_CE` kind = `CUSTOM` ) ).
    LOOP AT all INTO DATA(entity).
      IF CONV zif_accx_cds_access=>ty_name( entity-name ) IN names.
        APPEND entity TO result.
      ENDIF.
    ENDLOOP.
  ENDMETHOD.
  METHOD zif_accx_cds_access~get_roles.
    IF CONV zif_accx_cds_access=>ty_name( `ZI_A` ) IN entities.
      result = VALUE #( ( entity = `ZI_A` role = `ZR_A` dcl = `ZR_A`
                          source = |define role ZR_A \{ grant select on ZI_A where ( X ) = aspect pfcg_auth( Z_OBJ, F ); \}| ) ).
    ENDIF.
  ENDMETHOD.
  METHOD zif_accx_cds_access~get_exposures.
  ENDMETHOD.
  METHOD zif_accx_cds_access~find_exposures.
  ENDMETHOD.
  METHOD zif_accx_cds_access~evaluate.
    APPEND |{ user } { entity }| TO evaluated.
    IF entity = `ZI_N`.
      result-access = zif_accx_cds_access=>co_access-full.
    ELSEIF user = 'U_PART'.
      result-access    = zif_accx_cds_access=>co_access-restricted.
      result-condition = `X = 'A'`.
    ELSE.
      result-access = zif_accx_cds_access=>co_access-none.
    ENDIF.
  ENDMETHOD.
  METHOD zif_accx_cds_access~count_rows.
    APPEND |{ entity } { access } { condition }| TO counted.
    result = VALUE #( visible = 3 total = 10 ).
  ENDMETHOD.
ENDCLASS.

CLASS ltd_user_repo DEFINITION FINAL FOR TESTING.
  PUBLIC SECTION.
    INTERFACES zif_accx_user_repo PARTIALLY IMPLEMENTED.
ENDCLASS.

CLASS ltd_user_repo IMPLEMENTATION.
  METHOD zif_accx_user_repo~exists.
    result = xsdbool( user = 'U_PART' OR user = 'U_NONE' OR user = 'U_LOCK' OR user = 'U_HID' ).
  ENDMETHOD.
  METHOD zif_accx_user_repo~get_user.
    result = VALUE #( user = user locked = xsdbool( user = 'U_LOCK' ) ).
  ENDMETHOD.
ENDCLASS.

CLASS ltd_origin DEFINITION FINAL FOR TESTING.
  PUBLIC SECTION.
    INTERFACES zif_accx_access_origin PARTIALLY IMPLEMENTED.
ENDCLASS.

CLASS ltd_origin IMPLEMENTATION.
  METHOD zif_accx_access_origin~get_user_sources.
    result = SWITCH #( user WHEN 'U_PART' THEN VALUE #( ( profile = 'T-PART' role = 'ZR_PART' ) )
                            ELSE VALUE #( ( profile = 'T-OTHER' role = 'ZR_OTHER' ) ) ).
  ENDMETHOD.
  METHOD zif_accx_access_origin~get_profile_values.
    IF profile = 'T-PART' AND line_exists( objects[ table_line = `Z_OBJ` ] ).
      result = VALUE #( ( object = 'Z_OBJ' auth = 'A1' field = 'F' low = 'B' )
                        ( object = 'Z_OBJ' auth = 'A1' field = 'F' low = 'A' )
                        ( object = 'Z_OBJ' auth = 'A1' field = 'ACTVT' low = '03' ) ).
    ENDIF.
  ENDMETHOD.
ENDCLASS.

"! Hides U_HID; data preview with privileged access only when allowed
CLASS ltd_guard DEFINITION FINAL FOR TESTING.
  PUBLIC SECTION.
    INTERFACES zif_accx_caller_guard.
    DATA preview TYPE abap_bool VALUE abap_true.
ENDCLASS.

CLASS ltd_guard IMPLEMENTATION.
  METHOD zif_accx_caller_guard~can_display_user.
    result = xsdbool( user <> 'U_HID' ).
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
  METHOD zif_accx_caller_guard~can_preview_privileged.
    result = preview.
  ENDMETHOD.
ENDCLASS.

CLASS ltc_simulate_cds DEFINITION FINAL FOR TESTING
  DURATION SHORT RISK LEVEL HARMLESS.

  PRIVATE SECTION.
    DATA cut TYPE REF TO zif_accx_tool.
    DATA cds TYPE REF TO ltd_cds.
    DATA guard TYPE REF TO ltd_guard.

    METHODS setup.
    METHODS teardown.
    METHODS run
      IMPORTING !user       TYPE string
                !entity     TYPE string
                !count_rows TYPE abap_bool DEFAULT abap_false
      EXPORTING !result     TYPE zif_accx_types=>ty_result
                !payload    TYPE zcl_accx_t_simulate_cds=>ty_payload
      RAISING   zcx_accx_error.
    METHODS assert_refused
      IMPORTING !user   TYPE string
                !entity TYPE string
                !status TYPE string.

    METHODS restricted_with_count  FOR TESTING RAISING zcx_accx_error.
    METHODS no_access_missing      FOR TESTING RAISING zcx_accx_error.
    METHODS unprotected_and_custom FOR TESTING RAISING zcx_accx_error.
    METHODS refused                FOR TESTING RAISING zcx_accx_error.
ENDCLASS.

CLASS ltc_simulate_cds IMPLEMENTATION.

  METHOD setup.
    cds = NEW ltd_cds( ).
    guard = NEW ltd_guard( ).
    zcl_accx_domain_factory=>inject( cds_access    = cds
                                     user_repo     = NEW ltd_user_repo( )
                                     access_origin = NEW ltd_origin( ) ).
    cut = NEW zcl_accx_t_simulate_cds( ).
  ENDMETHOD.

  METHOD teardown.
    zcl_accx_domain_factory=>reset( ).
  ENDMETHOD.

  METHOD run.
    FIELD-SYMBOLS <payload> TYPE zcl_accx_t_simulate_cds=>ty_payload.
    DATA(ctx) = NEW zcl_accx_context( profile  = `test/unit`
                                      max_rows = 50
                                      guard    = guard
                                      privacy  = NEW zcl_accx_privacy_none( ) ).
    DATA(args) = NEW zcl_accx_args_map( ).
    args->set( name = `user` value = user ).
    args->set( name = `cds_entity` value = entity ).
    args->set( name = `count_rows` value = count_rows ).
    result = cut->execute( args = args ctx = ctx ).
    cut->render_summary( EXPORTING ctx = ctx CHANGING result = result ).
    ASSIGN result-data->* TO <payload>.
    payload = <payload>.
  ENDMETHOD.

  METHOD assert_refused.
    TRY.
        run( user = user entity = entity ).
        cl_abap_unit_assert=>fail( |{ user } { entity } not refused| ).
      CATCH zcx_accx_error INTO DATA(error).
        cl_abap_unit_assert=>assert_equals( exp = status act = error->status ).
    ENDTRY.
  ENDMETHOD.

  METHOD restricted_with_count.
    run( EXPORTING user = ` u_part ` entity = `zi_a` count_rows = abap_true IMPORTING result = DATA(result) payload = DATA(payload) ).
    cl_abap_unit_assert=>assert_equals( exp = VALUE string_table( ( `U_PART ZI_A` ) ) act = cds->evaluated ).
    cl_abap_unit_assert=>assert_equals( exp = zif_accx_cds_access=>co_access-restricted act = payload-access ).
    cl_abap_unit_assert=>assert_equals( exp = `X = 'A'` act = payload-condition ).
    cl_abap_unit_assert=>assert_equals( exp = `#CHECK` act = payload-authorization_check ).
    cl_abap_unit_assert=>assert_true( payload-protected ).
    cl_abap_unit_assert=>assert_true( payload-user_usable ).
    cl_abap_unit_assert=>assert_equals( exp = VALUE string_table( ( `ZR_A` ) ) act = payload-roles ).
    cl_abap_unit_assert=>assert_equals( exp = 1 act = lines( payload-objects ) ).
    DATA(object) = payload-objects[ 1 ].
    cl_abap_unit_assert=>assert_equals( exp = `Z_OBJ` act = object-object ).
    cl_abap_unit_assert=>assert_equals( exp = VALUE string_table( ( `F` ) ) act = object-dcl_fields ).
    cl_abap_unit_assert=>assert_true( object-granted ).
    cl_abap_unit_assert=>assert_equals( exp = VALUE string_table( ( `ZR_PART` ) ) act = object-sources ).
    cl_abap_unit_assert=>assert_equals( exp = VALUE zcl_accx_t_simulate_cds=>ty_fields( ( field = `ACTVT` values = VALUE #( ( `03` ) ) )
                                                                                       ( field = `F` values = VALUE #( ( `A` ) ( `B` ) ) ) )
                                        act = object-fields ).
    cl_abap_unit_assert=>assert_initial( payload-missing_objects ).
    cl_abap_unit_assert=>assert_equals( exp = VALUE string_table( ( |ZI_A restricted X = 'A'| ) ) act = cds->counted ).
    cl_abap_unit_assert=>assert_true( payload-rows_counted ).
    cl_abap_unit_assert=>assert_equals( exp = 3 act = payload-visible_rows ).
    cl_abap_unit_assert=>assert_equals( exp = 10 act = payload-total_rows ).
    cl_abap_unit_assert=>assert_char_cp( exp = `**U_PART** on CDS entity **ZI_A** (Protected): **restricted**. Only rows matching*`
                                         act = result-summary ).
    cl_abap_unit_assert=>assert_char_cp( exp = `*Rows: 3 of 10 visible.*- Z_OBJ: ACTVT 03; F A, B (from ZR_PART)*` act = result-summary ).
    cl_abap_unit_assert=>assert_equals( exp = `get_user_authorizations U_PART Z_OBJ shows where the values come from.`
                                        act = result-next_steps[ 1 ] ).
    cl_abap_unit_assert=>assert_equals( exp = 2 act = lines( result-next_steps ) ).
    cl_abap_unit_assert=>assert_initial( result-warnings ).
  ENDMETHOD.

  METHOD no_access_missing.
    guard->preview = abap_false.
    run( EXPORTING user = `U_NONE` entity = `ZI_A` count_rows = abap_true IMPORTING result = DATA(result) payload = DATA(payload) ).
    cl_abap_unit_assert=>assert_equals( exp = zif_accx_cds_access=>co_access-none act = payload-access ).
    cl_abap_unit_assert=>assert_false( payload-objects[ 1 ]-granted ).
    cl_abap_unit_assert=>assert_equals( exp = VALUE string_table( ( `Z_OBJ` ) ) act = payload-missing_objects ).
    cl_abap_unit_assert=>assert_equals( exp = `No rows: U_NONE holds no authorization of Z_OBJ.` act = payload-reason ).
    " not allowed to preview: nothing counted, no hint to count
    cl_abap_unit_assert=>assert_initial( cds->counted ).
    cl_abap_unit_assert=>assert_false( payload-rows_counted ).
    cl_abap_unit_assert=>assert_char_cp( exp = `Rows not counted: you are not authorized*` act = result-warnings[ 1 ] ).
    cl_abap_unit_assert=>assert_char_cp( exp = `U_NONE lacks Z_OBJ: find_roles*` act = result-next_steps[ 1 ] ).
    cl_abap_unit_assert=>assert_char_cp( exp = `get_cds_access_control ZI_A*` act = result-next_steps[ 2 ] ).
    cl_abap_unit_assert=>assert_char_cp( exp = `*- Z_OBJ: **not held***` act = result-summary ).

    run( EXPORTING user = `U_LOCK` entity = `ZI_A` IMPORTING result = result payload = payload ).
    cl_abap_unit_assert=>assert_false( payload-user_usable ).
    cl_abap_unit_assert=>assert_char_cp( exp = `U_LOCK is locked*` act = result-warnings[ 1 ] ).
    cl_abap_unit_assert=>assert_char_cp( exp = `count_rows=true*` act = result-next_steps[ 2 ] ).
  ENDMETHOD.

  METHOD unprotected_and_custom.
    run( EXPORTING user = `U_NONE` entity = `ZI_N` count_rows = abap_true IMPORTING result = DATA(result) payload = DATA(payload) ).
    cl_abap_unit_assert=>assert_equals( exp = zif_accx_cds_access=>co_access-full act = payload-access ).
    cl_abap_unit_assert=>assert_false( payload-protected ).
    cl_abap_unit_assert=>assert_equals( exp = `All rows: ZI_N has no effective access control (no_role).` act = payload-reason ).
    cl_abap_unit_assert=>assert_initial( payload-objects ).
    cl_abap_unit_assert=>assert_equals( exp = VALUE string_table( ( `ZI_N full ` ) ) act = cds->counted ).
    cl_abap_unit_assert=>assert_char_cp( exp = `*Rows: 3 of 10 visible.*` act = result-summary ).

    CLEAR cds->evaluated.
    run( EXPORTING user = `U_PART` entity = `ZI_CE` IMPORTING result = result payload = payload ).
    cl_abap_unit_assert=>assert_initial( cds->evaluated ).
    cl_abap_unit_assert=>assert_initial( payload-access ).
    cl_abap_unit_assert=>assert_equals( exp = zcl_accx_dcl_analyzer=>co_status-custom act = payload-status ).
    cl_abap_unit_assert=>assert_char_cp( exp = `Custom entity: *` act = payload-reason ).
    cl_abap_unit_assert=>assert_char_cp( exp = `Custom entities: the query implementation class of ZI_CE*` act = result-next_steps[ 1 ] ).
  ENDMETHOD.

  METHOD refused.
    assert_refused( user = `` entity = `ZI_A` status = zif_accx_types=>co_status-invalid ).
    assert_refused( user = `U_PART` entity = `ZI_*` status = zif_accx_types=>co_status-invalid ).
    assert_refused( user = `U_UNKNOWN` entity = `ZI_A` status = zif_accx_types=>co_status-not_found ).
    assert_refused( user = `U_HID` entity = `ZI_A` status = zif_accx_types=>co_status-denied ).
    assert_refused( user = `U_PART` entity = `ZI_GONE` status = zif_accx_types=>co_status-not_found ).
    cl_abap_unit_assert=>assert_initial( cds->evaluated ).
  ENDMETHOD.

ENDCLASS.
