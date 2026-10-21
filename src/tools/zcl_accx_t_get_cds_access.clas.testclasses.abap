"! ZI_A: protected by ZR_A (F_BKPF_BUK on CompanyCode), published in ZUI_A_O2 and in the unbound ZSD_A2;
"! ZI_N: #NOT_REQUIRED without role, published in ZUI_N_O4; ZI_D: inherits from ZI_A; ZI_CE: custom entity
CLASS ltd_cds DEFINITION FINAL FOR TESTING.
  PUBLIC SECTION.
    INTERFACES zif_accx_cds_access.
ENDCLASS.

CLASS ltd_cds IMPLEMENTATION.
  METHOD zif_accx_cds_access~get_entities.
    DATA(all) = VALUE zif_accx_cds_access=>ty_entities(
      ( name = `ZI_A` ddl_source = `ZI_A` description = `Entity A` package = `ZPKG` kind = `VIEWENTITY` authorization_check = `CHECK` )
      ( name = `ZI_N` ddl_source = `ZI_N` package = `ZPKG` kind = `VIEWENTITY` authorization_check = `NOT_REQUIRED` )
      ( name = `ZI_D` ddl_source = `ZI_D` package = `ZPKG` kind = `PROJ_STD` )
      ( name = `ZI_CE` ddl_source = `ZI_CE` package = `ZPKG` kind = `CUSTOM` ) ).
    LOOP AT all INTO DATA(entity).
      IF CONV zif_accx_cds_access=>ty_name( entity-name ) IN names.
        APPEND entity TO result.
      ENDIF.
    ENDLOOP.
  ENDMETHOD.
  METHOD zif_accx_cds_access~get_roles.
    DATA(all) = VALUE zif_accx_cds_access=>ty_roles(
      ( entity = `ZI_A` role = `ZR_A` dcl = `ZR_A`
        source = |define role ZR_A \{ grant select on ZI_A where ( CompanyCode ) = aspect pfcg_auth( F_BKPF_BUK, BUKRS, ACTVT = '03' );| &&
                 | grant select on ZI_OTHER; \}| )
      ( entity = `ZI_D` role = `ZR_D` dcl = `ZR_D_DCL`
        source = |define role ZR_D \{ grant select on ZI_D where inheriting conditions from entity ZI_A; \}| ) ).
    LOOP AT all INTO DATA(role).
      IF CONV zif_accx_cds_access=>ty_name( role-entity ) IN entities.
        APPEND role TO result.
      ENDIF.
    ENDLOOP.
  ENDMETHOD.
  METHOD zif_accx_cds_access~get_exposures.
    DATA(all) = VALUE zif_accx_cds_access=>ty_exposures(
      ( entity = `ZI_A` service_definition = `ZSD_A2` alias = `A` )
      ( entity = `ZI_A` service_definition = `ZSD_A` alias = `A` binding = `ZUI_A_O2` service = `ZUI_A_O2` service_version = `0001`
        protocol = `V2` published = abap_true )
      ( entity = `ZI_N` service_definition = `ZSD_N` alias = `N` binding = `ZUI_N_O4` service = `ZUI_N_O4` service_version = `0001`
        protocol = `V4` published = abap_true ) ).
    LOOP AT all INTO DATA(exposure).
      IF CONV zif_accx_cds_access=>ty_name( exposure-entity ) IN entities.
        APPEND exposure TO result.
      ENDIF.
    ENDLOOP.
  ENDMETHOD.
  METHOD zif_accx_cds_access~find_exposures.
  ENDMETHOD.
ENDCLASS.

CLASS ltc_get_cds_access DEFINITION FINAL FOR TESTING
  DURATION SHORT RISK LEVEL HARMLESS.

  PRIVATE SECTION.
    DATA cut TYPE REF TO zif_accx_tool.

    METHODS setup.
    METHODS teardown.
    METHODS run
      IMPORTING !entity  TYPE string
      EXPORTING !result  TYPE zif_accx_types=>ty_result
                !payload TYPE zcl_accx_t_get_cds_access=>ty_payload
      RAISING   zcx_accx_error.

    METHODS protected_entity      FOR TESTING RAISING zcx_accx_error.
    METHODS unprotected_published FOR TESTING RAISING zcx_accx_error.
    METHODS inherited_and_custom  FOR TESTING RAISING zcx_accx_error.
    METHODS refusals              FOR TESTING.
ENDCLASS.

CLASS ltc_get_cds_access IMPLEMENTATION.

  METHOD setup.
    zcl_accx_domain_factory=>inject( cds_access = NEW ltd_cds( ) ).
    cut = NEW zcl_accx_t_get_cds_access( ).
  ENDMETHOD.

  METHOD teardown.
    zcl_accx_domain_factory=>reset( ).
  ENDMETHOD.

  METHOD run.
    FIELD-SYMBOLS <payload> TYPE zcl_accx_t_get_cds_access=>ty_payload.
    DATA(ctx) = NEW zcl_accx_context( profile  = `test/unit`
                                      max_rows = 50
                                      guard    = NEW zcl_accx_caller_guard( )
                                      privacy  = NEW zcl_accx_privacy_none( ) ).
    DATA(args) = NEW zcl_accx_args_map( ).
    args->set( name = `cds_entity` value = entity ).
    result = cut->execute( args = args ctx = ctx ).
    cut->render_summary( EXPORTING ctx = ctx CHANGING result = result ).
    ASSIGN result-data->* TO <payload>.
    payload = <payload>.
  ENDMETHOD.

  METHOD protected_entity.
    run( EXPORTING entity = ` zi_a ` IMPORTING result = DATA(result) payload = DATA(payload) ).
    cl_abap_unit_assert=>assert_equals( exp = `#CHECK` act = payload-authorization_check ).
    cl_abap_unit_assert=>assert_equals( exp = `protected` act = payload-status ).
    cl_abap_unit_assert=>assert_true( payload-protected ).
    cl_abap_unit_assert=>assert_equals( exp = VALUE zcl_accx_t_get_cds_access=>ty_roles(
                                                  ( role = `ZR_A` dcl = `ZR_A` conditions = VALUE #( ( `F_BKPF_BUK: CompanyCode = BUKRS (ACTVT = '03')` ) ) ) )
                                        act = payload-roles ).
    cl_abap_unit_assert=>assert_equals( exp = VALUE zcl_accx_t_get_cds_access=>ty_objects(
                                                  ( object = `F_BKPF_BUK` fields = VALUE #( ( `BUKRS` ) ) filters = VALUE #( ( `ACTVT = '03'` ) ) ) )
                                        act = payload-pfcg_objects ).
    " published first
    cl_abap_unit_assert=>assert_equals( exp = VALUE string_table( ( `ZUI_A_O2` ) ( `` ) )
                                        act = VALUE string_table( FOR e IN payload-exposures ( e-binding ) ) ).
    cl_abap_unit_assert=>assert_char_cp( exp = `CDS entity **ZI_A** (Entity A), VIEWENTITY, DDL source ZI_A, package ZPKG. authorizationCheck: ##CHECK.*Protected (protected)*`
                                         act = result-summary ).
    cl_abap_unit_assert=>assert_char_cp( exp = `*- ZSD_A as A, binding ZUI_A_O2 - published V2*- service definition ZSD_A2 (not bound) - not published*`
                                         act = result-summary ).
    cl_abap_unit_assert=>assert_equals( exp = 2 act = lines( result-next_steps ) ).
    cl_abap_unit_assert=>assert_char_cp( exp = `Users see rows only with F_BKPF_BUK*` act = result-next_steps[ 1 ] ).
    cl_abap_unit_assert=>assert_equals( exp = `simulate_cds_access with a user and ZI_A evaluates the conditions for that user.`
                                        act = result-next_steps[ 2 ] ).
    cl_abap_unit_assert=>assert_initial( result-warnings ).
  ENDMETHOD.

  METHOD unprotected_published.
    run( EXPORTING entity = `ZI_N` IMPORTING result = DATA(result) payload = DATA(payload) ).
    cl_abap_unit_assert=>assert_equals( exp = `no_role` act = payload-status ).
    cl_abap_unit_assert=>assert_false( payload-protected ).
    cl_abap_unit_assert=>assert_initial( payload-roles ).
    cl_abap_unit_assert=>assert_char_cp( exp = `*- ZSD_N as N, binding ZUI_N_O4 - published V4*` act = result-summary ).
    cl_abap_unit_assert=>assert_char_cp( exp = `ZI_N is published in service ZUI_N_O4 without effective access control*get_service_access ZUI_N_O4*`
                                         act = result-next_steps[ 1 ] ).
  ENDMETHOD.

  METHOD inherited_and_custom.
    run( EXPORTING entity = `ZI_D` IMPORTING result = DATA(result) payload = DATA(payload) ).
    cl_abap_unit_assert=>assert_equals( exp = `protected` act = payload-status ).
    cl_abap_unit_assert=>assert_equals( exp = `PROJ_STD` act = payload-kind ).
    cl_abap_unit_assert=>assert_initial( payload-authorization_check ).
    cl_abap_unit_assert=>assert_equals( exp = VALUE string_table( ( `ZI_A` ) ) act = payload-inherited_from ).
    cl_abap_unit_assert=>assert_char_cp( exp = `*- ZR_D (DCL ZR_D_DCL): conditions inherited from ZI_A*Not exposed in an OData service.*` act = result-summary ).
    cl_abap_unit_assert=>assert_equals( exp = `get_cds_access_control ZI_A shows the inherited conditions.` act = result-next_steps[ 1 ] ).

    run( EXPORTING entity = `ZI_CE` IMPORTING result = result payload = payload ).
    cl_abap_unit_assert=>assert_equals( exp = `custom` act = payload-status ).
    cl_abap_unit_assert=>assert_equals( exp = `Check the authorization checks in the query implementation class of ZI_CE.` act = result-next_steps[ 1 ] ).
  ENDMETHOD.

  METHOD refusals.
    DATA(cases) = VALUE string_table( ( `invalid: ` ) ( `invalid:ZI_*` ) ( `not_found:ZI_UNKNOWN` ) ).
    LOOP AT cases INTO DATA(case).
      SPLIT case AT `:` INTO DATA(status) DATA(entity).
      TRY.
          run( entity ).
          cl_abap_unit_assert=>fail( |{ status } expected for { entity }| ).
        CATCH zcx_accx_error INTO DATA(error).
          cl_abap_unit_assert=>assert_equals( exp = status act = error->status msg = case ).
      ENDTRY.
    ENDLOOP.
  ENDMETHOD.

ENDCLASS.
