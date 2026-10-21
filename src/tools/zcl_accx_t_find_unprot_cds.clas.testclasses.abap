"! Exposures: ZI_A protected and published; ZI_N without role, published twice (V2, V4); ZI_U without role in an
"! unbound service definition; ZI_CE custom entity, published; ZI_ABS abstract; ZI_GONE not a CDS entity
CLASS ltd_cds DEFINITION FINAL FOR TESTING.
  PUBLIC SECTION.
    INTERFACES zif_accx_cds_access.
    DATA names TYPE zif_accx_cds_access=>ty_names.
    DATA packages TYPE zif_accx_cds_access=>ty_names.
ENDCLASS.

CLASS ltd_cds IMPLEMENTATION.
  METHOD zif_accx_cds_access~get_entities.
    DATA(all) = VALUE zif_accx_cds_access=>ty_entities(
      ( name = `ZI_A` kind = `VIEWENTITY` authorization_check = `CHECK` )
      ( name = `ZI_N` kind = `VIEWENTITY` authorization_check = `NOT_REQUIRED` )
      ( name = `ZI_U` kind = `VIEWENTITY` )
      ( name = `ZI_CE` kind = `CUSTOM` )
      ( name = `ZI_ABS` kind = `ABSTRACT` ) ).
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
    me->names = names.
    me->packages = packages.
    IF NOT CONV zif_accx_cds_access=>ty_name( `ZSD_A` ) IN names.
      RETURN.
    ENDIF.
    result = VALUE #(
      ( entity = `ZI_A` service_definition = `ZSD_A` binding = `ZUI_A` service = `ZUI_A` protocol = `V2` published = abap_true )
      ( entity = `ZI_N` service_definition = `ZSD_A` binding = `ZUI_A` service = `ZUI_A` protocol = `V2` published = abap_true )
      ( entity = `ZI_N` service_definition = `ZSD_A` binding = `ZUI_A_O4` service = `ZUI_A_O4` protocol = `V4` published = abap_true )
      ( entity = `ZI_U` service_definition = `ZSD_U` )
      ( entity = `ZI_CE` service_definition = `ZSD_A` binding = `ZUI_A` service = `ZUI_A` protocol = `V2` published = abap_true )
      ( entity = `ZI_ABS` service_definition = `ZSD_A` binding = `ZUI_A` service = `ZUI_A` protocol = `V2` published = abap_true )
      ( entity = `ZI_GONE` service_definition = `ZSD_U` ) ).
  ENDMETHOD.
ENDCLASS.

CLASS ltc_find_unprot_cds DEFINITION FINAL FOR TESTING
  DURATION SHORT RISK LEVEL HARMLESS.

  PRIVATE SECTION.
    DATA cut TYPE REF TO zif_accx_tool.
    DATA repo TYPE REF TO ltd_cds.

    METHODS setup.
    METHODS teardown.
    METHODS run
      IMPORTING !names             TYPE string_table OPTIONAL
                !package           TYPE string OPTIONAL
                !include_protected TYPE abap_bool DEFAULT abap_false
                !published_only    TYPE abap_bool DEFAULT abap_false
                !max_rows          TYPE i DEFAULT 50
      EXPORTING !result            TYPE zif_accx_types=>ty_result
                !payload           TYPE zcl_accx_t_find_unprot_cds=>ty_payload
      RAISING   zcx_accx_error.

    METHODS default_audit       FOR TESTING RAISING zcx_accx_error.
    METHODS filters_and_options FOR TESTING RAISING zcx_accx_error.
ENDCLASS.

CLASS ltc_find_unprot_cds IMPLEMENTATION.

  METHOD setup.
    repo = NEW ltd_cds( ).
    zcl_accx_domain_factory=>inject( cds_access = repo ).
    cut = NEW zcl_accx_t_find_unprot_cds( ).
  ENDMETHOD.

  METHOD teardown.
    zcl_accx_domain_factory=>reset( ).
  ENDMETHOD.

  METHOD run.
    FIELD-SYMBOLS <payload> TYPE zcl_accx_t_find_unprot_cds=>ty_payload.
    DATA(ctx) = NEW zcl_accx_context( profile  = `test/unit`
                                      max_rows = max_rows
                                      guard    = NEW zcl_accx_caller_guard( )
                                      privacy  = NEW zcl_accx_privacy_none( ) ).
    DATA(args) = NEW zcl_accx_args_map( ).
    IF names IS NOT INITIAL.
      args->set_list( name = `names` values = names ).
    ENDIF.
    IF package IS NOT INITIAL.
      args->set( name = `package` value = package ).
    ENDIF.
    args->set( name = `include_protected` value = include_protected ).
    args->set( name = `published_only` value = published_only ).
    result = cut->execute( args = args ctx = ctx ).
    cut->render_summary( EXPORTING ctx = ctx CHANGING result = result ).
    ASSIGN result-data->* TO <payload>.
    payload = <payload>.
  ENDMETHOD.

  METHOD default_audit.
    run( IMPORTING result = DATA(result) payload = DATA(payload) ).
    cl_abap_unit_assert=>assert_equals( exp = VALUE string_table( ( `Z*` ) ( `Y*` ) ) act = payload-patterns ).
    cl_abap_unit_assert=>assert_equals( exp = VALUE zif_accx_cds_access=>ty_names( ( sign = 'I' option = 'CP' low = 'Z*' )
                                                                                   ( sign = 'I' option = 'CP' low = 'Y*' ) )
                                        act = repo->names ).
    cl_abap_unit_assert=>assert_initial( repo->packages ).
    cl_abap_unit_assert=>assert_equals( exp = 2 act = payload-service_definitions ).
    " ZI_GONE is no CDS entity
    cl_abap_unit_assert=>assert_equals( exp = 5 act = payload-entities_checked ).
    cl_abap_unit_assert=>assert_equals( exp = VALUE zcl_accx_t_find_unprot_cds=>ty_counts(
                                                  ( status = `no_role` entities = 2 ) ( status = `custom` entities = 1 )
                                                  ( status = `protected` entities = 1 ) ( status = `abstract` entities = 1 ) )
                                        act = payload-counts ).
    cl_abap_unit_assert=>assert_equals( exp = 2 act = payload-unprotected ).
    cl_abap_unit_assert=>assert_equals( exp = 1 act = payload-published_unprotected ).
    " unprotected and custom, published first, then by severity
    cl_abap_unit_assert=>assert_equals( exp = VALUE string_table( ( `ZI_N` ) ( `ZI_CE` ) ( `ZI_U` ) )
                                        act = VALUE string_table( FOR e IN payload-entities ( e-entity ) ) ).
    cl_abap_unit_assert=>assert_equals( exp = VALUE string_table( ( `ZUI_A (V2, published)` ) ( `ZUI_A_O4 (V4, published)` ) )
                                        act = payload-entities[ 1 ]-services ).
    cl_abap_unit_assert=>assert_equals( exp = VALUE string_table( ( `ZSD_U (not bound)` ) ) act = payload-entities[ 3 ]-services ).
    cl_abap_unit_assert=>assert_equals( exp = `#NOT_REQUIRED` act = payload-entities[ 1 ]-authorization_check ).
    cl_abap_unit_assert=>assert_char_cp( exp = `5 CDS entities exposed in 2 service definitions (Z*, Y*): **2 without effective access control**, 1 of them in published services.*`
                                         act = result-summary ).
    cl_abap_unit_assert=>assert_char_cp( exp = `*- **ZI_N** (no_role, ##NOT_REQUIRED): ZUI_A (V2, published), ZUI_A_O4 (V4, published)*- **ZI_U** (no_role, not annotated): ZSD_U (not bound)*`
                                         act = result-summary ).
    cl_abap_unit_assert=>assert_char_cp( exp = `1 entities in published services have no effective access control*` act = result-next_steps[ 1 ] ).
    cl_abap_unit_assert=>assert_char_cp( exp = `Custom entities*` act = result-next_steps[ 2 ] ).
    cl_abap_unit_assert=>assert_equals( exp = `get_cds_access_control ZI_N explains the first entity.` act = result-next_steps[ 3 ] ).
  ENDMETHOD.

  METHOD filters_and_options.
    run( EXPORTING names = VALUE #( ( `zsd_a` ) ( ` zsd_a ` ) ) package = `zpkg*` include_protected = abap_true published_only = abap_true
         IMPORTING payload = DATA(payload) ).
    cl_abap_unit_assert=>assert_equals( exp = VALUE zif_accx_cds_access=>ty_names( ( sign = 'I' option = 'EQ' low = 'ZSD_A' ) )
                                        act = repo->names ).
    cl_abap_unit_assert=>assert_equals( exp = VALUE zif_accx_cds_access=>ty_names( ( sign = 'I' option = 'CP' low = 'ZPKG*' ) )
                                        act = repo->packages ).
    " ZI_U is not published; protected ZI_A and abstract ZI_ABS are listed now
    cl_abap_unit_assert=>assert_equals( exp = VALUE string_table( ( `ZI_N` ) ( `ZI_CE` ) ( `ZI_A` ) ( `ZI_ABS` ) )
                                        act = VALUE string_table( FOR e IN payload-entities ( e-entity ) ) ).
    cl_abap_unit_assert=>assert_equals( exp = 1 act = payload-entities[ 3 ]-roles ).

    run( EXPORTING max_rows = 1 IMPORTING result = DATA(result) payload = payload ).
    cl_abap_unit_assert=>assert_equals( exp = 1 act = lines( payload-entities ) ).
    cl_abap_unit_assert=>assert_equals( exp = 3 act = result-total_count ).
    cl_abap_unit_assert=>assert_true( result-truncated ).

    run( EXPORTING names = VALUE #( ( `NONE*` ) ) IMPORTING result = result payload = payload ).
    cl_abap_unit_assert=>assert_initial( payload-entities ).
    cl_abap_unit_assert=>assert_char_cp( exp = `No exposed CDS entities*` act = result-next_steps[ 1 ] ).
  ENDMETHOD.

ENDCLASS.
