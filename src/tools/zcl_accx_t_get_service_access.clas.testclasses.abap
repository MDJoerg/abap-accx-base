"! /Z/GOOD_SRV: active, alias LOCAL, hashes HG (IWSG) and HV (IWSV); /Z/OFF_SRV: registered, not active,
"! one hash HO; /Z/NEW_SRV: not registered, no hash
CLASS ltd_fiori DEFINITION FINAL FOR TESTING.
  PUBLIC SECTION.
    INTERFACES zif_accx_fiori_repo PARTIALLY IMPLEMENTED.
ENDCLASS.

CLASS ltd_fiori IMPLEMENTATION.
  METHOD zif_accx_fiori_repo~get_service.
    DATA(service) = to_upper( name ).
    result = VALUE #( name = service version = COND #( WHEN version IS INITIAL THEN `0001` ELSE version )
                      odata_version = `2.0` icf_active = abap_true ).
    CASE service.
      WHEN `/Z/GOOD_SRV`.
        result-registered = result-active = abap_true.
        result-aliases = VALUE #( ( `LOCAL` ) ).
        result-hashes  = VALUE #( ( object = `IWSG` hash = 'HG' obj_name = `Z_GOOD_SRV_0001` )
                                  ( object = `IWSV` hash = 'HV' obj_name = `/Z/GOOD_SRV 0001` ) ).
      WHEN `/Z/OFF_SRV`.
        result-registered = abap_true.
        result-hashes = VALUE #( ( object = `IWSV` hash = 'HO' obj_name = `/Z/OFF_SRV 0001` ) ).
      WHEN `/Z/NEW_SRV`.
      WHEN OTHERS.
        CLEAR result.
    ENDCASE.
  ENDMETHOD.
ENDCLASS.

CLASS ltd_proposals DEFINITION FINAL FOR TESTING.
  PUBLIC SECTION.
    INTERFACES zif_accx_proposal_source.
ENDCLASS.

CLASS ltd_proposals IMPLEMENTATION.
  METHOD zif_accx_proposal_source~get_for_transaction ##NEEDED.
  ENDMETHOD.
  METHOD zif_accx_proposal_source~get_for_service.
    IF hash = 'HV'.
      result = VALUE #( objects = VALUE #( ( object = 'S_TABU_DIS' proposed = abap_true ) )
                        values  = VALUE #( ( object = 'S_TABU_DIS' field = 'ACTVT' low = '03' )
                                           ( object = 'S_TABU_DIS' field = 'DICBERCLS' ) ) ).
    ENDIF.
  ENDMETHOD.
ENDCLASS.

"! ZBOTH grants both hashes (3 users), ZFRONT only HG (5 users), ZHIDDEN is hidden
CLASS ltd_role_repo DEFINITION FINAL FOR TESTING.
  PUBLIC SECTION.
    INTERFACES zif_accx_role_repo PARTIALLY IMPLEMENTED.
ENDCLASS.

CLASS ltd_role_repo IMPLEMENTATION.
  METHOD zif_accx_role_repo~find_roles_granting.
    DATA(hash) = check-fields[ field = 'SRV_NAME' ]-value.
    CASE hash.
      WHEN `HG`.
        result = VALUE #( ( 'ZBOTH' ) ( 'ZFRONT' ) ( 'ZHIDDEN' ) ).
      WHEN `HV`.
        result = VALUE #( ( 'ZBOTH' ) ).
    ENDCASE.
  ENDMETHOD.
  METHOD zif_accx_role_repo~count_assigned_users.
    LOOP AT VALUE zif_accx_role_repo=>ty_user_counts( ( role = 'ZBOTH' users = 3 ) ( role = 'ZFRONT' users = 5 ) ) INTO DATA(count).
      IF line_exists( roles[ table_line = count-role ] ).
        INSERT count INTO TABLE result.
      ENDIF.
    ENDLOOP.
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
    result = xsdbool( role <> 'ZHIDDEN' ).
  ENDMETHOD.
  METHOD zif_accx_caller_guard~can_display_profile.
    result = abap_true.
  ENDMETHOD.
  METHOD zif_accx_caller_guard~can_display_authorization.
    result = abap_true.
  ENDMETHOD.
ENDCLASS.

CLASS ltc_get_service_access DEFINITION FINAL FOR TESTING
  DURATION SHORT RISK LEVEL HARMLESS.

  PRIVATE SECTION.
    DATA cut TYPE REF TO zif_accx_tool.
    DATA ctx TYPE REF TO zif_accx_context.

    METHODS setup.
    METHODS teardown.
    METHODS run
      IMPORTING !service TYPE string
      EXPORTING !result  TYPE zif_accx_types=>ty_result
                !payload TYPE zcl_accx_t_get_service_access=>ty_payload
      RAISING   zcx_accx_error.

    METHODS roles_and_proposals FOR TESTING RAISING zcx_accx_error.
    METHODS inactive_service    FOR TESTING RAISING zcx_accx_error.
    METHODS unknown_service     FOR TESTING RAISING zcx_accx_error.
    METHODS invalid_name        FOR TESTING.
ENDCLASS.

CLASS ltc_get_service_access IMPLEMENTATION.

  METHOD setup.
    zcl_accx_domain_factory=>inject( fiori_repo      = NEW ltd_fiori( )
                                     proposal_source = NEW ltd_proposals( )
                                     role_repo       = NEW ltd_role_repo( ) ).
    cut = NEW zcl_accx_t_get_service_access( ).
    ctx = NEW zcl_accx_context( profile  = `test/unit`
                                max_rows = 50
                                guard    = NEW ltd_guard( )
                                privacy  = NEW zcl_accx_privacy_none( ) ).
  ENDMETHOD.

  METHOD teardown.
    zcl_accx_domain_factory=>reset( ).
  ENDMETHOD.

  METHOD run.
    FIELD-SYMBOLS <payload> TYPE zcl_accx_t_get_service_access=>ty_payload.
    DATA(args) = NEW zcl_accx_args_map( ).
    args->set( name = `service` value = service ).
    result = cut->execute( args = args ctx = ctx ).
    cut->render_summary( EXPORTING ctx = ctx CHANGING result = result ).
    ASSIGN result-data->* TO <payload>.
    payload = <payload>.
  ENDMETHOD.

  METHOD roles_and_proposals.
    run( EXPORTING service = `/z/good_srv` IMPORTING result = DATA(result) payload = DATA(payload) ).
    cl_abap_unit_assert=>assert_true( payload-active ).
    cl_abap_unit_assert=>assert_equals( exp = `yes` act = payload-icf_node ).
    cl_abap_unit_assert=>assert_equals( exp = 2 act = lines( payload-hashes ) ).
    cl_abap_unit_assert=>assert_equals( exp = VALUE string_table( ( `S_TABU_DIS ACTVT=03` ) ( `S_TABU_DIS DICBERCLS=(open)` ) )
                                        act = payload-hashes[ hash = `HV` ]-proposals ).
    " most users first; the hidden role is counted
    cl_abap_unit_assert=>assert_equals( exp = 2 act = lines( payload-roles ) ).
    cl_abap_unit_assert=>assert_equals( exp = `ZFRONT` act = payload-roles[ 1 ]-role ).
    cl_abap_unit_assert=>assert_equals( exp = VALUE string_table( ( `HG` ) ( `HV` ) ) act = payload-roles[ 2 ]-hashes ).
    cl_abap_unit_assert=>assert_equals( exp = 1 act = result-hidden_by_authorization ).
    cl_abap_unit_assert=>assert_initial( result-warnings ).
    cl_abap_unit_assert=>assert_char_cp( exp = `OData service **/Z/GOOD_SRV** (version 0001, OData 2.0): registered and active, system alias LOCAL, ICF node yes.*`
                                         act = result-summary ).
    cl_abap_unit_assert=>assert_char_cp( exp = `*- ZFRONT: 5 users (only HG)*- ZBOTH: 3 users*` act = result-summary ).
    cl_abap_unit_assert=>assert_char_cp( exp = `Use find_users with role ZFRONT*` act = result-next_steps[ 1 ] ).
  ENDMETHOD.

  METHOD inactive_service.
    run( EXPORTING service = `/Z/OFF_SRV` IMPORTING result = DATA(result) payload = DATA(payload) ).
    cl_abap_unit_assert=>assert_false( payload-active ).
    cl_abap_unit_assert=>assert_char_cp( exp = `*registered but not active*` act = result-warnings[ 1 ] ).
    cl_abap_unit_assert=>assert_initial( payload-roles ).
    cl_abap_unit_assert=>assert_char_cp( exp = `No role grants the service*SRV_NAME=HO, SRV_TYPE=HT*` act = result-next_steps[ 1 ] ).
  ENDMETHOD.

  METHOD unknown_service.
    run( EXPORTING service = `/Z/NEW_SRV` IMPORTING result = DATA(result) ).
    cl_abap_unit_assert=>assert_char_cp( exp = `*not registered in the gateway*` act = result-warnings[ 1 ] ).
    cl_abap_unit_assert=>assert_char_cp( exp = `No S_SERVICE hash found*` act = result-warnings[ 2 ] ).
    cl_abap_unit_assert=>assert_char_cp( exp = `***not registered***` act = result-summary ).
  ENDMETHOD.

  METHOD invalid_name.
    TRY.
        run( `nonsense` ).
        cl_abap_unit_assert=>fail( `invalid expected` ).
      CATCH zcx_accx_error INTO DATA(error).
        cl_abap_unit_assert=>assert_equals( exp = zif_accx_types=>co_status-invalid act = error->status ).
    ENDTRY.
  ENDMETHOD.

ENDCLASS.
